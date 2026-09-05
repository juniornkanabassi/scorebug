// Port, data folder, overlay override folder.
import SwiftUI
import ScorebugCore

struct SettingsView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        Form {
            Section("Server") {
                LabeledContent("Status", value: model.serverStatus)
                Stepper("Port \(model.settings.port)", value: $model.settings.port, in: 1024...65535).onChange(of: model.settings.port) { _, _ in model.saveSettings() }
                Text("A port change takes effect after Scorebug is relaunched. OBS sources and the Stream Deck plugin default to 8600.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Folders") {
                LabeledContent("Data") { Text(model.store.directory.path).textSelection(.enabled) }
                LabeledContent("Bundled overlays") { Text(model.resolver.bundled.path).textSelection(.enabled) }
                LabeledContent("Overrides") { Text(model.store.overlayOverridesDirectory.path).textSelection(.enabled) }
                Toggle("Use override folder", isOn: $model.settings.themeOverridesEnabled).onChange(of: model.settings.themeOverridesEnabled) { _, _ in model.saveSettings() }
                Button("Reveal data folder in Finder") { NSWorkspace.shared.activateFileViewerSelecting([model.store.directory]) }
            }
            Section("OBS browser sources") {
                ForEach(["h/1", "h/2", "v/1", "v/2"], id: \.self) { p in
                    LabeledContent(p.hasPrefix("h") ? "1920 x 1080" : "1080 x 1920") { Text("\(model.baseURL)/overlay/\(p)").textSelection(.enabled) }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
    }
}
