// One match slot: a resizable live preview on top, then a control panel of full-width rounded blocks below.
// Each block below is its own Equatable view, so a command that only changes one block (e.g. a goal, which
// touches the match card and goals list) does not force SwiftUI to re-diff the others.
import SwiftUI
import ScorebugCore

/// Short pill label for the period row, matching Uno Overlays' "Match Time" tab wording;
/// `.title` (from ScorebugCore) stays the tooltip's full name.
extension Period {
    var shortLabel: String {
        switch self {
        case .firstHalf: return "1st"
        case .secondHalf: return "2nd"
        case .extraFirst: return "ET1"
        case .extraSecond: return "ET2"
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
            GeometryReader { geo in ScrollView {
                VStack(spacing: 16) {
                    // `.equatable()` is what actually makes SwiftUI skip a block's diff when its inputs compare
                    // equal; conforming the view to Equatable alone does not opt it into that shortcut.
                    MatchCardSection(home: m.home, away: m.away, homeScore: m.homeScore, awayScore: m.awayScore,
                                      competitionId: m.competitionId, phase: m.phase, aggregate: m.aggregate,
                                      hasKnockouts: hasKnockouts, slot: slot, model: model).equatable()
                    ClockSection(phase: m.phase, clock: m.clock, addedMinutes: m.addedMinutes, clockStyle: clockStyle,
                                  hasKnockouts: hasKnockouts, slot: slot, model: model).equatable()
                    StoppageSection(addedMinutes: m.addedMinutes, slot: slot, model: model).equatable()
                    GoalsSection(goals: m.goals, homeCode: m.home.code, awayCode: m.away.code, showScorers: m.showScorers,
                                  homeColour: m.home.primaryColour, awayColour: m.away.primaryColour, slot: slot, model: model).equatable()
                    if hasKnockouts || m.phase == .shootout {
                        ShootoutSection(shootout: m.shootout, phase: m.phase, homeShortName: m.home.shortName, awayShortName: m.away.shortName, slot: slot, model: model).equatable()
                    }
                }
                .padding(16)
                // Capped and centred rather than stretched edge to edge, so a wide window (1900 pt) does not
                // leave every block absurdly wide with dead space either side of its actual controls.
                .frame(maxWidth: 1100)
                .frame(width: geo.size.width)
            } }
            // The reader keeps this pane's ideal width tiny: a split view pane's ideal width becomes the
            // detail column's minimum, which pushed the sidebar off the window at 1180 pt.
            .frame(minHeight: 360)
        }
        .navigationTitle(slot == 1 ? "Primary match" : "Secondary match")
        .navigationSubtitle("\(m.home.name) v \(m.away.name)")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Toggle(isOn: Binding(get: { m.visible }, set: { model.apply(.setVisible($0), slot: slot) })) {
                    Label(m.visible ? "Bug shown" : "Bug hidden", systemImage: m.visible ? "eye" : "eye.slash").scaledFont(.body)
                }.toggleStyle(.button).help("Show or hide the bug in OBS")
                // Icon-only, not label-and-icon: at a narrow window the toolbar otherwise crowds the navigation
                // title (Junior's screenshot showed it truncated to "Pr"). The help tooltip carries the text.
                Button(role: .destructive) { confirmReset = true } label: { Label("Reset match", systemImage: "arrow.counterclockwise").scaledFont(.body) }
                    .labelStyle(.iconOnly)
                    .help("Reset match: zero the score, clock and shootout; keep the teams")
                    .confirmationDialog("Reset this match?", isPresented: $confirmReset) {
                        Button("Reset match", role: .destructive) { model.apply(.reset, slot: slot) }
                    } message: { Text("Zeroes the score, clock, goals and shootout. The teams and competition stay.") }
            }
        }
    }
}

/// A rounded, full-width block: a small uppercase caption (with an optional trailing accessory, e.g. the
/// Goals block's "Show scorers" switch) over its content. Replaces `Form`'s `Section`, which read far too
/// small at Junior's window scale and buried controls in a cramped list.
private struct Panel<Content: View, Accessory: View>: View {
    let caption: String
    let accessory: Accessory
    let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(caption).scaledFont(.caption, weight: .semibold).foregroundStyle(.secondary).tracking(1.2).textCase(.uppercase)
                Spacer()
                accessory
            }
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
    }
}

