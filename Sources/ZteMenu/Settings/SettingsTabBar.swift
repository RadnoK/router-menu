import SwiftUI

/// Icon-and-label tab strip across the top of the settings window.
///
/// Hand-built rather than `TabView`'s: inside a plain `Window` scene, SwiftUI
/// renders tabs in its content style, which draws titles only and drops the
/// `systemImage` entirely. The icon-over-label toolbar look belongs to the
/// `Settings` scene, and that scene cannot be opened programmatically from the
/// menu bar popover — see `ZteMenuApp` and `SettingsWindowTests`.
struct SettingsTabBar: View {
    @Binding var selection: SettingsTab
    let l10n: L10n

    var body: some View {
        HStack(spacing: 2) {
            ForEach(SettingsTab.allCases) { tab in
                SettingsTabButton(tab: tab,
                                  isSelected: tab == selection,
                                  title: l10n(tab.titleKey)) {
                    selection = tab
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity)
        .background(.bar)
    }
}

private struct SettingsTabButton: View {
    let tab: SettingsTab
    let isSelected: Bool
    let title: String
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: tab.symbolName)
                    .font(.system(size: 20, weight: .regular))
                    .frame(height: 22)
                Text(title)
                    .font(.system(size: 11))
                    .lineLimit(1)
            }
            .foregroundStyle(isSelected ? Color.accentColor : .primary)
            .frame(minWidth: 68)
            .padding(.vertical, 5)
            .padding(.horizontal, 6)
            .background(background)
            .contentShape(.rect(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .help(title)
    }

    /// Selection reads as a filled chip; hover only hints, so the two states
    /// stay distinguishable.
    @ViewBuilder
    private var background: some View {
        let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
        if isSelected {
            shape.fill(Color.accentColor.opacity(0.15))
        } else if isHovering {
            shape.fill(Color.primary.opacity(0.07))
        }
    }
}
