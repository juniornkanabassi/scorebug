// Owns state for both slots, calls MatchEngine, saves through Store, then broadcasts through OverlayServer.
import Foundation
import SwiftUI
import QuartzCore
import ScorebugCore

/// Tiny per-slot values the sidebar row and the menu bar extra actually draw, precomputed in
/// `persistAndBroadcast()` rather than read from the full `Match` (which drags in both squads via
/// `TeamEntry`) so those two Equatable-skippable views never decode more than they show.
struct SlotSummary: Equatable {
    var homeCode = "HOM"
    var awayCode = "AWY"
    var homeScore = 0
    var awayScore = 0
    var visible = true
}

struct LaunchOptions {
    var dataDirectory: URL
    var overlaysDirectory: String?
    var port: Int?
    /// `--import-crests <folder>`: import a crest folder once at launch (the launch-time default import only runs on a first run).
    var importCrests: String?
    /// `--background`: keep the server and menu bar item alive without presenting the main window.
    var background = false
    /// `--screen <name>`: open the window on that display (by its name in System Settings) and do not steal focus.
    /// Agents' test instances use `--screen "Agent Screen"` so nothing lands on Junior's monitors.
    var screenName: String?

    static func parse(_ args: [String]) -> LaunchOptions {
        var opts = LaunchOptions(dataDirectory: Store.defaultDirectory(), overlaysDirectory: nil, port: nil)
        var i = 0
        while i < args.count {
            switch args[i] {
            case "--background": opts.background = true
            case "--data-directory" where i + 1 < args.count: opts.dataDirectory = URL(fileURLWithPath: args[i + 1], isDirectory: true); i += 1
            case "--overlays-directory" where i + 1 < args.count: opts.overlaysDirectory = args[i + 1]; i += 1
            case "--port" where i + 1 < args.count: opts.port = Int(args[i + 1]); i += 1
            case "--import-crests" where i + 1 < args.count: opts.importCrests = args[i + 1]; i += 1
            case "--screen" where i + 1 < args.count: opts.screenName = args[i + 1]; i += 1
            default: break
            }
            i += 1
        }
        return opts
    }
}

@MainActor
final class AppModel: ObservableObject {
    var state: MatchState
    @Published var library: Library
    @Published var settings: ScorebugCore.Settings
    @Published var serverStatus: String = "Starting"
    @Published var serverRunning = false
    @Published var lastError: String?
    private(set) var slotSummaries: [Int: SlotSummary] = [:]

    let store: Store
    private(set) var resolver: OverlayResolver
    let options: LaunchOptions
    private var server: OverlayServer?
    private var themeConfigCache: [String: ThemeConfig] = [:]
    /// Last polled lineups per slot, in the feed's own sides; read through `liveLineup(slot:side:)`.
    @Published private(set) var liveLineups: [Int: (eventId: String, lineups: [Side: [String]])] = [:]
    @Published private(set) var liveSourceStatus: [String: String] = ["ESPN": "Ready", "FotMob": "Not checked", "SofaScore": "Unavailable: HTTP 403"]
    private var liveSeenAt: [String: Date] = [:]
    private var stoppedLiveEvents: Set<String> = []
    private var pendingUIUpdate: DispatchWorkItem?

    var port: Int { options.port ?? settings.port }
    var baseURL: String { "http://127.0.0.1:\(port)" }

    init(options: LaunchOptions) {
        self.options = options
        let store = try! Store(directory: options.dataDirectory)
        self.store = store
        var loadErrors: [String] = []
        func load<T>(_ name: String, fallback: T, _ read: () throws -> T) -> T {
            do { return try read() } catch { loadErrors.append("Could not load \(name): \(error)"); return fallback }
        }
        self.library = load("library", fallback: SeedLibrary.make(), store.loadLibrary)
        if store.libraryDirty { loadErrors.append("Loaded library has unsaved updates; could not save library.") }
        self.state = load("state", fallback: MatchState(), store.loadState)
        let settings = load("settings", fallback: ScorebugCore.Settings(), store.loadSettings)
        self.settings = settings
        let bundled = OverlayResolver.locateBundledOverlays(explicit: options.overlaysDirectory)
            ?? URL(fileURLWithPath: "/nonexistent")
        self.resolver = OverlayResolver(bundled: bundled, overrides: settings.themeOverridesEnabled ? store.overlayOverridesDirectory : nil)
        CrestImage.directory = store.crestsDirectory
        ScaledFonts.scale = zoomScale
        updateSlotSummaries()
        if loadErrors.isEmpty, options.dataDirectory == Store.defaultDirectory() { importDefaultCrestFolderIfPresent() }
        if !loadErrors.isEmpty { lastError = loadErrors.joined(separator: "\n") }
        if let folder = options.importCrests { importCrestFolder(URL(fileURLWithPath: folder, isDirectory: true)) }
        Task.detached(priority: .utility) { [store] in store.writeMissingThumbnails() }
        Task { await livePollLoop() }
    }

