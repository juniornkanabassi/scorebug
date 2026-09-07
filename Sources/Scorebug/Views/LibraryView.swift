// Team Library: competitions and clubs. Codes per competition, colours and crest import.
// The Clubs tab: search, a Competitions tick-menu, Clubs/National teams/All, List/Icons. See LibraryFilters.swift.
import SwiftUI
import ScorebugCore
import UniformTypeIdentifiers
import ImageIO
import AppKit

struct LibraryView: View {
    @EnvironmentObject var model: AppModel
    @State private var selected: UUID?
    @State private var mode = 0
    @State private var selectedCompetition: String?
    @State private var competitionSearch = ""

    @State private var search = ""
    @State private var selectedCompetitions: Set<String> = []
    @State private var clubsNationsFilter: ClubsNationsFilter = .all
    @State private var confirmDelete: Club?
    @AppStorage("libraryViewMode") private var viewMode: LibraryViewMode = .list

    var body: some View {
        Group { if mode == 1 { competitions } else { clubsSplit } }
            .navigationTitle("Team Library")
    }

    /// The Clubs/Competitions switch, now in the list column's own header (was a full-width bar above the
    /// split view, wasting the width the detail pane could otherwise use at a wide window).
    private var modePicker: some View {
        Picker("", selection: $mode) { Text("Clubs").tag(0); Text("Competitions").tag(1) }
            .scaledFont(.body).pickerStyle(.segmented).labelsHidden().padding(10)
    }

    // MARK: Competitions tab

