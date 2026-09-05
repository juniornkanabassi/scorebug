// Small shared views: competition mark, crest thumbnail, colour helpers, squad search matching.
import SwiftUI
import ScorebugCore

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
struct CompetitionMark: View {
    @EnvironmentObject var model: AppModel
    let competition: Competition
    var size: CGFloat = 28
    var body: some View {
        Group {
            if let f = competition.logoFile, let img = NSImage(contentsOf: model.store.crestsDirectory.appendingPathComponent(f)) {
                Image(nsImage: img).resizable().scaledToFit()
            } else {
                RoundedRectangle(cornerRadius: size * 0.22).fill(CompetitionColours.colour(for: competition.id))
                    .overlay(Text(competition.shortName.prefix(4)).font(.system(size: size * 0.34, weight: .heavy)).foregroundStyle(.white).minimumScaleFactor(0.5).padding(2))
            }
        }.frame(width: size, height: size)
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
                Circle().fill(Color(hex: team.primaryColour)).overlay(Text(String(team.code.prefix(2))).font(.system(size: size * 0.36, weight: .bold)).foregroundStyle(Color(hex: team.textColour)))
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
