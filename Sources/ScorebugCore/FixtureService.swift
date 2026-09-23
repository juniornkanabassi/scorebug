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
