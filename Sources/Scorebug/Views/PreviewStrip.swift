// WebKit view of an overlay page from the local server, scaled to fit. Used by PreviewStage.
import SwiftUI
import WebKit

struct OverlayWebView: NSViewRepresentable {
    let url: URL
    let scale: CGFloat
    let size: CGSize

    /// The web view's own magnification scales the page while it keeps laying out at the OBS canvas size
    /// (WebKit's layout viewport is the frame divided by the magnification), so the preview is the exact
    /// page OBS renders, just smaller. Magnification is per page in WebKit and resets to 1 when a navigation
    /// commits, so the coordinator re-applies it on commit and finish.
    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")
        let web = WKWebView(frame: CGRect(origin: .zero, size: CGSize(width: size.width * scale, height: size.height * scale)), configuration: config)
        web.setValue(false, forKey: "drawsBackground")
        web.allowsMagnification = true
        web.navigationDelegate = context.coordinator
        context.coordinator.requestedURL = url
        context.coordinator.scale = scale
        web.load(URLRequest(url: url))
        web.setMagnification(scale, centeredAt: .zero)
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
        var scale: CGFloat = 1
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

        /// A blank preview is worse than a late one: a load that raced the embedded server at launch is retried,
        /// and a view whose content process was terminated is reloaded.
        private func retry(_ web: WKWebView) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak web] in
                guard let web else { return }
                if let url = web.url { web.load(URLRequest(url: url)) } else { web.reload() }
            }
        }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            if (error as NSError).code == NSURLErrorCancelled { return } // superseded by a newer load, nothing to retry
            retry(webView)
        }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { retry(webView) }
        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) { webView.setMagnification(scale, centeredAt: .zero) }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { webView.setMagnification(scale, centeredAt: .zero); finished = true }
        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { webView.reload() }
    }

    func updateNSView(_ web: WKWebView, context: Context) {
        context.coordinator.scale = scale
        if abs(web.magnification - scale) > 0.0001 { web.setMagnification(scale, centeredAt: .zero) }
        if context.coordinator.requestedURL != url { context.coordinator.requestedURL = url; web.load(URLRequest(url: url)) }
    }
}
