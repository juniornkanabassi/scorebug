// One match slot: a resizable live preview on top, then the match card (home, competition and clock, away) and grouped sections.
// Each section below is its own Equatable view, so a command that only changes one section (e.g. a goal, which
// touches the match card and goals list) does not force SwiftUI to re-diff the others.
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
    @State private var confirmReset = false

    private var match: Match { model.match(slot) }
    private var competition: Competition? { model.library.competitions.first { $0.id == match.competitionId } }
    private var clockStyle: ClockStyle? { model.themeConfig(id: match.themeId ?? competition?.themeId ?? match.competitionId)?.clockStyle }
    private var hasKnockouts: Bool { competition?.hasKnockouts ?? Competition.hasKnockouts(id: match.competitionId) }

    var body: some View {
        let m = match
        VSplitView {
            PreviewStage(slot: slot, baseURL: model.baseURL).frame(minHeight: 180, idealHeight: 300)
            Form {
                // `.equatable()` is what actually makes SwiftUI skip a section's diff when its inputs compare
                // equal; conforming the view to Equatable alone does not opt it into that shortcut.
                MatchCardSection(home: m.home, away: m.away, homeScore: m.homeScore, awayScore: m.awayScore,
                                  competitionId: m.competitionId, phase: m.phase, clock: m.clock, addedMinutes: m.addedMinutes,
                                  aggregate: m.aggregate, clockStyle: clockStyle, hasKnockouts: hasKnockouts, slot: slot, model: model).equatable()
                ClockSection(phase: m.phase, clock: m.clock, addedMinutes: m.addedMinutes, hasKnockouts: hasKnockouts, slot: slot, model: model).equatable()
                GoalsSection(goals: m.goals, homeCode: m.home.code, awayCode: m.away.code, showScorers: m.showScorers,
                              homeColour: m.home.primaryColour, awayColour: m.away.primaryColour, slot: slot, model: model).equatable()
                if hasKnockouts || m.phase == .shootout {
                    ShootoutSection(shootout: m.shootout, phase: m.phase, homeShortName: m.home.shortName, awayShortName: m.away.shortName, slot: slot, model: model).equatable()
                }
            }
            .formStyle(.grouped)
            .frame(maxWidth: 1400)
            .frame(minHeight: 320)
        }
        .navigationTitle(slot == 1 ? "Primary match" : "Secondary match")
        .navigationSubtitle("\(m.home.name) v \(m.away.name)")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Toggle(isOn: Binding(get: { m.visible }, set: { model.apply(.setVisible($0), slot: slot) })) {
                    Label(m.visible ? "Bug shown" : "Bug hidden", systemImage: m.visible ? "eye" : "eye.slash").scaledFont(.body)
                }.toggleStyle(.button).help("Show or hide the bug in OBS")
                Button(role: .destructive) { confirmReset = true } label: { Label("Reset match", systemImage: "arrow.counterclockwise").scaledFont(.body) }
                    .help("Zero the score, clock and shootout; keep the teams")
                    .confirmationDialog("Reset this match?", isPresented: $confirmReset) {
                        Button("Reset match", role: .destructive) { model.apply(.reset, slot: slot) }
                    } message: { Text("Zeroes the score, clock, goals and shootout. The teams and competition stay.") }
            }
        }
    }
}

/// Home/away crest-and-score columns and the centre competition/clock/play controls. Equatable on the values
/// it actually draws, so a command that leaves the match card untouched (a clock nudge, a shootout kick)
/// skips this section's diff and layout entirely.
struct MatchCardSection: View, Equatable {
    let home: TeamEntry
    let away: TeamEntry
    let homeScore: Int
    let awayScore: Int
    let competitionId: String
    let phase: Phase
    let clock: Clock
    let addedMinutes: Int?
    let aggregate: Aggregate?
    let clockStyle: ClockStyle?
    let hasKnockouts: Bool
    let slot: Int
    let model: AppModel

