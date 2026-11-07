import SwiftUI
import ScorebugCore

/// Live preview of both pages from the local server, so the window shows exactly what OBS shows. SlotView sets
/// its height (drag the handle below it); both panes fit that height, or the width if narrower, never cropped. Takes the base URL directly rather than the whole model, so a command on
/// either slot never invalidates this view (its `updateNSView` already no-ops when nothing changed).
struct PreviewStage: View {
    let slot: Int
    let baseURL: String
    let visible: Bool
    /// Why there is nothing to load (the server is starting or failed to start); nil once it is serving.
    var serverProblem: String? = nil
    var body: some View {
        GeometryReader { geo in
            // Both panes share one height; that height is capped by the width too, so a narrow window scales
            // the pair down instead of clipping the portrait pane at the right edge (Junior, 6 Sep).
            let widthPerHeight: CGFloat = 16.0 / 9 + 9.0 / 16
            let stageH = max(60, min(geo.size.height - 16, (geo.size.width - 16 - 12) / widthPerHeight))
            let hW = stageH * 16 / 9, vW = stageH * 9 / 16
            HStack(spacing: Space.md) {
                Spacer(minLength: 0)
                // `?preview=1` is the only difference from what OBS loads: it is what tells overlay.js this
                // page may show the preview backdrop, which OBS's own browser source (no query) never sees.
                previewPane(path: "h", width: hW, height: stageH, canvas: CGSize(width: 1920, height: 1080))
                previewPane(path: "v", width: vW, height: stageH, canvas: CGSize(width: 1080, height: 1920))
                Spacer(minLength: 0)
            }.padding(Space.sm)
        }
        .frame(maxWidth: .infinity)
        .background(Surface.fill)
    }

    @ViewBuilder
    private func previewPane(path: String, width: CGFloat, height: CGFloat, canvas: CGSize) -> some View {
        Group {
            if NativeSnapshots.isRequested {
                Text("Overlay preview requires the running server")
                    .scaledFont(.caption).foregroundStyle(.secondary).minimumScaleFactor(0.6)
                    .multilineTextAlignment(.center).padding(Space.sm)
                    .frame(width: width, height: height, alignment: .bottom)
                    .background(Surface.fill)
            } else if let serverProblem {
                Text(serverProblem)
                    .scaledFont(.caption).foregroundStyle(.secondary).minimumScaleFactor(0.6)
                    .multilineTextAlignment(.center).padding(Space.sm)
                    .frame(width: width, height: height)
                    .background(Surface.fill)
            } else {
                OverlayWebView(url: URL(string: "\(baseURL)/overlay/\(path)/\(slot)?preview=1")!, scale: width / canvas.width, size: canvas)
                    .frame(width: width, height: height).background(Surface.previewCanvas)
            }
        }
            .clipShape(RoundedRectangle(cornerRadius: Radius.medium))
            .overlay {
                if !visible {
                    Text("Off air").scaledFont(.caption).foregroundStyle(.secondary).padding(.horizontal, Space.md).padding(.vertical, Space.sm)
                        .background(.regularMaterial, in: Capsule())
                }
            }
    }
}
