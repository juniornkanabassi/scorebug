import Foundation

public struct LiveGoal: Codable, Sendable, Equatable {
    public var side: Side
    public var minute: Int
    public var added: Int
    public var scorer: String?
    public var ownGoal: Bool
    public var penalty: Bool
    public init(side: Side, minute: Int, added: Int = 0, scorer: String? = nil, ownGoal: Bool = false, penalty: Bool = false) {
        self.side = side; self.minute = minute; self.added = added; self.scorer = scorer; self.ownGoal = ownGoal; self.penalty = penalty
    }
    public var minuteLabel: String { added > 0 ? "\(minute)+\(added)'" : "\(minute)'" }
}

public struct LiveMatchData: Sendable, Equatable {
    public var eventId: String
    public var homeName: String
    public var awayName: String
    public var homeScore: Int
    public var awayScore: Int
    public var goals: [LiveGoal]
    public var lineups: [Side: [String]]
    public var isFinished: Bool
    public init(eventId: String, homeName: String, awayName: String, homeScore: Int, awayScore: Int, goals: [LiveGoal], lineups: [Side: [String]] = [:], isFinished: Bool = false) {
        self.eventId = eventId; self.homeName = homeName; self.awayName = awayName; self.homeScore = homeScore; self.awayScore = awayScore; self.goals = goals; self.lineups = lineups; self.isFinished = isFinished
    }
}
public struct LiveGoalAssignment: Sendable, Equatable {
    public var goalId: UUID?
    /// The feed goal with its side mapped onto this match's sides.
    public var liveGoal: LiveGoal
    /// Identity in the feed's own sides, the form saved in `Goal.autoAddedKey` and `Match.removedLiveGoalKeys`.
    public var key: String
    public var shouldAdd: Bool
    public var shouldUpdate: Bool
}
public struct LiveEvent: Sendable, Equatable {
    public var id: String
    public var kickoff: Date
    public init(id: String, kickoff: Date) { self.id = id; self.kickoff = kickoff }
}

/// Name and date based lookup plus a single match fetch keeps provider-specific network code out of AppModel.
public protocol LiveSource: Sendable {
    var name: String { get }
    func findEvent(home: String, away: String, date: Date) async throws -> LiveEvent?
    func fetchGoals(eventId: String) async throws -> LiveMatchData
}

public struct ESPNLiveSource: LiveSource {
    public let name = "ESPN"
    public let league: String
    public init(league: String) { self.league = league }
    public func findEvent(home: String, away: String, date: Date) async throws -> LiveEvent? {
        let fixtures = try await FixtureService.fetch(date: date, apiKey: nil, espnLeague: league)
        guard let fixture = fixtures.first(where: { Store.matchKey($0.home.name) == Store.matchKey(home) && Store.matchKey($0.away.name) == Store.matchKey(away) }),
              let id = fixture.espnEventId else { return nil }
        return LiveEvent(id: id, kickoff: fixture.kickoff)
    }
    public func fetchGoals(eventId: String) async throws -> LiveMatchData {
        let url = URL(string: "https://site.api.espn.com/apis/site/v2/sports/soccer/\(league)/summary?event=\(eventId)")!
        var request = URLRequest(url: url); request.timeoutInterval = 12
        let (data, _) = try await URLSession.shared.data(for: request)
        return try LiveDataLogic.espnSummary(data, eventId: eventId)
    }
}

