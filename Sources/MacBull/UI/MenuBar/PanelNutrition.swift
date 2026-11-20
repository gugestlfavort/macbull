import AppKit
import SwiftUI

/// Label paper and ink in the energy-can palette: frost paper, deep navy ink.
private enum LabelInk {
    static let paper = Theme.frost
    static let ink = Theme.navyDeep
    static let faded = Theme.navyDeep.opacity(0.62)
    static let hairline = Theme.navyDeep.opacity(0.35)
}

/// The label itself, styled like a real nutrition label. Also what "Copy as image" renders.
struct PanelNutritionLabel: View {
    let stats: NutritionStats
    let range: StatsRange

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Nutrition Facts")
                .font(.system(size: 29, weight: .black))
                .tracking(-0.6)
                .foregroundStyle(LabelInk.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text("MacBull, one can at a time")
                .font(.system(size: 11.5))
                .foregroundStyle(LabelInk.faded)
                .padding(.bottom, 4)
            thick(7)
            if NutritionFormat.isEmpty(stats) {
                emptyState
            } else {
                filled
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(LabelInk.paper)
        .overlay(Rectangle().strokeBorder(LabelInk.ink, lineWidth: 1.5))
        .environment(\.colorScheme, .light)
    }

    // MARK: Filled

    private var filled: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Amount \(NutritionFormat.rangePhrase(range))")
                .font(.system(size: 12, weight: .heavy))
                .foregroundStyle(LabelInk.ink)
                .padding(.top, 3)
                .padding(.bottom, 2)
            ForEach(Array(NutritionFormat.rows(stats).enumerated()), id: \.offset) { index, row in
                if index > 0 { hairline }
                rowView(row)
            }
            thick(4)
            ingredients
            empties
        }
    }

    private func rowView(_ row: NutritionRow) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(row.label)
                .font(.system(size: 12.5, weight: .heavy))
                .foregroundStyle(LabelInk.ink)
            if let note = row.note {
                Text(note)
                    .font(.system(size: 11))
                    .foregroundStyle(LabelInk.faded)
            }
            Spacer(minLength: 6)
            Text(row.value)
                .font(.system(size: 12.5, weight: .regular))
                .monospacedDigit()
                .foregroundStyle(LabelInk.ink)
        }
        .padding(.vertical, 3.5)
        .accessibilityElement(children: .combine)
    }

    private var ingredients: some View {
        Text("**Ingredients:** \(NutritionFormat.ingredients(stats.agentMix)).")
            .font(.system(size: 11))
            .foregroundStyle(LabelInk.ink)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 5)
    }

    @ViewBuilder
    private var empties: some View {
        let empties = NutritionFormat.empties(stats.emptiesToday)
        if empties.drawn > 0 {
            HStack(spacing: 2) {
                Text("Empties today")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(LabelInk.ink)
                    .padding(.trailing, 4)
                ForEach(0..<empties.drawn, id: \.self) { _ in
                    Image(nsImage: MenuBarIcon.image(.cutoff))
                        .renderingMode(.template)
                        .resizable()
                        .frame(width: 13, height: 13)
                        .foregroundStyle(LabelInk.ink)
                }
                if empties.more > 0 {
                    Text("+\(empties.more)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(LabelInk.ink)
                        .padding(.leading, 2)
                }
            }
            .padding(.top, 7)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Empties today: \(stats.emptiesToday)")
        }
    }

    // MARK: Empty

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Nothing in this can yet.")
                .font(.system(size: 14, weight: .heavy))
                .foregroundStyle(LabelInk.ink)
            Text("Drag some time into the laptop, or let an agent get to work. Your label fills up as you go.")
                .font(.system(size: 12.5))
                .foregroundStyle(LabelInk.faded)
                .fixedSize(horizontal: false, vertical: true)
            thick(4)
            Text("**Ingredients:** lime, bubbles.")
                .font(.system(size: 11))
                .foregroundStyle(LabelInk.ink)
        }
        .padding(.top, 8)
    }

    // MARK: Rules

    private func thick(_ height: CGFloat) -> some View {
        Rectangle().fill(LabelInk.ink).frame(height: height)
    }

    private var hairline: some View {
        Rectangle().fill(LabelInk.hairline).frame(height: 0.75)
    }
}

/// The back of the panel: the range switch, the label and the copy buttons.
struct PanelNutrition: View {
    let env: AppEnvironment
    let back: () -> Void

    @State private var range: StatsRange
    @State private var stats: NutritionStats
    @State private var copied: String?

    init(env: AppEnvironment, initialRange: StatsRange = .today, back: @escaping () -> Void) {
        self.env = env
        self.back = back
        _range = State(initialValue: initialRange)
        _stats = State(initialValue: env.actions.nutrition(initialRange))
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Button(action: back) {
                    Label("Back", systemImage: "chevron.left")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(PanelQuietButtonStyle())
                Spacer()
                rangeSwitch
            }
            PanelNutritionLabel(stats: stats, range: range)
            HStack(spacing: 8) {
                Button("Copy as image") { copyImage() }
                    .buttonStyle(PanelProminentButtonStyle())
                Button("Copy as text") { copyText() }
                    .buttonStyle(PanelQuietButtonStyle())
                Spacer(minLength: 0)
                if let copied {
                    Text(copied)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(Theme.voltInk)
                        .transition(.opacity)
                }
            }
        }
    }

    private var rangeSwitch: some View {
        HStack(spacing: 2) {
            ForEach(StatsRange.allCases, id: \.self) { option in
                let isSelected = option == range
                Button {
                    range = option
                    stats = env.actions.nutrition(option)
                } label: {
                    Text(NutritionFormat.rangeName(option))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(isSelected ? Theme.navyDeep : Color.primary)
                        .padding(.horizontal, 10)
                        .frame(height: 24)
                        .background(
                            RoundedRectangle(cornerRadius: Theme.Radius.chip - 1, style: .continuous)
                                .fill(isSelected ? Theme.volt : Color.clear)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
                .fill(Color.primary.opacity(0.07))
        )
    }

    // MARK: Copy

    private func copyImage() {
        let renderer = ImageRenderer(content: PanelNutritionLabel(stats: stats, range: range).frame(width: 300).padding(10).background(LabelInk.paper))
        renderer.scale = 2
        guard let image = renderer.nsImage else {
            Log.ui.error("Nutrition label could not be rendered to an image")
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([image])
        confirm("Copied image")
    }

    private func copyText() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(NutritionFormat.text(stats, range: range), forType: .string)
        confirm("Copied text")
    }

    private func confirm(_ message: String) {
        withAnimation(.easeOut(duration: 0.15)) { copied = message }
        Task { @MainActor in
            do {
                try await Task.sleep(for: .seconds(1.6))
            } catch {
                Log.ui.debug("Copy confirmation cut short")
            }
            withAnimation(.easeOut(duration: 0.2)) { copied = nil }
        }
    }
}
