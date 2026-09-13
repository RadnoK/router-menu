import SwiftUI

/// Presentation rules the widget shares with the menu bar: the same level
/// means the same symbol and the same colour in both places, so the widget
/// never contradicts the icon a few pixels above it.
enum WidgetBatteryStyle {
    /// SF Symbols' battery family is drawn from discrete fill steps, so the
    /// percentage is mapped onto those rather than passed through as a
    /// variable value — which the battery symbols do not honour.
    static func symbolName(percent: Int?, isCharging: Bool) -> String {
        // `battery.slash` does not exist in this SF Symbols release; the
        // batteryblock variant is the available "no battery reading" glyph.
        guard let percent else { return "minus.plus.batteryblock.slash" }
        if isCharging { return "battery.100percent.bolt" }
        switch percent {
        case ..<13: return "battery.0percent"
        case ..<38: return "battery.25percent"
        case ..<63: return "battery.50percent"
        case ..<88: return "battery.75percent"
        default: return "battery.100percent"
        }
    }

    /// Charging is green whatever the level: the number is on its way up, so
    /// coloring a charging 15 % red would read as a problem that is resolving.
    static func tint(percent: Int?, isCharging: Bool) -> Color {
        guard let percent else { return .secondary }
        if isCharging { return .green }
        switch percent {
        case ..<15: return .red
        case ..<30: return .orange
        default: return .green
        }
    }

    static func percentText(_ percent: Int?) -> String {
        percent.map { "\($0)%" } ?? "—"
    }

    /// Signal bars as a wifi-style glyph, matching the popover's vocabulary.
    static func signalSymbol(bars: Int) -> String {
        // No `cellularbars.slash` in SF Symbols — the antenna family carries
        // the struck-through variant.
        bars <= 0 ? "antenna.radiowaves.left.and.right.slash" : "cellularbars"
    }
}
