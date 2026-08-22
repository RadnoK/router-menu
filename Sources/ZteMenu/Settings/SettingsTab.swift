import Foundation

/// The settings window's tabs, in display order.
///
/// A plain model rather than an inline list so the toolbar and the content
/// switch cannot drift apart, and so the pairing of tab to icon and label is
/// unit testable.
enum SettingsTab: String, CaseIterable, Identifiable, Sendable {
    case general
    case panel
    case account
    case updates

    var id: String { rawValue }

    /// SF Symbol shown above the tab's title.
    var symbolName: String {
        switch self {
        case .general: return "gearshape"
        case .panel: return "menubar.rectangle"
        case .account: return "key"
        case .updates: return "arrow.triangle.2.circlepath"
        }
    }

    var titleKey: LocKey {
        switch self {
        case .general: return .settingsTabGeneral
        case .panel: return .settingsTabPanel
        case .account: return .settingsTabAccount
        case .updates: return .settingsTabUpdates
        }
    }
}
