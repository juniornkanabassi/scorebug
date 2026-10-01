// UI caches and Keychain are excluded; the model, server, engine and transport are the production sources.
import Foundation
import SwiftUI
import ScorebugCore

enum CrestImage { static var directory: URL?; static func invalidate(file: String) {} }
enum ScaledFonts { static var scale: CGFloat = 1 }
enum KeychainStore { static func get() -> String? { fatalError("disposable checks must not use Keychain") } }
