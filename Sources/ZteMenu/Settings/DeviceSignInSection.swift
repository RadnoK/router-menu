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

            HStack {
                Button(l10n(.settingsTestConnection), action: runTest)
                    .disabled(testState == .testing)
                Spacer()
                testResult
            }
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

    // MARK: Connection test

    /// A live end-to-end check against the device: full login + data read
    /// through the profile's real driver, with whatever is typed in the
    /// fields right now.
    enum TestState: Equatable {
        case idle
        case testing
        case success
        case failure(LocKey)
    }

    @State private var testState: TestState = .idle

    /// Which error copy a failed test shows. Static and pure so it is
    /// unit-testable without a view.
    static func failureKey(for error: Error) -> LocKey {
        if case ModemError.loginFailed = error { return .errorLoginFailed }
        return .errorUnreachable
    }

    @ViewBuilder
    private var testResult: some View {
        switch testState {
        case .idle:
            EmptyView()
        case .testing:
            ProgressView()
                .controlSize(.small)
        case .success:
            Label(l10n(.settingsTestConnectionOK), systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.callout)
        case .failure(let key):
            Label(l10n(key), systemImage: "xmark.circle.fill")
                .foregroundStyle(.red)
                .font(.callout)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    private func runTest() {
        save()
        testState = .testing
        let profile = settings.profile
        let password = password.isEmpty ? nil : password
        Task { @MainActor in
            let driver = ProviderCatalog.descriptor(for: profile.provider)
                .makeDriver(profile, password, SessionHTTP())
            do {
                _ = try await driver.fetch()
                testState = .success
            } catch {
                testState = .failure(Self.failureKey(for: error))
            }
        }
    }

    private func save() {
        // A removal deletes the slot and tears this view down; the disappear-
        // save must not resurrect the credential for a device that is gone.
        guard !password.isEmpty,
              settings.settings.profiles.contains(where: { $0.id == profileID }) else { return }
        Keychain.setPassword(password, for: profileID)
    }
}
