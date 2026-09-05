// Live preview of the horizontal and vertical pages, rendered by WebKit from the local server so it matches OBS.
import SwiftUI
import WebKit

struct PreviewStrip: View {
    @EnvironmentObject var model: AppModel
    let slot: Int

    var body: some View {
        GroupBox("Preview") {
            HStack(alignment: .top, spacing: 16) {
                previewBox(orientation: "h", width: 1920, height: 1080, shown: 560)
                previewBox(orientation: "v", width: 1080, height: 1920, shown: 180)
                Spacer()
            }.padding(6)
        }
    }

    private func previewBox(orientation: String, width: CGFloat, height: CGFloat, shown: CGFloat) -> some View {
        let scale = shown / width
        return VStack(alignment: .leading, spacing: 4) {
            OverlayWebView(url: URL(string: "\(model.baseURL)/overlay/\(orientation)/\(slot)")!, scale: scale, size: CGSize(width: width, height: height))
                .frame(width: width * scale, height: height * scale)
                .background(Color(nsColor: .darkGray))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            Text("\(model.baseURL)/overlay/\(orientation)/\(slot)").font(.caption).textSelection(.enabled)
        }
    }
}

struct OverlayWebView: NSViewRepresentable {
    let url: URL
    let scale: CGFloat
    let size: CGSize

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")
        let view = WKWebView(frame: CGRect(origin: .zero, size: size), configuration: config)
        view.setValue(false, forKey: "drawsBackground")
        view.load(URLRequest(url: url))
        return view
    }

    func updateNSView(_ view: WKWebView, context: Context) {
        view.pageZoom = scale
        if view.url != url { view.load(URLRequest(url: url)) }
    }
}
