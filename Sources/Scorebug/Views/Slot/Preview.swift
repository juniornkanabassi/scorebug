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
    /// Below this pane height only the landscape pane is drawn; the portrait one is a strip nobody can read.
    static let portraitMinHeight: CGFloat = 160
    /// Below this pane height the placeholder keeps only its "Drag to enlarge" hint.
    static let captionMinHeight: CGFloat = 120

    var body: some View {
        GeometryReader { geo in
            // Both panes share one height; that height is capped by the width too, so a narrow window scales
            // the pair down instead of clipping the portrait pane at the right edge (Junior, 6 Sep).
            let room = max(60, geo.size.height - 16)
            let bothH = min(room, (geo.size.width - 16 - 12) / (16.0 / 9 + 9.0 / 16))
            let tall = bothH >= Self.portraitMinHeight
            let stageH = max(60, tall ? bothH : min(room, (geo.size.width - 16) * 9 / 16))
            let hW = stageH * 16 / 9, vW = stageH * 9 / 16
            HStack(spacing: Space.md) {
                Spacer(minLength: 0)
                // `?preview=1` is the only difference from what OBS loads: it is what tells overlay.js this
                // page may show the preview backdrop, which OBS's own browser source (no query) never sees.
                previewPane(path: "h", width: hW, height: stageH, canvas: CGSize(width: 1920, height: 1080))
                if tall { previewPane(path: "v", width: vW, height: stageH, canvas: CGSize(width: 1080, height: 1920)) }
                Spacer(minLength: 0)
            }.padding(Space.sm)
            // Once, over the whole stage, not once per pane (B18).
            .overlay {
                if !visible {
                    Text("Off air").scaledFont(.caption, weight: .semibold).foregroundStyle(Surface.fill)
                        .padding(.horizontal, Space.md).padding(.vertical, Space.sm)
                        .background(Surface.stageBadge, in: Capsule())
                        .overlay(Capsule().strokeBorder(Surface.fill, lineWidth: 1))
                }
            }
        }
        .frame(maxWidth: .infinity)
        .background(Surface.fill)
    }

    @ViewBuilder
    private func previewPane(path: String, width: CGFloat, height: CGFloat, canvas: CGSize) -> some View {
        Group {
            if NativeSnapshots.isRequested {
                placeholder("Overlay preview requires the running server", width: width, height: height, alignment: .bottom)
            } else if let serverProblem {
                placeholder(serverProblem, width: width, height: height, alignment: .center)
            } else {
                OverlayWebView(url: URL(string: "\(baseURL)/overlay/\(path)/\(slot)?preview=1")!, scale: width / canvas.width, size: canvas)
                    .frame(width: width, height: height).background(Surface.previewCanvas)
            }
        }
            .clipShape(RoundedRectangle(cornerRadius: Radius.medium))
    }

    /// What a pane says while there is nothing to load: the reason (three lines at most, dropped when the pane is
    /// too short to hold it) and how to get more room.
    private func placeholder(_ caption: String, width: CGFloat, height: CGFloat, alignment: Alignment) -> some View {
        VStack(spacing: Space.xs) {
            if height >= Self.captionMinHeight { Text(caption).lineLimit(3).minimumScaleFactor(0.8) }
            Text("Drag to enlarge").lineLimit(2)
        }
        .scaledFont(.caption).foregroundStyle(.primary).multilineTextAlignment(.center).padding(Space.sm)
        .frame(width: width, height: height, alignment: alignment)
        .background(Surface.fill)
    }
}