    private var filteredCompetitions: [Competition] {
        let q = competitionSearch.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return model.library.competitions }
        return model.library.competitions.filter { $0.name.lowercased().contains(q) || $0.shortName.lowercased().contains(q) }
    }

    private var competitions: some View {
        // The reader keeps the whole split's ideal width tiny, same reason as `SlotView`'s lower panel: an
        // `HSplitView` not wrapped this way reports the sum of both panes' natural (unclipped) widths as its
        // own ideal size to whatever hosts it, which becomes the outer `NavigationSplitView`'s detail-column
        // minimum and clips the whole pane at 1180 pt with the list sitting off to one side of its own space.
        GeometryReader { geo in
            HSplitView {
                VStack(spacing: 0) {
                    modePicker
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        TextField("Search competitions", text: $competitionSearch).scaledFont(.body).textFieldStyle(.plain)
                        if !competitionSearch.isEmpty {
                            Button { competitionSearch = "" } label: { Image(systemName: "xmark.circle.fill") }
                                .scaledFont(.body).buttonStyle(.plain).foregroundStyle(.secondary)
                        }
                    }
                    .padding(6)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .controlBackgroundColor)))
                    .padding(10)
                    Divider()
                    List(filteredCompetitions, selection: $selectedCompetition) { c in
                        HStack { CachedCompetitionMark(competition: c, size: 22); Text(c.name); Spacer(); Text(c.shortName).foregroundStyle(.secondary) }
                            .scaledFont(.body)
                            .tag(c.id)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(minWidth: 320, idealWidth: 360, maxWidth: 440, maxHeight: .infinity, alignment: .top)
                Group {
                    if let id = selectedCompetition, let c = model.library.competitions.first(where: { $0.id == id }) { CompetitionEditor(competition: c).id(id) }
                    else { ContentUnavailableView("Choose a competition", systemImage: "trophy") }
                }.frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        // Each pane's own root view needs maxHeight: .infinity too, or NSSplitView sizes it to the
        // content's ideal height instead of the pane's real height (see clubsSplit).
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Clubs tab

    private var filteredClubs: [Club] {
        model.library.clubs
            .filter { matchesSearch($0) && matchesCompetitions($0) && matchesClubsNations($0) }
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

    private func matchesClubsNations(_ club: Club) -> Bool {
        switch clubsNationsFilter {
        case .all: return true
        case .clubs: return !club.competitionIds.contains("international")
        case .nations: return club.competitionIds.contains("international")
        }
    }

    private var hasActiveFilters: Bool {
        !selectedCompetitions.isEmpty || clubsNationsFilter != .all
    }

    private func bindingFor(_ value: String, in set: Binding<Set<String>>) -> Binding<Bool> {
        Binding(get: { set.wrappedValue.contains(value) }, set: { on in if on { set.wrappedValue.insert(value) } else { set.wrappedValue.remove(value) } })
    }

    private var clubsSplit: some View {
        // Computed once per body evaluation and threaded through, rather than each of countsRow/clubList/
        // clubGrid calling the filteredClubs property itself and re-filtering the same 229 rows three times.
        let filtered = filteredClubs
        // The reader keeps the whole split's ideal width tiny, same reason as `SlotView`'s lower panel: an
        // `HSplitView` not wrapped this way reports the sum of both panes' natural (unclipped) widths as its
        // own ideal size to whatever hosts it, which becomes the outer `NavigationSplitView`'s detail-column
        // minimum and clips the whole pane at 1180 pt with the list sitting off to one side of its own space.
        return GeometryReader { geo in
            HSplitView {
                VStack(spacing: 0) {
                    modePicker
                    toolbarRow
                    countsRow(filtered)
                    Divider()
                    Group { if viewMode == .list { clubList(filtered) } else { clubGrid(filtered) } }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    Divider()
                    addRemoveRow
                }
                // This pane's own root view must carry maxHeight: .infinity, or NSSplitView sizes the pane
                // to the VStack's ideal height and the list renders at zero height instead of filling it.
                .frame(minWidth: 320, idealWidth: 360, maxWidth: 440, maxHeight: .infinity, alignment: .top)
                .background(shortcutButtons)
                Group {
                    if let id = selected, let club = model.library.clubs.first(where: { $0.id == id }) {
                        ClubEditor(club: club).id(id)
                    } else {
                        ContentUnavailableView("Choose a club", systemImage: "shield")
                    }
                }.frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        // Greedy frame on purpose: an HSplitView inside a VStack otherwise sizes to its content and the list collapses.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Search, then one row: the Competitions menu, the Clubs/National teams/All choice and the
    /// List/Icons toggle. Chips only appear while a filter is active.
    private var toolbarRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            searchField
            HStack(spacing: 10) {
                competitionsMenu
                Picker("", selection: $clubsNationsFilter) {
                    ForEach(ClubsNationsFilter.allCases) { f in Text(f.title).tag(f) }
                }.scaledFont(.body).pickerStyle(.segmented).labelsHidden()
                Spacer()
                Picker("", selection: $viewMode) {
                    Image(systemName: "list.bullet").tag(LibraryViewMode.list)
                    Image(systemName: "square.grid.2x2").tag(LibraryViewMode.icons)
                }.scaledFont(.body).pickerStyle(.segmented).labelsHidden().frame(width: 76)
            }
            if hasActiveFilters { chipsRow }
        }
        .padding(.horizontal, 10).padding(.top, 10).padding(.bottom, 6)
    }

    private var competitionsMenu: some View {
        Menu {
            ForEach(model.library.competitions) { comp in
                Toggle(isOn: bindingFor(comp.id, in: $selectedCompetitions)) {
                    HStack { competitionMenuMark(comp); Text(comp.name) }
                }.scaledFont(.body)
            }
            if !selectedCompetitions.isEmpty {
                Divider()
                Button("Show All") { selectedCompetitions.removeAll() }.scaledFont(.body)
            }
        } label: {
            Label("Competitions", systemImage: "trophy").scaledFont(.body)
        }
    }

    /// A uniform 18 pt circular mark for the Competitions menu. A plain `Image` there ignores `.frame`
    /// and draws at the source's native pixel size, so this uses a pre-sized menu icon, not a resized one.
    private func competitionMenuMark(_ comp: Competition) -> some View {
        Group {
            if let f = comp.logoFile, let img = CrestImage.menuIcon(file: f) {
                Image(nsImage: img).clipShape(Circle())
            } else {
                Circle().fill(CompetitionColours.colour(for: comp.id)).frame(width: 18, height: 18)
                    .overlay(Text(comp.shortName.prefix(2)).font(.system(size: 7, weight: .heavy)).foregroundStyle(.white))
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search clubs and nations", text: $search).scaledFont(.body).textFieldStyle(.plain)
            if !search.isEmpty {
                Button { search = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .scaledFont(.body).buttonStyle(.plain).foregroundStyle(.secondary)
            }
        }
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .controlBackgroundColor)))
    }

    private var chipsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(model.library.competitions.filter { selectedCompetitions.contains($0.id) }) { comp in
                    FilterChip(label: comp.shortName) { selectedCompetitions.remove(comp.id) }
                }
                if clubsNationsFilter != .all {
                    FilterChip(label: clubsNationsFilter.title) { clubsNationsFilter = .all }
                }
            }.padding(.horizontal, 10)
        }
        .padding(.top, 6)
    }

    private func countsRow(_ filtered: [Club]) -> some View {
        Text("\(model.library.clubs.count) clubs and nations, \(model.library.clubs.filter { $0.crestFile != nil }.count) with crests, \(filtered.count) shown")
            .scaledFont(.caption).foregroundStyle(.secondary)
            .padding(.horizontal, 10).padding(.vertical, 6)
    }

    /// Competitions this club plays in, in the library's own order, up to 4. `byId` is built once per row
    /// pass by the caller so this is a lookup per membership instead of a filter over every competition.
    private func clubCompetitions(_ club: Club, byId: [String: Competition]) -> [Competition] {
        Array(club.competitionIds.compactMap { byId[$0] }.prefix(4))
    }

    private func clubList(_ filtered: [Club]) -> some View {
        // uniquingKeysWith rather than uniqueKeysWithValues: a duplicate id in a user-edited library.json
        // must not trap the app, so the first competition with that id wins.
        let byId = Dictionary(model.library.competitions.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        return List(filtered, selection: $selected) { club in
            HStack(spacing: 10) {
                CachedCrestThumb(club: club, size: 22)
                Text(club.name)
                Spacer()
                Text(club.defaultCode).foregroundStyle(.secondary).monospaced()
                HStack(spacing: 2) { ForEach(clubCompetitions(club, byId: byId)) { comp in CachedCompetitionMark(competition: comp, size: 14) } }
            }
            .scaledFont(.body)
            .tag(club.id)
            .padding(.vertical, 2)
        }
    }

    private func clubGrid(_ filtered: [Club]) -> some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 104, maximum: 104), spacing: 12)], spacing: 12) {
                ForEach(filtered) { club in clubTile(club) }
            }.padding(10)
        }
    }

    private func clubTile(_ club: Club) -> some View {
        let isSelected = selected == club.id
        return VStack(spacing: 6) {
            ZStack {
                Circle().fill(.quaternary).frame(width: 56, height: 56)
                CachedCrestThumb(club: club, size: 44)
            }
            Text(club.name).scaledFont(.caption).multilineTextAlignment(.center).lineLimit(2).minimumScaleFactor(0.8)
            Text(club.defaultCode).scaledFont(.caption2).foregroundStyle(.secondary).monospaced()
        }
        .padding(8)
        .frame(width: 104, height: 104)
        .background(RoundedRectangle(cornerRadius: 10).fill(isSelected ? Color.accentColor.opacity(0.18) : Color.clear))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 1.5))
        .contentShape(Rectangle())
        .onTapGesture { selected = club.id }
    }

    private var addRemoveRow: some View {
        HStack {
            Button {
                let ids = selectedCompetitions.count == 1 ? Array(selectedCompetitions) : []
                let c = Club(name: "New club", shortName: "New", defaultCode: "NEW", primaryColour: "#333333", competitionIds: ids)
                model.upsertClub(c); selected = c.id
            } label: { Image(systemName: "plus") }
                .scaledFont(.body)
            Button {
                if let id = selected { confirmDelete = model.library.clubs.first(where: { $0.id == id }) }
            } label: { Image(systemName: "minus") }
                .scaledFont(.body).disabled(selected == nil)
            Spacer()
        }
        .padding(8)
        .confirmationDialog(
            "Delete \(confirmDelete?.name ?? "this club")?",
            isPresented: Binding(get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } }),
            presenting: confirmDelete
        ) { club in
            Button("Delete", role: .destructive) {
                model.deleteClub(club.id)
                if selected == club.id { selected = nil }
                confirmDelete = nil
            }
        }
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

