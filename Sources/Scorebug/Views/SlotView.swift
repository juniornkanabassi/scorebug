// One match slot: a resizable live preview on top, then a control panel of full-width rounded blocks below.
// Each block below is its own Equatable view, so a command that only changes one block (e.g. a goal, which
// touches the match card and goals list) does not force SwiftUI to re-diff the others.
import SwiftUI
import ScorebugCore

/// Short pill label for the period row, matching Uno Overlays' "Match Time" tab wording;
/// `.title` (from ScorebugCore) stays the tooltip's full name.
extension Period {
    var shortLabel: String {
        switch self {
        case .firstHalf: return "1st"
        case .secondHalf: return "2nd"
        case .extraFirst: return "ET1"
        case .extraSecond: return "ET2"
        }
    }
}

/// Full display name for the match phase, shown under the clock and beside the period pills
/// while no period is live.
extension Phase {
    var displayTitle: String {
        switch self {
        case .preMatch: return "Before kick-off"; case .firstHalf: return "First half"; case .halfTime: return "Half-time"
        case .secondHalf: return "Second half"; case .fullTime: return "Full time"; case .extraFirst: return "Extra time, first half"
        case .extraBreak: return "Extra time break"; case .extraSecond: return "Extra time, second half"; case .extraFullTime: return "After extra time"
        case .shootout: return "Penalty shootout"; case .finished: return "Finished"
        }
    }
}

struct SlotView: View {
    @EnvironmentObject var model: AppModel
    let slot: Int
    @State private var commandContextID = UUID()
    @State private var confirmReset = false
    @State private var promptGoalId: UUID?
    @AppStorage("showPreview") private var showPreview = true
    /// The preview height the operator dragged to; nil (never dragged) uses the default for the window height.
    @AppStorage("previewHeight") private var storedPreviewHeight: Double?
    @State private var dragHeight: CGFloat?
    @State private var dragStart: CGFloat?

    private var match: Match { model.match(slot) }
    private var competition: Competition? { model.library.competitions.first { $0.id == match.competitionId } }
    private var clockStyle: ClockStyle? { model.themeConfig(id: match.themeId ?? competition?.themeId ?? match.competitionId)?.clockStyle }
    private var hasKnockouts: Bool { competition?.hasKnockouts ?? Competition.hasKnockouts(id: match.competitionId) }