    static func == (l: Self, r: Self) -> Bool {
        l.home == r.home && l.away == r.away && l.homeScore == r.homeScore && l.awayScore == r.awayScore
            && l.competitionId == r.competitionId && l.phase == r.phase && l.clock == r.clock
            && l.addedMinutes == r.addedMinutes && l.aggregate == r.aggregate && l.clockStyle == r.clockStyle
            && l.hasKnockouts == r.hasKnockouts && l.slot == r.slot
    }

    private var competition: Competition? { model.library.competitions.first { $0.id == competitionId } }

    var body: some View {
        Section {
            HStack(alignment: .top, spacing: 0) {
                teamColumn(.home, team: home, score: homeScore)
                Divider().padding(.vertical, 8)
                centreColumn
                Divider().padding(.vertical, 8)
                teamColumn(.away, team: away, score: awayScore)
            }
            .padding(.vertical, 8)
        }
    }

    private func teamColumn(_ side: Side, team: TeamEntry, score: Int) -> some View {
        VStack(spacing: 12) {
            Text(side == .home ? "HOME" : "AWAY").scaledFont(.caption, weight: .semibold).foregroundStyle(.secondary).tracking(1.2)
            CrestView(team: team, size: 72, fitted: true)
            ClubPickerButton(side: side, slot: slot).equatable()
            // A placeholder reads "Home" or "Away" in full; a chosen club shows its broadcast code.
            Text(team.clubId == nil ? team.name : team.code).scaledFont(.caption).monospaced().foregroundStyle(.secondary)
            Text("\(score)").scaledFont(size: 48, weight: .bold, design: .rounded).monospacedDigit().frame(minWidth: 60)
            if let agg = aggregate {
                Text("(\(score + (side == .home ? agg.firstLegHome : agg.firstLegAway)))")
                    .scaledFont(size: 22, design: .rounded).foregroundStyle(.secondary)
            }
            // The plus is the button pressed live, over and over, so it gets the large, unmissable
            // hit target (44x44 pt minimum, per Apple's own floor for a control meant to be hit
            // quickly and often); the minus is only ever an undo, so it stays small and secondary.
            HStack(spacing: 16) {
                Button { model.apply(.goal(side, -1), slot: slot) } label: { Image(systemName: "minus").scaledFont(.callout, weight: .semibold) }
                    .buttonStyle(.bordered).controlSize(.small).frame(width: 28, height: 28)
                    .disabled(score == 0).help("Remove the last \(team.shortName) goal")
                PlusGoalButton(side: side, team: team, phase: phase, slot: slot, model: model).equatable()
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 12)
    }

    private var centreColumn: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                // On a small light plate: a dark broadcast mark (the Premier League lion, drawn
                // dark-on-transparent) would otherwise disappear against this dark card.
                if let c = competition { CompetitionMark(competition: c, size: 30, plate: true) }
                Picker("Competition", selection: Binding(get: { competitionId }, set: { model.setCompetition($0, slot: slot) })) {
                    ForEach(model.library.competitions) { c in Text(c.name).tag(c.id) }
                }.scaledFont(.body).labelsHidden().frame(width: 230)
            }
            Text(competition?.name ?? "Competition").scaledFont(.caption, weight: .semibold).foregroundStyle(.secondary).tracking(1.2).textCase(.uppercase)
            if hasKnockouts {
                Toggle("Second leg of a tie", isOn: Binding(
                    get: { aggregate != nil },
                    set: { on in
                        model.apply(on ? .setAggregate(home: aggregate?.firstLegHome ?? 0, away: aggregate?.firstLegAway ?? 0) : .clearAggregate, slot: slot)
                    }
                )).scaledFont(.caption)
                if let agg = aggregate {
                    HStack(spacing: 4) {
                        Text("1st leg \(home.code)").scaledFont(.caption).foregroundStyle(.secondary)
                        AggregateField(value: agg.firstLegHome) { model.apply(.setAggregate(home: $0, away: agg.firstLegAway), slot: slot) }
                        Text("–").scaledFont(.caption).foregroundStyle(.secondary)
                        AggregateField(value: agg.firstLegAway) { model.apply(.setAggregate(home: agg.firstLegHome, away: $0), slot: slot) }
                        Text(away.code).scaledFont(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            ClockReadout(clock: clock, phase: phase, addedMinutes: addedMinutes, style: clockStyle ?? .runOn)
            // "End half" moved down to sit beside the period pills in the Clock section, where it
            // reads as part of period control rather than a peer of Play/Pause here. This is the only
            // Play/Pause control left (the toolbar's was removed), so it gets the full-width, extra-large
            // treatment for a control pressed live throughout the match.
            Button {
                model.apply(.playPause, slot: slot)
            } label: {
                Label(clock.running ? "Pause" : "Play", systemImage: clock.running ? "pause.fill" : "play.fill")
                    .frame(maxWidth: .infinity).scaledFont(.body, weight: .semibold)
            }
            .buttonStyle(.borderedProminent).controlSize(.extraLarge)
            .keyboardShortcut(.space, modifiers: [])
            .disabled(phase.period == nil).help("Play or pause the clock (Space)")
            // Swapping ends is rare and deliberate, unlike Play/End half which are pressed live and
            // often, so it sits apart and smaller rather than sharing weight with them.
            Button("Swap", systemImage: "arrow.left.arrow.right") { model.apply(.swapTeams, slot: slot) }
                .scaledFont(.body).controlSize(.small).buttonStyle(.plain).foregroundStyle(.secondary)
                .help("Swap home and away")
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 12)
    }

}

/// One side of the aggregate score, editable like `GoalMinuteField`: committed on Return, not on every
/// keystroke, so the field can be emptied while typing a new value instead of snapping back to "0".
private struct AggregateField: View {
    let value: Int
    let onChange: (Int) -> Void
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField("", text: $text)
            .scaledFont(.caption).monospacedDigit().multilineTextAlignment(.center)
            .textFieldStyle(.roundedBorder).frame(width: 32)
            .focused($focused)
            .onAppear { text = "\(value)" }
            .onChange(of: value) { _, new in if !focused { text = "\(new)" } }
            .onSubmit {
                if let n = Int(text) { onChange(max(0, n)) } else { text = "\(value)" }
            }
    }
}

/// The plus button and its scorer popover, alone. `.lazyPopover(isPresented:)` hosts are AppKit-bridged, and this
/// button is pressed (and so re-diffed) on every goal; pulling it out of `MatchCardSection` and gating it on
/// (side, team, phase, slot) means a goal on one side no longer re-attaches the *other* side's popover host,
/// and neither side's re-attaches for a command that only changes the score (score lives in `teamColumn`,
/// not here).
struct PlusGoalButton: View, Equatable {
    let side: Side
    let team: TeamEntry
    let phase: Phase
    let slot: Int
    let model: AppModel
    static func == (l: Self, r: Self) -> Bool { l.side == r.side && l.team == r.team && l.phase == r.phase && l.slot == r.slot }

