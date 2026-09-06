// One match slot: a resizable live preview on top, then the match card (home, competition and clock, away) and grouped sections.
import SwiftUI
import ScorebugCore

/// Short pill label for the period row, matching Uno Overlays' "Match Time" tab wording;
/// `.title` (from ScorebugCore) stays the tooltip's full name.
extension Period {
    var shortLabel: String {
        switch self {
        case .firstHalf: return "1st half"
        case .secondHalf: return "2nd half"
        case .extraFirst: return "1st extra"
        case .extraSecond: return "2nd extra"
        }
    }
}

/// Full display name for the match phase, shown under the clock and beside the period pills
/// while no period is live.
extension Phase {
    var displayTitle: String {
        switch self {
        case .preMatch: return "Pre-match"; case .firstHalf: return "First half"; case .halfTime: return "Half time"
        case .secondHalf: return "Second half"; case .fullTime: return "Full time"; case .extraFirst: return "Extra time, first half"
        case .extraBreak: return "Extra time break"; case .extraSecond: return "Extra time, second half"; case .extraFullTime: return "After extra time"
        case .shootout: return "Penalty shootout"; case .finished: return "Finished"
        }
    }
}

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
            }
            .formStyle(.grouped)
            .frame(minHeight: 320)
        }
        .navigationTitle(slot == 1 ? "Primary match" : "Secondary match")
        .navigationSubtitle("\(match.home.name) v \(match.away.name)")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button { model.apply(.playPause, slot: slot) } label: { Label(match.clock.running ? "Pause" : "Play", systemImage: match.clock.running ? "pause.fill" : "play.fill").scaledFont(.body) }
                    .disabled(match.currentPeriod == nil).help("Play or pause the clock (Space)").keyboardShortcut(.space, modifiers: [])
                Toggle(isOn: Binding(get: { match.visible }, set: { model.apply(.setVisible($0), slot: slot) })) {
                    Label(match.visible ? "Bug shown" : "Bug hidden", systemImage: match.visible ? "eye" : "eye.slash").scaledFont(.body)
                }.toggleStyle(.button).help("Show or hide the bug in OBS")
                Button(role: .destructive) { model.apply(.reset, slot: slot) } label: { Label("Reset", systemImage: "arrow.counterclockwise").scaledFont(.body) }
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
        return VStack(spacing: 12) {
            Text(side == .home ? "HOME" : "AWAY").scaledFont(.caption, weight: .semibold).foregroundStyle(.secondary).tracking(1.2)
            CrestView(team: team, size: 72)
            ClubPickerButton(side: side, slot: slot)
            // A placeholder reads "Home" or "Away" in full; a chosen club shows its broadcast code.
            Text(team.clubId == nil ? team.name : team.code).scaledFont(.caption).monospaced().foregroundStyle(.secondary)
            Text("\(match.score(side))").scaledFont(size: 48, weight: .bold, design: .rounded).monospacedDigit().frame(minWidth: 60)
            // The plus is the button pressed live, over and over, so it gets the large, unmissable
            // hit target (44x44 pt minimum, per Apple's own floor for a control meant to be hit
            // quickly and often); the minus is only ever an undo, so it stays small and secondary.
            HStack(spacing: 16) {
                Button { model.apply(.goal(side, -1), slot: slot) } label: { Image(systemName: "minus").scaledFont(.callout, weight: .semibold) }
                    .buttonStyle(.bordered).controlSize(.small).frame(width: 28, height: 28)
                    .disabled(match.score(side) == 0).help("Remove the last \(team.shortName) goal")
                Button {
                    model.apply(.goal(side, 1), slot: slot)
                    // Open the new goal's scorer popover without making the plus button wait on it.
                    scorerPopoverGoalId = match.lastGoal?.goalId
                } label: { Image(systemName: "plus").scaledFont(.title2, weight: .bold) }
                    .buttonStyle(.borderedProminent).frame(width: 44, height: 44)
                    .disabled(match.phase == .shootout).help("Goal for \(team.shortName)")
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 12)
    }

    private var centreColumn: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                // On a small light plate: a dark broadcast mark (the Premier League lion, drawn
                // dark-on-transparent) would otherwise disappear against this dark card.
                if let c = competition { CompetitionMark(competition: c, size: 30, plate: true) }
                Picker("Competition", selection: Binding(get: { match.competitionId }, set: { model.setCompetition($0, slot: slot) })) {
                    ForEach(model.library.competitions) { c in Text(c.name).tag(c.id) }
                }.scaledFont(.body).labelsHidden().frame(maxWidth: 210)
            }
            Text(competition?.name ?? "Competition").scaledFont(.caption, weight: .semibold).foregroundStyle(.secondary).tracking(1.2).textCase(.uppercase)
            ClockReadout(match: match, style: themeConfig?.clockStyle ?? .runOn)
            // "End half" moved down to sit beside the period pills in the Clock section, where it
            // reads as part of period control rather than a peer of Play/Pause here.
            Button { model.apply(.playPause, slot: slot) } label: {
                Label(match.clock.running ? "Pause" : "Play", systemImage: match.clock.running ? "pause.fill" : "play.fill").scaledFont(.body)
            }.disabled(match.currentPeriod == nil).help("Play or pause the clock (Space)")
            // Swapping ends is rare and deliberate, unlike Play/End half which are pressed live and
            // often, so it sits apart and smaller rather than sharing weight with them.
            Button("Swap", systemImage: "arrow.left.arrow.right") { model.apply(.swapTeams, slot: slot) }
                .scaledFont(.body).controlSize(.small).buttonStyle(.plain).foregroundStyle(.secondary)
                .help("Swap home and away")
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 12)
    }

    /// A period already finished (the match phase has moved past it, e.g. half time is past first
    /// half) can't be restarted from its pill; the live period's own pill stays enabled so re-pressing
    /// it is harmless.
    private func isPeriodOver(_ period: Period) -> Bool {
        let phases = Phase.allCases
        guard let matchIndex = phases.firstIndex(of: match.phase), let periodIndex = phases.firstIndex(of: period.phase) else { return false }
        return matchIndex > periodIndex
    }

    private var periodRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                ForEach(Period.allCases, id: \.self) { p in periodPill(p) }
                Button("End half") { model.apply(.endPeriod, slot: slot) }
                    .scaledFont(.body)
                    .disabled(match.currentPeriod == nil)
            }
            if match.currentPeriod == nil {
                Text(match.phase.displayTitle).scaledFont(.caption).foregroundStyle(.secondary)
            }
        }
    }

    /// `.bordered` and `.borderedProminent` are different concrete `ButtonStyle` types, so the live/not-live
    /// choice between them needs two branches rather than one `buttonStyle(_ cond ? a : b)`.
    @ViewBuilder
    private func periodPill(_ p: Period) -> some View {
        let button = Button(p.shortLabel) { model.apply(.startPeriod(p), slot: slot) }
            .scaledFont(.body)
            .disabled(isPeriodOver(p))
            .help(p.title)
        if match.currentPeriod == p {
            button.buttonStyle(.borderedProminent)
        } else {
            button.buttonStyle(.bordered)
        }
    }

    // MARK: Clock

    private var clockSection: some View {
        Section("Clock") {
            LabeledContent("Period") { periodRow }.scaledFont(.body)
            LabeledContent("Clock") {
                HStack(spacing: 16) {
                    ClockFieldsRow(slot: slot)
                    Button { model.apply(.playPause, slot: slot) } label: {
                        Label(match.clock.running ? "Pause" : "Play", systemImage: match.clock.running ? "pause.fill" : "play.fill").scaledFont(.body)
                    }.disabled(match.currentPeriod == nil)
                    Button("Reset") { model.apply(.setClock(seconds: 0), slot: slot) }
                        .scaledFont(.body)
                        .disabled(match.currentPeriod == nil)
                        .help("Back to the start of this period")
                }
            }
            .scaledFont(.body)
            LabeledContent("Stoppage time") {
                HStack(spacing: 14) {
                    Toggle(isOn: Binding(
                        get: { match.addedMinutes != nil },
                        set: { on in model.apply(.setAddedMinutes(on ? max(1, match.addedMinutes ?? 1) : nil), slot: slot) }
                    )) { EmptyView() }.labelsHidden().toggleStyle(.switch)
                    Text("Minutes").scaledFont(.body).foregroundStyle(match.addedMinutes == nil ? .secondary : .primary)
                    HStack(spacing: 6) {
                        Button { adjustStoppageMinutes(-1) } label: { Image(systemName: "minus").scaledFont(.callout, weight: .semibold) }
                            .buttonStyle(.bordered).buttonBorderShape(.circle).controlSize(.small)
                        // A plain get/set binding (no focus juggling) is enough here: unlike the clock,
                        // added minutes never changes on its own between keystrokes, only in response to
                        // this same field, a nudge button, or an explicit command, so there's nothing to fight.
                        TextField("", text: Binding(
                            get: { "\(match.addedMinutes ?? 1)" },
                            set: { text in if let n = Int(text) { model.apply(.setAddedMinutes(min(15, max(1, n))), slot: slot) } }
                        ))
                        .scaledFont(.body).monospacedDigit().multilineTextAlignment(.center)
                        .textFieldStyle(.roundedBorder).frame(width: 36)
                        Button { adjustStoppageMinutes(1) } label: { Image(systemName: "plus").scaledFont(.callout, weight: .semibold) }
                            .buttonStyle(.bordered).buttonBorderShape(.circle).controlSize(.small)
                    }
                    .disabled(match.addedMinutes == nil)
                }
            }
            .scaledFont(.body)
            if let t = themeConfig {
                Text(t.clockStyle == .runOn ? "This design keeps counting past 45:00 and shows the added minutes beside the clock, as the broadcast does." : "This design stops at 45:00 and counts the added time separately.").scaledFont(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func adjustStoppageMinutes(_ delta: Int) {
        let next = min(15, max(1, (match.addedMinutes ?? 1) + delta))
        model.apply(.setAddedMinutes(next), slot: slot)
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
                .scaledFont(.body)
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
                            Button("Scored") { model.apply(.recordKick(side, .scored), slot: slot) }.scaledFont(.body).disabled(match.phase != .shootout)
                            Button("Missed") { model.apply(.recordKick(side, .missed), slot: slot) }.scaledFont(.body).disabled(match.phase != .shootout)
                        }
                    }
                    .scaledFont(.body)
                }
                Button("Undo Last Kick") { model.apply(.undoKick, slot: slot) }.scaledFont(.body).disabled(s.kicks.isEmpty)
            } else {
                LabeledContent("Shootout") { Button("Start Shootout") { model.apply(.startShootout(.home), slot: slot) }.scaledFont(.body) }.scaledFont(.body)
                Text("The bug shows PENS with a kick row; the match score stays and the shootout tally sits beside it.").scaledFont(.caption).foregroundStyle(.secondary)
            }
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
            Text(match.phase.displayTitle).scaledFont(.callout, weight: .medium).pillBadge()
        }
        .onReceive(timer) { tick = $0 }
    }
}

