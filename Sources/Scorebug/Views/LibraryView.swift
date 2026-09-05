// Competitions and clubs. Codes per competition, colours and crest import.
import SwiftUI
import ScorebugCore
import UniformTypeIdentifiers

struct LibraryView: View {
    @EnvironmentObject var model: AppModel
    @State private var selected: UUID?
    @State private var filter = ""
    @State private var mode = 0
    @State private var selectedCompetition: String?

    private var clubs: [Club] {
        model.library.clubs.filter { filter.isEmpty || $0.name.localizedCaseInsensitiveContains(filter) }.sorted { $0.name < $1.name }
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $mode) { Text("Clubs").tag(0); Text("Competitions").tag(1) }.pickerStyle(.segmented).labelsHidden().frame(width: 260).padding(10)
            if mode == 1 { competitions } else { clubsSplit }
        }
        .navigationTitle("Library")
    }

    private var competitions: some View {
        HSplitView {
            List(model.library.competitions, selection: $selectedCompetition) { c in
                HStack { CompetitionMark(competition: c, size: 22); Text(c.name); Spacer(); Text(c.shortName).foregroundStyle(.secondary) }.tag(c.id)
            }.frame(minWidth: 260, idealWidth: 300)
            Group {
                if let id = selectedCompetition, let c = model.library.competitions.first(where: { $0.id == id }) { CompetitionEditor(competition: c).id(id) }
                else { ContentUnavailableView("Choose a competition", systemImage: "trophy") }
            }.frame(minWidth: 420)
        }
    }

    private var clubsSplit: some View {
        HSplitView {
            VStack(spacing: 0) {
                TextField("Filter clubs", text: $filter).textFieldStyle(.roundedBorder).padding(8)
                Text("\(model.library.clubs.count) clubs and nations, \(model.library.clubs.filter { $0.crestFile != nil }.count) with crests").font(.caption).foregroundStyle(.secondary).padding(.bottom, 4)
                List(clubs, selection: $selected) { club in
                    HStack {
                        if let f = club.crestFile, let img = NSImage(contentsOf: model.store.crestsDirectory.appendingPathComponent(f)) {
                            Image(nsImage: img).resizable().scaledToFit().frame(width: 18, height: 18)
                        } else { Circle().fill(Color(hex: club.primaryColour)).frame(width: 12, height: 12).frame(width: 18) }
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
    }
}

struct CompetitionEditor: View {
    @EnvironmentObject var model: AppModel
    @State var competition: Competition
    @State private var importing = false
    var body: some View {
        Form {
            Section("Competition") {
                TextField("Name", text: $competition.name)
                TextField("Short name", text: $competition.shortName)
                Picker("Score bug design", selection: $competition.themeId) {
                    ForEach(model.resolver.availableThemeIds(), id: \.self) { id in Text(model.resolver.themeConfig(id: id)?.name ?? id).tag(id) }
                }
            }
            Section("Official mark") {
                HStack(spacing: 14) {
                    CompetitionMark(competition: competition, size: 56)
                    VStack(alignment: .leading, spacing: 4) {
                        Button("Import Image…") { importing = true }
                        Text("A PNG or SVG with transparency. Shown in the app and on the bug in place of the drawn mark, for example the lion roundel or the starball.").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .fileImporter(isPresented: $importing, allowedContentTypes: [.png, .svg, .jpeg, .webP]) { result in
            if case .success(let url) = result {
                let ok = url.startAccessingSecurityScopedResource(); defer { if ok { url.stopAccessingSecurityScopedResource() } }
                model.importCompetitionLogo(from: url, for: competition.id)
                if let c = model.library.competitions.first(where: { $0.id == competition.id }) { competition.logoFile = c.logoFile }
            }
        }
        .onChange(of: competition) { _, new in model.updateCompetition(new) }
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

