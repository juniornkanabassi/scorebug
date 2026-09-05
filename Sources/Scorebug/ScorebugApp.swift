// App entry. Window, menu bar item, --data-directory argument. See ARCHITECTURE.md "Control panel".
import SwiftUI
import ScorebugCore

@main
struct ScorebugApp: App {
    @StateObject private var model: AppModel

    init() {
        let options = LaunchOptions.parse(Array(CommandLine.arguments.dropFirst()))
        let model = AppModel(options: options)
        _model = StateObject(wrappedValue: model)
        model.startServer()
    }

    var body: some Scene {
        WindowGroup("Scorebug") {
            ContentView().environmentObject(model).frame(minWidth: 980, minHeight: 640)
        }
        .defaultSize(width: 1180, height: 760)

        MenuBarExtra("Scorebug", systemImage: model.serverRunning ? "sportscourt.fill" : "sportscourt") {
            Text(model.serverStatus)
            Divider()
            ForEach([1, 2], id: \.self) { slot in
                let m = model.match(slot)
                Text("Slot \(slot): \(m.home.code) \(m.homeScore) – \(m.awayScore) \(m.away.code)")
            }
            Divider()
            Button("Open Scorebug") { NSApp.activate(ignoringOtherApps: true) }
            Button("Quit") { NSApp.terminate(nil) }
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
                Label("Primary match", systemImage: "1.circle").tag(SidebarSection.slot(1))
                Label("Secondary match", systemImage: "2.circle").tag(SidebarSection.slot(2))
                Label("Library", systemImage: "books.vertical").tag(SidebarSection.library)
                Label("Settings", systemImage: "gearshape").tag(SidebarSection.settings)
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 210)
            .safeAreaInset(edge: .bottom) {
                HStack(spacing: 6) {
                    Circle().fill(model.serverRunning ? .green : .red).frame(width: 8, height: 8)
                    Text(model.serverStatus).font(.caption).lineLimit(2)
                }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
            }
        } detail: {
            switch section {
            case .slot(let s): SlotView(slot: s).id(s)
            case .library: LibraryView()
            case .settings: SettingsView()
            case nil: Text("Choose a match")
            }
        }
        .alert("Scorebug", isPresented: Binding(get: { model.lastError != nil }, set: { if !$0 { model.lastError = nil } })) {
            Button("OK") { model.lastError = nil }
        } message: { Text(model.lastError ?? "") }
    }
}
