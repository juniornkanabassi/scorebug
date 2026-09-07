// Settings window (Cmd-comma): four plain sections a streamer understands, plus Advanced tucked away.
import SwiftUI
import ScorebugCore

struct SettingsView: View {
    @EnvironmentObject var model: AppModel
    @State private var pickingFolder = false
    @State private var pickingBackdrop = false

    private enum BackdropMode: Hashable { case none, pitch, streamer, file }
    /// Read straight from settings rather than a separate `@State`, so cancelling the file importer (which
    /// leaves `previewBackdrop` untouched) snaps the picker back to whatever was actually chosen before.
    private var backdropMode: BackdropMode {
        switch model.settings.previewBackdrop {
        case nil: return .none
        case "pitch": return .pitch
        case "streamer": return .streamer
        default: return .file
        }
    }

    var body: some View {
        Form {
            Section("OBS") {
                ForEach(["h/1", "h/2", "v/1", "v/2"], id: \.self) { p in
                    LabeledContent(obsRowLabel(p)) {
                        HStack {
                            Text("\(model.baseURL)/overlay/\(p)").scaledFont(.body).monospaced().textSelection(.enabled)
                            Button("Copy") { copy("\(model.baseURL)/overlay/\(p)") }.scaledFont(.body)
                        }
                    }.scaledFont(.body)
                }
                LabeledContent("Port") {
                    TextField("Port", value: Binding(get: { model.settings.port }, set: { model.settings.port = min(65535, max(1024, $0)) }), format: .number.grouping(.never))
                        .scaledFont(.body).monospacedDigit().textFieldStyle(.roundedBorder).frame(width: 90).labelsHidden()
                }.scaledFont(.body).onChange(of: model.settings.port) { _, _ in model.saveSettings() }
                Text("A port change takes effect after Scorebug is restarted.").scaledFont(.caption).foregroundStyle(.secondary)
            }
            Section("Preview") {
                Picker("Backdrop", selection: Binding(
                    get: { backdropMode },
                    set: { mode in
                        switch mode {
                        case .none: model.settings.previewBackdrop = nil; model.saveSettings()
                        case .pitch: model.settings.previewBackdrop = "pitch"; model.saveSettings()
                        case .streamer: model.settings.previewBackdrop = "streamer"; model.saveSettings()
                        case .file: pickingBackdrop = true
                        }
                    }
                )) {
                    Text("None").tag(BackdropMode.none)
                    Text("Pitch").tag(BackdropMode.pitch)
                    Text("Streamer").tag(BackdropMode.streamer)
                    Text("Choose file…").tag(BackdropMode.file)
                }.scaledFont(.body)
                if backdropMode == .file, let path = model.settings.previewBackdrop {
                    LabeledContent("File") { Text(URL(fileURLWithPath: path).lastPathComponent).scaledFont(.body).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle) }.scaledFont(.body)
                }
                Stepper("Portrait bug top \(String(model.settings.portraitTop)) px", value: $model.settings.portraitTop, in: 0...800, step: 10).scaledFont(.body).onChange(of: model.settings.portraitTop) { _, _ in model.saveSettings() }
                Text("Shown behind the bug in this window's preview only, so you can judge colours against a real picture; OBS never sees it.").scaledFont(.caption).foregroundStyle(.secondary)
            }
            .fileImporter(isPresented: $pickingBackdrop, allowedContentTypes: [.image, .movie]) { result in
                if case .success(let url) = result {
                    let ok = url.startAccessingSecurityScopedResource(); defer { if ok { url.stopAccessingSecurityScopedResource() } }
                    model.settings.previewBackdrop = url.path
                    model.saveSettings()
                }
            }
            Section("Crests") {
                LabeledContent("Folder") {
                    HStack {
                        Text(model.settings.crestFolder ?? "Not set").scaledFont(.body).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                        Button("Choose…") { pickingFolder = true }.scaledFont(.body)
                        if let folder = model.settings.crestFolder {
                            Button("Import again") { model.importCrestFolder(URL(fileURLWithPath: folder, isDirectory: true)) }.scaledFont(.body)
                        }
                    }
                }
                .scaledFont(.body)
                Text("Image files are matched to clubs by name and copied into your data folder; clubs that already have a crest are left alone.").scaledFont(.caption).foregroundStyle(.secondary)
            }
            .fileImporter(isPresented: $pickingFolder, allowedContentTypes: [.folder]) { result in
                if case .success(let url) = result {
                    let ok = url.startAccessingSecurityScopedResource(); defer { if ok { url.stopAccessingSecurityScopedResource() } }
                    model.importCrestFolder(url)
                }
            }
            DisclosureGroup("Advanced") {
                LabeledContent("Data folder") { Text(model.store.directory.path).scaledFont(.body).textSelection(.enabled).lineLimit(1).truncationMode(.middle) }.scaledFont(.body)
                Toggle("Use override folder", isOn: $model.settings.themeOverridesEnabled).scaledFont(.body).onChange(of: model.settings.themeOverridesEnabled) { _, _ in model.saveSettings() }
                Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([model.store.directory]) }.scaledFont(.body)
            }.scaledFont(.body)
            Section {
                LabeledContent("Scorebug", value: AppInfo.version).scaledFont(.body)
                Text("© 2026 Junior Nkana Bassi.").scaledFont(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
    }

    /// "h/1", "h/2", "v/1", "v/2" labelled by slot and size, so the two landscape (or two portrait) rows
    /// no longer read identically.
    private func obsRowLabel(_ p: String) -> String {
        let slot = p.hasSuffix("1") ? "Slot 1" : "Slot 2"
        let size = p.hasPrefix("h") ? "1920 × 1080" : "1080 × 1920"
        return "\(slot), \(size)"
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
