import SwiftUI

/// The device manager, System-Settings style: the profile list as a sidebar
/// on the left, the selected device's settings filling the right pane.
/// Stored order IS matcher priority — the first matching profile wins, so
/// the rows support drag reordering.
struct DevicesSettingsTab: View {
    @Bindable var settings: SettingsStore
    /// Read-only: marks the profile the last refresh actually matched.
    let store: ModemStore
    let l10n: L10n
    let onNotificationsEnabled: () -> Void

    @State private var confirmingRemoval = false

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 224)

            Divider()

            // `.id` re-creates the detail (and its @State password) when the
            // selection moves to another device — without it, the sign-in
            // field would keep showing the previous device's credential.
            DeviceDetailView(settings: settings, l10n: l10n,
                             onNotificationsEnabled: onNotificationsEnabled)
                .id(settings.profile.id)
                .frame(maxWidth: .infinity)
        }
        // Fixed pane height: the grouped Form on the right scrolls within it,
        // which is exactly System Settings' behaviour.
        .frame(height: 480)
    }

    private var sidebar: some View {
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
            .listStyle(.sidebar)

            Divider()

            // System-Settings-style footer: icon-only add/remove, the
            // localized labels surviving as tooltips.
            HStack(spacing: 12) {
                Menu {
                    ForEach(ProviderKind.allCases, id: \.self) { kind in
                        Button(ProviderCatalog.descriptor(for: kind).displayName) {
                            settings.editedProfileID = settings.settings.addProfile(provider: kind)
                        }
                    }
                } label: {
                    Image(systemName: "plus")
                }
                .menuIndicator(.hidden)
                .fixedSize()
                .help(l10n(.settingsDeviceAdd))

                Button(role: .destructive) {
                    confirmingRemoval = true
                } label: {
                    Image(systemName: "minus")
                }
                .disabled(settings.settings.profiles.count <= 1)
                .help(l10n(.settingsDeviceRemove))
                .confirmationDialog(l10n(.settingsDeviceRemoveConfirm),
                                    isPresented: $confirmingRemoval) {
                    Button(l10n(.settingsDeviceRemove), role: .destructive, action: removeSelected)
                }

                Spacer()
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
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
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(profile.matchMode == .ssid
                        ? "SSID: \(profile.ssid)"
                        : "IP: \(profile.modemIP)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
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