    /// First run on Junior's Mac: his logo library exists at a known place, so crests are imported without asking.
    /// Any other Mac skips this and uses Settings > Choose and import.
    private func importDefaultCrestFolderIfPresent() {
        guard settings.crestFolder == nil else { return }
        let candidate = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Content Creation/03 Media/03 Graphics/01 Images/02 Logos", isDirectory: true)
        guard FileManager.default.fileExists(atPath: candidate.path) else { return }
        importCrestFolder(candidate)
    }

    func importCrestFolder(_ url: URL) {
        var lib = library
        let before = Set(lib.clubs.compactMap(\.crestFile) + lib.competitions.compactMap(\.logoFile))
        let n = store.importCrests(from: url, into: &lib)
        library = lib
        let after = Set(lib.clubs.compactMap(\.crestFile) + lib.competitions.compactMap(\.logoFile))
        for file in after.subtracting(before) { CrestImage.invalidate(file: file) }
        settings.crestFolder = url.path
        saveSettings()
        saveLibrary()
        refreshTeamsFromLibrary()
        if n == 0 { lastError = "No new crests matched in \(url.lastPathComponent)." }
    }

    /// Re-copies crest and colours into live matches whose clubs are in the library.
    private func refreshTeamsFromLibrary() {
        for idx in state.matches.indices {
            var m = state.matches[idx]
            for side in Side.allCases {
                if let id = m.team(side).clubId, let club = library.clubs.first(where: { $0.id == id }) {
                    m = MatchEngine.apply(.setTeam(side, club.entry(for: m.competitionId)), to: m, now: Date())
                }
            }
            state.matches[idx] = m
        }
        persistAndBroadcast()
    }

    // MARK: Matches

    func match(_ slot: Int) -> Match { state.match(slot: slot) ?? Match(slot: slot) }

    /// `theme.json` decoded once per id, not on every body evaluation. Cleared in `saveSettings()`, since an
    /// override-folder toggle can change which file an id resolves to.
    func themeConfig(id: String) -> ThemeConfig? {
        if let cached = themeConfigCache[id] { return cached }
        let config = resolver.themeConfig(id: id)
        if let config { themeConfigCache[id] = config }
        return config
    }

    @discardableResult
    func apply(_ command: Command, slot: Int) -> Bool {
        guard let idx = state.matches.firstIndex(where: { $0.slot == slot }) else { return false }
        var saved = false
        profiled(command) {
            mutate(command, at: idx)
            saved = persistAndBroadcast()
            if saved, case .setTeam = command { Task { await self.linkESPN(slot: slot) } }
        }
        return saved
    }

    /// The engine step shared by the window, API, Stream Deck and live poll. Removing a feed goal, by id or with
    /// minus, remembers its identity so the next poll does not bring it back (Codex review, 1 Oct).
    private func mutate(_ command: Command, at idx: Int) {
        let goals = state.matches[idx].goals
        let removedKey: String? = switch command {
        case .removeGoal(let id): goals.first(where: { $0.id == id })?.autoAddedKey
        case .goal(let side, let delta) where delta < 0: goals.last(where: { $0.side == side })?.autoAddedKey
        default: nil
        }
        state.matches[idx] = MatchEngine.apply(command, to: state.matches[idx], now: Date())
        if let removedKey, !state.matches[idx].goals.contains(where: { $0.autoAddedKey == removedKey }), !state.matches[idx].removedLiveGoalKeys.contains(removedKey) {
            state.matches[idx].removedLiveGoalKeys.append(removedKey)
        }
    }

