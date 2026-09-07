// The shared scorer popover content: pressed from a goal's plus button (MatchCardSection.teamColumn) or from
// its row in the Goals section (GoalRow). Search field over the scoring side's squad, a second group over the
// other side's squad headed "Own goal" (picking there pre-sets it), and Own goal/Penalty toggles that apply
// to the goal immediately, independent of picking a scorer.
import SwiftUI
import ScorebugCore

struct GoalPrompt: View {
    @EnvironmentObject var model: AppModel
    let goal: Goal
    let slot: Int
    /// Called once a scorer is committed (a name picked or Return submitted), so the caller can close its popover.
    let onPick: () -> Void

    @State private var query = ""
    @State private var ownGoal: Bool
    @State private var penalty: Bool
    @State private var highlighted = 0
    @FocusState private var searchFocused: Bool

    init(goal: Goal, slot: Int, onPick: @escaping () -> Void) {
        self.goal = goal; self.slot = slot; self.onPick = onPick
        _ownGoal = State(initialValue: goal.ownGoal)
        _penalty = State(initialValue: goal.penalty)
    }

    /// The goal's current scorer's row, so the popover opens with it highlighted instead of always row 0.
    private func initialHighlight() -> Int {
        guard let scorer = goal.scorer else { return 0 }
        return flatResults.firstIndex { $0.name == scorer } ?? 0
    }

    /// Read live rather than passed in: this view only exists while its popover is open, so the cost of a
    /// section elsewhere in `SlotView` skipping its own diff (the whole point of the Equatable sections in
    /// `SlotView.swift`) never applies here.
    private var match: Match { model.match(slot) }
    private var scoringSquad: [String] { match.team(goal.side).squad ?? [] }
    private var otherSquad: [String] { match.team(goal.side.other).squad ?? [] }
    private var filteredScoring: [String] { query.isEmpty ? scoringSquad : scoringSquad.filter { squadNameMatches($0, query: query) } }
    private var filteredOther: [String] { query.isEmpty ? otherSquad : otherSquad.filter { squadNameMatches($0, query: query) } }
    /// The navigable rows in reading order (the scoring side's squad, then the other side's).
    private var flatResults: [(name: String, ownGoal: Bool)] { filteredScoring.map { ($0, false) } + filteredOther.map { ($0, true) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TextField("Search scorer", text: $query)
                .scaledFont(.body)
                .textFieldStyle(.roundedBorder)
                .focused($searchFocused)
                .padding(8)
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        group(match.team(goal.side).shortName, filteredScoring, ownGoal: false, startIndex: 0)
                        group("Own goal", filteredOther, ownGoal: true, startIndex: filteredScoring.count)
                        if flatResults.isEmpty {
                            Text(query.isEmpty ? "No squad for this team. Type a name, then press Return." : "No match. Press Return to use \"\(query)\".")
                                .scaledFont(.caption).foregroundStyle(.secondary).padding(8)
                        }
                    }
                }.frame(maxHeight: 220)
                    .onAppear { proxy.scrollTo(highlighted, anchor: .center) }
                    .onChange(of: highlighted) { _, new in proxy.scrollTo(new, anchor: .center) }
            }
            Divider()
            HStack(spacing: 20) {
                Toggle("Own goal", isOn: ownGoalBinding)
                Toggle("Penalty", isOn: penaltyBinding)
            }
            .scaledFont(.body).toggleStyle(.checkbox).padding(8)
        }
        .frame(width: 260)
        .onAppear { searchFocused = true; highlighted = initialHighlight() }
        .onChange(of: query) { _, _ in highlighted = 0 }
        .keyNavigation(count: flatResults.count, highlighted: $highlighted, onPick: submitQuery, onClose: onPick)
    }

    @ViewBuilder
    private func group(_ title: String, _ names: [String], ownGoal og: Bool, startIndex: Int) -> some View {
        if !names.isEmpty {
            Text(title).scaledFont(.caption, weight: .semibold).foregroundStyle(.secondary)
                .padding(.horizontal, 8).padding(.top, 6).padding(.bottom, 2)
            ForEach(Array(names.enumerated()), id: \.element) { i, name in
                let index = startIndex + i
                // `Button(String)` ignores an outer `.scaledFont`, so the name is a Text inside the label
                // closure instead.
                Button {
                    pick(name, ownGoal: og)
                } label: {
                    Text(name).scaledFont(.body)
                        .padding(.vertical, 4).padding(.horizontal, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background(index == highlighted ? Color.accentColor.opacity(0.2) : .clear)
                .id(index)
            }
        }
    }

    /// Return picks the highlighted row; with no result at all, the typed text becomes the scorer, same as
    /// a free-typed name always has.
    private func submitQuery() {
        let results = flatResults
        if results.indices.contains(highlighted) { pick(results[highlighted].name, ownGoal: results[highlighted].ownGoal); return }
        let typed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !typed.isEmpty else { return }
        pick(typed, ownGoal: ownGoal)
    }

    private func pick(_ name: String, ownGoal og: Bool) {
        ownGoal = og
        model.apply(.setScorer(goal.id, name, ownGoal: og, penalty: penalty), slot: slot)
        onPick()
    }

    private var ownGoalBinding: Binding<Bool> {
        Binding(get: { ownGoal }, set: { v in
            ownGoal = v
            model.apply(.setScorer(goal.id, goal.scorer, ownGoal: v, penalty: nil), slot: slot)
        })
    }

    private var penaltyBinding: Binding<Bool> {
        Binding(get: { penalty }, set: { v in
            penalty = v
            model.apply(.setScorer(goal.id, goal.scorer, ownGoal: nil, penalty: v), slot: slot)
        })
    }
}
