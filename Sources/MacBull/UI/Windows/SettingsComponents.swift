import AppKit
import SwiftUI

/// Small grey explanation under a control.
struct Footnote: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// An icon and a line in a status colour (ready, warning, error).
struct SettingsStatusRow: View {
    let text: String
    let symbol: String
    let color: Color

    var body: some View {
        Label {
            Text(text).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: symbol)
        }
        .font(.callout)
        .foregroundStyle(color)
    }
}

/// A picker over `SettingsOptions` choices.
struct ChoicePicker: View {
    let title: String
    let choices: [SettingsOptions.Choice]
    @Binding var selection: Int

    var body: some View {
        Picker(title, selection: $selection) {
            ForEach(choices) { choice in
                Text(choice.label).tag(choice.value)
            }
        }
    }
}

/// The "Open at login" state, shared by Settings and the welcome flow.
@MainActor
@Observable
final class LoginItemModel {
    private let actions: AppActions
    private(set) var status: LoginItemStatus

    init(actions: AppActions) {
        self.actions = actions
        status = actions.loginItemStatus()
    }

    func refresh() {
        status = actions.loginItemStatus()
    }

    func set(_ enabled: Bool) {
        status = actions.setLoginItem(enabled)
    }

    func openLoginItemsSettings() {
        guard let url = URL(string: LoginItemCopy.loginItemsSettingsURL) else { return }
        NSWorkspace.shared.open(url)
    }
}

/// The approval and failure lines for the login item, with the button into System Settings.
struct LoginItemNotes: View {
    let model: LoginItemModel

    var body: some View {
        switch model.status {
        case .needsApproval:
            VStack(alignment: .leading, spacing: 6) {
                SettingsStatusRow(text: LoginItemCopy.needsApproval, symbol: "exclamationmark.triangle.fill", color: .orange)
                Button("Open Login Items") { model.openLoginItemsSettings() }
            }
        case .failed:
            SettingsStatusRow(text: LoginItemCopy.failed, symbol: "exclamationmark.triangle.fill", color: .orange)
        case .enabled, .disabled:
            EmptyView()
        }
    }
}
