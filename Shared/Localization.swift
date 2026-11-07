import Foundation

/// App-Sprache: Deutsch oder Englisch. Die Wahl liegt in der App Group, damit das Widget dieselbe Sprache nutzt.
/// Leer bedeutet Systemsprache (Deutsch, wenn das System Deutsch ist, sonst Englisch).
enum Lang {
    static let key = "pref.language"

    static var store: UserDefaults { UserDefaults(suiteName: SharedStore.appGroup) ?? .standard }

    static var code: String {
        let choice = store.string(forKey: key) ?? ""
        if choice == "de" || choice == "en" { return choice }
        return (Locale.preferredLanguages.first ?? "en").hasPrefix("de") ? "de" : "en"
    }

    static var locale: Locale { Locale(identifier: code == "de" ? "de_DE" : "en_US") }

    private static var bundles: [String: Bundle] = [:]

    fileprivate static var bundle: Bundle {
        let code = code
        if let cached = bundles[code] { return cached }
        let found = Bundle.main.path(forResource: code, ofType: "lproj").flatMap(Bundle.init(path:)) ?? .main
        bundles[code] = found
        return found
    }
}

/// Übersetzt einen deutschen Text in die gewählte Sprache. Platzhalter wie %@ und %lld werden mit `args` gefüllt.
func tr(_ key: String, _ args: CVarArg...) -> String {
    let text = Lang.code == "de" ? key : Lang.bundle.localizedString(forKey: key, value: key, table: nil)
    return args.isEmpty ? text : String(format: text, locale: Lang.locale, arguments: args)
}
