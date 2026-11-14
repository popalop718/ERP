import Foundation

/// Smart Punctuation: curly quotes in each language's style, ’ apostrophes,
/// "--" → "—", and French no-break spaces before ; : ! ?
enum SmartPunctuation {
    enum Edit {
        case insert(String)
        case replacePrevious(count: Int, with: String)
    }

    static func transform(_ input: String, before: String, language: KeyboardLanguage) -> Edit {
        let prev = before.last
        let opensQuote = prev == nil || prev!.isWhitespace || "([{“‘«„‚-—–/".contains(prev!)
        let q = language.quotes
        switch input {
        case "\"":
            return .insert(opensQuote ? q.open : q.close)
        case "'":
            // Apostrophe inside or after a word; opening single quote otherwise.
            return .insert(opensQuote ? q.singleOpen : "\u{2019}")
        case "-":
            if prev == "-" { return .replacePrevious(count: 1, with: "—") }
            return .insert("-")
        case ";", ":", "!", "?":
            if language == .french, let p = prev, !p.isWhitespace, p != "\u{202F}", p != "\u{00A0}",
               !before.lowercased().hasSuffix("http"), !before.lowercased().hasSuffix("https"), !(p.isNumber && input == ":") {
                return .insert("\u{202F}" + input)
            }
            return .insert(input)
        default:
            return .insert(input)
        }
    }
}
