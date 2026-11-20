import SwiftUI

// Small controls of the panel. They are drawn in SwiftUI (not AppKit-backed controls) so the same views
// render in ImageRenderer for the preview PNGs and in the real panel.

/// A switch in Volt, like the original. Reads and writes a Bool.
struct PanelSwitch: View {
    @Binding var isOn: Bool
    var label: String

    private let width: CGFloat = 36
    private let height: CGFloat = 20

    var body: some View {
        Button {
            withAnimation(.easeOut(duration: 0.15)) { isOn.toggle() }
        } label: {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule()
                    .fill(isOn ? Theme.volt : Color.primary.opacity(0.18))
                Circle()
                    .fill(isOn ? Theme.navyDeep : Color.white)
                    .shadow(color: .black.opacity(0.25), radius: 1, y: 0.5)
                    .padding(2)
            }
            .frame(width: width, height: height)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityValue(isOn ? "on" : "off")
        .accessibilityAddTraits(.isToggle)
    }
}

/// A quiet text button with a hover highlight (the footer).
struct PanelQuietButtonStyle: ButtonStyle {
    @State private var isHovering = false

    private func highlight(pressed: Bool) -> Double {
        if pressed { return 0.14 }
        return isHovering ? 0.08 : 0
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(isHovering ? Color.primary : Color.secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous)
                    .fill(Color.primary.opacity(highlight(pressed: configuration.isPressed)))
            )
            .contentShape(Rectangle())
            .onHover { isHovering = $0 }
    }
}

/// A small filled button ("Set up", "Copy as image").
struct PanelProminentButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous)
                    .fill(Theme.electric.opacity(configuration.isPressed ? 0.8 : 1))
            )
    }
}

/// The paper edge of a receipt: straight on top, a zigzag along the bottom.
struct PanelTornEdge: Shape {
    var tooth: CGFloat = 7

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        let teeth = max(Int((rect.width / tooth).rounded()), 1)
        let step = rect.width / CGFloat(teeth)
        let baseline = rect.maxY - tooth * 0.6
        path.addLine(to: CGPoint(x: rect.maxX, y: baseline))
        for index in stride(from: teeth, to: 0, by: -1) {
            let right = rect.minX + step * CGFloat(index)
            path.addLine(to: CGPoint(x: right - step / 2, y: rect.maxY))
            path.addLine(to: CGPoint(x: right - step, y: baseline))
        }
        path.closeSubpath()
        return path
    }
}

/// A round symbol badge for the mode rows, 30 pt, lime when the mode is on.
struct PanelModeSymbol: View {
    var systemName: String
    var isOn: Bool

    var body: some View {
        ZStack {
            Circle().fill(isOn ? Theme.volt : Color.primary.opacity(0.1))
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isOn ? Theme.navyDeep : Color.secondary)
        }
        .frame(width: 30, height: 30)
        .accessibilityHidden(true)
    }
}

/// Drives one number with its own animation, so level, pour and foam can each use their own spring.
struct PanelScalarDriver<Content: View>: View, @preconcurrency Animatable {
    var value: Double
    var content: (Double) -> Content

    var animatableData: Double {
        get { value }
        set { value = newValue }
    }

    var body: some View {
        content(value)
    }
}