    /// Goal whose scorer popover should be open on this button, since it just scored it. Cleared as soon as
    /// that goal is no longer in the match (the guard below checks on every read, fetched live from `model`).
    @State private var plusPromptGoalId: UUID?

    var body: some View {
        Button {
            model.apply(.goal(side, 1), slot: slot)
            plusPromptGoalId = model.match(slot).lastGoal?.goalId
        } label: { Image(systemName: "plus").scaledFont(.title2, weight: .bold) }
            .buttonStyle(.borderedProminent).frame(width: 44, height: 44)
            .keyboardShortcut(side == .home ? "h" : "a", modifiers: [.command, .shift])
            .help("Goal for \(team.name) (⇧⌘\(side == .home ? "H" : "A"))")
            .disabled(phase == .shootout).help("Goal for \(team.shortName)")
            .lazyPopover(isPresented: plusPromptBinding) {
                if let id = plusPromptGoalId, let g = model.match(slot).goals.first(where: { $0.id == id }) {
                    GoalPrompt(goal: g, slot: slot, onPick: { plusPromptGoalId = nil })
                }
            }
    }

    /// True only while `plusPromptGoalId` names a goal still in the match on this side; a minus press
    /// or a goal on the other side both make this false on the next render, dismissing the popover.
    private var plusPromptBinding: Binding<Bool> {
        Binding(
            get: { plusPromptGoalId.flatMap { id in model.match(slot).goals.first(where: { $0.id == id }) }?.side == side },
            set: { if !$0 { plusPromptGoalId = nil } }
        )
    }
}

/// Period pills, the clock fields and the stoppage-time quick-picks. Equatable on phase/clock/addedMinutes/
/// clockStyle, so a goal (which does not touch any of those) skips this section entirely.
struct ClockSection: View, Equatable {
    let phase: Phase
    let clock: Clock
    let addedMinutes: Int?
    let hasKnockouts: Bool
    let slot: Int
    let model: AppModel

