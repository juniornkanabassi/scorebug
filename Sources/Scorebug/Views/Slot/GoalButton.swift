import SwiftUI
import ScorebugCore

/// The plus button and its scorer popover, alone. `.lazyPopover(isPresented:)` hosts are AppKit-bridged, and this
/// button is pressed (and so re-diffed) on every goal; pulling it out of `MatchCardSection` and gating it on
/// (side, team, phase, slot) means a goal on one side no longer re-attaches the *other* side's popover host,
/// and neither side's re-attaches for a command that only changes the score (score lives in `teamColumn`,
/// not here).
struct PlusGoalButton: View, Equatable {
    let side: Side
    let team: TeamEntry
    let phase: Phase
    let slot: Int
    let model: AppModel
    let buttonSide: CGFloat
    let promptGoalId: UUID?
    let addGoal: () -> Void
    let dismissGoal: (UUID?) -> Void
    static func == (l: Self, r: Self) -> Bool {
        l.side == r.side && l.team == r.team && l.phase == r.phase && l.slot == r.slot && l.buttonSide == r.buttonSide
            && l.promptGoalId == r.promptGoalId
    }

    var body: some View {
        Button(action: addGoal) {
            Image(systemName: "plus").scaledFont(.title, weight: .bold).frame(width: buttonSide, height: buttonSide)
                .frame(minWidth: buttonSide, minHeight: buttonSide)
        }
            .buttonStyle(.borderedProminent).controlSize(.extraLarge)
            // The same accent stroke as the live period pill: the prominent fill fades once the window is not key
            // (OBS has focus), and this keeps the most pressed control's edge visible either way.
            .overlay(RoundedRectangle(cornerRadius: Radius.medium).strokeBorder(.tint, lineWidth: 2).opacity(phase == .shootout ? 0 : 1))
            .disabled(phase == .shootout).help("Goal for \(team.name) (⇧⌘\(side == .home ? "H" : "A"))")
            .accessibilityLabel("Goal for \(team.name)")
            .lazyPopover(isPresented: plusPromptBinding) {
                if let id = promptGoalId, let g = model.match(slot).goals.first(where: { $0.id == id }) {
                    GoalPrompt(goal: g, slot: slot, onPick: { dismissGoal(promptGoalId) })
                }
            }
    }

    /// True only while `promptGoalId` names a goal still in the match on this side; a minus press
    /// or a goal on the other side both make this false on the next render, dismissing the popover.
    private var plusPromptBinding: Binding<Bool> {
        Binding(
            get: { promptGoalId.flatMap { id in model.match(slot).goals.first(where: { $0.id == id }) }?.side == side },
            set: { isPresented in
                if !isPresented,
                   promptGoalId.flatMap({ id in model.match(slot).goals.first(where: { $0.id == id }) })?.side == side {
                    dismissGoal(promptGoalId)
                }
            }
        )
    }
}

