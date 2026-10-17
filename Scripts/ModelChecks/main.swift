import Foundation
import SwiftUI
import ScorebugCore

final class CannedProtocol: URLProtocol {
    static let lock = NSLock()
    static var payload = Data()
    static var hold = false
    static var pending: [CannedProtocol] = []
    override class func canInit(with request: URLRequest) -> Bool { request.url?.scheme == "https" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        if request.url?.path.hasSuffix("summary") == true {
            let held = Self.lock.withLock { if Self.hold { Self.pending.append(self); return true }; return false }
            if held { return }
        }
        finish()
    }
    func finish() {
        let data = request.url?.path.hasSuffix("summary") == true ? Self.payload : Data(#"{"events":[]}"#.utf8)
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
    static func release() { let held = lock.withLock { hold = false; let p = pending; pending = []; return p }; held.forEach { $0.finish() } }
}

@main struct ModelChecks {
    @MainActor static func main() async throws {
        var checks = 0
        func check(_ condition: @autoclosure () -> Bool, _ label: String) {
            guard condition() else { fatalError("FAIL \(label)") }
            checks += 1; print("PASS \(label)")
        }
        _ = URLProtocol.registerClass(CannedProtocol.self)
        defer { URLProtocol.unregisterClass(CannedProtocol.self) }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("data-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let model = AppModel(options: LaunchOptions(dataDirectory: root, port: Int(ProcessInfo.processInfo.environment["SCOREBUG_CHECK_PORT"]!)!))
        // Let the initial pre-match poll enter its sleep before controlling the slot.
        try await Task.sleep(for: .milliseconds(100))
        model.settings.liveSourceEnabled["FotMob"] = false
        var linked = Match(slot: 1, competitionId: "champions-league", home: TeamEntry(name: "Original Home", code: "HOM", squad: ["Home Squad"]), away: TeamEntry(name: "Original Away", code: "AWY", squad: ["Away Squad"]))
        linked = MatchEngine.apply(.startPeriod(.firstHalf), to: linked, now: Date())
        linked.espnEventId = "12345"; linked.espnLeague = "uefa.champions"; linked.liveDataDelayMinutes = 0
        linked.kickoff = Date().addingTimeInterval(-3600)
        func seed(_ match: Match = linked) { model.state.matches[0] = match }
        CannedProtocol.payload = Data(#"{"header":{"competitions":[{"competitors":[{"homeAway":"home","score":"2","team":{"id":"10","displayName":"Original Home"}},{"homeAway":"away","score":"0","team":{"id":"20","displayName":"Original Away"}}],"details":[{"scoringPlay":true,"clock":{"displayValue":"20'"},"team":{"id":"10"},"athletesInvolved":[{"displayName":"First Scorer"}]},{"scoringPlay":true,"clock":{"displayValue":"75'"},"team":{"id":"10"},"athletesInvolved":[{"displayName":"Second Scorer"}]}]}]},"rosters":[{"team":{"id":"10"},"roster":[{"athlete":{"displayName":"Home Live"}}]},{"team":{"id":"20"},"roster":[{"athlete":{"displayName":"Away Live"}}]}]}"#.utf8)
        seed(); await model.refreshLiveData(slot: 1)
        check(model.match(1).homeScore == 2 && model.match(1).goals.count == 2, "FLAW 4 feed adds two distinct goals")
        let laterID = model.match(1).goals[1].id
        model.apply(.removeGoal(model.match(1).goals[0].id), slot: 1)
        await model.refreshLiveData(slot: 1)
        check(model.match(1).homeScore == 1 && model.match(1).goals.map(\.id) == [laterID], "FLAW 4 removing the earlier goal never duplicates the later goal")
        let fullPayload = CannedProtocol.payload
        // SB-R3: ESPN keyEvents give each goal an id that survives a minute correction (event 401861081 shape).
        func withKeyEvents(_ events: [(id: String, clock: String)], replacing: (String, String)? = nil) throws -> Data {
            var root = try JSONSerialization.jsonObject(with: fullPayload) as! [String: Any]
            root["keyEvents"] = events.map { ["id": $0.id, "scoringPlay": true, "shootout": false, "clock": ["displayValue": $0.clock], "team": ["id": "10"]] as [String: Any] }
            let text = String(decoding: try JSONSerialization.data(withJSONObject: root), as: UTF8.self)
            return Data((replacing.map { text.replacingOccurrences(of: $0.0, with: $0.1) } ?? text).utf8)
        }
        CannedProtocol.payload = try withKeyEvents([("501", "20'"), ("502", "75'")])
        seed(); await model.refreshLiveData(slot: 1)
        check(model.match(1).goals.compactMap(\.autoAddedKey) == ["12345:id:501", "12345:id:502"], "SB-R3 automatic goals carry the provider id")
        model.apply(.removeGoal(model.match(1).goals[0].id), slot: 1)
        CannedProtocol.payload = try withKeyEvents([("501", "21'"), ("502", "75'")], replacing: (#""displayValue":"20'""#, #""displayValue":"21'""#))
        await model.refreshLiveData(slot: 1)
        let restarted = try JSONCoding.decoder().decode(Match.self, from: JSONCoding.encoder().encode(model.match(1)))
        seed(restarted); await model.refreshLiveData(slot: 1)
        check(model.match(1).homeScore == 1 && model.match(1).removedLiveGoalKeys == ["12345:id:501"], "SB-R3 a removed goal stays removed after a minute correction and a restart")
        CannedProtocol.payload = try withKeyEvents([("503", "21'"), ("502", "75'")], replacing: (#""displayValue":"20'""#, #""displayValue":"21'""#))
        await model.refreshLiveData(slot: 1)
        check(model.match(1).homeScore == 2 && model.match(1).goals.contains { $0.autoAddedKey == "12345:id:503" }, "SB-R3 a different goal replacing the removed one in the same poll is added")
        var legacy = linked
        legacy.homeScore = 1; legacy.removedLiveGoalKeys = ["12345:home:20:0"]
        legacy.goals = [Goal(side: .home, elapsedSeconds: 4440, minuteLabel: "75'", autoFilled: true, autoAdded: true, autoAddedKey: "12345:home:75:0")]
        CannedProtocol.payload = try withKeyEvents([("501", "20'"), ("502", "75'")])
        seed(legacy); await model.refreshLiveData(slot: 1)
        check(model.match(1).homeScore == 1 && model.match(1).removedLiveGoalKeys == ["12345:id:501"] && model.match(1).goals.map(\.autoAddedKey) == ["12345:id:502"], "SB-R3 saved minute keys move onto the ids of the exact matching goals")
        CannedProtocol.payload = fullPayload
        var reduced = try JSONSerialization.jsonObject(with: fullPayload) as! [String: Any]
        var header = reduced["header"] as! [String: Any]
        var competitions = header["competitions"] as! [[String: Any]]
        let details = competitions[0]["details"] as! [[String: Any]]
        competitions[0]["details"] = [details[1]]; header["competitions"] = competitions; reduced["header"] = header
        CannedProtocol.payload = try JSONSerialization.data(withJSONObject: reduced)
        var conservative = linked
        conservative.homeScore = 2
        conservative.goals = [Goal(side: .home, elapsedSeconds: 1140, minuteLabel: "20'", autoFilled: true), Goal(side: .home, elapsedSeconds: 4440, minuteLabel: "75'", autoFilled: true)]
        seed(conservative); await model.refreshLiveData(slot: 1)
        check(model.match(1).goals == conservative.goals, "a shortened feed leaves ambiguous recorded goals untouched")
        CannedProtocol.payload = fullPayload; await model.refreshLiveData(slot: 1)
        check(model.match(1).homeScore == 2 && model.match(1).goals.map(\.minuteLabel) == ["20'", "75'"], "restoring the feed keeps goal order and score")
        for useAPI in [false, true] {
            seed(); await model.refreshLiveData(slot: 1)
            if useAPI { try model.applyRequest(CommandRequest(command: "goal", side: "home", delta: -1), slot: 1) }
            else { model.apply(.goal(.home, -1), slot: 1) }
            check(model.match(1).removedLiveGoalKeys == ["12345:home:75:0"], "FLAW 5 \(useAPI ? "API" : "GUI") minus saves suppression")
            await model.refreshLiveData(slot: 1)
            check(model.match(1).homeScore == 1 && model.match(1).goals[0].minuteLabel == "20'", "FLAW 5 \(useAPI ? "API" : "GUI") removed goal stays removed")
        }
        var manual = MatchEngine.apply(.goal(.home, 1), to: linked, now: Date())
        manual = MatchEngine.apply(.setScorer(manual.goals[0].id, "Manual Player", ownGoal: true, penalty: false), to: manual, now: Date())
        let originalGoal = manual.goals[0]
        seed(MatchEngine.apply(.startShootout(.home), to: manual, now: Date()))
        await model.refreshLiveData(slot: 1)
        check(model.match(1).goals == [originalGoal] && model.match(1).homeScore == 1, "FLAW 3 a shootout poll preserves the manual goal")
        seed(manual)
        CannedProtocol.lock.withLock { CannedProtocol.hold = true }
        let poll = Task { await model.refreshLiveData(slot: 1) }
        for _ in 0..<200 {
            if CannedProtocol.lock.withLock({ !CannedProtocol.pending.isEmpty }) { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        check(CannedProtocol.lock.withLock { !CannedProtocol.pending.isEmpty }, "FLAW 3 poll is held at the real network await")
        model.apply(.startShootout(.home), slot: 1)
        CannedProtocol.release(); await poll.value
        check(model.match(1).goals == [originalGoal] && model.match(1).phase == .shootout, "FLAW 3 shootout started during the request rejects stale goals")
        seed(MatchEngine.apply(.swapTeams, to: linked, now: Date()))
        await model.refreshLiveData(slot: 1)
        check(model.match(1).homeScore == 0 && model.match(1).awayScore == 2, "FLAW 6 swapped goals follow the original team")
        check(model.liveLineup(slot: 1, side: .home) == ["Away Live"] && model.liveLineup(slot: 1, side: .away) == ["Home Live"], "FLAW 6 swapped lineups follow the original team")
        try model.applyRequest(CommandRequest(command: "linkESPN", competitionId: "uefa.champions", eventId: "12345"), slot: 1)
        check(model.match(1).liveSidesSwapped, "FLAW 6 linking the same event preserves its orientation")
        model.apply(.goal(.away, -1), slot: 1); await model.refreshLiveData(slot: 1)
        check(model.match(1).awayScore == 1 && model.match(1).removedLiveGoalKeys == ["12345:home:75:0"], "FLAW 6 swapped removal uses provider identity")
        model.apply(.setLiveLink(eventId: nil, league: nil), slot: 1)
        try model.applyRequest(CommandRequest(command: "linkESPN", competitionId: "uefa.champions", eventId: "12345"), slot: 1)
        await model.refreshLiveData(slot: 1)
        check(model.match(1).liveSidesSwapped && model.match(1).homeScore == 0 && model.match(1).awayScore == 1 && model.liveLineup(slot: 1, side: .home) == ["Away Live"],
              "SB-R4 unlink and re-link of a swapped match keeps goals and lineups on the original team")
        let saved = try JSONCoding.decoder().decode(Match.self, from: JSONCoding.encoder().encode(model.match(1)))
        seed(saved); await model.refreshLiveData(slot: 1)
        check(model.match(1).awayScore == 1 && model.match(1).liveSidesSwapped, "FLAW 6 restart preserves mapped suppression")
        seed(); await model.refreshLiveData(slot: 1)
        let prompt = GoalPromptProbe(model: model, goal: model.match(1).goals[0], slot: 1)
        check(Set(prompt.scoringSquad) == Set(["Home Squad", "Home Live"]), "FLAW 13 scoring picker has only its own lineup")
        check(Set(prompt.otherSquad) == Set(["Away Squad", "Away Live"]), "FLAW 13 own-goal picker has the opponent lineup")
        var delayed = linked; delayed.liveDataDelayMinutes = 5
        seed(delayed); await model.refreshLiveData(slot: 1)
        check(model.match(1).goals.isEmpty && model.match(1).homeScore == 0, "delayed polling does not reveal fresh goals")
        seed(manual)
        let fixture = Fixture(kickoff: Date(), competitionCode: "uefa.champions", competitionName: "UCL", home: FixtureTeam(name: "Next Home", shortName: "Next Home", code: "NXH"), away: FixtureTeam(name: "Next Away", shortName: "Next Away", code: "NXA"), espnEventId: "67890")
        let skipped = await model.loadFixture(fixture, slot: 1)
        check(skipped == nil, "FLAW 7 unforced replacement still refuses a live slot")
        let loaded = await model.loadFixture(fixture, slot: 1, force: true)
        check(loaded == false && model.match(1).phase == .preMatch && model.match(1).homeScore == 0 && model.match(1).goals.isEmpty && !model.match(1).clock.running, "FLAW 7 forced replacement clears the old play")
        var same = model.match(1)
        same = MatchEngine.apply(.startPeriod(.secondHalf), to: same, now: Date())
        same.aggregate = Aggregate(firstLegHome: 3, firstLegAway: 2); same.removedLiveGoalKeys = ["67890:home:20:0"]; same.liveSidesSwapped = true
        same.visible = false; same.themeId = "stealth"; same.autoUpdateLiveData = false; same.liveDataDelayMinutes = 7
        seed(same)
        let noLink = Fixture(kickoff: Date().addingTimeInterval(3600), competitionCode: "uefa.champions", competitionName: "UCL", home: fixture.home, away: fixture.away)
        _ = await model.loadFixture(noLink, slot: 1, force: true)
        check(model.match(1).aggregate == nil && model.match(1).removedLiveGoalKeys.isEmpty && model.match(1).espnEventId == nil && !model.match(1).liveSidesSwapped, "FLAW 7 same-team replacement clears tie, suppression and old link")
        check(model.match(1).kickoff == noLink.kickoff && model.match(1).revision > same.revision && model.liveLineup(slot: 1, side: .home).isEmpty, "FLAW 7 new event keeps fresh kickoff and no old lineup")
        check(!model.match(1).visible && model.match(1).themeId == "stealth" && !model.match(1).autoUpdateLiveData && model.match(1).liveDataDelayMinutes == 7, "FLAW 7 slot display and live-data settings survive replacement")
        let image = root.appendingPathComponent("mark.svg")
        try Data("first image".utf8).write(to: image)
        model.importCompetitionLogo(from: image, for: "champions-league")
        let logoRevision = model.match(1).revision
        let logoVersion = model.snapshot().competitions.first { $0.id == "champions-league" }?.logoVersion ?? 0
        try Data("replacement image".utf8).write(to: image)
        model.importCompetitionLogo(from: image, for: "champions-league")
        let replacedLogo = model.snapshot().competitions.first { $0.id == "champions-league" }
        check(replacedLogo?.logoVersion == logoVersion + 1 && replacedLogo?.logoFile == "competition-champions-league.svg", "FLAW 10 same-name logo replacement bumps the logo's version in the snapshot")
        check(model.match(1).revision == logoRevision, "SB-R1 logo replacement leaves the match revision alone")
        let crestClub = Club(name: "Crest Club", shortName: "Crest", defaultCode: "CRC", primaryColour: "#000000")
        model.upsertClub(crestClub)
        model.apply(.setTeam(.home, crestClub.entry(for: model.match(1).competitionId)), slot: 1)
        let crestImage = root.appendingPathComponent("crest.png")
        try Data("first crest".utf8).write(to: crestImage)
        model.importCrest(from: crestImage, for: crestClub.id)
        let firstCrest = model.match(1).home
        try Data("replacement crest".utf8).write(to: crestImage)
        model.importCrest(from: crestImage, for: crestClub.id)
        let crestFiles = try FileManager.default.contentsOfDirectory(atPath: model.store.crestsDirectory.path).filter { $0.hasPrefix(crestClub.id.uuidString) }
        check(firstCrest.crestFile == model.match(1).home.crestFile && model.match(1).home.crestVersion == (firstCrest.crestVersion ?? 0) + 1
              && model.library.clubs.first { $0.id == crestClub.id }?.crestVersion == model.match(1).home.crestVersion, "SB-R2 same-name crest replacement bumps the shown and saved crest version")
        check(crestFiles == [firstCrest.crestFile], "SB-R2 a replacement leaves one crest file, no cache-busting copies")
        let themeFolder = model.store.overlayOverridesDirectory.appendingPathComponent("themes/ligue1")
        try FileManager.default.createDirectory(at: themeFolder, withIntermediateDirectories: true)
        try Data(#"{"id":"ligue1","name":"Override sentinel","clockStyle":"freezeAndCount","geometry":{}}"#.utf8).write(to: themeFolder.appendingPathComponent("theme.json"))
        check(model.themeConfig(id: "ligue1")?.name == "Override sentinel", "FLAW 11 window resolves enabled override")
        model.startServer()
        for _ in 0..<200 {
            if model.serverRunning { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        check(model.serverRunning, "FLAW 11 disposable HTTP server is listening")
        func servedTheme() async throws -> String {
            let (data, response) = try await URLSession.shared.data(from: URL(string: model.baseURL + "/themes/ligue1/theme.json")!)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
            return String(decoding: data, as: UTF8.self)
        }
        let enabled = try await servedTheme()
        check(enabled.contains("Override sentinel"), "FLAW 11 real route serves enabled override")
        model.settings.themeOverridesEnabled = false; model.saveSettings()
        check(model.themeConfig(id: "ligue1")?.name != "Override sentinel" && model.snapshot().overlay.themeOverrides == false, "FLAW 11 disabling overrides refreshes window and snapshot")
        let disabled = try await servedTheme()
        check(!disabled.contains("Override sentinel"), "FLAW 11 real route serves bundled asset without restarting")
        model.settings.themeOverridesEnabled = true; model.saveSettings()
        check(model.themeConfig(id: "ligue1")?.name == "Override sentinel" && model.snapshot().overlay.themeOverrides == true, "FLAW 11 re-enabling overrides refreshes window and snapshot")
        let restored = try await servedTheme()
        check(restored.contains("Override sentinel"), "FLAW 11 real route restores override without restarting")
        // Rule 3: with the data folder read-only, a command, a setting and a competition edit change nothing an overlay sees.
        func servedState() async throws -> Data { try await URLSession.shared.data(from: URL(string: model.baseURL + "/api/state")!).0 }
        func stripTime(_ data: Data) throws -> NSDictionary { let d = try JSONSerialization.jsonObject(with: data, options: .mutableContainers) as! NSMutableDictionary; d.removeObject(forKey: "serverTime"); return d }
        let savedMatch = model.match(1), savedTop = model.settings.portraitTop, savedCompetition = model.library.competitions[0]
        let beforeFailure = try stripTime(try await servedState())
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: root.path)
        check(!model.apply(.goal(.home, 1), slot: 1) && model.match(1) == savedMatch && model.stateSaveFailed, "rule 3 failed save rolls the command back")
        model.settings.portraitTop = savedTop + 10
        check(model.snapshot().overlay.portraitTop == savedTop, "rule 3 a setting edited but not yet saved stays off the snapshot")
        model.saveSettings()
        check(model.snapshot().overlay.portraitTop == savedTop, "rule 3 a failed settings save stays off the snapshot")
        var edited = savedCompetition; edited.name += " unsaved"; model.updateCompetition(edited)
        check(model.snapshot().competitions[0] == savedCompetition, "rule 3 a failed competition save stays off the snapshot")
        let afterFailure = try stripTime(try await servedState())
        check(afterFailure == beforeFailure, "rule 3 served state is unchanged after failed saves")
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: root.path)
        check(model.apply(.goal(.home, 1), slot: 1) && model.match(1).homeScore == savedMatch.homeScore + 1, "rule 3 the next save after recovery applies")
        model.saveSettings(); model.updateCompetition(edited)
        check(model.snapshot().overlay.portraitTop == savedTop + 10 && model.snapshot().competitions[0] == edited, "rule 3 settings and competitions show once saved")
        print("\(checks) model checks passed")
    }
}