    static func == (l: Self, r: Self) -> Bool {
        l.phase == r.phase && l.clock == r.clock && l.addedMinutes == r.addedMinutes && l.hasKnockouts == r.hasKnockouts && l.slot == r.slot
    }

    private var periods: [Period] { Period.allCases.filter { hasKnockouts || ($0 != .extraFirst && $0 != .extraSecond) } }

    var body: some View {
        Section("Clock") {
            LabeledContent("Period") {
                HStack(spacing: 8) {
                    ForEach(periods, id: \.self) { p in periodPill(p) }
                    Button("End half") { model.apply(.endPeriod, slot: slot) }
                        .keyboardShortcut("e", modifiers: [.command, .shift]).help("End the current period (⇧⌘E)")
                        .scaledFont(.body).controlSize(.large)
                        .disabled(phase.period == nil)
                }
            }.scaledFont(.body)
            LabeledContent("Clock") {
                HStack(spacing: 10) {
                    Button("−10 s") { model.apply(.adjustClock(deltaSeconds: -10), slot: slot) }
                        .scaledFont(.body).controlSize(.large).buttonStyle(.bordered).disabled(phase.period == nil)
                    ClockFieldsRow(slot: slot)
                    Button("+10 s") { model.apply(.adjustClock(deltaSeconds: 10), slot: slot) }
                        .scaledFont(.body).controlSize(.large).buttonStyle(.bordered).disabled(phase.period == nil)
                }
            }.scaledFont(.body)
            LabeledContent("Stoppage") {
                HStack(spacing: 10) {
                    Button { setAddedMinutes((addedMinutes ?? 0) - 1) } label: { Image(systemName: "minus").scaledFont(.callout, weight: .semibold) }
                        .buttonStyle(.bordered).controlSize(.small).frame(width: 28, height: 28)
                        .disabled((addedMinutes ?? 0) <= 0)
                    Text(addedMinutes.map { "+\($0)" } ?? "Off").scaledFont(.body).monospacedDigit().frame(minWidth: 44)
                    Button { setAddedMinutes((addedMinutes ?? 0) + 1) } label: { Image(systemName: "plus").scaledFont(.callout, weight: .semibold) }
                        .buttonStyle(.bordered).controlSize(.small).frame(width: 28, height: 28)
                        .disabled((addedMinutes ?? 0) >= 15)
                }
            }.scaledFont(.body)
        }
    }

    /// A period already finished (the match phase has moved past it, e.g. half time is past first
    /// half) can't be restarted from its pill; the live period's own pill stays enabled so re-pressing
    /// it is harmless.
    private func setAddedMinutes(_ n: Int) {
        let clamped = max(0, min(15, n))
        model.apply(.setAddedMinutes(clamped == 0 ? nil : clamped), slot: slot)
    }

    private func isPeriodOver(_ period: Period) -> Bool {
        let phases = Phase.allCases
        guard let matchIndex = phases.firstIndex(of: phase), let periodIndex = phases.firstIndex(of: period.phase) else { return false }
        return matchIndex > periodIndex
    }

    /// `.bordered` and `.borderedProminent` are different concrete `ButtonStyle` types, so the live/not-live
    /// choice between them needs two branches rather than one `buttonStyle(_ cond ? a : b)`.
    @ViewBuilder
    private func periodPill(_ p: Period) -> some View {
        let button = Button(p.shortLabel) { model.apply(.startPeriod(p), slot: slot) }
            .scaledFont(.body)
            .controlSize(.large)
            .disabled(isPeriodOver(p))
            .help(p.title)
        if phase.period == p {
            button.buttonStyle(.borderedProminent)
        } else {
            button.buttonStyle(.bordered)
        }
    }
}

/// The goal list and the scorer strap toggle. Equatable on the goal list and the two short names, so a
/// clock edit or a shootout kick (neither touches goals) skips this section.
struct GoalsSection: View, Equatable {
    let goals: [Goal]
    let homeCode: String
    let awayCode: String
    let showScorers: Bool
    let homeColour: String
    let awayColour: String
    let slot: Int
    let model: AppModel

