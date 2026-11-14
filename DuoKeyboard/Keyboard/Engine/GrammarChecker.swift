import Foundation

/// A suggested fix inside some text. `range` is in Characters (grapheme clusters),
/// which is what `textDocumentProxy.deleteBackward()` removes one at a time.
struct TextIssue {
    enum Kind { case grammar, spelling }
    let range: Range<Int>
    let replacement: String
    let message: String
    let kind: Kind
}

/// Lightweight, offline, rule-based grammar checking for EN/ES/FR/DE. iOS gives
/// third-party keyboards spelling (UITextChecker) but no grammar API, so these
/// rules cover the common mistakes: a/an, "could of", their/there, missing ¿¡,
/// French elision and spacing, German commas before subordinate clauses,
/// German noun capitalisation, repeated words and spacing around punctuation.
enum GrammarChecker {

    private struct Rule {
        let regex: NSRegularExpression
        let message: String
        let build: (NSTextCheckingResult, NSString) -> String?
    }

    private static func re(_ p: String) -> NSRegularExpression {
        // Patterns are compile-time constants; a failure here is a programming error.
        try! NSRegularExpression(pattern: p, options: [.caseInsensitive])
    }

    private static func template(_ pattern: String, _ tmpl: String, _ message: String) -> Rule {
        let r = re(pattern)
        return Rule(regex: r, message: message) { m, s in
            r.replacementString(for: m, in: s as String, offset: 0, template: tmpl)
        }
    }

    private static func group(_ m: NSTextCheckingResult, _ i: Int, _ s: NSString) -> String {
        let r = m.range(at: i)
        return r.location == NSNotFound ? "" : s.substring(with: r)
    }

    // MARK: Shared rules

    private static let repeatExceptions: Set<String> = ["had", "that", "nous", "vous", "is", "die", "der", "das", "sie", "que", "la"]

    private static let common: [Rule] = [
        Rule(regex: re("\\b(\\p{L}+)(\\s+)\\1\\b"), message: "Repeated word") { m, s in
            let w = group(m, 1, s)
            return repeatExceptions.contains(w.lowercased()) ? nil : w
        },
        template("(\\S) {2,}(?=\\S)", "$1 ", "Extra space"),
        template("(\\p{L}),(\\p{L})", "$1, $2", "Missing space after comma"),
    ]

    private static let spaceBeforePunct = template("(\\p{L}) +([,.!?;:])(?=\\s|$)", "$1$2", "Space before punctuation")
    private static let spaceBeforeCommaOnly = template("(\\p{L}) +([,.])(?=\\s|$)", "$1$2", "Space before punctuation")

    // MARK: English

    private static let anExceptions: Set<String> = ["hour", "hours", "honest", "honestly", "honor", "honour", "heir", "herb", "hourly", "honorable", "honourable"]
    private static let aExceptions: Set<String> = ["one", "once", "university", "unique", "unit", "united", "union", "user", "use", "used", "useful", "usual", "usually", "european", "euro", "uniform", "universe", "utility", "ufo", "unicorn", "uk", "us", "usb", "uber"]

