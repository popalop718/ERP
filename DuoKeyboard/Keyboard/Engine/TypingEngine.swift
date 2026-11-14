import UIKit

/// Spelling, autocorrection, completions, next-word prediction and learning.
/// Combines the bundled frequency dictionary, Apple's on-device UITextChecker
/// (available to keyboard extensions), the user's iOS Text Replacements and
/// contacts (UILexicon), and words/bigrams learned from what the user types.
final class TypingEngine {
    private(set) var language: KeyboardLanguage
    private var lists: [KeyboardLanguage: WordList] = [:]
    private let checker = UITextChecker()
    private var checkerLanguage: String?
    private var validCache: [String: Bool] = [:]

    /// Words from UILexicon (contacts, text replacements) and the user's custom shortcuts.
    private(set) var shortcuts: [String: String] = [:]
    private var lexiconWords: Set<String> = []

    private let store = UserDefaults.standard
    private var bigrams: [String: [String: Int]] = [:]
    private var userWordCounts: [String: Int] = [:]
    private var rejected: Set<String> = []   // words the user un-corrected this session
    private var dirty = false

    var words: WordList { list(for: language) }

    init(language: KeyboardLanguage) {
        self.language = language
        setLanguage(language)
    }

    func setLanguage(_ lang: KeyboardLanguage) {
        persist()
        language = lang
        let available = UITextChecker.availableLanguages
        checkerLanguage = lang.checkerCandidates.first { available.contains($0) }
            ?? available.first { $0.hasPrefix(lang.rawValue) }
        validCache.removeAll()
        bigrams = store.dictionary(forKey: "bigrams.\(lang.rawValue)") as? [String: [String: Int]] ?? [:]
        userWordCounts = store.dictionary(forKey: "userwords.\(lang.rawValue)") as? [String: Int] ?? [:]
        let wl = list(for: lang)
        for (w, n) in userWordCounts where n >= 2 { wl.learn(w) }
        for w in lexiconWords { wl.learn(w, logFreq: -3.5) }
        // Keep at most two dictionaries in memory (keyboard extensions have tight limits).
        if lists.count > 2 {
            for k in lists.keys where k != lang { lists[k] = nil; if lists.count <= 2 { break } }
        }
    }

    private func list(for lang: KeyboardLanguage) -> WordList {
        if let l = lists[lang] { return l }
        let l = WordList(language: lang)
        lists[lang] = l
        return l
    }

    /// Loads iOS Text Replacements + contact names, and the app's own shortcuts.
    func loadLexicon(_ lexicon: UILexicon?, custom: [String: String]) {
        var map: [String: String] = [:]
        for entry in lexicon?.entries ?? [] {
            if entry.userInput.lowercased() != entry.documentText.lowercased() {
                map[entry.userInput.lowercased()] = entry.documentText
            } else {
                lexiconWords.insert(entry.documentText)
                words.learn(entry.documentText, logFreq: -3.5)
            }
        }
        for (k, v) in custom where !k.isEmpty { map[k.lowercased()] = v }
        shortcuts = map
    }

    // MARK: Validity

    func isValid(_ word: String) -> Bool {
        if word.isEmpty { return true }
        if let c = validCache[word] { return c }
        var ok = false
        if word.contains(where: { $0.isNumber }) || lexiconWords.contains(word) { ok = true }
        else if let lang = checkerLanguage {
            let ns = word as NSString
            let r = checker.rangeOfMisspelledWord(in: word, range: NSRange(location: 0, length: ns.length),
                                                  startingAt: 0, wrap: false, language: lang)
            ok = r.location == NSNotFound
        } else {
            ok = words.contains(word)
        }
        if !ok, (userWordCounts[word.lowercased()] ?? 0) >= 2 { ok = true }
        validCache[word] = ok
        return ok
    }

    private func isKnown(_ word: String) -> Bool { words.contains(word) || isValid(word) }

    // MARK: Autocorrection

