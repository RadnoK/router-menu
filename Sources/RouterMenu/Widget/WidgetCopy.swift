import Foundation

/// The widget's own strings.
///
/// Not `L10n`: that resolves against `Bundle.main`, which inside an extension
/// is the `.appex` — and it is driven by the app's in-app language picker,
/// whose `UserDefaults` the widget process does not observe. The widget
/// follows the *system* language instead, which is what a Notification Center
/// widget is expected to do, so plain `NSLocalizedString` against its own
/// bundle is both simpler and more correct here.
public enum WidgetCopy {
    public static var noData: String { string(.widgetNoData) }
    public static var noHistoryYet: String { string(.widgetNoHistory) }
    public static var displayName: String { string(.widgetDisplayName) }
    public static var description: String { string(.widgetDescription) }
    public static var justNow: String { string(.widgetJustNow) }

    /// Falls back to the key's English default rather than the raw key, so a
    /// missing translation still renders a sentence.
    private static func string(_ key: LocKey) -> String {
        Bundle.widgetResources.localizedString(
            forKey: key.rawValue, value: fallback[key] ?? key.rawValue, table: nil)
    }

    private static let fallback: [LocKey: String] = [
        .widgetNoData: "No modem data",
        .widgetNoHistory: "No history yet",
        .widgetDisplayName: "Router Menu",
        .widgetDescription: "Battery, signal and transfer of your modem.",
        .widgetJustNow: "just now",
    ]
}

extension Bundle {
    /// The bundle carrying the widget's `.lproj` folders. In the extension
    /// that is the `.appex` itself; in unit tests it is the test bundle.
    static var widgetResources: Bundle { .main }
}
