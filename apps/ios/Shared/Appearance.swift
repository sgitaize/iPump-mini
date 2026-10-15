// SPDX-License-Identifier: GPL-3.0-or-later
// Language and appearance settings, shared between the app and its widgets
// (App Group user defaults; falls back to the app's own defaults without App Group).
import SwiftUI

enum AppLanguage: String, CaseIterable, Identifiable {
    case system, de, en
    var id: String { rawValue }
}

enum AppTheme: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

/// Glucose unit for display. Upload and API stay in mg/dL (Nightscout convention).
enum GlucoseUnit: String, CaseIterable, Identifiable {
    case mgdl, mmol
    var id: String { rawValue }
    var label: String { self == .mgdl ? "mg/dL" : "mmol/L" }

    func format(_ mgdl: Int) -> String {
        self == .mgdl ? "\(mgdl)" : String(format: "%.1f", Double(mgdl) / 18.0182)
    }

    func formatDelta(_ d: Int?) -> String {
        guard let d else { return "" }
        if self == .mgdl { return d > 0 ? "+\(d)" : d == 0 ? "±0" : "\(d)" }
        let v = Double(d) / 18.0182
        return abs(v) < 0.05 ? "±0,0" : String(format: "%+.1f", v)
    }
}

/// Colours by target range: low red, high orange, in range neutral.
enum RangeColor {
    static func color(_ mgdl: Int, low: Int, high: Int, neutral: Color) -> Color {
        mgdl < low ? .red : mgdl > high ? .orange : neutral
    }
}

/// Widget look: plain system background or tinted by the current range.
enum WidgetStyle: String, CaseIterable, Identifiable {
    case plain, tinted
    var id: String { rawValue }
}

enum Prefs {
    static let languageKey = "appLanguage"
    static let themeKey = "appTheme"
    static let unitKey = "glucoseUnit"
    static let lowKey = "rangeLow"
    static let highKey = "rangeHigh"
    static let widgetStyleKey = "widgetStyle"
    static let widgetShowIOBKey = "widgetShowIOB"
    static let widgetHoursKey = "widgetHours"

    /// App Group defaults so the widgets see the same settings.
    static let defaults: UserDefaults = {
        if let id = SharedStore.groupID, let d = UserDefaults(suiteName: id),
           FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: id) != nil {
            return d
        }
        return .standard
    }()

    static var language: AppLanguage { AppLanguage(rawValue: defaults.string(forKey: languageKey) ?? "") ?? .system }
    static var theme: AppTheme { AppTheme(rawValue: defaults.string(forKey: themeKey) ?? "") ?? .system }
    static var unit: GlucoseUnit { GlucoseUnit(rawValue: defaults.string(forKey: unitKey) ?? "") ?? .mgdl }
    static var low: Int { (defaults.object(forKey: lowKey) as? Int) ?? 70 }
    static var high: Int { (defaults.object(forKey: highKey) as? Int) ?? 180 }
    static var widgetStyle: WidgetStyle { WidgetStyle(rawValue: defaults.string(forKey: widgetStyleKey) ?? "") ?? .plain }
    static var widgetShowIOB: Bool { (defaults.object(forKey: widgetShowIOBKey) as? Bool) ?? true }
    static var widgetHours: Int { (defaults.object(forKey: widgetHoursKey) as? Int) ?? 3 }
}

/// Localisation with an in-app language switch. SwiftUI texts follow the `locale`
/// environment set at the root; strings built in code use `L10n.tr`.
/// German is the development language: the keys are the German texts.
enum L10n {
    /// "de" or "en". "system" follows the device: German if it is the first preferred
    /// language among de/en, otherwise English.
    static var code: String {
        switch Prefs.language {
        case .de: return "de"
        case .en: return "en"
        case .system:
            for lang in Locale.preferredLanguages {
                if lang.hasPrefix("de") { return "de" }
                if lang.hasPrefix("en") { return "en" }
            }
            return "en"
        }
    }

    static var locale: Locale { Locale(identifier: code == "de" ? "de_DE" : "en_US") }

    private static var cache: (String, Bundle?)?
    private static var bundle: Bundle? {
        if let cache, cache.0 == code { return cache.1 }
        let b = Bundle.main.path(forResource: code, ofType: "lproj").flatMap(Bundle.init(path:))
        cache = (code, b)
        return b
    }

    static func tr(_ key: String, _ args: CVarArg...) -> String {
        let format = bundle?.localizedString(forKey: key, value: key, table: nil) ?? key
        return args.isEmpty ? format : String(format: format, locale: locale, arguments: args)
    }
}

extension View {
    /// Applies language and theme from the settings.
    func appPreferences(language: String, theme: String) -> some View {
        environment(\.locale, L10n.locale)
            .preferredColorScheme(AppTheme(rawValue: theme)?.colorScheme)
            .id(language)
    }
}