    var body: some View {
        let m = match
        // A plain stack with a height we set, not VSplitView: the split view placed its divider from the
        // preview's content (274 pt in a 720 pt window) and ignored every ideal height, which kept Clock and
        // Added time below the fold. Here the preview is exactly `previewHeight` tall and the web views fit
        // inside it by height (PreviewStage), so the live controls get the rest.
        GeometryReader { outer in
            VStack(spacing: 0) {
                if showPreview {
                    let height = Self.clampedPreviewHeight(dragHeight ?? storedPreviewHeight.map { CGFloat($0) } ?? Self.defaultPreviewHeight(window: outer.size.height),
                                                           window: outer.size.height)
                    PreviewStage(slot: slot, baseURL: model.baseURL, visible: m.visible, serverProblem: previewServerProblem)
                        .frame(height: height)
                    previewResizeHandle(current: height, window: outer.size.height)
                }
                LiveMatchBar(home: m.home, away: m.away, homeScore: m.homeScore, awayScore: m.awayScore,
                             phase: m.phase, clock: m.clock, addedMinutes: m.addedMinutes, clockStyle: clockStyle,
                             aggregate: m.aggregate, slot: slot, model: model, zoomGeneration: ScaledFonts.generation,
                             promptGoalId: promptGoalId, addGoal: addGoal,
                             dismissGoal: { dismissedId in if promptGoalId == dismissedId { promptGoalId = nil } }).equatable()
                    .overlay(alignment: .bottom) { Divider() }
                statusStrip(m)
                GeometryReader { geo in ScrollView {
                    VStack(spacing: Space.lg) {
                        // `.equatable()` is what actually makes SwiftUI skip a block's diff when its inputs compare
                        // equal; conforming the view to Equatable alone does not opt it into that shortcut. None of
                        // these blocks' own fields mention zoom, so `zoomGeneration` (read fresh here, since this
                        // body itself is not equatable-gated) is threaded through purely so a zoom change is seen
                        // as a change too, not swallowed by the same shortcut.
                        let zoomGeneration = ScaledFonts.generation
                        // Order follows the job of the moment, and changes only with the phase, never on a tick:
                        // before kick-off the Clock (with the 1st pill the live bar points at) comes first; in a
                        // shootout the kick buttons do.
                        if m.phase == .shootout { shootoutSection(m, zoomGeneration) }
                        clockSection(m, zoomGeneration)
                        if m.phase == .preMatch { setupSection(m, zoomGeneration) }
                        StoppageSection(addedMinutes: m.addedMinutes, slot: slot, model: model, zoomGeneration: zoomGeneration).equatable()
                        GoalsSection(match: m, goals: m.goals, homeCode: m.home.code, awayCode: m.away.code, showScorers: m.showScorers,
                                      homeColour: m.home.primaryColour, awayColour: m.away.primaryColour, slot: slot, model: model, zoomGeneration: zoomGeneration).equatable()
                        if m.phase != .preMatch { setupSection(m, zoomGeneration) }
                        if hasKnockouts && m.phase != .shootout { shootoutSection(m, zoomGeneration) }
                    }
                    .padding(Space.lg)
                    // Capped and centred rather than stretched edge to edge, so a wide window (1900 pt) does not
                    // leave every block absurdly wide with dead space either side of its actual controls.
                    .frame(maxWidth: 1100)
                    .frame(width: geo.size.width)
                } }
                .frame(minHeight: 120)
            }
            // A zero ideal width keeps this pane out of the detail column's minimum, which once pushed the
            // sidebar off the window at 1180 pt (rule 22).
            .frame(minWidth: 0, idealWidth: 0, maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .navigationTitle(slot == 1 ? "Primary match" : "Secondary match")
        .navigationSubtitle("\(m.home.name) v \(m.away.name)")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button { model.apply(.setVisible(!m.visible), slot: slot) } label: {
                    Label(m.visible ? "On air" : "Off air", systemImage: m.visible ? "dot.radiowaves.left.and.right" : "eye.slash")
                        .symbolVariant(.fill).symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.primary).scaledFont(.body)
                }.labelStyle(.titleAndIcon).accessibilityLabel(m.visible ? "On air" : "Off air")
                    .help("Show or hide the bug in OBS")
                Toggle("Preview", systemImage: "rectangle.on.rectangle", isOn: $showPreview)
                    .toggleStyle(.button).labelStyle(.titleAndIcon).help("Show or hide the preview strip")
                // Icon-only, not label-and-icon: at a narrow window the toolbar otherwise crowds the navigation
                // title (Junior's screenshot showed it truncated to "Pr"). The help tooltip carries the text.
                Button(role: .destructive) { confirmReset = true } label: { Label("Reset match", systemImage: "arrow.counterclockwise").scaledFont(.body) }
                    .labelStyle(.iconOnly)
                    .help("Reset match: zero the score, clock and shootout; keep the teams")
            }
        }
        // On the persistent root, not the toolbar button: the toolbar can be hidden or overflowed, and the menu's
        // Reset Match… must still confirm.
        .confirmationDialog("Reset this match?", isPresented: $confirmReset) {
            Button("Reset match", role: .destructive) { model.apply(.reset, slot: slot) }
        } message: { Text("Zeroes the score, clock, goals and shootout. The teams and competition stay.") }
        .focusedSceneValue(\.matchCommands, MatchCommandContext(
            ownerID: commandContextID, slot: slot, homeName: m.home.name, awayName: m.away.name,
            clockRunning: m.clock.running, clockEnabled: m.phase.period != nil,
            endPeriodEnabled: m.phase.period != nil, goalsEnabled: m.phase != .shootout,
            visible: m.visible, previewVisible: showPreview,
            goalHome: { addGoal(.home) }, goalAway: { addGoal(.away) },
            playPause: { model.apply(.playPause, slot: slot) },
            endPeriod: { model.apply(.endPeriod, slot: slot) },
            toggleVisible: { model.apply(.setVisible(!model.match(slot).visible), slot: slot) },
            togglePreview: { showPreview.toggle() }, reset: { confirmReset = true }
        ))
    }

    /// A seventh of the window on the 4 pt grid: 100 pt for a 720 pt content area and the 96 pt floor under a
    /// real window's toolbar, which keeps Clock and Added time fully on screen at 1180 × 720. Drag for more.
    static func defaultPreviewHeight(window: CGFloat) -> CGFloat { (window * 0.14 / 4).rounded(.down) * 4 }

    /// Never so short the pair is unreadable, never more than half the window, so the live bar always fits.
    static func clampedPreviewHeight(_ height: CGFloat, window: CGFloat) -> CGFloat {
        min(max(96, height), max(96, (window * 0.5).rounded(.down)))
    }

    /// Drag to resize; the height is remembered. Arrow keys through VoiceOver's adjust action do the same.
    private func previewResizeHandle(current: CGFloat, window: CGFloat) -> some View {
        let step: CGFloat = 32
        // A short pill on the divider is the visible grip; the words are in the preview placeholder (B18).
        return Color.clear
            .frame(maxWidth: .infinity, minHeight: Space.md, maxHeight: Space.md)
            .overlay { Capsule().fill(Surface.controlOutline).frame(width: 40, height: 4) }
            .overlay(alignment: .bottom) { Divider() }
            .contentShape(Rectangle())
            .pointerStyle(.rowResize)
            .gesture(DragGesture(minimumDistance: 1, coordinateSpace: .global)
                .onChanged { drag in
                    let start = dragStart ?? current
                    dragStart = start
                    dragHeight = Self.clampedPreviewHeight(start + drag.translation.height, window: window)
                }
                .onEnded { _ in
                    if let dragHeight { storedPreviewHeight = Double(dragHeight) }
                    dragHeight = nil; dragStart = nil
                })
            .help("Drag to resize the preview")
            .accessibilityElement()
            .accessibilityLabel("Preview height")
            .accessibilityValue("\(Int(current)) points")
            .accessibilityAdjustableAction { direction in
                let delta = direction == .increment ? step : -step
                storedPreviewHeight = Double(Self.clampedPreviewHeight(current + delta, window: window))
            }
    }

    private func clockSection(_ m: Match, _ zoomGeneration: Int) -> some View {
        ClockSection(phase: m.phase, clock: m.clock, hasKnockouts: hasKnockouts, slot: slot, model: model,
                     zoomGeneration: zoomGeneration).equatable()
    }

    private func setupSection(_ m: Match, _ zoomGeneration: Int) -> some View {
        MatchSetupSection(home: m.home, away: m.away, competitionId: m.competitionId, phase: m.phase,
                          aggregate: m.aggregate, hasKnockouts: hasKnockouts, slot: slot, model: model,
                          zoomGeneration: zoomGeneration).equatable()
    }

    private func shootoutSection(_ m: Match, _ zoomGeneration: Int) -> some View {
        ShootoutSection(shootout: m.shootout, phase: m.phase, homeShortName: m.home.shortName, awayShortName: m.away.shortName,
                        homeCode: m.home.code, awayCode: m.away.code,
                        slot: slot, model: model, zoomGeneration: zoomGeneration).equatable()
    }

    /// Nil while the overlay server is serving; otherwise what the preview says instead of an empty page.
    private var previewServerProblem: String? {
        if model.serverRunning { return nil }
        if model.serverStatus.hasPrefix("Starting") { return "Starting the overlay server…" }
        return "No preview: the overlay server is not running.\n\(model.serverStatus)"
    }

    /// Standing notices under the live bar: a failed save stays visible until a save works again, and the last
    /// goal removed here can be put back until anything newer changes this match.
    @ViewBuilder
    private func statusStrip(_ m: Match) -> some View {
        if model.stateSaveFailed {
            Label("Changes are not being saved. OBS still shows the last saved match.", systemImage: "exclamationmark.triangle.fill")
                .scaledFont(.callout, weight: .semibold).foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Space.lg).padding(.vertical, Space.sm)
                .background(.bar).overlay(alignment: .top) { Divider() }
        }
        if let removal = model.undoableGoalRemoval(slot: slot) {
            let g = removal.goal
            let marks = (g.ownGoal ? " (og)" : "") + (g.penalty ? " (pen)" : "")
            HStack(spacing: Space.md) {
                Text("Removed \(g.side == .home ? m.home.code : m.away.code) goal, \(g.minuteLabel)\(g.scorer.map { ", \($0)" } ?? "")\(marks)")
                    .scaledFont(.callout).lineLimit(1)
                Spacer(minLength: Space.md)
                Button { model.undoGoalRemoval(slot: slot) } label: { Text("Undo").scaledFont(.body, weight: .semibold).scaledControl() }
                    // Keep Command-Z with the field editor; this action must never consume text undo.
                    .help("Put this goal back with its scorer and minute")
                Button { model.dismissGoalUndo(slot: slot) } label: { Image(systemName: "xmark").scaledFont(.callout).scaledControl(square: true) }
                    .buttonStyle(.borderless).help("Keep the goal removed").accessibilityLabel("Dismiss undo")
            }
            .padding(.horizontal, Space.lg)
            .background(.bar).overlay(alignment: .top) { Divider() }
        }
    }

    private func addGoal(_ side: Side) {
        model.apply(.goal(side, 1), slot: slot)
        promptGoalId = model.match(slot).lastGoal?.goalId
    }
}