    private static let english: [Rule] = [
        Rule(regex: re("\\b(a|an)(\\s+)([\\p{L}\\d]+)"), message: "a / an") { m, s in
            let art = group(m, 1, s), space = group(m, 2, s), next = group(m, 3, s)
            let lower = next.lowercased()
            let vowelSound: Bool
            if anExceptions.contains(lower) { vowelSound = true }
            else if aExceptions.contains(lower) || lower.hasPrefix("uni") || lower.hasPrefix("eu") { vowelSound = false }
            else if next.count <= 3, next == next.uppercased(), let f = next.first, "AEFHILMNORSX".contains(f) { vowelSound = true } // "an FBI agent"
            else { vowelSound = lower.first.map { "aeiou".contains($0) } ?? false }
            let want = vowelSound ? "an" : "a"
            guard art.lowercased() != want else { return nil }
            let fixed = art.first?.isUppercase == true ? want.capitalized : want
            return fixed + space + next
        },
        template("\\b(could|should|would|must|might)\\s+of\\b", "$1 have", "“have”, not “of”"),
        template("\\byour\\s+welcome\\b", "you're welcome", "you're"),
        template("\\bits\\s+(a|an|the|been|not|going|very|so|too|just|really|ok|okay)\\b", "it's $1", "it's = it is"),
        template("\\balot\\b", "a lot", "a lot"),
        template("\\b(more|less|better|worse|bigger|smaller|faster|slower|higher|lower|greater|rather|older|younger)\\s+then\\b", "$1 than", "than (comparison)"),
        template("\\btheir\\s+(is|are|was|were|will)\\b", "there $1", "there"),
        template("\\b(they|we|you)\\s+was\\b", "$1 were", "were"),
        template("\\b(he|she|it)\\s+don't\\b", "$1 doesn't", "doesn't"),
        template("\\b(he|she|it)\\s+have\\b", "$1 has", "has"),
        Rule(regex: re("(?<![\\p{L}'’.])i(?![\\p{L}.'’])"), message: "Capitalise “I”") { m, s in
            s.substring(with: m.range) == "i" ? "I" : nil
        },
        Rule(regex: re("(?<![\\p{L}])i(['’])(m|ll|ve|d)\\b"), message: "Capitalise “I”") { m, s in
            s.substring(with: m.range).first == "i" ? "I" + group(m, 1, s) + group(m, 2, s) : nil
        },
        spaceBeforePunct,
    ]

    // MARK: Spanish

    private static let spanish: [Rule] = [
        template("\\ba\\s+el\\b", "al", "a + el = al"),
        template("\\bde\\s+el\\b", "del", "de + el = del"),
        template("\\bosea\\b", "o sea", "o sea"),
        template("\\bhaiga\\b", "haya", "haya"),
        template("\\bnadien\\b", "nadie", "nadie"),
        template("\\bhalla\\s+(sido|estado|hecho|tenido)\\b", "haya $1", "haya (haber)"),
        spaceBeforePunct,
    ]

    // MARK: French

    private static let hAspire: Set<String> = ["héros", "haricot", "haricots", "hibou", "hache", "haine", "hasard", "haut", "hauts", "haute", "honte", "hors", "hall", "homard", "hockey", "huit", "hamac", "hameau", "hanche", "handicap", "hangar", "harpe", "hérisson", "hollande", "hongrie", "hurler"]

    private static let french: [Rule] = [
        template("\\bsi\\s+il(s?)\\b", "s'il$1", "si il → s'il"),
        template("\\bde\\s+le\\b", "du", "de le → du"),
        template("\\bde\\s+les\\b", "des", "de les → des"),
        template("\\bà\\s+le\\b", "au", "à le → au"),
        template("\\bà\\s+les\\b", "aux", "à les → aux"),
        template("\\bmalgrés\\b", "malgré", "malgré"),
        template("\\bquelque\\s+soit\\b", "quel que soit", "quel que soit"),
        Rule(regex: re("\\b(je|me|te|se|le|la|de|ne|que|jusque|lorsque|puisque)\\s+([aeiouyhâàéèêëîïôûùœ][\\p{L}]*)"), message: "Élision") { m, s in
            let w = group(m, 1, s), next = group(m, 2, s)
            if hAspire.contains(next.lowercased()) { return nil }
            if ["la", "le"].contains(w.lowercased()) && ["un", "une", "onze", "oui"].contains(next.lowercased()) { return nil }
            let stem: String
            switch w.lowercased() {
            case "la", "le": stem = w.first!.isUppercase ? "L" : "l"
            default: stem = String(w.dropLast())
            }
            return stem + "’" + next
        },
        // French typography: narrow no-break space before ; : ! ?
        Rule(regex: re("([\\p{L}\\d»)])([;:!?])(?=\\s|$)"), message: "Espace avant la ponctuation") { m, s in
            let before = s.substring(to: m.range.location).lowercased()
            if before.hasSuffix("http") || before.hasSuffix("https") { return nil }
            return group(m, 1, s) + "\u{202F}" + group(m, 2, s)
        },
        spaceBeforeCommaOnly,
    ]

    // MARK: German

    private static let noCommaBefore: Set<String> = ["und", "oder", "als", "auch", "selbst", "nur", "außer", "ausser", "so", "sowie", "bzw", "aber", "noch"]