extension Panel where Accessory == EmptyView {
    init(_ caption: String, @ViewBuilder content: () -> Content) {
        self.caption = caption; self.accessory = EmptyView(); self.content = content()
    }
}

extension Panel {
    init(_ caption: String, @ViewBuilder accessory: () -> Accessory, @ViewBuilder content: () -> Content) {
        self.caption = caption; self.accessory = accessory(); self.content = content()
    }
}

/// Home/away crest-and-score columns and the centre competition/aggregate controls. Equatable on the values
/// it actually draws, so a command that leaves the match card untouched (a clock nudge, a shootout kick)
/// skips this block's diff and layout entirely.
struct MatchCardSection: View, Equatable {
    let home: TeamEntry
    let away: TeamEntry
    let homeScore: Int
    let awayScore: Int
    let competitionId: String
    let phase: Phase
    let aggregate: Aggregate?
    let hasKnockouts: Bool
    let slot: Int
    let model: AppModel

    static func == (l: Self, r: Self) -> Bool {
        l.home == r.home && l.away == r.away && l.homeScore == r.homeScore && l.awayScore == r.awayScore
            && l.competitionId == r.competitionId && l.phase == r.phase && l.aggregate == r.aggregate
            && l.hasKnockouts == r.hasKnockouts && l.slot == r.slot
    }

    private var competition: Competition? { model.library.competitions.first { $0.id == competitionId } }

    var body: some View {
        Panel("Match") {
            HStack(alignment: .top, spacing: 0) {
                teamColumn(.home, team: home, score: homeScore)
                Divider().padding(.vertical, 8)
                centreColumn
                Divider().padding(.vertical, 8)
                teamColumn(.away, team: away, score: awayScore)
            }
        }
    }

