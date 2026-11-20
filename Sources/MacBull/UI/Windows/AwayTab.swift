import SwiftUI

struct AwayTab: View {
    let env: AppEnvironment
    @Bindable private var settings: Settings
    @Bindable private var state: AppState
    @State private var confirmingErase = false

    init(env: AppEnvironment) {
        self.env = env
        settings = env.settings
        state = env.state
    }

    var body: some View {
        Form {
            Section {
                Toggle("Hold agent notifications while I am away", isOn: $settings.bundleWhileAway)
                ChoicePicker(
                    title: "Make a receipt after being away for",
                    choices: SettingsOptions.including(settings.receiptMinAwayMinutes, in: SettingsOptions.minimumAway) { "\($0) min" },
                    selection: $settings.receiptMinAwayMinutes
                )
                Toggle("Show project names in receipts", isOn: $settings.showProjectNames)
                Footnote("When you come back, one receipt tells you what happened. Safety stops and agents that need you still notify at once.")
            }
            Section {
                ChoicePicker(
                    title: "Keep history for",
                    choices: SettingsOptions.including(settings.historyDays, in: SettingsOptions.historyDays) { "\($0) days" },
                    selection: $settings.historyDays
                )
                Button("Erase history\u{2026}", role: .destructive) { confirmingErase = true }
                Footnote("History stays on this Mac. It is what receipts and Nutrition facts are made from.")
            }
            Section("Last receipts") {
                if state.receipts.isEmpty {
                    Text("None yet. One shows up after you have been away and something happened.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(state.receipts.prefix(10)) { receipt in
                        ReceiptRow(receipt: receipt)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .confirmationDialog("Erase all history?", isPresented: $confirmingErase) {
            Button("Erase history", role: .destructive) { env.actions.eraseHistory() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the journal, the receipts and the totals in Nutrition facts. It cannot be undone.")
        }
    }
}

struct ReceiptRow: View {
    let receipt: Receipt

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(AwayFormat.title(receipt))
                Spacer()
                Text(receipt.awayTo.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute()))
                    .foregroundStyle(.secondary)
            }
            Text(AwayFormat.summary(receipt))
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}
