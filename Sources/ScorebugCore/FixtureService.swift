// Fixtures and crests: football-data.org first, ESPN fallback, manual always. Key comes from the Keychain.
// Stage 4, slice 1: the fixture model and the football-data.org decoder only. No network, no crest download yet.
import Foundation

public struct FixtureTeam: Equatable, Sendable {
    public var name: String
    public var shortName: String
    public var code: String
    public var crestURL: URL?
    public init(name: String, shortName: String, code: String, crestURL: URL? = nil) {
        self.name = name; self.shortName = shortName; self.code = code; self.crestURL = crestURL
    }
}

public struct Fixture: Equatable, Sendable {
    public var kickoff: Date
    public var espnEventId: String?
    public var competitionCode: String
    public var competitionName: String
    public var home: FixtureTeam
    public var away: FixtureTeam
    public init(kickoff: Date, competitionCode: String, competitionName: String, home: FixtureTeam, away: FixtureTeam, espnEventId: String? = nil) {
        self.kickoff = kickoff; self.competitionCode = competitionCode; self.competitionName = competitionName
        self.home = home; self.away = away; self.espnEventId = espnEventId
    }
}

public enum FixtureLogic {
    public static func matchingClub(for team: FixtureTeam, in clubs: [Club]) -> Club? {
        let keys = Set([team.name, team.shortName, team.code].map(Store.matchKey).filter { !$0.isEmpty })
        return clubs.first { club in
            ([club.name, club.shortName, club.defaultCode] + Array(club.codes.values)).contains { keys.contains(Store.matchKey($0)) }
        }
    }

    public static func makeClub(from team: FixtureTeam) -> Club {
        Club(name: team.name, shortName: team.shortName, defaultCode: team.code,
             primaryColour: "#555555", secondaryColour: "#FFFFFF", textColour: "#FFFFFF")
    }

    public static func filter(_ fixtures: [Fixture], competition: Competition?) -> [Fixture] {
        guard let competition else { return fixtures }
        let codes = Set(competition.sourceIds.values)
        return fixtures.filter { codes.contains($0.competitionCode) }
    }
}

public enum FixtureDecoder {
    // football-data.org v4 `/matches` shape: {"matches":[{utcDate, competition:{code,name}, homeTeam:{name,shortName,tla,crest}, awayTeam:{...}}]}
    private struct Envelope: Decodable { var matches: [Match] }
    private struct Match: Decodable { var utcDate: Date; var competition: Comp; var homeTeam: Team; var awayTeam: Team }
    private struct Comp: Decodable { var code: String; var name: String }
    private struct Team: Decodable { var name: String; var shortName: String?; var tla: String?; var crest: String? }

    public static func footballData(_ data: Data) throws -> [Fixture] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(Envelope.self, from: data).matches.map { m in
            func team(_ t: Team) -> FixtureTeam {
                FixtureTeam(name: t.name, shortName: t.shortName ?? t.name, code: t.tla ?? String(t.name.prefix(3)).uppercased(), crestURL: t.crest.flatMap(URL.init(string:)))
            }
            return Fixture(kickoff: m.utcDate, competitionCode: m.competition.code, competitionName: m.competition.name, home: team(m.homeTeam), away: team(m.awayTeam))
        }
    }
}

extension FixtureDecoder {
    // ESPN scoreboard shape (undocumented, so tolerant): {"leagues":[{abbreviation,name}],"events":[{date, competitions:[{competitors:[{homeAway, team:{displayName,shortDisplayName,abbreviation,logo}}]}]}]}
    private struct ESPNEnvelope: Decodable { var leagues: [ESPNLeague]?; var events: [ESPNEvent] }
    private struct ESPNLeague: Decodable { var abbreviation: String?; var name: String? }
    private struct ESPNEvent: Decodable { var id: String?; var date: String; var competitions: [ESPNCompetition] }
    private struct ESPNCompetition: Decodable { var competitors: [ESPNCompetitor] }
    private struct ESPNCompetitor: Decodable { var homeAway: String; var team: ESPNTeam }
    private struct ESPNTeam: Decodable { var displayName: String; var shortDisplayName: String?; var abbreviation: String?; var logo: String? }