public struct FotMobLiveSource: LiveSource {
    public let name = "FotMob"
    public init() {}
    public func findEvent(home: String, away: String, date: Date) async throws -> LiveEvent? {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        let url = URL(string: String(format: "https://www.fotmob.com/api/data/matches?date=%04d%02d%02d", parts.year!, parts.month!, parts.day!))!
        let root = try await json(url)
        let leagues = root["leagues"] as? [[String: Any]] ?? []
        guard let match = leagues.flatMap({ $0["matches"] as? [[String: Any]] ?? [] }).first(where: { match in
            let h = (match["home"] as? [String: Any])?["name"] as? String ?? ""
            let a = (match["away"] as? [String: Any])?["name"] as? String ?? ""
            return Store.matchKey(h) == Store.matchKey(home) && Store.matchKey(a) == Store.matchKey(away)
        }), let id = match["id"] as? Int else { return nil }
        let kickoffText = ((match["status"] as? [String: Any])?["utcTime"] as? String) ?? ""
        let formatter = ISO8601DateFormatter()
        return LiveEvent(id: String(id), kickoff: formatter.date(from: kickoffText) ?? date)
    }
    public func fetchGoals(eventId: String) async throws -> LiveMatchData {
        let root = try await json(URL(string: "https://www.fotmob.com/api/data/matchDetails?matchId=\(eventId)")!)
        let header = root["header"] as? [String: Any] ?? [:]
        let teams = header["teams"] as? [[String: Any]] ?? []
        let home = teams.first ?? [:], away = teams.dropFirst().first ?? [:]
        let content = root["content"] as? [String: Any] ?? [:]
        let facts = content["matchFacts"] as? [String: Any] ?? [:]
        let eventContainer = facts["events"] as? [String: Any] ?? [:]
        let events = eventContainer["events"] as? [[String: Any]] ?? []
        let goals = events.compactMap { event -> LiveGoal? in
            guard event["type"] as? String == "Goal", event["isPenaltyShootoutEvent"] as? Bool != true,
                  let side: Side = event["isHome"] as? Bool == true ? .home : .away else { return nil }
            let parsedTime = LiveDataLogic.parseMinute(String(describing: event["timeStr"] ?? ""))
            guard let minute = (event["time"] as? Int) ?? parsedTime?.0 else { return nil }
            let added = (event["overloadTime"] as? Int) ?? parsedTime?.1 ?? 0
            let player = event["player"] as? [String: Any] ?? [:]
            let scorer = event["fullName"] as? String ?? event["nameStr"] as? String ?? player["name"] as? String
            let description = (event["goalDescription"] as? String ?? "").lowercased()
            return LiveGoal(side: side, minute: minute, added: added, scorer: scorer,
                ownGoal: event["ownGoal"] as? Bool ?? false,
                penalty: event["isPenalty"] as? Bool ?? description.contains("penalty"))
        }
        let names: [Side: [String]] = [:]
        func int(_ value: Any?) -> Int { (value as? Int) ?? (value as? String).flatMap(Int.init) ?? 0 }
        let finished = (header["status"] as? [String: Any])?["finished"] as? Bool ?? false
        return LiveMatchData(eventId: eventId, homeName: home["name"] as? String ?? "Home", awayName: away["name"] as? String ?? "Away",
            homeScore: int(home["score"]), awayScore: int(away["score"]), goals: goals, lineups: names, isFinished: finished)
    }
    private func json(_ url: URL) async throws -> [String: Any] {
        var request = URLRequest(url: url); request.timeoutInterval = 12
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        request.setValue("https://www.fotmob.com/", forHTTPHeaderField: "Referer")
        let (data, _) = try await URLSession.shared.data(for: request)
        guard let result = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw URLError(.cannotParseResponse) }
        return result
    }
}

public enum LiveDataLogic {
    /// Identity of a feed goal by its feed side and minute, not position, so a reorder cannot revive a removed goal.
    public static func liveKey(eventId: String, _ goal: LiveGoal) -> String { "\(eventId):\(goal.side.rawValue):\(goal.minute):\(goal.added)" }