    private func teamColumn(_ side: Side, team: TeamEntry, score: Int) -> some View {
        VStack(spacing: 12) {
            Text(side == .home ? "HOME" : "AWAY").scaledFont(.caption, weight: .semibold).foregroundStyle(.secondary).tracking(1.2)
            CrestView(team: team, size: 72, fitted: true)
            ClubPickerButton(side: side, slot: slot).equatable()
            // A placeholder reads "Home" or "Away" in full; a chosen club shows its broadcast code.
            Text(team.clubId == nil ? team.name : team.code).scaledFont(.caption).monospaced().foregroundStyle(.secondary)
            Text("\(score)").scaledFont(size: 56, weight: .bold, design: .rounded).monospacedDigit().frame(minWidth: 70)
            if let agg = aggregate {
                Text("(\(score + (side == .home ? agg.firstLegHome : agg.firstLegAway)))")
                    .scaledFont(size: 22, design: .rounded).foregroundStyle(.secondary)
            }
            // Both buttons are now the same large size: the plus is pressed live, over and over, and the
            // minus undoes a misclick just as urgently, so a 28 pt target beside a 56 pt one (Junior's UX
            // critic) is gone.
            HStack(spacing: 16) {
                Button { model.apply(.goal(side, -1), slot: slot) } label: {
                    Image(systemName: "minus").scaledFont(.title, weight: .bold).frame(width: 56, height: 56)
                }
                .buttonStyle(.bordered).controlSize(.extraLarge).scaledControl(56, square: true)
                .disabled(score == 0)
                .help(score == 0 ? "No \(team.shortName) goals to remove" : "Remove the last \(team.shortName) goal")
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
            Spacer(minLength: 0)
            // Swapping ends is rare and deliberate, so it stays small and secondary rather than sharing
            // weight with the primary controls now living in the Clock block.
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
            .onChange(of: focused) { _, now in if !now { text = "\(value)" } }
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
        } label: { Image(systemName: "plus").scaledFont(.title, weight: .bold).frame(width: 56, height: 56) }
            .buttonStyle(.borderedProminent).controlSize(.extraLarge).scaledControl(56, square: true)
            .keyboardShortcut(side == .home ? "h" : "a", modifiers: [.command, .shift])
            .disabled(phase == .shootout).help("Goal for \(team.name) (⇧⌘\(side == .home ? "H" : "A"))")
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

/// The clock readout, the editable minutes/seconds, the play/reset/nudge/end-half row and the period pills.
/// Equatable on phase/clock/addedMinutes/clockStyle, so a goal (which does not touch any of those) skips
/// this block entirely.
struct ClockSection: View, Equatable {
    let phase: Phase
    let clock: Clock
    let addedMinutes: Int?
    let clockStyle: ClockStyle?
    let hasKnockouts: Bool
    let slot: Int
    let model: AppModel
    @State private var confirmResetClock = false
    // Owned here, not by ClockReadout and ClockFieldsRow individually: both used to run their own quarter-second
    // Timer.publish side by side for the same purpose, so one timer now feeds both through `tick`.
    @State private var tick = Date()
    private let timer = Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()

    static func == (l: Self, r: Self) -> Bool {
        l.phase == r.phase && l.clock == r.clock && l.addedMinutes == r.addedMinutes
            && l.clockStyle == r.clockStyle && l.hasKnockouts == r.hasKnockouts && l.slot == r.slot
    }

    private var periods: [Period] { Period.allCases.filter { hasKnockouts || ($0 != .extraFirst && $0 != .extraSecond) } }

    var body: some View {
        Panel("Clock") {
            VStack(spacing: 16) {
                HStack(spacing: 24) {
                    ClockReadout(clock: clock, phase: phase, addedMinutes: addedMinutes, style: clockStyle ?? .runOn, tick: tick)
                    ClockFieldsRow(slot: slot, tick: tick)
                    Spacer()
                }
                HStack(spacing: 10) {
                    playPauseButton
                    resetClockButton
                    Button { model.apply(.adjustClock(deltaSeconds: -10), slot: slot) } label: {
                        Text("−10 s").frame(maxWidth: .infinity, minHeight: 44)
                    }.scaledControl().disabled(phase.period == nil)
                    Button { model.apply(.adjustClock(deltaSeconds: 10), slot: slot) } label: {
                        Text("+10 s").frame(maxWidth: .infinity, minHeight: 44)
                    }.scaledControl().disabled(phase.period == nil)
                    Button {
                        model.apply(.endPeriod, slot: slot)
                    } label: {
                        Text("End half").frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .scaledControl().disabled(phase.period == nil)
                    .keyboardShortcut("e", modifiers: [.command, .shift]).help("End the current period (⇧⌘E)")
                }
                .buttonStyle(.bordered).controlSize(.extraLarge).scaledFont(.body, weight: .semibold)
                // Always enabled, even for a period already past: a misclick into the wrong half is undone by
                // pressing the right pill, which is simpler than a disabled state that needs its own escape hatch.
                HStack(spacing: 8) { ForEach(periods, id: \.self) { p in periodPill(p) } }
            }
        }
        .onReceive(timer) { tick = $0 }
    }

    private var playPauseButton: some View {
        Button {
            model.apply(.playPause, slot: slot)
        } label: {
            Label(clock.running ? "Pause" : "Play", systemImage: clock.running ? "pause.fill" : "play.fill")
                .frame(maxWidth: .infinity, minHeight: 44)
                // A plain `.tint` on a borderedProminent button can read as grey once the window is no longer
                // key (the streamer has OBS focused), so the green while running is also painted as our own
                // background layer, which stays visible regardless of key-window state.
                .background(clock.running ? Color.green.opacity(0.35) : .clear, in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.borderedProminent).tint(clock.running ? .green : .accentColor).scaledControl()
        .keyboardShortcut(.space, modifiers: [])
        .disabled(phase.period == nil).help("Play or pause the clock (Space)")
    }

    private var resetClockButton: some View {
        Button {
            if clock.running { confirmResetClock = true } else { model.apply(.setClock(seconds: 0), slot: slot) }
        } label: {
            Text("Reset clock").frame(maxWidth: .infinity, minHeight: 44)
        }
        .scaledControl()
        .disabled(phase.period == nil)
        .confirmationDialog("Reset the clock to zero?", isPresented: $confirmResetClock) {
            Button("Reset clock", role: .destructive) { model.apply(.setClock(seconds: 0), slot: slot) }
        }
    }

    @ViewBuilder
    private func periodPill(_ p: Period) -> some View {
        let button = Button {
            model.apply(.startPeriod(p), slot: slot)
        } label: {
            Text(p.shortLabel).scaledFont(.body, weight: .semibold).frame(maxWidth: .infinity, minHeight: 44)
        }
        .controlSize(.extraLarge).scaledControl().help(p.title)
        if phase.period == p {
            // Borders read clearly in a key window's own accent colour, but a borderedProminent fill can look
            // washed out once the window is not key (the streamer has OBS focused); the stroke is our own
            // layer, so the live pill still reads live either way.
            button.buttonStyle(.borderedProminent)
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.tint, lineWidth: 2))
        } else {
            button.buttonStyle(.bordered)
        }
    }
}

/// The stoppage-time (added-time) control, alone: minus, the value, plus, and a "Show on bug" switch that
/// hides it from the overlay (`setAddedMinutes(nil)`) without losing the number, restoring the last
/// non-zero value when switched back on.
struct StoppageSection: View, Equatable {
    let addedMinutes: Int?
    let slot: Int
    let model: AppModel
    @State private var lastValue = 1

    static func == (l: Self, r: Self) -> Bool { l.addedMinutes == r.addedMinutes && l.slot == r.slot }

    /// Remembers the last non-zero value per slot, so switching slots (or reopening the app) does not forget
    /// a "+3" that was switched off with "Show on bug".
    private var defaultsKey: String { "lastAdded\(slot)" }

    var body: some View {
        Panel("Stoppage") {
            HStack(spacing: 20) {
                Button { adjust(-1) } label: { Image(systemName: "minus").scaledFont(.title2, weight: .semibold).frame(minHeight: 44) }
                    .buttonStyle(.bordered).controlSize(.extraLarge).scaledControl()
                    .disabled((addedMinutes ?? 0) <= 0)
                HStack(spacing: 12) {
                    Text(addedMinutes.map { "+\($0)" } ?? "Off").scaledFont(size: 28, weight: .bold, design: .rounded).monospacedDigit().frame(minWidth: 80)
                    // Beside the value it governs, not off at the far end of the row.
                    Toggle("Show on bug", isOn: showBinding).toggleStyle(.switch).scaledFont(.body)
                }
                Button { adjust(1) } label: { Image(systemName: "plus").scaledFont(.title2, weight: .semibold).frame(minHeight: 44) }
                    .buttonStyle(.bordered).controlSize(.extraLarge).scaledControl()
                    .disabled((addedMinutes ?? 0) >= 15)
                Spacer()
            }
        }
        .onAppear {
            if let v = addedMinutes, v > 0 { lastValue = v }
            else { let saved = UserDefaults.standard.integer(forKey: defaultsKey); if saved > 0 { lastValue = saved } }
        }
        .onChange(of: addedMinutes) { _, new in
            if let v = new, v > 0 { lastValue = v; UserDefaults.standard.set(v, forKey: defaultsKey) }
        }
    }

    private var showBinding: Binding<Bool> {
        Binding(get: { addedMinutes != nil }, set: { on in model.apply(.setAddedMinutes(on ? lastValue : nil), slot: slot) })
    }

    private func adjust(_ delta: Int) {
        let clamped = max(0, min(15, (addedMinutes ?? 0) + delta))
        model.apply(.setAddedMinutes(clamped == 0 ? nil : clamped), slot: slot)
    }
}

/// The goal list and the scorer strap toggle. Equatable on the goal list and the two short names, so a
/// clock edit or a shootout kick (neither touches goals) skips this block.
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
        Panel("Goals", accessory: {
            Toggle("Show scorers", isOn: Binding(get: { showScorers }, set: { model.apply(.setShowScorers($0), slot: slot) }))
                .toggleStyle(.switch).scaledFont(.caption).disabled(goals.isEmpty)
                .help(goals.isEmpty ? "No goals yet to show scorers for" : "Show scorer names on the bug")
        }) {
            VStack(alignment: .leading, spacing: 4) {
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
                        Button { model.apply(.removeGoal(goal.id), slot: slot) } label: {
                            Image(systemName: "minus").scaledFont(.callout, weight: .semibold).frame(width: 32, height: 32)
                        }
                        .buttonStyle(.bordered).controlSize(.small).scaledControl(32, square: true)
                        .help("Remove this goal")
                    }
                    .frame(height: 44)
                }
            }
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
            .scaledFont(size: 18).monospacedDigit().multilineTextAlignment(.center)
            .textFieldStyle(.roundedBorder).frame(width: 52)
            .focused($focused)
            .onAppear { text = strip(goal.minuteLabel) }
            .onChange(of: goal.minuteLabel) { _, new in if !focused { text = strip(new) } }
            .onChange(of: focused) { _, now in if !now { text = strip(goal.minuteLabel) } }
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

/// The penalty shootout block: one-tap "scored"/"missed" buttons for each side, an editable row of kick
/// cells per side, undo, and the start button. Equatable on the shootout, phase and short names, so a goal
/// or clock edit (neither touches these once a shootout is not running) skips this block.
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

    private var beforeKickoff: Bool { phase == .preMatch }

    var body: some View {
        Panel("Shootout") {
            VStack(alignment: .leading, spacing: 16) {
                if beforeKickoff {
                    Text("Available after kick-off").scaledFont(.caption).foregroundStyle(.secondary)
                }
                Grid(horizontalSpacing: 12, verticalSpacing: 12) {
                    GridRow {
                        quickButton("\(homeShortName) scored", side: .home, result: .scored, tint: .green)
                        quickButton("\(homeShortName) missed", side: .home, result: .missed, tint: .red)
                    }
                    GridRow {
                        quickButton("\(awayShortName) scored", side: .away, result: .scored, tint: .green)
                        quickButton("\(awayShortName) missed", side: .away, result: .missed, tint: .red)
                    }
                }
                if let s = shootout {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(Side.allCases, id: \.self) { side in kickRow(side, s) }
                    }
                    Button {
                        model.apply(.undoKick, slot: slot)
                    } label: {
                        Text("Undo last").frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.bordered).controlSize(.extraLarge).scaledControl().disabled(s.kicks.isEmpty)
                } else {
                    Button {
                        model.apply(.startShootout(.home), slot: slot)
                    } label: {
                        Text("Start shootout").frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent).controlSize(.extraLarge).scaledControl()
                    .disabled(beforeKickoff)
                }
            }
        }
    }

