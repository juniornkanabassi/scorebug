// Port, folders, crest import and the OBS source list.
import SwiftUI
import ScorebugCore

struct SettingsView: View {
    @EnvironmentObject var model: AppModel
    @State private var pickingFolder = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                SectionTitle(text: "Server")
                FieldRow(label: "Status") { Text(model.serverStatus).font(.system(size: 13)).foregroundStyle(Uno.muted) }
                FieldRow(label: "Port") {
                    ValueBox(text: "\(model.settings.port)")
                    RoundButton(symbol: "minus") { model.settings.port = max(1024, model.settings.port - 1); model.saveSettings() }
                    RoundButton(symbol: "plus") { model.settings.port = min(65535, model.settings.port + 1); model.saveSettings() }
                    Text("takes effect after relaunch").font(.system(size: 12)).foregroundStyle(Uno.muted)
                }
                SectionTitle(text: "OBS browser sources")
                ForEach(["h/1", "h/2", "v/1", "v/2"], id: \.self) { p in
                    FieldRow(label: p.hasPrefix("h") ? "1920 x 1080" : "1080 x 1920") {
                        Text("\(model.baseURL)/overlay/\(p)").font(.system(size: 13, design: .monospaced)).foregroundStyle(Uno.text).textSelection(.enabled)
                    }
                }
                Text("Position 0,0, no crop, no scale. Vertical pages go on the Aitum Vertical canvas.").font(.system(size: 12)).foregroundStyle(Uno.muted)
                SectionTitle(text: "Crests")
                FieldRow(label: "Logo folder") {
                    Text(model.settings.crestFolder ?? "not set").font(.system(size: 12)).foregroundStyle(Uno.muted).lineLimit(1).truncationMode(.middle).frame(maxWidth: 360, alignment: .leading)
                    UnoPill(title: "Choose and import") { pickingFolder = true }
                }
                Text("Matches PNG or SVG files to clubs by name, for example \"PSG.png\" or \"Olympique de Marseille.png\", and copies them into your data folder. Clubs that already have a crest are left alone.").font(.system(size: 12)).foregroundStyle(Uno.muted)
                SectionTitle(text: "Folders")
                FieldRow(label: "Data") { Text(model.store.directory.path).font(.system(size: 12)).foregroundStyle(Uno.muted).textSelection(.enabled) }
                FieldRow(label: "Overrides") { Text(model.store.overlayOverridesDirectory.path).font(.system(size: 12)).foregroundStyle(Uno.muted).textSelection(.enabled) }
                FieldRow(label: "") { UnoPill(title: "Reveal data folder") { NSWorkspace.shared.activateFileViewerSelecting([model.store.directory]) } }
            }
            .frame(maxWidth: 720).padding(24).frame(maxWidth: .infinity)
        }
        .background(Uno.bg)
        .fileImporter(isPresented: $pickingFolder, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result {
                let ok = url.startAccessingSecurityScopedResource(); defer { if ok { url.stopAccessingSecurityScopedResource() } }
                model.importCrestFolder(url)
            }
        }
    }
}
