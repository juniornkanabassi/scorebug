import SwiftUI
import ScorebugCore

/// The clock readout, the editable minutes/seconds, the play/reset/nudge/end-half row and the period pills.
/// Equatable on phase/clock/addedMinutes/clockStyle, so a goal (which does not touch any of those) skips
/// this block entirely.
struct ClockSection: View, Equatable {
    let phase: Phase
    let clock: Clock
    let hasKnockouts: Bool
    let slot: Int
    let model: AppModel
    let zoomGeneration: Int
    /// Read only for the period confirmation's wording; defaulted so callers that show no added time need not pass it.
    @State private var confirmResetClock = false
    @State private var pendingPeriod: Period?
    /// The phase when the pill was pressed; a confirmation for a match that moved on meanwhile does nothing.
    @State private var pendingFrom: Phase?
    private static let unavailableHelp = "Only available while a period is live, not before kick-off or during a shootout"

    static func == (l: Self, r: Self) -> Bool {
        l.phase == r.phase && l.clock == r.clock && l.hasKnockouts == r.hasKnockouts && l.slot == r.slot
            && l.zoomGeneration == r.zoomGeneration
    }

    private var periods: [Period] { Period.allCases.filter { hasKnockouts || ($0 != .extraFirst && $0 != .extraSecond) } }

    var body: some View {
        Panel("Clock") {
            VStack(spacing: Space.lg) {
                HStack(spacing: Space.md) {
                    HStack(spacing: Space.sm) { ForEach(periods, id: \.self) { p in periodPill(p) } }
                    Spacer(minLength: 12)
                    TimelineView(.periodic(from: .now, by: clock.running ? 1.0 : 3600)) { context in
                        ClockFieldsRow(slot: slot, tick: context.date)
                    }
                }
                HStack(spacing: Space.md) {
                    resetClockButton
                    Button { model.apply(.adjustClock(deltaSeconds: -10), slot: slot) } label: {
                        Text("−10 s").frame(maxWidth: .infinity).scaledControl(64)
                    }.disabled(phase.period == nil).help(Self.unavailableHelp)
                    Button { model.apply(.adjustClock(deltaSeconds: -1), slot: slot) } label: {
                        Text("−1 s").frame(maxWidth: .infinity).scaledControl(64)
                    }.disabled(phase.period == nil).help(Self.unavailableHelp)
                    Button { model.apply(.adjustClock(deltaSeconds: 1), slot: slot) } label: {
                        Text("+1 s").frame(maxWidth: .infinity).scaledControl(64)
                    }.disabled(phase.period == nil).help(Self.unavailableHelp)
                    Button { model.apply(.adjustClock(deltaSeconds: 10), slot: slot) } label: {
                        Text("+10 s").frame(maxWidth: .infinity).scaledControl(64)
                    }.disabled(phase.period == nil).help(Self.unavailableHelp)
                    Button {
                        model.apply(.endPeriod, slot: slot)
                    } label: {
                        Text(phase == .extraFirst || phase == .extraSecond ? "End period" : "End half").frame(maxWidth: .infinity).scaledControl(64)
                    }
                    .disabled(phase.period == nil)
                    .help("End the current period (⇧⌘E)")
                }
                .buttonStyle(.bordered).controlSize(.extraLarge).scaledFont(.body, weight: .semibold)
                // Periods remain available to correct a mistaken selection, behind a confirmation when one would discard time.
            }
        }
        .confirmationDialog(pendingPeriod.map { "Start the \($0.title.lowercased()) now?" } ?? "", isPresented: Binding(
            get: { pendingPeriod != nil }, set: { if !$0 { pendingPeriod = nil } }
        ), presenting: pendingPeriod) { p in
            Button("Start \(p.title)", role: .destructive) { if phase == pendingFrom { model.apply(.startPeriod(p), slot: slot) } }
        } message: { p in
            Text(periodChangeMessage(p))
        }
    }

    private func periodChangeMessage(_ p: Period) -> String {
        let start = "\(p.baseSeconds / 60):00"
        let current = "\(Int(clock.elapsed(at: .now)) / 60):\(String(format: "%02d", Int(clock.elapsed(at: .now)) % 60))"
        let added = model.match(slot).addedMinutes.map { " and the +\($0) added time is cleared" } ?? ""
        return "The clock goes from \(current) to \(start)\(added). This shows on the bug at once."
    }

    private var resetClockButton: some View {
        Button {
            if clock.running { confirmResetClock = true } else { model.apply(.setClock(seconds: 0), slot: slot) }
        } label: {
            Text("Reset clock").frame(maxWidth: .infinity).scaledControl(64)
        }
        .disabled(phase.period == nil)
        .help(Self.unavailableHelp)
        .confirmationDialog("Reset the clock to zero?", isPresented: $confirmResetClock) {
            Button("Reset clock", role: .destructive) { model.apply(.setClock(seconds: 0), slot: slot) }
        }
    }

    @ViewBuilder
    private func periodPill(_ p: Period) -> some View {
        let button = Button {
            if AppModel.periodChangeNeedsConfirmation(from: phase, to: p) { pendingFrom = phase; pendingPeriod = p } else { model.apply(.startPeriod(p), slot: slot) }
        } label: {
            Text(p.shortLabel).scaledFont(.body, weight: .semibold).frame(maxWidth: .infinity).scaledControl(64)
        }
        .controlSize(.extraLarge).help(p.title).accessibilityLabel(p.title)
        if phase.period == p {
            // Borders read clearly in a key window's own accent colour, but a borderedProminent fill can look
            // washed out once the window is not key (the streamer has OBS focused); the stroke is our own
            // layer, so the live pill still reads live either way.
            button.buttonStyle(.borderedProminent)
                .overlay(RoundedRectangle(cornerRadius: Radius.medium).strokeBorder(.tint, lineWidth: 2))
        } else {
            button.buttonStyle(.bordered)
        }
    }
}

