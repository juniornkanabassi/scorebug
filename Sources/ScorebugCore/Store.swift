// JSON persistence for library.json, state.json, settings.json. Atomic writes, schema checks, one-time backup on upgrade.
import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum StoreError: Error, CustomStringConvertible {
    case newerSchema(file: String, found: Int)
    public var description: String {
        switch self { case .newerSchema(let f, let n): return "\(f) has schema \(n), newer than this app understands (\(currentSchema))." }
    }
}

public final class Store: @unchecked Sendable {
    public let directory: URL
    public var crestsDirectory: URL { directory.appendingPathComponent("crests", isDirectory: true) }
    public var overlayOverridesDirectory: URL { directory.appendingPathComponent("overlays", isDirectory: true) }

    public static func defaultDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("Scorebug", isDirectory: true)
    }

    public init(directory: URL) throws {
        self.directory = directory
        let fm = FileManager.default
        for dir in [directory, crestsDirectory, overlayOverridesDirectory] {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    // MARK: Files

    private func url(_ name: String) -> URL { directory.appendingPathComponent(name) }

    private var unreadableFiles: Set<String> = []
    public private(set) var libraryDirty = false

    private func load<T: Decodable>(_ name: String, as type: T.Type, schemaOf: (T) -> Int) throws -> T? {
        let file = url(name)
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        do {
        let data = try Data(contentsOf: file)
        let value = try JSONCoding.decoder().decode(T.self, from: data)
        let schema = schemaOf(value)
        if schema > currentSchema { throw StoreError.newerSchema(file: name, found: schema) }
        if schema < currentSchema {
            let backup = url(name.replacingOccurrences(of: ".json", with: "-before-schema-\(currentSchema).json"))
            if !FileManager.default.fileExists(atPath: backup.path) { try data.write(to: backup) }
        }
        return value
        } catch {
            unreadableFiles.insert(name)
            let backup = url("\(name).unreadable-\(UUID().uuidString)")
            try? FileManager.default.copyItem(at: file, to: backup)
            throw error
        }
    }

    private func save<T: Encodable>(_ value: T, to name: String) throws {
        guard !unreadableFiles.contains(name) else { throw CocoaError(.fileWriteNoPermission, userInfo: [NSLocalizedDescriptionKey: "Refusing to replace unreadable \(name); recover the original or its backup and restart."]) }
        let data = try JSONCoding.prettyEncoder().encode(value)
        let target = url(name)
        let temp = url(".\(name).\(UUID().uuidString).tmp")
        try data.write(to: temp, options: .atomic)
        _ = try FileManager.default.replaceItemAt(target, withItemAt: temp)
    }

    public func loadLibrary() throws -> Library {
        if var lib = try load("library.json", as: Library.self, schemaOf: { $0.schema }) {
            if let seed = SeedLibrary.load(from: Store.locateSeedFile()) {
                let seedVersion = SeedLibrary.lastLoadedSquadsVersion
                let changed = Store.mergeSeed(seed, into: &lib, seedSquadsVersion: seedVersion, storedSquadsVersion: storedSquadsVersion())
                if changed {
                    do { try saveLibrary(lib) } catch { return lib }
                }
                if let seedVersion { saveSquadsVersion(seedVersion) }
            }
            return lib
        }
        let seeded = SeedLibrary.load(from: Store.locateSeedFile()) ?? SeedLibrary.make()
        try saveLibrary(seeded)
        if let v = SeedLibrary.lastLoadedSquadsVersion { saveSquadsVersion(v) }
        return seeded
    }
    public func saveLibrary(_ library: Library) throws {
        libraryDirty = true
        try save(library, to: "library.json")
        libraryDirty = false
    }

    /// Sidecar tracking of the squads.json "_version" last applied to this store's library.json, kept outside
    /// Models.swift (Library carries no version field) so mergeSeed can tell a stale squad from a current one.
    private func storedSquadsVersion() -> String? {
        guard let data = try? Data(contentsOf: url("squads-version.txt")) else { return nil }
        let s = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return s.isEmpty ? nil : s
    }
    private func saveSquadsVersion(_ version: String) {
        try? Data(version.utf8).write(to: url("squads-version.txt"), options: .atomic)
    }

    public func loadState() throws -> MatchState {
        try load("state.json", as: MatchState.self, schemaOf: { $0.schema }) ?? MatchState()
    }
    public func saveState(_ state: MatchState) throws { try save(state, to: "state.json") }

    public func loadSettings() throws -> Settings {
        try load("settings.json", as: Settings.self, schemaOf: { $0.schema }) ?? Settings()
    }
    public func saveSettings(_ settings: Settings) throws { try save(settings, to: "settings.json") }

    /// Brings an existing library up to date with the bundled seed without touching what the user edits:
    /// adds missing competitions and clubs, fills empty squads, confederations, crest sources and default codes.
    /// Memberships and per-competition codes are the user's once saved (ClubEditor edits them); only a competition
    /// this library has never had brings its seed membership and code in. Colours, crests, names and logos are kept.
    /// A club's squad is replaced (not just filled when nil) whenever `seedSquadsVersion` is newer than
    /// `storedSquadsVersion`, since squads.json is refreshed independently of the rest of the seed. Returns true
    /// when anything changed.
    public static func mergeSeed(_ seed: Library, into lib: inout Library, seedSquadsVersion: String? = nil, storedSquadsVersion: String? = nil) -> Bool {
        var changed = false
        let squadsAreNewer = isVersionNewer(seedSquadsVersion, than: storedSquadsVersion)
        let newCompetitionIds = Set(seed.competitions.map(\.id)).subtracting(lib.competitions.map(\.id))
        for comp in seed.competitions where newCompetitionIds.contains(comp.id) { lib.competitions.append(comp); changed = true }
        for sc in seed.clubs {
            if let i = lib.clubs.firstIndex(where: { $0.name == sc.name }) {
                var c = lib.clubs[i]
                if let sq = sc.squad, c.squad == nil || squadsAreNewer { c.squad = sq }
                if c.confederation == nil, let cf = sc.confederation { c.confederation = cf }
                if c.crestSource == nil, let cs = sc.crestSource { c.crestSource = cs }
                if c.defaultCode.trimmingCharacters(in: .whitespaces).isEmpty { c.defaultCode = sc.defaultCode }
                if !c.competitionIds.isEmpty {
                    for id in sc.competitionIds where newCompetitionIds.contains(id) && !c.competitionIds.contains(id) { c.competitionIds.append(id) }
                }
                for (id, code) in sc.codes where newCompetitionIds.contains(id) && c.codes[id] == nil { c.codes[id] = code }
                if c != lib.clubs[i] { lib.clubs[i] = c; changed = true }
            } else { lib.clubs.append(sc); changed = true }
        }
        return changed
    }

    /// Lexicographic comparison of "YYYY-MM-DD" style version strings: nil is oldest, a newer `a` wins ties toward false.
    private static func isVersionNewer(_ a: String?, than b: String?) -> Bool {
        guard let a else { return false }
        guard let b else { return true }
        return a > b
    }

    /// Finds the bundled seed-library.json: the app bundle, or the source tree during development.
    public static func locateSeedFile() -> URL? {
        let fm = FileManager.default
        if let res = Bundle.main.resourceURL?.appendingPathComponent("seed-library.json"), fm.fileExists(atPath: res.path) { return res }
        let dev = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources/seed-library.json")
        return fm.fileExists(atPath: dev.path) ? dev : nil
    }

    /// Normalises a club or file name for matching: lowercase, no accents, letters and digits only.
    public static func matchKey(_ s: String) -> String {
        let folded = (s.applyingTransform(StringTransform("Any-Latin; Latin-ASCII"), reverse: false) ?? s).lowercased()
        return folded.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.map(String.init).joined()
    }

    /// Scans folders (recursively, one level of subfolders) for images and assigns them to clubs without a crest,
    /// matching the club's crestSource file name first, then its normalised name or short name. Also imports a
    /// competition mark named `competition-<id>.<ext>` (any of the supported extensions) for every competition
    /// that has no `logoFile` yet, reusing `importCompetitionLogo`. Returns the number of clubs plus competitions
    /// assigned (i.e. the total number of new logo files brought in).
    @discardableResult
    public func importCrests(from folder: URL, into library: inout Library) -> Int {
        let fm = FileManager.default
        guard let e = fm.enumerator(at: folder, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) else { return 0 }
        var files: [String: URL] = [:]   // matchKey of basename -> url
        var byName: [String: URL] = [:]  // exact file name -> url
        for case let url as URL in e where ["png", "svg", "jpg", "jpeg", "webp"].contains(url.pathExtension.lowercased()) {
            byName[url.lastPathComponent] = url
            files[Store.matchKey(url.deletingPathExtension().lastPathComponent)] = url
        }
        var count = 0
        for i in library.clubs.indices where library.clubs[i].crestFile == nil {
            let club = library.clubs[i]
            let candidate = club.crestSource.flatMap { byName[$0] } ?? files[Store.matchKey(club.name)] ?? files[Store.matchKey(club.shortName)]
            guard let source = candidate, let name = try? importCrest(from: source, for: club.id) else { continue }
            library.clubs[i].crestFile = name
            count += 1
        }
        for i in library.competitions.indices where library.competitions[i].logoFile == nil {
            let competitionId = library.competitions[i].id
            guard let source = files[Store.matchKey("competition-\(competitionId)")],
                  let name = try? importCompetitionLogo(from: source, for: competitionId) else { continue }
            library.competitions[i].logoFile = name
            count += 1
        }
        return count
    }

    /// Copies a competition mark into crests/ as competition-<id>.<ext> and returns the stored file name.
    public func importCompetitionLogo(from source: URL, for competitionId: String) throws -> String {
        let ext = source.pathExtension.isEmpty ? "png" : source.pathExtension.lowercased()
        return try copyIntoCrests(source, as: "competition-\(competitionId).\(ext)")
    }

    /// Copies an image into crests/ under the club id and returns the stored file name.
    public func importCrest(from source: URL, for clubId: UUID) throws -> String {
        let ext = source.pathExtension.isEmpty ? "png" : source.pathExtension.lowercased()
        return try copyIntoCrests(source, as: "\(clubId.uuidString).\(ext)")
    }

    /// Copies through a hidden temporary file and only then replaces the stored image, so a missing or unreadable
    /// replacement leaves the original the library points at (Codex review, 1 Oct). Importing the stored file itself is a no-op.
    private func copyIntoCrests(_ source: URL, as name: String) throws -> String {
        let target = crestsDirectory.appendingPathComponent(name)
        if source.resolvingSymlinksInPath().path == target.resolvingSymlinksInPath().path { return name }
        let temp = crestsDirectory.appendingPathComponent(".\(name).\(UUID().uuidString).tmp")
        defer { try? FileManager.default.removeItem(at: temp) }
        try FileManager.default.copyItem(at: source, to: temp)
        _ = try FileManager.default.replaceItemAt(target, withItemAt: temp)
        return name
    }

    /// Longest side of a persisted crest rendition under `crests/.thumbs/`; boxes drawn larger than half this read the original.
    public static let thumbnailPixelSize: CGFloat = 256

    /// Writes an aspect-preserving rendition of `source` to `dest`, atomically through a temporary file since the
    /// main thread may read `dest` while a detached task writes it. Called by `writeMissingThumbnails` at launch
    /// and by the app's `CrestImage` cache on a miss, never on the main thread.
    @discardableResult
    public static func writeThumbnail(source: URL, dest: URL, maxPixelSize: CGFloat = thumbnailPixelSize) -> Bool {
        guard let src = CGImageSourceCreateWithURL(source as CFURL, nil) else { return false }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, options as CFDictionary) else { return false }
        try? FileManager.default.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
        let tmp = dest.appendingPathExtension(UUID().uuidString)
        guard let dst = CGImageDestinationCreateWithURL(tmp as CFURL, UTType.png.identifier as CFString, 1, nil) else { return false }
        CGImageDestinationAddImage(dst, cg, nil)
        guard CGImageDestinationFinalize(dst), (try? FileManager.default.replaceItemAt(dest, withItemAt: tmp)) != nil else { try? FileManager.default.removeItem(at: tmp); return false }
        return true
    }

    /// One background pass at launch: a rendition for every crest that has none yet (a library imported before
    /// renditions existed), so the first Team Library open never decodes full-size files on the main thread.
    public func writeMissingThumbnails() {
        let thumbs = crestsDirectory.appendingPathComponent(".thumbs")
        for name in (try? FileManager.default.contentsOfDirectory(atPath: crestsDirectory.path)) ?? [] where !name.hasPrefix(".") {
            let dest = thumbs.appendingPathComponent(name)
            if !FileManager.default.fileExists(atPath: dest.path) { Store.writeThumbnail(source: crestsDirectory.appendingPathComponent(name), dest: dest) }
        }
    }
}

