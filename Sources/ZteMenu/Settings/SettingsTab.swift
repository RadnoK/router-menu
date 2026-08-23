import Foundation

/// The settings window's tabs, in display order.
///
/// A plain model rather than an inline list so the toolbar and the content
/// switch cannot drift apart, and so the pairing of tab to icon and label is
/// unit testable.
enum SettingsTab: String, CaseIterable, Identifiable, Sendable {
    case general
    case panel
    case battery
    case account
    case updates

    var id: String { rawValue }

    /// SF Symbol shown above the tab's title.
    var symbolName: String {
        switch self {
        case .general: return "gearshape"
        case .panel: return "menubar.rectangle"
        case .battery: return "battery.75percent"
        case .account: return "key"
        case .updates: return "arrow.triangle.2.circlepath"
        }
    }

    var titleKey: LocKey {
        switch self {
        case .general: return .settingsTabGeneral
        case .panel: return .settingsTabPanel
        case .battery: return .settingsTabBattery
        case .account: return .settingsTabAccount
        case .updates: return .settingsTabUpdates
        }
    }

    /// The tabs that make sense for the edited profile's provider — a device
    /// without a battery simply has no battery tab.
    static func visible(for provider: ProviderKind) -> [SettingsTab] {
        let capabilities = ProviderCatalog.descriptor(for: provider).capabilities
        return allCases.filter { $0 != .battery || capabilities.hasBattery }
    }
}
