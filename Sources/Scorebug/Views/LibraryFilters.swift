// Library Clubs tab: view mode, filters and the removable filter chip. Split out of LibraryView.swift
// only so that file stays readable; behaviour lives with the view that uses it.
import SwiftUI
import ScorebugCore

/// How the Clubs tab lays out its results. Persisted, so the user's choice survives a relaunch.
enum LibraryViewMode: String, CaseIterable {
    case list, icons
}

/// The "Clubs and nations" segmented choice. A club is a national team when its
/// `competitionIds` contains "international".
enum ClubsNationsFilter: String, CaseIterable, Identifiable {
    case all, clubs, nations
    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: return "All"
        case .clubs: return "Clubs"
        case .nations: return "National teams"
        }
    }
}

enum LibraryFilters {
    /// Canonical confederation order; anything else found in the data is appended alphabetically.
    static let confederationOrder = ["UEFA", "CONMEBOL", "CONCACAF", "CAF", "AFC", "OFC"]
}

/// A removable chip for one active filter, in the style of Mail's or Notes' filter bars.
struct FilterChip: View {
    let label: String
    let onRemove: () -> Void
    var body: some View {
        HStack(spacing: 4) {
            Text(label).font(.caption)
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill").font(.caption)
            }.buttonStyle(.plain)
        }
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(Capsule().fill(Color.accentColor.opacity(0.15)))
        .foregroundStyle(Color.accentColor)
    }
}