/// The editable minutes/seconds pair in the Clock row: each shows the cumulative on-screen time (period
/// base + elapsed, the same value `ClockReadout` derives via `Clock.elapsed(at:)`), flanked by round −/+
/// buttons that nudge the clock directly. Like `ClockReadout`, this owns its own quarter-second timer so
/// the running clock doesn't re-render the rest of the form. Typing a value only takes effect on Return
/// (`onSubmit`), and the text mirrors re-sync from the match on every tick *unless* a field is focused, so
/// a running clock never overwrites what the owner is mid-typing.
struct ClockFieldsRow: View {
    @EnvironmentObject var model: AppModel
    let slot: Int
    @State private var tick = Date()
    private let timer = Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()
    @State private var minutesText = "0"
    @State private var secondsText = "00"
    @FocusState private var minutesFocused: Bool
    @FocusState private var secondsFocused: Bool

    private var match: Match { model.match(slot) }
    private var periodBaseSeconds: Int { match.currentPeriod?.baseSeconds ?? 0 }
    private var cumulativeSeconds: Int { Int(match.clock.elapsed(at: tick)) }

    var body: some View {
        HStack(spacing: 14) {
            field(text: $minutesText, focused: $minutesFocused, unit: "min", nudge: 60, width: 40)
            field(text: $secondsText, focused: $secondsFocused, unit: "sec", nudge: 1, width: 34)
        }
        .disabled(match.currentPeriod == nil)
        .onReceive(timer) { tick = $0; resyncIfIdle() }
        .onAppear { resyncIfIdle(force: true) }
    }

