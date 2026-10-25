// Pure transitions (Match, Command, now) -> Match. No timers, no I/O. See ARCHITECTURE.md "MatchEngine".
import Foundation

public enum Command: Sendable, Equatable {
    case goal(Side, Int)
    /// `ownGoal`/`penalty` nil leaves that `Goal` field as it was; only a non-nil value overwrites it.
    case setScorer(UUID, String?, ownGoal: Bool?, penalty: Bool?)
    case startPeriod(Period)
    case endPeriod
    /// One-way start: a running clock stays running. `playPause` is the toggle for a single key or button.
    case play
    case playPause
    case pause
    case setAddedMinutes(Int?)
    case adjustAddedMinutes(Int)
    case setVisible(Bool)
    case toggleVisible
    case startShootout(Side)
    case recordKick(Side?, KickResult)
    case undoKick
    /// Edits one kick already taken, 0-based within that side's own kicks. Ignored outside a shootout or out of range.
    case setKick(Side, index: Int, result: KickResult)
    /// Removes one kick already taken, 0-based within that side's own kicks. Ignored outside a shootout or out of range.
    case removeKick(Side, index: Int)
    case setTeam(Side, TeamEntry)
    case swapTeams
    case setCompetition(String)
    case setKickoff(Date?)
    case setTheme(String?)
    /// First-leg score of a two-legged tie; the overlay adds the live score to get the aggregate shown.
    case setAggregate(home: Int, away: Int)
    case clearAggregate
    case setShowScorers(Bool)
    case toggleShowScorers
    case setLiveLink(eventId: String?, league: String?)
    case setAutoUpdateLiveData(Bool)
    case setLiveDataDelay(Int)
    case setLiveNotice(String?)
    /// Re-labels and re-times a goal after the fact. `plus` over 0 makes `"45+2'"`, else `"47'"`.
    case setGoalMinute(UUID, minute: Int, plus: Int?)
    case removeGoal(UUID)
    /// Manual clock correction, for when play was pressed late and the bug needs to line up with the broadcast.
    ///
    /// `seconds` is the elapsed time **within the current period**, the same period-local quantity
    /// `Clock.accumulated` (plus any running delta) already tracks, counted from that period's own zero.
    /// `Clock.periodBaseSeconds` is left untouched, so the cumulative reading the overlay derives via
    /// `Clock.elapsed(at:)` is `periodBaseSeconds + seconds`: setting 47:00 (2820s) during the second half
    /// (base 45:00) reads 92:00 on screen for a `runOn` theme. Whether the clock is running or paused is
    /// preserved: running clocks keep counting up from the new value; paused clocks freeze at it. A no-op
    /// outside a live period (no current period means no clock to set).
    case setClock(seconds: Int)
    /// Nudges the clock by `deltaSeconds` (negative to wind it back), using the same period-local accounting
    /// as `setClock`, so the effect on the on-screen cumulative reading is identical regardless of period.
    /// Clamps at 0 for the period (never carries a period's elapsed below its own start). A no-op outside a
    /// live period.
    case adjustClock(deltaSeconds: Int)
    case reset
}

/// Flat JSON shape accepted by POST /api/match/{slot}/command and sent by the Stream Deck.
///
/// Commands: goal, setScorer, startPeriod, endPeriod, play, pause, playPause, setAddedMinutes,
/// adjustAddedMinutes, setVisible, toggleVisible, startShootout, recordKick, undoKick, setKick, removeKick,
/// setTeam, swapTeams, setCompetition, setTheme, setAggregate, clearAggregate, setShowScorers, toggleScorers,
/// setGoalMinute, removeGoal, reset, and the manual clock corrections below.
///
///   {"command":"setGoalMinute","goalId":"…","minute":45,"plus":2} -> Command.setGoalMinute(id, minute: 45, plus: 2)
///   {"command":"removeGoal","goalId":"…"}                         -> Command.removeGoal(id)
///
///   {"command":"setClock","seconds":754}        -> Command.setClock(seconds: 754)
///   {"command":"adjustClock","delta":-5}         -> Command.adjustClock(deltaSeconds: -5)
///   {"command":"adjustClock","deltaSeconds":-5}  -> same, "deltaSeconds" is accepted as an alias of "delta"
///   {"command":"setAggregate","home":2,"away":1} -> Command.setAggregate(home: 2, away: 1)
///
/// See `Command.setClock` and `Command.adjustClock` for what `seconds` and the delta mean against the
/// current period's base.
public struct CommandRequest: Codable, Sendable {
    public var command: String
    public var strict: Bool?
    public var side: String?
    public var delta: Int?
    public var minutes: Int?
    public var period: String?
    public var result: String?
    public var visible: Bool?
    public var goalId: String?
    public var scorer: String?
    public var ownGoal: Bool?
    public var penalty: Bool?
    public var competitionId: String?
    public var team: TeamEntry?
    public var themeId: String?
    public var seconds: Int?
    /// Alias of `delta` for "adjustClock", since a bare "delta" reads ambiguously next to "seconds".
    public var deltaSeconds: Int?
    /// "setAggregate" only: first-leg goals for this match's home and away side.
    public var home: Int?
    public var away: Int?
    public var showScorers: Bool?
    /// "setGoalMinute" only.
    public var minute: Int?
    public var plus: Int?
    /// "setKick"/"removeKick" only: 0-based within that side's own kicks.
    public var index: Int?
    public var eventId: String?

