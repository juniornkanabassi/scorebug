// JSON persistence for library.json, state.json, settings.json. Atomic writes, schema checks, one-time backup on upgrade.
import Foundation

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

    private func load<T: Decodable>(_ name: String, as type: T.Type, schemaOf: (T) -> Int) throws -> T? {
        let file = url(name)
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        let data = try Data(contentsOf: file)
        let value = try JSONCoding.decoder().decode(T.self, from: data)
        let schema = schemaOf(value)
        if schema > currentSchema { throw StoreError.newerSchema(file: name, found: schema) }
        if schema < currentSchema {
            let backup = url(name.replacingOccurrences(of: ".json", with: "-before-schema-\(currentSchema).json"))
            if !FileManager.default.fileExists(atPath: backup.path) { try data.write(to: backup) }
        }
        return value
    }

    private func save<T: Encodable>(_ value: T, to name: String) throws {
        let data = try JSONCoding.prettyEncoder().encode(value)
        let target = url(name)
        let temp = url(".\(name).\(UUID().uuidString).tmp")
        try data.write(to: temp, options: .atomic)
        _ = try FileManager.default.replaceItemAt(target, withItemAt: temp)
    }

    public func loadLibrary() throws -> Library {
        if let lib = try load("library.json", as: Library.self, schemaOf: { $0.schema }) { return lib }
        let seeded = SeedLibrary.make()
        try saveLibrary(seeded)
        return seeded
    }
    public func saveLibrary(_ library: Library) throws { try save(library, to: "library.json") }

    public func loadState() throws -> MatchState {
        try load("state.json", as: MatchState.self, schemaOf: { $0.schema }) ?? MatchState()
    }
    public func saveState(_ state: MatchState) throws { try save(state, to: "state.json") }

    public func loadSettings() throws -> Settings {
        try load("settings.json", as: Settings.self, schemaOf: { $0.schema }) ?? Settings()
    }
    public func saveSettings(_ settings: Settings) throws { try save(settings, to: "settings.json") }

    /// Copies an image into crests/ under the club id and returns the stored file name.
    public func importCrest(from source: URL, for clubId: UUID) throws -> String {
        let ext = source.pathExtension.isEmpty ? "png" : source.pathExtension.lowercased()
        let name = "\(clubId.uuidString).\(ext)"
        let target = crestsDirectory.appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: target.path) { try FileManager.default.removeItem(at: target) }
        try FileManager.default.copyItem(at: source, to: target)
        return name
    }
}

/// Starter library so the app is usable before any fixture is fetched. Codes per competition are Junior's to correct in Library.
public enum SeedLibrary {
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
