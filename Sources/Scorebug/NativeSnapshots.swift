// Offscreen content snapshots. This route never opens a window or starts a server.
import AppKit
import SwiftUI
import ScorebugCore

@MainActor
enum NativeSnapshots {
    static let isRequested = ProcessInfo.processInfo.environment["SCOREBUG_NATIVE_SNAPSHOTS"] != nil
    private static let scratch = URL(fileURLWithPath: "/private/tmp/bama/build-scorebug", isDirectory: true)

    static func run(options: LaunchOptions) -> Never {
        do {
            let environment = ProcessInfo.processInfo.environment
            guard let destination = environment["SCOREBUG_NATIVE_SNAPSHOTS"],
                  let home = environment["CFFIXED_USER_HOME"],
                  CommandLine.arguments.contains("--data-directory"),
                  options.importCrests == nil,
                  isScratchChild(URL(fileURLWithPath: destination)),
                  isScratchChild(URL(fileURLWithPath: home)),
                  isScratchChild(options.dataDirectory) else {
                throw SnapshotError.unsafePaths
            }
            let output = URL(fileURLWithPath: destination, isDirectory: true)
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: options.dataDirectory, withIntermediateDirectories: true)
            _ = NSApplication.shared
            let fixtures = makeFixtures()
            try JSONCoding.prettyEncoder().encode(fixtures.state).write(to: options.dataDirectory.appendingPathComponent("state.json"))
            try JSONCoding.prettyEncoder().encode(fixtures.library).write(to: options.dataDirectory.appendingPathComponent("library.json"))
            try JSONCoding.prettyEncoder().encode(ScorebugCore.Settings(liveSourceEnabled: [:])).write(to: options.dataDirectory.appendingPathComponent("settings.json"))
            UserDefaults.standard.set(true, forKey: "showPreview")
            UserDefaults.standard.set(1, forKey: "zoomLevel")
            let model = AppModel(options: options, startsBackgroundTasks: false)
            // Keep only the small synthetic catalogue. The ordinary seed merge is deliberately not the screenshot fixture.
            model.library = fixtures.library
            model.serverStatus = "Snapshot fixture: server stopped"
            model.lastError = nil
            var results: [[String: Any]] = []
            for appearance in ["light", "dark"] {
                let scheme: ColorScheme = appearance == "dark" ? .dark : .light
                NSApp.appearance = NSAppearance(named: appearance == "dark" ? .darkAqua : .aqua)
                model.zoomLevel = 1
                UserDefaults.standard.set("list", forKey: "libraryViewMode")
                let pages: [(String, AnyView, CGSize)] = [
                    ("primary", AnyView(ContentView(initialSection: .slot(1))), CGSize(width: 1180, height: 720)),
                    ("secondary", AnyView(ContentView(initialSection: .slot(2))), CGSize(width: 1180, height: 720)),
                    ("library", AnyView(ContentView(initialSection: .library)), CGSize(width: 1180, height: 720)),
                    ("library-club", AnyView(LibraryView(snapshotClubID: fixtures.library.clubs[0].id)), CGSize(width: 1180, height: 720)),
                    ("library-competition", AnyView(LibraryView(snapshotCompetitionID: "europa-league")), CGSize(width: 1180, height: 720)),
                    ("settings-obs", AnyView(SettingsView(initialTab: .obs)), CGSize(width: 640, height: 600)),
                    ("settings-live-data", AnyView(SettingsView(initialTab: .liveData)), CGSize(width: 640, height: 600)),
                    ("settings-advanced", AnyView(SettingsView(initialTab: .advanced)), CGSize(width: 640, height: 600))
                ]
                for (name, view, size) in pages {
                    results.append(try capture(view, name: "\(name)-\(appearance)", scheme: scheme, size: size, model: model, output: output))
                }
                UserDefaults.standard.set("icons", forKey: "libraryViewMode")
                results.append(try capture(AnyView(LibraryView(snapshotClubID: fixtures.library.clubs[0].id)), name: "library-icons-\(appearance)", scheme: scheme, size: CGSize(width: 1180, height: 720), model: model, output: output))
                model.zoomLevel = 2
                for slot in [1, 2] {
                    results.append(try capture(AnyView(ContentView(initialSection: .slot(slot))), name: "slot-\(slot)-zoom-2-\(appearance)", scheme: scheme, size: CGSize(width: 1180, height: 720), model: model, output: output))
                }
            }
            guard !NSApp.windows.contains(where: \.isVisible) else { throw SnapshotError.render("unexpected visible window") }
            let report: [String: Any] = [
                "status": "PASS", "count": results.count, "images": results, "visibleWindows": 0,
                "method": "Offscreen NSHostingView cacheDisplay; no window was shown",
                "limitations": ["Active titlebar, menu bar, Liquid Glass and first-responder behaviour need a live visual check.", "Preview uses a labelled static placeholder; this checks native geometry but not WebKit or the broadcast overlay."]
            ]
            let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: output.appendingPathComponent("report.json"))
            log("PASS: \(results.count) native content snapshots, light and dark, at \(output.path)")
            exit(0)
        } catch {
            log("FAIL: native snapshots: \(error)")
            exit(1)
        }
    }

    private static func isScratchChild(_ url: URL) -> Bool {
        let root = scratch.resolvingSymlinksInPath().standardizedFileURL.path + "/"
        return url.resolvingSymlinksInPath().standardizedFileURL.path.hasPrefix(root)
    }

    private static func capture(_ view: AnyView, name: String, scheme: ColorScheme, size: CGSize, model: AppModel, output: URL) throws -> [String: Any] {
        let content = view.environmentObject(model).environment(\.colorScheme, scheme)
            .environment(\.font, .system(size: NSFont.systemFontSize * model.zoomScale))
            .background(Color(nsColor: .windowBackgroundColor))
        let hosting = NSHostingView(rootView: content)
        hosting.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        window.appearance = NSApp.appearance
        defer { window.contentView = nil; window.close() }
        // No orderFront, key window, activation, screen capture or synthetic input is used here.
        for _ in 0..<4 {
            hosting.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.08))
        }
        guard !window.isVisible, let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { throw SnapshotError.render(name) }
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        var sampledColours = Set<String>()
        for y in stride(from: 0, to: bitmap.pixelsHigh, by: max(1, bitmap.pixelsHigh / 32)) {
            for x in stride(from: 0, to: bitmap.pixelsWide, by: max(1, bitmap.pixelsWide / 48)) {
                if let colour = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) {
                    sampledColours.insert("\(Int(colour.redComponent * 255)),\(Int(colour.greenComponent * 255)),\(Int(colour.blueComponent * 255))")
                }
            }
        }
        guard sampledColours.count >= 8 else { throw SnapshotError.render("\(name): blank content") }
        guard let png = bitmap.representation(using: .png, properties: [:]), png.count > 2_000 else { throw SnapshotError.render(name) }
        let file = output.appendingPathComponent("\(name).png")
        try png.write(to: file)
        GridProbes.shared.write(to: output.appendingPathComponent("\(name)-layout.json").path, window: size)
        log("SNAPSHOT \(file.path) (\(bitmap.pixelsWide) × \(bitmap.pixelsHigh), offscreen)")
        return ["name": name, "file": file.lastPathComponent, "width": bitmap.pixelsWide, "height": bitmap.pixelsHigh, "bytes": png.count, "sampledColourCount": sampledColours.count]
    }

    private static func makeFixtures() -> (library: Library, state: MatchState) {
        let competitions = [
            Competition(id: "champions-league", name: "Champions League", shortName: "UCL", themeId: "champions-league"),
            Competition(id: "europa-league", name: "Europa League", shortName: "UEL", themeId: "europa-league"),
            Competition(id: "premier-league", name: "Premier League", shortName: "PL", themeId: "premier-league"),
            Competition(id: "club-world-cup", name: "Club World Cup", shortName: "CWC", themeId: "stealth"),
            Competition(id: "international", name: "International", shortName: "INT", themeId: "stealth")
        ]
        let names = ["Northbridge Athletic", "Rivergate United", "Eastborough Wanderers", "Westhaven City", "Northbridge Athletic Development", "Lakeside Rovers", "Harbour Town", "Southern Albion"]
        let colours = ["#FFFFFF", "#EA580C", "#E8CB64", "#1D4ED8", "#6622BB", "#A51030", "#087F5B", "#252525"]
        let clubs = names.enumerated().map { index, name in
            Club(id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", index + 1))!, name: name, shortName: name, defaultCode: String(name.prefix(3)).uppercased(), primaryColour: colours[index], textColour: index < 3 ? "#000000" : "#FFFFFF", competitionIds: ["champions-league", "premier-league", index == 2 ? "club-world-cup" : "europa-league"], confederation: "UEFA", squad: ["A. Sample", "B. Example", "C. Northbridge"])
        }
        var first = Match(slot: 1, competitionId: "champions-league", home: clubs[0].entry(for: "champions-league"), away: clubs[1].entry(for: "champions-league"))
        first.phase = .secondHalf
        first.clock = Clock(periodBaseSeconds: 2700, accumulated: 1210, running: false)
        first.homeScore = 2; first.awayScore = 1
        first.addedMinutes = 4
        first.aggregate = Aggregate(firstLegHome: 1, firstLegAway: 2)
        first.showScorers = true
        first.goals = [
            Goal(side: .home, elapsedSeconds: 900, minuteLabel: "15′", scorer: "A. Sample"),
            Goal(side: .away, elapsedSeconds: 1700, minuteLabel: "29′", scorer: "B. Example", penalty: true),
            Goal(side: .home, elapsedSeconds: 3100, minuteLabel: "52′", scorer: "C. Northbridge")
        ]
        var second = Match(slot: 2, competitionId: "premier-league", home: clubs[2].entry(for: "premier-league"), away: clubs[3].entry(for: "premier-league"))
        second.visible = false
        return (Library(competitions: competitions, clubs: clubs), MatchState(matches: [first, second]))
    }

    private static func log(_ message: String) { FileHandle.standardError.write(Data((message + "\n").utf8)) }
    private enum SnapshotError: Error {
        case unsafePaths
        case render(String)
    }
}
