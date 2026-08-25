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
        HStack(alignment: .top, spacing: 12) {
            deviceBox
                .frame(width: 232)

            // `.id` re-creates the detail (and its @State password) when the
            // selection moves to another device — without it, the sign-in
            // field would keep showing the previous device's credential.
            DeviceDetailView(settings: settings, l10n: l10n,
                             onNotificationsEnabled: onNotificationsEnabled)
                .id(settings.profile.id)
                .frame(maxWidth: .infinity)
        }
        .padding(12)
        // Height comes from SettingsView's fixed tab frame; the grouped Form
        // on the right scrolls within it, System Settings style.
    }

    /// The Mail-style device box: a bordered, inset list with the add/remove
    /// strip attached to its bottom edge — one framed control, not a sidebar.
    private var deviceBox: some View {
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
            .listStyle(.inset)
            .scrollContentBackground(.hidden)

            Divider()

            // The classic add/remove strip: bare glyphs split by a hairline,
            // the localized labels surviving as tooltips.
            HStack(spacing: 0) {
                Menu {
                    ForEach(ProviderKind.allCases, id: \.self) { kind in
                        Button(ProviderCatalog.descriptor(for: kind).displayName) {
                            settings.editedProfileID = settings.settings.addProfile(provider: kind)
                        }
                    }
                } label: {
                    Image(systemName: "plus")
                        .frame(width: 24, height: 20)
                        .contentShape(Rectangle())
                }
                .menuIndicator(.hidden)
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help(l10n(.settingsDeviceAdd))

                Divider()
                    .frame(height: 14)

                Button {
                    confirmingRemoval = true
                } label: {
                    Image(systemName: "minus")
                        .frame(width: 24, height: 20)
                        .contentShape(Rectangle())
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
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        )
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
