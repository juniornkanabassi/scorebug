// Assertion suite over ScorebugCore. Run after every engine change.
import Foundation
import ScorebugCore

var failures = 0
func check(_ condition: @autoclosure () -> Bool, _ label: String) {
    if condition() { print("ok   \(label)") } else { failures += 1; print("FAIL \(label)") }
}
func at(_ seconds: Double) -> Date { Date(timeIntervalSince1970: 1_000_000 + seconds) }

// Clock and periods
var m = Match(slot: 1)
m = MatchEngine.apply(.startPeriod(.firstHalf), to: m, now: at(0))
check(m.phase == .firstHalf && m.clock.running, "start first half runs the clock")
check(Int(m.clock.elapsed(at: at(600))) == 600, "elapsed is derived from wall time")
m = MatchEngine.apply(.pause, to: m, now: at(600))
check(!m.clock.running && Int(m.clock.elapsed(at: at(900))) == 600, "pause freezes elapsed")
m = MatchEngine.apply(.play, to: m, now: at(900))
check(Int(m.clock.elapsed(at: at(1000))) == 700, "play resumes from the frozen value")
m = MatchEngine.apply(.play, to: m, now: at(1000))
check(m.clock.running && Int(m.clock.elapsed(at: at(1100))) == 800, "play while running is a no-op (one-way start after startPeriod)")
m = MatchEngine.apply(.playPause, to: m, now: at(1000))
check(!m.clock.running, "playPause while running pauses (single key)")
m = MatchEngine.apply(.playPause, to: m, now: at(1000))
check(m.clock.running, "playPause while paused resumes")
check((try? CommandRequest(command: "playPause").toCommand()) == .playPause, "playPause request decodes to the toggle")

// Added time entered late, freezeAndCount
let lateNow = at(1000 + (2700 - 700) + 75)   // 45:00 plus 75 seconds of play
check(ClockEngine.display(match: m, style: .freezeAndCount, now: lateNow).main == "45:00", "freezeAndCount holds 45:00 past the end")
check(ClockEngine.display(match: m, style: .freezeAndCount, now: lateNow).addedCounter == nil, "no added counter until minutes are announced")
m = MatchEngine.apply(.setAddedMinutes(3), to: m, now: lateNow)
let d = ClockEngine.display(match: m, style: .freezeAndCount, now: lateNow)
check(d.added == "+3" && d.addedCounter == "01:15", "late added time still shows the true elapsed added time")
check(ClockEngine.display(match: m, style: .runOn, now: lateNow).main == "46:15", "runOn keeps counting")
m = MatchEngine.apply(.endPeriod, to: m, now: lateNow)
check(m.phase == .halfTime && !m.clock.running, "end period goes to half time")
check(ClockEngine.display(match: m, style: .freezeAndCount, now: at(9999)).state == "HT", "half time shows HT")
m = MatchEngine.apply(.startPeriod(.secondHalf), to: m, now: at(5000))
check(m.addedMinutes == nil && Int(m.clock.elapsed(at: at(5000))) == 2700, "second half starts at 45:00 with added time cleared")

// Manual clock control (setClock / adjustClock)
// setClock/adjustClock work in period-local seconds: periodBaseSeconds is never touched, so the on-screen
// cumulative reading (what elapsed(at:) and ClockEngine.display show) is periodBaseSeconds + the local value.
var clockM = MatchEngine.apply(.startPeriod(.firstHalf), to: Match(slot: 1), now: at(0))
clockM = MatchEngine.apply(.setClock(seconds: 754), to: clockM, now: at(0))
check(Int(clockM.clock.elapsed(at: at(0))) == 754 && clockM.clock.running, "setClock while running lands on the exact value and keeps running")
check(Int(clockM.clock.elapsed(at: at(10))) == 764, "setClock while running: elapsed 10s later is value + 10")

