import Foundation
import Observation

/// Resolves `LocKey` values against the active language's `.lproj` bundle.
///
/// Injected rather than global so tests can build an instance for any language
/// and so a language change re-renders observing views automatically.
@MainActor
@Observable
public final class L10n {
    private(set) var language: AppLanguage
    private let searchBundles: [Bundle]

    /// Where to look for `.lproj` directories, in order: the assembled `.app`
    /// bundle first, then SwiftPM target resources so `swift run` and `swift
    /// test` work without a built bundle.
    ///
    /// `Bundle.module` is added by Task 4, which declares `resources:` on the
    /// `ZteMenu` target in `Package.swift`. That synthesizes the `Bundle.module`
    /// accessor; without it the symbol does not exist and the package fails to
    /// compile. Until then this list is `Bundle.main` only.
    static var defaultBundles: [Bundle] {
        var bundles = [Bundle.main]
        // TODO(Task 4): bundles.append(Bundle.module) once resources: is declared.
        return bundles
    }

    init(language: AppLanguage = .system, bundles: [Bundle] = L10n.defaultBundles) {
        self.language = language
        self.searchBundles = bundles
    }

    var resolvedCode: String { language.resolvedCode }

    /// Used by date and number formatters so they match the interface language.
    var locale: Locale { Locale(identifier: resolvedCode) }

    func setLanguage(_ language: AppLanguage) {
        self.language = language
    }

    func callAsFunction(_ key: LocKey) -> String {
        lookup(key.rawValue)
    }

    func callAsFunction(_ key: LocKey, _ args: CVarArg...) -> String {
        String(format: lookup(key.rawValue), locale: locale, arguments: args)
    }

    /// Resolved `.lproj`, then the English base table, then the raw key. A
    /// missing string stays visible instead of rendering as empty text.
    private func lookup(_ key: String) -> String {
        for code in [resolvedCode, AppLanguage.base] {
            for bundle in searchBundles {
                guard let path = bundle.path(forResource: code, ofType: "lproj"),
                      let lproj = Bundle(path: path) else { continue }
                let value = lproj.localizedString(forKey: key, value: Self.missing, table: nil)
                if value != Self.missing { return value }
            }
        }
        return key
    }

    private static let missing = "\u{0}__missing__"
}
