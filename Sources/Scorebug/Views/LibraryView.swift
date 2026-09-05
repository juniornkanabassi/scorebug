// Competitions and clubs. Codes per competition, colours and crest import.
import SwiftUI
import ScorebugCore
import UniformTypeIdentifiers

struct LibraryView: View {
    @EnvironmentObject var model: AppModel
    @State private var selected: UUID?
    @State private var filter = ""

    private var clubs: [Club] {
        model.library.clubs.filter { filter.isEmpty || $0.name.localizedCaseInsensitiveContains(filter) }.sorted { $0.name < $1.name }
    }

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                TextField("Filter clubs", text: $filter).textFieldStyle(.roundedBorder).padding(8)
                List(clubs, selection: $selected) { club in
                    HStack {
                        Circle().fill(Color(hex: club.primaryColour)).frame(width: 12, height: 12)
                        Text(club.name)
                        Spacer()
                        Text(club.defaultCode).foregroundStyle(.secondary).monospaced()
                    }.tag(club.id)
                }
                HStack {
                    Button { let c = Club(name: "New club", shortName: "New", defaultCode: "NEW", primaryColour: "#333333"); model.upsertClub(c); selected = c.id } label: { Image(systemName: "plus") }
                    Button { if let id = selected { model.deleteClub(id); selected = nil } } label: { Image(systemName: "minus") }.disabled(selected == nil)
                    Spacer()
                }.padding(8)
            }.frame(minWidth: 260, idealWidth: 300)
            Group {
                if let id = selected, let club = model.library.clubs.first(where: { $0.id == id }) {
                    ClubEditor(club: club)
                } else {
                    Text("Choose a club").foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }.frame(minWidth: 420)
        }
        .navigationTitle("Library")
    }
}

struct ClubEditor: View {
    @EnvironmentObject var model: AppModel
    @State var club: Club
    @State private var importing = false

    var body: some View {
        Form {
            Section("Club") {
                TextField("Full name", text: $club.name)
                TextField("Short name", text: $club.shortName)
                TextField("Default code", text: $club.defaultCode)
            }
            Section("Code per competition") {
                ForEach(model.library.competitions) { comp in
                    TextField(comp.name, text: Binding(
                        get: { club.codes[comp.id] ?? "" },
                        set: { v in let t = v.uppercased().trimmingCharacters(in: .whitespaces); if t.isEmpty { club.codes[comp.id] = nil } else { club.codes[comp.id] = t } }))
                    .help("Leave empty to use the default code")
                }
            }
            Section("Colours") {
                ColorPicker("Primary", selection: Binding(get: { Color(hex: club.primaryColour) }, set: { club.primaryColour = $0.hexString }))
                ColorPicker("Secondary", selection: Binding(get: { Color(hex: club.secondaryColour) }, set: { club.secondaryColour = $0.hexString }))
                ColorPicker("Text on primary", selection: Binding(get: { Color(hex: club.textColour) }, set: { club.textColour = $0.hexString }))
            }
            Section("Crest") {
                HStack {
                    if let file = club.crestFile, let img = NSImage(contentsOf: model.store.crestsDirectory.appendingPathComponent(file)) {
                        Image(nsImage: img).resizable().scaledToFit().frame(width: 48, height: 48)
                    } else { Text("No crest").foregroundStyle(.secondary) }
                    Button("Import image") { importing = true }
                }
            }
            Section("Competitions") {
                ForEach(model.library.competitions) { comp in
                    Toggle(comp.name, isOn: Binding(
                        get: { club.competitionIds.contains(comp.id) },
                        set: { on in if on { club.competitionIds.append(comp.id) } else { club.competitionIds.removeAll { $0 == comp.id } } }))
                }
            }
        }
        .formStyle(.grouped)
        .fileImporter(isPresented: $importing, allowedContentTypes: [.png, .svg, .jpeg, .webP]) { result in
            if case .success(let url) = result {
                let ok = url.startAccessingSecurityScopedResource(); defer { if ok { url.stopAccessingSecurityScopedResource() } }
                model.importCrest(from: url, for: club.id)
                if let updated = model.library.clubs.first(where: { $0.id == club.id }) { club.crestFile = updated.crestFile }
            }
        }
        .onChange(of: club) { _, new in model.upsertClub(new) }
    }
}

extension Color {
    init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces); if s.hasPrefix("#") { s.removeFirst() }
        var v: UInt64 = 0; Scanner(string: s).scanHexInt64(&v)
        let r = Double((v >> 16) & 0xFF) / 255, g = Double((v >> 8) & 0xFF) / 255, b = Double(v & 0xFF) / 255
        self.init(.sRGB, red: r, green: g, blue: b, opacity: 1)
    }
    var hexString: String {
        let c = NSColor(self).usingColorSpace(.sRGB) ?? .black
        return String(format: "#%02X%02X%02X", Int(round(c.redComponent * 255)), Int(round(c.greenComponent * 255)), Int(round(c.blueComponent * 255)))
    }
}
