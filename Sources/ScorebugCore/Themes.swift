// Theme loading: Overlays/themes/<id>/theme.json and theme.css, user override folder wins file by file.
import Foundation

public struct ThemeGeometry: Codable, Sendable, Equatable {
    public var left: Int?
    public var top: Int?
    public var maxWidth: Int?
    public var scale: Double?
}

public struct ThemeConfig: Codable, Sendable, Equatable {
    public var id: String
    public var name: String?
    public var clockStyle: ClockStyle
    public var geometry: [String: ThemeGeometry]
    public var verified: Bool?
    public var family: String?
}

/// Resolves overlay files. Order: user override folder (if enabled), then the bundled Overlays folder.
public struct OverlayResolver: Sendable {
    public let bundled: URL
    public let overrides: URL?

    public init(bundled: URL, overrides: URL?) { self.bundled = bundled; self.overrides = overrides }

    /// Finds the bundled Overlays folder: an explicit path, the app bundle, or the source tree during development.
    public static func locateBundledOverlays(explicit: String?) -> URL? {
        let fm = FileManager.default
        if let explicit { return URL(fileURLWithPath: explicit, isDirectory: true) }
        if let res = Bundle.main.resourceURL?.appendingPathComponent("Overlays", isDirectory: true), fm.fileExists(atPath: res.path) { return res }
        let dev = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources/Overlays", isDirectory: true)
        return fm.fileExists(atPath: dev.path) ? dev : nil
    }

    /// Returns the file for a relative path such as "themes/ligue1/theme.css", refusing any path that escapes the roots.
    public func file(for relativePath: String) -> URL? {
        let clean = relativePath.split(separator: "/").filter { !$0.isEmpty && $0 != "." && $0 != ".." }.joined(separator: "/")
        guard !clean.isEmpty else { return nil }
        let fm = FileManager.default
        if let overrides {
            let candidate = overrides.appendingPathComponent(clean)
            if fm.fileExists(atPath: candidate.path), Self.contains(candidate, in: overrides) { return candidate }
        }
        let candidate = bundled.appendingPathComponent(clean)
        return fm.fileExists(atPath: candidate.path) && Self.contains(candidate, in: bundled) ? candidate : nil
    }

    public static func contains(_ file: URL, in root: URL) -> Bool {
        file.resolvingSymlinksInPath().path.hasPrefix(root.resolvingSymlinksInPath().path + "/")
    }

    public func themeConfig(id: String) -> ThemeConfig? {
        guard !id.contains("/"), !id.contains("..") else { return nil }
        guard let url = file(for: "themes/\(id)/theme.json"), let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(ThemeConfig.self, from: data)
    }

    public func availableThemeIds() -> [String] {
        var ids = Set<String>()
        for root in [overrides, bundled].compactMap({ $0 }) {
            let themes = root.appendingPathComponent("themes")
            if let names = try? FileManager.default.contentsOfDirectory(atPath: themes.path) { ids.formUnion(names.filter { !$0.hasPrefix(".") }) }
        }
        return ids.filter { themeConfig(id: $0) != nil }.sorted()
    }
}

public enum MIME {
    public static func type(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "html": return "text/html; charset=utf-8"
        case "css": return "text/css; charset=utf-8"
        case "js": return "text/javascript; charset=utf-8"
        case "json": return "application/json; charset=utf-8"
        case "svg": return "image/svg+xml"
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "webp": return "image/webp"
        case "woff2": return "font/woff2"
        case "woff": return "font/woff"
        case "ttf": return "font/ttf"
        case "otf": return "font/otf"
        default: return "application/octet-stream"
        }
    }
}

/// A first-route guard for HTTP and WebSocket requests, before any action or file read.
public enum RequestSafety {
    public static func refusal(port: Int, host: String?, origin: String?, method: String, contentType: String?, contentLength: String? = nil, transferEncoding: String? = nil) -> (Int, String)? {
        let hosts = ["127.0.0.1:\(port)", "localhost:\(port)"]
        guard let host, hosts.contains(host) else { return (403, "request refused: foreign host") }
        if let origin, !hosts.contains(where: { origin == "http://\($0)" }) { return (403, "request refused: foreign origin") }
        if method == "POST" {
            guard contentType?.split(separator: ";").first?.trimmingCharacters(in: .whitespaces).lowercased() == "application/json" else { return (415, "content type must be application/json") }
            guard transferEncoding == nil, let length = contentLength.flatMap(Int.init), (0...65536).contains(length) else { return (413, "JSON body must have Content-Length and be at most 64 KiB") }
        }
        return nil
    }
}
