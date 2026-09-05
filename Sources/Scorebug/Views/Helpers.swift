// Small shared views: competition mark, crest thumbnail, colour helpers, squad search matching, zoom-scaled fonts.
import SwiftUI
import ScorebugCore

// MARK: Zoom-scaled fonts
//
// Interface zoom (View > Bigger/Smaller/Actual Size) scales font point sizes, not layout: on macOS the system
// text styles (.body, .caption, .title2 ...) have fixed point sizes and ignore Dynamic Type, and scaling the
// whole window with scaleEffect breaks hit-testing on AppKit-backed views (VSplitView, HSplitView, a grouped
// Form, List, WKWebView) — see the comment above `AppModel.zoomLevel`. So every text-bearing view reads the
// current `zoomScale` from the environment and builds its font from the system's own preferred point size for
// that text style, multiplied by the scale.

private struct ZoomScaleKey: EnvironmentKey {
    static let defaultValue: CGFloat = 1
}

extension EnvironmentValues {
    var zoomScale: CGFloat {
        get { self[ZoomScaleKey.self] }
        set { self[ZoomScaleKey.self] = newValue }
    }
}

/// Maps a SwiftUI text style to the AppKit text style whose preferred point size drives that style's scaling.
private func nsFontTextStyle(_ style: Font.TextStyle) -> NSFont.TextStyle {
    switch style {
    case .largeTitle: return .largeTitle
    case .title: return .title1
    case .title2: return .title2
    case .title3: return .title3
    case .headline: return .headline
    case .subheadline: return .subheadline
    case .body: return .body
    case .callout: return .callout
    case .footnote: return .footnote
    case .caption: return .caption1
    case .caption2: return .caption2
    default: return .body
    }
}

private struct ScaledTextStyleFont: ViewModifier {
    @Environment(\.zoomScale) private var scale
    let style: Font.TextStyle
    var weight: Font.Weight?
    var design: Font.Design?
    func body(content: Content) -> some View {
        let pointSize = NSFont.preferredFont(forTextStyle: nsFontTextStyle(style)).pointSize
        content.font(.system(size: pointSize * scale, weight: weight ?? .regular, design: design ?? .default))
    }
}

private struct ScaledFixedSizeFont: ViewModifier {
    @Environment(\.zoomScale) private var scale
    let size: CGFloat
    var weight: Font.Weight?
    var design: Font.Design?
    func body(content: Content) -> some View {
        content.font(.system(size: size * scale, weight: weight ?? .regular, design: design ?? .default))
    }
}

extension View {
    /// A system text style (`.body`, `.caption`, `.title2` …) scaled by the interface zoom level.
    func scaledFont(_ style: Font.TextStyle, weight: Font.Weight? = nil, design: Font.Design? = nil) -> some View {
        modifier(ScaledTextStyleFont(style: style, weight: weight, design: design))
    }
    /// A fixed point size scaled by the interface zoom level. Not for sizes derived from a fixed-size graphic
    /// (a crest or mark placeholder's initials), which must stay proportional to that graphic instead.
    func scaledFont(size: CGFloat, weight: Font.Weight? = nil, design: Font.Design? = nil) -> some View {
        modifier(ScaledFixedSizeFont(size: size, weight: weight, design: design))
    }
}

enum CompetitionColours {
    static func colour(for id: String) -> Color {
        switch id {
        case "premier-league": return Color(hex: "#37003C")
        case "champions-league": return Color(hex: "#0C1E96")
        case "europa-league": return Color(hex: "#F26A21")
        case "conference-league": return Color(hex: "#00A86B")
        case "ligue1": return Color(hex: "#0A5CFF")
        case "la-liga": return Color(hex: "#FF4B44")
        case "serie-a": return Color(hex: "#024494")
        case "bundesliga": return Color(hex: "#D3010C")
        case "club-world-cup": return Color(hex: "#B08D57")
        default: return Color(hex: "#3A3F4B")
        }
    }
}

/// The competition's official mark when imported, otherwise a coloured tile with its short name.
/// `plate`, when true, sets the mark on a small light backing plate so a dark broadcast mark (the
/// Premier League lion, drawn dark-on-transparent) still reads clearly on the app's dark match card.
struct CompetitionMark: View {
    @EnvironmentObject var model: AppModel
    let competition: Competition
    var size: CGFloat = 28
    var plate: Bool = false
    var body: some View {
        let mark = Group {
            if let f = competition.logoFile, let img = NSImage(contentsOf: model.store.crestsDirectory.appendingPathComponent(f)) {
                Image(nsImage: img).resizable().scaledToFit()
            } else {
                RoundedRectangle(cornerRadius: size * 0.22).fill(CompetitionColours.colour(for: competition.id))
                    .overlay(Text(competition.shortName.prefix(4)).font(.system(size: size * 0.34, weight: .heavy)).foregroundStyle(.white).minimumScaleFactor(0.5).padding(2))
            }
        }.frame(width: size, height: size)
        if plate {
            mark.padding(size * 0.16)
                .background(RoundedRectangle(cornerRadius: size * 0.22).fill(Color.white))
        } else {
            mark
        }
    }
}

struct CrestView: View {
    @EnvironmentObject var model: AppModel
    let team: TeamEntry
    var size: CGFloat = 24
    var body: some View {
        Group {
            if let f = team.crestFile, let img = NSImage(contentsOf: model.store.crestsDirectory.appendingPathComponent(f)) {
                Image(nsImage: img).resizable().scaledToFit()
            } else {
                Circle().fill(Color(hex: team.primaryColour)).overlay(Text(team.clubId == nil ? String(team.name.prefix(1)) : String(team.code.prefix(2))).font(.system(size: size * 0.36, weight: .bold)).foregroundStyle(Color(hex: team.textColour)))
            }
        }.frame(width: size, height: size)
    }
}

/// Case- and diacritic-insensitive squad search: matches anywhere in the name, the surname, or the initial
/// in a "K. Mbappé" style entry, so typing "mbap" or "k" both find the right player.
func squadNameMatches(_ name: String, query: String) -> Bool {
    let q = query.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
    guard !q.isEmpty else { return true }
    let folded = name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
    if folded.contains(q) { return true }
    let dotParts = name.split(separator: ".", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
    if dotParts.count == 2 {
        let initial = dotParts[0].folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        let surname = dotParts[1].folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        if surname.hasPrefix(q) || initial.hasPrefix(q) { return true }
    } else if let last = name.split(separator: " ").last {
        let surname = String(last).folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        if surname.hasPrefix(q) { return true }
    }
    return false
}

extension View {
    /// A small capsule badge: the live phase status ("First half", "Half time"...) shown under the clock,
    /// and anywhere else a compact status needs to sit apart from plain text.
    func pillBadge() -> some View {
        self.padding(.horizontal, 10).padding(.vertical, 4)
            .background(Capsule().fill(Color.secondary.opacity(0.15)))
    }
}

extension Color {
    init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces); if s.hasPrefix("#") { s.removeFirst() }
        var v: UInt64 = 0; Scanner(string: s).scanHexInt64(&v)
        let r = Double((v >> 16) & 0xFF) / 255, g = Double((v >> 8) & 0xFF) / 255, b = Double(v & 0xFF) / 255
        self.init(.sRGB, red: r, green: g, blue: b, opacity: 1)
    }
    var hexString: String {
        let c = NSColor(self).usingColorSpace(.sRGB) ?? .black
        return String(format: "#%02X%02X%02X", Int(round(c.redComponent * 255)), Int(round(c.greenComponent * 255)), Int(round(c.blueComponent * 255)))
    }
}
