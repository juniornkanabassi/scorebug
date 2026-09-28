// App entry. Standard macOS structure: sidebar and detail, toolbar, Settings window on Cmd-comma, menu bar item.
import SwiftUI
import ScorebugCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var screenObserver: Any?

    func applicationWillFinishLaunching(_ notification: Notification) {
        // SCOREBUG_APPEARANCE=light|dark pins this launch to Aqua or Dark Aqua for visual checks.
        switch ProcessInfo.processInfo.environment["SCOREBUG_APPEARANCE"] {
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
        default: break
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        let wanted = LaunchOptions.parse(Array(CommandLine.arguments.dropFirst())).screenName
        guard let wanted else { NSApp.activate(ignoringOtherApps: true); return }
        // `--screen`: every window this process opens goes to the named display, and the app never takes focus,
        // so agents' test instances stay off Junior's monitors. Falls back to normal behaviour if the screen is absent.
        let place: (NSWindow) -> Void = { window in
            guard let screen = NSScreen.screens.first(where: { $0.localizedName == wanted }) else { return }
            let f = screen.visibleFrame
            let size = window.frame.size
            window.setFrameOrigin(NSPoint(x: f.minX + 40, y: f.maxY - size.height - 40))
        }
        NSApp.windows.forEach(place)
        // Placed once more on the first didBecomeKey (the window often has no frame yet at launch), then never
        // again, so a later drag to another display sticks instead of snapping back.
        screenObserver = NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main) { [weak self] note in
            if let w = note.object as? NSWindow, w.screen?.localizedName != wanted { place(w) }
            if let observer = self?.screenObserver { NotificationCenter.default.removeObserver(observer) }
            self?.screenObserver = nil
        }
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { true }
}

@main
struct ScorebugApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model: AppModel

    init() {
        let options = LaunchOptions.parse(Array(CommandLine.arguments.dropFirst()))
        let model = AppModel(options: options)
        _model = StateObject(wrappedValue: model)
        model.startServer()
    }

    var body: some Scene {
        WindowGroup("Scorebug", id: "main") {
            ContentView().environmentObject(model).frame(minWidth: 1180, minHeight: 720)
                .environment(\.font, .system(size: NSFont.systemFontSize * model.zoomScale))
                .onAppear { WindowSetup.apply(zoom: { model.zoom($0) }, reset: { model.zoomLevel = 0 }) }
        }
        .defaultSize(width: 1180, height: 820)
        .defaultLaunchBehavior(.presented)
        .restorationBehavior(.disabled)
        .commands {
            CommandGroup(after: .toolbar) {
                Button("Bigger Text") { model.zoom(1) }.keyboardShortcut("=", modifiers: .command)
                Button("Smaller Text") { model.zoom(-1) }.keyboardShortcut("-", modifiers: .command)
                Button("Actual Size") { model.zoomLevel = 0 }.keyboardShortcut("0", modifiers: .command)
                Divider()
                Button("Reload Previews") { NotificationCenter.default.post(name: OverlayWebView.reloadRequested, object: nil) }.keyboardShortcut("r", modifiers: .command)
            }
        }
    }
}

/// Command with = + - 0 zooms the interface text from anywhere in the window, including while a text field has
/// focus, and Command-Shift-= (the + key) counts as Command-+. Handled with a local key-down monitor, in the
/// style of the sister app Content Template, so the menu equivalents never fire the change twice.
enum WindowSetup {
    private static var keyMonitor: Any?
    static func apply(zoom: @escaping (Int) -> Void, reset: @escaping () -> Void) {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting([.shift, .numericPad, .function])
            guard flags == .command else { return event }
            // Key codes cover every layout; the characters cover keyboards where = and - sit elsewhere.
            let characters = event.charactersIgnoringModifiers ?? ""
            switch (event.keyCode, characters) {
            case (24, _), (69, _), (_, "="), (_, "+"): zoom(1); return nil
            case (27, _), (78, _), (_, "-"), (_, "_"): zoom(-1); return nil
            case (29, _), (82, _), (_, "0"): reset(); return nil
            default: return event
            }
        }
    }
}

enum SidebarSection: Hashable { case slot(Int), library, settings }

/// One sidebar row for a match slot. Equatable on the tiny summary it draws (codes, scores, visible), not
/// the whole `Match` (which drags in both squads via `TeamEntry`), so a command that leaves this slot's
/// summary untouched skips the row entirely.
struct SidebarMatchRow: View, Equatable {
    let slot: Int
    let summary: SlotSummary
    static func == (l: Self, r: Self) -> Bool { l.slot == r.slot && l.summary == r.summary }
    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(slot == 1 ? "Primary" : "Secondary").scaledFont(.body)
                    if summary.visible {
                        Circle().fill(.green).frame(width: 8, height: 8).help("On air: this bug is shown in OBS")
                        Text("LIVE").scaledFont(.caption2, weight: .bold).foregroundStyle(.green)
                    }
                }
                Text("\(summary.homeCode) \(summary.homeScore) – \(summary.awayScore) \(summary.awayCode)").scaledFont(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
        } icon: { Image(systemName: slot == 1 ? "1.square" : "2.square").scaledFont(.body) }
    }
}

struct ContentView: View {
    @EnvironmentObject var model: AppModel
    @State private var section: SidebarSection? = .slot(1)

    var body: some View {
        NavigationSplitView {
            List(selection: $section) {
                Section("Matches") {
                    ForEach([1, 2], id: \.self) { slot in
                        SidebarMatchRow(slot: slot, summary: model.slotSummaries[slot] ?? SlotSummary()).equatable().tag(SidebarSection.slot(slot))
                    }
                }
                Section {
                    HStack(spacing: 8) {
                        Image(systemName: "books.vertical")
                        Text("Team Library").lineLimit(1)
                    }.scaledFont(.body).accessibilityElement(children: .combine).tag(SidebarSection.library)
                    HStack(spacing: 8) {
                        Image(systemName: "gearshape")
                        Text("Settings").lineLimit(1)
                    }.scaledFont(.body).accessibilityElement(children: .combine).tag(SidebarSection.settings)
                }
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 230, max: 260)
            .safeAreaInset(edge: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Circle().fill(model.serverRunning ? Color.green : Color.red).frame(width: 7, height: 7)
                        Text(model.serverRunning ? "Serving on localhost:\(model.port)" : model.serverStatus).scaledFont(.caption).foregroundStyle(.secondary).lineLimit(2)
                    }
                    Text("Scorebug \(AppInfo.version)").scaledFont(.caption2).foregroundStyle(.secondary)
                }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
            }
        } detail: {
            switch section {
            case .slot(let s): SlotView(slot: s).id(s)
            case .library: LibraryView()
            case .settings: SettingsView()
            case nil: ContentUnavailableView("Choose a match", systemImage: "sportscourt")
            }
        }
        .alert("Scorebug", isPresented: Binding(get: { model.lastError != nil }, set: { if !$0 { model.lastError = nil } })) {
            Button("OK") { model.lastError = nil }
        } message: { Text(model.lastError ?? "") }
    }
}
