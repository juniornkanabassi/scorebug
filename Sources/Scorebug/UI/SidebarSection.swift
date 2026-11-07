import Foundation

enum SidebarSection: Hashable {
    case slot(Int), library

    var storageID: String {
        switch self { case .slot(2): return "secondary"; case .slot: return "primary"; case .library: return "library" }
    }
    init(storageID: String) {
        switch storageID { case "secondary": self = .slot(2); case "library": self = .library; default: self = .slot(1) }
    }

    /// Window restoration is off, so SceneStorage starts empty at each launch; this default keeps the last page across quits.
    /// Unknown stored values fall back to Primary through init(storageID:).
    static var remembered: String {
        get { UserDefaults.standard.string(forKey: "lastSidebarSection") ?? "primary" }
        set { UserDefaults.standard.set(newValue, forKey: "lastSidebarSection") }
    }
}

