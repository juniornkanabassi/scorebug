// One match slot: teams, clock, score, goals, shootout, visibility, and the live preview of both pages.
import SwiftUI
import ScorebugCore

struct SlotView: View {
    @EnvironmentObject var model: AppModel
    let slot: Int
    @State private var tick = Date()
    private let timer = Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()

    private var match: Match { model.match(slot) }
    private var theme: ThemeConfig? {
        let comp = model.library.competitions.first { $0.id == match.competitionId }
        return model.resolver.themeConfig(id: comp?.themeId ?? match.competitionId)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                teamsSection
                clockSection
                scoreSection
                if match.phase == .shootout || match.shootout != nil { shootoutSection }
                PreviewStrip(slot: slot)
            }
            .padding(20)
        }
        .navigationTitle(slot == 1 ? "Primary match" : "Secondary match")
        .toolbar {
            ToolbarItemGroup {
                Toggle(isOn: Binding(get: { match.visible }, set: { model.apply(.setVisible($0), slot: slot) })) {
                    Label(match.visible ? "Bug shown" : "Bug hidden", systemImage: match.visible ? "eye" : "eye.slash")
                }.toggleStyle(.button)
                Button(role: .destructive) { model.apply(.reset, slot: slot) } label: { Label("Reset match", systemImage: "arrow.counterclockwise") }
            }
        }
        .onReceive(timer) { tick = $0 }
    }

    // MARK: Teams

    private var teamsSection: some View {
        GroupBox("Fixture") {
            HStack(alignment: .top, spacing: 16) {
                Picker("Competition", selection: Binding(get: { match.competitionId }, set: { model.setCompetition($0, slot: slot) })) {
                    ForEach(model.library.competitions) { c in Text(c.name).tag(c.id) }
                }.frame(maxWidth: 260)
                teamPicker(.home)
                Button { model.apply(.swapTeams, slot: slot) } label: { Image(systemName: "arrow.left.arrow.right") }.help("Swap home and away")
                teamPicker(.away)
            }
            .padding(6)
        }
    }

    private func teamPicker(_ side: Side) -> some View {
        let clubs = model.library.clubs(in: match.competitionId)
        return Picker(side == .home ? "Home" : "Away", selection: Binding<UUID?>(
            get: { match.team(side).clubId },
            set: { id in model.setClub(clubs.first { $0.id == id }, side: side, slot: slot) })) {
            Text("Not set").tag(UUID?.none)
            ForEach(clubs) { c in Text("\(c.name) (\(c.code(for: match.competitionId)))").tag(UUID?.some(c.id)) }
        }.frame(maxWidth: 300)
    }

    // MARK: Clock

    private var clockSection: some View {
        GroupBox("Clock") {
            let d = ClockEngine.display(match: match, style: theme?.clockStyle ?? .freezeAndCount, now: tick)
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 14) {
                    Text(d.state ?? d.main).font(.system(size: 44, weight: .bold, design: .rounded)).monospacedDigit()
                    if let a = d.added { Text(a).font(.system(size: 28, weight: .semibold)).foregroundStyle(.secondary) }
                    if let c = d.addedCounter { Text(c).font(.system(size: 22, weight: .medium)).monospacedDigit().foregroundStyle(.secondary) }
                    Spacer()
                    Text(phaseTitle).font(.headline).foregroundStyle(.secondary)
                }
                HStack(spacing: 8) {
                    ForEach(Period.allCases, id: \.self) { p in
                        Button("Start \(p.title)") { model.apply(.startPeriod(p), slot: slot) }
                    }
                    Button(match.clock.running ? "Pause" : "Play") { model.apply(.play, slot: slot) }
                        .keyboardShortcut(.space, modifiers: [])
                        .disabled(match.currentPeriod == nil)
                    Button("End period") { model.apply(.endPeriod, slot: slot) }.disabled(match.currentPeriod == nil)
                }
                HStack(spacing: 8) {
                    Text("Added time").foregroundStyle(.secondary)
                    Button("−") { model.apply(.adjustAddedMinutes(-1), slot: slot) }
                    Text(match.addedMinutes.map { "+\($0)" } ?? "none").frame(width: 50)
                    Button("+") { model.apply(.adjustAddedMinutes(1), slot: slot) }
                    Button("Clear") { model.apply(.setAddedMinutes(nil), slot: slot) }.disabled(match.addedMinutes == nil)
                    Spacer()
                    Button("Start shootout") { model.apply(.startShootout(.home), slot: slot) }.disabled(match.phase == .shootout)
                }
            }.padding(6)
        }
    }

    private var phaseTitle: String {
        switch match.phase {
        case .preMatch: return "Pre-match"
        case .firstHalf: return "First half"
        case .halfTime: return "Half time"
        case .secondHalf: return "Second half"
        case .fullTime: return "Full time"
        case .extraFirst: return "Extra time, first half"
        case .extraBreak: return "Extra time break"
        case .extraSecond: return "Extra time, second half"
        case .extraFullTime: return "After extra time"
        case .shootout: return "Penalty shootout"
        case .finished: return "Finished"
        }
    }

    // MARK: Score and goals

    private var scoreSection: some View {
        GroupBox("Score") {
            HStack(alignment: .top, spacing: 24) {
                scoreColumn(.home)
                Divider()
                scoreColumn(.away)
            }.padding(6)
        }
    }

    private func scoreColumn(_ side: Side) -> some View {
        let team = match.team(side)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Text(team.code).font(.title2.bold())
                Text("\(match.score(side))").font(.system(size: 40, weight: .bold, design: .rounded))
                Button { model.apply(.goal(side, 1), slot: slot) } label: { Image(systemName: "plus.circle.fill").font(.title) }
                    .buttonStyle(.plain).disabled(match.phase == .shootout)
                Button { model.apply(.goal(side, -1), slot: slot) } label: { Image(systemName: "minus.circle").font(.title) }
                    .buttonStyle(.plain).disabled(match.score(side) == 0)
            }
            ForEach(match.goals.filter { $0.side == side }) { goal in
                HStack {
                    Text(goal.minuteLabel).monospacedDigit().frame(width: 52, alignment: .trailing).foregroundStyle(.secondary)
                    TextField("Scorer", text: Binding(get: { goal.scorer ?? "" }, set: { model.apply(.setScorer(goal.id, $0), slot: slot) }))
                        .textFieldStyle(.roundedBorder)
                }
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Shootout

    private var shootoutSection: some View {
        GroupBox("Penalty shootout") {
            let s = match.shootout ?? Shootout(firstKicker: .home)
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 24) {
                    ForEach(Side.allCases, id: \.self) { side in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(match.team(side).code).font(.headline)
                                Text("\(s.tally(side))").font(.title2.bold())
                                if s.nextSide == side && match.phase == .shootout { Text("to kick").font(.caption).foregroundStyle(.secondary) }
                            }
                            HStack(spacing: 6) {
                                ForEach(s.kicks.filter { $0.side == side }) { k in
                                    Circle().fill(k.result == .scored ? Color.green : k.result == .missed ? Color.red : Color.gray).frame(width: 14, height: 14)
                                }
                            }
                            HStack {
                                Button("Scored") { model.apply(.recordKick(side, .scored), slot: slot) }
                                Button("Missed") { model.apply(.recordKick(side, .missed), slot: slot) }
                            }.disabled(match.phase != .shootout)
                        }
                    }
                    Spacer()
                    Button("Undo kick") { model.apply(.undoKick, slot: slot) }.disabled(s.kicks.isEmpty)
                }
            }.padding(6)
        }
    }
}