clockM = MatchEngine.apply(.pause, to: clockM, now: at(10))
clockM = MatchEngine.apply(.setClock(seconds: 500), to: clockM, now: at(10))
check(!clockM.clock.running && Int(clockM.clock.elapsed(at: at(10))) == 500, "setClock while paused lands on the value and stays paused")
check(Int(clockM.clock.elapsed(at: at(9999))) == 500, "setClock while paused: value does not drift with wall time")

clockM = MatchEngine.apply(.adjustClock(deltaSeconds: -600), to: clockM, now: at(10))
check(Int(clockM.clock.elapsed(at: at(10))) == 0, "adjustClock negative past zero clamps at 0 for the period")

clockM = MatchEngine.apply(.play, to: clockM, now: at(10))
clockM = MatchEngine.apply(.adjustClock(deltaSeconds: 30), to: clockM, now: at(20))
check(Int(clockM.clock.elapsed(at: at(20))) == 40 && clockM.clock.running, "adjustClock while running adds to the elapsed value and keeps counting")
check(Int(clockM.clock.elapsed(at: at(25))) == 45, "adjustClock while running: still counts up after the nudge")

var secondHalfM = MatchEngine.apply(.startPeriod(.secondHalf), to: Match(slot: 1), now: at(0))
secondHalfM = MatchEngine.apply(.setClock(seconds: 47 * 60), to: secondHalfM, now: at(0))
check(Int(secondHalfM.clock.elapsed(at: at(0))) == 45 * 60 + 47 * 60, "setClock in the second half adds the period base: 47:00 local reads 92:00 on screen")
check(ClockEngine.display(match: secondHalfM, style: .runOn, now: at(0)).main == "92:00", "runOn display after a set in the second half shows the cumulative 92:00")
let freezeDisplay = ClockEngine.display(match: secondHalfM, style: .freezeAndCount, now: at(0))
check(freezeDisplay.main == "90:00", "freezeAndCount display after a set in the second half still clamps the main clock at the period end")

check((try? CommandRequest(command: "setClock", seconds: 754).toCommand()) == .setClock(seconds: 754), "setClock request decodes")
check((try? CommandRequest(command: "adjustClock", delta: -5).toCommand()) == .adjustClock(deltaSeconds: -5), "adjustClock request decodes \"delta\"")
check((try? CommandRequest(command: "adjustClock", deltaSeconds: -5).toCommand()) == .adjustClock(deltaSeconds: -5), "adjustClock request decodes \"deltaSeconds\" as an alias")
check((try? CommandRequest(command: "setClock").toCommand()) == nil, "setClock without seconds is rejected")

// Goals and minute labels
m = MatchEngine.apply(.goal(.home, 1), to: m, now: at(5000 + 61))
check(m.homeScore == 1 && m.goals.count == 1 && m.goals[0].minuteLabel == "47'", "goal records the minute in progress")
m = MatchEngine.apply(.goal(.away, 1), to: m, now: at(5000 + 2700 + 30))
check(m.goals[1].minuteLabel == "90+1'", "goal in added time is labelled 90+1")
m = MatchEngine.apply(.setScorer(m.goals[0].id, "  Dembélé "), to: m, now: at(0))
check(m.goals[0].scorer == "Dembélé", "scorer is trimmed and stored")
m = MatchEngine.apply(.goal(.home, -1), to: m, now: at(0))
check(m.homeScore == 0 && m.goals.count == 1 && m.goals[0].side == .away, "minus removes that side's last goal")
m = MatchEngine.apply(.goal(.home, -1), to: m, now: at(0))
check(m.homeScore == 0, "score never goes below zero")
check(MatchEngine.minuteLabel(elapsed: 0, phase: .firstHalf) == "1'", "first second is minute 1")
check(MatchEngine.minuteLabel(elapsed: 2700, phase: .firstHalf) == "45+1'", "45:00 exactly is 45+1")
check(MatchEngine.minuteLabel(elapsed: 6299, phase: .extraFirst) == "105'", "extra time first half minute label")

