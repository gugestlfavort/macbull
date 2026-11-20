import SwiftUI

struct AboutTab: View {
    let env: AppEnvironment
    let icon: NSImage
    let version: String

    var body: some View {
        VStack(spacing: 10) {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .frame(width: 112, height: 112)
                .accessibilityHidden(true)
            Text("MacBull")
                .font(.system(size: 26, weight: .bold, design: .rounded))
            Text("Version \(version)")
                .foregroundStyle(.secondary)
            Text("Keeps your Mac awake, lid closed too, and while your AI agents work.")
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)
            Button("Show the welcome again") { env.actions.openWelcome(.hello) }
                .buttonStyle(.link)
                .padding(.top, 4)
            Text("MIT License. \u{00A9} 2026 MacBull.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.top, 8)
        }
        .padding(.horizontal, 40)
        .padding(.vertical, 28)
        .frame(maxWidth: .infinity)
    }
}
