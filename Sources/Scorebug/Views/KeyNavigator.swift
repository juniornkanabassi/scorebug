// Arrow-key and Return/Escape navigation for a search popover's result list, installed as a local key-down
// monitor so it fires no matter which field has focus (a plain `.onKeyPress` on the list never got the event
// while the search `TextField` was focused, which is why arrow keys did nothing in these popovers).
import SwiftUI
import AppKit

private struct KeyNavigationModifier: ViewModifier {
    let count: Int
    @Binding var highlighted: Int
    let onPick: () -> Void
    let onClose: () -> Void
    @State private var monitor: Any?
    // The monitor closure is installed once, in onAppear, so it must not close over `count` by value: typing
    // a filter changes `count` on every keystroke, and a closure that captured the original count would let
    // the highlight climb past the (now shorter) list and pick nothing on Return. `liveCount` is kept current
    // by onChange and read fresh on every key press instead.
    @State private var liveCount: Int

    init(count: Int, highlighted: Binding<Int>, onPick: @escaping () -> Void, onClose: @escaping () -> Void) {
        self.count = count
        self._highlighted = highlighted
        self.onPick = onPick
        self.onClose = onClose
        self._liveCount = State(initialValue: count)
    }

    func body(content: Content) -> some View {
        content
            .onAppear {
                monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                    switch event.keyCode {
                    case 125 where liveCount > 0: highlighted = min(liveCount - 1, highlighted + 1); return nil
                    case 126 where liveCount > 0: highlighted = max(0, highlighted - 1); return nil
                    case 36: onPick(); return nil
                    case 53: onClose(); return nil
                    default: return event
                    }
                }
            }
            .onChange(of: count) { _, new in liveCount = new }
            .onDisappear {
                if let monitor { NSEvent.removeMonitor(monitor) }
                monitor = nil
            }
    }
}

extension View {
    /// Down/up move `highlighted` within `0..<count`, Return calls `onPick`, Escape calls `onClose`; any other
    /// key is returned untouched so typing still reaches the search field. Mirror the highlight with
    /// `Color.accentColor.opacity(0.2)` on the row and scroll to it with a `ScrollViewReader`, same as the
    /// existing result rows already do.
    func keyNavigation(count: Int, highlighted: Binding<Int>, onPick: @escaping () -> Void, onClose: @escaping () -> Void) -> some View {
        modifier(KeyNavigationModifier(count: count, highlighted: highlighted, onPick: onPick, onClose: onClose))
    }
}
