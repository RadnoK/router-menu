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
    case popoverSessionData = "popover.session_data"

    // Popover — pane headers
    case popoverSectionStatus = "popover.section.status"
    case popoverSectionSignal = "popover.section.signal"
    case popoverSectionTransfer = "popover.section.transfer"
    case popoverSectionBattery = "popover.section.battery"

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
    case settingsTabUpdates = "settings.tab.updates"
    case settingsNetworkSection = "settings.network.section"
    case settingsDeviceType = "settings.network.device_type"

    // Settings — device manager
    case settingsTabDevices = "settings.tab.devices"
    case settingsDeviceName = "settings.device.name"
    case settingsDeviceAdd = "settings.device.add"
    case settingsDeviceRemove = "settings.device.remove"
    case settingsDeviceRemoveConfirm = "settings.device.remove_confirm"
    case settingsDeviceActiveNow = "settings.device.active_now"
    case settingsUsernameField = "settings.account.username_field"
    case settingsSignInSection = "settings.signin.section"
    case settingsPasswordHelpRequired = "settings.account.password_help_required"
    case settingsDeviceTabInfo = "settings.device.tab.info"
    case settingsDeviceTabStats = "settings.device.tab.stats"
    case settingsDeviceTabBattery = "settings.device.tab.battery"
    case settingsTestConnection = "settings.device.test_connection"
    case settingsTestConnectionOK = "settings.device.test_connection_ok"
    case settingsDetectionMode = "settings.network.detection_mode"
    case settingsDetectionBySSID = "settings.network.detection_by_ssid"
    case settingsDetectionByIP = "settings.network.detection_by_ip"
    case settingsCurrentNetwork = "settings.network.current"
    case settingsSSIDField = "settings.network.ssid_field"
    case settingsModemIPField = "settings.network.modem_ip_field"
    case settingsSSIDHelp = "settings.network.ssid_help"
    case settingsModemIPHelp = "settings.network.modem_ip_help"

    // Settings — startup
    case settingsLaunchAtLogin = "settings.general.launch_at_login"
    case settingsLaunchAtLoginHelp = "settings.general.launch_at_login_help"
    /// Takes one argument: the system's failure message.
    case settingsLaunchAtLoginError = "settings.general.launch_at_login_error"

    // Settings — menu bar visibility
    case settingsShowWhenDisconnected = "settings.panel.show_when_disconnected"
    case settingsShowWhenDisconnectedHelp = "settings.panel.show_when_disconnected_help"

    // Settings — stats section
    case settingsStatsSection = "settings.stats.section"
    case settingsStatsBasic = "settings.stats.basic"
    case settingsStatsRadio = "settings.stats.radio"
    case settingsStatsTransfer = "settings.stats.transfer"
    case settingsStatsUptime = "settings.stats.uptime"
    case settingsStatsSession = "settings.stats.session"
    case settingsStatsChartsSection = "settings.stats.charts_section"
    case settingsStatsChartTransfer = "settings.stats.chart_transfer"
    case settingsStatsChartSignal = "settings.stats.chart_signal"
    case settingsStatsChartBattery = "settings.stats.chart_battery"

    // Settings — account section
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

    // Settings — about section
    case settingsAboutSection = "settings.about.section"
    case settingsAboutWebsite = "settings.about.website"
    case settingsAboutContact = "settings.about.contact"

    // Settings — appearance section
    case settingsAppearanceSection = "settings.appearance.section"
    case settingsLanguage = "settings.appearance.language"
    case settingsLanguageSystem = "settings.appearance.language_system"
    case settingsLanguagePolish = "settings.appearance.language_polish"
    case settingsLanguageEnglish = "settings.appearance.language_english"

    // Settings — battery tab
    case settingsBatteryMenuBarSection = "settings.battery.menu_bar_section"
    case settingsBatteryShowPercent = "settings.battery.show_percent"
    case settingsBatteryShowPercentHelp = "settings.battery.show_percent_help"
    case settingsBatteryNotificationsSection = "settings.battery.notifications_section"
    case settingsBatteryThresholdsSection = "settings.battery.thresholds_section"
    case settingsBatteryAddThreshold = "settings.battery.add_threshold"
    case settingsBatteryRemoveThreshold = "settings.battery.remove_threshold"
    case settingsBatteryNoThresholds = "settings.battery.no_thresholds"
    case settingsBatteryNormal = "settings.battery.normal"
    case settingsBatteryUrgent = "settings.battery.urgent"
    case settingsBatteryFull = "settings.battery.full"
    /// Takes one argument: the threshold percentage.
    case settingsBatteryThreshold = "settings.battery.threshold"
    case settingsBatteryNotificationsHelp = "settings.battery.notifications_help"

    // Notifications
    case notificationBatteryLowTitle = "notification.battery.low_title"
    /// Takes one argument: the current battery percentage.
    case notificationBatteryLowBody = "notification.battery.low_body"
    case notificationBatteryCriticalTitle = "notification.battery.critical_title"
    /// Takes one argument: the current battery percentage.
    case notificationBatteryCriticalBody = "notification.battery.critical_body"
    case notificationBatteryFullTitle = "notification.battery.full_title"
    case notificationBatteryFullBody = "notification.battery.full_body"

    // Shared
    case placeholderDash = "shared.placeholder_dash"
}