    // ponytail: last 500 successful responses per session; durable retry history only if needed.
    private var commandResponses: [String: (Data, Bool)] = [:]
    private var commandResponseOrder: [String] = []
    func commandResponse(_ request: CommandRequest, slot: Int, requestId: String?) throws -> (data: Data, saveFailed: Bool) {
        let key = requestId.map { "\(slot)|\($0)" }
        if let key, let cached = commandResponses[key] { return (cached.0, cached.1) }
        try applyRequest(request, slot: slot)
        let data = snapshotData()
        if let key, !stateSaveFailed {
            commandResponses[key] = (data, stateSaveFailed); commandResponseOrder.append(key)
            if commandResponseOrder.count > 500 { commandResponses.removeValue(forKey: commandResponseOrder.removeFirst()) }
        }
        return (data, stateSaveFailed)
    }

    func applyRequest(_ request: CommandRequest, slot: Int) throws {
        let command = try request.toCommand()
        if case .setCompetition(let id) = command {
            guard library.competitions.contains(where: { $0.id == id }) else { throw EngineError.badRequest("unknown competition \(id); known: \(library.competitions.map(\.id).sorted().joined(separator: ", "))") }
            setCompetition(id, slot: slot, deferUIUpdate: true)
            return
        }
        if case .setTheme(let id) = command, let id, !id.isEmpty, themeConfig(id: id) == nil {
            throw EngineError.badRequest("unknown theme \(id); known: \(resolver.availableThemeIds().joined(separator: ", "))")
        }
        guard let idx = state.matches.firstIndex(where: { $0.slot == slot }) else { throw EngineError.badRequest("slot must be 1 or 2") }
        if case .removeGoal(let id) = command {
            guard state.matches[idx].phase != .shootout else { throw EngineError.badRequest("goals cannot be removed during a shootout") }
            guard state.matches[idx].goals.contains(where: { $0.id == id }) else { throw EngineError.badRequest("goal does not exist") }
        }
        if case .goal(let side, let delta) = command, delta < 0 {
            guard state.matches[idx].phase != .shootout else { throw EngineError.badRequest("goals cannot be removed during a shootout") }
            guard state.matches[idx].goals.contains(where: { $0.side == side }) else { throw EngineError.badRequest("no goal exists for that side") }
        }
        profiled(command) {
            mutate(command, at: idx)
            if persistAndBroadcast(deferUIUpdate: true), case .setTeam = command { Task { await self.linkESPN(slot: slot) } }
        }
    }

    /// `SCOREBUG_PROFILE=1`: times the engine call plus save and broadcast, then logs to stderr once this
    /// run-loop turn's layer tree has committed (`CATransaction`'s completion block), which approximates
    /// command-to-painted-frame.
    private static let profileEnabled = ProcessInfo.processInfo.environment["SCOREBUG_PROFILE"] != nil
    private func profiled(_ command: Command, _ body: () -> Void) {
        guard AppModel.profileEnabled else { body(); return }
        let start = CFAbsoluteTimeGetCurrent()
        body()
        let label = String(describing: command).prefix { $0 != "(" }
        CATransaction.setCompletionBlock {
            FileHandle.standardError.write(Data(String(format: "profile %@ %.1f\n", "\(label)", (CFAbsoluteTimeGetCurrent() - start) * 1000).utf8))
        }
    }

    func setClub(_ club: Club?, side: Side, slot: Int) {
        let m = match(slot)
        // Picking the club that already occupies the other side swaps the teams instead of putting it on both.
        if let club, m.team(side.other).clubId == club.id { apply(.swapTeams, slot: slot); return }
        let entry = club?.entry(for: m.competitionId) ?? (side == .home ? TeamEntry.placeholderHome : TeamEntry.placeholderAway)
        apply(.setTeam(side, entry), slot: slot)
    }

    @discardableResult
    func setCompetition(_ id: String, slot: Int, deferUIUpdate: Bool = false) -> Bool {
        var m = match(slot)
        m = MatchEngine.apply(.setCompetition(id), to: m, now: Date())
        // Codes follow the competition, so refresh both entries from the library where the club is known.
        for side in Side.allCases {
            let entry = m.team(side)
            if let clubId = entry.clubId, let club = library.clubs.first(where: { $0.id == clubId }) {
                m = MatchEngine.apply(.setTeam(side, club.entry(for: id)), to: m, now: Date())
            }
        }
        if let idx = state.matches.firstIndex(where: { $0.slot == slot }) { state.matches[idx] = m }
        return persistAndBroadcast(deferUIUpdate: deferUIUpdate)
    }

