import Foundation

/// Languages supported by Duo Keyboard. Each has its own physical-style layout
/// (QWERTY / QWERTY-ñ / AZERTY / QWERTZ), dictionary, grammar rules and quotes.
enum KeyboardLanguage: String, CaseIterable, Codable, Identifiable {
    case english = "en"
    case spanish = "es"
    case french = "fr"
    case german = "de"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .english: return "English"
        case .spanish: return "Español"
        case .french: return "Français"
        case .german: return "Deutsch"
        }
    }

    var shortCode: String { rawValue.uppercased() }

    var layoutName: String {
        switch self {
        case .english: return "QWERTY"
        case .spanish: return "QWERTY (Español)"
        case .french: return "AZERTY"
        case .german: return "QWERTZ"
        }
    }

    /// Preferred UITextChecker language identifiers, most specific first.
    var checkerCandidates: [String] {
        switch self {
        case .english: return ["en_US", "en_GB", "en"]
        case .spanish: return ["es_ES", "es_MX", "es"]
        case .french: return ["fr_FR", "fr_CA", "fr"]
        case .german: return ["de_DE", "de_CH", "de"]
        }
    }

    var locale: Locale { Locale(identifier: checkerCandidates[0]) }

    /// Opening / closing double and single quotes used by Smart Punctuation.
    var quotes: (open: String, close: String, singleOpen: String, singleClose: String) {
        switch self {
        case .english, .spanish: return ("\u{201C}", "\u{201D}", "\u{2018}", "\u{2019}")
        case .french: return ("\u{00AB}\u{202F}", "\u{202F}\u{00BB}", "\u{2039}\u{202F}", "\u{202F}\u{203A}")
        case .german: return ("\u{201E}", "\u{201C}", "\u{201A}", "\u{2018}")
        }
    }

    /// Characters that sit on their own letter key in this layout. Swipe matching keeps
    /// these distinct; every other accented letter folds to its base key.
    var nativeLetters: Set<Character> {
        switch self {
        case .english: return []
        case .spanish: return ["ñ"]
        case .french: return ["ù"]
        case .german: return ["ä", "ö", "ü"]
        }
    }

    /// Decimal separator used when showing math results.
    var decimalSeparator: String { self == .english ? "." : "," }
}