    private static let german: [Rule] = [
        Rule(regex: re("(\\p{L}+)\\s+(dass|weil|obwohl|damit|nachdem|sodass|bevor|falls|sobald|während)\\b"), message: "Komma vor Nebensatz") { m, s in
            let prev = group(m, 1, s), conj = group(m, 2, s)
            if noCommaBefore.contains(prev.lowercased()) { return nil }
            return prev + ", " + conj
        },
        template(",\\s*das\\s+(ich|du|er|sie|es|wir|ihr|man)\\b", ", dass $1", "dass (Konjunktion)"),
        template("\\bihr\\s+seit\\b", "ihr seid", "seid (sein)"),
        template("\\bstandart\\b", "Standard", "Standard"),
        template("\\bnähmlich\\b", "nämlich", "nämlich"),
        template("\\bvieleicht\\b", "vielleicht", "vielleicht"),
        template("\\bgarnicht\\b", "gar nicht", "gar nicht"),
        template("\\bdesweiteren\\b", "des Weiteren", "des Weiteren"),
        template("\\bwiederspiegel", "widerspiegel", "wider = gegen"),
        spaceBeforePunct,
    ]

    private static func rules(for lang: KeyboardLanguage) -> [Rule] {
        switch lang {
        case .english: return common + english
        case .spanish: return common + spanish
        case .french: return common + french
        case .german: return common + german
        }
    }

    // MARK: Checking

    /// `isValid` answers "is this a correctly spelled word?" (UITextChecker + dictionary);
    /// it powers German noun capitalisation.
    static func check(_ text: String, language: KeyboardLanguage, isValid: (String) -> Bool) -> [TextIssue] {
        let ns = text as NSString
        var issues: [TextIssue] = []
        for rule in rules(for: language) {
            for m in rule.regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
                guard var replacement = rule.build(m, ns) else { continue }
                let original = ns.substring(with: m.range)
                if original.first?.isUppercase == true, let f = replacement.first, f.isLowercase {
                    replacement = f.uppercased() + replacement.dropFirst()
                }
                guard replacement != original, let r = Range(m.range, in: text) else { continue }
                let start = text.distance(from: text.startIndex, to: r.lowerBound)
                let len = text.distance(from: r.lowerBound, to: r.upperBound)
                issues.append(TextIssue(range: start..<(start + len), replacement: replacement, message: rule.message, kind: .grammar))
            }
        }
        if language == .spanish { issues += invertedMarks(text) }
        if language == .german { issues += germanNouns(text, isValid: isValid) }
        return issues.sorted { $0.range.lowerBound < $1.range.lowerBound }
    }

    /// "Como estas?" → "¿Como estas?"
    private static func invertedMarks(_ text: String) -> [TextIssue] {
        var out: [TextIssue] = []
        let chars = Array(text)
        var sentenceStart = 0
        for (i, c) in chars.enumerated() {
            if c == "?" || c == "!" {
                let opener: Character = c == "?" ? "¿" : "¡"
                var s = sentenceStart
                while s < i, chars[s].isWhitespace { s += 1 }
                let sentence = chars[s..<i]
                if !sentence.contains(opener), let first = sentence.first, first.isLetter {
                    out.append(TextIssue(range: s..<(s + 1), replacement: String(opener) + String(first),
                                         message: "Falta \(opener)", kind: .grammar))
                }
            }
            if ".?!\n".contains(c) { sentenceStart = i + 1 }
        }
        return out
    }

    /// German nouns are capitalised: flag lowercase words whose capitalised form is
    /// the valid one ("ich habe einen hund" → "Hund").
    private static func germanNouns(_ text: String, isValid: (String) -> Bool) -> [TextIssue] {
        var out: [TextIssue] = []
        let r = re("\\b(\\p{Ll}[\\p{L}]{2,})\\b")
        let ns = text as NSString
        for m in r.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            let w = ns.substring(with: m.range)
            let cap = w.prefix(1).uppercased() + w.dropFirst()
            guard !isValid(w), isValid(cap), let range = Range(m.range, in: text) else { continue }
            let start = text.distance(from: text.startIndex, to: range.lowerBound)
            out.append(TextIssue(range: start..<(start + w.count), replacement: cap, message: "Substantiv großschreiben", kind: .grammar))
        }
        return out
    }
}
