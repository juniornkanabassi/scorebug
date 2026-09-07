// Small shared views: competition mark, crest thumbnail, colour helpers, squad search matching, zoom-scaled fonts.
import SwiftUI
import ScorebugCore
import ImageIO

/// Decoded crest and competition mark thumbnails, cached so a body re-evaluation never re-decodes a full-size
/// PNG. `directory` is set once by `AppModel.init`; `invalidate(file:)` drops a file's cached sizes (and any
/// stale persisted rendition) when its bytes change under the same name (a re-imported crest or mark).
enum CrestImage {
    static var directory: URL?
    private static let cache = NSCache<NSString, NSImage>()
    private static var keysByFile: [String: Set<String>] = [:]
    /// Files with a rendition-write already in flight, so a burst of rows for the same crest (list + grid +
    /// menu, all missing the same file) does not queue the same decode-and-write job several times over.
    private static var pendingRenditions: Set<String> = []

    /// Aspect-preserving thumbnail for any crest or competition mark box. Reads the persisted small rendition
    /// under `crests/.thumbs/<file>` when one exists (written at import time by `Store.writeThumbnail`, so
    /// this is a small decode); on a cache miss it decodes the full file now, for this one row only, and
    /// kicks off writing that rendition off the main thread so every later access, this session and the
    /// next launch, is a small decode again. Callers draw the result with `.resizable().scaledToFit()` so a
    /// non-square source (the squashed Atletico crest, formerly stretched to a square) keeps its own shape.
    static func thumbnail(file: String, size: CGFloat) -> NSImage? {
        let key = "\(file)@\(Int(size))"
        if let cached = cache.object(forKey: key as NSString) { return cached }
        guard let dir = directory else { return nil }
        let fullFile = dir.appendingPathComponent(file)
        let thumbFile = dir.appendingPathComponent(".thumbs").appendingPathComponent(file)
        let haveThumb = FileManager.default.fileExists(atPath: thumbFile.path)
        let useThumb = haveThumb && size * 2 <= Store.thumbnailPixelSize
        guard let source = CGImageSourceCreateWithURL((useThumb ? thumbFile : fullFile) as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: size * 2,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let img = NSImage(cgImage: cg, size: NSSize(width: CGFloat(cg.width) / 2, height: CGFloat(cg.height) / 2))
        cache.setObject(img, forKey: key as NSString)
        keysByFile[file, default: []].insert(key)
        if !haveThumb, pendingRenditions.insert(file).inserted {
            Task.detached(priority: .utility) {
                _ = Store.writeThumbnail(source: fullFile, dest: thumbFile)
                // invalidate(file:) removes the pending mark; a write that lands after it is stale and is discarded.
                await MainActor.run { if pendingRenditions.remove(file) == nil { try? FileManager.default.removeItem(at: thumbFile) } }
            }
        }
        return img
    }

    /// SwiftUI's `Menu` ignores an `Image`'s `.frame` and draws it at native size straight off the pixel
    /// data, so a menu row needs a pre-sized icon (not a large crest scaled down in layout) and, for a mark
    /// that isn't already circular (a flag, a square badge), the round mask baked into those pixels rather
    /// than applied with `.clipShape` (which a `Menu` also ignores).
    static func menuIcon(file: String) -> NSImage? {
        let key = "\(file)@menu"
        if let cached = cache.object(forKey: key as NSString) { return cached }
        guard let dir = directory, let source = CGImageSourceCreateWithURL(dir.appendingPathComponent(file) as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 36,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let side = min(cg.width, cg.height)
        let cropped = cg.cropping(to: CGRect(x: (cg.width - side) / 2, y: (cg.height - side) / 2, width: side, height: side)) ?? cg
        let size = NSSize(width: 18, height: 18)
        let circular = NSImage(size: size)
        circular.lockFocus()
        NSBezierPath(ovalIn: NSRect(origin: .zero, size: size)).setClip()
        NSImage(cgImage: cropped, size: size).draw(in: NSRect(origin: .zero, size: size))
        circular.unlockFocus()
        cache.setObject(circular, forKey: key as NSString)
        keysByFile[file, default: []].insert(key)
        return circular
    }

    /// Drops this file's cached sizes and its persisted rendition, so a re-imported crest is decoded afresh.
    static func invalidate(file: String) {
        for key in keysByFile.removeValue(forKey: file) ?? [] { cache.removeObject(forKey: key as NSString) }
        pendingRenditions.remove(file)
        if let dir = directory { try? FileManager.default.removeItem(at: dir.appendingPathComponent(".thumbs").appendingPathComponent(file)) }
    }
}

// MARK: Zoom-scaled fonts
//
// Interface zoom (View > Bigger/Smaller/Actual Size) scales font point sizes, not layout: on macOS the system
// text styles (.body, .caption, .title2 ...) have fixed point sizes and ignore Dynamic Type, and scaling the
// whole window with scaleEffect breaks hit-testing on AppKit-backed views (VSplitView, HSplitView, a grouped
// Form, List, WKWebView), see the comment above `AppModel.zoomLevel`. `scaledFont` used to read the scale
// from a custom `ViewModifier`'s own `@Environment`, which meant a distinct generic `ModifiedContent`
// specialisation and a live environment lookup at every one of this codebase's 120-odd call sites, on every
// view-graph update (this is what `sample` shows as `find1`/`EnvironmentValues.subscript.getter` and generic
// metadata instantiation under `AG::Graph::UpdateStack::update`). `AppModel.zoomLevel`'s `didSet` (and its
// init) now write the current scale into this plain static instead, so each call site is just a `.font(_:)`
// with a value computed from that static, no environment plumbing, no custom modifier type, of its own.
enum ScaledFonts {
    static var scale: CGFloat = 1 { didSet { generation &+= 1 } }
    /// Bumped whenever `scale` changes. `SlotView`'s panel blocks are each wrapped in `.equatable()` so a
    /// command that leaves a block's own fields untouched skips its diff; none of those fields mention zoom,
    /// so without this a zoom change published nothing changed and every scaled control stayed exactly the
    /// size it opened at. Each block adds a `zoomGeneration` field (read fresh at construction, in `SlotView`'s
    /// body, which itself is not equatable-gated) purely so its own `==` can see a zoom change too.
    private(set) static var generation = 0
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

extension View {
    /// A system text style (`.body`, `.caption`, `.title2` …) scaled by the interface zoom level.
    func scaledFont(_ style: Font.TextStyle, weight: Font.Weight? = nil, design: Font.Design? = nil) -> some View {
        let pointSize = NSFont.preferredFont(forTextStyle: nsFontTextStyle(style)).pointSize
        return font(.system(size: pointSize * ScaledFonts.scale, weight: weight ?? .regular, design: design ?? .default))
    }
    /// A fixed point size scaled by the interface zoom level. Not for sizes derived from a fixed-size graphic
    /// (a crest or mark placeholder's initials), which must stay proportional to that graphic instead.
    func scaledFont(size: CGFloat, weight: Font.Weight? = nil, design: Font.Design? = nil) -> some View {
        font(.system(size: size * ScaledFonts.scale, weight: weight ?? .regular, design: design ?? .default))
    }
    /// A panel button's minimum size, scaled by interface zoom, so View > Bigger Text grows the button itself
    /// and not only its label text (a `.controlSize` alone only affects AppKit's own default metrics, not a
    /// custom minimum this codebase already sets). Scales from the button's real base size, so applied inside
    /// a `Button`'s label (never on the `Button` itself, which an AppKit-backed control size such as
    /// `.extraLarge` already pins to a fixed height that an outer frame cannot grow). Pass `square: true` for
    /// a round or icon button so the minimum width matches the height too.
    func scaledControl(_ base: CGFloat = 44, square: Bool = false) -> some View {
        let side = max(44, base) * ScaledFonts.scale
        return frame(minWidth: square ? side : nil, minHeight: side)
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
    let competition: Competition
    var size: CGFloat = 28
    var plate: Bool = false
    var body: some View {
        let mark = Group {
            if let f = competition.logoFile, let img = CrestImage.thumbnail(file: f, size: size) {
                Image(nsImage: img).resizable().aspectRatio(contentMode: .fit)
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
    let team: TeamEntry
    var size: CGFloat = 24
    /// True for the match card and the club pickers: the crest is scaled to fit an inner box (60/72 of the
    /// frame) instead of being stretched to fill it, so two crests whose source PNGs carry different padding
    /// still read at the same visual size (Junior's Real Madrid v Inter Milan screenshot).
    var fitted: Bool = false
    var body: some View {
        Group {
            if let f = team.crestFile, let img = CrestImage.thumbnail(file: f, size: size) {
                if fitted {
                    Image(nsImage: img).resizable().aspectRatio(contentMode: .fit).frame(width: size * 60 / 72, height: size * 60 / 72)
                } else {
                    Image(nsImage: img).resizable().aspectRatio(contentMode: .fit)
                }
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

/// Case- and diacritic-insensitive match for the club picker's search field: name, short name (both via
/// `squadNameMatches`'s substring/surname folding, so "etienne" finds Saint-Étienne and "psg" still falls
/// through to the code check below) and the club's broadcast code for the competition in play (so "psg"
/// matches Paris Saint-Germain by code even where the name alone would not).
func nameMatches(_ club: Club, in competitionId: String, query: String) -> Bool {
    guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return true }
    if squadNameMatches(club.name, query: query) { return true }
    if squadNameMatches(club.shortName, query: query) { return true }
    let q = query.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
    return club.code(for: competitionId).folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current).contains(q)
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

extension View {
    /// A popover whose AppKit host exists only while it is shown. An always-attached `.popover` costs about
    /// 4 ms of main-thread work on every window update even when closed; four of them made every command slower.
    func lazyPopover<Content: View>(isPresented: Binding<Bool>, @ViewBuilder content: @escaping () -> Content) -> some View {
        overlay { if isPresented.wrappedValue { Color.clear.popover(isPresented: isPresented, content: content) } }
    }
}
