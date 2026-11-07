import SwiftUI
import ScorebugCore

/// The live bar's one plain outlined square tile (B17): the goal and added-time minus and plus all use it, so the
/// bar is four-plus-two identical tiles beside one prominent Play. The neutral edge survives an inactive window
/// without looking like a second keyboard focus ring. Callers dim a disabled tile with `Surface.disabledOpacity`.
struct NudgeTile: View {
    let symbol: String
    let side: CGFloat
    var body: some View {
        Image(systemName: symbol).scaledFont(.title, weight: .bold)
            .frame(width: side, height: side)
            .background(Surface.fill, in: RoundedRectangle(cornerRadius: Radius.medium))
            .overlay(RoundedRectangle(cornerRadius: Radius.medium).strokeBorder(Surface.controlOutline, lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: Radius.medium))
    }
}

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
            NudgeTile(symbol: "plus", side: buttonSide)
                .gridProbe("livebar-button-goal-plus-\(side == .home ? "home" : "away")", area: "livebar-team-\(side == .home ? "home" : "away")", edge: nil)
        }
            .buttonStyle(.plain)
            // Dimmed by opacity alone, like the minus beside it, so a disabled plus keeps its box (C 8).
            .disabled(phase == .shootout).opacity(phase == .shootout ? Surface.disabledOpacity : 1).help("Goal for \(team.name) (⇧⌘\(side == .home ? "H" : "A"))")
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