    static func == (l: Self, r: Self) -> Bool {
        l.goals == r.goals && l.homeCode == r.homeCode && l.awayCode == r.awayCode
            && l.showScorers == r.showScorers && l.homeColour == r.homeColour && l.awayColour == r.awayColour && l.slot == r.slot
    }

    var body: some View {
        Section("Goals") {
            if goals.isEmpty {
                Text("No goals yet. Use the plus buttons above; each goal gets a line here for the scorer's name.").scaledFont(.caption).foregroundStyle(.secondary)
            }
            ForEach(goals) { goal in
                HStack(spacing: 10) {
                    Circle().fill(Color(hex: goal.side == .home ? homeColour : awayColour)).frame(width: 8, height: 8)
                    Text(goal.side == .home ? homeCode : awayCode).scaledFont(.body).lineLimit(1).frame(width: 56, alignment: .leading)
                    GoalMinuteField(goal: goal, slot: slot)
                    GoalRow(goal: goal, slot: slot)
                    Spacer()
                    Button { model.apply(.removeGoal(goal.id), slot: slot) } label: { Image(systemName: "minus").scaledFont(.callout, weight: .semibold) }
                        .buttonStyle(.bordered).controlSize(.small).frame(width: 24, height: 24)
                        .help("Remove this goal")
                }
                .scaledFont(.body)
            }
            Button(showScorers ? "Hide scorers" : "Show scorers") {
                model.apply(.setShowScorers(!showScorers), slot: slot)
            }
            .buttonStyle(.borderedProminent).controlSize(.large)
            .disabled(goals.isEmpty)
        }
    }
}

/// A goal's editable minute (`"45+2"` or `"47"`), parsed into `setGoalMinute` on Return. Mirrors the match
/// the moment it opens and on every external change, unless the field is focused.
struct GoalMinuteField: View {
    @EnvironmentObject var model: AppModel
    let goal: Goal
    let slot: Int
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField("", text: $text)
            .scaledFont(.body).monospacedDigit().multilineTextAlignment(.center)
            .textFieldStyle(.roundedBorder).frame(width: 48)
            .focused($focused)
            .onAppear { text = strip(goal.minuteLabel) }
            .onChange(of: goal.minuteLabel) { _, new in if !focused { text = strip(new) } }
            .onSubmit(apply)
    }

    /// `minuteLabel` (`"45+2'"` or `"47'"`) without its trailing apostrophe, for seeding the field.
    private func strip(_ label: String) -> String { label.trimmingCharacters(in: CharacterSet(charactersIn: "'")) }

    /// Keeps only digits and "+" before splitting, so a seeded (or re-typed) trailing apostrophe never
    /// breaks the guard below.
    private func apply() {
        let parts = text.filter { $0.isNumber || $0 == "+" }.split(separator: "+")
        guard let minute = parts.first.flatMap({ Int($0) }) else { text = strip(goal.minuteLabel); return }
        let plus = parts.count > 1 ? Int(parts[1]) : nil
        model.apply(.setGoalMinute(goal.id, minute: minute, plus: plus), slot: slot)
    }
}

/// The penalty shootout tally and kick buttons. Equatable on the shootout, phase and short names, so a
/// goal or clock edit (neither touches these once a shootout is not running) skips this section.
struct ShootoutSection: View, Equatable {
    let shootout: Shootout?
    let phase: Phase
    let homeShortName: String
    let awayShortName: String
    let slot: Int
    let model: AppModel

    static func == (l: Self, r: Self) -> Bool {
        l.shootout == r.shootout && l.phase == r.phase && l.homeShortName == r.homeShortName
            && l.awayShortName == r.awayShortName && l.slot == r.slot
    }