    /// One assignment per feed goal, in feed order. Feed sides map onto the match's through `liveSidesSwapped`.
    /// A goal the operator removed is a no-op; a recorded goal carrying a feed goal's key is matched first; the
    /// rest pair by position per side (Codex review, 1 Oct).
    public static func assignments(match: Match, liveGoals: [LiveGoal], eventId: String = "") -> [LiveGoalAssignment] {
        let keys = liveGoals.map { liveKey(eventId: eventId, $0) }
        let removed = Set(match.removedLiveGoalKeys)
        let mapped = liveGoals.map { goal -> LiveGoal in var g = goal; if match.liveSidesSwapped { g.side = g.side.other }; return g }
        var byKey: [Int: Goal] = [:]
        for i in mapped.indices where !removed.contains(keys[i]) {
            if let goal = match.goals.first(where: { $0.autoAddedKey == keys[i] && $0.side == mapped[i].side && !byKey.values.contains($0) }) { byKey[i] = goal }
        }
        let recorded = Dictionary(grouping: match.goals.filter { goal in !byKey.values.contains(goal) }, by: \.side)
        let feed = Dictionary(grouping: mapped.indices.filter { !removed.contains(keys[$0]) && byKey[$0] == nil }, by: { mapped[$0].side })
        var sideIndex: [Side: Int] = [.home: 0, .away: 0]
        func fillable(_ goal: Goal) -> Bool { goal.scorer == nil || goal.scorer?.isEmpty == true || goal.autoFilled }
        return mapped.indices.map { i -> LiveGoalAssignment in
            let live = mapped[i]
            if removed.contains(keys[i]) { return LiveGoalAssignment(goalId: nil, liveGoal: live, key: keys[i], shouldAdd: false, shouldUpdate: false) }
            if let goal = byKey[i] { return LiveGoalAssignment(goalId: goal.id, liveGoal: live, key: keys[i], shouldAdd: false, shouldUpdate: fillable(goal)) }
            let index = sideIndex[live.side, default: 0]
            sideIndex[live.side] = index + 1
            let goals = recorded[live.side, default: []]
            guard goals.indices.contains(index) else { return LiveGoalAssignment(goalId: nil, liveGoal: live, key: keys[i], shouldAdd: true, shouldUpdate: false) }
            let goal = goals[index]
            // The feed has fewer goals for this side than recorded (VAR overturn or a correction): positions no longer
            // line up, so leave that side alone rather than rewrite the wrong row (review of 28 Sep).
            let shouldUpdate = feed[live.side, default: []].count >= goals.count && fillable(goal)
            return LiveGoalAssignment(goalId: goal.id, liveGoal: live, key: keys[i], shouldAdd: false, shouldUpdate: shouldUpdate)
        }
    }
    public static func espnSummary(_ data: Data, eventId: String = "") throws -> LiveMatchData {
        let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        let header = root["header"] as? [String: Any] ?? [:]
        let competition = (header["competitions"] as? [[String: Any]])?.first ?? [:]
        let competitors = competition["competitors"] as? [[String: Any]] ?? []
        func string(_ value: Any?) -> String? { value as? String }
        func score(_ row: [String: Any]) -> Int { Int(string(row["score"]) ?? "") ?? 0 }
        let home = competitors.first { string($0["homeAway"]) == "home" } ?? [:]
        let away = competitors.first { string($0["homeAway"]) == "away" } ?? [:]
        let homeTeam = home["team"] as? [String: Any] ?? [:]
        let awayTeam = away["team"] as? [String: Any] ?? [:]
        let homeId = string(homeTeam["id"]) ?? string(home["id"]) ?? ""
        let awayId = string(awayTeam["id"]) ?? string(away["id"]) ?? ""
        var goals: [LiveGoal] = []
        for detail in competition["details"] as? [[String: Any]] ?? [] where detail["scoringPlay"] as? Bool == true {
            let team = detail["team"] as? [String: Any] ?? [:]
            let scorerTeamId = string(team["id"]) ?? ""
            guard let side: Side = scorerTeamId == homeId ? .home : scorerTeamId == awayId ? .away : nil else { continue }
            // Verified against ESPN finished-match event 401878777 (Manchester United at Fulham, 20 Sep 2026):
            // an own-goal detail's team.id is Fulham's competitor id, the side credited with the goal.
            let clock = (detail["clock"] as? [String: Any])?["displayValue"] as? String ?? ""
            guard let parsedMinute = parseMinute(clock) else { continue }
            let minute = parsedMinute.0
            var added = parsedMinute.1
            if added == 0, let extra = (detail["addedClock"] as? [String: Any])?["displayValue"] as? String,
               let parsedExtra = Int(extra.filter(\.isNumber)), parsedExtra > 0 { added = parsedExtra }
            let athletes = (detail["athletesInvolved"] as? [[String: Any]])
                ?? (detail["participants"] as? [[String: Any]])?.compactMap { $0["athlete"] as? [String: Any] }
                ?? []
            let athlete = athletes.first ?? [:]
            goals.append(LiveGoal(side: side, minute: minute, added: added,
                scorer: string(athlete["displayName"]) ?? string(athlete["shortName"]),
                ownGoal: detail["ownGoal"] as? Bool ?? false, penalty: detail["penaltyKick"] as? Bool ?? false))
        }
        let rosters = root["rosters"] as? [[String: Any]] ?? []
        var names: [Side: [String]] = [.home: [], .away: []]
        for roster in rosters {
            let rosterTeam = roster["team"] as? [String: Any] ?? [:]
            let rosterTeamId = string(rosterTeam["id"]) ?? ""
            let rosterSide: Side? = rosterTeamId == homeId ? .home : rosterTeamId == awayId ? .away : nil
            guard let rosterSide else { continue }
            names[rosterSide, default: []] += (roster["roster"] as? [[String: Any]] ?? []).compactMap {
                ($0["athlete"] as? [String: Any])?["displayName"] as? String
            }
        }
        let status = competition["status"] as? [String: Any] ?? [:]
        let completed = (status["type"] as? [String: Any])?["completed"] as? Bool ?? false
        return LiveMatchData(eventId: eventId, homeName: string(homeTeam["displayName"]) ?? "Home", awayName: string(awayTeam["displayName"]) ?? "Away", homeScore: score(home), awayScore: score(away), goals: goals, lineups: names, isFinished: completed)
    }

    public static func parseMinute(_ label: String) -> (Int, Int)? {
        let cleaned = label.filter { $0.isNumber || $0 == "+" }
        let parts = cleaned.split(separator: "+", omittingEmptySubsequences: false)
        guard parts.count <= 2, let minute = Int(parts[0]), minute > 0 else { return nil }
        let added = parts.count == 2 ? Int(parts[1]) : 0
        guard let added, added >= 0 else { return nil }
        return (minute, added)
    }

