// WebKit view of an overlay page from the local server, scaled to fit. Used by PreviewStage.
import SwiftUI
import WebKit

struct OverlayWebView: NSViewRepresentable {
    let url: URL
    let scale: CGFloat
    let size: CGSize

    /// The web view keeps the exact canvas size OBS gives the page as its bounds (so the page lays out at
    /// 1920x1080 or 1080x1920) while its frame is the pane size; AppKit scales the view's drawing by the
    /// bounds-to-frame ratio. No WebKit magnification: WebKit resets that per page and clamps small values,
    /// which left the portrait pane unscaled (6 Sep).
    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")
        let web = WKWebView(frame: CGRect(origin: .zero, size: size), configuration: config)
        web.setValue(false, forKey: "drawsBackground")
        web.navigationDelegate = context.coordinator
        context.coordinator.requestedURL = url
        web.load(URLRequest(url: url))
        context.coordinator.watch(web)
        return web
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    static let reloadRequested = Notification.Name("scorebug.reloadPreviews")

    final class Coordinator: NSObject, WKNavigationDelegate {
        private var observers: [Any] = []
        /// The URL last handed to `load`. `WKWebView.url` stays nil until the navigation commits, and a slow first
        /// load restarted on every SwiftUI update never committed at all (both panes blank, 6 Sep).
        var requestedURL: URL?
        private var finished = false

        /// WebKit stops painting a view whose window is occluded or on another Space; reloading once the window is
        /// visible again, or on View > Reload Previews, brings a page back. Nothing is lost, state is the server's.
        func watch(_ web: WKWebView) {
            observers.append(NotificationCenter.default.addObserver(forName: NSWindow.didChangeOcclusionStateNotification, object: nil, queue: .main) { [weak web, weak self] note in
                guard let web, let win = note.object as? NSWindow, win === web.window, win.occlusionState.contains(.visible), self?.finished == true else { return }
                web.reload()
            })
            observers.append(NotificationCenter.default.addObserver(forName: OverlayWebView.reloadRequested, object: nil, queue: .main) { [weak web] _ in web?.reload() })
        }
        deinit { observers.forEach { NotificationCenter.default.removeObserver($0) } }

        private func retry(_ web: WKWebView) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak web] in
                guard let web else { return }
                if let url = web.url { web.load(URLRequest(url: url)) } else { web.reload() }
            }
        }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            if (error as NSError).code == NSURLErrorCancelled { return }
            retry(webView)
        }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { retry(webView) }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { finished = true }
        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { webView.reload() }
    }

    func updateNSView(_ web: WKWebView, context: Context) {
        let frame = CGRect(origin: .zero, size: CGSize(width: size.width * scale, height: size.height * scale))
        if web.frame != frame { web.frame = frame }
        if web.bounds.size != size { web.bounds = CGRect(origin: .zero, size: size) }
        if context.coordinator.requestedURL != url { context.coordinator.requestedURL = url; web.load(URLRequest(url: url)) }
    }
}
