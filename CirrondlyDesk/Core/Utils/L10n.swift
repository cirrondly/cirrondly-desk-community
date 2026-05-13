import Foundation

enum L10n {
    static func tr(_ key: String, comment: String = "") -> String {
        NSLocalizedString(key, comment: comment)
    }

    static func tr(_ key: String, _ arguments: CVarArg..., comment: String = "") -> String {
        let format = NSLocalizedString(key, comment: comment)
        return String(format: format, locale: Locale.current, arguments: arguments)
    }
}