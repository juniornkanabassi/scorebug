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
    let homeCode: String
    let awayCode: String
    let slot: Int
    let model: AppModel
    let zoomGeneration: Int
    @FocusState private var focusedKick: UUID?

    static func == (l: Self, r: Self) -> Bool {
        l.shootout == r.shootout && l.phase == r.phase && l.homeShortName == r.homeShortName
            && l.awayShortName == r.awayShortName && l.homeCode == r.homeCode && l.awayCode == r.awayCode && l.slot == r.slot && l.zoomGeneration == r.zoomGeneration
    }

    private var beforeKickoff: Bool { phase == .preMatch }

    /// The penalty score leads the panel once a shootout exists, "Penalties NOR 3–2 RIV" (A F1).
    private var heading: String {
        guard let s = shootout else { return "Shootout" }
        return "Penalties \(homeCode) \(s.tally(.home))–\(s.tally(.away)) \(awayCode)"
    }

    var body: some View {
        Panel(heading) {
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
                        Text("Start shootout").scaledFont(.body, weight: .semibold).frame(maxWidth: .infinity).scaledControl(64)
                    }
                    .buttonStyle(.borderedProminent).controlSize(.extraLarge).disabled(beforeKickoff)
                }
            }
        }
    }

    /// Translucent tint fill, 1 pt tint edge, primary text and a leading symbol in the tint (B19), the same
    /// vocabulary as the kick circles. Only the side due to kick can be pressed (A F2); the other is dimmed.
    @ViewBuilder
    private func quickButton(_ title: String, side: Side, result: KickResult, tint: Color) -> some View {
        // The engine takes kicks whenever a shootout exists, not only while `phase == .shootout` (a kick can
        // land after full time or extra time too), so the buttons follow the shootout, not the phase.
        let enabled = shootout.map { $0.nextSide == side } ?? false
        Button {
            model.apply(.recordKick(side, result), slot: slot)
        } label: {
            HStack(spacing: Space.sm) {
                Image(systemName: result == .scored ? "checkmark" : "xmark").scaledFont(.body, weight: .bold).foregroundStyle(tint)
                Text(title).scaledFont(.body)
            }
            .foregroundStyle(.primary).frame(maxWidth: .infinity).scaledControl(64)
            .background(Surface.tintFill(tint), in: RoundedRectangle(cornerRadius: Radius.medium))
            .overlay(RoundedRectangle(cornerRadius: Radius.medium).strokeBorder(tint, lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: Radius.medium))
        }
        .buttonStyle(.plain)
        .disabled(!enabled).opacity(enabled ? 1 : Surface.disabledOpacity)
        .help(shootout == nil || enabled ? title : "Not \(side == .home ? homeShortName : awayShortName)'s turn to kick")
    }

    /// This side's kicks in order, each a round cell that cycles scored → missed → removed on a press
    /// (`setKick` scored to missed, `removeKick` missed to gone). The cell itself stays a small 28 pt circle,
    /// so the row stays compact; the button's hit target is padded out to 44 pt around it.
    private func kickRow(_ side: Side, _ s: Shootout) -> some View {
        let sideKicks = s.kicks.filter { $0.side == side }
        let sideName = side == .home ? "home" : "away"
        let cell = 44 * ScaledFonts.scale
        return HStack(alignment: .top, spacing: Space.sm) {
            Text(side == .home ? homeShortName : awayShortName).scaledFont(.body).lineLimit(2)
                .frame(width: 140 * ScaledFonts.scale, alignment: .leading).frame(minHeight: cell, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            // Wraps, so every kick is visible and "to kick" follows the last cell (B20).
            KickFlow(spacing: Space.sm) {
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
                    .frame(width: cell, height: cell)
                    .contentShape(Rectangle())
                    .gridProbe("flow-kick-\(sideName)-\(i)", area: "flow-kicks-\(sideName)", edge: nil)
                    .focused($focusedKick, equals: kick.id)
                    .help(helpText(for: kick.result))
                    .accessibilityLabel("\(side == .home ? homeShortName : awayShortName) penalty \(i + 1)")
                    .accessibilityValue(kick.result == .scored ? "Scored" : kick.result == .missed ? "Missed" : "Pending")
                    .accessibilityHint(helpText(for: kick.result))
                }
                if s.nextSide == side && phase == .shootout {
                    Text("to kick").scaledFont(.caption).foregroundStyle(.primary).frame(height: cell)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .gridArea("flow-kicks-\(sideName)", inset: 0)
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

/// Left-to-right cells that wrap onto the next line when the row is full; every cell keeps its own size.
private struct KickFlow: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(width: proposal.width ?? .infinity, subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (subview, origin) in zip(subviews, arrange(width: bounds.width, subviews).origins) {
            subview.place(at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y), proposal: .unspecified)
        }
    }

    private func arrange(width: CGFloat, _ subviews: Subviews) -> (size: CGSize, origins: [CGPoint]) {
        var origins: [CGPoint] = []
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, widest: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            origins.append(CGPoint(x: x, y: y))
            x += size.width; widest = max(widest, x); x += spacing
            rowHeight = max(rowHeight, size.height)
        }
        return (CGSize(width: widest, height: y + rowHeight), origins)
    }
}
