// Settings window (Cmd-comma): server, OBS sources, crest folder, data folders.
import SwiftUI
import ScorebugCore

struct SettingsView: View {
    @EnvironmentObject var model: AppModel
    @State private var pickingFolder = false
    @State private var pickingBackdrop = false

    private enum BackdropMode: Hashable { case none, pitch, file }
    /// Read straight from settings rather than a separate `@State`, so cancelling the file importer (which
    /// leaves `previewBackdrop` untouched) snaps the picker back to whatever was actually chosen before.
    private var backdropMode: BackdropMode {
        switch model.settings.previewBackdrop {
        case nil: return .none
        case "pitch": return .pitch
        default: return .file
        }
    }

    var body: some View {
        Form {
            Section("Server") {
                LabeledContent("Status", value: model.serverStatus).scaledFont(.body)
                LabeledContent("Port") {
                    TextField("Port", value: Binding(get: { model.settings.port }, set: { model.settings.port = min(65535, max(1024, $0)) }), format: .number.grouping(.never))
                        .scaledFont(.body).monospacedDigit().textFieldStyle(.roundedBorder).frame(width: 90)
                }.scaledFont(.body).onChange(of: model.settings.port) { _, _ in model.saveSettings() }
                Text("A port change takes effect after Scorebug is relaunched. OBS sources and the Stream Deck plugin default to 8600.").scaledFont(.caption).foregroundStyle(.secondary)
            }
            Section("OBS browser sources") {
                ForEach(["h/1", "h/2", "v/1", "v/2"], id: \.self) { p in
                    LabeledContent(p.hasPrefix("h") ? "1920 × 1080" : "1080 × 1920") { Text("\(model.baseURL)/overlay/\(p)").scaledFont(.body).monospaced().textSelection(.enabled) }
                        .scaledFont(.body)
                }
                Text("Position 0,0, no crop, no scale. Vertical pages go on the Aitum Vertical canvas.").scaledFont(.caption).foregroundStyle(.secondary)
            }
            Section("Overlays") {
                Stepper("Portrait bug top \(String(model.settings.portraitTop)) px", value: $model.settings.portraitTop, in: 0...800, step: 10).scaledFont(.body).onChange(of: model.settings.portraitTop) { _, _ in model.saveSettings() }
                Text("Top edge of the primary bug on the 1080 x 1920 canvas. The secondary bug keeps its distance below it. TikTok draws its own controls in the top 250 px.").scaledFont(.caption).foregroundStyle(.secondary)
            }
            Section("Preview backdrop") {
                Picker("Preview backdrop", selection: Binding(
                    get: { backdropMode },
                    set: { mode in
                        switch mode {
                        case .none: model.settings.previewBackdrop = nil; model.saveSettings()
                        case .pitch: model.settings.previewBackdrop = "pitch"; model.saveSettings()
                        case .file: pickingBackdrop = true
                        }
                    }
                )) {
                    Text("None").tag(BackdropMode.none)
                    Text("Pitch").tag(BackdropMode.pitch)
                    Text("Choose file…").tag(BackdropMode.file)
                }.scaledFont(.body).labelsHidden()
                if backdropMode == .file, let path = model.settings.previewBackdrop {
                    Text(URL(fileURLWithPath: path).lastPathComponent).scaledFont(.body).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                }
                Text("Shown behind the bug in this window's preview only, so club colours can be judged against a real picture; OBS never sees it.").scaledFont(.caption).foregroundStyle(.secondary)
            }
            .fileImporter(isPresented: $pickingBackdrop, allowedContentTypes: [.image, .movie]) { result in
                if case .success(let url) = result {
                    let ok = url.startAccessingSecurityScopedResource(); defer { if ok { url.stopAccessingSecurityScopedResource() } }
                    model.settings.previewBackdrop = url.path
                    model.saveSettings()
                }
            }
            Section("Crests") {
                LabeledContent("Logo folder") {
                    HStack {
                        Text(model.settings.crestFolder ?? "Not set").scaledFont(.body).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                        Button("Choose…") { pickingFolder = true }.scaledFont(.body)
                    }
                }
                .scaledFont(.body)
                Text("Image files are matched to clubs by name, such as PSG.png or Olympique de Marseille.png, and copied into your data folder. Clubs that already have a crest are left alone.").scaledFont(.caption).foregroundStyle(.secondary)
            }
            Section("Folders") {
                LabeledContent("Data") { Text(model.store.directory.path).scaledFont(.body).textSelection(.enabled).lineLimit(1).truncationMode(.middle) }.scaledFont(.body)
                LabeledContent("Overrides") { Text(model.store.overlayOverridesDirectory.path).scaledFont(.body).textSelection(.enabled).lineLimit(1).truncationMode(.middle) }.scaledFont(.body)
                Toggle("Use override folder", isOn: $model.settings.themeOverridesEnabled).scaledFont(.body).onChange(of: model.settings.themeOverridesEnabled) { _, _ in model.saveSettings() }
                Button("Reveal Data Folder in Finder") { NSWorkspace.shared.activateFileViewerSelecting([model.store.directory]) }.scaledFont(.body)
            }
            Section("About") {
                LabeledContent("Scorebug", value: AppInfo.version).scaledFont(.body)
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
