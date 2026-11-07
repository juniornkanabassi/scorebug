import SwiftUI
import ScorebugCore

/// The added-time control, alone: minus, the value, plus, and a "Show added time on bug" switch that
/// hides it from the overlay (`setAddedMinutes(nil)`) without losing the number, restoring the last
/// non-zero value when switched back on.
struct StoppageSection: View, Equatable {
    let addedMinutes: Int?
    let slot: Int
    let model: AppModel
    let zoomGeneration: Int
    @State private var lastValue = 1

    static func == (l: Self, r: Self) -> Bool {
        l.addedMinutes == r.addedMinutes && l.slot == r.slot && l.zoomGeneration == r.zoomGeneration
    }

    /// Remembers the last non-zero value per slot, so switching slots (or reopening the app) does not forget
    /// a "+3" that was switched off with "Show added time on bug".
    private var defaultsKey: String { "lastAdded\(slot)" }

    var body: some View {
        Panel("Added time", accessory: {
            Toggle("Show added time on bug", isOn: showBinding).toggleStyle(.switch).scaledFont(.caption)
                .help("Show or hide the added time on the bug; the number is kept either way")
        }) {
            HStack(spacing: Space.lg) {
                Button { adjust(-1) } label: { Image(systemName: "minus").scaledFont(.title2, weight: .semibold).scaledControl(square: true) }
                    .buttonStyle(.bordered).controlSize(.extraLarge)
                    .accessibilityLabel("Remove a minute of added time").help("Remove a minute of added time")
                    .disabled((addedMinutes ?? 0) <= 0)
                Text(addedMinutes.map { "+\($0)" } ?? "Off").scaledFont(size: 28, weight: .bold, design: .rounded).monospacedDigit().frame(minWidth: 80 * ScaledFonts.scale)
                    .accessibilityLabel("Added time").accessibilityValue(addedMinutes.map { "\($0) minutes" } ?? "Off")
                Button { adjust(1) } label: { Image(systemName: "plus").scaledFont(.title2, weight: .semibold).scaledControl(square: true) }
                    .buttonStyle(.bordered).controlSize(.extraLarge)
                    .accessibilityLabel("Add a minute of added time").help("Add a minute of added time")
                    .disabled((addedMinutes ?? 0) >= 15)
            }
            .frame(maxWidth: .infinity)
        }
        .onAppear {
            if let v = addedMinutes, v > 0 { lastValue = v }
            else { let saved = UserDefaults.standard.integer(forKey: defaultsKey); if saved > 0 { lastValue = saved } }
        }
        .onChange(of: addedMinutes) { _, new in
            if let v = new, v > 0 { lastValue = v; UserDefaults.standard.set(v, forKey: defaultsKey) }
        }
    }

    private var showBinding: Binding<Bool> {
        Binding(get: { addedMinutes != nil }, set: { on in model.apply(.setAddedMinutes(on ? lastValue : nil), slot: slot) })
    }

    private func adjust(_ delta: Int) {
        let clamped = max(0, min(15, (addedMinutes ?? 0) + delta))
        model.apply(.setAddedMinutes(clamped == 0 ? nil : clamped), slot: slot)
    }
}