// Shootout
var pre = Match(slot: 1)
pre = MatchEngine.apply(.startShootout(.home), to: pre, now: at(0))
check(pre.phase == .preMatch && pre.shootout == nil, "startShootout before kick-off is ignored")
var live = MatchEngine.apply(.startPeriod(.firstHalf), to: Match(slot: 1), now: at(0))
live = MatchEngine.apply(.startShootout(.home), to: live, now: at(10))
check(live.phase == .firstHalf && live.shootout == nil, "startShootout during a live period is ignored")
live = MatchEngine.apply(.startPeriod(.firstHalf), to: live, now: at(1000))
check(Int(live.clock.elapsed(at: at(1000))) == 1000, "re-pressing the live period does not zero the clock")
m = MatchEngine.apply(.endPeriod, to: m, now: at(0))
m = MatchEngine.apply(.startShootout(.away), to: m, now: at(0))
let before = (m.homeScore, m.awayScore)
m = MatchEngine.apply(.goal(.home, 1), to: m, now: at(0))
check((m.homeScore, m.awayScore) == before, "goal is ignored during the shootout")
m = MatchEngine.apply(.recordKick(nil, .scored), to: m, now: at(0))
check(m.shootout?.kicks.first?.side == .away, "first kick goes to the first kicker when side is omitted")
m = MatchEngine.apply(.recordKick(nil, .missed), to: m, now: at(0))
m = MatchEngine.apply(.recordKick(.away, .scored), to: m, now: at(0))
check(m.shootout?.tally(.away) == 2 && m.shootout?.tally(.home) == 0, "tally counts scored kicks per side")
m = MatchEngine.apply(.undoKick, to: m, now: at(0))
check(m.shootout?.kicks.count == 2, "undo removes the last kick")
for _ in 0..<10 { m = MatchEngine.apply(.recordKick(nil, .scored), to: m, now: at(0)) }
check(m.shootout?.kicks.count == 12, "sudden death has no cap")

// Swap and reset
m = MatchEngine.apply(.swapTeams, to: m, now: at(0))
check(m.home.code == "AWY" && m.awayScore == 0 && m.goals[0].side == .home, "swap moves teams, scores and goals together")
let rev = m.revision
m = MatchEngine.apply(.reset, to: m, now: at(0))
check(m.phase == .preMatch && m.goals.isEmpty && m.shootout == nil && m.home.code == "AWY" && m.revision == rev + 1, "reset zeroes the match but keeps teams and bumps revision")

// Command requests
check((try? CommandRequest(command: "goal", side: "home").toCommand()) == .goal(.home, 1), "goal request decodes")
check((try? CommandRequest(command: "goal").toCommand()) == nil, "goal without side is rejected")
check((try? CommandRequest(command: "recordKick", result: "pending").toCommand()) == nil, "pending is not a kick result")
check((try? CommandRequest(command: "startPeriod", period: "extraSecond").toCommand()) == .startPeriod(.extraSecond), "period request decodes")

// Persistence round trip on a disposable directory
let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("scorebug-checks-\(UUID().uuidString)")
do {
    let store = try Store(directory: tmp)
    let lib = try store.loadLibrary()
    check(lib.clubs.contains { $0.shortName == "PSG" } && lib.competitions.count >= 6, "seed library is written on first run")
    check(lib.clubs.first { $0.shortName == "Marseille" }?.code(for: "champions-league") == "MAR", "club code follows the competition")
    check(lib.clubs.first { $0.shortName == "Marseille" }?.code(for: "ligue1") == "OM", "club code falls back to the default")
    var state = try store.loadState()
    state.matches[0] = m
    try store.saveState(state)
    let again = try store.loadState()
    check(again.matches[0] == m, "state survives a save and load")
    let leftovers = try FileManager.default.contentsOfDirectory(atPath: tmp.path).filter { $0.hasSuffix(".tmp") }
    check(leftovers.isEmpty, "no temp files are left behind")
    try FileManager.default.removeItem(at: tmp)
} catch { failures += 1; print("FAIL store: \(error)") }

