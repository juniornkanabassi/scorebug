import SwiftUI
import ScorebugCore

/// A Home or Away column's club control: a button showing the current team (crest thumbnail, name,
/// chevron) that opens a search popover over the whole library, same pattern as `GoalPrompt`.
/// The plain alphabetical menu of about 165 clubs and nations it replaces was impractical to scroll;
/// this groups results instead and narrows them as the owner types. `model.setClub(_:side:slot:)` stays
/// the only side effect, exactly as the old picker's `onChange` was. Equatable on (side, slot) alone (its
/// only real inputs; everything else it reads live off `model` via its own `@EnvironmentObject`, so a goal
/// on either side, which never changes the team, no longer re-attaches this popover host either.
struct ClubPickerButton: View, Equatable {
    static func == (l: Self, r: Self) -> Bool { l.side == r.side && l.slot == r.slot }
    @EnvironmentObject var model: AppModel
    let side: Side
    let slot: Int
    @State private var query = ""
    @State private var isOpen = false
    @State private var highlighted = 0
    @FocusState private var searchFocused: Bool

    private var match: Match { model.match(slot) }
    private var team: TeamEntry { match.team(side) }

    /// A club is a national team when its `competitionIds` contains "international" (same rule as
    /// `LibraryFilters`'s Clubs/Nations split, kept in sync with it).
    private func isNational(_ club: Club) -> Bool { club.competitionIds.contains("international") }

    /// `Club.isEligible(for:)`: memberships decide for clubs and national teams alike (Codex review, 1 Oct).
    private func isEligible(_ club: Club) -> Bool { club.isEligible(for: match.competitionId) }

    /// Search results split into the two groups the popover shows, each sorted alphabetically.
    private var groups: (inCompetition: [Club], nations: [Club]) {
        let all = model.library.clubs
        let filtered = (query.isEmpty ? all : all.filter { nameMatches($0, in: match.competitionId, query: query) }).filter(isEligible)
        let nations = filtered.filter(isNational).sorted { $0.name < $1.name }
        let inComp = filtered.filter { !isNational($0) }.sorted { $0.name < $1.name }
        return (inComp, nations)
    }

    /// The navigable rows in reading order (in-competition clubs, then national teams), matching how the
    /// groups are drawn top to bottom; "None" sits above these and is not part of arrow navigation.
    private var flatClubs: [Club] { groups.inCompetition + groups.nations }

    var body: some View {
        Button {
            query = ""
            highlighted = flatClubs.firstIndex { $0.id == team.clubId } ?? 0
            isOpen = true
        } label: {
            HStack(spacing: Space.sm) {
                CrestView(team: team, size: 24, fitted: true)
                Text(team.name).scaledFont(.callout).lineLimit(1).help(team.name)
                Spacer(minLength: 4)
                Image(systemName: "chevron.down").scaledFont(.caption2).foregroundStyle(.secondary)
            }
            // A minimum, not maxWidth: a short name (e.g. "Inter") must not leave this button narrower than
            // the other side's, which is what threw the two pickers out of alignment. Both dimensions scale
            // with interface zoom like every other panel control, the width base carried directly since it
            // is not the usual 44/56/64 pt shape.
            .frame(minWidth: 200 * ScaledFonts.scale, alignment: .leading)
            .scaledControl()
        }
        .buttonStyle(.bordered)
        .accessibilityLabel("\(side == .home ? "Home" : "Away") team: \(team.name)")
        .lazyPopover(isPresented: $isOpen) {
            let clubs = flatClubs
            VStack(alignment: .leading, spacing: 0) {
                TextField("Search club or nation", text: $query)
                    .scaledFont(.body)
                    .textFieldStyle(.roundedBorder)
                    .focused($searchFocused)
                    .padding(Space.sm)
                Divider()
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            noneRow
                            Divider().padding(.vertical, Space.xxs)
                            groupSection("In this competition", groups.inCompetition, startIndex: 0)
                            groupSection("National teams", groups.nations, startIndex: groups.inCompetition.count)
                            if clubs.isEmpty {
                                Text("No match.").scaledFont(.caption).foregroundStyle(.secondary).padding(Space.sm)
                            }
                        }
                    }.frame(maxHeight: 320)
                        .onAppear { proxy.scrollTo(highlighted, anchor: .center) }
                        .onChange(of: highlighted) { _, new in proxy.scrollTo(new, anchor: .center) }
                }
            }
            .frame(width: 280)
            .onAppear { searchFocused = true }
            .onChange(of: query) { _, _ in highlighted = 0 }
            .keyNavigation(count: clubs.count, highlighted: $highlighted, onPick: submitQuery, onClose: { isOpen = false })
        }
    }

    /// Always present, unfiltered by the search text, so the team can be cleared back to the
    /// placeholder ("Home"/"Away") no matter what is typed.
    private var noneRow: some View {
        Button(action: pickNone) {
            HStack(spacing: Space.sm) {
                Image(systemName: "xmark.circle").foregroundStyle(.secondary)
                Text("None").foregroundStyle(.secondary)
            }
            .scaledFont(.body)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, Space.xs).padding(.horizontal, Space.sm)
    }

    @ViewBuilder
    private func groupSection(_ title: String, _ clubs: [Club], startIndex: Int) -> some View {
        if !clubs.isEmpty {
            Text(title).scaledFont(.caption, weight: .semibold).foregroundStyle(.secondary)
                .padding(.horizontal, Space.sm).padding(.top, Space.sm).padding(.bottom, Space.xxs)
            ForEach(Array(clubs.enumerated()), id: \.element.id) { i, club in clubRow(club, index: startIndex + i) }
        }
    }

    private func clubRow(_ club: Club, index: Int) -> some View {
        let entry = club.entry(for: match.competitionId)
        return Button { pick(club) } label: {
            HStack(spacing: Space.sm) {
                CrestView(team: entry, size: 20, fitted: true)
                Text(entry.name).scaledFont(.body)
                Spacer()
                Text(entry.code).scaledFont(.caption).monospaced().foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, Space.xs).padding(.horizontal, Space.sm)
        .background(index == highlighted ? Surface.selectedFill : .clear)
        .id(index)
    }

    private func submitQuery() {
        if flatClubs.indices.contains(highlighted) { pick(flatClubs[highlighted]) }
    }

    private func pick(_ club: Club) {
        model.setClub(club, side: side, slot: slot)
        isOpen = false
    }

    private func pickNone() {
        model.setClub(nil, side: side, slot: slot)
        isOpen = false
    }
}