/// Starter library so the app is usable before any fixture is fetched. The full seed is Resources/seed-library.json; this Swift fallback is small.
public enum SeedLibrary {
    private struct SeedClub: Decodable {
        var name: String; var shortName: String; var defaultCode: String; var codes: [String: String]?
        var primaryColour: String; var secondaryColour: String?; var textColour: String?
        var competitionIds: [String]?; var crestSource: String?; var sourceIds: [String: String]?
        var confederation: String?; var squad: [String]?
    }
    private struct SeedFile: Decodable { var schema: Int; var competitions: [Competition]; var clubs: [SeedClub] }

    /// squads.json's optional top-level version marker, for example "2026-09-05": a plain string key beside the
    /// per-club arrays. Decoded with a dynamic-key container so older squads.json files without it still decode.
    private struct SquadsSidecar: Decodable {
        var version: String?
        var squads: [String: [String]]
        private struct DynamicKey: CodingKey {
            var stringValue: String
            init?(stringValue: String) { self.stringValue = stringValue }
            var intValue: Int? { nil }
            init?(intValue: Int) { nil }
        }
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: DynamicKey.self)
            var version: String? = nil
            var squads: [String: [String]] = [:]
            for key in container.allKeys {
                if key.stringValue == "_version" {
                    version = try? container.decode(String.self, forKey: key)
                } else if let arr = try? container.decode([String].self, forKey: key) {
                    squads[key.stringValue] = arr
                }
            }
            self.version = version
            self.squads = squads
        }
    }

    /// The "_version" squads.json carried on the most recent `load(from:)` call, or nil if the file had none or
    /// wasn't found. Store.swift reads this right after calling `load` to track whether a refresh is due.
    public private(set) static var lastLoadedSquadsVersion: String?

    public static func load(from url: URL?) -> Library? {
        lastLoadedSquadsVersion = nil
        guard let url, let data = try? Data(contentsOf: url), let seed = try? JSONDecoder().decode(SeedFile.self, from: data) else { return nil }
        var clubs = seed.clubs.map { c in
            Club(name: c.name, shortName: c.shortName, defaultCode: c.defaultCode, codes: c.codes ?? [:], primaryColour: c.primaryColour,
                 secondaryColour: c.secondaryColour ?? "#FFFFFF", textColour: c.textColour ?? "#FFFFFF", crestSource: c.crestSource,
                 sourceIds: c.sourceIds ?? [:], competitionIds: c.competitionIds ?? [], confederation: c.confederation, squad: c.squad)
        }
        // Optional squads file beside the seed: { "Paris Saint-Germain": ["K. Mbappé", ...] } keyed by club name,
        // plus an optional "_version" string used by mergeSeed to decide whether to refresh an existing squad.
        let squadsURL = url.deletingLastPathComponent().appendingPathComponent("squads.json")
        if let data = try? Data(contentsOf: squadsURL), let sidecar = try? JSONDecoder().decode(SquadsSidecar.self, from: data) {
            lastLoadedSquadsVersion = sidecar.version
            for i in clubs.indices where clubs[i].squad == nil { clubs[i].squad = sidecar.squads[clubs[i].name] }
        }
        return Library(competitions: seed.competitions, clubs: clubs)
    }

    public static func make() -> Library {
        let competitions = [
            Competition(id: "ligue1", name: "Ligue 1", shortName: "L1", themeId: "ligue1", sourceIds: ["footballData": "FL1", "espn": "fra.1"]),
            Competition(id: "premier-league", name: "Premier League", shortName: "PL", themeId: "premier-league", sourceIds: ["footballData": "PL", "espn": "eng.1"]),
            Competition(id: "champions-league", name: "Champions League", shortName: "UCL", themeId: "champions-league", sourceIds: ["footballData": "CL", "espn": "uefa.champions"]),
            Competition(id: "europa-league", name: "Europa League", shortName: "UEL", themeId: "europa-league", sourceIds: ["espn": "uefa.europa"]),
            Competition(id: "conference-league", name: "Conference League", shortName: "UECL", themeId: "conference-league", sourceIds: ["espn": "uefa.europa.conf"]),
            Competition(id: "la-liga", name: "LaLiga", shortName: "LaLiga", themeId: "la-liga", sourceIds: ["footballData": "PD", "espn": "esp.1"]),
        ]
        func club(_ name: String, _ short: String, _ code: String, _ primary: String, _ secondary: String = "#FFFFFF", text: String = "#FFFFFF", codes: [String: String] = [:], in comps: [String]) -> Club {
            Club(name: name, shortName: short, defaultCode: code, codes: codes, primaryColour: primary, secondaryColour: secondary, textColour: text, competitionIds: comps)
        }
        let l1 = ["ligue1", "champions-league", "europa-league", "conference-league"]
        let clubs = [
            club("Paris Saint-Germain", "PSG", "PSG", "#004170", "#DA291C", in: l1),
            club("Olympique de Marseille", "Marseille", "OM", "#2FAEE0", "#FFFFFF", codes: ["champions-league": "MAR"], in: l1),
            club("Olympique Lyonnais", "Lyon", "OL", "#1B3F94", "#DA291C", codes: ["champions-league": "LYO", "europa-league": "LYO"], in: l1),
            club("AS Monaco", "Monaco", "ASM", "#E51B22", "#FFFFFF", codes: ["champions-league": "MON"], in: l1),
            club("LOSC Lille", "Lille", "LOSC", "#E01E13", "#FFFFFF", codes: ["champions-league": "LIL", "europa-league": "LIL"], in: l1),
            club("OGC Nice", "Nice", "OGCN", "#D2001C", "#000000", codes: ["champions-league": "NIC", "europa-league": "NIC"], in: l1),
            club("RC Lens", "Lens", "RCL", "#FFD100", "#D31E1B", text: "#000000", codes: ["champions-league": "LEN"], in: l1),
            club("Stade Rennais", "Rennes", "SRFC", "#E30613", "#000000", codes: ["champions-league": "REN"], in: l1),
            club("RC Strasbourg", "Strasbourg", "RCSA", "#1E90FF", "#FFFFFF", codes: ["conference-league": "STR"], in: l1),
            club("Toulouse FC", "Toulouse", "TFC", "#5E2C8B", "#FFFFFF", in: l1),
            club("FC Nantes", "Nantes", "FCN", "#FFD500", "#00843D", text: "#000000", in: l1),
            club("Stade Brestois", "Brest", "SB29", "#E2001A", "#FFFFFF", in: l1),
            club("AJ Auxerre", "Auxerre", "AJA", "#0E4C92", "#FFFFFF", in: l1),
            club("Angers SCO", "Angers", "SCO", "#000000", "#FFFFFF", in: l1),
            club("Le Havre AC", "Le Havre", "HAC", "#7BC1E4", "#1E3A8A", in: l1),
            club("FC Metz", "Metz", "FCM", "#7D1D3F", "#FFFFFF", in: l1),
            club("FC Lorient", "Lorient", "FCL", "#F58220", "#000000", in: l1),
            club("Paris FC", "Paris FC", "PFC", "#0F2B5B", "#FFFFFF", in: l1),
        ]
        return Library(competitions: competitions, clubs: clubs)
    }
}