    func fixtures(on date: Date, competitionId: String?) async throws -> [Fixture] {
        if let competitionId, !library.competitions.contains(where: { $0.id == competitionId }) { return [] }
        let competition = competitionId.flatMap { id in library.competitions.first { $0.id == id } }
        let found = try await FixtureService.fetch(date: date, apiKey: options.dataDirectory == Store.defaultDirectory() ? KeychainStore.get() : nil, espnLeague: competition?.sourceIds["espn"])
        return FixtureLogic.filter(found, competition: competition)
    }

    /// Nil when skipped; otherwise returns whether any fixture change failed to save.
    @discardableResult
    func loadFixture(_ fixture: Fixture, slot: Int, force: Bool = false) async -> Bool? {
        guard let idx = state.matches.firstIndex(where: { $0.slot == slot }) else { return nil }
        guard state.matches[idx].phase == .preMatch || force else { return nil }
        let competition = library.competitions.first { $0.sourceIds.values.contains(fixture.competitionCode) }
        let competitionId = competition?.id ?? state.matches[idx].competitionId
        func club(for team: FixtureTeam) async -> Club {
            var club = FixtureLogic.matchingClub(for: team, in: library.clubs) ?? FixtureLogic.makeClub(from: team)
            if club.crestFile == nil, case .file(let url) = await FixtureService.crest(for: team, in: store.crestsDirectory) {
                club.crestFile = url.lastPathComponent
                CrestImage.invalidate(file: url.lastPathComponent)
            }
            return club
        }
        let homeClub = await club(for: fixture.home)
        let awayClub = await club(for: fixture.away)
        guard match(slot).phase == .preMatch || force else { return nil }
        for club in [homeClub, awayClub] {
            if let i = library.clubs.firstIndex(where: { $0.id == club.id }) { library.clubs[i] = club }
            else { library.clubs.append(club) }
        }
        saveLibrary()
        // Replace the event, including when the next fixture has the same teams. A normal reset keeps the old link and tie.
        let old = state.matches[idx]
        var fresh = Match(slot: slot, competitionId: competitionId, home: homeClub.entry(for: competitionId), away: awayClub.entry(for: competitionId))
        fresh.visible = old.visible; fresh.themeId = old.themeId
        fresh.fillScorersFromESPN = old.fillScorersFromESPN; fresh.autoUpdateLiveData = old.autoUpdateLiveData
        fresh.liveDataDelayMinutes = old.liveDataDelayMinutes; fresh.revision = old.revision + 1
        fresh.kickoff = fixture.kickoff
        if let eventId = fixture.espnEventId, let league = competition?.sourceIds["espn"] ?? (fixture.competitionCode.hasPrefix("uefa") ? fixture.competitionCode : nil) {
            fresh.espnEventId = eventId; fresh.espnLeague = league
        }
        state.matches[idx] = fresh
        guard persistAndBroadcast() else { return true }
        stoppedLiveEvents = stoppedLiveEvents.filter { !$0.hasPrefix("\(slot):") }
        liveSeenAt = liveSeenAt.filter { !$0.key.hasPrefix("\(slot):") }
        liveLineups[slot] = nil
        var saveFailed = false
        if fresh.espnEventId == nil { saveFailed = !(await linkESPN(slot: slot, date: fixture.kickoff)) || saveFailed }
        return saveFailed
    }

    @discardableResult
    func linkESPN(slot: Int, date: Date = Date()) async -> Bool {
        let m = match(slot)
        guard let competition = library.competitions.first(where: { $0.id == m.competitionId }),
              let league = competition.sourceIds["espn"] else { return true }
        do {
            let source = ESPNLiveSource(league: league)
            guard let event = try await source.findEvent(home: m.home.name, away: m.away.name, date: date) else {
                lastError = "No ESPN fixture matched \(m.home.name) v \(m.away.name)."; return true
            }
            guard match(slot).home.name == m.home.name, match(slot).away.name == m.away.name,
                  match(slot).competitionId == m.competitionId else { return true }
            var saved = apply(.setLiveLink(eventId: event.id, league: league), slot: slot)
            if m.kickoff == nil { saved = apply(.setKickoff(event.kickoff), slot: slot) && saved }
            return saved
        } catch { liveSourceStatus["ESPN"] = "Lookup failed: \(error.localizedDescription)"; return true }
    }

