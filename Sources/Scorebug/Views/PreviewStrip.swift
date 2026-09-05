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
        scroll.documentView = web
        scroll.magnification = scale
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let web = scroll.documentView as? WKWebView else { return }
        if web.frame.size != size { web.frame = CGRect(origin: .zero, size: size) }
        if abs(scroll.magnification - scale) > 0.0001 { scroll.magnification = scale }
        scroll.contentView.scroll(to: .zero)
        if web.url != url { web.load(URLRequest(url: url)) }
    }
}
