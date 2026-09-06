// Owns state for both slots, calls MatchEngine, saves through Store, then broadcasts through OverlayServer.
import Foundation
import SwiftUI
import ScorebugCore

struct LaunchOptions {
    var dataDirectory: URL
    var overlaysDirectory: String?
    var port: Int?
    /// `--import-crests <folder>`: import a crest folder once at launch (the launch-time default import only runs on a first run).
    var importCrests: String?
    /// `--screen <name>`: open the window on that display (by its name in System Settings) and do not steal focus.
    /// Agents' test instances use `--screen "Agent Screen"` so nothing lands on Junior's monitors.
    var screenName: String?

    static func parse(_ args: [String]) -> LaunchOptions {
        var opts = LaunchOptions(dataDirectory: Store.defaultDirectory(), overlaysDirectory: nil, port: nil)
        var i = 0
        while i < args.count {
            switch args[i] {
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
        if let folder = options.importCrests { importCrestFolder(URL(fileURLWithPath: folder, isDirectory: true)) }
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
        state.matches[idx] = MatchEngine.apply(command, to: state.matches[idx], now: Date())
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
        guard let base = try? JSONCoding.encoder().encode(snapshot()),
              var obj = (try? JSONSerialization.jsonObject(with: base)) as? [String: Any] else {
            return Data("{}".utf8)
        }
        // Overlay-wide settings, distinct from per-match state. portraitTop overrides every theme's
        // geometry.v.top for the primary portrait slot; overlay.js derives the secondary slot's top from it.
        obj["overlay"] = ["portraitTop": settings.portraitTop]
        return (try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys])) ?? base
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

    /// Interface text size, Cmd-plus and Cmd-minus, remembered between launches. This scales font point sizes
    /// directly (`zoomScale`) rather than a `scaleEffect` on the whole content: an AppKit-backed view (VSplitView,
    /// a grouped Form, WKWebView) scaled with scaleEffect draws in one place and takes clicks in another, which is
    /// why nothing responded when zoomed. It also no longer maps to `DynamicTypeSize`, because on macOS the system
    /// text styles have fixed point sizes and ignore Dynamic Type, so that mapping changed nothing on screen either.
    @Published var zoomLevel: Int = {
        let stored = UserDefaults.standard.object(forKey: "zoomLevel") as? Int ?? 0
        return min(3, max(-2, stored))
    }() {
        didSet { UserDefaults.standard.set(zoomLevel, forKey: "zoomLevel") }
    }
    /// Level 0 is 1.0, the system default point size. The clamp of -2...3 reaches from 0.85x up to 1.5x.
    private static let zoomScales: [CGFloat] = [0.85, 0.92, 1.0, 1.15, 1.3, 1.5]
    var zoomScale: CGFloat {
        let index = zoomLevel + 2
        return AppModel.zoomScales[min(max(index, 0), AppModel.zoomScales.count - 1)]
    }
    func zoom(_ delta: Int) { zoomLevel = min(3, max(-2, zoomLevel + delta)) }

    func saveSettings() {
        do { try store.saveSettings(settings) } catch { lastError = "Could not save settings: \(error.localizedDescription)" }
        // Settings (e.g. portraitTop) ride inside every state snapshot, so overlay clients need a fresh
        // broadcast on change, the same way a match edit does via persistAndBroadcast().
        broadcast()
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

/// Bundle facts shown in the sidebar and Settings › About.
enum AppInfo {
    static var version: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "development" }
}
