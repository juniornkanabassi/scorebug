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
check(!m.clock.running, "play while running pauses (play/pause key)")
m = MatchEngine.apply(.play, to: m, now: at(1000))

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
    check(seed.clubs.count > 100 && seed.competitions.count == 10, "seed-library.json loads with clubs, nations and competitions")
    check(seed.clubs.first { $0.shortName == "Marseille" }?.code(for: "champions-league") == "MAR", "seed keeps per-competition codes")
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

print(failures == 0 ? "All checks passed." : "\(failures) check(s) failed.")
exit(failures == 0 ? 0 : 1)