    var body: some View {
        Section("Penalty shootout") {
            if let s = shootout {
                ForEach(Side.allCases, id: \.self) { side in
                    HStack {
                        Text("\(side == .home ? homeShortName : awayShortName)  \(s.tally(side))").frame(width: 120, alignment: .leading)
                        HStack(spacing: 5) {
                            ForEach(s.kicks.filter { $0.side == side }) { k in
                                Circle().fill(k.result == .scored ? Color.green : k.result == .missed ? Color.red : Color.gray).frame(width: 11, height: 11)
                            }
                            if s.nextSide == side && phase == .shootout { Text("to kick").scaledFont(.caption).foregroundStyle(.secondary) }
                        }
                        Spacer()
                    }
                    .scaledFont(.body)
                }
                HStack(spacing: 12) {
                    Button("Scored") { model.apply(.recordKick(nil, .scored), slot: slot) }
                        .buttonStyle(.borderedProminent).controlSize(.extraLarge).tint(.green)
                        .frame(maxWidth: .infinity).disabled(phase != .shootout)
                    Button("Missed") { model.apply(.recordKick(nil, .missed), slot: slot) }
                        .buttonStyle(.borderedProminent).controlSize(.extraLarge).tint(.red)
                        .frame(maxWidth: .infinity).disabled(phase != .shootout)
                }.scaledFont(.body, weight: .semibold)
                Button("Undo") { model.apply(.undoKick, slot: slot) }.scaledFont(.body).disabled(s.kicks.isEmpty)
            } else {
                Button("Start shootout") { model.apply(.startShootout(.home), slot: slot) }
                    .buttonStyle(.borderedProminent).controlSize(.large)
                    .disabled(phase == .preMatch)
            }
        }
    }
}

/// The ticking clock and phase label, alone. This is the only part of a slot that changes four times a second,
/// so it owns its own `Timer.publish` subscription; the section above does not, so a tick here re-renders
/// only this small view, leaving pickers and buttons elsewhere in the tree untouched. Takes the clock's raw
/// fields rather than a whole `Match` (a scratch `Match` is built once per tick to reuse `ClockEngine.display`,
/// the single source of truth also used by overlay.js).
struct ClockReadout: View {
    let clock: Clock
    let phase: Phase
    let addedMinutes: Int?
    let style: ClockStyle
    @State private var tick = Date()
    private let timer = Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()
    private var display: ClockDisplay {
        var m = Match(slot: 0)
        m.clock = clock; m.phase = phase; m.addedMinutes = addedMinutes
        return ClockEngine.display(match: m, style: style, now: tick)
    }

