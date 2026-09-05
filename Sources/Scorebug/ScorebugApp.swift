// App entry. Standard macOS structure: sidebar and detail, toolbar, Settings window on Cmd-comma, menu bar item.
import SwiftUI
import ScorebugCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var screenObserver: Any?

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
        screenObserver = NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main) { note in
            if let w = note.object as? NSWindow, w.screen?.localizedName != wanted { place(w) }
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
            ContentView().environmentObject(model).frame(minWidth: 960, minHeight: 640)
                .environment(\.zoomScale, model.zoomScale)
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
            }
        }

        MenuBarExtra("Scorebug", systemImage: model.serverRunning ? "sportscourt.fill" : "sportscourt") {
            MenuBarContent().environmentObject(model)
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

struct MenuBarContent: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Group {
            Text(model.serverStatus)
            Divider()
            ForEach([1, 2], id: \.self) { slot in
                let m = model.match(slot)
                Text("\(slot == 1 ? "Primary" : "Secondary"): \(m.home.code) \(m.homeScore) – \(m.awayScore) \(m.away.code)")
            }
            Divider()
            Button("Open Scorebug") { openWindow(id: "main"); NSApp.activate(ignoringOtherApps: true) }
            Button("Quit Scorebug") { NSApp.terminate(nil) }.keyboardShortcut("q")
        }
    }
}

enum SidebarSection: Hashable { case slot(Int), library, settings }

struct ContentView: View {
    @EnvironmentObject var model: AppModel
    @State private var section: SidebarSection? = .slot(1)

    var body: some View {
        NavigationSplitView {
            List(selection: $section) {
                Section("Matches") {
                    ForEach([1, 2], id: \.self) { slot in
                        let m = model.match(slot)
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(slot == 1 ? "Primary" : "Secondary").scaledFont(.body)
                                Text("\(m.home.code) \(m.homeScore) – \(m.awayScore) \(m.away.code)").scaledFont(.caption).foregroundStyle(.secondary).monospacedDigit()
                            }
                        } icon: { Image(systemName: slot == 1 ? "1.square" : "2.square").scaledFont(.body) }
                        .tag(SidebarSection.slot(slot))
                    }
                }
                Section {
                    Label("Library", systemImage: "books.vertical").scaledFont(.body).tag(SidebarSection.library)
                    Label("Settings", systemImage: "gearshape").scaledFont(.body).tag(SidebarSection.settings)
                }
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 230)
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
