// One match slot, laid out like the Uno control app: preview on top, then Score, Match Time, Setup and Customize tabs.
import SwiftUI
import ScorebugCore

struct SlotView: View {
    @EnvironmentObject var model: AppModel
    let slot: Int
    @State private var tab = 0
    @State private var tick = Date()
    private let timer = Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()

    private var match: Match { model.match(slot) }
    private var competition: Competition? { model.library.competitions.first { $0.id == match.competitionId } }
    private var themeConfig: ThemeConfig? { model.resolver.themeConfig(id: match.themeId ?? competition?.themeId ?? match.competitionId) }

    var body: some View {
        VStack(spacing: 0) {
            header
            PreviewStage(slot: slot)
            UnoTabBar(tabs: ["Score", "Match Time", "Setup", "Customize"], selected: $tab)
            ScrollView {
                Group {
                    switch tab {
                    case 0: scoreTab
                    case 1: timeTab
                    case 2: setupTab
                    default: customizeTab
                    }
                }
                .frame(maxWidth: 640).padding(.vertical, 22).frame(maxWidth: .infinity)
            }
        }
        .background(Uno.bg)
        .onReceive(timer) { tick = $0 }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text(slot == 1 ? "Primary Scorebug" : "Secondary Scorebug").font(.system(size: 15, weight: .semibold)).foregroundStyle(Uno.text)
            Text("|").foregroundStyle(Uno.muted)
            Text(themeConfig?.name ?? "Theme").font(.system(size: 14)).foregroundStyle(Uno.muted)
            Spacer()
            Circle().fill(model.serverRunning ? Uno.green : Uno.red).frame(width: 8, height: 8)
            Text(model.serverRunning ? "localhost:\(model.port)" : "server off").font(.system(size: 12)).foregroundStyle(Uno.muted)
        }
        .padding(.horizontal, 20).frame(height: 44).background(Uno.panel)
    }

    // MARK: Score

    private var scoreTab: some View {
        VStack(alignment: .leading, spacing: 18) {
            FieldRow(label: "Overlay") { UnoSwitch(isOn: Binding(get: { match.visible }, set: { model.apply(.setVisible($0), slot: slot) })) }
            SectionTitle(text: "Goals")
            ForEach(Side.allCases, id: \.self) { side in
                FieldRow(label: match.team(side).code) {
                    ValueBox(text: "\(match.score(side))")
                    RoundButton(symbol: "minus") { model.apply(.goal(side, -1), slot: slot) }
                    RoundButton(symbol: "plus", prominent: true) { model.apply(.goal(side, 1), slot: slot) }
                }.disabled(match.phase == .shootout)
            }
            if !match.goals.isEmpty {
                SectionTitle(text: "Scorers")
                ForEach(match.goals) { goal in
                    FieldRow(label: "\(match.team(goal.side).code)  \(goal.minuteLabel)") {
                        TextField("Scorer name", text: Binding(get: { goal.scorer ?? "" }, set: { model.apply(.setScorer(goal.id, $0), slot: slot) }))
                            .textFieldStyle(.plain).font(.system(size: 14)).foregroundStyle(Uno.text)
                            .padding(.horizontal, 10).frame(width: 240, height: 34).background(Uno.panel2).clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
                Text("The scorers strap shows under the bug for a few seconds every minute or so.").font(.system(size: 12)).foregroundStyle(Uno.muted)
            }
        }
    }

    // MARK: Match time

    private var timeTab: some View {
        let d = ClockEngine.display(match: match, style: themeConfig?.clockStyle ?? .freezeAndCount, now: tick)
        return VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline, spacing: 14) {
                Text(d.state ?? d.main).font(.system(size: 46, weight: .bold, design: .rounded)).monospacedDigit().foregroundStyle(Uno.text)
                if let a = d.added { Text(a).font(.system(size: 26, weight: .semibold)).foregroundStyle(Uno.accent) }
                if let c = d.addedCounter { Text(c).font(.system(size: 20, weight: .medium)).monospacedDigit().foregroundStyle(Uno.muted) }
                Spacer()
                Text(phaseTitle).font(.system(size: 13, weight: .medium)).foregroundStyle(Uno.muted)
            }
            FieldRow(label: "Clock") {
                UnoPill(title: match.clock.running ? "Pause" : "Play", filled: true, disabled: match.currentPeriod == nil) { model.apply(.play, slot: slot) }
                UnoPill(title: "End period", disabled: match.currentPeriod == nil) { model.apply(.endPeriod, slot: slot) }
            }
            FieldRow(label: "Start") {
                ForEach(Period.allCases, id: \.self) { p in UnoPill(title: p.title, filled: match.phase == p.phase) { model.apply(.startPeriod(p), slot: slot) } }
            }
            FieldRow(label: "Added time") {
                ValueBox(text: match.addedMinutes.map { "+\($0)" } ?? "–")
                RoundButton(symbol: "minus") { model.apply(.adjustAddedMinutes(-1), slot: slot) }
                RoundButton(symbol: "plus", prominent: true) { model.apply(.adjustAddedMinutes(1), slot: slot) }
                UnoPill(title: "Clear", disabled: match.addedMinutes == nil) { model.apply(.setAddedMinutes(nil), slot: slot) }
            }
            SectionTitle(text: "Penalty shootout")
            FieldRow(label: "Shootout") {
                UnoPill(title: match.phase == .shootout ? "In progress" : "Start shootout", filled: match.phase != .shootout, disabled: match.phase == .shootout) { model.apply(.startShootout(.home), slot: slot) }
                if match.shootout != nil { UnoPill(title: "Undo kick", disabled: match.shootout?.kicks.isEmpty ?? true) { model.apply(.undoKick, slot: slot) } }
            }
            if let s = match.shootout {
                ForEach(Side.allCases, id: \.self) { side in
                    FieldRow(label: "\(match.team(side).code)  \(s.tally(side))") {
                        HStack(spacing: 6) {
                            ForEach(s.kicks.filter { $0.side == side }) { k in
                                Circle().fill(k.result == .scored ? Uno.green : k.result == .missed ? Uno.red : Uno.muted).frame(width: 12, height: 12)
                            }
                            if s.nextSide == side && match.phase == .shootout { Text("to kick").font(.system(size: 11)).foregroundStyle(Uno.muted) }
                        }.frame(minWidth: 120, alignment: .leading)
                        UnoPill(title: "Scored", disabled: match.phase != .shootout) { model.apply(.recordKick(side, .scored), slot: slot) }
                        UnoPill(title: "Missed", disabled: match.phase != .shootout) { model.apply(.recordKick(side, .missed), slot: slot) }
                    }
                }
            }
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

    // MARK: Setup

    private var setupTab: some View {
        let clubs = model.library.clubs(in: match.competitionId)
        return VStack(alignment: .leading, spacing: 18) {
            FieldRow(label: "Competition") {
                Picker("", selection: Binding(get: { match.competitionId }, set: { model.setCompetition($0, slot: slot) })) {
                    ForEach(model.library.competitions) { c in Text(c.name).tag(c.id) }
                }.labelsHidden().frame(width: 260)
            }
            ForEach(Side.allCases, id: \.self) { side in
                FieldRow(label: side == .home ? "Home (left)" : "Away (right)") {
                    Picker("", selection: Binding<UUID?>(get: { match.team(side).clubId }, set: { id in model.setClub(clubs.first { $0.id == id }, side: side, slot: slot) })) {
                        Text("Not set").tag(UUID?.none)
                        ForEach(clubs) { c in Text("\(c.name)  (\(c.code(for: match.competitionId)))").tag(UUID?.some(c.id)) }
                    }.labelsHidden().frame(width: 320)
                    crestThumb(match.team(side))
                }
            }
            FieldRow(label: "") {
                UnoPill(title: "Swap sides") { model.apply(.swapTeams, slot: slot) }
                UnoPill(title: "Reset match") { model.apply(.reset, slot: slot) }
            }
            Text("Clubs without a crest show a monogram. Add crests in Library, or import your logo folder in Settings.").font(.system(size: 12)).foregroundStyle(Uno.muted)
        }
    }

    private func crestThumb(_ team: TeamEntry) -> some View {
        Group {
            if let f = team.crestFile, let img = NSImage(contentsOf: model.store.crestsDirectory.appendingPathComponent(f)) {
                Image(nsImage: img).resizable().scaledToFit()
            } else {
                Circle().fill(Color(hex: team.primaryColour)).overlay(Text(String(team.code.prefix(2))).font(.system(size: 11, weight: .bold)).foregroundStyle(Color(hex: team.textColour)))
            }
        }.frame(width: 30, height: 30)
    }

    // MARK: Customize

    private var customizeTab: some View {
        VStack(alignment: .leading, spacing: 18) {
            FieldRow(label: "Design") {
                Picker("", selection: Binding<String>(get: { match.themeId ?? "" }, set: { model.apply(.setTheme($0.isEmpty ? nil : $0), slot: slot) })) {
                    Text("Follow competition (\(competition?.themeId ?? "none"))").tag("")
                    ForEach(model.resolver.availableThemeIds(), id: \.self) { id in
                        Text(model.resolver.themeConfig(id: id)?.name ?? id).tag(id)
                    }
                }.labelsHidden().frame(width: 320)
            }
            if let t = themeConfig {
                FieldRow(label: "Clock style") { Text(t.clockStyle == .runOn ? "Runs on past 45:00, +N beside it" : "Freezes at 45:00, added time counted separately").font(.system(size: 13)).foregroundStyle(Uno.muted) }
                FieldRow(label: "Horizontal") { Text("left \(t.geometry["h"]?.left ?? 0)px, top \(t.geometry["h"]?.top ?? 0)px").font(.system(size: 13)).foregroundStyle(Uno.muted) }
                FieldRow(label: "Vertical") { Text("centred, top \(t.geometry["v"]?.top ?? 0)px, max width \(t.geometry["v"]?.maxWidth ?? 0)px").font(.system(size: 13)).foregroundStyle(Uno.muted) }
            }
            Text("Designs are CSS files in the app. Copy one into the overrides folder (Settings) to tweak it without a rebuild.").font(.system(size: 12)).foregroundStyle(Uno.muted)
        }
    }
}

/// The black stage at the top of the panel with the horizontal page, and the vertical page beside it.
struct PreviewStage: View {
    @EnvironmentObject var model: AppModel
    let slot: Int
    var body: some View {
        GeometryReader { geo in
            let stageH = geo.size.height
            let hW = stageH * 16 / 9, vW = stageH * 9 / 16
            HStack(spacing: 10) {
                Spacer(minLength: 0)
                OverlayWebView(url: URL(string: "\(model.baseURL)/overlay/h/\(slot)")!, scale: hW / 1920, size: CGSize(width: 1920, height: 1080))
                    .frame(width: hW, height: stageH).background(.black)
                OverlayWebView(url: URL(string: "\(model.baseURL)/overlay/v/\(slot)")!, scale: vW / 1080, size: CGSize(width: 1080, height: 1920))
                    .frame(width: vW, height: stageH).background(.black)
                Spacer(minLength: 0)
            }
        }
        .frame(height: 300).frame(maxWidth: .infinity).background(Uno.bg)
    }
}
