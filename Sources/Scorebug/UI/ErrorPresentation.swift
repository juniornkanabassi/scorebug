import Foundation

/// Alert titles name the failed task; each `AppModel.report` call site picks one, and the message keeps the diagnostic.
enum ErrorTitle: String {
    case saveMatch = "Unable to Save Match"
    case saveLibrary = "Unable to Save Team Library"
    case saveSettings = "Unable to Save Settings"
    case load = "Unable to Load Saved Data"
    case importCrests = "Unable to Import Crests"
    case importLogo = "Unable to Import Competition Logo"
    case findFixture = "Unable to Find Fixture"
    case generic = "Unable to Complete Action"
}
