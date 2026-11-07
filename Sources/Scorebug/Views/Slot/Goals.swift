import SwiftUI
import ScorebugCore

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
    @State private var linking = false

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
            VStack(alignment: .leading, spacing: Space.xs) {
                HStack(spacing: Space.sm) {
                    if match.espnEventId != nil {
                        Label("Linked to ESPN · \(match.home.shortName) v \(match.away.shortName)", systemImage: "link")
                            .scaledFont(.caption).foregroundStyle(.secondary).lineLimit(1)
                        Button("Unlink") { model.apply(.setLiveLink(eventId: nil, league: nil), slot: slot) }.scaledFont(.caption)
                    } else {
                        Text("Not linked to live data").scaledFont(.caption).foregroundStyle(.secondary)
                        if linking {
                            ProgressView().controlSize(.small).accessibilityLabel("Looking for the ESPN fixture")
                            Text("Looking for the ESPN fixture…").scaledFont(.caption).foregroundStyle(.secondary)
                        } else {
                            Button("Link") {
                                linking = true
                                Task { await model.linkESPN(slot: slot); linking = false }
                            }.scaledFont(.caption).help("Find this match on ESPN; press again to retry")
                        }
                    }
                    Spacer()
                    Toggle("Auto-update from live data", isOn: Binding(get: { match.autoUpdateLiveData }, set: { model.apply(.setAutoUpdateLiveData($0), slot: slot) }))
                        .toggleStyle(.switch).scaledFont(.caption)
                }
                HStack {
                    Text("Spoiler delay").scaledFont(.caption).foregroundStyle(.secondary)
                    Picker("Spoiler delay", selection: Binding(get: { match.liveDataDelayMinutes }, set: { model.apply(.setLiveDataDelay($0), slot: slot) })) {
                        ForEach(0...10, id: \.self) { Text("\($0) min").tag($0) }
                    }.labelsHidden().frame(width: 96 * ScaledFonts.scale)
                    Spacer()
                }
                if let notice = match.liveDataNotice {
                    Text(notice).scaledFont(.caption).foregroundStyle(.secondary)
                }
                if goals.isEmpty {
                    Text("No goals yet. Use the plus buttons above; each goal gets a line here for the scorer's name.").scaledFont(.caption).foregroundStyle(.secondary)
                }
                ForEach(goals) { goal in
                    HStack(spacing: Space.md) {
                        Circle().fill(Color(hex: goal.side == .home ? homeColour : awayColour)).frame(width: 8, height: 8)
                        Text(goal.side == .home ? homeCode : awayCode).scaledFont(.body).lineLimit(1).frame(width: 56 * ScaledFonts.scale, alignment: .leading)
                        GoalMinuteField(goal: goal, slot: slot)
                        if goal.autoAdded { Text("Auto").scaledFont(.caption, weight: .semibold).padding(.horizontal, Space.sm).padding(.vertical, Space.xs).background(.secondary.opacity(0.16), in: Capsule()) }
                        GoalRow(goal: goal, slot: slot).frame(maxWidth: .infinity)
                        Button { model.removeGoalFromWindow(.removeGoal(goal.id), slot: slot) } label: {
                            // scaledControl(32, square: true) used to differ from the default here; now that
                            // the modifier floors at 44 regardless of a smaller base, the two are the same.
                            Image(systemName: "minus").scaledFont(.callout, weight: .semibold).frame(width: 32, height: 32).scaledControl(square: true)
                        }
                        .buttonStyle(.bordered)
                        .help("Remove this goal; Undo puts it back").accessibilityLabel("Remove \(goal.side == .home ? homeCode : awayCode) goal at \(goal.minuteLabel)")
                    }
                    .frame(minHeight: 44 * ScaledFonts.scale)
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
            .accessibilityLabel("Goal minute")
            .scaledFont(size: 18).monospacedDigit().multilineTextAlignment(.center)
            // The native rounded bezel caps its text cell height even when the outer frame grows.
            .textFieldStyle(.plain)
            .padding(.horizontal, Space.xs)
            .frame(width: 56 * ScaledFonts.scale, height: 44 * ScaledFonts.scale)
            .background(Surface.fill, in: RoundedRectangle(cornerRadius: Radius.small))
            .overlay(RoundedRectangle(cornerRadius: Radius.small).stroke(focused ? Color.accentColor : Surface.separator, lineWidth: 1))
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

