import SwiftUI

/// The device's panel credentials. The password lives in the profile's own
/// Keychain slot; the username is stored on the profile and shown only for
/// providers whose login has one.
///
/// The field saves itself — on submit and when it loses focus — so it
/// behaves like every other control. Only deletion stays an explicit
/// button, because it destroys a stored credential.
struct DeviceSignInSection: View {
    @Bindable var settings: SettingsStore
    let l10n: L10n

    private let profileID: UUID
    @State private var password: String
    @FocusState private var focused: Bool

    init(settings: SettingsStore, l10n: L10n) {
        self.settings = settings
        self.l10n = l10n
        let id = settings.profile.id
        self.profileID = id
        _password = State(initialValue: Keychain.password(for: id) ?? "")
    }

    private var capabilities: ModemCapabilities {
        ProviderCatalog.descriptor(for: settings.profile.provider).capabilities
    }

    var body: some View {
        Section {
            if capabilities.needsUsername {
                TextField(l10n(.settingsUsernameField), text: $settings.profile.username)
            }
            SecureField(l10n(.settingsPasswordField), text: $password)
                .focused($focused)
                .onSubmit(save)
                .onChange(of: focused) { wasFocused, isFocused in
                    if wasFocused && !isFocused { save() }
                }

            Button(l10n(.settingsDeletePassword), role: .destructive) {
                Keychain.deletePassword(for: profileID)
                password = ""
            }
            .disabled(password.isEmpty)
        } header: {
            Text(l10n(.settingsSignInSection))
        } footer: {
            Text(l10n(capabilities.passwordRole == .requiredForAll
                        ? .settingsPasswordHelpRequired
                        : .settingsPasswordHelp))
                .foregroundStyle(.secondary)
        }
        .onDisappear(perform: save)
    }

    private func save() {
        guard !password.isEmpty else { return }
        Keychain.setPassword(password, for: profileID)
    }
}
