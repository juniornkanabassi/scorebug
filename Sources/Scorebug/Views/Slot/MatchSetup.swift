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
        // One heading: the panel's own, with the show/hide control beside it, instead of a second disclosure title.
        Panel("Match setup", accessory: {
            Button { isExpanded.toggle() } label: {
                Label(isExpanded ? "Hide" : "Show", systemImage: isExpanded ? "chevron.up" : "chevron.down").scaledFont(.caption).scaledControl()
            }
            .buttonStyle(.borderless).help(isExpanded ? "Hide the teams and competition" : "Show the teams and competition")
        }) {
            if !isExpanded {
                Text("\(home.name) v \(away.name) · \(competition?.name ?? competitionId)").scaledFont(.body).foregroundStyle(.primary).lineLimit(1)
            } else {
                VStack(alignment: .leading, spacing: Space.md) {
                    HStack(spacing: Space.md) {
                        ClubPickerButton(side: .home, slot: slot).equatable()
                        ClubPickerButton(side: .away, slot: slot).equatable()
                        Button { model.apply(.swapTeams, slot: slot) } label: {
                            Label("Swap", systemImage: "arrow.left.arrow.right").scaledFont(.body).scaledControl()
                        }
                        .buttonStyle(.bordered).help("Swap home and away")
                    }
                    Picker(selection: Binding(get: { competitionId }, set: { model.setCompetition($0, slot: slot) })) {
                        ForEach(model.library.competitions) { c in Text(c.name).tag(c.id) }
                    } label: {
                        HStack(spacing: Space.sm) {
                            if let c = competition { CompetitionMark(competition: c, size: 32, plate: true) }
                            Text("Competition").scaledFont(.body)
                        }
                    }
                    .scaledFont(.body).controlSize(.extraLarge)
                    .frame(maxWidth: .infinity, minHeight: 44 * ScaledFonts.scale)
                    .accessibilityLabel("Competition")
                    if hasKnockouts {
                        Toggle("Second leg of a tie", isOn: Binding(
                            get: { aggregate != nil },
                            set: { on in model.apply(on ? .setAggregate(home: aggregate?.firstLegHome ?? 0, away: aggregate?.firstLegAway ?? 0) : .clearAggregate, slot: slot) }
                        )).scaledFont(.body).controlSize(.large).frame(minHeight: 44 * ScaledFonts.scale)
                        if let agg = aggregate {
                            HStack(spacing: Space.xs) {
                                Text("First leg \(home.code)").scaledFont(.body).foregroundStyle(.primary)
                                AggregateField(value: agg.firstLegHome) { model.apply(.setAggregate(home: $0, away: agg.firstLegAway), slot: slot) }
                                    .accessibilityLabel("First leg home score")
                                Text("–").scaledFont(.body).foregroundStyle(.primary)
                                AggregateField(value: agg.firstLegAway) { model.apply(.setAggregate(home: agg.firstLegHome, away: $0), slot: slot) }
                                    .accessibilityLabel("First leg away score")
                                Text(away.code).scaledFont(.body).foregroundStyle(.primary)
                            }
                        }
                    }
                    Button { showingFixtures = true } label: { Text("Load fixture…").scaledFont(.body).scaledControl() }
                        .disabled(phase != .preMatch).help("Only available before kick-off")
                }
            }
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
            .scaledFont(.body).monospacedDigit().multilineTextAlignment(.center)
            .textFieldStyle(.plain).controlSize(.large)
            .frame(width: 48 * ScaledFonts.scale, height: 44 * ScaledFonts.scale)
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: Radius.small))
            .overlay {
                RoundedRectangle(cornerRadius: Radius.small).stroke(.tertiary, lineWidth: 1)
                if focused { RoundedRectangle(cornerRadius: Radius.small).stroke(Color.accentColor, lineWidth: 1) }
            }
            .focused($focused)
            .onAppear { text = "\(value)" }
            .onChange(of: value) { _, new in if !focused { text = "\(new)" } }
            .onChange(of: focused) { _, now in if !now { text = "\(value)" } }
            .onSubmit {
                if let n = Int(text) { onChange(max(0, n)) } else { text = "\(value)" }
            }
    }
}