    public static func displayScorer(_ value: String) -> String {
        let words = value.split(whereSeparator: \.isWhitespace).map(String.init)
        guard words.count > 1 else { return value }
        let particles: Set<String> = ["de", "van", "von", "da", "di", "del", "le", "la", "ten", "ter"]
        let folded = words.map { $0.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current) }
        var surnameStart = words.count - 1
        while surnameStart > 1 && particles.contains(folded[surnameStart - 1]) { surnameStart -= 1 }
        return "\(words[0].prefix(1)). \(words[surnameStart...].joined(separator: " "))"
    }

    /// Returns the best matching rank: 0 for exact/prefix, 1 for fuzzy, nil for no match.
    public static func scorerRank(_ name: String, query: String) -> (Int, Double)? {
        let q = normalize(query)
        guard !q.isEmpty else { return (0, 1) }
        let rawTokens = name.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map { normalize(String($0)) }
        let tokens = rawTokens.filter { !$0.isEmpty }
        let compact = normalize(name).filter { !$0.isWhitespace }
        let qCompact = q.filter { !$0.isWhitespace }
        let surname = tokens.last ?? ""
        let surnameWithParticles = tokens.suffix(3).joined()
        if tokens.contains(where: { $0.hasPrefix(q) }) || surname == q || surname.hasPrefix(q) || surnameWithParticles.hasPrefix(qCompact) || surnameWithParticles == qCompact || compact.hasPrefix(qCompact) {
            return (0, 1)
        }
        if q.split(whereSeparator: \.isWhitespace).allSatisfy({ token in tokens.contains { $0.hasPrefix(String(token)) } }) { return (0, 1) }
        let candidates = tokens.filter { $0.count >= 4 } + (compact.count >= 4 ? [compact] : [])
        let similarity = candidates.map { jaroWinkler(qCompact, $0) }.max() ?? 0
        return similarity >= 0.85 ? (1, similarity) : nil
    }

    public static func rankedScorers(_ names: [String], query: String) -> [String] {
        let names = deduplicatedScorers(names)
        var ranked: [(name: String, rank: Int, score: Double)] = []
        for name in names {
            guard let match = scorerRank(name, query: query) else { continue }
            ranked.append((name, match.0, match.1))
        }
        ranked.sort {
            if $0.rank != $1.rank { return $0.rank < $1.rank }
            if $0.score != $1.score { return $0.score > $1.score }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
        return ranked.map(\.name)
    }

    public static func deduplicatedScorers(_ names: [String]) -> [String] {
        var unique: [String: String] = [:]
        for name in names where !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let key = dedupeKey(name)
            if unique[key].map({ name.filter(\.isLetter).count > $0.filter(\.isLetter).count }) ?? true { unique[key] = name }
        }
        return unique.values.sorted()
    }

    private static func normalize(_ value: String) -> String {
        value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) || CharacterSet.whitespaces.contains($0) }
            .map(String.init).joined()
    }
    private static func dedupeKey(_ value: String) -> String {
        let tokens = value.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
        guard let surname = tokens.last else { return normalize(value) }
        let initial = tokens.first?.first.map(String.init) ?? ""
        return normalize(surname) + initial
    }
    private static func jaroWinkler(_ lhs: String, _ rhs: String) -> Double {
        let a = Array(lhs), b = Array(rhs)
        guard !a.isEmpty, !b.isEmpty else { return 0 }
        let range = max(0, max(a.count, b.count) / 2 - 1)
        var am = Array(repeating: false, count: a.count), bm = Array(repeating: false, count: b.count), matches = 0
        for i in a.indices {
            let lo = max(0, i - range), hi = min(b.count - 1, i + range)
            guard lo <= hi else { continue }
            for j in lo...hi where !bm[j] && a[i] == b[j] {
                am[i] = true; bm[j] = true; matches += 1; break
            }
        }
        guard matches > 0 else { return 0 }
        let aa = zip(a.indices, am).compactMap { $0.1 ? a[$0.0] : nil }
        let bb = zip(b.indices, bm).compactMap { $0.1 ? b[$0.0] : nil }
        let transpositions = zip(aa, bb).filter(!=).count / 2
        let m = Double(matches)
        let jaro = (m / Double(a.count) + m / Double(b.count) + (m - Double(transpositions)) / m) / 3
        let prefix = zip(a.prefix(4), b.prefix(4)).prefix(while: ==).count
        return jaro + Double(prefix) * 0.1 * (1 - jaro)
    }
}
