import Foundation

/// "Show Math Results": when the text before the cursor ends in an arithmetic
/// expression followed by "=", offer the result (e.g. "12*(3+4)=" → 84).
enum MathEvaluator {

    static func resultForTrailingExpression(_ text: String, language: KeyboardLanguage) -> String? {
        guard text.hasSuffix("=") else { return nil }
        let body = text.dropLast()
        // Take the longest tail made of math characters.
        let allowed = Set("0123456789.,+-*/×÷x^%() \u{2212}")
        var tail = ""
        for ch in body.reversed() {
            guard allowed.contains(ch) else { break }
            tail.insert(ch, at: tail.startIndex)
        }
        let expr = tail.trimmingCharacters(in: .whitespaces)
        guard expr.contains(where: \.isNumber),
              expr.contains(where: { "+-*/×÷x^%\u{2212}".contains($0) }),
              let value = evaluate(expr, language: language), value.isFinite else { return nil }
        return format(value, language: language)
    }

    static func evaluate(_ raw: String, language: KeyboardLanguage) -> Double? {
        var s = raw.replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "×", with: "*").replacingOccurrences(of: "x", with: "*")
            .replacingOccurrences(of: "÷", with: "/").replacingOccurrences(of: "\u{2212}", with: "-")
        // Comma decimals for es/fr/de ("2,5*2").
        if language != .english && !s.contains(".") { s = s.replacingOccurrences(of: ",", with: ".") }
        else { s = s.replacingOccurrences(of: ",", with: "") }
        var p = Parser(chars: Array(s))
        guard let v = p.expression(), p.i == p.chars.count else { return nil }
        return v
    }

    static func format(_ v: Double, language: KeyboardLanguage) -> String {
        let f = NumberFormatter()
        f.locale = language.locale
        f.numberStyle = .decimal
        f.usesGroupingSeparator = false
        f.maximumFractionDigits = 8
        f.usesSignificantDigits = abs(v) >= 1e12 || (abs(v) < 1e-6 && v != 0)
        f.maximumSignificantDigits = 10
        return f.string(from: NSNumber(value: v)) ?? String(v)
    }

    /// Recursive-descent parser: expr := term (('+'|'-') term)*,
    /// term := power (('*'|'/') power)*, power := unary ('^' power)?, unary := '-' unary | postfix,
    /// postfix := primary '%'?, primary := number | '(' expr ')'.
    private struct Parser {
        let chars: [Character]
        var i = 0

        mutating func expression() -> Double? {
            guard var v = term() else { return nil }
            while i < chars.count, chars[i] == "+" || chars[i] == "-" {
                let op = chars[i]; i += 1
                guard let r = term() else { return nil }
                v = op == "+" ? v + r : v - r
            }
            return v
        }

        mutating func term() -> Double? {
            guard var v = power() else { return nil }
            while i < chars.count, chars[i] == "*" || chars[i] == "/" {
                let op = chars[i]; i += 1
                guard let r = power() else { return nil }
                if op == "/" && r == 0 { return nil }
                v = op == "*" ? v * r : v / r
            }
            return v
        }

        mutating func power() -> Double? {
            guard let base = unary() else { return nil }
            if i < chars.count, chars[i] == "^" {
                i += 1
                guard let e = power() else { return nil }
                return pow(base, e)
            }
            return base
        }

        mutating func unary() -> Double? {
            if i < chars.count, chars[i] == "-" { i += 1; return unary().map { -$0 } }
            if i < chars.count, chars[i] == "+" { i += 1; return unary() }
            guard var v = primary() else { return nil }
            if i < chars.count, chars[i] == "%" { i += 1; v /= 100 }
            return v
        }

        mutating func primary() -> Double? {
            guard i < chars.count else { return nil }
            if chars[i] == "(" {
                i += 1
                let v = expression()
                guard i < chars.count, chars[i] == ")" else { return nil }
                i += 1
                return v
            }
            let start = i
            while i < chars.count, chars[i].isNumber || chars[i] == "." { i += 1 }
            guard i > start else { return nil }
            return Double(String(chars[start..<i]))
        }
    }
}
