// Native Settings window, organised by the task each group supports.
import SwiftUI
import ScorebugCore

enum SettingsTab: String, CaseIterable { case obs, liveData, advanced }

struct SettingsView: View {
    @AppStorage("settingsTab") private var savedTab = SettingsTab.obs.rawValue
    private let initialTab: SettingsTab?
    init(initialTab: SettingsTab? = nil) { self.initialTab = initialTab }
    private var selectedTab: Binding<SettingsTab> {
        Binding(get: { initialTab ?? SettingsTab(rawValue: savedTab) ?? .obs },
                set: { savedTab = $0.rawValue })
    }
    @EnvironmentObject var model: AppModel
    @Environment(\.appearsActive) private var appearsActive
    @State private var pickingFolder = false
    @State private var pickingBackdrop = false
    @State private var footballDataKey = ""
    /// Nil until the first time Settings is shown; never read in the initialiser, which runs on every App.body pass.
    @State private var keyStatus: String?
    @State private var copiedURL: String?
    @State private var copyReset: Task<Void, Never>?

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
        TabView(selection: selectedTab) {
            obsSettings.tabItem { Label("OBS", systemImage: "tv") }.tag(SettingsTab.obs)
            liveSettings.tabItem { Label("Live Data", systemImage: "antenna.radiowaves.left.and.right") }.tag(SettingsTab.liveData)
            advancedSettings.tabItem { Label("Advanced", systemImage: "gearshape.2") }.tag(SettingsTab.advanced)
        }
        .frame(width: 640, height: contentHeight)
        .appErrorAlert(model: model, inSettings: true)
        .onChange(of: appearsActive, initial: true) { _, active in model.settingsIsActive = active }
        .onDisappear {
            model.settingsIsActive = false
            // An error Settings owned moves to the main window rather than vanishing with it.
            model.errorInSettings = false
            copyReset?.cancel()
        }
        .overlay { if GridOverlay.enabled { GridOverlay() } }
        .task { await loadKeyStatus() }
    }

    // Grouped forms scroll above 640 pt; shorter tabs resize with the reading scale.
    private var contentHeight: CGFloat {
        let base: CGFloat
        switch selectedTab.wrappedValue {
        case .obs: base = 520
        case .liveData: base = 320
        case .advanced: base = 360
        }
        return min(640, (base * model.zoomScale / 4).rounded(.up) * 4)
    }

    private var obsSettings: some View {
        Form {
            Section("OBS") {
                ForEach(["h/1", "h/2", "v/1", "v/2"], id: \.self) { p in
                    LabeledContent(obsRowLabel(p)) {
                        HStack(spacing: Space.sm) {
                            Text("/overlay/\(p)").scaledFont(.body).monospaced().lineLimit(1).textSelection(.enabled)
                                .help("\(model.baseURL)/overlay/\(p)")
                            Button(copiedURL == "\(model.baseURL)/overlay/\(p)" ? "Copied" : "Copy") { copy("\(model.baseURL)/overlay/\(p)") }.scaledFont(.body)
                                .accessibilityLabel("Copy OBS URL for \(obsRowLabel(p))")
                        }
                    }.scaledFont(.body)
                }
                Text("Landscape: 1920 × 1080\nPortrait: 1080 × 1920")
                    .scaledFont(.caption).foregroundStyle(.primary).fixedSize(horizontal: false, vertical: true)
                LabeledContent("Port") {
                    TextField("Port", value: Binding(get: { model.settings.port }, set: { model.settings.port = min(65535, max(1024, $0)) }), format: .number.grouping(.never))
                        .scaledFont(.body).monospacedDigit().textFieldStyle(.roundedBorder).frame(width: 92).labelsHidden().accessibilityLabel("Server port")
                }.scaledFont(.body).onChange(of: model.settings.port) { _, _ in model.saveSettings() }
                Text("Use a port from 1024 to 65535. Restart Scorebug after changing it.").scaledFont(.caption).foregroundStyle(.secondary)
            }
            Section("Overlay position and preview") {
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
                Text("The backdrop appears only in this window. OBS never sees it.").scaledFont(.caption).foregroundStyle(.secondary)
                Stepper("Portrait top position: \(model.settings.portraitTop) px", value: $model.settings.portraitTop, in: 0...800, step: 10).scaledFont(.body).onChange(of: model.settings.portraitTop) { _, _ in model.saveSettings() }
                Text("Moves the score bug down from the top of the portrait overlay, including in OBS.").scaledFont(.caption).foregroundStyle(.secondary)
            }
            .fileImporter(isPresented: $pickingBackdrop, allowedContentTypes: [.image, .movie]) { result in
                if case .success(let url) = result {
                    let ok = url.startAccessingSecurityScopedResource(); defer { if ok { url.stopAccessingSecurityScopedResource() } }
                    model.settings.previewBackdrop = url.path
                    model.saveSettings()
                }
            }
        }.formStyle(.grouped)
    }

    private var liveSettings: some View {
        Form {
            Section("Fixtures") {
                LabeledContent("football-data.org key") {
                    SecureField("Paste key here", text: $footballDataKey).scaledFont(.body)
                        .textFieldStyle(.roundedBorder).frame(minWidth: 160)
                        .accessibilityLabel("football-data.org API key")
                }.scaledFont(.body)
                HStack(spacing: Space.sm) {
                    Button("Save") {
                        do { try KeychainStore.set(footballDataKey); footballDataKey = ""; keyStatus = "Key saved securely" }
                        catch { keyStatus = "Could not save key: \(error.localizedDescription)" }
                    }.disabled(footballDataKey.isEmpty).scaledFont(.body)
                    Button("Remove") {
                        do { try KeychainStore.delete(); keyStatus = "No key, using ESPN only" }
                        catch { keyStatus = "Could not remove key: \(error.localizedDescription)" }
                    }.scaledFont(.body)
                    Text(keyStatus ?? "Checking saved key…").scaledFont(.caption).foregroundStyle(.secondary)
                }
            }
            Section("Live data") {
                ForEach(["ESPN", "FotMob", "SofaScore"], id: \.self) { source in
                    LabeledContent(source) {
                        HStack(spacing: Space.sm) {
                            Text(sourceStatus(source)).scaledFont(.caption).foregroundStyle(.primary).lineLimit(1)
                                .help(model.liveSourceStatus[source] ?? "Not checked")
                            Toggle("Use \(source)", isOn: Binding(
                                get: { model.settings.liveSourceEnabled[source] ?? false },
                                set: { model.setLiveSource(source, enabled: $0) }
                            ))
                            .labelsHidden().toggleStyle(.switch).disabled(source == "SofaScore")
                            .accessibilityLabel("Use \(source) live data")
                        }
                    }.scaledFont(.body)
                }
                Text("ESPN is primary. FotMob cross-checks goal counts. SofaScore is unavailable from this network.")
                    .scaledFont(.caption).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped)
    }

    private var advancedSettings: some View {
        Form {
            Section("Crests") {
                LabeledContent("Folder") {
                    HStack(spacing: Space.sm) {
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
            Section("Advanced") {
                LabeledContent("Data folder") { Text(model.store.directory.path).scaledFont(.body).textSelection(.enabled).lineLimit(1).truncationMode(.middle) }.scaledFont(.body)
                Toggle("Use my own overlay designs", isOn: $model.settings.themeOverridesEnabled).scaledFont(.body).onChange(of: model.settings.themeOverridesEnabled) { _, _ in model.saveSettings() }
                Text("Loads your designs from the overlays folder inside the data folder. Turn this off to use Scorebug’s built-in designs.").scaledFont(.caption).foregroundStyle(.secondary)
                Button("Show Data Folder in Finder") { NSWorkspace.shared.activateFileViewerSelecting([model.store.directory]) }.scaledFont(.body)
            }.scaledFont(.body)
            Section {
                LabeledContent("Scorebug", value: AppInfo.version).scaledFont(.body)
                Text("© 2026 Junior Nkana Bassi.").scaledFont(.caption).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped)
    }

    private func loadKeyStatus() async {
        guard keyStatus == nil else { return }
        // Snapshot and other disposable runs must never touch the Keychain.
        guard !NativeSnapshots.isRequested else { keyStatus = "No key needed for this preview"; return }
        guard model.options.dataDirectory == Store.defaultDirectory() else { keyStatus = "Key unavailable in this test copy"; return }
        let saved = await Task.detached(priority: .userInitiated) { KeychainStore.get() != nil }.value
        // Save or Remove may have finished first; their result wins.
        guard keyStatus == nil else { return }
        keyStatus = saved ? "Key saved securely" : "No key, using ESPN only"
    }

    /// "h/1", "h/2", "v/1", "v/2" labelled by slot and size, so the two landscape (or two portrait) rows
    /// no longer read identically.
    private func obsRowLabel(_ p: String) -> String {
        let slot = p.hasSuffix("1") ? "Primary" : "Secondary"
        let size = p.hasPrefix("h") ? "landscape" : "portrait"
        return "\(slot), \(size)"
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        copiedURL = text
        copyReset?.cancel()
        copyReset = Task { @MainActor in
            do { try await Task.sleep(nanoseconds: 2_000_000_000) }
            catch { return }
            copiedURL = nil
        }
    }

    private func sourceStatus(_ source: String) -> String {
        let status = model.liveSourceStatus[source] ?? "Not checked"
        if source == "SofaScore" { return "Unavailable from this network" }
        if status.hasPrefix("Lookup failed") || status.hasPrefix("Error:") { return "Unable to connect. Try again later." }
        return status
    }
}