    @ViewBuilder
    private func quickButton(_ title: String, side: Side, result: KickResult, tint: Color) -> some View {
        Button {
            model.apply(.recordKick(side, result), slot: slot)
        } label: {
            Text(title).frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.borderedProminent).controlSize(.extraLarge).tint(tint).scaledControl()
        .disabled(phase != .shootout)
    }

    /// This side's kicks in order, each a round cell that cycles scored → missed → removed on a press
    /// (`setKick` scored to missed, `removeKick` missed to gone). The cell itself stays a small 28 pt circle,
    /// so the row stays compact; the button's hit target is padded out to 44 pt around it.
    private func kickRow(_ side: Side, _ s: Shootout) -> some View {
        let sideKicks = s.kicks.filter { $0.side == side }
        return HStack(spacing: 8) {
            Text(side == .home ? homeShortName : awayShortName).scaledFont(.body).frame(width: 100, alignment: .leading)
            ForEach(Array(sideKicks.enumerated()), id: \.offset) { i, kick in
                Button { cycle(side: side, index: i, current: kick.result) } label: {
                    Circle().fill(colour(kick.result)).frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
                .help(helpText(for: kick.result))
            }
            if s.nextSide == side && phase == .shootout { Text("to kick").scaledFont(.caption).foregroundStyle(.secondary) }
        }
    }

    private func colour(_ r: KickResult) -> Color { r == .scored ? .green : r == .missed ? .red : .gray }

    private func helpText(for result: KickResult) -> String {
        switch result {
        case .scored: return "Scored, press to mark missed"
        case .missed: return "Missed, press to remove"
        case .pending: return "Pending"
        }
    }

    private func cycle(side: Side, index: Int, current: KickResult) {
        switch current {
        case .scored: model.apply(.setKick(side, index: index, result: .missed), slot: slot)
        case .missed: model.apply(.removeKick(side, index: index), slot: slot)
        case .pending: break
        }
    }
}

/// The ticking clock and phase label, alone. Takes the clock's raw fields rather than a whole `Match` (a
/// scratch `Match` is built once per tick to reuse `ClockEngine.display`, the single source of truth also
/// used by overlay.js), and `tick` from `ClockSection`'s own quarter-second timer, shared with
/// `ClockFieldsRow` rather than each running its own subscription for the same purpose.
struct ClockReadout: View {
    let clock: Clock
    let phase: Phase
    let addedMinutes: Int?
    let style: ClockStyle
    let tick: Date
    private var display: ClockDisplay {
        var m = Match(slot: 0)
        m.clock = clock; m.phase = phase; m.addedMinutes = addedMinutes
        return ClockEngine.display(match: m, style: style, now: tick)
    }

