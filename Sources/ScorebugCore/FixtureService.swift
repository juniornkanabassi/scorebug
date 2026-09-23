// Fixtures and crests: football-data.org first, ESPN fallback, manual always. Key comes from the Keychain.
// Stage 4, slice 1: the fixture model and the football-data.org decoder only. No network, no crest download yet.
import Foundation

public struct FixtureTeam: Equatable, Sendable {
    public var name: String
    public var shortName: String
    public var code: String
    public var crestURL: URL?
}

public struct Fixture: Equatable, Sendable {
    public var kickoff: Date
    public var competitionCode: String
    public var competitionName: String
    public var home: FixtureTeam
    public var away: FixtureTeam
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
    private struct ESPNEvent: Decodable { var date: String; var competitions: [ESPNCompetition] }
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
            return Fixture(kickoff: date, competitionCode: league?.abbreviation ?? "", competitionName: league?.name ?? "", home: team(h.team), away: team(a.team))
        }
    }
}
