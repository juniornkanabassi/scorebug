// One match slot: live preview on top, then a grouped form with the fixture, clock, score, shootout and design.
import SwiftUI
import ScorebugCore

struct SlotView: View {
    @EnvironmentObject var model: AppModel
    let slot: Int
    @State private var tick = Date()
    private let timer = Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()

    private var match: Match { model.match(slot) }
    private var competition: Competition? { model.library.competitions.first { $0.id == match.competitionId } }
    private var themeConfig: ThemeConfig? { model.resolver.themeConfig(id: match.themeId ?? competition?.themeId ?? match.competitionId) }

    var body: some View {
        VStack(spacing: 0) {
            PreviewStage(slot: slot)
            Divider()
            Form {
                fixtureSection
                clockSection
                scoreSection
                shootoutSection
                designSection
            }
            .formStyle(.grouped)
        }
        .navigationTitle(slot == 1 ? "Primary match" : "Secondary match")
        .navigationSubtitle("\(match.home.name) v \(match.away.name)")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button { model.apply(.play, slot: slot) } label: { Label(match.clock.running ? "Pause" : "Play", systemImage: match.clock.running ? "pause.fill" : "play.fill") }
                    .disabled(match.currentPeriod == nil).help("Play or pause the clock (Space)").keyboardShortcut(.space, modifiers: [])
                Toggle(isOn: Binding(get: { match.visible }, set: { model.apply(.setVisible($0), slot: slot) })) {
                    Label(match.visible ? "Bug shown" : "Bug hidden", systemImage: match.visible ? "eye" : "eye.slash")
                }.toggleStyle(.button).help("Show or hide the bug in OBS")
                Button(role: .destructive) { model.apply(.reset, slot: slot) } label: { Label("Reset", systemImage: "arrow.counterclockwise") }
                    .help("Zero the score, clock and shootout; keep the teams")
            }
        }
        .onReceive(timer) { tick = $0 }
    }

    // MARK: Fixture

    private var fixtureSection: some View {
        Section("Fixture") {
            Picker("Competition", selection: Binding(get: { match.competitionId }, set: { model.setCompetition($0, slot: slot) })) {
                ForEach(model.library.competitions) { c in Text(c.name).tag(c.id) }
            }
            teamPicker(.home, label: "Home (left)")
            teamPicker(.away, label: "Away (right)")
            HStack {
                Button("Swap Sides") { model.apply(.swapTeams, slot: slot) }
                Spacer()
                Text("Codes follow the competition, for example OM in Ligue 1 and MAR in the Champions League.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func teamPicker(_ side: Side, label: String) -> some View {
        let clubs = model.library.clubs(in: match.competitionId)
        return LabeledContent(label) {
            HStack(spacing: 10) {
                crestThumb(match.team(side))
                Picker("", selection: Binding<UUID?>(get: { match.team(side).clubId }, set: { id in model.setClub(clubs.first { $0.id == id }, side: side, slot: slot) })) {
                    Text("Not set").tag(UUID?.none)
                    ForEach(clubs) { c in Text("\(c.name)  (\(c.code(for: match.competitionId)))").tag(UUID?.some(c.id)) }
                }.labelsHidden().frame(maxWidth: 320)
            }
        }
    }

    private func crestThumb(_ team: TeamEntry) -> some View {
        Group {
            if let f = team.crestFile, let img = NSImage(contentsOf: model.store.crestsDirectory.appendingPathComponent(f)) {
                Image(nsImage: img).resizable().scaledToFit()
            } else {
                Circle().fill(Color(hex: team.primaryColour)).overlay(Text(String(team.code.prefix(2))).font(.system(size: 9, weight: .bold)).foregroundStyle(Color(hex: team.textColour)))
            }
        }.frame(width: 22, height: 22)
    }

    // MARK: Clock

    private var clockSection: some View {
        let d = ClockEngine.display(match: match, style: themeConfig?.clockStyle ?? .runOn, now: tick)
        return Section("Clock") {
            LabeledContent("Match time") {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(d.state ?? d.main).font(.system(size: 30, weight: .semibold, design: .rounded)).monospacedDigit()
                    if let a = d.added { Text(a).font(.title3.weight(.semibold)).foregroundStyle(.orange) }
                    if let c = d.addedCounter { Text(c).font(.body).monospacedDigit().foregroundStyle(.secondary) }
                    Text(phaseTitle).font(.callout).foregroundStyle(.secondary)
                }
            }
            LabeledContent("Start") {
                HStack { ForEach(Period.allCases, id: \.self) { p in periodButton(p) } }
            }
            LabeledContent("Period") {
                HStack {
                    Button(match.clock.running ? "Pause" : "Play") { model.apply(.play, slot: slot) }.disabled(match.currentPeriod == nil)
                    Button("End Period") { model.apply(.endPeriod, slot: slot) }.disabled(match.currentPeriod == nil)
                }
            }
            LabeledContent("Added time") {
                HStack {
                    Stepper(value: Binding(get: { match.addedMinutes ?? 0 }, set: { model.apply(.setAddedMinutes($0), slot: slot) }), in: 0...15) {
                        Text(match.addedMinutes.map { "+\($0) min" } ?? "None").monospacedDigit().frame(minWidth: 64, alignment: .leading)
                    }
                    Button("Clear") { model.apply(.setAddedMinutes(nil), slot: slot) }.disabled(match.addedMinutes == nil)
                }
            }
        }
    }

    @ViewBuilder private func periodButton(_ p: Period) -> some View {
        if match.phase == p.phase {
            Button(p.title) { model.apply(.startPeriod(p), slot: slot) }.buttonStyle(.borderedProminent)
        } else {
            Button(p.title) { model.apply(.startPeriod(p), slot: slot) }.buttonStyle(.bordered)
        }
    }

    private var phaseTitle: String {
        switch match.phase {
        case .preMatch: return "Pre-match"; case .firstHalf: return "First half"; case .halfTime: return "Half time"
        case .secondHalf: return "Second half"; case .fullTime: return "Full time"; case .extraFirst: return "Extra time, first half"
        case .extraBreak: return "Extra time break"; case .extraSecond: return "Extra time, second half"; case .extraFullTime: return "After extra time"
        case .shootout: return "Penalty shootout"; case .finished: return "Finished"
        }
    }

    // MARK: Score

    private var scoreSection: some View {
        Section("Score") {
            ForEach(Side.allCases, id: \.self) { side in
                LabeledContent(match.team(side).code) {
                    HStack(spacing: 12) {
                        Text("\(match.score(side))").font(.system(size: 26, weight: .bold, design: .rounded)).monospacedDigit().frame(minWidth: 28)
                        Button { model.apply(.goal(side, -1), slot: slot) } label: { Image(systemName: "minus") }.disabled(match.score(side) == 0)
                        Button { model.apply(.goal(side, 1), slot: slot) } label: { Image(systemName: "plus") }.buttonStyle(.borderedProminent).disabled(match.phase == .shootout)
                            .help("Goal for \(match.team(side).name)")
                    }
                }
            }
            ForEach(match.goals) { goal in
                LabeledContent("\(match.team(goal.side).code) \(goal.minuteLabel)") {
                    TextField("Scorer", text: Binding(get: { goal.scorer ?? "" }, set: { model.apply(.setScorer(goal.id, $0), slot: slot) }))
                        .textFieldStyle(.roundedBorder).frame(maxWidth: 260)
                }
            }
            if !match.goals.isEmpty {
                Text("Scorers appear in a strap under the bug for a few seconds every minute or so.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Shootout

    private var shootoutSection: some View {
        Section("Penalty shootout") {
            if let s = match.shootout {
                ForEach(Side.allCases, id: \.self) { side in
                    LabeledContent("\(match.team(side).code)  \(s.tally(side))") {
                        HStack(spacing: 10) {
                            HStack(spacing: 5) {
                                ForEach(s.kicks.filter { $0.side == side }) { k in
                                    Circle().fill(k.result == .scored ? Color.green : k.result == .missed ? Color.red : Color.gray).frame(width: 11, height: 11)
                                }
                            }.frame(minWidth: 90, alignment: .leading)
                            if s.nextSide == side && match.phase == .shootout { Text("to kick").font(.caption).foregroundStyle(.secondary) }
                            Button("Scored") { model.apply(.recordKick(side, .scored), slot: slot) }.disabled(match.phase != .shootout)
                            Button("Missed") { model.apply(.recordKick(side, .missed), slot: slot) }.disabled(match.phase != .shootout)
                        }
                    }
                }
                Button("Undo Last Kick") { model.apply(.undoKick, slot: slot) }.disabled(s.kicks.isEmpty)
            } else {
                LabeledContent("Shootout") {
                    Button("Start Shootout") { model.apply(.startShootout(.home), slot: slot) }
                }
                Text("The bug shows PENS with a kick row; the match score stays and the shootout tally sits beside it.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Design

    private var designSection: some View {
        Section("Design") {
            Picker("Score bug", selection: Binding<String>(get: { match.themeId ?? "" }, set: { model.apply(.setTheme($0.isEmpty ? nil : $0), slot: slot) })) {
                Text("Follow competition").tag("")
                Divider()
                ForEach(model.resolver.availableThemeIds(), id: \.self) { id in Text(model.resolver.themeConfig(id: id)?.name ?? id).tag(id) }
            }
            if let t = themeConfig {
                LabeledContent("Clock", value: t.clockStyle == .runOn ? "Runs on past 45:00 with +N beside it" : "Stops at 45:00, added time counted separately")
                LabeledContent("Placement", value: "Horizontal \(t.geometry["h"]?.left ?? 0), \(t.geometry["h"]?.top ?? 0) px. Vertical centred, top \(t.geometry["v"]?.top ?? 0) px, max width \(t.geometry["v"]?.maxWidth ?? 0) px.")
            }
        }
    }
}

/// Live preview of both pages from the local server, so the window shows exactly what OBS shows.
struct PreviewStage: View {
    @EnvironmentObject var model: AppModel
    let slot: Int
    var body: some View {
        GeometryReader { geo in
            let stageH = geo.size.height - 16
            let hW = stageH * 16 / 9, vW = stageH * 9 / 16
            HStack(spacing: 12) {
                Spacer(minLength: 0)
                OverlayWebView(url: URL(string: "\(model.baseURL)/overlay/h/\(slot)")!, scale: hW / 1920, size: CGSize(width: 1920, height: 1080))
                    .frame(width: hW, height: stageH).background(.black).clipShape(RoundedRectangle(cornerRadius: 6))
                OverlayWebView(url: URL(string: "\(model.baseURL)/overlay/v/\(slot)")!, scale: vW / 1080, size: CGSize(width: 1080, height: 1920))
                    .frame(width: vW, height: stageH).background(.black).clipShape(RoundedRectangle(cornerRadius: 6))
                Spacer(minLength: 0)
            }.padding(8)
        }
        .frame(height: 260)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