    var body: some View {
        VStack(spacing: 12) {
            Text(display.state ?? display.main).scaledFont(size: 40, weight: .semibold, design: .rounded).monospacedDigit()
            HStack(spacing: 8) {
                if let a = display.added { Text(a).scaledFont(.title3, weight: .semibold).foregroundStyle(.orange) }
                if let c = display.addedCounter { Text(c).scaledFont(.callout).monospacedDigit().foregroundStyle(.secondary) }
            }.frame(height: 20)
            Text(phase.displayTitle).scaledFont(.callout, weight: .medium).pillBadge()
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
        HStack(spacing: 4) {
            TextField("", text: $minutesText)
                .scaledFont(.body).monospacedDigit().multilineTextAlignment(.trailing)
                .textFieldStyle(.plain).frame(width: 36)
                .focused($minutesFocused).onSubmit(applyTypedTime)
            Text(":").scaledFont(.body).foregroundStyle(.secondary)
            TextField("", text: $secondsText)
                .scaledFont(.body).monospacedDigit().multilineTextAlignment(.leading)
                .textFieldStyle(.plain).frame(width: 30)
                .focused($secondsFocused).onSubmit(applyTypedTime)
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.secondary.opacity(0.35)))
        .disabled(match.currentPeriod == nil)
        .onReceive(timer) { tick = $0; resyncIfIdle() }
        .onAppear { resyncIfIdle(force: true) }
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

/// A goal row's scorer control: a button showing the current scorer (with " (og)"/" (pen)" appended) or
/// "Add scorer", that opens `GoalPrompt` from itself. Each row owns its own open state, so removing the goal
/// (minus pressed) removes the row, and its popover, with it.
struct GoalRow: View {
    let goal: Goal
    let slot: Int
    @State private var isOpen = false

    private var label: String {
        guard let scorer = goal.scorer, !scorer.isEmpty else { return "Add scorer" }
        return scorer + (goal.ownGoal ? " (og)" : "") + (goal.penalty ? " (pen)" : "")
    }

    var body: some View {
        Button(label) { isOpen = true }
            .scaledFont(.body)
            .frame(maxWidth: 280, alignment: .leading)
            .lazyPopover(isPresented: $isOpen) {
                GoalPrompt(goal: goal, slot: slot, onPick: { isOpen = false })
            }
    }
}

/// A Home or Away column's club control: a button showing the current team (crest thumbnail, name,
/// chevron) that opens a search popover over the whole library, same pattern as `GoalPrompt`.
/// The plain alphabetical menu of about 165 clubs and nations it replaces was impractical to scroll;
/// this groups results instead and narrows them as the owner types. `model.setClub(_:side:slot:)` stays
/// the only side effect, exactly as the old picker's `onChange` was. Equatable on (side, slot) alone (its
/// only real inputs; everything else it reads live off `model` via its own `@EnvironmentObject`, so a goal
/// on either side, which never changes the team, no longer re-attaches this popover host either.
struct ClubPickerButton: View, Equatable {
    static func == (l: Self, r: Self) -> Bool { l.side == r.side && l.slot == r.slot }
    @EnvironmentObject var model: AppModel
    let side: Side
    let slot: Int
    @State private var query = ""
    @State private var isOpen = false
    @State private var highlighted = 0
    @FocusState private var searchFocused: Bool

    private var match: Match { model.match(slot) }
    private var team: TeamEntry { match.team(side) }

    /// A club is a national team when its `competitionIds` contains "international" (same rule as
    /// `LibraryFilters`'s Clubs/Nations split, kept in sync with it).
    private func isNational(_ club: Club) -> Bool { club.competitionIds.contains("international") }

    /// A club with an empty `competitionIds` is in every competition (the library's own escape hatch).
    /// Competition `other` shows everything. A national team otherwise only shows for `international`;
    /// any other club shows only where its own `competitionIds` names this competition.
    private func isEligible(_ club: Club) -> Bool {
        if club.competitionIds.isEmpty || match.competitionId == "other" { return true }
        if isNational(club) { return match.competitionId == "international" }
        return club.competitionIds.contains(match.competitionId)
    }

    /// Search results split into the two groups the popover shows, each sorted alphabetically.
    private var groups: (inCompetition: [Club], nations: [Club]) {
        let all = model.library.clubs
        let filtered = (query.isEmpty ? all : all.filter { nameMatches($0, in: match.competitionId, query: query) }).filter(isEligible)
        let nations = filtered.filter(isNational).sorted { $0.name < $1.name }
        let inComp = filtered.filter { !isNational($0) }.sorted { $0.name < $1.name }
        return (inComp, nations)
    }

    /// The navigable rows in reading order (in-competition clubs, then national teams), matching how the
    /// groups are drawn top to bottom; "None" sits above these and is not part of arrow navigation.
    private var flatClubs: [Club] { groups.inCompetition + groups.nations }

    var body: some View {
        Button {
            query = ""
            highlighted = 0
            isOpen = true
        } label: {
            HStack(spacing: 8) {
                CrestView(team: team, size: 22, fitted: true)
                Text(team.name).scaledFont(.callout).lineLimit(1)
                Spacer(minLength: 4)
                Image(systemName: "chevron.down").scaledFont(.caption2).foregroundStyle(.secondary)
            }
            // Fixed, not maxWidth: a short name (e.g. "Inter") must not leave this button narrower than the
            // other side's, which is what threw the two pickers out of alignment (Junior's screenshot).
            .frame(width: 220)
        }
        .buttonStyle(.bordered)
        .lazyPopover(isPresented: $isOpen) {
            let clubs = flatClubs
            VStack(alignment: .leading, spacing: 0) {
                TextField("Search club or nation", text: $query)
                    .scaledFont(.body)
                    .textFieldStyle(.roundedBorder)
                    .focused($searchFocused)
                    .padding(8)
                    .onSubmit(submitQuery)
                Divider()
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            noneRow
                            Divider().padding(.vertical, 2)
                            groupSection("In this competition", groups.inCompetition, startIndex: 0)
                            groupSection("National teams", groups.nations, startIndex: groups.inCompetition.count)
                            if clubs.isEmpty {
                                Text("No match.").scaledFont(.caption).foregroundStyle(.secondary).padding(8)
                            }
                        }
                    }.frame(maxHeight: 320)
                        .onChange(of: highlighted) { _, new in proxy.scrollTo(new, anchor: .center) }
                }
            }
            .frame(width: 280)
            .onAppear { searchFocused = true }
            .onChange(of: query) { _, _ in highlighted = 0 }
            .onKeyPress(.upArrow) { highlighted = max(0, highlighted - 1); return .handled }
            .onKeyPress(.downArrow) { highlighted = min(max(0, clubs.count - 1), highlighted + 1); return .handled }
            .onKeyPress(.escape) { isOpen = false; return .handled }
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
    private func groupSection(_ title: String, _ clubs: [Club], startIndex: Int) -> some View {
        if !clubs.isEmpty {
            Text(title).scaledFont(.caption, weight: .semibold).foregroundStyle(.secondary)
                .padding(.horizontal, 8).padding(.top, 6).padding(.bottom, 2)
            ForEach(Array(clubs.enumerated()), id: \.element.id) { i, club in clubRow(club, index: startIndex + i) }
        }
    }

    private func clubRow(_ club: Club, index: Int) -> some View {
        let entry = club.entry(for: match.competitionId)
        return Button { pick(club) } label: {
            HStack(spacing: 8) {
                CrestView(team: entry, size: 20, fitted: true)
                Text(entry.name).scaledFont(.body)
                Spacer()
                Text(entry.code).scaledFont(.caption).monospaced().foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, 4).padding(.horizontal, 8)
        .background(index == highlighted ? Color.accentColor.opacity(0.2) : .clear)
        .id(index)
    }

    private func submitQuery() {
        if flatClubs.indices.contains(highlighted) { pick(flatClubs[highlighted]) }
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

/// Live preview of both pages from the local server, so the window shows exactly what OBS shows. Drag the
/// divider below it to resize. Takes the base URL directly rather than the whole model, so a command on
/// either slot never invalidates this view (its `updateNSView` already no-ops when nothing changed).
struct PreviewStage: View {
    let slot: Int
    let baseURL: String
    var body: some View {
        GeometryReader { geo in
            // Both panes share one height; that height is capped by the width too, so a narrow window scales
            // the pair down instead of clipping the portrait pane at the right edge (Junior, 6 Sep).
            let widthPerHeight: CGFloat = 16.0 / 9 + 9.0 / 16
            let stageH = max(60, min(geo.size.height - 16, (geo.size.width - 16 - 12) / widthPerHeight))
            let hW = stageH * 16 / 9, vW = stageH * 9 / 16
            HStack(spacing: 12) {
                Spacer(minLength: 0)
                // `?preview=1` is the only difference from what OBS loads: it is what tells overlay.js this
                // page may show the preview backdrop, which OBS's own browser source (no query) never sees.
                OverlayWebView(url: URL(string: "\(baseURL)/overlay/h/\(slot)?preview=1")!, scale: hW / 1920, size: CGSize(width: 1920, height: 1080))
                    .frame(width: hW, height: stageH).background(.black).clipShape(RoundedRectangle(cornerRadius: 6))
                OverlayWebView(url: URL(string: "\(baseURL)/overlay/v/\(slot)?preview=1")!, scale: vW / 1080, size: CGSize(width: 1080, height: 1920))
                    .frame(width: vW, height: stageH).background(.black).clipShape(RoundedRectangle(cornerRadius: 6))
                Spacer(minLength: 0)
            }.padding(8)
        }
        .frame(maxWidth: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
