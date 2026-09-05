// Pure transitions (Match, Command, now) -> Match. No timers, no I/O. See ARCHITECTURE.md "MatchEngine".
import Foundation

public enum Command: Sendable, Equatable {
    case goal(Side, Int)
    case setScorer(UUID, String?)
    case startPeriod(Period)
    case endPeriod
    case play
    case pause
    case setAddedMinutes(Int?)
    case adjustAddedMinutes(Int)
    case setVisible(Bool)
    case toggleVisible
    case startShootout(Side)
    case recordKick(Side?, KickResult)
    case undoKick
    case setTeam(Side, TeamEntry)
    case swapTeams
    case setCompetition(String)
    case setKickoff(Date?)
    case reset
}

/// Flat JSON shape accepted by POST /api/match/{slot}/command and sent by the Stream Deck.
public struct CommandRequest: Codable, Sendable {
    public var command: String
    public var side: String?
    public var delta: Int?
    public var minutes: Int?
    public var period: String?
    public var result: String?
    public var visible: Bool?
    public var goalId: String?
    public var scorer: String?
    public var competitionId: String?
    public var team: TeamEntry?

    public init(command: String, side: String? = nil, delta: Int? = nil, minutes: Int? = nil, period: String? = nil, result: String? = nil, visible: Bool? = nil, goalId: String? = nil, scorer: String? = nil, competitionId: String? = nil, team: TeamEntry? = nil) {
        self.command = command; self.side = side; self.delta = delta; self.minutes = minutes; self.period = period
        self.result = result; self.visible = visible; self.goalId = goalId; self.scorer = scorer; self.competitionId = competitionId; self.team = team
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
            return .setScorer(id, scorer)
        case "startPeriod":
            guard let p = period, let v = Period(rawValue: p) else { throw EngineError.badRequest("period must be firstHalf, secondHalf, extraFirst or extraSecond") }
            return .startPeriod(v)
        case "endPeriod": return .endPeriod
        case "play": return .play
        case "pause": return .pause
        case "playPause": return .play // resolved by the engine using the running flag
        case "setAddedMinutes": return .setAddedMinutes(minutes)
        case "adjustAddedMinutes": return .adjustAddedMinutes(delta ?? 1)
        case "setVisible": return .setVisible(visible ?? true)
        case "toggleVisible": return .toggleVisible
        case "startShootout": return .startShootout((try? sideValue()) ?? .home)
        case "recordKick":
            guard let r = result, let v = KickResult(rawValue: r), v != .pending else { throw EngineError.badRequest("result must be scored or missed") }
            return .recordKick(try? sideValue(), v)
        case "undoKick": return .undoKick
        case "setTeam":
            guard let t = team else { throw EngineError.badRequest("team required") }
            return .setTeam(try sideValue(), t)
        case "swapTeams": return .swapTeams
        case "setCompetition":
            guard let c = competitionId else { throw EngineError.badRequest("competitionId required") }
            return .setCompetition(c)
        case "reset": return .reset
        default: throw EngineError.badRequest("unknown command \(command)")
        }
    }
}

public enum EngineError: Error, Equatable, CustomStringConvertible {
    case badRequest(String)
    public var description: String { switch self { case .badRequest(let m): return m } }
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
        case .setScorer(let id, let scorer):
            guard let idx = m.goals.firstIndex(where: { $0.id == id }) else { return m }
            let trimmed = scorer?.trimmingCharacters(in: .whitespacesAndNewlines)
            m.goals[idx].scorer = (trimmed?.isEmpty ?? true) ? nil : trimmed
        case .startPeriod(let period):
            m.phase = period.phase
            m.clock = Clock(periodBaseSeconds: period.baseSeconds, periodStart: now, accumulated: 0, running: true)
            m.addedMinutes = nil
        case .endPeriod:
            guard let period = m.currentPeriod else { return m }
            freeze(&m.clock, now: now)
            m.phase = period.breakPhase
        case .play:
            guard m.currentPeriod != nil else { return m }
            if m.clock.running { freeze(&m.clock, now: now) } else { m.clock.periodStart = now; m.clock.running = true }
        case .pause:
            guard m.currentPeriod != nil, m.clock.running else { return m }
            freeze(&m.clock, now: now)
        case .setAddedMinutes(let minutes):
            m.addedMinutes = (minutes ?? 0) > 0 ? minutes : nil
        case .adjustAddedMinutes(let delta):
            let value = max(0, (m.addedMinutes ?? 0) + delta)
            m.addedMinutes = value > 0 ? value : nil
        case .setVisible(let v):
            m.visible = v
        case .toggleVisible:
            m.visible.toggle()
        case .startShootout(let first):
            freeze(&m.clock, now: now)
            m.phase = .shootout
            m.addedMinutes = nil
            m.shootout = Shootout(firstKicker: first)
        case .recordKick(let side, let result):
            guard m.phase == .shootout, var s = m.shootout else { return m }
            s.kicks.append(Kick(side: side ?? s.nextSide, result: result))
            m.shootout = s
        case .undoKick:
            guard var s = m.shootout, !s.kicks.isEmpty else { return m }
            s.kicks.removeLast()
            m.shootout = s
        case .setTeam(let side, let entry):
            if side == .home { m.home = entry } else { m.away = entry }
        case .swapTeams:
            swap(&m.home, &m.away)
            swap(&m.homeScore, &m.awayScore)
            m.goals = m.goals.map { var g = $0; g.side = g.side.other; return g }
            if var s = m.shootout {
                s.firstKicker = s.firstKicker.other
                s.kicks = s.kicks.map { var k = $0; k.side = k.side.other; return k }
                m.shootout = s
            }
            m.lastGoal = nil
        case .setCompetition(let id):
            m.competitionId = id
        case .setKickoff(let date):
            m.kickoff = date
        case .reset:
            var fresh = Match(slot: m.slot, competitionId: m.competitionId, home: m.home, away: m.away)
            fresh.kickoff = m.kickoff
            fresh.visible = m.visible
            fresh.revision = m.revision
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

    private static func setScore(_ m: inout Match, _ side: Side, _ value: Int) {
        if side == .home { m.homeScore = value } else { m.awayScore = value }
    }

    private static func freeze(_ clock: inout Clock, now: Date) {
        if clock.running, let start = clock.periodStart { clock.accumulated += max(0, now.timeIntervalSince(start)) }
        clock.running = false
        clock.periodStart = nil
    }
}
