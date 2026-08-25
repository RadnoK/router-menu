import Foundation

/// The settings window's tabs, in display order.
///
/// A plain model rather than an inline list so the toolbar and the content
/// switch cannot drift apart, and so the pairing of tab to icon and label is
/// unit testable. Per-device settings live inside the Devices tab's detail
/// view, so no tab is capability-gated anymore.
enum SettingsTab: String, CaseIterable, Identifiable, Sendable {
    case general
    case devices
    case updates

    var id: String { rawValue }

    /// SF Symbol shown above the tab's title.
    var symbolName: String {
        switch self {
        case .general: return "gearshape"
        case .devices: return "wifi.router"
        case .updates: return "arrow.triangle.2.circlepath"
        }
    }

    var titleKey: LocKey {
        switch self {
        case .general: return .settingsTabGeneral
        case .devices: return .settingsTabDevices
        case .updates: return .settingsTabUpdates
        }
    }
}
