import Foundation

enum SidebarSection: Hashable {
    case slot(Int), library

    var storageID: String {
        switch self { case .slot(2): return "secondary"; case .slot: return "primary"; case .library: return "library" }
    }
    init(storageID: String) {
        switch storageID { case "secondary": self = .slot(2); case "library": self = .library; default: self = .slot(1) }
    }
}

