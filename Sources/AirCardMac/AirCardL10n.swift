import Foundation

enum AirCardL10n {
    static var locale: Locale {
        Locale(identifier: Bundle.main.preferredLocalizations.first ?? Locale.current.identifier)
    }

    static func text(_ key: String) -> String {
        NSLocalizedString(key, bundle: .main, comment: "")
    }

    static func cardName(_ name: String) -> String {
        let prefixes = ["Card ", "Tarjeta "]
        guard let prefix = prefixes.first(where: { name.hasPrefix($0) }),
              let number = Int(name.dropFirst(prefix.count)) else { return name }
        return format("Card %d", number)
    }

    static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: text(key), locale: locale, arguments: arguments)
    }
}
