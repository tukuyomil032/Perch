// perch/Core/L10n.swift
import Defaults
import Foundation

enum L10n {
    static func string(_ key: String) -> String {
        let lang = Defaults[.languageCode]
        if let value = lookup(key: key, lang: lang) { return value }
        if let value = lookup(key: key, lang: "en") { return value }
        return key
    }

    private static func lookup(key: String, lang: String) -> String? {
        guard
            let path = Bundle.main.path(
                forResource: "Localizable", ofType: "strings",
                inDirectory: nil, forLocalization: lang
            ),
            let dict = NSDictionary(contentsOfFile: path) as? [String: String]
        else { return nil }
        return dict[key]
    }
}