    public static func espn(_ data: Data) throws -> [Fixture] {
        let env = try JSONDecoder().decode(ESPNEnvelope.self, from: data)
        let league = env.leagues?.first
        let iso = ISO8601DateFormatter()
        return env.events.compactMap { e -> Fixture? in
            guard let comp = e.competitions.first,
                  let h = comp.competitors.first(where: { $0.homeAway == "home" }),
                  let a = comp.competitors.first(where: { $0.homeAway == "away" }) else { return nil }
            // ESPN writes "2026-09-27T15:00Z", without seconds; a decode failure drops the event rather than crashing
            guard let date = iso.date(from: e.date) ?? iso.date(from: e.date.replacingOccurrences(of: "Z", with: ":00Z")) else { return nil }
            func team(_ t: ESPNTeam) -> FixtureTeam {
                FixtureTeam(name: t.displayName, shortName: t.shortDisplayName ?? t.displayName, code: t.abbreviation ?? String(t.displayName.prefix(3)).uppercased(), crestURL: t.logo.flatMap(URL.init(string:)))
            }
            return Fixture(kickoff: date, competitionCode: league?.abbreviation ?? "", competitionName: league?.name ?? "", home: team(h.team), away: team(a.team), espnEventId: e.id)
        }
    }
}

public enum FixtureService {
    public typealias Loader = @Sendable (URLRequest) async throws -> Data

    public static let urlSessionLoader: Loader = { try await URLSession.shared.data(for: $0).0 }

    /// Fixtures on one day: football-data.org first (needs the API key), ESPN as fallback. Throws only when both fail.
    /// `espnLeague` (a competition's `sourceIds["espn"]`, e.g. "uefa.nations") asks ESPN for that league only and stamps
    /// its slug as the competition code, because ESPN's all-leagues scoreboard carries no per-event competition.
    public static func fetch(date: Date, apiKey: String?, espnLeague: String? = nil, loader: Loader = urlSessionLoader) async throws -> [Fixture] {
        var day = Calendar(identifier: .gregorian); day.timeZone = TimeZone(identifier: "UTC")!
        let c = day.dateComponents([.year, .month, .day], from: date)
        let iso = String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
        var firstError: Error?
        if let apiKey {
            var request = URLRequest(url: URL(string: "https://api.football-data.org/v4/matches?date=\(iso)")!)
            request.setValue(apiKey, forHTTPHeaderField: "X-Auth-Token")
            do { return try FixtureDecoder.footballData(try await loader(request)) } catch { firstError = error }
        }
        let compact = iso.replacingOccurrences(of: "-", with: "")
        let request = URLRequest(url: URL(string: "https://site.api.espn.com/apis/site/v2/sports/soccer/\(espnLeague ?? "all")/scoreboard?dates=\(compact)")!)
        do {
            let found = try FixtureDecoder.espn(try await loader(request))
            guard let espnLeague else { return found }
            return found.map { var f = $0; f.competitionCode = espnLeague; return f }
        } catch { throw firstError ?? error }
    }
}

public enum FixtureCrest: Equatable, Sendable {
    case file(URL)
    /// Two letters on the club colour when there is no crest or the download failed.
    case monogram(String)
}

extension FixtureService {
    /// The crest for a fixture team, cached under `folder` as `<slug>.<ext>` so a repeat fetch never touches the network.
    public static func crest(for team: FixtureTeam, in folder: URL, loader: Loader = urlSessionLoader) async -> FixtureCrest {
        let monogram = FixtureCrest.monogram(String(team.shortName.filter(\.isLetter).prefix(2)).uppercased())
        guard let url = team.crestURL, url.scheme?.lowercased() == "https" else { return monogram }
        let slug = team.name.lowercased().map { $0.isLetter || $0.isNumber ? $0 : "-" }.reduce(into: "") { if !($0.last == "-" && $1 == "-") { $0.append($1) } }
        let ext = ["png", "svg", "jpg", "jpeg", "webp"].contains(url.pathExtension.lowercased()) ? url.pathExtension.lowercased() : "png"
        let file = folder.appendingPathComponent("\(slug).\(ext)")
        if FileManager.default.fileExists(atPath: file.path) { return .file(file) }
        do {
            let data = try await loader(URLRequest(url: url))
            guard !data.isEmpty else { return monogram }
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try data.write(to: file, options: .atomic)
            return .file(file)
        } catch { return monogram }
    }
}
