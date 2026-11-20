import SwiftUI

/// The receipt's paper and ink. Always a light paper, like a real till roll, in light and dark mode.
private enum PaperInk {
    static let paper = Color(hex: 0xFBF8EF)
    static let ink = Color(hex: 0x1D2230)
    static let faded = Color(hex: 0x1D2230).opacity(0.55)
    static let rule = Color(hex: 0x1D2230).opacity(0.28)
}

private struct RowsHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct ReceiptStartsExpandedKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// Lets a render open the receipt with "Show all" already pressed.
    var receiptStartsExpanded: Bool {
        get { self[ReceiptStartsExpandedKey.self] }
        set { self[ReceiptStartsExpandedKey.self] = newValue }
    }
}

/// The lines of one receipt, in a monospaced face. Used by the card and the history.
struct PanelReceiptBody: View {
    let receipt: Receipt

    @Environment(\.receiptStartsExpanded) private var startsExpanded
    @State private var expandedByUser: Bool?
    @State private var rowsHeight: CGFloat = 0

    private var isExpanded: Bool { expandedByUser ?? startsExpanded }

    var body: some View {
        let rows = ReceiptFormat.rows(receipt.lines)
        let shown = ReceiptFormat.visible(rows, expanded: isExpanded)
        VStack(alignment: .leading, spacing: 5) {
            if receipt.lines.isEmpty {
                line("Nothing was running")
            }
            rowList(shown.rows)
            if rows.count > ReceiptFormat.collapsedRowLimit {
                Button(isExpanded ? ReceiptFormat.showLessTitle : ReceiptFormat.showAllTitle(total: rows.count)) {
                    expandedByUser = !isExpanded
                }
                .buttonStyle(.plain)
                .font(.system(size: 11.5, weight: .bold, design: .monospaced))
                .foregroundStyle(PaperInk.ink)
                .underline()
                .accessibilityHint(isExpanded ? "Shows fewer rows" : "Shows every row")
            }
            let notes = ReceiptFormat.notes(receipt)
            if !notes.isEmpty {
                PanelDashedRule()
                ForEach(notes, id: \.self) { note in
                    line(note)
                }
            }
        }
    }

    /// The rows. Expanded, they scroll inside a fixed maximum height so the panel never grows past it.
    @ViewBuilder
    private func rowList(_ rows: [ReceiptFormat.Row]) -> some View {
        let list = VStack(alignment: .leading, spacing: 5) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                rowView(row)
            }
        }
        if isExpanded {
            ScrollView(.vertical) {
                list.frame(maxWidth: .infinity, alignment: .leading)
                    .background(GeometryReader { proxy in
                        Color.clear.preference(key: RowsHeightKey.self, value: proxy.size.height)
                    })
            }
            .frame(height: min(max(rowsHeight, 1), ReceiptFormat.expandedMaxHeight))
            .onPreferenceChange(RowsHeightKey.self) { rowsHeight = $0 }
        } else {
            list
        }
    }

    private func rowView(_ row: ReceiptFormat.Row) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(ReceiptFormat.title(row))
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(PaperInk.ink)
                .lineLimit(1)
                .truncationMode(.middle)
            if let detail = ReceiptFormat.detail(row) {
                Text(detail)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(PaperInk.faded)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func line(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11.5, design: .monospaced))
            .foregroundStyle(PaperInk.ink)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct PanelDashedRule: View {
    var body: some View {
        Rectangle()
            .fill(Color.clear)
            .frame(height: 1)
            .overlay(
                Line().stroke(PaperInk.rule, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            )
            .padding(.vertical, 2)
    }

    private struct Line: Shape {
        func path(in rect: CGRect) -> Path {
            var path = Path()
            path.move(to: CGPoint(x: rect.minX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            return path
        }
    }
}

/// "While you were away", at the top of the panel until it is dismissed.
struct PanelReceiptCard: View {
    let receipt: Receipt
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("WHILE YOU WERE AWAY")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .tracking(0.6)
                        .foregroundStyle(PaperInk.ink)
                    Text("Away \(ReceiptFormat.away(receipt)), \(PanelFormat.clock(receipt.awayFrom)) to \(PanelFormat.clock(receipt.awayTo))")
                        .font(.system(size: 11.5, design: .monospaced))
                        .foregroundStyle(PaperInk.faded)
                }
                Spacer(minLength: 6)
                Button(action: dismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(PaperInk.faded)
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss receipt")
            }
            PanelDashedRule()
            PanelReceiptBody(receipt: receipt)
            PanelDashedRule()
            Text(ReceiptFormat.summary(receipt).uppercased())
                .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                .tracking(0.4)
                .foregroundStyle(PaperInk.ink)
        }
        .padding(.horizontal, 14)
        .padding(.top, 11)
        .padding(.bottom, 19)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            PanelTornEdge()
                .fill(PaperInk.paper)
                .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
        )
        .accessibilityElement(children: .contain)
    }
}

/// The saved receipts, most recent first. Each row opens to the full receipt.
struct PanelReceiptHistory: View {
    let receipts: [Receipt]
    let back: () -> Void

    @State private var expanded: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Button(action: back) {
                    Label("Back", systemImage: "chevron.left")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(PanelQuietButtonStyle())
                Spacer()
                Text("Receipts")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                // Keeps the title centred
                Color.clear.frame(width: 60, height: 1)
            }
            if receipts.isEmpty {
                Text("No receipts yet. When you come back from a long break, MacBull keeps the summary here.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.bottom, 6)
            } else {
                VStack(spacing: 8) {
                    ForEach(receipts) { receipt in
                        row(receipt)
                    }
                }
            }
        }
    }

    private func row(_ receipt: Receipt) -> some View {
        let isOpen = expanded == receipt.id
        return VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(.easeOut(duration: 0.18)) {
                    expanded = isOpen ? nil : receipt.id
                }
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(receipt.awayFrom.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute()))
                            .font(.system(size: 11.5, weight: .bold, design: .monospaced))
                            .foregroundStyle(PaperInk.ink)
                        Text("Away \(ReceiptFormat.away(receipt)): \(ReceiptFormat.summary(receipt))")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(PaperInk.faded)
                            .multilineTextAlignment(.leading)
                    }
                    Spacer(minLength: 4)
                    Image(systemName: isOpen ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(PaperInk.faded)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(isOpen ? "Hides the details" : "Shows the details")
            if isOpen {
                PanelDashedRule()
                PanelReceiptBody(receipt: receipt)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
                .fill(PaperInk.paper)
        )
    }
}