// Overlay resolver refuses escapes
if let bundled = OverlayResolver.locateBundledOverlays(explicit: nil) {
    let r = OverlayResolver(bundled: bundled, overrides: nil)
    check(r.file(for: "../Package.swift") == nil, "resolver never escapes the overlays folder")
    check(r.file(for: "shell.html") != nil, "resolver finds the shell")
    check(r.themeConfig(id: "ligue1")?.clockStyle != nil, "ligue1 theme config loads")
} else { failures += 1; print("FAIL overlays folder not found") }

// Seed file, theme override, crest matching
if let seed = SeedLibrary.load(from: Store.locateSeedFile()) {
    check(seed.clubs.count >= 165 && seed.competitions.count == 10, "seed-library.json loads with clubs, nations and competitions")
    check(seed.clubs.first { $0.shortName == "Marseille" }?.code(for: "champions-league") == "MAR", "seed keeps per-competition codes")
    let fiveLeagues = ["premier-league", "ligue1", "la-liga", "serie-a", "bundesliga"]
    let leagueCounts = [20, 18, 20, 20, 18]
    for (comp, expected) in zip(fiveLeagues, leagueCounts) {
        let n = seed.clubs.filter { $0.competitionIds.contains(comp) }.count
        check(n == expected, "\(comp) has \(expected) clubs for 2026-27 (found \(n))")
    }
} else { failures += 1; print("FAIL seed-library.json not found") }
check(Store.matchKey("AS Saint-Étienne") == "assaintetienne" && Store.matchKey("FK Bodø/Glimt") == "fkbodoglimt", "match key folds accents and punctuation")
var themed = MatchEngine.apply(.setTheme("stealth"), to: Match(slot: 1), now: at(0))
check(themed.themeId == "stealth", "theme override is stored")
themed = MatchEngine.apply(.setTheme(""), to: themed, now: at(0))
check(themed.themeId == nil, "empty theme override clears it")
check((try? CommandRequest(command: "setTheme", themeId: "la-liga").toCommand()) == .setTheme("la-liga"), "setTheme request decodes")
let crestTmp = FileManager.default.temporaryDirectory.appendingPathComponent("scorebug-crests-\(UUID().uuidString)")
do {
    let folder = crestTmp.appendingPathComponent("logos"); try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try Data([0x89, 0x50, 0x4E, 0x47]).write(to: folder.appendingPathComponent("PSG.png"))
    try Data([0x89, 0x50, 0x4E, 0x47]).write(to: folder.appendingPathComponent("Olympique de Marseille.png"))
    let store = try Store(directory: crestTmp.appendingPathComponent("data"))
    var lib = try store.loadLibrary()
    let n = store.importCrests(from: folder, into: &lib)
    check(n == 2, "crest import matches by crestSource file name (\(n))")
    check(lib.clubs.first { $0.shortName == "PSG" }?.crestFile?.hasSuffix(".png") == true, "imported crest is recorded on the club")
    try FileManager.default.removeItem(at: crestTmp)
} catch { failures += 1; print("FAIL crest import: \(error)") }

// Competition marks: importCrests also picks up competition-<id>.png for competitions without a logoFile
let competitionLogoTmp = FileManager.default.temporaryDirectory.appendingPathComponent("scorebug-competition-logos-\(UUID().uuidString)")
do {
    let folder = competitionLogoTmp.appendingPathComponent("logos"); try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try Data([0x89, 0x50, 0x4E, 0x47]).write(to: folder.appendingPathComponent("competition-ligue1.png"))
    let store = try Store(directory: competitionLogoTmp.appendingPathComponent("data"))
    var lib = try store.loadLibrary()
    check(lib.competitions.first { $0.id == "ligue1" }?.logoFile == nil, "competition starts with no logoFile before import")
    let n = store.importCrests(from: folder, into: &lib)
    check(n == 1, "importCrests reports one competition mark imported (\(n))")
    check(lib.competitions.first { $0.id == "ligue1" }?.logoFile == "competition-ligue1.png", "competition mark is recorded with the competition-<id> file name")
    check(lib.competitions.filter({ $0.id != "ligue1" }).allSatisfy { $0.logoFile == nil }, "only the matched competition gains a logoFile")
    try FileManager.default.removeItem(at: competitionLogoTmp)
} catch { failures += 1; print("FAIL competition logo import: \(error)") }