/// A competition's mark at a given size, backed by the thumbnail cache (never a full-size decode in a row).
private struct CachedCompetitionMark: View {
    let competition: Competition
    var size: CGFloat = 22
    var body: some View {
        Group {
            if let f = competition.logoFile, let img = CrestImage.thumbnail(file: f, size: size) {
                Image(nsImage: img)
            } else {
                RoundedRectangle(cornerRadius: size * 0.22).fill(CompetitionColours.colour(for: competition.id))
                    .overlay(Text(competition.shortName.prefix(4)).font(.system(size: size * 0.34, weight: .heavy)).foregroundStyle(.white).minimumScaleFactor(0.5).padding(2))
            }
        }.frame(width: size, height: size)
    }
}

/// A club's crest at a given size, backed by the thumbnail cache (never a full-size decode in a row).
private struct CachedCrestThumb: View {
    let club: Club
    var size: CGFloat = 22
    var body: some View {
        Group {
            if let f = club.crestFile, let img = CrestImage.thumbnail(file: f, size: size) {
                Image(nsImage: img)
            } else {
                Circle().fill(Color(hex: club.primaryColour))
                    .overlay(Text(String(club.defaultCode.prefix(2))).font(.system(size: size * 0.32, weight: .bold)).foregroundStyle(Color(hex: club.textColour)))
            }
        }.frame(width: size, height: size)
    }
}

