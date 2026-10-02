// Schema 1 data model. See ARCHITECTURE.md "Data model". Every later field is optional; none is removed.
import Foundation

public let currentSchema = 1

public enum Side: String, Codable, Sendable, CaseIterable {
    case home, away
    public var other: Side { self == .home ? .away : .home }
}

public enum Phase: String, Codable, Sendable, CaseIterable {
    case preMatch, firstHalf, halfTime, secondHalf, fullTime
    case extraFirst, extraBreak, extraSecond, extraFullTime
    case shootout, finished

    public var isLivePeriod: Bool { period != nil }
    public var period: Period? {
        switch self {
        case .firstHalf: return .firstHalf
        case .secondHalf: return .secondHalf
        case .extraFirst: return .extraFirst
        case .extraSecond: return .extraSecond
        default: return nil
        }
    }
    /// Short broadcast label for a non-running state, nil while a period is live.
    public var stateLabel: String? {
        switch self {
        case .preMatch: return "KO"
        case .halfTime: return "HT"
        case .fullTime: return "FT"
        case .extraBreak: return "HT"
        case .extraFullTime: return "AET"
        case .shootout: return "PENS"
        case .finished: return "FT"
        default: return nil
        }
    }
}

public enum Period: String, Codable, Sendable, CaseIterable {
    case firstHalf, secondHalf, extraFirst, extraSecond

    public var baseSeconds: Int {
        switch self {
        case .firstHalf: return 0
        case .secondHalf: return 45 * 60
        case .extraFirst: return 90 * 60
        case .extraSecond: return 105 * 60
        }
    }
    public var endSeconds: Int {
        switch self {
        case .firstHalf: return 45 * 60
        case .secondHalf: return 90 * 60
        case .extraFirst: return 105 * 60
        case .extraSecond: return 120 * 60
        }
    }
    public var phase: Phase {
        switch self {
        case .firstHalf: return .firstHalf
        case .secondHalf: return .secondHalf
        case .extraFirst: return .extraFirst
        case .extraSecond: return .extraSecond
        }
    }
    public var breakPhase: Phase {
        switch self {
        case .firstHalf: return .halfTime
        case .secondHalf: return .fullTime
        case .extraFirst: return .extraBreak
        case .extraSecond: return .extraFullTime
        }
    }
    public var title: String {
        switch self {
        case .firstHalf: return "1st half"
        case .secondHalf: return "2nd half"
        case .extraFirst: return "1st extra time"
        case .extraSecond: return "2nd extra time"
        }
    }
}

/// The master clock. Elapsed is always derived; no timer ever writes it.
public struct Clock: Codable, Sendable, Equatable {
    public var periodBaseSeconds: Int
    public var periodStart: Date?
    public var accumulated: TimeInterval
    public var running: Bool

    public init(periodBaseSeconds: Int = 0, periodStart: Date? = nil, accumulated: TimeInterval = 0, running: Bool = false) {
        self.periodBaseSeconds = periodBaseSeconds
        self.periodStart = periodStart
        self.accumulated = accumulated
        self.running = running
    }

    public func elapsed(at now: Date) -> TimeInterval {
        var total = TimeInterval(periodBaseSeconds) + accumulated
        if running, let start = periodStart { total += max(0, now.timeIntervalSince(start)) }
        return total.isFinite ? min(20000, max(0, total)) : 0
    }
}

public struct Goal: Codable, Sendable, Identifiable, Equatable {
    public var id: UUID
    public var side: Side
    public var elapsedSeconds: Int
    public var minuteLabel: String
    public var scorer: String?
    public var ownGoal: Bool
    public var penalty: Bool
    /// True only while this scorer came from ESPN and may be corrected by a later poll.
    public var autoFilled: Bool
    public var autoAdded: Bool
    public var autoAddedKey: String?

    public init(id: UUID = UUID(), side: Side, elapsedSeconds: Int, minuteLabel: String, scorer: String? = nil, ownGoal: Bool = false, penalty: Bool = false, autoFilled: Bool = false, autoAdded: Bool = false, autoAddedKey: String? = nil) {
        self.id = id; self.side = side; self.elapsedSeconds = elapsedSeconds; self.minuteLabel = minuteLabel
        self.scorer = scorer; self.ownGoal = ownGoal; self.penalty = penalty; self.autoFilled = autoFilled; self.autoAdded = autoAdded; self.autoAddedKey = autoAddedKey
    }

