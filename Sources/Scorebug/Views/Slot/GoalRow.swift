import SwiftUI
import ScorebugCore

/// A goal row's scorer control: a button showing the current scorer (with " (og)"/" (pen)" appended) or
/// "Add scorer", that opens `GoalPrompt` from itself. Each row owns its own open state, so removing the goal
/// (minus pressed) removes the row, and its popover, with it.
struct GoalRow: View {
    let goal: Goal
    let slot: Int
    @State private var isOpen = false

    private var label: String {
        guard let scorer = goal.scorer, !scorer.isEmpty else { return "Add scorer" }
        return scorer + (goal.ownGoal ? " (og)" : "") + (goal.penalty ? " (pen)" : "")
    }

    var body: some View {
        // `Button(String)` ignores an outer `.scaledFont`, so the title is a Text inside the label closure
        // instead; the frame carries the 44 pt minimum row height, scaled by zoom like every other control.
        Button {
            isOpen = true
        } label: {
            Text(label).scaledFont(.body).foregroundStyle(goal.scorer == nil || goal.scorer?.isEmpty == true ? .secondary : .primary)
                .frame(maxWidth: .infinity, alignment: .leading).scaledControl()
        }
        .controlSize(.large)
        .lazyPopover(isPresented: $isOpen) {
            GoalPrompt(goal: goal, slot: slot, onPick: { isOpen = false })
        }
    }
}

