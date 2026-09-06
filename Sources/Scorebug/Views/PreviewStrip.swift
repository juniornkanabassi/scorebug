// WebKit view of an overlay page from the local server, scaled to fit. Used by PreviewStage.
import SwiftUI
import WebKit

struct OverlayWebView: NSViewRepresentable {
    let url: URL
    let scale: CGFloat
    let size: CGSize

    /// The web view keeps the exact canvas size OBS gives the page (1920x1080 or 1080x1920) and a scroll view
    /// magnifies it to fit the stage. `pageZoom` used to scale the content while the page laid out at the stage's
    /// own size, so portrait bugs rendered with a different viewport than in OBS and the preview lied.
    func makeNSView(context: Context) -> NSScrollView {
        let config = WKWebViewConfiguration()
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")
        let web = WKWebView(frame: CGRect(origin: .zero, size: size), configuration: config)
        web.setValue(false, forKey: "drawsBackground")
        web.load(URLRequest(url: url))
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = false; scroll.hasHorizontalScroller = false
        scroll.verticalScrollElasticity = .none; scroll.horizontalScrollElasticity = .none
        scroll.allowsMagnification = true
        // NSScrollView clamps magnification to 0.25 by default, which is above the portrait pane's 1080-to-pane
        // scale, so the portrait preview rendered 1.6x too big and clipped (Junior, 6 Sep).
        scroll.minMagnification = 0.02
        scroll.documentView = web
        scroll.magnification = scale
        // View > Reload Previews (⌘R): WebKit can leave a view blank after its window was occluded or on another Space.
        context.coordinator.observer = NotificationCenter.default.addObserver(forName: OverlayWebView.reloadRequested, object: nil, queue: .main) { [weak web] _ in web?.reload() }
        return scroll
    }

    static let reloadRequested = Notification.Name("scorebug.reloadPreviews")
    func makeCoordinator() -> Coordinator { Coordinator() }
    final class Coordinator { var observer: Any?; var lastScale: CGFloat?; deinit { if let o = observer { NotificationCenter.default.removeObserver(o) } } }

    /// Every SwiftUI body evaluation calls this, most with nothing actually different, so each of the three
    /// AppKit side effects (frame, magnification, scroll position) is gated on its own value having changed;
    /// touching the scroll view on every re-render was fighting the user's own drag-to-resize.
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let web = scroll.documentView as? WKWebView else { return }
        var changed = false
        if web.frame.size != size { web.frame = CGRect(origin: .zero, size: size); changed = true }
        if context.coordinator.lastScale != scale { scroll.magnification = scale; context.coordinator.lastScale = scale; changed = true }
        if web.url != url { web.load(URLRequest(url: url)); changed = true }
        if changed { scroll.contentView.scroll(to: .zero) }
    }
}
