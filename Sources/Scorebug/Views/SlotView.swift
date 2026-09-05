// One match slot: a resizable live preview on top, then the match card (home, competition and clock, away) and grouped sections.
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
    private var display: ClockDisplay { ClockEngine.display(match: match, style: themeConfig?.clockStyle ?? .runOn, now: tick) }

    var body: some View {
        VSplitView {
            PreviewStage(slot: slot).frame(minHeight: 180, idealHeight: 300)
            Form {
                matchCard
                clockSection
                goalsSection
                shootoutSection
                designSection
            }
            .formStyle(.grouped)
            .frame(minHeight: 320)
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

    // MARK: Match card

    private var matchCard: some View {
        Section {
            HStack(alignment: .top, spacing: 0) {
                teamColumn(.home)
                Divider().padding(.vertical, 8)
                centreColumn
                Divider().padding(.vertical, 8)
                teamColumn(.away)
            }
            .padding(.vertical, 6)
        }
    }

    private func teamColumn(_ side: Side) -> some View {
        let team = match.team(side)
        let clubs = model.library.clubs(in: match.competitionId)
        return VStack(spacing: 12) {
            Text(side == .home ? "HOME" : "AWAY").font(.caption.weight(.semibold)).foregroundStyle(.secondary).tracking(1.2)
            CrestView(team: team, size: 72)
            Picker("", selection: Binding<UUID?>(get: { team.clubId }, set: { id in model.setClub(clubs.first { $0.id == id }, side: side, slot: slot) })) {
                Text("Choose a club").tag(UUID?.none)
                ForEach(clubs) { c in Text(c.name).tag(UUID?.some(c.id)) }
            }.labelsHidden().frame(maxWidth: 220)
            Text(team.code).font(.caption.monospaced()).foregroundStyle(.secondary)
            HStack(spacing: 14) {
                Button { model.apply(.goal(side, -1), slot: slot) } label: { Image(systemName: "minus").frame(width: 14) }
                    .controlSize(.large).disabled(match.score(side) == 0).help("Remove the last \(team.shortName) goal")
                Text("\(match.score(side))").font(.system(size: 48, weight: .bold, design: .rounded)).monospacedDigit().frame(minWidth: 60)
                Button { model.apply(.goal(side, 1), slot: slot) } label: { Image(systemName: "plus").frame(width: 14) }
                    .controlSize(.large).buttonStyle(.borderedProminent).disabled(match.phase == .shootout).help("Goal for \(team.shortName)")
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 12)
    }

    private var centreColumn: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                if let c = competition { CompetitionMark(competition: c, size: 30) }
                Picker("Competition", selection: Binding(get: { match.competitionId }, set: { model.setCompetition($0, slot: slot) })) {
                    ForEach(model.library.competitions) { c in Text(c.name).tag(c.id) }
                }.labelsHidden().frame(maxWidth: 210)
            }
            Text(competition?.name ?? "Competition").font(.caption.weight(.semibold)).foregroundStyle(.secondary).tracking(1.2).textCase(.uppercase)
            Text(display.state ?? display.main).font(.system(size: 40, weight: .semibold, design: .rounded)).monospacedDigit()
            HStack(spacing: 8) {
                if let a = display.added { Text(a).font(.title3.weight(.semibold)).foregroundStyle(.orange) }
                if let c = display.addedCounter { Text(c).font(.callout).monospacedDigit().foregroundStyle(.secondary) }
            }.frame(height: 20)
            Text(phaseTitle).font(.callout).foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Button(match.clock.running ? "Pause" : "Play") { model.apply(.play, slot: slot) }.disabled(match.currentPeriod == nil)
                Button("End Period") { model.apply(.endPeriod, slot: slot) }.disabled(match.currentPeriod == nil)
                Button("Swap") { model.apply(.swapTeams, slot: slot) }.help("Swap home and away")
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 12)
    }

    // MARK: Clock

    private var clockSection: some View {
        Section("Clock") {
            LabeledContent("Start") { HStack { ForEach(Period.allCases, id: \.self) { p in periodButton(p) } } }
            LabeledContent("Added time") {
                HStack {
                    Stepper(value: Binding(get: { match.addedMinutes ?? 0 }, set: { model.apply(.setAddedMinutes($0), slot: slot) }), in: 0...15) {
                        Text(match.addedMinutes.map { "+\($0) min" } ?? "None").monospacedDigit().frame(minWidth: 64, alignment: .leading)
                    }
                    Button("Clear") { model.apply(.setAddedMinutes(nil), slot: slot) }.disabled(match.addedMinutes == nil)
                }
            }
            if let t = themeConfig {
                Text(t.clockStyle == .runOn ? "This design keeps counting past 45:00 and shows the added minutes beside the clock, as the broadcast does." : "This design stops at 45:00 and counts the added time separately.").font(.caption).foregroundStyle(.secondary)
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

    // MARK: Goals

    private var goalsSection: some View {
        Section("Goals") {
            if match.goals.isEmpty {
                Text("No goals yet. Use the plus buttons above; each goal gets a line here for the scorer's name.").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(match.goals) { goal in
                LabeledContent("\(match.team(goal.side).shortName)  \(goal.minuteLabel)") {
                    TextField("Scorer", text: Binding(get: { goal.scorer ?? "" }, set: { model.apply(.setScorer(goal.id, $0), slot: slot) }))
                        .textFieldStyle(.roundedBorder).frame(maxWidth: 280)
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
                    LabeledContent("\(match.team(side).shortName)  \(s.tally(side))") {
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
                LabeledContent("Shootout") { Button("Start Shootout") { model.apply(.startShootout(.home), slot: slot) } }
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
                LabeledContent("Placement", value: "Horizontal \(t.geometry["h"]?.left ?? 0), \(t.geometry["h"]?.top ?? 0) px. Vertical centred, top \(t.geometry["v"]?.top ?? 0) px, max width \(t.geometry["v"]?.maxWidth ?? 0) px.")
            }
            Text("Official competition marks (the lion, the starball) can be imported in Library › Competitions and replace the drawn glyph.").font(.caption).foregroundStyle(.secondary)
        }
    }
}

/// Live preview of both pages from the local server, so the window shows exactly what OBS shows. Drag the divider below it to resize.
struct PreviewStage: View {
    @EnvironmentObject var model: AppModel
    let slot: Int
    var body: some View {
        GeometryReader { geo in
            let stageH = max(60, geo.size.height - 16)
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
        .frame(maxWidth: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
