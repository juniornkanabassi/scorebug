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
    @FocusState private var searchFocused: Bool

    init(goal: Goal, slot: Int, onPick: @escaping () -> Void) {
        self.goal = goal; self.slot = slot; self.onPick = onPick
        _ownGoal = State(initialValue: goal.ownGoal)
        _penalty = State(initialValue: goal.penalty)
    }

    /// Read live rather than passed in: this view only exists while its popover is open, so the cost of a
    /// section elsewhere in `SlotView` skipping its own diff (the whole point of the Equatable sections in
    /// `SlotView.swift`) never applies here.
    private var match: Match { model.match(slot) }
    private var scoringSquad: [String] { match.team(goal.side).squad ?? [] }
    private var otherSquad: [String] { match.team(goal.side.other).squad ?? [] }
    private var filteredScoring: [String] { query.isEmpty ? scoringSquad : scoringSquad.filter { squadNameMatches($0, query: query) } }
    private var filteredOther: [String] { query.isEmpty ? otherSquad : otherSquad.filter { squadNameMatches($0, query: query) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TextField("Search scorer", text: $query)
                .scaledFont(.body)
                .textFieldStyle(.roundedBorder)
                .focused($searchFocused)
                .padding(8)
                .onSubmit(submitQuery)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    group(match.team(goal.side).shortName, filteredScoring, ownGoal: false)
                    group("Own goal", filteredOther, ownGoal: true)
                    if filteredScoring.isEmpty && filteredOther.isEmpty {
                        Text("No match. Press Return to use \"\(query)\".").scaledFont(.caption).foregroundStyle(.secondary).padding(8)
                    }
                }
            }.frame(maxHeight: 220)
            Divider()
            HStack(spacing: 20) {
                Toggle("Own goal", isOn: ownGoalBinding)
                Toggle("Penalty", isOn: penaltyBinding)
            }
            .scaledFont(.body).toggleStyle(.checkbox).padding(8)
        }
        .frame(width: 260)
        .onAppear { searchFocused = true }
    }

    @ViewBuilder
    private func group(_ title: String, _ names: [String], ownGoal og: Bool) -> some View {
        if !names.isEmpty {
            Text(title).scaledFont(.caption, weight: .semibold).foregroundStyle(.secondary)
                .padding(.horizontal, 8).padding(.top, 6).padding(.bottom, 2)
            ForEach(names, id: \.self) { name in
                Button(name) { pick(name, ownGoal: og) }
                    .scaledFont(.body)
                    .buttonStyle(.plain)
                    .padding(.vertical, 4).padding(.horizontal, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
        }
    }

    /// Return picks the first result in reading order (the scoring side's squad, then the other side's);
    /// with no match at all, the typed text becomes the scorer, same as a free-typed name always has.
    private func submitQuery() {
        if let first = filteredScoring.first { pick(first, ownGoal: false); return }
        if let first = filteredOther.first { pick(first, ownGoal: true); return }
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