    private enum CodingKeys: String, CodingKey { case id, side, elapsedSeconds, minuteLabel, scorer, ownGoal, penalty, autoFilled, autoAdded, autoAddedKey }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id); side = try c.decode(Side.self, forKey: .side)
        elapsedSeconds = try c.decode(Int.self, forKey: .elapsedSeconds); minuteLabel = try c.decode(String.self, forKey: .minuteLabel)
        scorer = try c.decodeIfPresent(String.self, forKey: .scorer); ownGoal = try c.decodeIfPresent(Bool.self, forKey: .ownGoal) ?? false
        penalty = try c.decodeIfPresent(Bool.self, forKey: .penalty) ?? false; autoFilled = try c.decodeIfPresent(Bool.self, forKey: .autoFilled) ?? false
        autoAdded = try c.decodeIfPresent(Bool.self, forKey: .autoAdded) ?? false
        autoAddedKey = try c.decodeIfPresent(String.self, forKey: .autoAddedKey)
    }
}

public enum KickResult: String, Codable, Sendable { case pending, scored, missed }

public struct Kick: Codable, Sendable, Identifiable, Equatable {
    public var id: UUID
    public var side: Side
    public var result: KickResult
    public init(id: UUID = UUID(), side: Side, result: KickResult) { self.id = id; self.side = side; self.result = result }
}

public struct Shootout: Codable, Sendable, Equatable {
    public var kicks: [Kick]
    public var firstKicker: Side
    public init(kicks: [Kick] = [], firstKicker: Side) { self.kicks = kicks; self.firstKicker = firstKicker }

    public func tally(_ side: Side) -> Int { kicks.filter { $0.side == side && $0.result == .scored }.count }
    public func taken(_ side: Side) -> Int { kicks.filter { $0.side == side }.count }
    // Taken counts, not kicks.count % 2: strict alternation breaks once removeKick takes a kick back out of order.
    public var nextSide: Side { taken(firstKicker) <= taken(firstKicker.other) ? firstKicker : firstKicker.other }
}

/// A club as it appears in one match. Copied from the library so a later library edit does not change a live bug.
public struct TeamEntry: Codable, Sendable, Equatable {
    public var clubId: UUID?
    public var name: String
    public var shortName: String
    public var code: String
    public var primaryColour: String
    public var secondaryColour: String
    public var textColour: String
    public var crestFile: String?
    /// Bumped when the crest image is replaced under the same file name, so overlays fetch it again. Optional; nil on older saves.
    public var crestVersion: Int?
    /// Current squad copied from the club, "K. Mbappé" style, for the scorer picker. Optional since schema 1.
    public var squad: [String]?

    public init(clubId: UUID? = nil, name: String, shortName: String? = nil, code: String, primaryColour: String = "#222222", secondaryColour: String = "#FFFFFF", textColour: String = "#FFFFFF", crestFile: String? = nil, crestVersion: Int? = nil, squad: [String]? = nil) {
        self.clubId = clubId; self.name = name; self.shortName = shortName ?? name; self.code = code
        self.primaryColour = primaryColour; self.secondaryColour = secondaryColour; self.textColour = textColour; self.crestFile = crestFile; self.crestVersion = crestVersion; self.squad = squad
    }

    public static let placeholderHome = TeamEntry(name: "Home", shortName: "Home", code: "HOM", primaryColour: "#1D4ED8")
    public static let placeholderAway = TeamEntry(name: "Away", shortName: "Away", code: "AWY", primaryColour: "#DC2626")
}

public struct LastGoal: Codable, Sendable, Equatable {
    public var side: Side
    public var at: Date
    public var goalId: UUID
}

/// First-leg score of a two-legged tie; the overlay adds the live score to get the running aggregate.
public struct Aggregate: Codable, Sendable, Equatable {
    public var firstLegHome: Int
    public var firstLegAway: Int
    public init(firstLegHome: Int, firstLegAway: Int) { self.firstLegHome = firstLegHome; self.firstLegAway = firstLegAway }
}

