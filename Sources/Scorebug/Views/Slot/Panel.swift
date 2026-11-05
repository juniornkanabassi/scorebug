import SwiftUI
import ScorebugCore

/// A rounded, full-width block: a small uppercase caption (with an optional trailing accessory, e.g. the
/// Goals block's "Show scorers" switch) over its content. Replaces `Form`'s `Section`, which read far too
/// small at Junior's window scale and buried controls in a cramped list.
struct Panel<Content: View, Accessory: View>: View {
    let caption: String
    let accessory: Accessory
    let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            HStack {
                Text(caption).scaledFont(.caption, weight: .semibold).foregroundStyle(.secondary).tracking(1.2).textCase(.uppercase)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                accessory
            }
            .gridProbe("\(caption)-heading", area: "panel-\(caption)")
            content
                .frame(maxWidth: .infinity, alignment: .leading)
                .gridProbe("\(caption)-content", area: "panel-\(caption)")
        }
        .padding(Space.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Surface.subtleFill, in: RoundedRectangle(cornerRadius: Radius.large))
        .gridArea("panel-\(caption)", inset: Space.lg)
    }
}

extension Panel where Accessory == EmptyView {
    init(_ caption: String, @ViewBuilder content: () -> Content) {
        self.caption = caption; self.accessory = EmptyView(); self.content = content()
    }
}

extension Panel {
    init(_ caption: String, @ViewBuilder accessory: () -> Accessory, @ViewBuilder content: () -> Content) {
        self.caption = caption; self.accessory = accessory(); self.content = content()
    }
}