    func setLiveSource(_ name: String, enabled: Bool) {
        settings.liveSourceEnabled[name] = enabled
        saveSettings()
    }

    private func livePollLoop() async {
        while !Task.isCancelled {
            for slot in [1, 2] { await refreshLiveData(slot: slot) }
            try? await Task.sleep(for: .seconds(30))
        }
    }

    /// The live poll takes goals only during play and breaks: never before kick-off, after the final whistle or in a
    /// shootout, where the engine refuses a match goal (Codex review, 1 Oct).
    private static func takesLiveGoals(_ phase: Phase) -> Bool {
        ![.preMatch, .fullTime, .extraFullTime, .finished, .shootout].contains(phase)
    }

    /// The linked feed's lineup for one of this match's sides, mapped through a swap; empty once the link changes.
    func liveLineup(slot: Int, side: Side) -> [String] {
        let m = match(slot)
        guard let feed = liveLineups[slot], feed.eventId == m.espnEventId else { return [] }
        return feed.lineups[m.liveSidesSwapped ? side.other : side] ?? []
    }

    func refreshLiveData(slot: Int) async {
        var m = match(slot)
        var now = Date()
        guard m.autoUpdateLiveData, let eventId = m.espnEventId, let league = m.espnLeague,
              !stoppedLiveEvents.contains("\(slot):\(eventId)"), AppModel.takesLiveGoals(m.phase),
              (m.kickoff.map { now >= $0 } ?? m.phase.isLivePeriod), settings.liveSourceEnabled["ESPN"] != false else { return }
        do {
            let live = try await Task.detached(priority: .utility) {
                try await ESPNLiveSource(league: league).fetchGoals(eventId: eventId)
            }.value
            let eventKey = "\(slot):\(eventId)"
            liveLineups[slot] = (eventId, live.lineups)
            // Feed bookkeeping that holds in any phase, skipped if the link changed during the request: orientation
            // from the feed's team names (SB-R4) and saved minute keys moved onto provider goal ids (SB-R3).
            if let idx = state.matches.firstIndex(where: { $0.slot == slot }), state.matches[idx].espnEventId == eventId {
                var edited = LiveDataLogic.migrateLegacyKeys(match: state.matches[idx], liveGoals: live.goals, eventId: eventId)
                if let swapped = LiveDataLogic.feedSidesSwapped(match: edited, feedHome: live.homeName, feedAway: live.awayName) { edited.liveSidesSwapped = swapped }
                if edited != state.matches[idx] { state.matches[idx] = edited; persistAndBroadcast() }
                m = edited
            }
            liveSourceStatus["ESPN"] = "OK · \(Date.now.formatted(date: .omitted, time: .shortened))"
            let liveHome = live.goals.filter { $0.side == .home }, liveAway = live.goals.filter { $0.side == .away }
            if settings.liveSourceEnabled["FotMob"] == true, let kickoff = m.kickoff {
                // Searched in the feed's own orientation, so FotMob's counts line up with ESPN's after a swap.
                let (feedHome, feedAway) = m.liveSidesSwapped ? (m.away.name, m.home.name) : (m.home.name, m.away.name)
                do {
                    let secondary = FotMobLiveSource()
                    if let secondaryEvent = try await Task.detached(priority: .utility, operation: {
                        try await secondary.findEvent(home: feedHome, away: feedAway, date: kickoff)
                    }).value {
                        let other = try await Task.detached(priority: .utility) {
                            try await secondary.fetchGoals(eventId: secondaryEvent.id)
                        }.value
                        liveSourceStatus["FotMob"] = "OK · \(Date.now.formatted(date: .omitted, time: .shortened))"
                        let primaryCounts = [liveHome.count, liveAway.count], otherCounts = [other.goals.filter { $0.side == .home }.count, other.goals.filter { $0.side == .away }.count]
                        let conflict = zip(primaryCounts, otherCounts).contains { $0.0 != $0.1 } &&
                            (other.isFinished || otherCounts.enumerated().contains { $0.element > primaryCounts[$0.offset] })
                        if conflict {
                            // No scores in notices: they show at once and would spoil the 5 minute delay (28 Sep).
                            let message = "ESPN and FotMob disagree, so live updates are paused"
                            if m.liveDataNotice != message { apply(.setLiveNotice(message), slot: slot) }
                            return
                        }
                    } else { liveSourceStatus["FotMob"] = "No matching fixture" }
                } catch { liveSourceStatus["FotMob"] = "Error: \(error.localizedDescription)" }
            }
            // Re-read after the network waits: the operator may have added or removed a goal meanwhile (review of 28 Sep).
            m = match(slot); now = Date()
            // Also re-check the phase: a reset, full time or shootout during the waits must not take stale goals (Codex reviews, 28 Sep and 1 Oct).
            guard m.autoUpdateLiveData, m.espnEventId == eventId, AppModel.takesLiveGoals(m.phase) else { return }
            if m.liveDataNotice != nil { apply(.setLiveNotice(nil), slot: slot) }
            var mature = true
            for (idx, assignment) in LiveDataLogic.assignments(match: m, liveGoals: live.goals, eventId: eventId).enumerated() {
                let goal = assignment.liveGoal
                let seenKey = "\(slot):\(idx):\(assignment.key)"
                let seen = liveSeenAt[seenKey] ?? now
                liveSeenAt[seenKey] = seen
                guard now.timeIntervalSince(seen) >= Double(m.liveDataDelayMinutes * 60) else { mature = false; continue }
                if assignment.shouldAdd {
                    let before = Set(match(slot).goals.map(\.id))
                    apply(.goal(goal.side, 1), slot: slot)
                    // Only a goal this call created takes the feed's details, never an older goal (Codex review, 1 Oct).
                    guard let addedId = match(slot).lastGoal?.goalId, !before.contains(addedId) else { continue }
                    setGoalMinuteFromLive(addedId, goal: goal, slot: slot)
                    apply(.setScorer(addedId, goal.scorer.map(LiveDataLogic.displayScorer), ownGoal: goal.ownGoal, penalty: goal.penalty), slot: slot)
                    setAutoAdded(addedId, liveKey: assignment.key, slot: slot)
                    setAutoFilled(addedId, slot: slot)
                } else if assignment.shouldUpdate, let goalId = assignment.goalId {
                    let scorer = goal.scorer.map(LiveDataLogic.displayScorer) ?? match(slot).goals.first(where: { $0.id == goalId })?.scorer
                    apply(.setScorer(goalId, scorer, ownGoal: goal.ownGoal, penalty: goal.penalty), slot: slot)
                    setGoalMinuteFromLive(goalId, goal: goal, slot: slot)
                    // The filled row carries this feed goal's identity (re-keyed if the feed corrected its minute), so
                    // removing it suppresses that goal and later polls match it before position.
                    markGoal(goalId, slot: slot) { $0.autoFilled = true; $0.autoAddedKey = assignment.key }
                }
            }
            if live.isFinished && mature { stoppedLiveEvents.insert(eventKey) }
        } catch { liveSourceStatus["ESPN"] = "Error: \(error.localizedDescription)" }
    }