    /// Returns the replacement for `word` (or nil to keep it) when Space/punctuation is typed.
    func autocorrection(for word: String, previous: String?) -> String? {
        guard word.count >= 1, !rejected.contains(word.lowercased()),
              !word.contains(where: { $0.isNumber }) else { return nil }
        if word.count > 1, word == word.uppercased(), word.contains(where: \.isLetter) { return nil } // acronyms
        let lower = word.lowercased()

        // English "i" → "I", "im" → "I'm" etc.
        if language == .english {
            let iForms: [String: String?] = ["i": "I", "im": "I'm", "ive": "I've", "ill": nil, "id": nil]
            if let f = iForms[lower] { return f.map { applyCase(of: word, to: $0, force: true) } }
        }

        let known = isKnown(word)
        // Same letters, missing apostrophe/accent and far more common ("dont" → "don't", "cafe" → "café").
        let key = WordList.swipeKey(word, language: language)
        if let variant = words.entries(forKey: key).filter({ $0.word != lower }).max(by: { $0.logFreq < $1.logFreq }) {
            let ownFreq = words.logFreq(lower) ?? -7
            if (!isValid(word) || !words.contains(lower)) && variant.logFreq > ownFreq + 0.8 {
                return applyCase(of: word, to: variant.word)
            }
        }
        if known { return nil }

        let candidates = corrections(for: word, previous: previous)
        guard let best = candidates.first else { return nil }
        return best.word == lower ? nil : applyCase(of: word, to: best.word)
    }

    struct Candidate { let word: String; let score: Double }

    /// Ranked spelling candidates: Apple's guesses plus our keyboard-aware edit search.
    func corrections(for word: String, previous: String?) -> [Candidate] {
        let lower = word.lowercased()
        var pool: [String: Double] = [:]
        if let lang = checkerLanguage {
            let ns = word as NSString
            for g in checker.guesses(forWordRange: NSRange(location: 0, length: ns.length), in: word, language: lang) ?? [] {
                pool[g.lowercased()] = 0
            }
        }
        for c in edits1(lower) where words.contains(c) { pool[c] = pool[c] ?? 0 }
        var scored: [Candidate] = []
        for (cand, _) in pool {
            guard cand != lower else { continue }
            let freq = words.logFreq(cand) ?? -6.5
            let dist = Double(weightedDistance(lower, cand))
            var score = freq - 2.2 * dist + bigramBoost(previous: previous, word: cand)
            if cand.first == lower.first { score += 0.4 }
            scored.append(Candidate(word: cand, score: score))
        }
        scored.sort { $0.score > $1.score }
        // Be conservative: only auto-apply confident corrections.
        guard let top = scored.first else { return [] }
        if top.score < -7.5 { return [] }
        return scored
    }

    private static let neighbors: [Character: String] = {
        let rows = ["qwertyuiop", "asdfghjkl", "zxcvbnm"]
        var map: [Character: String] = [:]
        for (r, row) in rows.enumerated() {
            for (i, c) in row.enumerated() {
                var n = ""
                for rr in max(0, r - 1)...min(2, r + 1) {
                    let other = Array(rows[rr])
                    for j in max(0, i - 1)...min(other.count - 1, i + 1) where other[j] != c { n.append(other[j]) }
                }
                map[c] = n
            }
        }
        return map
    }()

    private func edits1(_ w: String) -> Set<String> {
        let chars = Array(w)
        let extra: String
        switch language {
        case .english: extra = "'"
        case .french: extra = "éèêàçùâîôû'"
        case .spanish: extra = "áéíóúüñ"
        case .german: extra = "äöüß"
        }
        let alphabet: [Character] = Array("abcdefghijklmnopqrstuvwxyz" + extra)
        var out = Set<String>()
        for i in 0...chars.count {
            let a: [Character] = Array(chars[..<i])
            let b: [Character] = Array(chars[i...])
            let rest: [Character] = Array(b.dropFirst())
            if !b.isEmpty { out.insert(String(a + rest)) }                                // deletion
            if b.count > 1 {
                let swapped: [Character] = [b[1], b[0]] + Array(b.dropFirst(2))
                out.insert(String(a + swapped))                                           // transposition
            }
            for c in alphabet {
                if !b.isEmpty { out.insert(String(a + [c] + rest)) }                      // substitution
                out.insert(String(a + [c] + b))                                           // insertion
            }
        }
        return out
    }

