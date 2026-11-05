import SwiftUI
import ScorebugCore

/// The ticking clock and phase label, alone. Takes the clock's raw fields rather than a whole `Match` (a
/// scratch `Match` is built once per tick to reuse `ClockEngine.display`, the single source of truth also
/// used by overlay.js), and `tick` from `ClockSection`'s own quarter-second timer, shared with
/// `ClockFieldsRow` rather than each running its own subscription for the same purpose.
struct ClockReadout: View {
    let clock: Clock
    let phase: Phase
    let addedMinutes: Int?
    let style: ClockStyle
    let tick: Date
    private var display: ClockDisplay {
        var m = Match(slot: 0)
        m.clock = clock; m.phase = phase; m.addedMinutes = addedMinutes
        return ClockEngine.display(match: m, style: style, now: tick)
    }

    var body: some View {
        VStack(spacing: Space.md) {
            Text(display.state ?? display.main).scaledFont(size: 48, weight: .semibold, design: .rounded).monospacedDigit()
            HStack(spacing: Space.sm) {
                if let a = display.added { Text(a).scaledFont(.title3, weight: .semibold).foregroundStyle(Surface.statusWarningForeground).padding(.horizontal, Space.sm).padding(.vertical, Space.xxs).background(Surface.statusWarning, in: Capsule()) }
                if let c = display.addedCounter { Text(c).scaledFont(.callout).monospacedDigit().foregroundStyle(.secondary) }
            }.frame(height: 20)
            Text(phase.displayTitle).scaledFont(.subheadline).foregroundStyle(.secondary)
        }
    }
}

/// The editable minutes/seconds pair in the Clock block: shows the cumulative on-screen time (period
/// base + elapsed, the same value `ClockReadout` derives via `Clock.elapsed(at:)`), flanked by round −/+
/// buttons that nudge the clock directly. `tick` comes from `ClockSection`'s shared periodic `TimelineView`.
/// Typing a value only takes effect on Return (`onSubmit`), and the text mirrors re-sync on every tick
/// *unless* a field is focused, so a running clock never overwrites what the owner is mid-typing.
struct ClockFieldsRow: View {
    @EnvironmentObject var model: AppModel
    let slot: Int
    let tick: Date
    @State private var minutesText = "0"
    @State private var secondsText = "00"
    @FocusState private var minutesFocused: Bool
    @FocusState private var secondsFocused: Bool

    private var match: Match { model.match(slot) }
    private var periodBaseSeconds: Int { match.currentPeriod?.baseSeconds ?? 0 }
    private var cumulativeSeconds: Int { Int(match.clock.elapsed(at: tick)) }

    var body: some View {
        HStack(spacing: Space.xs) {
            TextField("", text: $minutesText)
                .accessibilityLabel("Clock minutes")
                .scaledFont(size: 20).monospacedDigit().multilineTextAlignment(.trailing)
                .textFieldStyle(.plain).frame(width: 48)
                .focused($minutesFocused).onSubmit(applyTypedTime)
            Text(":").scaledFont(size: 20).foregroundStyle(.secondary)
            TextField("", text: $secondsText)
                .accessibilityLabel("Clock seconds")
                .scaledFont(size: 20).monospacedDigit().multilineTextAlignment(.leading)
                .textFieldStyle(.plain).frame(width: 40)
                .focused($secondsFocused).onSubmit(applyTypedTime)
        }
        .padding(.horizontal, Space.md).padding(.vertical, Space.sm)
        .background(RoundedRectangle(cornerRadius: Radius.medium).strokeBorder(Surface.separator))
        .disabled(match.currentPeriod == nil)
        .help(match.currentPeriod == nil ? "Only available while a period is live, not before kick-off or during a shootout" : "")
        .onChange(of: tick) { _, _ in resyncIfIdle() }
        .onAppear { resyncIfIdle(force: true) }
    }

    /// Re-reads the match clock into the text fields, unless the owner is mid-edit in either of them.
    private func resyncIfIdle(force: Bool = false) {
        guard force || (!minutesFocused && !secondsFocused) else { return }
        let s = cumulativeSeconds
        minutesText = "\(s / 60)"
        secondsText = String(format: "%02d", s % 60)
    }

    /// The typed minutes/seconds are the on-screen cumulative time, so the period's own base is subtracted
    /// back out before sending `.setClock`.
    private func applyTypedTime() {
        guard let m = Int(minutesText), let s = Int(secondsText), match.currentPeriod != nil else { resyncIfIdle(force: true); return }
        model.apply(.setClock(seconds: max(0, min(333, max(0, m)) * 60 + min(59, max(0, s)) - periodBaseSeconds)), slot: slot)
    }
}

