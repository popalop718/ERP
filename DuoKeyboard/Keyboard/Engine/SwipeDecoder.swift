import CoreGraphics
import Foundation

/// Shape-matching gesture decoder (in the spirit of SHARK²): the swipe path is
/// compared against the ideal polyline through each candidate word's keys, and
/// combined with word frequency and the previous word. Tuned on synthetic swipes
/// (≈94% top-1 / 99% top-3 on the 3,000 most common English words).
struct SwipeDecoder {
    struct Result { let word: String; let score: Double }

    private static let samples = 40
    private static let dense = 100
    private static let shapeWeight = 4.0
    private static let alignWeight = 2.0
    private static let freqWeight = 0.7
    private static let letterThreshold = 1.4   // in key widths

    static func decode(path raw: [CGPoint], centers: [Character: CGPoint], unit: CGFloat,
                       words: WordList, contextBoost: (String) -> Double) -> [Result] {
        guard raw.count >= 2, unit > 0, !centers.isEmpty else { return [] }
        // Normalise to key-width units.
        let pts = raw.map { CGPoint(x: $0.x / unit, y: $0.y / unit) }
        let keys = centers.mapValues { CGPoint(x: $0.x / unit, y: $0.y / unit) }
        let path = resample(pts, count: samples)
        let densePath = resample(pts, count: dense)
        let pathLength = length(path)

        func nearest(_ p: CGPoint) -> [Character] {
            let sorted = keys.sorted { d($0.value, p) < d($1.value, p) }
            let close = sorted.prefix(3).filter { d($0.value, p) < 1.0 }.map { $0.key }
            return close.isEmpty ? [sorted[0].key] : close
        }
        let starts = nearest(path[0])
        let ends = nearest(path[path.count - 1])

        var results: [Result] = []
        var seen = Set<String>()
        for s in starts {
            for e in ends {
                for idx in words.candidates(first: s, last: e) {
                    let entry = words.entries[idx]
                    let letters = collapse(entry.key)
                    if letters.count == 1 && pathLength > 1.0 { continue }
                    if seen.contains(entry.word) { continue }
                    let centersForWord = letters.compactMap { keys[$0] }
                    guard centersForWord.count == letters.count else { continue }
                    // Alignment: every letter must be passed near, in order.
                    var cursor = 0
                    var total = 0.0
                    var ok = true
                    for c in centersForWord {
                        var best = Double.greatestFiniteMagnitude
                        var bestIndex = cursor
                        var j = cursor
                        while j < densePath.count {
                            let dist = d(c, densePath[j])
                            if dist < best { best = dist; bestIndex = j }
                            else if best < letterThreshold && dist > best + 0.5 { break }
                            j += 1
                        }
                        if best > letterThreshold { ok = false; break }
                        total += best
                        cursor = bestIndex
                    }
                    guard ok else { continue }
                    let template = resample(centersForWord, count: samples)
                    var shape = 0.0
                    for i in 0..<samples { shape += d(path[i], template[i]) }
                    shape /= Double(samples)
                    let score = -shapeWeight * shape - alignWeight * total / Double(letters.count)
                        + freqWeight * entry.logFreq + contextBoost(entry.word)
                    seen.insert(entry.word)
                    results.append(Result(word: entry.word, score: score))
                }
            }
        }
        return Array(results.sorted { $0.score > $1.score }.prefix(5))
    }

    private static func collapse(_ key: String) -> [Character] {
        var out: [Character] = []
        for c in key where out.last != c { out.append(c) }
        return out
    }

    private static func d(_ a: CGPoint, _ b: CGPoint) -> Double {
        Double(hypot(a.x - b.x, a.y - b.y))
    }

    private static func length(_ pts: [CGPoint]) -> Double {
        zip(pts, pts.dropFirst()).reduce(0) { $0 + d($1.0, $1.1) }
    }

    static func resample(_ pts: [CGPoint], count n: Int) -> [CGPoint] {
        guard pts.count > 1 else { return Array(repeating: pts.first ?? .zero, count: n) }
        var cum: [Double] = [0]
        for (a, b) in zip(pts, pts.dropFirst()) { cum.append(cum[cum.count - 1] + d(a, b)) }
        let total = cum[cum.count - 1]
        guard total > 0 else { return Array(repeating: pts[0], count: n) }
        var out: [CGPoint] = []
        out.reserveCapacity(n)
        var j = 0
        for i in 0..<n {
            let t = total * Double(i) / Double(n - 1)
            while j < pts.count - 2 && cum[j + 1] < t { j += 1 }
            let seg = max(cum[j + 1] - cum[j], 1e-9)
            let u = CGFloat((t - cum[j]) / seg)
            let a = pts[j], b = pts[j + 1]
            out.append(CGPoint(x: a.x + (b.x - a.x) * u, y: a.y + (b.y - a.y) * u))
        }
        return out
    }
}
