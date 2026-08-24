import SwiftUI

/// The device manager: every configured profile in matcher-priority order,
/// with the selected one edited below. Stored order IS priority — the first
/// matching profile wins, so the rows support drag reordering.
struct DevicesSettingsTab: View {
    @Bindable var settings: SettingsStore
    /// Read-only: marks the profile the last refresh actually matched.
    let store: ModemStore
    let l10n: L10n
    let onNotificationsEnabled: () -> Void

    @State private var confirmingRemoval = false

    var body: some View {
        VStack(spacing: 0) {
            List(selection: Binding(
                get: { settings.editedProfileID ?? settings.settings.profiles.first?.id },
                set: { settings.editedProfileID = $0 }
            )) {
                ForEach(settings.settings.profiles) { profile in
                    row(for: profile).tag(profile.id)
                }
                .onMove { offsets, destination in
                    settings.settings.moveProfiles(fromOffsets: offsets, toOffset: destination)
                }
            }
            .frame(height: 148)

            HStack(spacing: 12) {
                Menu {
                    ForEach(ProviderKind.allCases, id: \.self) { kind in
                        Button(ProviderCatalog.descriptor(for: kind).displayName) {
                            settings.editedProfileID = settings.settings.addProfile(provider: kind)
                        }
                    }
                } label: {
                    Label(l10n(.settingsDeviceAdd), systemImage: "plus")
                }
                .fixedSize()

                Button(role: .destructive) {
                    confirmingRemoval = true
                } label: {
                    Label(l10n(.settingsDeviceRemove), systemImage: "minus")
                }
                .disabled(settings.settings.profiles.count <= 1)
                .confirmationDialog(l10n(.settingsDeviceRemoveConfirm),
                                    isPresented: $confirmingRemoval) {
                    Button(l10n(.settingsDeviceRemove), role: .destructive, action: removeSelected)
                }
                Spacer()
            }
            .buttonStyle(.borderless)
            .labelStyle(.titleAndIcon)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            // `.id` re-creates the detail (and its @State password) when the
            // selection moves to another device — without it, the sign-in
            // field would keep showing the previous device's credential.
            DeviceDetailView(settings: settings, l10n: l10n,
                             onNotificationsEnabled: onNotificationsEnabled)
                .id(settings.profile.id)
        }
    }

    private func row(for profile: ModemProfile) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(store.activeProfile?.id == profile.id ? Color.green : Color.clear)
                .frame(width: 8, height: 8)
                .help(l10n(.settingsDeviceActiveNow))
            VStack(alignment: .leading, spacing: 2) {
                Text(profile.displayTitle)
                Text(profile.matchMode == .ssid
                        ? "SSID: \(profile.ssid)"
                        : "IP: \(profile.modemIP)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(ProviderCatalog.descriptor(for: profile.provider).displayName)
                .font(.caption)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.quaternary, in: Capsule())
        }
        .padding(.vertical, 2)
    }

    private func removeSelected() {
        let id = settings.profile.id
        guard settings.settings.removeProfile(id: id) else { return }
        // The credential dies with the device.
        Keychain.deletePassword(for: id)
        settings.editedProfileID = settings.settings.profiles.first?.id
    }
}