public struct Match: Codable, Sendable, Equatable {
    public var slot: Int
    public var competitionId: String
    public var home: TeamEntry
    public var away: TeamEntry
    public var kickoff: Date?
    public var phase: Phase
    public var clock: Clock
    public var addedMinutes: Int?
    public var homeScore: Int
    public var awayScore: Int
    public var goals: [Goal]
    public var shootout: Shootout?
    public var visible: Bool
    public var lastGoal: LastGoal?
    public var revision: Int
    /// Optional theme override; nil means the competition's theme.
    public var themeId: String?
    /// Nil unless this match is one leg of a two-legged tie. Optional since schema 1.
    public var aggregate: Aggregate?
    /// Manual scorer strap visibility. Optional in decoding (old state.json files default to false).
    public var showScorers: Bool
    /// ESPN event link and opt-in scorer filling, optional for existing schema-1 files.
    public var espnEventId: String?
    public var espnLeague: String?
    public var fillScorersFromESPN: Bool
    public var autoUpdateLiveData: Bool
    public var liveDataDelayMinutes: Int
    public var liveDataNotice: String?
    public var removedLiveGoalKeys: [String]
    /// True when the teams were swapped after the live link was made, so the feed's home is this match's away.
    /// Live goal identity keys stay in the feed's own sides. Optional in decoding (false) since schema 1.
    public var liveSidesSwapped: Bool

    public init(slot: Int, competitionId: String = "ligue1", home: TeamEntry = .placeholderHome, away: TeamEntry = .placeholderAway) {
        self.slot = slot; self.competitionId = competitionId; self.home = home; self.away = away
        self.kickoff = nil; self.phase = .preMatch; self.clock = Clock(); self.addedMinutes = nil
        self.homeScore = 0; self.awayScore = 0; self.goals = []; self.shootout = nil
        self.visible = true; self.lastGoal = nil; self.revision = 0; self.themeId = nil
        self.aggregate = nil; self.showScorers = false; self.espnEventId = nil; self.espnLeague = nil
        self.fillScorersFromESPN = true; self.autoUpdateLiveData = true; self.liveDataDelayMinutes = 5; self.liveDataNotice = nil
        self.removedLiveGoalKeys = []; self.liveSidesSwapped = false
    }

    private enum CodingKeys: String, CodingKey {
        case slot, competitionId, home, away, kickoff, phase, clock, addedMinutes, homeScore, awayScore
        case goals, shootout, visible, lastGoal, revision, themeId, aggregate, showScorers, espnEventId, espnLeague, fillScorersFromESPN, autoUpdateLiveData, liveDataDelayMinutes, liveDataNotice, removedLiveGoalKeys, liveSidesSwapped
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        slot = try c.decode(Int.self, forKey: .slot)
        competitionId = try c.decode(String.self, forKey: .competitionId)
        home = try c.decode(TeamEntry.self, forKey: .home)
        away = try c.decode(TeamEntry.self, forKey: .away)
        kickoff = try c.decodeIfPresent(Date.self, forKey: .kickoff)
        phase = try c.decode(Phase.self, forKey: .phase)
        clock = try c.decode(Clock.self, forKey: .clock)
        addedMinutes = try c.decodeIfPresent(Int.self, forKey: .addedMinutes)
        homeScore = try c.decode(Int.self, forKey: .homeScore)
        awayScore = try c.decode(Int.self, forKey: .awayScore)
        goals = try c.decode([Goal].self, forKey: .goals)
        shootout = try c.decodeIfPresent(Shootout.self, forKey: .shootout)
        visible = try c.decode(Bool.self, forKey: .visible)
        lastGoal = try c.decodeIfPresent(LastGoal.self, forKey: .lastGoal)
        revision = try c.decode(Int.self, forKey: .revision)
        themeId = try c.decodeIfPresent(String.self, forKey: .themeId)
        aggregate = try c.decodeIfPresent(Aggregate.self, forKey: .aggregate)
        showScorers = try c.decodeIfPresent(Bool.self, forKey: .showScorers) ?? false
        espnEventId = try c.decodeIfPresent(String.self, forKey: .espnEventId); espnLeague = try c.decodeIfPresent(String.self, forKey: .espnLeague)
        fillScorersFromESPN = try c.decodeIfPresent(Bool.self, forKey: .fillScorersFromESPN) ?? true
        autoUpdateLiveData = try c.decodeIfPresent(Bool.self, forKey: .autoUpdateLiveData) ?? fillScorersFromESPN
        liveDataDelayMinutes = min(10, max(0, try c.decodeIfPresent(Int.self, forKey: .liveDataDelayMinutes) ?? 5))
        liveDataNotice = try c.decodeIfPresent(String.self, forKey: .liveDataNotice)
        removedLiveGoalKeys = try c.decodeIfPresent([String].self, forKey: .removedLiveGoalKeys) ?? []
        liveSidesSwapped = try c.decodeIfPresent(Bool.self, forKey: .liveSidesSwapped) ?? false
    }

