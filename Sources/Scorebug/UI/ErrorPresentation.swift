import Foundation

/// Keep the diagnostic intact while naming the failed task in the alert title.
enum ErrorPresentation {
    static func title(for message: String) -> String {
        let text = message.lowercased()
        if text.contains("save state") { return "Unable to Save Match" }
        if text.contains("save library") || text.contains("unsaved updates") { return "Unable to Save Team Library" }
        if text.contains("save settings") { return "Unable to Save Settings" }
        if text.contains("load ") { return "Unable to Load Saved Data" }
        if text.contains("crest") { return "Unable to Import Crests" }
        if text.contains("competition logo") { return "Unable to Import Competition Logo" }
        if text.contains("fixture") { return "Unable to Find Fixture" }
        return "Unable to Complete Action"
    }
}
