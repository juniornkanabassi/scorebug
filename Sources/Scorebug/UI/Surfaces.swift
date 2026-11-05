import SwiftUI
import AppKit

/// Native semantic surfaces and status colours, resolved by macOS for each appearance.
enum Surface {
    static let fill = Color(nsColor: .controlBackgroundColor)
    static let subtleFill = Color(nsColor: .underPageBackgroundColor)
    static let separator = Color(nsColor: .separatorColor)
    static let statusSuccess = Color(nsColor: .systemGreen)
    static let statusDanger = Color(nsColor: .systemRed)
    static let statusWarning = Color(nsColor: .systemOrange)
    static let selectedFill = Color.accentColor.opacity(0.18)
    static let accentFill = Color.accentColor.opacity(0.35)
    // Transparent overlay previews need a video-canvas backing in both appearances.
    static let previewCanvas = Color.black
    static var statusWarningForeground: Color { text(on: statusWarning) }
    // Imported transparent competition marks require a light backing, independent of window appearance.
    static let markPlate = Color.white

    /// Black or white, whichever has the higher WCAG contrast against an opaque sRGB fill.
    static func text(on fill: Color) -> Color {
        relativeLuminance(of: fill) > sqrt(0.05 * 1.05) - 0.05 ? .black : .white
    }

    static func relativeLuminance(of fill: Color) -> Double {
        let colour = NSColor(fill).usingColorSpace(.sRGB) ?? .black
        func linear(_ component: CGFloat) -> Double {
            let value = Double(component)
            return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(colour.redComponent)
            + 0.7152 * linear(colour.greenComponent)
            + 0.0722 * linear(colour.blueComponent)
    }
}

enum CompetitionColours {
    static func colour(for id: String) -> Color {
        switch id {
        case "premier-league": return colour(0x37003C)
        case "champions-league": return colour(0x0C1E96)
        case "europa-league": return colour(0xF26A21)
        case "conference-league": return colour(0x00A86B)
        case "nations-league": return colour(0x3D5566)
        case "ligue1": return colour(0x0A5CFF)
        case "la-liga": return colour(0xFF4B44)
        case "serie-a": return colour(0x024494)
        case "bundesliga": return colour(0xD3010C)
        case "club-world-cup": return colour(0xB08D57)
        default: return colour(0x3A3F4B)
        }
    }
    private static func colour(_ rgb: UInt32) -> Color {
        Color(.sRGB, red: Double((rgb >> 16) & 0xff) / 255,
              green: Double((rgb >> 8) & 0xff) / 255, blue: Double(rgb & 0xff) / 255, opacity: 1)
    }
}

