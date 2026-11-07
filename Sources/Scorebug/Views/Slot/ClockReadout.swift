import AppKit
import SwiftUI
import ScorebugCore

/// The ticking clock and phase label, alone. Takes the clock's raw fields rather than a whole `Match` (a
/// scratch `Match` is built once per tick to reuse `ClockEngine.display`, the single source of truth also
/// used by overlay.js), and `tick` from `ClockSection`'s own quarter-second timer, shared with
/// `ClockFieldsRow` rather than each running its own subscription for the same purpose.
struct ClockReadout<Leading: View>: View {
    let clock: Clock
    let phase: Phase
    let addedMinutes: Int?
    let style: ClockStyle
    let tick: Date
    /// The live bar's quick added-time minus and plus; nil draws the readout alone.
    var adjustAdded: ((Int) -> Void)? = nil
    /// Drawn before the added-time pair on the second row (the live bar's Play button).
    @ViewBuilder var leading: Leading
    private var display: ClockDisplay {
        var m = Match(slot: 0)
        m.clock = clock; m.phase = phase; m.addedMinutes = addedMinutes
        return ClockEngine.display(match: m, style: style, now: tick)
    }

    var body: some View {
        VStack(spacing: Space.sm) {
            // The phase sits beside the clock, so the −/+ below flank only the added time they change (B11).
            HStack(alignment: .firstTextBaseline, spacing: Space.md) {
                Text(display.state ?? display.main).scaledFont(size: 48, weight: .semibold, design: .rounded).monospacedDigit()
                    .lineLimit(1).fixedSize(horizontal: true, vertical: false)
                    .accessibilityLabel("Match clock").accessibilityValue(display.state ?? display.main)
                    .gridProbe("livebar-clock-value", area: "livebar-centre", edge: nil)
                Text(phase.displayTitle).scaledFont(.subheadline).foregroundStyle(.primary).lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .accessibilityLabel("Match phase").accessibilityValue(phase.displayTitle)
                    .gridProbe("livebar-clock-phase", area: "livebar-centre", edge: nil)
            }
            HStack(spacing: Space.sm) {
                leading
                if let adjustAdded { addedControls(adjustAdded) }
            }
        }
        .gridArea("livebar-centre", inset: 0)
    }

    /// "− Added time [+4] +", with a grey +0 while none is set so the pair always names what it changes.
    /// Disabled outside a live period, as the clock nudges are, so nothing reaches the bug before kick-off.
    private func addedControls(_ adjust: @escaping (Int) -> Void) -> some View {
        let live = phase.period != nil
        let minutes = addedMinutes ?? 0
        return HStack(spacing: Space.sm) {
            addedButton("minus", delta: -1, adjust: adjust, enabled: live && minutes > 0)
            let chip = Text(display.added ?? "+0").scaledFont(.title3, weight: .semibold).monospacedDigit()
                .padding(.horizontal, Space.sm).padding(.vertical, Space.xxs).fixedSize()
            VStack(spacing: Space.xxs) {
                Text("Added time").scaledFont(.caption).foregroundStyle(.primary).lineLimit(1).fixedSize().accessibilityHidden(true)
                if display.added != nil {
                    chip.foregroundStyle(Surface.statusWarningForeground).background(Surface.statusWarning, in: Capsule())
                } else {
                    chip.foregroundStyle(.primary).background(.quaternary, in: Capsule())
                }
            }
            .fixedSize(horizontal: true, vertical: false)
            .accessibilityLabel("Added time").accessibilityValue(display.added ?? "None")
            .gridProbe("livebar-added-chip", area: "livebar-centre", edge: nil)
            if let c = display.addedCounter {
                // A word over the time played, in the same caption style as "Added time" (A F6).
                VStack(spacing: Space.xxs) {
                    Text("Stoppage").scaledFont(.caption).foregroundStyle(.primary).lineLimit(1).fixedSize().accessibilityHidden(true)
                    Text(c).scaledFont(.callout).monospacedDigit().foregroundStyle(.primary)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Added time played").accessibilityValue(c)
            }
            addedButton("plus", delta: 1, adjust: adjust, enabled: live && minutes < 15)
        }
    }

    private func addedButton(_ symbol: String, delta: Int, adjust: @escaping (Int) -> Void, enabled: Bool) -> some View {
        let words = delta < 0 ? "Remove a minute of added time" : "Add a minute of added time"
        return Button { adjust(delta) } label: {
            // The same tile as the goal minus and plus (B17).
            NudgeTile(symbol: symbol, side: 44 * ScaledFonts.scale)
                .gridProbe("livebar-button-added-\(symbol)", area: "livebar-centre", edge: nil)
        }
        .buttonStyle(.plain).accessibilityLabel(words)
        .disabled(!enabled).opacity(enabled ? 1 : Surface.disabledOpacity)
        .help(phase.period == nil ? "Only available while a period is live, not before kick-off or during a shootout" : words)
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
                .textFieldStyle(.plain).frame(width: 48 * ScaledFonts.scale)
                .focused($minutesFocused).onSubmit(applyTypedTime)
            Text(":").scaledFont(size: 20).foregroundStyle(.primary)
            TextField("", text: $secondsText)
                .accessibilityLabel("Clock seconds")
                .scaledFont(size: 20).monospacedDigit().multilineTextAlignment(.leading)
                .textFieldStyle(.plain).frame(width: 40 * ScaledFonts.scale)
                .focused($secondsFocused).onSubmit(applyTypedTime)
        }
        .padding(.horizontal, Space.md).padding(.vertical, Space.sm)
        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: Radius.medium))
        .overlay(RoundedRectangle(cornerRadius: Radius.medium).strokeBorder(.tertiary))
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

