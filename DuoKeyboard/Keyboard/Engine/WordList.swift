import Foundation

/// Frequency-ranked dictionary for one language (top 30k words from the wordfreq
/// project, see README for attribution) plus words the user has taught it.
final class WordList {
    struct Entry {
        let word: String      // display form (lowercase unless proper/German noun cased later)
        let key: String       // letters-only, folded for swipe matching
        var logFreq: Double   // log10 frequency, e.g. -1.3 for "the", -6 for rare words
    }

    let language: KeyboardLanguage
    private(set) var entries: [Entry] = []
    /// Indices into `entries` sorted by `word` for prefix lookups.
    private var sortedByWord: [Int] = []
    /// (first key letter, last key letter) → entry indices, for swipe candidates.
    private var byEnds: [String: [Int]] = [:]
    /// Exact folded key → entry indices (for "dont" → "don't", "cafe" → "café").
    private var byKey: [String: [Int]] = [:]
    private var byWord: [String: Int] = [:]

    init(language: KeyboardLanguage) {
        self.language = language
        load()
    }

    private func load() {
        guard let url = Bundle.main.url(forResource: "words_\(language.rawValue)", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return }
        var list: [Entry] = []
        list.reserveCapacity(30_000)
        for line in text.split(separator: "\n") {
            guard let tab = line.firstIndex(of: "\t") else { continue }
            let w = String(line[..<tab])
            let bucket = Double(line[line.index(after: tab)...]) ?? 600
            list.append(Entry(word: w, key: WordList.swipeKey(w, language: language), logFreq: -bucket / 100))
        }
        entries = list
        reindex()
    }

    private func reindex() {
        byEnds.removeAll(keepingCapacity: true)
        byKey.removeAll(keepingCapacity: true)
        byWord.removeAll(keepingCapacity: true)
        for (i, e) in entries.enumerated() {
            guard let f = e.key.first, let l = e.key.last else { continue }
            byEnds[String([f, l]), default: []].append(i)
            byKey[e.key, default: []].append(i)
            if byWord[e.word] == nil { byWord[e.word] = i }
        }
        sortedByWord = entries.indices.sorted { entries[$0].word < entries[$1].word }
    }

    /// Folds diacritics (except letters that have their own key in this layout),
    /// strips apostrophes/hyphens, lowercases. "Don't" → "dont", "café" → "cafe".
    static func swipeKey(_ word: String, language: KeyboardLanguage) -> String {
        var out = ""
        let native = language.nativeLetters
        for ch in word.lowercased() {
            if native.contains(ch) { out.append(ch); continue }
            if ch == "ß" { out += "ss"; continue }
            if ch == "œ" { out += "oe"; continue }
            if ch == "æ" { out += "ae"; continue }
            guard ch.isLetter else { continue }
            let folded = String(ch).folding(options: [.diacriticInsensitive], locale: nil)
            out += folded
        }
        return out
    }

    func entry(for word: String) -> Entry? {
        byWord[word.lowercased()].map { entries[$0] }
    }

    func contains(_ word: String) -> Bool { byWord[word.lowercased()] != nil }

    func logFreq(_ word: String) -> Double? { entry(for: word)?.logFreq }

    func candidates(first: Character, last: Character) -> [Int] { byEnds[String([first, last])] ?? [] }

    func entries(forKey key: String) -> [Entry] { (byKey[key] ?? []).map { entries[$0] } }

    /// Most frequent words starting with `prefix` (case-insensitive).
    func completions(prefix: String, limit: Int) -> [Entry] {
        let p = prefix.lowercased()
        guard !p.isEmpty else { return [] }
        // Binary search for the first word >= prefix.
        var lo = 0, hi = sortedByWord.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if entries[sortedByWord[mid]].word < p { lo = mid + 1 } else { hi = mid }
        }
        var found: [Entry] = []
        var i = lo
        while i < sortedByWord.count, found.count < 400 {
            let e = entries[sortedByWord[i]]
            guard e.word.hasPrefix(p) else { break }
            if e.word != p { found.append(e) }
            i += 1
        }
        return Array(found.sorted { $0.logFreq > $1.logFreq }.prefix(limit))
    }

    /// Adds (or boosts) a user word so it is suggested, swiped and not "corrected".
    func learn(_ word: String, logFreq: Double = -4.0) {
        let lw = word.lowercased()
        if let i = byWord[lw] {
            entries[i].logFreq = max(entries[i].logFreq, logFreq)
            return
        }
        let key = WordList.swipeKey(lw, language: language)
        guard let f = key.first, let l = key.last else { return }
        entries.append(Entry(word: lw, key: key, logFreq: logFreq))
        let i = entries.count - 1
        byWord[lw] = i
        byEnds[String([f, l]), default: []].append(i)
        byKey[key, default: []].append(i)
        // Insert keeping sortedByWord ordered.
        var lo = 0, hi = sortedByWord.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if entries[sortedByWord[mid]].word < lw { lo = mid + 1 } else { hi = mid }
        }
        sortedByWord.insert(i, at: lo)
    }
}
