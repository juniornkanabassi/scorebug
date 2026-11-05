import SwiftUI
import ScorebugCore

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
                VStack(alignment: .leading, spacing: Space.md) {
                    HStack(spacing: Space.md) {
                        ClubPickerButton(side: .home, slot: slot).equatable()
                        ClubPickerButton(side: .away, slot: slot).equatable()
                        Button { model.apply(.swapTeams, slot: slot) } label: {
                            Label("Swap", systemImage: "arrow.left.arrow.right").scaledFont(.body).scaledControl()
                        }
                        .buttonStyle(.bordered).help("Swap home and away")
                    }
                    HStack(spacing: Space.sm) {
                        if let c = competition { CompetitionMark(competition: c, size: 32, plate: true) }
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
                            HStack(spacing: Space.xs) {
                                Text("First leg \(home.code)").scaledFont(.caption).foregroundStyle(.secondary)
                                AggregateField(value: agg.firstLegHome) { model.apply(.setAggregate(home: $0, away: agg.firstLegAway), slot: slot) }
                                    .accessibilityLabel("First leg home score")
                                Text("–").scaledFont(.caption).foregroundStyle(.secondary)
                                AggregateField(value: agg.firstLegAway) { model.apply(.setAggregate(home: agg.firstLegHome, away: $0), slot: slot) }
                                    .accessibilityLabel("First leg away score")
                                Text(away.code).scaledFont(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    Button { showingFixtures = true } label: { Text("Load fixture…").scaledFont(.body).scaledControl() }
                        .disabled(phase != .preMatch).help("Only available before kick-off")
                }.padding(.top, Space.sm)
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

