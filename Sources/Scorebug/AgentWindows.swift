import AppKit

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