// Seed merge into an existing library keeps user edits and adds what is new
if let seed = SeedLibrary.load(from: Store.locateSeedFile()) {
    var old = Library(competitions: [seed.competitions[0]], clubs: [seed.clubs[0]])
    old.clubs[0].primaryColour = "#123456"; old.clubs[0].crestFile = "mine.png"; old.clubs[0].squad = ["X. Custom"]
    let changed = Store.mergeSeed(seed, into: &old)
    check(changed && old.clubs.count == seed.clubs.count && old.competitions.count == seed.competitions.count, "merge adds missing clubs and competitions")
    check(old.clubs[0].primaryColour == "#123456" && old.clubs[0].crestFile == "mine.png" && old.clubs[0].squad == ["X. Custom"], "merge keeps the user's colour, crest and squad")
    check(seed.clubs.first { $0.name == "Arsenal" }?.squad?.contains("B. Saka") == true, "squads.json is merged into the seed")
    var again = old; check(!Store.mergeSeed(seed, into: &again), "a second merge changes nothing")

    // squads.json carries a version, and mergeSeed uses it to tell a stale squad from a current one
    let seedVersion = SeedLibrary.lastLoadedSquadsVersion
    check(seedVersion != nil, "squads.json carries a _version")

    var stale = Library(competitions: seed.competitions, clubs: seed.clubs)
    stale.clubs[0].squad = ["Old. Player"]
    let staleChanged = Store.mergeSeed(seed, into: &stale, seedSquadsVersion: seedVersion, storedSquadsVersion: "2000-01-01")
    check(staleChanged && stale.clubs[0].squad == seed.clubs[0].squad, "a stale squad is replaced when the seed version is newer than the stored one")

    var current = Library(competitions: seed.competitions, clubs: seed.clubs)
    current.clubs[0].squad = ["Old. Player"]
    _ = Store.mergeSeed(seed, into: &current, seedSquadsVersion: seedVersion, storedSquadsVersion: seedVersion)
    check(current.clubs[0].squad == ["Old. Player"], "a squad is left alone when the stored version matches the seed version")

    var unversioned = Library(competitions: seed.competitions, clubs: seed.clubs)
    unversioned.clubs[0].squad = ["Old. Player"]
    _ = Store.mergeSeed(seed, into: &unversioned)
    check(unversioned.clubs[0].squad == ["Old. Player"], "a squad is left alone when no version is supplied, matching the pre-version merge behaviour")

    // Every club in the five leagues carries a full squad and a code for each competition it plays in
    let fiveLeagues: Set<String> = ["premier-league", "ligue1", "la-liga", "serie-a", "bundesliga"]
    let leagueClubs = seed.clubs.filter { !$0.competitionIds.filter(fiveLeagues.contains).isEmpty }
    check(leagueClubs.count == 96, "96 clubs across the five leagues (found \(leagueClubs.count))")
    let missingSquad = leagueClubs.filter { ($0.squad?.isEmpty ?? true) }.map { $0.name }
    check(missingSquad.isEmpty, "every five-league club has a non-empty squad (missing: \(missingSquad))")
    let missingCode = leagueClubs.filter { club in club.competitionIds.contains { club.code(for: $0).isEmpty } }.map { $0.name }
    check(missingCode.isEmpty, "every five-league club has a code for each of its competitions (missing: \(missingCode))")
}

print(failures == 0 ? "All checks passed." : "\(failures) check(s) failed.")
exit(failures == 0 ? 0 : 1)