    public func score(_ side: Side) -> Int { side == .home ? homeScore : awayScore }
    public func team(_ side: Side) -> TeamEntry { side == .home ? home : away }
    public var currentPeriod: Period? { phase.period }
}

public struct Club: Codable, Sendable, Identifiable, Equatable {
    public var id: UUID
    public var name: String
    public var shortName: String
    public var defaultCode: String
    /// Competition id to the code that competition's broadcast uses, for example ligue1 -> OM, champions-league -> MAR.
    public var codes: [String: String]
    public var primaryColour: String
    public var secondaryColour: String
    public var textColour: String
    public var crestFile: String?
    /// See `TeamEntry.crestVersion`. Optional; nil on older saves.
    public var crestVersion: Int?
    /// File name to look for when importing a crest folder, for example "PSG.png".
    public var crestSource: String?
    public var sourceIds: [String: String]
    public var competitionIds: [String]
    /// For national teams: UEFA, CONMEBOL, CONCACAF, CAF, AFC or OFC. Nil for clubs. Optional since schema 1.
    public var confederation: String?
    /// Current squad, one entry per player as "K. Mbappé". Optional since schema 1.
    public var squad: [String]?

    public init(id: UUID = UUID(), name: String, shortName: String, defaultCode: String, codes: [String: String] = [:], primaryColour: String, secondaryColour: String = "#FFFFFF", textColour: String = "#FFFFFF", crestFile: String? = nil, crestSource: String? = nil, sourceIds: [String: String] = [:], competitionIds: [String] = [], confederation: String? = nil, squad: [String]? = nil) {
        self.id = id; self.name = name; self.shortName = shortName; self.defaultCode = defaultCode; self.codes = codes
        self.primaryColour = primaryColour; self.secondaryColour = secondaryColour; self.textColour = textColour
        self.crestFile = crestFile; self.crestSource = crestSource; self.sourceIds = sourceIds; self.competitionIds = competitionIds; self.confederation = confederation; self.squad = squad
    }

    public func code(for competitionId: String) -> String { codes[competitionId] ?? defaultCode }

    /// Team picker rule: an empty membership means every competition and "other" shows everything; otherwise the
    /// club's own memberships decide, national teams included (the Nations League lists its nations).
    public func isEligible(for competitionId: String) -> Bool {
        competitionIds.isEmpty || competitionId == "other" || competitionIds.contains(competitionId)
    }

    public func entry(for competitionId: String) -> TeamEntry {
        TeamEntry(clubId: id, name: name, shortName: shortName, code: code(for: competitionId), primaryColour: primaryColour, secondaryColour: secondaryColour, textColour: textColour, crestFile: crestFile, crestVersion: crestVersion, squad: squad)
    }
}

public struct Competition: Codable, Sendable, Identifiable, Equatable {
    public var id: String
    public var name: String
    public var shortName: String
    public var themeId: String
    public var sourceIds: [String: String]
    /// Optional official mark imported by the user, stored under crests/. Optional since schema 1.
    public var logoFile: String?
    /// Bumped when the logo is replaced under the same file name, so overlays fetch it again. Optional; nil on older saves.
    public var logoVersion: Int?
    public init(id: String, name: String, shortName: String, themeId: String, sourceIds: [String: String] = [:], logoFile: String? = nil) {
        self.id = id; self.name = name; self.shortName = shortName; self.themeId = themeId; self.sourceIds = sourceIds; self.logoFile = logoFile
    }

    /// League competitions that never have a two-legged tie, an aggregate or a knockout shootout. The only
    /// place this list lives; `hasKnockouts` reads it by instance, `hasKnockouts(id:)` by a bare id.
    private static let leagueIds: Set<String> = ["ligue1", "premier-league", "la-liga", "serie-a", "bundesliga"]
    public var hasKnockouts: Bool { Competition.hasKnockouts(id: id) }
    public static func hasKnockouts(id: String) -> Bool { !leagueIds.contains(id) }
}

public struct Library: Codable, Sendable, Equatable {
    public var schema: Int
    public var competitions: [Competition]
    public var clubs: [Club]
    public init(schema: Int = currentSchema, competitions: [Competition] = [], clubs: [Club] = []) {
        self.schema = schema; self.competitions = competitions; self.clubs = clubs
    }
    public func clubs(in competitionId: String) -> [Club] {
        clubs.filter { $0.competitionIds.isEmpty || $0.competitionIds.contains(competitionId) }.sorted { $0.name < $1.name }
    }
}