    public init(command: String, side: String? = nil, delta: Int? = nil, minutes: Int? = nil, period: String? = nil, result: String? = nil, visible: Bool? = nil, goalId: String? = nil, scorer: String? = nil, ownGoal: Bool? = nil, penalty: Bool? = nil, competitionId: String? = nil, team: TeamEntry? = nil, themeId: String? = nil, seconds: Int? = nil, deltaSeconds: Int? = nil, home: Int? = nil, away: Int? = nil, showScorers: Bool? = nil, minute: Int? = nil, plus: Int? = nil, index: Int? = nil, eventId: String? = nil, strict: Bool? = nil) {
        self.strict = strict
        self.command = command; self.side = side; self.delta = delta; self.minutes = minutes; self.period = period
        self.result = result; self.visible = visible; self.goalId = goalId; self.scorer = scorer; self.ownGoal = ownGoal; self.penalty = penalty
        self.competitionId = competitionId; self.team = team; self.themeId = themeId
        self.seconds = seconds; self.deltaSeconds = deltaSeconds; self.home = home; self.away = away; self.showScorers = showScorers
        self.minute = minute; self.plus = plus; self.index = index; self.eventId = eventId
    }

    public func toCommand() throws -> Command {
        func sideValue() throws -> Side {
            guard let s = side, let v = Side(rawValue: s) else { throw EngineError.badRequest("side must be home or away") }
            return v
        }
        switch command {
        case "goal": return .goal(try sideValue(), delta ?? 1)
        case "setScorer":
            guard let g = goalId, let id = UUID(uuidString: g) else { throw EngineError.badRequest("goalId required") }
            return .setScorer(id, scorer, ownGoal: ownGoal, penalty: penalty)
        case "startPeriod":
            guard let p = period, let v = Period(rawValue: p) else { throw EngineError.badRequest("period must be firstHalf, secondHalf, extraFirst or extraSecond") }
            return .startPeriod(v)
        case "endPeriod": return .endPeriod
        case "play": return .play
        case "pause": return .pause
        case "playPause": return .playPause
        case "setAddedMinutes": return .setAddedMinutes(minutes)
        case "adjustAddedMinutes": return .adjustAddedMinutes(delta ?? 1)
        case "setVisible": return .setVisible(visible ?? true)
        case "toggleVisible": return .toggleVisible
        case "startShootout": return .startShootout(side == nil ? .home : try sideValue())
        case "recordKick":
            guard let r = result, let v = KickResult(rawValue: r), v != .pending else { throw EngineError.badRequest("result must be scored or missed") }
            return .recordKick(side == nil ? nil : try sideValue(), v)
        case "undoKick": return .undoKick
        case "setKick":
            guard let i = index, let r = result, let v = KickResult(rawValue: r), v != .pending else { throw EngineError.badRequest("side, index and result (scored or missed) required") }
            return .setKick(try sideValue(), index: i, result: v)
        case "removeKick":
            guard let i = index else { throw EngineError.badRequest("side and index required") }
            return .removeKick(try sideValue(), index: i)
        case "setTeam":
            guard let t = team else { throw EngineError.badRequest("team required") }
            return .setTeam(try sideValue(), t)
        case "swapTeams": return .swapTeams
        case "setCompetition":
            guard let c = competitionId else { throw EngineError.badRequest("competitionId required") }
            return .setCompetition(c)
        case "setTheme": return .setTheme(themeId)
        case "setAggregate":
            guard let h = home, let a = away else { throw EngineError.badRequest("home and away required") }
            return .setAggregate(home: h, away: a)
        case "clearAggregate": return .clearAggregate
        case "setShowScorers": return .setShowScorers(showScorers ?? true)
        case "toggleScorers": return .toggleShowScorers
        case "linkESPN":
            guard let eventId, eventId.range(of: "^[0-9]{1,12}$", options: .regularExpression) != nil,
                  let competitionId, competitionId.range(of: "^[a-z0-9._-]{1,40}$", options: .regularExpression) != nil else { throw EngineError.badRequest("eventId must be 1 to 12 digits; league must be 1 to 40 letters, digits, dots, underscores or hyphens") }
            return .setLiveLink(eventId: eventId, league: competitionId)
        case "unlinkESPN": return .setLiveLink(eventId: nil, league: nil)
        case "setAutoUpdateLiveData": return .setAutoUpdateLiveData(showScorers ?? true)
        case "setLiveDataDelay": return .setLiveDataDelay(max(0, min(10, minutes ?? 5)))
        case "setGoalMinute":
            guard let g = goalId, let id = UUID(uuidString: g), let min = minute else { throw EngineError.badRequest("goalId and minute required") }
            return .setGoalMinute(id, minute: min, plus: plus)
        case "removeGoal":
            guard let g = goalId, let id = UUID(uuidString: g) else { throw EngineError.badRequest("goalId required") }
            return .removeGoal(id)
        case "setClock":
            guard let s = seconds else { throw EngineError.badRequest("seconds required") }
            return .setClock(seconds: s)
        case "adjustClock": return .adjustClock(deltaSeconds: delta ?? deltaSeconds ?? 0)
        case "reset": return .reset
        default: throw EngineError.badRequest("unknown command \(command)")
        }
    }
}

