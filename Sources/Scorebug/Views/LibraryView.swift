// Competitions and clubs. Codes per competition, colours and crest import.
// The Clubs tab: search, tick-menu filters, removable chips, List/Icons view modes. See LibraryFilters.swift.
import SwiftUI
import ScorebugCore
import UniformTypeIdentifiers

struct LibraryView: View {
    @EnvironmentObject var model: AppModel
    @State private var selected: UUID?
    @State private var mode = 0
    @State private var selectedCompetition: String?

    @State private var search = ""
    @State private var selectedCompetitions: Set<String> = []
    @State private var selectedConfederations: Set<String> = []
    @State private var clubsNationsFilter: ClubsNationsFilter = .all
    @AppStorage("libraryViewMode") private var viewMode: LibraryViewMode = .list

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $mode) { Text("Clubs").tag(0); Text("Competitions").tag(1) }.pickerStyle(.segmented).labelsHidden().frame(width: 260).padding(10)
            if mode == 1 { competitions } else { clubsSplit }
        }
        .navigationTitle("Library")
    }

    // MARK: Competitions tab (unchanged)

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

    // MARK: Clubs tab

    private var filteredClubs: [Club] {
        model.library.clubs
            .filter { matchesSearch($0) && matchesCompetitions($0) && matchesConfederations($0) && matchesClubsNations($0) }
            .sorted { $0.name < $1.name }
    }

    private func matchesSearch(_ club: Club) -> Bool {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return true }
        if club.name.lowercased().contains(q) || club.shortName.lowercased().contains(q) || club.defaultCode.lowercased().contains(q) { return true }
        if club.codes.values.contains(where: { $0.lowercased().contains(q) }) { return true }
        let playedIn = model.library.competitions.filter { club.competitionIds.contains($0.id) }.flatMap { [$0.name, $0.shortName] }
        return playedIn.contains { $0.lowercased().contains(q) }
    }

    private func matchesCompetitions(_ club: Club) -> Bool {
        selectedCompetitions.isEmpty || !selectedCompetitions.isDisjoint(with: Set(club.competitionIds))
    }

    private func matchesConfederations(_ club: Club) -> Bool {
        selectedConfederations.isEmpty || (club.confederation.map { selectedConfederations.contains($0) } ?? false)
    }

    private func matchesClubsNations(_ club: Club) -> Bool {
        switch clubsNationsFilter {
        case .all: return true
        case .clubs: return !club.competitionIds.contains("international")
        case .nations: return club.competitionIds.contains("international")
        }
    }

    /// Confederations actually present on a club in the library, canonical order first.
    private var confederationsPresent: [String] {
        let present = Set(model.library.clubs.compactMap { $0.confederation })
        return LibraryFilters.confederationOrder.filter { present.contains($0) } + present.subtracting(LibraryFilters.confederationOrder).sorted()
    }

    private var hasActiveFilters: Bool {
        !selectedCompetitions.isEmpty || !selectedConfederations.isEmpty || clubsNationsFilter != .all
    }

    private func bindingFor(_ value: String, in set: Binding<Set<String>>) -> Binding<Bool> {
        Binding(get: { set.wrappedValue.contains(value) }, set: { on in if on { set.wrappedValue.insert(value) } else { set.wrappedValue.remove(value) } })
    }

    private var clubsSplit: some View {
        HSplitView {
            VStack(spacing: 0) {
                searchField
                filterControls
                if hasActiveFilters { chipsRow }
                countsRow
                Divider()
                Group { if viewMode == .list { clubList } else { clubGrid } }
                Divider()
                addRemoveRow
            }
            .frame(minWidth: 300, idealWidth: 340)
            .background(shortcutButtons)
            Group {
                if let id = selected, let club = model.library.clubs.first(where: { $0.id == id }) {
                    ClubEditor(club: club).id(id)
                } else {
                    ContentUnavailableView("Choose a club", systemImage: "shield")
                }
            }.frame(minWidth: 420)
        }
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search clubs and nations", text: $search).textFieldStyle(.plain)
            if !search.isEmpty {
                Button { search = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
            }
        }
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .controlBackgroundColor)))
        .padding(.horizontal, 10).padding(.top, 10)
    }

    private var filterControls: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Menu {
                    ForEach(model.library.competitions) { comp in
                        Toggle(isOn: bindingFor(comp.id, in: $selectedCompetitions)) {
                            HStack { CompetitionMark(competition: comp, size: 16); Text(comp.name) }
                        }
                    }
                    if !selectedCompetitions.isEmpty {
                        Divider()
                        Button("Show All Competitions") { selectedCompetitions.removeAll() }
                    }
                } label: {
                    Label("Competitions", systemImage: "trophy")
                }

                Menu {
                    ForEach(confederationsPresent, id: \.self) { conf in
                        Toggle(conf, isOn: bindingFor(conf, in: $selectedConfederations))
                    }
                    if !selectedConfederations.isEmpty {
                        Divider()
                        Button("Show All Nations") { selectedConfederations.removeAll() }
                    }
                } label: {
                    Label("Nations", systemImage: "globe")
                }.disabled(confederationsPresent.isEmpty)

                Spacer()

                Picker("", selection: $viewMode) {
                    Image(systemName: "list.bullet").tag(LibraryViewMode.list)
                    Image(systemName: "square.grid.2x2").tag(LibraryViewMode.icons)
                }.pickerStyle(.segmented).labelsHidden().frame(width: 76)
            }

            Picker("", selection: $clubsNationsFilter) {
                ForEach(ClubsNationsFilter.allCases) { f in Text(f.title).tag(f) }
            }.pickerStyle(.segmented).labelsHidden()
        }
        .padding(.horizontal, 10).padding(.top, 8)
    }

    private var chipsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(model.library.competitions.filter { selectedCompetitions.contains($0.id) }) { comp in
                    FilterChip(label: comp.shortName) { selectedCompetitions.remove(comp.id) }
                }
                ForEach(confederationsPresent.filter { selectedConfederations.contains($0) }, id: \.self) { conf in
                    FilterChip(label: conf) { selectedConfederations.remove(conf) }
                }
                if clubsNationsFilter != .all {
                    FilterChip(label: clubsNationsFilter.title) { clubsNationsFilter = .all }
                }
            }.padding(.horizontal, 10)
        }
        .padding(.top, 6)
    }

    private var countsRow: some View {
        Text("\(model.library.clubs.count) clubs and nations, \(model.library.clubs.filter { $0.crestFile != nil }.count) with crests, \(filteredClubs.count) shown")
            .font(.caption).foregroundStyle(.secondary)
            .padding(.horizontal, 10).padding(.vertical, 6)
    }

    private func clubCompetitions(_ club: Club) -> [Competition] {
        Array(model.library.competitions.filter { club.competitionIds.contains($0.id) }.prefix(4))
    }

    private func crestThumb(_ club: Club, size: CGFloat = 20) -> some View {
        Group {
            if let f = club.crestFile, let img = NSImage(contentsOf: model.store.crestsDirectory.appendingPathComponent(f)) {
                Image(nsImage: img).resizable().scaledToFit()
            } else {
                Circle().fill(Color(hex: club.primaryColour))
                    .overlay(Text(String(club.defaultCode.prefix(2))).font(.system(size: size * 0.32, weight: .bold)).foregroundStyle(Color(hex: club.textColour)))
            }
        }.frame(width: size, height: size)
    }

    private var clubList: some View {
        List(filteredClubs, selection: $selected) { club in
            HStack(spacing: 10) {
                crestThumb(club)
                Text(club.name)
                Spacer()
                Text(club.defaultCode).foregroundStyle(.secondary).monospaced()
                HStack(spacing: 2) { ForEach(clubCompetitions(club)) { comp in CompetitionMark(competition: comp, size: 14) } }
            }
            .tag(club.id)
            .padding(.vertical, 2)
        }
    }

    private var clubGrid: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 96, maximum: 112), spacing: 12)], spacing: 12) {
                ForEach(filteredClubs) { club in clubTile(club) }
            }.padding(10)
        }
    }

    private func clubTile(_ club: Club) -> some View {
        let isSelected = selected == club.id
        return VStack(spacing: 6) {
            crestThumb(club, size: 56)
            Text(club.name).font(.caption).multilineTextAlignment(.center).lineLimit(2).minimumScaleFactor(0.8)
            Text(club.defaultCode).font(.caption2).foregroundStyle(.secondary).monospaced()
        }
        .padding(8)
        .frame(width: 96, height: 96)
        .background(RoundedRectangle(cornerRadius: 10).fill(isSelected ? Color.accentColor.opacity(0.18) : Color.clear))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 1.5))
        .contentShape(Rectangle())
        .onTapGesture { selected = club.id }
    }

    private var addRemoveRow: some View {
        HStack {
            Button { let c = Club(name: "New club", shortName: "New", defaultCode: "NEW", primaryColour: "#333333"); model.upsertClub(c); selected = c.id } label: { Image(systemName: "plus") }
            Button { if let id = selected { model.deleteClub(id); selected = nil } } label: { Image(systemName: "minus") }.disabled(selected == nil)
            Spacer()
        }.padding(8)
    }

    /// Invisible buttons so Cmd-1 and Cmd-2 switch view mode, matching the segmented control.
    private var shortcutButtons: some View {
        Group {
            Button("") { viewMode = .list }.keyboardShortcut("1", modifiers: .command)
            Button("") { viewMode = .icons }.keyboardShortcut("2", modifiers: .command)
        }
        .opacity(0)
        .frame(width: 0, height: 0)
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
    @State private var squadText: String

    init(club: Club) {
        _club = State(initialValue: club)
        _squadText = State(initialValue: (club.squad ?? []).joined(separator: "\n"))
    }

    var body: some View {
        Form {
            Section("Club") {
                TextField("Full name", text: $club.name)
                TextField("Short name", text: $club.shortName)
                TextField("Default code", text: $club.defaultCode)
            }
            if club.competitionIds.contains("international") {
                Section("Confederation") {
                    Picker("Confederation", selection: Binding(get: { club.confederation ?? "" }, set: { club.confederation = $0.isEmpty ? nil : $0 })) {
                        Text("None").tag("")
                        ForEach(LibraryFilters.confederationOrder, id: \.self) { conf in Text(conf).tag(conf) }
                    }
                }
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
            Section("Squad") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("One player per line, formatted \"K. Mbappé\". Used for the scorer picker.").font(.caption).foregroundStyle(.secondary)
                    TextEditor(text: $squadText).font(.body).frame(minHeight: 140).overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(nsColor: .separatorColor)))
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
        .onChange(of: squadText) { _, new in
            let lines = new.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            club.squad = lines.isEmpty ? nil : lines
        }
        .onChange(of: club) { _, new in model.upsertClub(new) }
    }
}