    var body: some View {
        VStack(spacing: 12) {
            Text(display.state ?? display.main).scaledFont(size: 48, weight: .semibold, design: .rounded).monospacedDigit()
            HStack(spacing: 8) {
                if let a = display.added { Text(a).scaledFont(.title3, weight: .semibold).foregroundStyle(.orange) }
                if let c = display.addedCounter { Text(c).scaledFont(.callout).monospacedDigit().foregroundStyle(.secondary) }
            }.frame(height: 20)
            Text(phase.displayTitle).scaledFont(.callout, weight: .medium).pillBadge()
        }
    }
}

/// The editable minutes/seconds pair in the Clock block: shows the cumulative on-screen time (period
/// base + elapsed, the same value `ClockReadout` derives via `Clock.elapsed(at:)`), flanked by round −/+
/// buttons that nudge the clock directly. `tick` comes from `ClockSection`'s shared quarter-second timer.
/// Typing a value only takes effect on Return (`onSubmit`), and the text mirrors re-sync on every tick
/// *unless* a field is focused, so a running clock never overwrites what the owner is mid-typing.
struct ClockFieldsRow: View {
    @EnvironmentObject var model: AppModel
    let slot: Int
    let tick: Date
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
                .scaledFont(size: 20).monospacedDigit().multilineTextAlignment(.trailing)
                .textFieldStyle(.plain).frame(width: 46)
                .focused($minutesFocused).onSubmit(applyTypedTime)
            Text(":").scaledFont(size: 20).foregroundStyle(.secondary)
            TextField("", text: $secondsText)
                .scaledFont(size: 20).monospacedDigit().multilineTextAlignment(.leading)
                .textFieldStyle(.plain).frame(width: 38)
                .focused($secondsFocused).onSubmit(applyTypedTime)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.secondary.opacity(0.35)))
        .disabled(match.currentPeriod == nil)
        .onChange(of: tick) { _, _ in resyncIfIdle() }
        .onAppear { resyncIfIdle(force: true) }
    }

    /// Re-reads the match clock into the text fields, unless the owner is mid-edit in either of them.
    private func resyncIfIdle(force: Bool = false) {
        guard force || (!minutesFocused && !secondsFocused) else { return }
        let s = cumulativeSeconds
        minutesText = "\(s / 60)"
        secondsText = String(format: "%02d", s % 60)
    }

    /// The typed minutes/seconds are the on-screen cumulative time, so the period's own base is subtracted
    /// back out before sending `.setClock`.
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
            .scaledFont(.body).controlSize(.large)
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
            highlighted = flatClubs.firstIndex { $0.id == team.clubId } ?? 0
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
            .keyNavigation(count: clubs.count, highlighted: $highlighted, onPick: submitQuery, onClose: { isOpen = false })
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
