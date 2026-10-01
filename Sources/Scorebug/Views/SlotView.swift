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
        case .preMatch: return "Before kick-off"; case .firstHalf: return "First half"; case .halfTime: return "Half-time"
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
    @AppStorage("showPreview") private var showPreview = true

    private var match: Match { model.match(slot) }
    private var competition: Competition? { model.library.competitions.first { $0.id == match.competitionId } }
    private var clockStyle: ClockStyle? { model.themeConfig(id: match.themeId ?? competition?.themeId ?? match.competitionId)?.clockStyle }
    private var hasKnockouts: Bool { competition?.hasKnockouts ?? Competition.hasKnockouts(id: match.competitionId) }

    var body: some View {
        let m = match
        VSplitView {
            if showPreview {
                PreviewStage(slot: slot, baseURL: model.baseURL, visible: m.visible).frame(minHeight: 110, idealHeight: 160)
            }
            // Live bar and controls share the lower pane, so the live bar is never a draggable split pane of its own,
            // and its zero ideal width keeps it out of the detail column's minimum (rule 22).
            VStack(spacing: 0) {
            LiveMatchBar(home: m.home, away: m.away, homeScore: m.homeScore, awayScore: m.awayScore,
                         phase: m.phase, clock: m.clock, addedMinutes: m.addedMinutes, clockStyle: clockStyle,
                         aggregate: m.aggregate, slot: slot, model: model, zoomGeneration: ScaledFonts.generation).equatable()
                .frame(minWidth: 0, idealWidth: 0, maxWidth: .infinity)
            GeometryReader { geo in ScrollView {
                VStack(spacing: 16) {
                    // `.equatable()` is what actually makes SwiftUI skip a block's diff when its inputs compare
                    // equal; conforming the view to Equatable alone does not opt it into that shortcut. None of
                    // these blocks' own fields mention zoom, so `zoomGeneration` (read fresh here, since this
                    // body itself is not equatable-gated) is threaded through purely so a zoom change is seen
                    // as a change too, not swallowed by the same shortcut.
                    let zoomGeneration = ScaledFonts.generation
                    if m.phase == .preMatch {
                        MatchSetupSection(home: m.home, away: m.away, competitionId: m.competitionId, phase: m.phase,
                                          aggregate: m.aggregate, hasKnockouts: hasKnockouts, slot: slot, model: model,
                                          zoomGeneration: zoomGeneration).equatable()
                    }
                    ClockSection(phase: m.phase, clock: m.clock,
                                  hasKnockouts: hasKnockouts, slot: slot, model: model, zoomGeneration: zoomGeneration).equatable()
                    StoppageSection(addedMinutes: m.addedMinutes, slot: slot, model: model, zoomGeneration: zoomGeneration).equatable()
                    GoalsSection(match: m, goals: m.goals, homeCode: m.home.code, awayCode: m.away.code, showScorers: m.showScorers,
                                  homeColour: m.home.primaryColour, awayColour: m.away.primaryColour, slot: slot, model: model, zoomGeneration: zoomGeneration).equatable()
                    if m.phase != .preMatch {
                        MatchSetupSection(home: m.home, away: m.away, competitionId: m.competitionId, phase: m.phase,
                                          aggregate: m.aggregate, hasKnockouts: hasKnockouts, slot: slot, model: model,
                                          zoomGeneration: zoomGeneration).equatable()
                    }
                    if hasKnockouts || m.phase == .shootout {
                        ShootoutSection(shootout: m.shootout, phase: m.phase, homeShortName: m.home.shortName, awayShortName: m.away.shortName, slot: slot, model: model, zoomGeneration: zoomGeneration).equatable()
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
            .frame(minHeight: 200)
            .overlay(alignment: .top) { Divider() }
            }
        }
        .navigationTitle(slot == 1 ? "Primary match" : "Secondary match")
        .navigationSubtitle("\(m.home.name) v \(m.away.name)")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button { model.apply(.setVisible(!m.visible), slot: slot) } label: {
                    Label(m.visible ? "On air" : "Off air", systemImage: m.visible ? "dot.radiowaves.left.and.right" : "eye.slash")
                        .symbolVariant(.fill).symbolRenderingMode(.hierarchical)
                        .foregroundStyle(m.visible ? .green : .secondary).scaledFont(.body)
                }.labelStyle(.titleAndIcon).accessibilityLabel(m.visible ? "Bug on air" : "Bug off air")
                    .help("Show or hide the bug in OBS")
                Toggle("Preview", systemImage: "rectangle.on.rectangle", isOn: $showPreview)
                    .toggleStyle(.button).labelStyle(.titleAndIcon).help("Show or hide the preview strip")
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

/// Fixed live controls between the preview and scrollable panels. The clock readout owns its own tick so
/// the enclosing bar stays equatable and goal/clock commands only update the values they affect.
struct LiveMatchBar: View, Equatable {
    let home: TeamEntry
    let away: TeamEntry
    let homeScore: Int
    let awayScore: Int
    let phase: Phase
    let clock: Clock
    let addedMinutes: Int?
    let clockStyle: ClockStyle?
    let aggregate: Aggregate?
    let slot: Int
    let model: AppModel
    let zoomGeneration: Int

    static func == (l: Self, r: Self) -> Bool {
        l.home == r.home && l.away == r.away && l.homeScore == r.homeScore && l.awayScore == r.awayScore
            && l.phase == r.phase && l.clock == r.clock && l.addedMinutes == r.addedMinutes
            && l.clockStyle == r.clockStyle && l.aggregate == r.aggregate && l.slot == r.slot && l.zoomGeneration == r.zoomGeneration
    }

    var body: some View {
        HStack(spacing: 8) {
            teamColumn(.home, team: home, score: homeScore)
            VStack(spacing: 10) {
                TimelineView(.periodic(from: .now, by: clock.running ? 1.0 : 3600)) { context in
                    ClockReadout(clock: clock, phase: phase, addedMinutes: addedMinutes,
                                 style: clockStyle ?? .runOn, tick: context.date)
                }
                Button { model.apply(.playPause, slot: slot) } label: {
                    Label(clock.running ? "Pause" : "Play", systemImage: clock.running ? "pause.fill" : "play.fill")
                        .frame(minWidth: 180).scaledControl(56)
                        .background(clock.running ? Color.green.opacity(0.35) : .clear, in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.borderedProminent).controlSize(.extraLarge).tint(clock.running ? .green : .accentColor)
                .keyboardShortcut(.space, modifiers: []).disabled(phase.period == nil).help("Play or pause the clock (Space)")
                if phase == .preMatch {
                    Text("Choose 1st to kick off").scaledFont(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(minWidth: 180)
            teamColumn(.away, team: away, score: awayScore)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(.bar)
    }

    private func teamColumn(_ side: Side, team: TeamEntry, score: Int) -> some View {
        let goalButtonSide = max(44, 56) * ScaledFonts.scale
        return VStack(spacing: 8) {
            HStack(spacing: 8) {
                CrestView(team: team, size: 40, fitted: true)
                Text(team.shortName).scaledFont(.headline).lineLimit(1)
            }
            HStack(spacing: 8) {
                VStack(spacing: 0) {
                    Text("\(score)").scaledFont(size: 56, weight: .bold, design: .rounded).monospacedDigit().frame(minWidth: 64)
                    if let agg = aggregate {
                        Text("(\(score + (side == .home ? agg.firstLegHome : agg.firstLegAway)))")
                            .scaledFont(.caption).monospacedDigit().foregroundStyle(.secondary)
                    }
                }
                Button { model.apply(.goal(side, -1), slot: slot) } label: {
                    Image(systemName: "minus").scaledFont(.title, weight: .bold).frame(width: goalButtonSide, height: goalButtonSide)
                        .frame(minWidth: goalButtonSide, minHeight: goalButtonSide)
                }
                .buttonStyle(.bordered).controlSize(.extraLarge).disabled(score == 0)
                .accessibilityLabel("Remove last \(team.shortName) goal")
                .help(score == 0 ? "No \(team.shortName) goals to remove" : "Remove the last \(team.shortName) goal")
                PlusGoalButton(side: side, team: team, phase: phase, slot: slot, model: model, buttonSide: goalButtonSide).equatable()
            }
        }
        .frame(maxWidth: .infinity)
    }
}

struct MatchSetupSection: View, Equatable {
    let home: TeamEntry
    let away: TeamEntry
    let competitionId: String
    let phase: Phase
    let aggregate: Aggregate?
    let hasKnockouts: Bool
    let slot: Int
    let model: AppModel
    let zoomGeneration: Int
    @State private var isExpanded: Bool
    @State private var showingFixtures = false

    init(home: TeamEntry, away: TeamEntry, competitionId: String, phase: Phase, aggregate: Aggregate?, hasKnockouts: Bool, slot: Int, model: AppModel, zoomGeneration: Int) {
        self.home = home; self.away = away; self.competitionId = competitionId; self.phase = phase
        self.aggregate = aggregate; self.hasKnockouts = hasKnockouts; self.slot = slot; self.model = model
        self.zoomGeneration = zoomGeneration
        _isExpanded = State(initialValue: phase == .preMatch)
    }

    static func == (l: Self, r: Self) -> Bool {
        l.home == r.home && l.away == r.away && l.competitionId == r.competitionId && l.phase == r.phase
            && l.aggregate == r.aggregate && l.hasKnockouts == r.hasKnockouts && l.slot == r.slot
            && l.zoomGeneration == r.zoomGeneration
    }

    private var competition: Competition? { model.library.competitions.first { $0.id == competitionId } }

    var body: some View {
        Panel("Match setup") {
            DisclosureGroup(isExpanded: $isExpanded) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        ClubPickerButton(side: .home, slot: slot).equatable()
                        ClubPickerButton(side: .away, slot: slot).equatable()
                        Button { model.apply(.swapTeams, slot: slot) } label: {
                            Label("Swap", systemImage: "arrow.left.arrow.right").scaledFont(.body).scaledControl()
                        }
                        .buttonStyle(.bordered).help("Swap home and away")
                    }
                    HStack(spacing: 8) {
                        if let c = competition { CompetitionMark(competition: c, size: 30, plate: true) }
                        Picker("Competition", selection: Binding(get: { competitionId }, set: { model.setCompetition($0, slot: slot) })) {
                            ForEach(model.library.competitions) { c in Text(c.name).tag(c.id) }
                        }.scaledFont(.body).frame(maxWidth: 360)
                    }
                    if hasKnockouts {
                        Toggle("Second leg of a tie", isOn: Binding(
                            get: { aggregate != nil },
                            set: { on in model.apply(on ? .setAggregate(home: aggregate?.firstLegHome ?? 0, away: aggregate?.firstLegAway ?? 0) : .clearAggregate, slot: slot) }
                        )).scaledFont(.body)
                        if let agg = aggregate {
                            HStack(spacing: 4) {
                                Text("First leg \(home.code)").scaledFont(.caption).foregroundStyle(.secondary)
                                AggregateField(value: agg.firstLegHome) { model.apply(.setAggregate(home: $0, away: agg.firstLegAway), slot: slot) }
                                Text("–").scaledFont(.caption).foregroundStyle(.secondary)
                                AggregateField(value: agg.firstLegAway) { model.apply(.setAggregate(home: agg.firstLegHome, away: $0), slot: slot) }
                                Text(away.code).scaledFont(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    Button { showingFixtures = true } label: { Text("Load fixture…").scaledFont(.body).scaledControl() }
                        .disabled(phase != .preMatch).help("Only available before kick-off")
                }.padding(.top, 8)
            } label: { Text("Teams and competition").scaledFont(.caption).foregroundStyle(.secondary) }
        }
        .onChange(of: phase) { _, phase in isExpanded = phase == .preMatch }
        .sheet(isPresented: $showingFixtures) { FixturePickerSheet(competitionId: competitionId, slot: slot) }
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

private struct FixturePickerSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let competitionId: String
    let slot: Int
    @State private var date = Calendar.current.startOfDay(for: .now)
    @State private var fixtures: [Fixture] = []
    @State private var selected: Fixture?
    @State private var isLoading = false
    @State private var failed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            DatePicker("Date", selection: $date, displayedComponents: .date).scaledFont(.body)
            if isLoading {
                ProgressView("Loading fixtures…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if failed {
                ContentUnavailableView("Couldn't reach the fixture service", systemImage: "wifi.exclamationmark")
            } else if fixtures.isEmpty {
                ContentUnavailableView("No fixtures found for this date", systemImage: "calendar")
            } else {
                List {
                    ForEach(fixtures.indices, id: \.self) { index in
                        let fixture = fixtures[index]
                        Button { selected = fixture } label: {
                            HStack(spacing: 10) {
                                FixtureTeamMark(team: fixture.home)
                                Text(fixture.home.shortName).lineLimit(1)
                                Text("v").foregroundStyle(.secondary)
                                Text(fixture.away.shortName).lineLimit(1)
                                FixtureTeamMark(team: fixture.away)
                                Spacer()
                                Text(fixture.kickoff.formatted(date: .omitted, time: .shortened)).foregroundStyle(.secondary)
                            }.scaledFont(.body).padding(.vertical, 4).scaledControl().contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(selected == fixture ? Color.accentColor.opacity(0.18) : .clear)
                    }
                }
            }
            HStack {
                Spacer()
                Button { dismiss() } label: { Text("Cancel").scaledFont(.body).scaledControl() }.keyboardShortcut(.cancelAction)
                Button {
                    guard let selected else { return }
                    Task { await model.loadFixture(selected, slot: slot); dismiss() }
                } label: { Text("Load").scaledFont(.body).scaledControl() }
                    .keyboardShortcut(.defaultAction).disabled(selected == nil || isLoading)
            }
        }
        .padding(20).frame(width: 620, height: 480)
        .task(id: date) { await loadFixtures() }
    }

    @MainActor
    private func loadFixtures() async {
        isLoading = true; failed = false; selected = nil
        do { fixtures = try await model.fixtures(on: date, competitionId: competitionId) }
        catch { fixtures = []; failed = true }
        isLoading = false
    }
}

private struct FixtureTeamMark: View {
    let team: FixtureTeam
    var body: some View {
        AsyncImage(url: team.crestURL) { image in
            image.resizable().scaledToFit()
        } placeholder: {
            Circle().fill(Color.secondary.opacity(0.18)).overlay(Text(team.code.prefix(2)).scaledFont(.caption2, weight: .bold).foregroundStyle(.secondary))
        }
        .frame(width: 24, height: 24)
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
    let buttonSide: CGFloat
    static func == (l: Self, r: Self) -> Bool {
        l.side == r.side && l.team == r.team && l.phase == r.phase && l.slot == r.slot && l.buttonSide == r.buttonSide
    }

    /// Goal whose scorer popover should be open on this button, since it just scored it. Cleared as soon as
    /// that goal is no longer in the match (the guard below checks on every read, fetched live from `model`).
    @State private var plusPromptGoalId: UUID?

    var body: some View {
        Button {
            model.apply(.goal(side, 1), slot: slot)
            plusPromptGoalId = model.match(slot).lastGoal?.goalId
        } label: {
            Image(systemName: "plus").scaledFont(.title, weight: .bold).frame(width: buttonSide, height: buttonSide)
                .frame(minWidth: buttonSide, minHeight: buttonSide)
        }
            .buttonStyle(.borderedProminent).controlSize(.extraLarge)
            .keyboardShortcut(side == .home ? "h" : "a", modifiers: [.command, .shift])
            .disabled(phase == .shootout).help("Goal for \(team.name) (⇧⌘\(side == .home ? "H" : "A"))")
            .accessibilityLabel("Goal for \(team.name)")
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
    let hasKnockouts: Bool
    let slot: Int
    let model: AppModel
    let zoomGeneration: Int
    @State private var confirmResetClock = false
    private static let unavailableHelp = "Only available while a period is live, not before kick-off or during a shootout"

    static func == (l: Self, r: Self) -> Bool {
        l.phase == r.phase && l.clock == r.clock && l.hasKnockouts == r.hasKnockouts && l.slot == r.slot
            && l.zoomGeneration == r.zoomGeneration
    }

    private var periods: [Period] { Period.allCases.filter { hasKnockouts || ($0 != .extraFirst && $0 != .extraSecond) } }

    var body: some View {
        Panel("Clock") {
            VStack(spacing: 16) {
                HStack(spacing: 12) {
                    HStack(spacing: 8) { ForEach(periods, id: \.self) { p in periodPill(p) } }
                    Spacer(minLength: 12)
                    TimelineView(.periodic(from: .now, by: clock.running ? 1.0 : 3600)) { context in
                        ClockFieldsRow(slot: slot, tick: context.date)
                    }
                }
                HStack(spacing: 10) {
                    resetClockButton
                    Button { model.apply(.adjustClock(deltaSeconds: -10), slot: slot) } label: {
                        Text("−10 s").frame(maxWidth: .infinity).scaledControl(64)
                    }.disabled(phase.period == nil).help(Self.unavailableHelp)
                    Button { model.apply(.adjustClock(deltaSeconds: -1), slot: slot) } label: {
                        Text("−1 s").frame(maxWidth: .infinity).scaledControl(64)
                    }.disabled(phase.period == nil).help(Self.unavailableHelp)
                    Button { model.apply(.adjustClock(deltaSeconds: 1), slot: slot) } label: {
                        Text("+1 s").frame(maxWidth: .infinity).scaledControl(64)
                    }.disabled(phase.period == nil).help(Self.unavailableHelp)
                    Button { model.apply(.adjustClock(deltaSeconds: 10), slot: slot) } label: {
                        Text("+10 s").frame(maxWidth: .infinity).scaledControl(64)
                    }.disabled(phase.period == nil).help(Self.unavailableHelp)
                    Button {
                        model.apply(.endPeriod, slot: slot)
                    } label: {
                        Text("End half").frame(maxWidth: .infinity).scaledControl(64)
                    }
                    .disabled(phase.period == nil)
                    .keyboardShortcut("e", modifiers: [.command, .shift]).help("End the current period (⇧⌘E)")
                }
                .buttonStyle(.bordered).controlSize(.extraLarge).scaledFont(.body, weight: .semibold)
                // Periods remain available to correct a mistaken selection.
            }
        }
    }

    private var resetClockButton: some View {
        Button {
            if clock.running { confirmResetClock = true } else { model.apply(.setClock(seconds: 0), slot: slot) }
        } label: {
            Text("Reset clock").frame(maxWidth: .infinity).scaledControl(64)
        }
        .disabled(phase.period == nil)
        .help(Self.unavailableHelp)
        .confirmationDialog("Reset the clock to zero?", isPresented: $confirmResetClock) {
            Button("Reset clock", role: .destructive) { model.apply(.setClock(seconds: 0), slot: slot) }
        }
    }

    @ViewBuilder
    private func periodPill(_ p: Period) -> some View {
        let button = Button {
            model.apply(.startPeriod(p), slot: slot)
        } label: {
            Text(p.shortLabel).scaledFont(.body, weight: .semibold).frame(maxWidth: .infinity).scaledControl(64)
        }
        .controlSize(.extraLarge).help(p.title)
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
    let zoomGeneration: Int
    @State private var lastValue = 1

    static func == (l: Self, r: Self) -> Bool {
        l.addedMinutes == r.addedMinutes && l.slot == r.slot && l.zoomGeneration == r.zoomGeneration
    }

    /// Remembers the last non-zero value per slot, so switching slots (or reopening the app) does not forget
    /// a "+3" that was switched off with "Show on bug".
    private var defaultsKey: String { "lastAdded\(slot)" }

    var body: some View {
        Panel("Stoppage", accessory: {
            Toggle("Show on bug", isOn: showBinding).toggleStyle(.switch).scaledFont(.caption)
        }) {
            HStack(spacing: 16) {
                Button { adjust(-1) } label: { Image(systemName: "minus").scaledFont(.title2, weight: .semibold).scaledControl(square: true) }
                    .buttonStyle(.bordered).controlSize(.extraLarge)
                    .disabled((addedMinutes ?? 0) <= 0)
                Text(addedMinutes.map { "+\($0)" } ?? "Off").scaledFont(size: 28, weight: .bold, design: .rounded).monospacedDigit().frame(minWidth: 80)
                Button { adjust(1) } label: { Image(systemName: "plus").scaledFont(.title2, weight: .semibold).scaledControl(square: true) }
                    .buttonStyle(.bordered).controlSize(.extraLarge)
                    .disabled((addedMinutes ?? 0) >= 15)
            }
            .frame(maxWidth: .infinity)
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
    let match: Match
    let goals: [Goal]
    let homeCode: String
    let awayCode: String
    let showScorers: Bool
    let homeColour: String
    let awayColour: String
    let slot: Int
    let model: AppModel
    let zoomGeneration: Int

    static func == (l: Self, r: Self) -> Bool {
        l.match.espnEventId == r.match.espnEventId && l.match.home.shortName == r.match.home.shortName && l.match.away.shortName == r.match.away.shortName
            && l.match.autoUpdateLiveData == r.match.autoUpdateLiveData && l.match.liveDataDelayMinutes == r.match.liveDataDelayMinutes
            && l.match.liveDataNotice == r.match.liveDataNotice && l.goals == r.goals && l.homeCode == r.homeCode && l.awayCode == r.awayCode
            && l.showScorers == r.showScorers && l.homeColour == r.homeColour && l.awayColour == r.awayColour
            && l.slot == r.slot && l.zoomGeneration == r.zoomGeneration
    }

    var body: some View {
        Panel("Goals", accessory: {
            Toggle("Show scorers", isOn: Binding(get: { showScorers }, set: { model.apply(.setShowScorers($0), slot: slot) }))
                .toggleStyle(.switch).scaledFont(.caption).disabled(goals.isEmpty)
                .help(goals.isEmpty ? "No goals yet to show scorers for" : "Show scorer names on the bug")
        }) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    if match.espnEventId != nil {
                        Label("Linked to ESPN · \(match.home.shortName) v \(match.away.shortName)", systemImage: "link")
                            .scaledFont(.caption).foregroundStyle(.secondary).lineLimit(1)
                        Button("Unlink") { model.apply(.setLiveLink(eventId: nil, league: nil), slot: slot) }.scaledFont(.caption)
                    } else {
                        Text("Not linked to live data").scaledFont(.caption).foregroundStyle(.secondary)
                        Button("Link") { Task { await model.linkESPN(slot: slot) } }.scaledFont(.caption)
                    }
                    Spacer()
                    Toggle("Auto-update from live data", isOn: Binding(get: { match.autoUpdateLiveData }, set: { model.apply(.setAutoUpdateLiveData($0), slot: slot) }))
                        .toggleStyle(.switch).scaledFont(.caption)
                }
                HStack {
                    Text("Spoiler delay").scaledFont(.caption).foregroundStyle(.secondary)
                    Picker("Spoiler delay", selection: Binding(get: { match.liveDataDelayMinutes }, set: { model.apply(.setLiveDataDelay($0), slot: slot) })) {
                        ForEach(0...10, id: \.self) { Text("\($0) min").tag($0) }
                    }.labelsHidden().frame(width: 96)
                    Spacer()
                }
                if let notice = match.liveDataNotice {
                    Text(notice).scaledFont(.caption).foregroundStyle(.secondary)
                }
                if goals.isEmpty {
                    Text("No goals yet. Use the plus buttons above; each goal gets a line here for the scorer's name.").scaledFont(.caption).foregroundStyle(.secondary)
                }
                ForEach(goals) { goal in
                    HStack(spacing: 10) {
                        Circle().fill(Color(hex: goal.side == .home ? homeColour : awayColour)).frame(width: 8, height: 8)
                        Text(goal.side == .home ? homeCode : awayCode).scaledFont(.body).lineLimit(1).frame(width: 56, alignment: .leading)
                        GoalMinuteField(goal: goal, slot: slot)
                        if goal.autoAdded { Text("Auto").scaledFont(.caption, weight: .semibold).padding(.horizontal, 6).padding(.vertical, 3).background(.secondary.opacity(0.16), in: Capsule()) }
                        GoalRow(goal: goal, slot: slot).frame(maxWidth: .infinity)
                        Button { model.apply(.removeGoal(goal.id), slot: slot) } label: {
                            // scaledControl(32, square: true) used to differ from the default here; now that
                            // the modifier floors at 44 regardless of a smaller base, the two are the same.
                            Image(systemName: "minus").scaledFont(.callout, weight: .semibold).frame(width: 32, height: 32).scaledControl(square: true)
                        }
                        .buttonStyle(.bordered)
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
    let zoomGeneration: Int

    static func == (l: Self, r: Self) -> Bool {
        l.shootout == r.shootout && l.phase == r.phase && l.homeShortName == r.homeShortName
            && l.awayShortName == r.awayShortName && l.slot == r.slot && l.zoomGeneration == r.zoomGeneration
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
                        Text("Undo last").frame(maxWidth: .infinity).scaledControl(64)
                    }
                    .buttonStyle(.bordered).controlSize(.extraLarge).disabled(s.kicks.isEmpty)
                } else {
                    Button {
                        model.apply(.startShootout(.home), slot: slot)
                    } label: {
                        // Painted as our own layer, same as the Play/Pause tint, so it still reads once the
                        // window is not key (the streamer has OBS focused).
                        Text("Start shootout").frame(maxWidth: .infinity).scaledControl(64)
                            .background(Color.accentColor.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.borderedProminent).controlSize(.extraLarge)
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
            Text(title).frame(maxWidth: .infinity).scaledControl(64)
                .background(tint.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.borderedProminent).controlSize(.extraLarge).tint(tint)
        // The engine takes kicks whenever a shootout exists, not only while `phase == .shootout` (a kick can
        // land after full time or extra time too), so the buttons follow the shootout's existence, not the phase.
        .disabled(shootout == nil)
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
                if let a = display.added { Text(a).scaledFont(.title3, weight: .semibold).foregroundStyle(.primary).padding(.horizontal, 8).padding(.vertical, 2).background(.orange, in: Capsule()) }
                if let c = display.addedCounter { Text(c).scaledFont(.callout).monospacedDigit().foregroundStyle(.secondary) }
            }.frame(height: 20)
            Text(phase.displayTitle).scaledFont(.subheadline).foregroundStyle(.secondary)
        }
    }
}

/// The editable minutes/seconds pair in the Clock block: shows the cumulative on-screen time (period
/// base + elapsed, the same value `ClockReadout` derives via `Clock.elapsed(at:)`), flanked by round −/+
/// buttons that nudge the clock directly. `tick` comes from `ClockSection`'s shared periodic `TimelineView`.
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
        .help(match.currentPeriod == nil ? "Only available while a period is live, not before kick-off or during a shootout" : "")
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
        model.apply(.setClock(seconds: max(0, min(333, max(0, m)) * 60 + min(59, max(0, s)) - periodBaseSeconds)), slot: slot)
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
        // `Button(String)` ignores an outer `.scaledFont`, so the title is a Text inside the label closure
        // instead; the frame carries the 44 pt minimum row height, scaled by zoom like every other control.
        Button {
            isOpen = true
        } label: {
            Text(label).scaledFont(.body).foregroundStyle(goal.scorer == nil || goal.scorer?.isEmpty == true ? .secondary : .primary)
                .frame(maxWidth: .infinity, alignment: .leading).scaledControl()
        }
        .controlSize(.large)
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

    /// `Club.isEligible(for:)`: memberships decide for clubs and national teams alike (Codex review, 1 Oct).
    private func isEligible(_ club: Club) -> Bool { club.isEligible(for: match.competitionId) }

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
            // A minimum, not maxWidth: a short name (e.g. "Inter") must not leave this button narrower than
            // the other side's, which is what threw the two pickers out of alignment. Both dimensions scale
            // with interface zoom like every other panel control, the width base carried directly since it
            // is not the usual 44/56/64 pt shape.
            .frame(minWidth: 220 * ScaledFonts.scale, alignment: .leading)
            .scaledControl()
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
                        .onAppear { proxy.scrollTo(highlighted, anchor: .center) }
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
    let visible: Bool
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
                previewPane(path: "h", width: hW, height: stageH, canvas: CGSize(width: 1920, height: 1080))
                previewPane(path: "v", width: vW, height: stageH, canvas: CGSize(width: 1080, height: 1920))
                Spacer(minLength: 0)
            }.padding(8)
        }
        .frame(maxWidth: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func previewPane(path: String, width: CGFloat, height: CGFloat, canvas: CGSize) -> some View {
        OverlayWebView(url: URL(string: "\(baseURL)/overlay/\(path)/\(slot)?preview=1")!, scale: width / canvas.width, size: canvas)
            .frame(width: width, height: height).background(.black).clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay {
                if !visible {
                    Text("Off air").scaledFont(.caption).foregroundStyle(.secondary).padding(.horizontal, 12).padding(.vertical, 6)
                        .background(.regularMaterial, in: Capsule())
                }
            }
    }
}
