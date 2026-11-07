import SwiftUI
import ScorebugCore

/// The penalty shootout block: one-tap "scored"/"missed" buttons for each side, an editable row of kick
/// cells per side, undo, and the start button. Equatable on the shootout, phase and short names, so a goal
/// or clock edit (neither touches these once a shootout is not running) skips this block.
struct ShootoutSection: View, Equatable {
    let shootout: Shootout?
    let phase: Phase
    let homeShortName: String
    let awayShortName: String
    let slot: Int
    let model: AppModel
    let zoomGeneration: Int
    @FocusState private var focusedKick: UUID?

    static func == (l: Self, r: Self) -> Bool {
        l.shootout == r.shootout && l.phase == r.phase && l.homeShortName == r.homeShortName
            && l.awayShortName == r.awayShortName && l.slot == r.slot && l.zoomGeneration == r.zoomGeneration
    }

    private var beforeKickoff: Bool { phase == .preMatch }

    var body: some View {
        Panel("Shootout") {
            VStack(alignment: .leading, spacing: Space.lg) {
                if beforeKickoff {
                    Text("Available after kick-off").scaledFont(.caption).foregroundStyle(.primary)
                }
                Grid(horizontalSpacing: Space.md, verticalSpacing: Space.md) {
                    GridRow {
                        quickButton("\(homeShortName) scored", side: .home, result: .scored, tint: Surface.statusSuccess)
                        quickButton("\(homeShortName) missed", side: .home, result: .missed, tint: Surface.statusDanger)
                    }
                    GridRow {
                        quickButton("\(awayShortName) scored", side: .away, result: .scored, tint: Surface.statusSuccess)
                        quickButton("\(awayShortName) missed", side: .away, result: .missed, tint: Surface.statusDanger)
                    }
                }
                if let s = shootout {
                    VStack(alignment: .leading, spacing: Space.md) {
                        ForEach(Side.allCases, id: \.self) { side in kickRow(side, s) }
                    }
                    Button {
                        model.apply(.undoKick, slot: slot)
                    } label: {
                        Text("Undo last").frame(maxWidth: .infinity).scaledControl(64)
                    }
                    .buttonStyle(.bordered).controlSize(.extraLarge).disabled(s.kicks.isEmpty)
                } else {
                    Button {
                        model.apply(.startShootout(.home), slot: slot)
                    } label: {
                        Text("Start shootout").frame(maxWidth: .infinity).scaledControl(64)
                            .foregroundStyle(Surface.text(on: Color.accentColor))
                            .background(Color.accentColor, in: RoundedRectangle(cornerRadius: Radius.medium))
                    }
                    .buttonStyle(.plain)
                    .disabled(beforeKickoff).opacity(beforeKickoff ? 0.45 : 1)
                }
            }
        }
    }

    @ViewBuilder
    private func quickButton(_ title: String, side: Side, result: KickResult, tint: Color) -> some View {
        Button {
            model.apply(.recordKick(side, result), slot: slot)
        } label: {
            Text(title).scaledFont(.body).frame(maxWidth: .infinity).scaledControl(64)
                .foregroundStyle(Surface.text(on: tint))
                .background(tint, in: RoundedRectangle(cornerRadius: Radius.medium))
        }
        .buttonStyle(.plain).tint(tint)
        // The engine takes kicks whenever a shootout exists, not only while `phase == .shootout` (a kick can
        // land after full time or extra time too), so the buttons follow the shootout's existence, not the phase.
        .disabled(shootout == nil).opacity(shootout == nil ? 0.45 : 1)
    }

    /// This side's kicks in order, each a round cell that cycles scored → missed → removed on a press
    /// (`setKick` scored to missed, `removeKick` missed to gone). The cell itself stays a small 28 pt circle,
    /// so the row stays compact; the button's hit target is padded out to 44 pt around it.
    private func kickRow(_ side: Side, _ s: Shootout) -> some View {
        let sideKicks = s.kicks.filter { $0.side == side }
        return HStack(spacing: Space.sm) {
            Text(side == .home ? homeShortName : awayShortName).scaledFont(.body).lineLimit(2)
                .frame(width: 140 * ScaledFonts.scale, alignment: .leading).fixedSize(horizontal: false, vertical: true)
            ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    HStack(spacing: Space.sm) {
                        ForEach(Array(sideKicks.enumerated()), id: \.offset) { i, kick in
                            Button { cycle(side: side, index: i, current: kick.result) } label: {
                                Circle().fill(colour(kick.result)).frame(width: 28, height: 28)
                                    .overlay {
                                        Image(systemName: kick.result == .scored ? "checkmark" : kick.result == .missed ? "xmark" : "ellipsis")
                                            .scaledFont(.caption, weight: .bold)
                                            .foregroundStyle(Surface.text(on: colour(kick.result)))
                                    }
                            }
                            .buttonStyle(.plain)
                            .frame(width: 44 * ScaledFonts.scale, height: 44 * ScaledFonts.scale)
                            .contentShape(Rectangle())
                            .id(kick.id)
                            .focused($focusedKick, equals: kick.id)
                            .help(helpText(for: kick.result))
                            .accessibilityLabel("\(side == .home ? homeShortName : awayShortName) penalty \(i + 1)")
                            .accessibilityValue(kick.result == .scored ? "Scored" : kick.result == .missed ? "Missed" : "Pending")
                            .accessibilityHint(helpText(for: kick.result))
                        }
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 44 * ScaledFonts.scale)
                .onChange(of: focusedKick) { _, id in
                    if let id { proxy.scrollTo(id, anchor: .center) }
                }
            }
            if s.nextSide == side && phase == .shootout { Text("to kick").scaledFont(.caption).foregroundStyle(.primary) }
        }
    }

    private func colour(_ r: KickResult) -> Color { r == .scored ? Surface.statusSuccess : r == .missed ? Surface.statusDanger : .secondary }

    private func helpText(for result: KickResult) -> String {
        switch result {
        case .scored: return "Scored, press to mark missed"
        case .missed: return "Missed, press to remove"
        case .pending: return "Pending"
        }
    }

    private func cycle(side: Side, index: Int, current: KickResult) {
        switch current {
        case .scored: model.apply(.setKick(side, index: index, result: .missed), slot: slot)
        case .missed: model.apply(.removeKick(side, index: index), slot: slot)
        case .pending: break
        }
    }
}