public struct MatchState: Codable, Sendable, Equatable {
    public var schema: Int
    public var matches: [Match]
    public init(schema: Int = currentSchema, matches: [Match] = [Match(slot: 1), Match(slot: 2)]) {
        self.schema = schema; self.matches = matches
    }
    public func match(slot: Int) -> Match? { matches.first { $0.slot == slot } }
}

public struct Settings: Codable, Sendable, Equatable {
    public var schema: Int
    public var port: Int
    public var dataSourceOrder: [String]
    public var themeOverridesEnabled: Bool
    /// Folder scanned for crest images by club name. Optional since schema 1.
    public var crestFolder: String?
    /// Live override for the top edge (px) of the primary portrait bug on the 1080x1920 canvas, applied over every
    /// theme's `geometry.v.top`. Optional in Codable so settings.json files saved before this field decode fine;
    /// defaults to 100 when absent. Schema unchanged.
    public var portraitTop: Int
    /// Backdrop shown behind the bug in the app's own preview panes only (never OBS): `nil` (none), `"pitch"`
    /// (drawn stadium green, no asset), or an absolute path to a still or a muted looping video. Optional
    /// since schema 1.
    public var previewBackdrop: String?
    public var liveSourceEnabled: [String: Bool]

    public init(schema: Int = currentSchema, port: Int = 8600, dataSourceOrder: [String] = ["footballData", "espn"], themeOverridesEnabled: Bool = true, crestFolder: String? = nil, portraitTop: Int = 100, previewBackdrop: String? = nil, liveSourceEnabled: [String: Bool] = ["ESPN": true, "FotMob": true, "SofaScore": false]) {
        self.schema = schema; self.port = port; self.dataSourceOrder = dataSourceOrder; self.themeOverridesEnabled = themeOverridesEnabled
        self.crestFolder = crestFolder; self.portraitTop = portraitTop; self.previewBackdrop = previewBackdrop; self.liveSourceEnabled = liveSourceEnabled
    }

    private enum CodingKeys: String, CodingKey {
        case schema, port, dataSourceOrder, themeOverridesEnabled, crestFolder, portraitTop, previewBackdrop, liveSourceEnabled
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schema = try c.decode(Int.self, forKey: .schema)
        port = try c.decode(Int.self, forKey: .port)
        dataSourceOrder = try c.decode([String].self, forKey: .dataSourceOrder)
        themeOverridesEnabled = try c.decode(Bool.self, forKey: .themeOverridesEnabled)
        crestFolder = try c.decodeIfPresent(String.self, forKey: .crestFolder)
        portraitTop = try c.decodeIfPresent(Int.self, forKey: .portraitTop) ?? 100
        previewBackdrop = try c.decodeIfPresent(String.self, forKey: .previewBackdrop)
        liveSourceEnabled = try c.decodeIfPresent([String: Bool].self, forKey: .liveSourceEnabled) ?? ["ESPN": true, "FotMob": true, "SofaScore": false]
    }
}

/// Overlay-wide settings, distinct from per-match state. `previewBackdrop` rides here too so overlay.js can
/// read it from the same broadcast state; it only acts on it when the page was opened with `?preview=1`.
public struct OverlaySettings: Codable, Sendable, Equatable {
    public var portraitTop: Int
    public var previewBackdrop: String?
    /// Whether the user override folder is in use; an overlay page reloads its files when this changes.
    public var themeOverrides: Bool?
    public init(portraitTop: Int, previewBackdrop: String? = nil, themeOverrides: Bool = false) { self.portraitTop = portraitTop; self.previewBackdrop = previewBackdrop; self.themeOverrides = themeOverrides }
}

/// What the overlay pages and the Stream Deck receive. One message, full state.
public struct StateSnapshot: Codable, Sendable {
    public var schema: Int
    public var serverTime: Date
    public var matches: [Match]
    public var competitions: [Competition]
    public var overlay: OverlaySettings
    public init(serverTime: Date, matches: [Match], competitions: [Competition], overlay: OverlaySettings) {
        self.schema = currentSchema; self.serverTime = serverTime; self.matches = matches; self.competitions = competitions; self.overlay = overlay
    }
}

public enum JSONCoding {
    public static func encoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .millisecondsSince1970
        e.outputFormatting = [.sortedKeys]
        return e
    }
    public static func prettyEncoder() -> JSONEncoder {
        let e = encoder(); e.outputFormatting = [.sortedKeys, .prettyPrinted]; return e
    }
    public static func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .millisecondsSince1970
        return d
    }
}
