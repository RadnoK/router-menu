import SwiftUI

/// The modem's web-panel password, needed only for the total and monthly
/// transfer counters.
///
/// The field saves itself — on submit and when it loses focus — so it behaves
/// like every other control in this window. Only deletion stays an explicit
/// button, because it destroys a stored credential.
struct AccountSettingsTab: View {
    let l10n: L10n

    @State private var password: String
    @FocusState private var focused: Bool

    init(l10n: L10n) {
        self.l10n = l10n
        _password = State(initialValue: Keychain.password() ?? "")
    }

    var body: some View {
        Form {
            Section {
                SecureField(l10n(.settingsPasswordField), text: $password)
                    .focused($focused)
                    .onSubmit(save)
                    .onChange(of: focused) { wasFocused, isFocused in
                        // Save on the focus-lost edge only. Saving on focus-gained
                        // would write the unchanged value back on every visit.
                        if wasFocused && !isFocused { save() }
                    }

                Button(l10n(.settingsDeletePassword), role: .destructive) {
                    Keychain.deletePassword()
                    password = ""
                }
                .disabled(password.isEmpty)
            } footer: {
                Text(l10n(.settingsPasswordHelp))
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        // The window can close while the field still holds focus, which skips
        // the focus-lost edge above.
        .onDisappear(perform: save)
    }

    private func save() {
        guard !password.isEmpty else { return }
        Keychain.setPassword(password)
    }
}
