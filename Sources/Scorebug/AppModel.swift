// Owns state for both slots, calls MatchEngine, saves through Store, then broadcasts through OverlayServer.
import Foundation
import SwiftUI
import ScorebugCore

struct LaunchOptions {
    var dataDirectory: URL
    var overlaysDirectory: String?
    var port: Int?

    static func parse(_ args: [String]) -> LaunchOptions {
        var opts = LaunchOptions(dataDirectory: Store.defaultDirectory(), overlaysDirectory: nil, port: nil)
        var i = 0
        while i < args.count {
            switch args[i] {
            case "--data-directory" where i + 1 < args.count: opts.dataDirectory = URL(fileURLWithPath: args[i + 1], isDirectory: true); i += 1
            case "--overlays-directory" where i + 1 < args.count: opts.overlaysDirectory = args[i + 1]; i += 1
            case "--port" where i + 1 < args.count: opts.port = Int(args[i + 1]); i += 1
            default: break
            }
            i += 1
        }
        return opts
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published var state: MatchState
    @Published var library: Library
    @Published var settings: ScorebugCore.Settings
    @Published var serverStatus: String = "Starting"
    @Published var serverRunning = false
    @Published var lastError: String?

    let store: Store
    let resolver: OverlayResolver
    let options: LaunchOptions
    private var server: OverlayServer?

    var port: Int { options.port ?? settings.port }
    var baseURL: String { "http://localhost:\(port)" }

    init(options: LaunchOptions) {
        self.options = options
        let store = try! Store(directory: options.dataDirectory)
        self.store = store
        self.library = (try? store.loadLibrary()) ?? SeedLibrary.make()
        self.state = (try? store.loadState()) ?? MatchState()
        let settings = (try? store.loadSettings()) ?? ScorebugCore.Settings()
        self.settings = settings
        let bundled = OverlayResolver.locateBundledOverlays(explicit: options.overlaysDirectory)
            ?? URL(fileURLWithPath: "/nonexistent")
        self.resolver = OverlayResolver(bundled: bundled, overrides: settings.themeOverridesEnabled ? store.overlayOverridesDirectory : nil)
        importDefaultCrestFolderIfPresent()
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
        let n = store.importCrests(from: url, into: &lib)
        library = lib
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
        try? store.saveState(state)
    }

    // MARK: Matches

    func match(_ slot: Int) -> Match { state.match(slot: slot) ?? Match(slot: slot) }

    func apply(_ command: Command, slot: Int) {
        guard let idx = state.matches.firstIndex(where: { $0.slot == slot }) else { return }
        state.matches[idx] = MatchEngine.apply(command, to: state.matches[idx], now: Date())
        persistAndBroadcast()
    }

    func applyRequest(_ request: CommandRequest, slot: Int) throws {
        let command = try request.toCommand()
        guard let idx = state.matches.firstIndex(where: { $0.slot == slot }) else { throw EngineError.badRequest("slot must be 1 or 2") }
        var m = state.matches[idx]
        if request.command == "playPause" {
            m = MatchEngine.apply(.play, to: m, now: Date())
        } else {
            m = MatchEngine.apply(command, to: m, now: Date())
        }
        state.matches[idx] = m
        persistAndBroadcast()
    }

    func setClub(_ club: Club?, side: Side, slot: Int) {
        let m = match(slot)
        let entry = club?.entry(for: m.competitionId) ?? (side == .home ? TeamEntry.placeholderHome : TeamEntry.placeholderAway)
        apply(.setTeam(side, entry), slot: slot)
    }

    func setCompetition(_ id: String, slot: Int) {
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
        persistAndBroadcast()
    }

    private func persistAndBroadcast() {
        do { try store.saveState(state) } catch { lastError = "Could not save state: \(error.localizedDescription)" }
        broadcast()
    }

    func snapshot() -> StateSnapshot {
        StateSnapshot(serverTime: Date(), matches: state.matches, competitions: library.competitions)
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

    func saveLibrary() {
        do { try store.saveLibrary(library) } catch { lastError = "Could not save library: \(error.localizedDescription)" }
        broadcast()
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
            if let idx = library.clubs.firstIndex(where: { $0.id == clubId }) { library.clubs[idx].crestFile = name }
            saveLibrary()
            // Live matches using this club pick up the crest.
            for slot in [1, 2] {
                let m = match(slot)
                for side in Side.allCases where m.team(side).clubId == clubId {
                    var entry = m.team(side); entry.crestFile = name
                    apply(.setTeam(side, entry), slot: slot)
                }
            }
        } catch { lastError = "Could not import crest: \(error.localizedDescription)" }
    }

    func importCompetitionLogo(from url: URL, for competitionId: String) {
        do {
            let name = try store.importCompetitionLogo(from: url, for: competitionId)
            if let idx = library.competitions.firstIndex(where: { $0.id == competitionId }) { library.competitions[idx].logoFile = name }
            saveLibrary()
        } catch { lastError = "Could not import the competition logo: \(error.localizedDescription)" }
    }

    func updateCompetition(_ comp: Competition) {
        if let idx = library.competitions.firstIndex(where: { $0.id == comp.id }) { library.competitions[idx] = comp; saveLibrary() }
    }

    /// Interface zoom, Cmd-plus and Cmd-minus, remembered between launches.
    @Published var uiScale: CGFloat = CGFloat(UserDefaults.standard.double(forKey: "uiScale") == 0 ? 1 : UserDefaults.standard.double(forKey: "uiScale")) {
        didSet { UserDefaults.standard.set(Double(uiScale), forKey: "uiScale") }
    }
    func zoom(_ delta: CGFloat) { uiScale = min(1.6, max(0.8, (uiScale + delta).rounded(toPlaces: 2))) }

    func saveSettings() {
        do { try store.saveSettings(settings) } catch { lastError = "Could not save settings: \(error.localizedDescription)" }
    }

    // MARK: Server

    func startServer() {
        let server = OverlayServer(port: UInt16(port), resolver: resolver, crestsDirectory: store.crestsDirectory, model: self)
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