    private func setGoalMinuteFromLive(_ id: UUID, goal: LiveGoal, slot: Int) { apply(.setGoalMinute(id, minute: goal.minute, plus: goal.added > 0 ? goal.added : nil), slot: slot) }
    private func setAutoFilled(_ id: UUID, slot: Int) { markGoal(id, slot: slot) { $0.autoFilled = true } }
    private func setAutoAdded(_ id: UUID, liveKey: String, slot: Int) { markGoal(id, slot: slot) { $0.autoAdded = true; $0.autoAddedKey = liveKey } }
    private func markGoal(_ id: UUID, slot: Int, edit: (inout Goal) -> Void) {
        guard let idx = state.matches.firstIndex(where: { $0.slot == slot }), let goal = state.matches[idx].goals.firstIndex(where: { $0.id == id }) else { return }
        edit(&state.matches[idx].goals[goal]); state.matches[idx].revision += 1; persistAndBroadcast()
    }

    private(set) var stateSaveFailed = false
    @discardableResult
    private func persistAndBroadcast(deferUIUpdate: Bool = false) -> Bool {
        // A failed save puts the last saved state back and broadcasts nothing (rule 3).
        if let error = store.commitState(&state, broadcast: broadcast) {
            stateSaveFailed = true; lastError = "Could not save state: \(error.localizedDescription)"
        } else { stateSaveFailed = false }
        updateSlotSummaries()
        if deferUIUpdate {
            // Coalesce rapid API commands so the window diff cannot hold up the next response.
            pendingUIUpdate?.cancel()
            let update = DispatchWorkItem { [weak self] in
                self?.objectWillChange.send()
                self?.pendingUIUpdate = nil
            }
            pendingUIUpdate = update
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: update)
        } else {
            pendingUIUpdate?.cancel()
            pendingUIUpdate = nil
            objectWillChange.send()
        }
        return !stateSaveFailed
    }

    private func updateSlotSummaries() {
        for m in state.matches {
            let summary = SlotSummary(homeCode: m.home.code, awayCode: m.away.code, homeScore: m.homeScore, awayScore: m.awayScore, visible: m.visible)
            if slotSummaries[m.slot] != summary { slotSummaries[m.slot] = summary }
        }
    }

    func snapshot() -> StateSnapshot {
        // The overlay never reads a squad; sending both every command's worth of players over the WebSocket
        // is dead weight the client just discards.
        let matches = state.matches.map { match -> Match in
            var m = match
            m.home.squad = nil
            m.away.squad = nil
            return m
        }
        return StateSnapshot(serverTime: Date(), matches: matches, competitions: library.competitions, overlay: OverlaySettings(portraitTop: settings.portraitTop, previewBackdrop: settings.previewBackdrop, themeOverrides: resolver.overrides != nil))
    }

    func snapshotData() -> Data {
        (try? JSONCoding.encoder().encode(snapshot())) ?? Data("{}".utf8)
    }

    private func broadcast() {
        let data = snapshotData()
        guard let server else { return }
        Task { await server.broadcast(data) }
    }

    // MARK: Library

    // Clubs never ride in the snapshot (only competitions do), so saving the library has nothing to broadcast;
    // `updateCompetition` and `importCompetitionLogo` broadcast themselves for the part that does.
    func saveLibrary() {
        do { try store.saveLibrary(library) } catch { lastError = "Could not save library: \(error.localizedDescription)" }
    }

    func upsertClub(_ club: Club) {
        if let idx = library.clubs.firstIndex(where: { $0.id == club.id }) { library.clubs[idx] = club } else { library.clubs.append(club) }
        saveLibrary()
    }

    func deleteClub(_ id: UUID) {
        library.clubs.removeAll { $0.id == id }
        saveLibrary()
    }

    func importCrest(from url: URL, for clubId: UUID) {
        do {
            let name = try store.importCrest(from: url, for: clubId)
            CrestImage.invalidate(file: name)
            // A replacement often keeps the file name, so the version tells overlays to fetch the image again (SB-R2).
            var version: Int?
            if let idx = library.clubs.firstIndex(where: { $0.id == clubId }) {
                library.clubs[idx].crestFile = name; library.clubs[idx].crestVersion = (library.clubs[idx].crestVersion ?? 0) + 1
                version = library.clubs[idx].crestVersion
            }
            saveLibrary()
            // Live matches using this club pick up the crest.
            for slot in [1, 2] {
                let m = match(slot)
                for side in Side.allCases where m.team(side).clubId == clubId {
                    var entry = m.team(side); entry.crestFile = name; entry.crestVersion = version ?? (entry.crestVersion ?? 0) + 1
                    apply(.setTeam(side, entry), slot: slot)
                }
            }
        } catch { lastError = "Could not import crest: \(error.localizedDescription)" }
    }

    func importCompetitionLogo(from url: URL, for competitionId: String) {
        do {
            let name = try store.importCompetitionLogo(from: url, for: competitionId)
            CrestImage.invalidate(file: name)
            // The file name can stay the same when its image changes; the logo's own version refreshes overlays,
            // so goals and live polls never change the logo URL (SB-R1).
            if let idx = library.competitions.firstIndex(where: { $0.id == competitionId }) {
                library.competitions[idx].logoFile = name; library.competitions[idx].logoVersion = (library.competitions[idx].logoVersion ?? 0) + 1
            }
            saveLibrary()
            broadcast()
        } catch { lastError = "Could not import the competition logo: \(error.localizedDescription)" }
    }

    func updateCompetition(_ comp: Competition) {
        guard let idx = library.competitions.firstIndex(where: { $0.id == comp.id }) else { return }
        library.competitions[idx] = comp
        saveLibrary()
        broadcast()
    }

    /// Interface text size, Cmd-plus and Cmd-minus, remembered between launches. This scales font point sizes
    /// directly (`zoomScale`) rather than a `scaleEffect` on the whole content: an AppKit-backed view (VSplitView,
    /// a grouped Form, WKWebView) scaled with scaleEffect draws in one place and takes clicks in another, which is
    /// why nothing responded when zoomed. It also no longer maps to `DynamicTypeSize`, because on macOS the system
    /// text styles have fixed point sizes and ignore Dynamic Type, so that mapping changed nothing on screen either.
    @Published var zoomLevel: Int = {
        let stored = UserDefaults.standard.object(forKey: "zoomLevel") as? Int ?? 0
        return min(3, max(-2, stored))
    }() {
        didSet {
            UserDefaults.standard.set(zoomLevel, forKey: "zoomLevel")
            ScaledFonts.scale = zoomScale
        }
    }
    /// Level 0 is 1.15x, one step bigger than the system default point size (now level -1, at 1.0x), so the
    /// interface opens a step bigger while "Actual Size" (Command-0) still resets to level 0. The clamp of
    /// -2...3 reaches from 0.92x up to 1.7x.
    private static let zoomScales: [CGFloat] = [0.92, 1.0, 1.15, 1.3, 1.5, 1.7]
    var zoomScale: CGFloat {
        let index = zoomLevel + 2
        return AppModel.zoomScales[min(max(index, 0), AppModel.zoomScales.count - 1)]
    }
    func zoom(_ delta: Int) { zoomLevel = min(3, max(-2, zoomLevel + delta)) }

    func saveSettings() {
        themeConfigCache.removeAll()
        // "Use override folder" takes effect at once for the window and the server; overlays reload on the
        // snapshot's themeOverrides change (Codex review, 1 Oct).
        let overrides = settings.themeOverridesEnabled ? store.overlayOverridesDirectory : nil
        if resolver.overrides != overrides {
            resolver = OverlayResolver(bundled: resolver.bundled, overrides: overrides)
            server?.resolver = resolver
        }
        do { try store.saveSettings(settings) } catch { lastError = "Could not save settings: \(error.localizedDescription)" }
        // Settings (e.g. portraitTop) ride inside every state snapshot, so overlay clients need a fresh
        // broadcast on change, the same way a match edit does via persistAndBroadcast().
        broadcast()
    }

    /// Builds and sends a key down then a key up into the key window. See `TestKeyRequest` for the wire shape.
    /// Posted, not sent: local key monitors only see events that pass through the run loop's dispatch.
    @discardableResult static func sendTestKey(_ req: TestKeyRequest) -> Bool {
        guard let window = NSApp.keyWindow ?? NSApp.mainWindow ?? NSApp.windows.first(where: { $0.isVisible }) else { return false }
        window.makeKey()
        let flagNames: [String: NSEvent.ModifierFlags] = ["shift": .shift, "command": .command, "option": .option, "control": .control]
        let flags = (req.modifiers ?? []).compactMap { flagNames[$0] }.reduce(into: NSEvent.ModifierFlags()) { $0.formUnion($1) }
        let characters = req.characters ?? ""
        for type: NSEvent.EventType in [.keyDown, .keyUp] {
            // No `continue` on nil: a build failure for either event must not still report {"sent":true}.
            guard let event = NSEvent.keyEvent(with: type, location: .zero, modifierFlags: flags, timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil, characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: req.keyCode) else { return false }
            NSApp.postEvent(event, atStart: false)
        }
        return true
    }

    // MARK: Server

    func startServer() {
        guard let validPort = UInt16(exactly: port), validPort >= 1024 else { serverStatus = "Invalid port \(port)"; return }
        let server = OverlayServer(port: validPort, resolver: resolver, crestsDirectory: store.crestsDirectory, model: self)
        self.server = server
        serverStatus = "Starting on port \(port)"
        Task {
            do {
                try await server.start()
                self.serverRunning = true
                self.serverStatus = "Serving on \(self.baseURL)"
            } catch {
                self.serverRunning = false
                self.serverStatus = "Could not start on port \(self.port): \(error.localizedDescription)"
            }
        }
    }
}

/// Bundle facts shown in the sidebar and Settings › About.
enum AppInfo {
    static var version: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "development" }
}
