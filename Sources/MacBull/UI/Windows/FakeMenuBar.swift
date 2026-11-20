import SwiftUI

/// A can for the fake menu bar: body, lid line and pull tab, drawn with paths. The real menu bar icon
/// is owned elsewhere, so this stays a stand-in.
struct CanGlyph: View {
    var body: some View {
        Canvas { context, size in
            let width = size.width * 0.5
            let height = size.height * 0.82
            let body = CGRect(x: (size.width - width) / 2, y: (size.height - height) / 2 + 1, width: width, height: height)
            let outline = Path(roundedRect: body, cornerRadius: 2.2)
            context.stroke(outline, with: .foreground, lineWidth: 1.2)
            var lid = Path()
            lid.move(to: CGPoint(x: body.minX, y: body.minY + 2.4))
            lid.addLine(to: CGPoint(x: body.maxX, y: body.minY + 2.4))
            context.stroke(lid, with: .foreground, lineWidth: 1)
            let tab = CGRect(x: body.midX - 1.2, y: body.minY - 0.4, width: 2.4, height: 1)
            context.fill(Path(roundedRect: tab, cornerRadius: 0.5), with: .foreground)
            let stripe = CGRect(x: body.minX + 1.6, y: body.midY - 0.4, width: width - 3.2, height: 1.1)
            context.fill(Path(roundedRect: stripe, cornerRadius: 0.5), with: .foreground)
        }
        .frame(width: 18, height: 18)
    }
}

/// The picture on the last welcome step: a slice of the menu bar with the can highlighted.
struct FakeMenuBar: View {
    var body: some View {
        HStack(spacing: 14) {
            Spacer(minLength: 0)
            CanGlyph()
                .foregroundStyle(Theme.navyDeep)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Theme.volt, in: RoundedRectangle(cornerRadius: 6))
            Image(systemName: "wifi")
            Image(systemName: "battery.75percent")
            Text("Wed 9:41")
        }
        .font(.system(size: 13))
        .foregroundStyle(.primary)
        .padding(.horizontal, 12)
        .frame(height: 28)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("The MacBull can, lit up, in the menu bar next to wifi, battery and the clock")
    }
}