struct CompetitionEditor: View {
    @EnvironmentObject var model: AppModel
    @State var competition: Competition
    @State private var importing = false
    var body: some View {
        Form {
            Section("Competition") {
                TextField("Name", text: $competition.name).scaledFont(.body)
                TextField("Short name", text: $competition.shortName).scaledFont(.body)
                Picker("Score bug design", selection: $competition.themeId) {
                    ForEach(model.resolver.availableThemeIds(), id: \.self) { id in Text(model.resolver.themeConfig(id: id)?.name ?? id).tag(id) }
                }.scaledFont(.body)
            }
            Section("Official mark") {
                HStack(spacing: 14) {
                    CompetitionMark(competition: competition, size: 56)
                    VStack(alignment: .leading, spacing: 4) {
                        Button("Import Image…") { importing = true }.scaledFont(.body)
                        Text("A PNG or SVG with transparency. Shown in the app and on the bug in place of the drawn mark, for example the lion roundel or the starball.").scaledFont(.caption).foregroundStyle(.secondary)
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
            Section {
                VStack(spacing: 8) {
                    Group {
                        if let f = club.crestFile, let img = CrestImage.thumbnail(file: f, size: 160) {
                            Image(nsImage: img).resizable().aspectRatio(contentMode: .fit)
                        } else {
                            Circle().fill(Color(hex: club.primaryColour)).overlay(Text(String(club.defaultCode.prefix(2))).font(.system(size: 44, weight: .bold)).foregroundStyle(Color(hex: club.textColour)))
                        }
                    }.frame(width: 160, height: 160)
                    Text(club.name).scaledFont(.title2, weight: .semibold)
                    Text(club.shortName).scaledFont(.body).foregroundStyle(.secondary)
                    Text(club.defaultCode).scaledFont(.caption).foregroundStyle(.secondary).monospaced()
                    Button("Import image") { importing = true }.scaledFont(.body)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            Section("Club") {
                TextField("Full name", text: $club.name).scaledFont(.body)
                TextField("Short name", text: $club.shortName).scaledFont(.body)
                TextField("Default code", text: $club.defaultCode).scaledFont(.body)
            }
            if club.competitionIds.contains("international") {
                Section("Confederation") {
                    Picker("Confederation", selection: Binding(get: { club.confederation ?? "" }, set: { club.confederation = $0.isEmpty ? nil : $0 })) {
                        Text("None").tag("")
                        ForEach(LibraryFilters.confederationOrder, id: \.self) { conf in Text(conf).tag(conf) }
                    }.scaledFont(.body)
                }
            }
            Section("Code per competition") {
                ForEach(model.library.competitions) { comp in
                    TextField(comp.name, text: Binding(
                        get: { club.codes[comp.id] ?? "" },
                        set: { v in let t = v.uppercased().trimmingCharacters(in: .whitespaces); if t.isEmpty { club.codes[comp.id] = nil } else { club.codes[comp.id] = t } }))
                    .scaledFont(.body)
                    .help("Leave empty to use the default code")
                }
            }
            Section("Colours") {
                ColorPicker("Primary", selection: Binding(get: { Color(hex: club.primaryColour) }, set: { club.primaryColour = $0.hexString })).scaledFont(.body)
                ColorPicker("Secondary", selection: Binding(get: { Color(hex: club.secondaryColour) }, set: { club.secondaryColour = $0.hexString })).scaledFont(.body)
                ColorPicker("Text on primary", selection: Binding(get: { Color(hex: club.textColour) }, set: { club.textColour = $0.hexString })).scaledFont(.body)
            }
            Section("Competitions") {
                ForEach(model.library.competitions) { comp in
                    Toggle(comp.name, isOn: Binding(
                        get: { club.competitionIds.contains(comp.id) },
                        set: { on in if on { club.competitionIds.append(comp.id) } else { club.competitionIds.removeAll { $0 == comp.id } } }))
                    .scaledFont(.body)
                }
            }
            Section("Squad") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("One player per line, formatted \"K. Mbappé\". Used for the scorer picker.").scaledFont(.caption).foregroundStyle(.secondary)
                    TextEditor(text: $squadText).scaledFont(.body).frame(minHeight: 140).overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(nsColor: .separatorColor)))
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