public enum EngineError: Error, Equatable, CustomStringConvertible {
    case badRequest(String)
    case notApplied(String)
    public var description: String { switch self { case .badRequest(let m), .notApplied(let m): return m } }
}

public enum MatchEngine {
    public static func apply(_ command: Command, to input: Match, now: Date) -> Match {
        var m = input
        switch command {
        case .goal(let side, let delta):
            guard m.phase != .shootout else { return m }
            if delta > 0 {
                let elapsed = Int(m.clock.elapsed(at: now))
                let goal = Goal(side: side, elapsedSeconds: elapsed, minuteLabel: minuteLabel(elapsed: elapsed, phase: m.phase))
                m.goals.append(goal)
                setScore(&m, side, m.score(side) + 1)
                m.lastGoal = LastGoal(side: side, at: now, goalId: goal.id)
            } else if delta < 0 {
                if let idx = m.goals.lastIndex(where: { $0.side == side }) { m.goals.remove(at: idx) }
                setScore(&m, side, max(0, m.score(side) - 1))
                m.lastGoal = nil
            }
        case .setScorer(let id, let scorer, let ownGoal, let penalty):
            guard let idx = m.goals.firstIndex(where: { $0.id == id }) else { return m }
            let trimmed = scorer?.trimmingCharacters(in: .whitespacesAndNewlines)
            m.goals[idx].scorer = (trimmed?.isEmpty ?? true) ? nil : trimmed.map(LiveDataLogic.displayScorer)
            m.goals[idx].autoFilled = false
            if let ownGoal { m.goals[idx].ownGoal = ownGoal }
            if let penalty { m.goals[idx].penalty = penalty }
        case .startPeriod(let period):
            // Re-pressing the live period's pill must not zero a running clock.
            guard m.currentPeriod != period else { return m }
            m.phase = period.phase
            m.clock = Clock(periodBaseSeconds: period.baseSeconds, periodStart: now, accumulated: 0, running: true)
            m.addedMinutes = nil
        case .endPeriod:
            guard let period = m.currentPeriod else { return m }
            freeze(&m.clock, now: now)
            m.phase = period.breakPhase
        case .play:
            guard m.currentPeriod != nil, !m.clock.running else { return m }
            m.clock.periodStart = now; m.clock.running = true
        case .playPause:
            guard m.currentPeriod != nil else { return m }
            if m.clock.running { freeze(&m.clock, now: now) } else { m.clock.periodStart = now; m.clock.running = true }
        case .pause:
            guard m.currentPeriod != nil, m.clock.running else { return m }
            freeze(&m.clock, now: now)
        case .setAddedMinutes(let minutes):
            let value = min(30, max(0, minutes ?? 0))
            m.addedMinutes = value > 0 ? value : nil
        case .adjustAddedMinutes(let delta):
            let value = min(30, max(0, min(30, max(0, m.addedMinutes ?? 0)) + min(30, max(-30, delta))))
            m.addedMinutes = value > 0 ? value : nil
        case .setVisible(let v):
            m.visible = v
        case .toggleVisible:
            m.visible.toggle()
        case .startShootout(let first):
            // Allowed from any phase after kick-off, including live play; only a pre-match press is ignored.
            guard m.phase != .preMatch else { return m }
            freeze(&m.clock, now: now)
            m.phase = .shootout
            m.addedMinutes = nil
            m.shootout = Shootout(firstKicker: first)
        case .recordKick(let side, let result):
            // No phase guard: a period pill press can leave the match in another phase with m.shootout still set,
            // and this should still append then (setKick, removeKick and undoKick already had no phase guard).
            guard var s = m.shootout else { return m }
            s.kicks.append(Kick(side: side ?? s.nextSide, result: result))
            m.shootout = s
        case .undoKick:
            guard var s = m.shootout, !s.kicks.isEmpty else { return m }
            s.kicks.removeLast()
            m.shootout = s
        case .setKick(let side, let index, let result):
            // No phase guard: a period pill press can leave the match in another phase with m.shootout still set,
            // and these edits should still apply then (undoKick already had no phase guard; this matches it).
            guard var s = m.shootout, let i = kickIndex(s, side, index) else { return m }
            s.kicks[i].result = result
            m.shootout = s
        case .removeKick(let side, let index):
            guard var s = m.shootout, let i = kickIndex(s, side, index) else { return m }
            s.kicks.remove(at: i)
            m.shootout = s
        case .setTeam(let side, let entry):
            let old = m.team(side)
            let changed = old.clubId != entry.clubId || (old.clubId == nil && old.name != entry.name)
            if side == .home { m.home = entry } else { m.away = entry }
            if changed {
                m.kickoff = nil; m.espnEventId = nil; m.espnLeague = nil
                m.aggregate = nil; m.liveDataNotice = nil
            }
        case .swapTeams:
            swap(&m.home, &m.away)
            swap(&m.homeScore, &m.awayScore)
            m.goals = m.goals.map { var g = $0; g.side = g.side.other; return g }
            if var s = m.shootout {
                s.firstKicker = s.firstKicker.other
                s.kicks = s.kicks.map { var k = $0; k.side = k.side.other; return k }
                m.shootout = s
            }
            if var agg = m.aggregate {
                swap(&agg.firstLegHome, &agg.firstLegAway)
                m.aggregate = agg
            }
            m.liveSidesSwapped.toggle()
            m.lastGoal = nil
        case .setCompetition(let id):
            m.competitionId = id
            if !Competition.hasKnockouts(id: id) { m.aggregate = nil }
        case .setKickoff(let date):
            m.kickoff = date
        case .setTheme(let id):
            m.themeId = (id?.isEmpty ?? true) ? nil : id
        case .setAggregate(let home, let away):
            m.aggregate = Aggregate(firstLegHome: min(99, max(0, home)), firstLegAway: min(99, max(0, away)))
        case .clearAggregate:
            m.aggregate = nil
        case .setShowScorers(let v):
            m.showScorers = v
        case .toggleShowScorers:
            m.showScorers.toggle()
        case .setLiveLink(let eventId, let league):
            let nextLeague = eventId == nil ? nil : league
            if m.espnEventId != eventId || m.espnLeague != nextLeague { m.liveSidesSwapped = false }
            m.espnEventId = eventId; m.espnLeague = nextLeague; m.liveDataNotice = nil
        case .setAutoUpdateLiveData(let enabled):
            m.autoUpdateLiveData = enabled; m.fillScorersFromESPN = enabled
        case .setLiveDataDelay(let minutes):
            m.liveDataDelayMinutes = max(0, min(10, minutes))
        case .setLiveNotice(let notice):
            m.liveDataNotice = notice
        case .setGoalMinute(let id, let minute, let plus):
            guard let idx = m.goals.firstIndex(where: { $0.id == id }) else { return m }
            let minute = min(130, max(1, minute)), extra = min(30, max(0, plus ?? 0))
            m.goals[idx].minuteLabel = extra > 0 ? "\(minute)+\(extra)'" : "\(minute)'"
            m.goals[idx].elapsedSeconds = (minute + extra - 1) * 60
            m.goals.sort { $0.elapsedSeconds < $1.elapsedSeconds }
        case .removeGoal(let id):
            guard m.phase != .shootout, let idx = m.goals.firstIndex(where: { $0.id == id }) else { return m }
            let goal = m.goals.remove(at: idx)
            setScore(&m, goal.side, max(0, m.score(goal.side) - 1))
            if m.lastGoal?.goalId == id { m.lastGoal = nil }
        case .setClock(let seconds):
            guard m.currentPeriod != nil else { return m }
            setLocalElapsed(&m.clock, to: TimeInterval(min(10000, max(0, seconds))), now: now)
        case .adjustClock(let delta):
            guard m.currentPeriod != nil else { return m }
            let currentLocal = m.clock.elapsed(at: now) - TimeInterval(m.clock.periodBaseSeconds)
            let newLocal = min(10000, max(0, currentLocal + TimeInterval(min(10000, max(-10000, delta)))))
            setLocalElapsed(&m.clock, to: newLocal, now: now)
        case .reset:
            var fresh = Match(slot: m.slot, competitionId: m.competitionId, home: m.home, away: m.away)
            fresh.kickoff = m.kickoff
            fresh.visible = m.visible
            fresh.themeId = m.themeId
            fresh.revision = m.revision
            fresh.aggregate = m.aggregate
            fresh.espnEventId = m.espnEventId; fresh.espnLeague = m.espnLeague
            fresh.fillScorersFromESPN = m.fillScorersFromESPN; fresh.autoUpdateLiveData = m.autoUpdateLiveData
            fresh.liveDataDelayMinutes = m.liveDataDelayMinutes; fresh.removedLiveGoalKeys = m.removedLiveGoalKeys
            fresh.liveSidesSwapped = m.liveSidesSwapped
            m = fresh
        }
        m.revision += 1
        return m
    }

