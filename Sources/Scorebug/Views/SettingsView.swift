// Settings window (Cmd-comma): server, OBS sources, crest folder, data folders.
import SwiftUI
import ScorebugCore

struct SettingsView: View {
    @EnvironmentObject var model: AppModel
    @State private var pickingFolder = false

    var body: some View {
        Form {
            Section("Server") {
                LabeledContent("Status", value: model.serverStatus)
                Stepper("Port \(String(model.settings.port))", value: $model.settings.port, in: 1024...65535).onChange(of: model.settings.port) { _, _ in model.saveSettings() }
                Text("A port change takes effect after Scorebug is relaunched. OBS sources and the Stream Deck plugin default to 8600.").scaledFont(.caption).foregroundStyle(.secondary)
            }
            Section("OBS browser sources") {
                ForEach(["h/1", "h/2", "v/1", "v/2"], id: \.self) { p in
                    LabeledContent(p.hasPrefix("h") ? "1920 × 1080" : "1080 × 1920") { Text("\(model.baseURL)/overlay/\(p)").scaledFont(.body).monospaced().textSelection(.enabled) }
                }
                Text("Position 0,0, no crop, no scale. Vertical pages go on the Aitum Vertical canvas.").scaledFont(.caption).foregroundStyle(.secondary)
            }
            Section("Overlays") {
                Stepper("Portrait bug top \(String(model.settings.portraitTop)) px", value: $model.settings.portraitTop, in: 0...800, step: 10).onChange(of: model.settings.portraitTop) { _, _ in model.saveSettings() }
                Text("Top edge of the primary bug on the 1080 x 1920 canvas. The secondary bug keeps its distance below it. TikTok draws its own controls in the top 250 px.").scaledFont(.caption).foregroundStyle(.secondary)
            }
            Section("Crests") {
                LabeledContent("Logo folder") {
                    HStack {
                        Text(model.settings.crestFolder ?? "Not set").foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                        Button("Choose…") { pickingFolder = true }
                    }
                }
                Text("Image files are matched to clubs by name, such as PSG.png or Olympique de Marseille.png, and copied into your data folder. Clubs that already have a crest are left alone.").scaledFont(.caption).foregroundStyle(.secondary)
            }
            Section("Folders") {
                LabeledContent("Data") { Text(model.store.directory.path).textSelection(.enabled).lineLimit(1).truncationMode(.middle) }
                LabeledContent("Overrides") { Text(model.store.overlayOverridesDirectory.path).textSelection(.enabled).lineLimit(1).truncationMode(.middle) }
                Toggle("Use override folder", isOn: $model.settings.themeOverridesEnabled).onChange(of: model.settings.themeOverridesEnabled) { _, _ in model.saveSettings() }
                Button("Reveal Data Folder in Finder") { NSWorkspace.shared.activateFileViewerSelecting([model.store.directory]) }
            }
            Section("About") {
                LabeledContent("Scorebug", value: AppInfo.version)
                Text("© 2026 Junior Nkana Bassi.").scaledFont(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
        .fileImporter(isPresented: $pickingFolder, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result {
                let ok = url.startAccessingSecurityScopedResource(); defer { if ok { url.stopAccessingSecurityScopedResource() } }
                model.importCrestFolder(url)
            }
        }
    }
}
