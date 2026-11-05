import SwiftUI
import ScorebugCore

struct FixturePickerSheet: View {
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
        VStack(alignment: .leading, spacing: Space.md) {
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
                            HStack(spacing: Space.md) {
                                FixtureTeamMark(team: fixture.home)
                                Text(fixture.home.shortName).lineLimit(1).help(fixture.home.name)
                                Text("v").foregroundStyle(.secondary)
                                Text(fixture.away.shortName).lineLimit(1).help(fixture.away.name)
                                FixtureTeamMark(team: fixture.away)
                                Spacer()
                                Text(fixture.kickoff.formatted(date: .omitted, time: .shortened)).foregroundStyle(.secondary)
                            }.scaledFont(.body).padding(.vertical, Space.xs).scaledControl().contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(selected == fixture ? Surface.selectedFill : .clear)
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
        .padding(Space.xl).frame(width: 620, height: 480)
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