    /// "12'" style minute for a goal, "45+2'" past the end of a period. Football counts the minute in progress.
    public static func minuteLabel(elapsed: Int, phase: Phase) -> String {
        guard let period = phase.period else { return phase.stateLabel ?? "" }
        let minute = elapsed / 60 + 1
        if elapsed >= period.endSeconds {
            let extra = (elapsed - period.endSeconds) / 60 + 1
            return "\(period.endSeconds / 60)+\(extra)'"
        }
        return "\(minute)'"
    }

    /// The global index into `shootout.kicks` for the `index`-th kick (0-based) that side has taken, or nil if out of range.
    private static func kickIndex(_ s: Shootout, _ side: Side, _ index: Int) -> Int? {
        let matching = s.kicks.indices.filter { s.kicks[$0].side == side }
        guard index >= 0, index < matching.count else { return nil }
        return matching[index]
    }

    private static func setScore(_ m: inout Match, _ side: Side, _ value: Int) {
        if side == .home { m.homeScore = value } else { m.awayScore = value }
    }

    private static func freeze(_ clock: inout Clock, now: Date) {
        if clock.running, let start = clock.periodStart { clock.accumulated += max(0, now.timeIntervalSince(start)) }
        clock.running = false
        clock.periodStart = nil
    }

    /// Sets the clock's period-local elapsed time, what `accumulated` plus any running delta represents,
    /// i.e. `elapsed(at:) - periodBaseSeconds`, to `local` at `now`, preserving running vs paused. Used by
    /// `setClock` and `adjustClock`; `periodBaseSeconds` itself is never touched here.
    private static func setLocalElapsed(_ clock: inout Clock, to local: TimeInterval, now: Date) {
        clock.accumulated = local
        clock.periodStart = clock.running ? now : nil
    }
}