    /// Edit distance where substituting a neighbouring key or adding an accent is cheap.
    private func weightedDistance(_ a: String, _ b: String) -> Double {
        let x = Array(a), y = Array(b)
        var dp = Array(repeating: Array(repeating: 0.0, count: y.count + 1), count: x.count + 1)
        for i in 0...x.count { dp[i][0] = Double(i) }
        for j in 0...y.count { dp[0][j] = Double(j) }
        guard !x.isEmpty, !y.isEmpty else { return Double(max(x.count, y.count)) }
        for i in 1...x.count {
            for j in 1...y.count {
                let sub: Double
                if x[i - 1] == y[j - 1] { sub = 0 }
                else if String(x[i - 1]).folding(options: .diacriticInsensitive, locale: nil)
                            == String(y[j - 1]).folding(options: .diacriticInsensitive, locale: nil) { sub = 0.2 }
                else if TypingEngine.neighbors[x[i - 1]]?.contains(y[j - 1]) == true { sub = 0.6 }
                else { sub = 1 }
                dp[i][j] = min(dp[i - 1][j] + 1, dp[i][j - 1] + (y[j - 1] == "'" ? 0.2 : 1), dp[i - 1][j - 1] + sub)
                if i > 1, j > 1, x[i - 1] == y[j - 2], x[i - 2] == y[j - 1] { dp[i][j] = min(dp[i][j], dp[i - 2][j - 2] + 0.7) }
            }
        }
        return dp[x.count][y.count]
    }

    func applyCase(of original: String, to word: String, force: Bool = false) -> String {
        var out = word
        if original.count > 1, original == original.uppercased(), original.contains(where: \.isLetter) {
            out = word.uppercased()
        } else if original.first?.isUppercase == true {
            out = word.prefix(1).uppercased() + word.dropFirst()
        }
        return force && word.first?.isUppercase == true ? word : casedForLanguage(out)
    }

    /// German nouns, "I", proper names: pick the capitalisation the spell checker accepts.
    func casedForLanguage(_ word: String) -> String {
        if language == .english, ["i", "i'm", "i'll", "i've", "i'd", "i’m", "i’ll", "i’ve", "i’d"].contains(word) {
            return "I" + word.dropFirst()
        }
        guard let first = word.first, first.isLowercase, word.count > 1 else { return word }
        let cap = word.prefix(1).uppercased() + word.dropFirst()
        if (language == .german || lexiconWords.contains(cap)) && !isValid(word) && isValid(cap) { return cap }
        return word
    }

    // MARK: Predictions

    func completions(prefix: String, previous: String?, limit: Int) -> [String] {
        guard !prefix.isEmpty else { return [] }
        var items = words.completions(prefix: prefix, limit: 40).map { e in
            (word: e.word, score: e.logFreq + bigramBoost(previous: previous, word: e.word))
        }
        items.sort { $0.score > $1.score }
        return items.prefix(limit).map { applyCase(of: prefix, to: $0.word) }
    }

    func nextWords(after previous: String?, limit: Int) -> [String] {
        var out: [String] = []
        if let p = previous?.lowercased(), let next = bigrams[p] {
            out = next.sorted { $0.value > $1.value }.map { $0.key }
        }
        for w in defaultNext where !out.contains(w) { out.append(w) }
        return out.prefix(limit).map { casedForLanguage($0) }
    }

    private var defaultNext: [String] {
        switch language {
        case .english: return ["I", "the", "and", "you", "to", "it"]
        case .spanish: return ["de", "que", "la", "y", "el", "en"]
        case .french: return ["de", "je", "la", "et", "le", "est"]
        case .german: return ["ich", "die", "und", "der", "das", "ist"]
        }
    }

    func bigramBoost(previous: String?, word: String) -> Double {
        guard let p = previous?.lowercased(), let counts = bigrams[p], let n = counts[word.lowercased()] else { return 0 }
        return min(2.0, 0.5 + log2(Double(n + 1)) * 0.4)
    }

    // MARK: Learning

    func learn(word: String, previous: String?) {
        let w = word.lowercased()
        guard w.count > 0, w.count < 40, !w.contains(where: { $0.isNumber }) else { return }
        if let p = previous?.lowercased(), !p.isEmpty {
            var row = bigrams[p] ?? [:]
            row[w, default: 0] += 1
            if row.count > 30, let minKey = row.min(by: { $0.value < $1.value })?.key { row[minKey] = nil }
            bigrams[p] = row
            if bigrams.count > 4000, let k = bigrams.keys.first { bigrams[k] = nil }
        }
        if !words.contains(w) {
            userWordCounts[w, default: 0] += 1
            if userWordCounts[w]! >= 2 { words.learn(w); validCache[w] = nil; validCache[word] = nil }
        }
        dirty = true
    }

    /// The user undid an autocorrection: stop correcting this word and learn it.
    func reject(correctionOf word: String) {
        rejected.insert(word.lowercased())
        userWordCounts[word.lowercased(), default: 0] += 1
        dirty = true
    }

    func persist() {
        guard dirty else { return }
        store.set(bigrams, forKey: "bigrams.\(language.rawValue)")
        store.set(userWordCounts, forKey: "userwords.\(language.rawValue)")
        dirty = false
    }
}
