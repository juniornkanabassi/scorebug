import AppKit
import SwiftUI
import ScorebugCore

@MainActor enum AgentWindows {
    static let invisible = LaunchOptions.parse(Array(CommandLine.arguments.dropFirst())).invisible
        || NativeSnapshots.isRequested
        || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
}

extension NSWindow {
  /// `--agent-screen` (the packaged checks) runs the real app with nothing visible on any of Junior's displays:
  /// windows stay ordered in, so Accessibility still reads them, but are transparent and let clicks through.
  static func keepEveryWindowInvisible() {
    NotificationCenter.default.addObserver(forName: NSWindow.didUpdateNotification, object: nil, queue: .main) { note in
      guard let window = note.object as? NSWindow, window.alphaValue != 0 || !window.ignoresMouseEvents else { return }
      MainActor.assumeIsolated { window.alphaValue = 0; window.ignoresMouseEvents = true }
    }
  }
}


/// Two-launch check of the remembered sidebar page (Scripts/sidebar-restore-check.sh). Acts only in an invisible launch with
/// a disposable home and data folder: `select:<page>` picks a page through the sidebar's own binding and quits; `report`
/// prints the page the new window opened on and quits.
@MainActor enum SidebarRestoreProbe {
    static func run(_ selection: Binding<SidebarSection?>) {
        let environment = ProcessInfo.processInfo.environment
        guard let probe = environment["SCOREBUG_SIDEBAR_PROBE"], AgentWindows.invisible, environment["CFFIXED_USER_HOME"] != nil,
              CommandLine.arguments.contains("--data-directory"),
              LaunchOptions.parse(Array(CommandLine.arguments.dropFirst())).dataDirectory != Store.defaultDirectory() else { return }
        // After this update pass, as a click would be, so the sidebar's table is not changed from inside its own delegate.
        DispatchQueue.main.async {
            if probe.hasPrefix("select:") { selection.wrappedValue = SidebarSection(storageID: String(probe.dropFirst(7))) }
            let shown = selection.wrappedValue?.storageID ?? "none"
            FileHandle.standardError.write(Data("SIDEBAR_PROBE \(probe) shown=\(shown)\n".utf8))
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { NSApp.terminate(nil) }
        }
    }
}
