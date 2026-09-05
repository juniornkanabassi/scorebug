// One match slot: a resizable live preview on top, then the match card (home, competition and clock, away) and grouped sections.
import SwiftUI
import ScorebugCore

struct SlotView: View {
    @EnvironmentObject var model: AppModel
    let slot: Int
    /// Goal whose scorer popover should be open. Set right after a plus button scores a goal so the
    /// popover appears on that goal's row without the plus button itself waiting on anything.
    @State private var scorerPopoverGoalId: UUID?

    private var match: Match { model.match(slot) }
    private var competition: Competition? { model.library.competitions.first { $0.id == match.competitionId } }
    private var themeConfig: ThemeConfig? { model.resolver.themeConfig(id: match.themeId ?? competition?.themeId ?? match.competitionId) }

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
            Text(side == .home ? "HOME" : "AWAY").scaledFont(.caption, weight: .semibold).foregroundStyle(.secondary).tracking(1.2)
            CrestView(team: team, size: 72)
            Picker("", selection: Binding<UUID?>(get: { team.clubId }, set: { id in model.setClub(clubs.first { $0.id == id }, side: side, slot: slot) })) {
                Text("Choose a club").tag(UUID?.none)
                ForEach(clubs) { c in Text(c.name).tag(UUID?.some(c.id)) }
            }.labelsHidden().frame(maxWidth: 220)
            // A placeholder reads "Home" or "Away" in full; a chosen club shows its broadcast code.
            Text(team.clubId == nil ? team.name : team.code).scaledFont(.caption).monospaced().foregroundStyle(.secondary)
            HStack(spacing: 14) {
                Button { model.apply(.goal(side, -1), slot: slot) } label: { Image(systemName: "minus").frame(width: 14) }
                    .controlSize(.large).disabled(match.score(side) == 0).help("Remove the last \(team.shortName) goal")
                Text("\(match.score(side))").scaledFont(size: 48, weight: .bold, design: .rounded).monospacedDigit().frame(minWidth: 60)
                Button {
                    model.apply(.goal(side, 1), slot: slot)
                    // Open the new goal's scorer popover without making the plus button wait on it.
                    scorerPopoverGoalId = match.lastGoal?.goalId
                } label: { Image(systemName: "plus").frame(width: 14) }
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
            Text(competition?.name ?? "Competition").scaledFont(.caption, weight: .semibold).foregroundStyle(.secondary).tracking(1.2).textCase(.uppercase)
            ClockReadout(match: match, style: themeConfig?.clockStyle ?? .runOn)
            HStack(spacing: 8) {
                Button(match.clock.running ? "Pause" : "Play") { model.apply(.play, slot: slot) }.disabled(match.currentPeriod == nil)
                Button("End half") { model.apply(.endPeriod, slot: slot) }.disabled(match.currentPeriod == nil)
                Button("Swap") { model.apply(.swapTeams, slot: slot) }.help("Swap home and away")
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 12)
    }

    /// Manual clock correction, for when play was pressed late and the bug needs to line up with the
    /// broadcast: small nudge buttons for quick offsets, and "Set time…" for typing an exact value.
    private var clockNudgeRow: some View {
        HStack(spacing: 6) {
            clockNudgeButton("−1 min", -60)
            clockNudgeButton("−10 s", -10)
            clockNudgeButton("−1 s", -1)
            clockNudgeButton("+1 s", 1)
            clockNudgeButton("+10 s", 10)
            clockNudgeButton("+1 min", 60)
            SetClockButton(match: match, slot: slot)
        }
    }

    private func clockNudgeButton(_ title: String, _ delta: Int) -> some View {
        Button(title) { model.apply(.adjustClock(deltaSeconds: delta), slot: slot) }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(match.currentPeriod == nil)
    }

    // MARK: Clock