    private func field(text: Binding<String>, focused: FocusState<Bool>.Binding, unit: String, nudge: Int, width: CGFloat) -> some View {
        HStack(spacing: 6) {
            Button { model.apply(.adjustClock(deltaSeconds: -nudge), slot: slot) } label: { Image(systemName: "minus").scaledFont(.callout, weight: .semibold) }
                .buttonStyle(.bordered).buttonBorderShape(.circle).controlSize(.small)
                .help("Subtract \(nudge == 60 ? "1 min" : "1 s") from the clock")
            HStack(spacing: 4) {
                TextField("", text: text)
                    .scaledFont(.body).monospacedDigit().multilineTextAlignment(.trailing)
                    .textFieldStyle(.plain).frame(width: width)
                    .focused(focused)
                    .onSubmit(applyTypedTime)
                Text(unit).scaledFont(.caption).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.secondary.opacity(0.35)))
            Button { model.apply(.adjustClock(deltaSeconds: nudge), slot: slot) } label: { Image(systemName: "plus").scaledFont(.callout, weight: .semibold) }
                .buttonStyle(.bordered).buttonBorderShape(.circle).controlSize(.small)
                .help("Add \(nudge == 60 ? "1 min" : "1 s") to the clock")
        }
    }

    /// Re-reads the match clock into the text fields, unless the owner is mid-edit in either of them.
    private func resyncIfIdle(force: Bool = false) {
        guard force || (!minutesFocused && !secondsFocused) else { return }
        let s = cumulativeSeconds
        minutesText = "\(s / 60)"
        secondsText = String(format: "%02d", s % 60)
    }

    /// Same conversion `SetClockButton.apply` used to do: the typed minutes/seconds are the on-screen
    /// cumulative time, so the period's own base is subtracted back out before sending `.setClock`.
    private func applyTypedTime() {
        guard let m = Int(minutesText), let s = Int(secondsText), match.currentPeriod != nil else { resyncIfIdle(force: true); return }
        model.apply(.setClock(seconds: max(0, m * 60 + s - periodBaseSeconds)), slot: slot)
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
        .scaledFont(.body)
        .frame(maxWidth: 280, alignment: .leading)
        .popover(isPresented: Binding(get: { isOpen }, set: { if !$0 { openGoalId = nil } })) {
            VStack(alignment: .leading, spacing: 0) {
                TextField("Search scorer", text: $query)
                    .scaledFont(.body)
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
                                    .scaledFont(.body)
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

/// A Home or Away column's club control: a button showing the current team (crest thumbnail, name,
/// chevron) that opens a search popover over the whole library, same pattern as `ScorerButton` above.
/// The plain alphabetical menu of about 165 clubs and nations it replaces was impractical to scroll;
/// this groups results instead and narrows them as the owner types. `model.setClub(_:side:slot:)` stays
/// the only side effect, exactly as the old picker's `onChange` was.
struct ClubPickerButton: View {
    @EnvironmentObject var model: AppModel
    let side: Side
    let slot: Int
    @State private var query = ""
    @State private var isOpen = false
    @FocusState private var searchFocused: Bool

    private var match: Match { model.match(slot) }
    private var team: TeamEntry { match.team(side) }

    /// A club is a national team when its `competitionIds` contains "international" (same rule as
    /// `LibraryFilters`'s Clubs/Nations split, kept in sync with it).
    private func isNational(_ club: Club) -> Bool { club.competitionIds.contains("international") }
    private func inThisCompetition(_ club: Club) -> Bool { club.competitionIds.isEmpty || club.competitionIds.contains(match.competitionId) }

    /// Search results split into the three groups the popover shows, each sorted alphabetically;
    /// national teams are pulled out first so a club's own competition membership only has to
    /// distinguish "in this competition" from "other clubs".
    private var groups: (inCompetition: [Club], other: [Club], nations: [Club]) {
        let all = model.library.clubs
        let filtered = query.isEmpty ? all : all.filter { nameMatches($0, in: match.competitionId, query: query) }
        let nations = filtered.filter(isNational).sorted { $0.name < $1.name }
        let clubsOnly = filtered.filter { !isNational($0) }
        let inComp = clubsOnly.filter(inThisCompetition).sorted { $0.name < $1.name }
        let other = clubsOnly.filter { !inThisCompetition($0) }.sorted { $0.name < $1.name }
        return (inComp, other, nations)
    }

    /// What Return picks: the first row in reading order (in-competition clubs, then other clubs,
    /// then national teams), matching how the groups are drawn top to bottom.
    private var firstResult: Club? {
        let g = groups
        return g.inCompetition.first ?? g.other.first ?? g.nations.first
    }

    var body: some View {
        Button {
            query = ""
            isOpen = true
        } label: {
            HStack(spacing: 8) {
                CrestView(team: team, size: 22)
                Text(team.name).scaledFont(.callout).lineLimit(1)
                Spacer(minLength: 4)
                Image(systemName: "chevron.down").scaledFont(.caption2).foregroundStyle(.secondary)
            }
            .frame(maxWidth: 220)
        }
        .buttonStyle(.bordered)
        .popover(isPresented: $isOpen) {
            VStack(alignment: .leading, spacing: 0) {
                TextField("Search club or nation", text: $query)
                    .scaledFont(.body)
                    .textFieldStyle(.roundedBorder)
                    .focused($searchFocused)
                    .padding(8)
                    .onSubmit(submitQuery)
                Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        noneRow
                        Divider().padding(.vertical, 2)
                        groupSection("In this competition", groups.inCompetition)
                        groupSection("Other clubs", groups.other)
                        groupSection("National teams", groups.nations)
                        if groups.inCompetition.isEmpty && groups.other.isEmpty && groups.nations.isEmpty {
                            Text("No match.").scaledFont(.caption).foregroundStyle(.secondary).padding(8)
                        }
                    }
                }.frame(maxHeight: 320)
            }
            .frame(width: 280)
            .onAppear { searchFocused = true }
        }
    }

    /// Always present, unfiltered by the search text, so the team can be cleared back to the
    /// placeholder ("Home"/"Away") no matter what is typed.
    private var noneRow: some View {
        Button(action: pickNone) {
            HStack(spacing: 8) {
                Image(systemName: "xmark.circle").foregroundStyle(.secondary)
                Text("None").foregroundStyle(.secondary)
            }
            .scaledFont(.body)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, 4).padding(.horizontal, 8)
    }

    @ViewBuilder
    private func groupSection(_ title: String, _ clubs: [Club]) -> some View {
        if !clubs.isEmpty {
            Text(title).scaledFont(.caption, weight: .semibold).foregroundStyle(.secondary)
                .padding(.horizontal, 8).padding(.top, 6).padding(.bottom, 2)
            ForEach(clubs) { club in clubRow(club) }
        }
    }

    private func clubRow(_ club: Club) -> some View {
        let entry = club.entry(for: match.competitionId)
        return Button { pick(club) } label: {
            HStack(spacing: 8) {
                CrestView(team: entry, size: 20)
                Text(entry.name).scaledFont(.body)
                Spacer()
                Text(entry.code).scaledFont(.caption).monospaced().foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, 4).padding(.horizontal, 8)
    }

    private func submitQuery() {
        if let first = firstResult { pick(first) }
    }

    private func pick(_ club: Club) {
        model.setClub(club, side: side, slot: slot)
        isOpen = false
    }

    private func pickNone() {
        model.setClub(nil, side: side, slot: slot)
        isOpen = false
    }
}

/// Live preview of both pages from the local server, so the window shows exactly what OBS shows. Drag the divider below it to resize.
struct PreviewStage: View {
    @EnvironmentObject var model: AppModel
    let slot: Int
    var body: some View {
        GeometryReader { geo in
            // Both panes share one height; that height is capped by the width too, so a narrow window scales
            // the pair down instead of clipping the portrait pane at the right edge (Junior, 6 Sep).
            let widthPerHeight: CGFloat = 16.0 / 9 + 9.0 / 16
            let stageH = max(60, min(geo.size.height - 16, (geo.size.width - 16 - 12) / widthPerHeight))
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
