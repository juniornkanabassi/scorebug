// App entry. Standard macOS structure: sidebar and detail, toolbar, Settings window on Cmd-comma, menu bar item.
import SwiftUI
import ScorebugCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
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
        }
        .defaultSize(width: 1180, height: 820)
        .defaultLaunchBehavior(.presented)
        .restorationBehavior(.disabled)

        MenuBarExtra("Scorebug", systemImage: model.serverRunning ? "sportscourt.fill" : "sportscourt") {
            MenuBarContent().environmentObject(model)
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
                                Text(slot == 1 ? "Primary" : "Secondary")
                                Text("\(m.home.code) \(m.homeScore) – \(m.awayScore) \(m.away.code)").font(.caption).foregroundStyle(.secondary).monospacedDigit()
                            }
                        } icon: { Image(systemName: slot == 1 ? "1.square" : "2.square") }
                        .tag(SidebarSection.slot(slot))
                    }
                }
                Section {
                    Label("Library", systemImage: "books.vertical").tag(SidebarSection.library)
                    Label("Settings", systemImage: "gearshape").tag(SidebarSection.settings)
                }
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 230)
            .safeAreaInset(edge: .bottom) {
                HStack(spacing: 6) {
                    Circle().fill(model.serverRunning ? Color.green : Color.red).frame(width: 7, height: 7)
                    Text(model.serverRunning ? "Serving on localhost:\(model.port)" : model.serverStatus).font(.caption).foregroundStyle(.secondary).lineLimit(2)
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