    private var clockSection: some View {
        Section("Clock") {
            LabeledContent("Start") { HStack { ForEach(Period.allCases, id: \.self) { p in periodButton(p) } } }
            LabeledContent("Adjust") { clockNudgeRow }
            LabeledContent("Added time") {
                HStack {
                    Stepper(value: Binding(get: { match.addedMinutes ?? 0 }, set: { model.apply(.setAddedMinutes($0), slot: slot) }), in: 0...15) {
                        Text(match.addedMinutes.map { "+\($0) min" } ?? "None").monospacedDigit().frame(minWidth: 64, alignment: .leading)
                    }
                    Button("Clear") { model.apply(.setAddedMinutes(nil), slot: slot) }.disabled(match.addedMinutes == nil)
                }
            }
            if let t = themeConfig {
                Text(t.clockStyle == .runOn ? "This design keeps counting past 45:00 and shows the added minutes beside the clock, as the broadcast does." : "This design stops at 45:00 and counts the added time separately.").scaledFont(.caption).foregroundStyle(.secondary)
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

    // MARK: Goals

    private var goalsSection: some View {
        Section("Goals") {
            if match.goals.isEmpty {
                Text("No goals yet. Use the plus buttons above; each goal gets a line here for the scorer's name.").scaledFont(.caption).foregroundStyle(.secondary)
            }
            ForEach(match.goals) { goal in
                LabeledContent("\(match.team(goal.side).shortName)  \(goal.minuteLabel)") {
                    ScorerButton(goal: goal, squad: match.team(goal.side).squad ?? [], slot: slot, openGoalId: $scorerPopoverGoalId)
                }
            }
            if !match.goals.isEmpty {
                Text("Scorers appear in a strap under the bug for a few seconds every minute or so.").scaledFont(.caption).foregroundStyle(.secondary)
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
                            if s.nextSide == side && match.phase == .shootout { Text("to kick").scaledFont(.caption).foregroundStyle(.secondary) }
                            Button("Scored") { model.apply(.recordKick(side, .scored), slot: slot) }.disabled(match.phase != .shootout)
                            Button("Missed") { model.apply(.recordKick(side, .missed), slot: slot) }.disabled(match.phase != .shootout)
                        }
                    }
                }
                Button("Undo Last Kick") { model.apply(.undoKick, slot: slot) }.disabled(s.kicks.isEmpty)
            } else {
                LabeledContent("Shootout") { Button("Start Shootout") { model.apply(.startShootout(.home), slot: slot) } }
                Text("The bug shows PENS with a kick row; the match score stays and the shootout tally sits beside it.").scaledFont(.caption).foregroundStyle(.secondary)
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
            Text("Official competition marks (the lion, the starball) can be imported in Library › Competitions and replace the drawn glyph.").scaledFont(.caption).foregroundStyle(.secondary)
        }
    }
}

/// The ticking clock and phase label, alone. This is the only part of a slot that changes four times a second,
/// so it owns its own `Timer.publish` subscription; `SlotView` does not subscribe, and a tick here re-renders
/// only this small view, leaving pickers and buttons elsewhere in the tree untouched.
struct ClockReadout: View {
    let match: Match
    let style: ClockStyle
    @State private var tick = Date()
    private let timer = Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()
    private var display: ClockDisplay { ClockEngine.display(match: match, style: style, now: tick) }

    var body: some View {
        VStack(spacing: 12) {
            Text(display.state ?? display.main).scaledFont(size: 40, weight: .semibold, design: .rounded).monospacedDigit()
            HStack(spacing: 8) {
                if let a = display.added { Text(a).scaledFont(.title3, weight: .semibold).foregroundStyle(.orange) }
                if let c = display.addedCounter { Text(c).scaledFont(.callout).monospacedDigit().foregroundStyle(.secondary) }
            }.frame(height: 20)
            Text(phaseTitle).scaledFont(.callout).foregroundStyle(.secondary)
        }
        .onReceive(timer) { tick = $0 }
    }

    private var phaseTitle: String {
        switch match.phase {
        case .preMatch: return "Pre-match"; case .firstHalf: return "First half"; case .halfTime: return "Half time"
        case .secondHalf: return "Second half"; case .fullTime: return "Full time"; case .extraFirst: return "Extra time, first half"
        case .extraBreak: return "Extra time break"; case .extraSecond: return "Extra time, second half"; case .extraFullTime: return "After extra time"
        case .shootout: return "Penalty shootout"; case .finished: return "Finished"
        }
    }
}

/// "Set time…": a popover with a free-text field for the exact match time the owner sees on the broadcast
/// (mm:ss, "47m" for minutes, or a plain number of seconds), a live preview of what that parses to, and an
/// Apply button. The field is read as the on-screen cumulative time the owner wants, matching what a
/// broadcast graphic shows and what the popover previews back; `apply()` converts that into the period-local
/// value `Command.setClock` expects (see its doc comment) by subtracting the current period's base, so the
/// owner never has to do that arithmetic themselves in the second half or extra time.
struct SetClockButton: View {
    @EnvironmentObject var model: AppModel
    let match: Match
    let slot: Int
    @State private var text = ""
    @State private var isOpen = false
    @FocusState private var fieldFocused: Bool

    private var periodBaseSeconds: Int { match.currentPeriod?.baseSeconds ?? 0 }
    private var parsedSeconds: Int? { Self.parse(text) }

