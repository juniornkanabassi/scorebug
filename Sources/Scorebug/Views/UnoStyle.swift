// The look of the window: dark purple-black panels and an orange accent, in the spirit of the Uno control app Junior is used to.
import SwiftUI

enum Uno {
    static let bg = Color(hex: "#15131D")
    static let panel = Color(hex: "#1E1B2A")
    static let panel2 = Color(hex: "#2A2739")
    static let line = Color(hex: "#34304A")
    static let text = Color(hex: "#F2F0F7")
    static let muted = Color(hex: "#9A95AD")
    static let accent = Color(hex: "#FF7A1A")
    static let accent2 = Color(hex: "#FF4E2A")
    static let green = Color(hex: "#2BD576")
    static let red = Color(hex: "#FF3B5C")
    static var accentGradient: LinearGradient { LinearGradient(colors: [accent, accent2], startPoint: .leading, endPoint: .trailing) }
}

struct UnoCard: ViewModifier {
    func body(content: Content) -> some View {
        content.padding(16).background(Uno.panel).clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
extension View { func unoCard() -> some View { modifier(UnoCard()) } }

struct RoundButton: View {
    let symbol: String
    var prominent = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 13, weight: .bold)).foregroundStyle(Uno.text)
                .frame(width: 34, height: 34)
                .background(prominent ? AnyShapeStyle(Uno.accentGradient) : AnyShapeStyle(Uno.panel2))
                .clipShape(Circle())
        }.buttonStyle(.plain)
    }
}

struct ValueBox: View {
    let text: String
    var width: CGFloat = 78
    var body: some View {
        Text(text).font(.system(size: 17, weight: .semibold, design: .rounded)).monospacedDigit().foregroundStyle(Uno.text)
            .frame(width: width, height: 34).background(Uno.panel2).clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct UnoPill: View {
    let title: String
    var filled = false
    var disabled = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(disabled ? Uno.muted : Uno.text)
                .padding(.horizontal, 14).frame(height: 34)
                .background(filled ? AnyShapeStyle(Uno.accentGradient) : AnyShapeStyle(Uno.panel2))
                .clipShape(Capsule())
        }.buttonStyle(.plain).disabled(disabled)
    }
}

struct UnoSwitch: View {
    @Binding var isOn: Bool
    var body: some View {
        Button { isOn.toggle() } label: {
            HStack(spacing: 6) {
                if isOn { Text("ON").font(.system(size: 12, weight: .bold)) }
                Circle().fill(.white).frame(width: 14, height: 14)
                if !isOn { Text("OFF").font(.system(size: 12, weight: .bold)) }
            }
            .foregroundStyle(.white).padding(.horizontal, 10).frame(width: 74, height: 30)
            .background(isOn ? AnyShapeStyle(Uno.accentGradient) : AnyShapeStyle(Uno.panel2))
            .clipShape(Capsule())
        }.buttonStyle(.plain)
    }
}

struct UnoTabBar: View {
    let tabs: [String]
    @Binding var selected: Int
    var body: some View {
        HStack(spacing: 28) {
            ForEach(tabs.indices, id: \.self) { i in
                Button { selected = i } label: {
                    VStack(spacing: 8) {
                        Text(tabs[i]).font(.system(size: 13, weight: selected == i ? .semibold : .regular))
                            .foregroundStyle(selected == i ? Uno.text : Uno.muted)
                        Rectangle().fill(selected == i ? Uno.accent : .clear).frame(height: 2)
                    }
                }.buttonStyle(.plain)
            }
        }
        .padding(.top, 10).frame(maxWidth: .infinity).background(Uno.bg)
        .overlay(alignment: .bottom) { Rectangle().fill(Uno.line).frame(height: 1) }
    }
}

struct FieldRow<Content: View>: View {
    let label: String
    @ViewBuilder let content: Content
    var body: some View {
        HStack(spacing: 14) {
            Text(label).font(.system(size: 14, weight: .medium)).foregroundStyle(Uno.text).frame(width: 130, alignment: .leading)
            content
            Spacer()
        }
    }
}

struct SectionTitle: View {
    let text: String
    var body: some View { Text(text).font(.system(size: 14, weight: .semibold)).foregroundStyle(Uno.text).padding(.top, 6) }
}
