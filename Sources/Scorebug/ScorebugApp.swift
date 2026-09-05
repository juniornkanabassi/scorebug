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
            ContentView().environmentObject(model).frame(minWidth: 1040, minHeight: 700).preferredColorScheme(.dark)
        }
        .defaultSize(width: 1240, height: 820)

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
    @State private var section: SidebarSection = .slot(1)

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 6).fill(Uno.accentGradient).frame(width: 22, height: 22)
                        .overlay(Text("S").font(.system(size: 13, weight: .black)).foregroundStyle(.white))
                    Text("Scorebug").font(.system(size: 15, weight: .bold)).foregroundStyle(Uno.text)
                }.padding(.horizontal, 16).padding(.top, 18).padding(.bottom, 14)
                sidebarItem(.slot(1), "Primary Scorebug", "1.square.fill")
                sidebarItem(.slot(2), "Secondary Scorebug", "2.square.fill")
                sidebarItem(.library, "Library", "books.vertical.fill")
                sidebarItem(.settings, "Settings", "gearshape.fill")
                Spacer()
                HStack(spacing: 6) {
                    Circle().fill(model.serverRunning ? Uno.green : Uno.red).frame(width: 7, height: 7)
                    Text(model.serverStatus).font(.system(size: 11)).foregroundStyle(Uno.muted).lineLimit(2)
                }.padding(14)
            }
            .frame(width: 210).background(Uno.panel)
            Rectangle().fill(Uno.line).frame(width: 1)
            Group {
                switch section {
                case .slot(let s): SlotView(slot: s).id(s)
                case .library: LibraryView()
                case .settings: SettingsView()
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity).background(Uno.bg)
        }
        .background(Uno.bg)
        .alert("Scorebug", isPresented: Binding(get: { model.lastError != nil }, set: { if !$0 { model.lastError = nil } })) {
            Button("OK") { model.lastError = nil }
        } message: { Text(model.lastError ?? "") }
    }

    private func sidebarItem(_ s: SidebarSection, _ title: String, _ symbol: String) -> some View {
        Button { section = s } label: {
            HStack(spacing: 10) {
                Image(systemName: symbol).font(.system(size: 13)).frame(width: 18)
                Text(title).font(.system(size: 13, weight: section == s ? .semibold : .regular))
                Spacer()
            }
            .foregroundStyle(section == s ? Uno.text : Uno.muted)
            .padding(.horizontal, 12).frame(height: 34)
            .background(section == s ? Uno.panel2 : .clear).clipShape(RoundedRectangle(cornerRadius: 8))
        }.buttonStyle(.plain).padding(.horizontal, 8)
    }
}