    var body: some View {
        Button("Set time…") { text = ""; isOpen = true }
            .disabled(match.currentPeriod == nil)
            .popover(isPresented: $isOpen) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Set match clock").scaledFont(.headline)
                    TextField("mm:ss, minutes, or seconds", text: $text)
                        .textFieldStyle(.roundedBorder)
                        .focused($fieldFocused)
                        .frame(width: 220)
                        .onSubmit(apply)
                    if let seconds = parsedSeconds {
                        Text("Sets the clock to \(ClockEngine.format(seconds)).").scaledFont(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("Enter mm:ss (47:30), minutes (47m), or plain seconds.").scaledFont(.caption).foregroundStyle(.secondary)
                    }
                    Text("The clock keeps running from this value if it's currently running, or stays paused at it if it's paused.")
                        .scaledFont(.caption).foregroundStyle(.secondary)
                    HStack {
                        Spacer()
                        Button("Apply", action: apply)
                            .keyboardShortcut(.defaultAction)
                            .disabled(parsedSeconds == nil)
                    }
                }
                .padding(12)
                .onAppear { fieldFocused = true }
            }
    }

    private func apply() {
        guard let seconds = parsedSeconds else { return }
        model.apply(.setClock(seconds: max(0, seconds - periodBaseSeconds)), slot: slot)
        isOpen = false
    }

    /// Parses "mm:ss" (colon splits minutes and seconds), "<n>m" / "<n>min" (minutes), or a bare integer
    /// (seconds) into a total number of seconds. Returns nil for anything else, including negative values.
    static func parse(_ raw: String) -> Int? {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.contains(":") {
            let parts = trimmed.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2, let mm = Int(parts[0]), let ss = Int(parts[1]), mm >= 0, ss >= 0, ss < 60 else { return nil }
            return mm * 60 + ss
        }
        let lower = trimmed.lowercased()
        if lower.hasSuffix("min") || lower.hasSuffix("m") {
            let digits = lower.hasSuffix("min") ? String(lower.dropLast(3)) : String(lower.dropLast(1))
            guard let minutes = Int(digits.trimmingCharacters(in: .whitespaces)), minutes >= 0 else { return nil }
            return minutes * 60
        }
        guard let seconds = Int(lower), seconds >= 0 else { return nil }
        return seconds
    }
}

/// A goal's scorer control: a button showing the current scorer, or "Add scorer", that opens a popover with a
/// search field over the scoring club's squad. Clicking a name (or pressing Return with no exact match, which
/// uses the typed text as a custom name) sets the scorer and closes the popover.
struct ScorerButton: View {
    @EnvironmentObject var model: AppModel
    let goal: Goal
    let squad: [String]
    let slot: Int
    @Binding var openGoalId: UUID?
    @State private var query = ""
    @FocusState private var searchFocused: Bool

    private var isOpen: Bool { openGoalId == goal.id }
    private var filtered: [String] { query.isEmpty ? squad : squad.filter { squadNameMatches($0, query: query) } }

    var body: some View {
        Button(goal.scorer?.isEmpty == false ? goal.scorer! : "Add scorer") {
            query = ""
            openGoalId = goal.id
        }
        .frame(maxWidth: 280, alignment: .leading)
        .popover(isPresented: Binding(get: { isOpen }, set: { if !$0 { openGoalId = nil } })) {
            VStack(alignment: .leading, spacing: 0) {
                TextField("Search scorer", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .focused($searchFocused)
                    .padding(8)
                    .onSubmit(submitQuery)
                Divider()
                if squad.isEmpty {
                    Text("No squad on file, type a name").scaledFont(.caption).foregroundStyle(.secondary).padding(8)
                } else if filtered.isEmpty {
                    Text("No match. Press Return to use \"\(query)\".").scaledFont(.caption).foregroundStyle(.secondary).padding(8)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(filtered, id: \.self) { name in
                                Button(name) { pick(name) }
                                    .buttonStyle(.plain)
                                    .padding(.vertical, 4).padding(.horizontal, 8)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .contentShape(Rectangle())
                            }
                        }
                    }.frame(maxHeight: 200)
                }
            }
            .frame(width: 260)
            .onAppear { searchFocused = true }
        }
    }

    private func submitQuery() {
        let typed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !typed.isEmpty else { return }
        if let exact = squad.first(where: { $0.compare(typed, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }) {
            pick(exact)
        } else {
            pick(typed)
        }
    }

    private func pick(_ name: String) {
        model.apply(.setScorer(goal.id, name), slot: slot)
        openGoalId = nil
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
