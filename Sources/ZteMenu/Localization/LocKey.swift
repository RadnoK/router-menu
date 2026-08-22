import Foundation

/// Every user-facing string in the app, as a type. A typo is a compile error
/// rather than a key rendered raw at runtime.
enum LocKey: String, CaseIterable, Sendable {
    // Popover — states
    case popoverNoConnection = "popover.no_connection"
    case popoverLocationDenied = "popover.location_denied"

    // Popover — rows
    case popoverBattery = "popover.battery"
    case popoverSignal = "popover.signal"
    case popoverNetwork = "popover.network"
    case popoverDownload = "popover.download"
    case popoverUpload = "popover.upload"
    case popoverMonthly = "popover.monthly"
    case popoverTotal = "popover.total"
    case popoverSession = "popover.session"

    // Popover — actions
    case popoverRefresh = "popover.refresh"
    case popoverSettings = "popover.settings"
    case popoverQuit = "popover.quit"

    // Signal quality
    case signalNone = "signal.none"
    case signalVeryWeak = "signal.very_weak"
    case signalWeak = "signal.weak"
    case signalMedium = "signal.medium"
    case signalGood = "signal.good"
    case signalVeryGood = "signal.very_good"

    // Errors
    case errorLoginFailed = "error.login_failed"
    case errorUnreachable = "error.unreachable"

    // Settings — window and network section
    case settingsWindowTitle = "settings.window_title"

    // Tab names.
    case settingsTabGeneral = "settings.tab.general"
    case settingsTabPanel = "settings.tab.panel"
    case settingsTabAccount = "settings.tab.account"
    case settingsTabUpdates = "settings.tab.updates"
    case settingsNetworkSection = "settings.network.section"
    case settingsDetectionMode = "settings.network.detection_mode"
    case settingsDetectionBySSID = "settings.network.detection_by_ssid"
    case settingsDetectionByIP = "settings.network.detection_by_ip"
    case settingsCurrentNetwork = "settings.network.current"
    case settingsSSIDField = "settings.network.ssid_field"
    case settingsModemIPField = "settings.network.modem_ip_field"
    case settingsSSIDHelp = "settings.network.ssid_help"
    case settingsModemIPHelp = "settings.network.modem_ip_help"

    // Settings — stats section
    case settingsStatsSection = "settings.stats.section"
    case settingsStatsBasic = "settings.stats.basic"
    case settingsStatsRadio = "settings.stats.radio"
    case settingsStatsTransfer = "settings.stats.transfer"
    case settingsStatsUptime = "settings.stats.uptime"

    // Settings — account section
    case settingsAccountSection = "settings.account.section"
    case settingsPasswordField = "settings.account.password_field"
    case settingsDeletePassword = "settings.account.delete_password"
    case settingsPasswordHelp = "settings.account.password_help"

    // Settings — updates section
    case settingsUpdatesSection = "settings.updates.section"
    case settingsVersion = "settings.updates.version"
    case settingsBuild = "settings.updates.build"
    case settingsAutoCheck = "settings.updates.auto_check"
    case settingsFrequency = "settings.updates.frequency"
    case settingsFrequencyDaily = "settings.updates.frequency_daily"
    case settingsFrequencyWeekly = "settings.updates.frequency_weekly"
    case settingsAutoDownload = "settings.updates.auto_download"
    case settingsCheckNow = "settings.updates.check_now"
    case settingsNeverChecked = "settings.updates.never_checked"
    /// Takes one argument: the relative date, e.g. "2 hours ago".
    case settingsLastChecked = "settings.updates.last_checked"

    // Settings — appearance section
    case settingsAppearanceSection = "settings.appearance.section"
    case settingsLanguage = "settings.appearance.language"
    case settingsLanguageSystem = "settings.appearance.language_system"
    case settingsLanguagePolish = "settings.appearance.language_polish"
    case settingsLanguageEnglish = "settings.appearance.language_english"

    // Shared
    case placeholderDash = "shared.placeholder_dash"
}
