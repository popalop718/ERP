import UIKit

enum FieldKind { case normal, email, url, web }

struct LayoutContext {
    var language: KeyboardLanguage
    var page: KeyboardPage
    var split: Bool
    var needsGlobe: Bool
    var fieldKind: FieldKind
    var numberRow: Bool
    var returnLabel: String
    var gifsEnabled: Bool
}

/// Builds the rows for every language/page. Letter pages are full desktop-style
/// layouts: number row, Tab, Caps Lock, both Shift keys and the language's own
/// punctuation keys, plus arrow keys on the bottom row.
enum KeyLayouts {

    // MARK: Accents (long-press)

    private static func accents(_ lang: KeyboardLanguage) -> [String: [String]] {
        switch lang {
        case .english:
            return ["a": ["à", "á", "â", "ä", "æ", "ã", "å", "ā"], "e": ["è", "é", "ê", "ë", "ē", "ė", "ę"],
                    "i": ["î", "ï", "í", "ī", "į", "ì"], "o": ["ô", "ö", "ò", "ó", "œ", "ø", "ō", "õ"],
                    "u": ["û", "ü", "ù", "ú", "ū"], "c": ["ç", "ć", "č"], "n": ["ñ", "ń"],
                    "s": ["ß", "ś", "š"], "y": ["ÿ"], "z": ["ž", "ź", "ż"], "l": ["ł"]]
        case .spanish:
            return ["a": ["á", "à", "ä", "â", "ª", "ã"], "e": ["é", "è", "ë", "ê", "ē"],
                    "i": ["í", "ì", "ï", "î"], "o": ["ó", "ò", "ö", "ô", "º", "õ"],
                    "u": ["ú", "ü", "ù", "û"], "n": ["ñ", "ń"], "c": ["ç", "ć", "č"], "s": ["ß", "š"]]
        case .french:
            return ["a": ["à", "â", "æ", "á", "ä", "ã", "å"], "e": ["é", "è", "ê", "ë", "ē"],
                    "i": ["î", "ï", "í", "ì"], "o": ["ô", "œ", "ö", "ó", "ò", "ø"],
                    "u": ["ù", "û", "ü", "ú"], "c": ["ç", "ć"], "y": ["ÿ"], "n": ["ñ"]]
        case .german:
            return ["a": ["ä", "à", "á", "â", "æ", "å"], "o": ["ö", "ó", "ò", "ô", "œ", "ø"],
                    "u": ["ü", "ú", "ù", "û"], "s": ["ß", "ś", "š"], "e": ["é", "è", "ê", "ë"],
                    "i": ["í", "ì", "î", "ï"], "c": ["ç", "č"], "n": ["ñ"], "z": ["ž"]]
        }
    }

    private static let punctAlternates: [String: [String]] = [
        "'": ["\u{2019}", "\u{2018}", "`", "´"], "\"": ["\u{201C}", "\u{201D}", "\u{201E}", "«", "»"],
        "-": ["–", "—", "•", "·"], ".": ["…"], "?": ["¿"], "!": ["¡"], "$": ["€", "£", "¥", "¢", "₹", "₩"],
        "/": ["\\"], "&": ["§"], "%": ["‰"], "0": ["°"], "=": ["≠", "≈"], ",": [";"],
    ]

    private static func letter(_ c: String, _ lang: KeyboardLanguage) -> KeyDef {
        KeyDef(.character(c), label: c, alternates: accents(lang)[c] ?? [])
    }

    /// A punctuation/number key: `base` is typed, `shift` with Shift or a flick down.
    private static func punct(_ base: String, _ shift: String?) -> KeyDef {
        var alts = punctAlternates[base] ?? []
        if let s = shift { alts += punctAlternates[s] ?? [] }
        return KeyDef(.character(base), label: base, shift: shift ?? base, secondary: shift, alternates: alts)
    }

    private static func special(_ action: KeyAction, _ label: String, _ width: CGFloat, symbol: String? = nil,
                                flexible: Bool = false, style: KeyStyle = .special) -> KeyDef {
        KeyDef(action, label: label, width: width, flexible: flexible, style: style, symbol: symbol)
    }

    // MARK: Letter rows

    private struct LangRows {
        var number: [(String, String?)]
        var top: [String]; var topPunct: [(String, String?)]
        var home: [String]; var homePunct: [(String, String?)]
        var bottom: [String]; var bottomPunct: [(String, String?)]
    }

    private static func rows(for lang: KeyboardLanguage) -> LangRows {
        switch lang {
        case .english:
            return LangRows(
                number: [("`", "~"), ("1", "!"), ("2", "@"), ("3", "#"), ("4", "$"), ("5", "%"), ("6", "^"),
                         ("7", "&"), ("8", "*"), ("9", "("), ("0", ")"), ("-", "_"), ("=", "+")],
                top: "qwertyuiop".map(String.init), topPunct: [("[", "{"), ("]", "}"), ("\\", "|")],
                home: "asdfghjkl".map(String.init), homePunct: [(";", ":"), ("'", "\"")],
                bottom: "zxcvbnm".map(String.init), bottomPunct: [(",", "<"), (".", ">"), ("/", "?")])
        case .spanish:
            return LangRows(
                number: [("º", "ª"), ("1", "!"), ("2", "\""), ("3", "#"), ("4", "$"), ("5", "%"), ("6", "&"),
                         ("7", "/"), ("8", "("), ("9", ")"), ("0", "="), ("'", "?"), ("¡", "¿")],
                top: "qwertyuiop".map(String.init), topPunct: [("[", "{"), ("]", "}"), ("+", "*")],
                home: "asdfghjkl".map(String.init) + ["ñ"], homePunct: [("´", "¨")],
                bottom: "zxcvbnm".map(String.init), bottomPunct: [(",", ";"), (".", ":"), ("-", "_")])
        case .french:
            return LangRows(
                number: [("²", "³"), ("1", "&"), ("2", "é"), ("3", "\""), ("4", "'"), ("5", "("), ("6", "-"),
                         ("7", "è"), ("8", "_"), ("9", "ç"), ("0", "à"), (")", "°"), ("=", "+")],
                top: "azertyuiop".map(String.init), topPunct: [("^", "¨"), ("$", "£"), ("*", "µ")],
                home: "qsdfghjklm".map(String.init) + ["ù"], homePunct: [],
                bottom: "wxcvbn".map(String.init), bottomPunct: [("'", "\""), (",", ";"), (".", ":"), ("?", "!")])
        case .german:
            return LangRows(
                number: [("^", "°"), ("1", "!"), ("2", "\""), ("3", "§"), ("4", "$"), ("5", "%"), ("6", "&"),
                         ("7", "/"), ("8", "("), ("9", ")"), ("0", "="), ("ß", "?"), ("´", "`")],
                top: "qwertzuiop".map(String.init) + ["ü"], topPunct: [("+", "*"), ("#", "'")],
                home: "asdfghjkl".map(String.init) + ["ö", "ä"], homePunct: [],
                bottom: "yxcvbnm".map(String.init), bottomPunct: [(",", ";"), (".", ":"), ("-", "_")])
        }
    }

    static func build(_ ctx: LayoutContext) -> [KeyRow] {
        switch ctx.page {
        case .letters: return letterRows(ctx)
        case .symbols: return symbolRows(ctx, more: false)
        case .moreSymbols: return symbolRows(ctx, more: true)
        }
    }

    private static func letterRows(_ ctx: LayoutContext) -> [KeyRow] {
        let lang = ctx.language
        let r = rows(for: lang)
        var out: [KeyRow] = []

        if ctx.numberRow {
            var keys = r.number.map { punct($0.0, $0.1) }
            keys.append(special(.backspace, "delete", 1.5, symbol: "delete.left", flexible: true))
            out.append(KeyRow(keys: keys, splitIndex: 7))
        }

        var top = [special(.tab, "tab", 1.5, symbol: "arrow.right.to.line")]
        top += r.top.map { letter($0, lang) }
        top += r.topPunct.map { punct($0.0, $0.1) }
        if !ctx.numberRow { top.append(special(.backspace, "delete", 1.5, symbol: "delete.left")) }
        top[top.count - 1].flexible = true
        out.append(KeyRow(keys: top, splitIndex: 6))

        var home = [special(.capsLock, "caps", 1.75, symbol: "capslock")]
        home += r.home.map { letter($0, lang) }
        home += r.homePunct.map { punct($0.0, $0.1) }
        home.append(special(.returnKey, ctx.returnLabel, 1.75, flexible: true, style: .accent))
        out.append(KeyRow(keys: home, splitIndex: 6))

        var bottom = [special(.shift, "shift", 2.25, symbol: "shift")]
        bottom += r.bottom.map { letter($0, lang) }
        bottom += r.bottomPunct.map { punct($0.0, $0.1) }
        bottom.append(special(.shift, "shift", 1.5, symbol: "shift", flexible: true))
        out.append(KeyRow(keys: bottom, splitIndex: 6))

        out.append(controlRow(ctx, pageKey: special(.symbols, "123", 1.25)))
        return out
    }

    private static func controlRow(_ ctx: LayoutContext, pageKey: KeyDef) -> KeyRow {
        var left: [KeyDef] = []
        if ctx.needsGlobe { left.append(special(.nextKeyboard, "globe", 1.15, symbol: "globe")) }
        left.append(special(.switchLanguage, ctx.language.shortCode, 1.15))
        left.append(pageKey)
        left.append(special(.emoji, "emoji", 1.15, symbol: "face.smiling"))

        var right: [KeyDef] = []
        switch ctx.fieldKind {
        case .email: right.append(KeyDef(.character("@"), label: "@", alternates: [".", "_", "-"], width: 1.15, style: .special))
        case .url, .web: right.append(KeyDef(.text(".com"), label: ".com",
                                             alternates: [".net", ".org", ".de", ".es", ".fr", ".co.uk"], width: 1.4, style: .special))
        case .normal: if ctx.gifsEnabled { right.append(special(.gif, "GIF", 1.15)) }
        }
        right.append(special(.cursorLeft, "left", 1, symbol: "arrowtriangle.left.fill"))
        right.append(special(.cursorRight, "right", 1, symbol: "arrowtriangle.right.fill"))

        let space = KeyDef(.space, label: ctx.language.displayName, width: 3, flexible: true)
        if ctx.split {
            return KeyRow(keys: left + [space, space] + right, splitIndex: left.count + 1)
        }
        return KeyRow(keys: left + [space] + right, splitIndex: left.count + 1)
    }

    // MARK: Symbol pages

    private static func symbolRows(_ ctx: LayoutContext, more: Bool) -> [KeyRow] {
        func keys(_ s: String) -> [KeyDef] {
            s.split(separator: " ").map { tok -> KeyDef in
                let t = String(tok)
                return KeyDef(.character(t), label: t, alternates: punctAlternates[t] ?? [])
            }
        }
        let r0 = more ? "€ £ ¥ ₹ ¢ ₩ ₽ ₺ ₿ § ¤" : "1 2 3 4 5 6 7 8 9 0 °"
        let r1 = more ? "_ \\ | ~ < > « » ‹ › • ¶" : "- / : ; ( ) $ & @ \" ' ´"
        let r2 = more ? "… ¡ ¿ © ® ™ ± × ÷ ≠ ≈" : "[ ] { } # % ^ * + = `"
        let r3 = more ? "´ ¨ ^ ˜ — – ‰ √ ∞" : ". , ? ! _ ~ | \\ < >"

        var row0 = keys(r0); row0.append(special(.backspace, "delete", 1.5, symbol: "delete.left", flexible: true))
        var row1 = [special(.tab, "tab", 1.5, symbol: "arrow.right.to.line")] + keys(r1)
        row1[row1.count - 1].flexible = true
        var row2 = keys(r2); row2.append(special(.returnKey, ctx.returnLabel, 1.75, flexible: true, style: .accent))
        var row3 = [special(more ? .symbols : .moreSymbols, more ? "123" : "#+=", 2.0)] + keys(r3)
        row3.append(special(more ? .symbols : .moreSymbols, more ? "123" : "#+=", 1.5, flexible: true))
        let pageKey = special(.letters, "ABC", 1.25)
        return [KeyRow(keys: row0, splitIndex: 6), KeyRow(keys: row1, splitIndex: 7),
                KeyRow(keys: row2, splitIndex: 6), KeyRow(keys: row3, splitIndex: 6),
                controlRow(ctx, pageKey: pageKey)]
    }

    // MARK: Geometry

    /// Lays rows out into frames. Unsplit, each row spans the full width (flexible
    /// keys absorb the slack). Split, the two halves get exactly equal widths with
    /// `gap` points between them, so the gap is centred on `rect.midX` — on iPhone Duo's
    /// inner display that is precisely where the crease is, so no key sits on the fold.
    static func place(_ rows: [KeyRow], in rect: CGRect, split: Bool, gap: CGFloat) -> (keys: [PlacedKey], unit: CGFloat) {
        guard !rows.isEmpty else { return ([], 1) }
        let rowH = rect.height / CGFloat(rows.count)
        var placed: [PlacedKey] = []

        if !split {
            let maxUnits = rows.map { $0.keys.reduce(0) { $0 + $1.width } }.max() ?? 15
            let unit = rect.width / maxUnits
            for (ri, row) in rows.enumerated() {
                let y = rect.minY + CGFloat(ri) * rowH
                placed += layoutSegment(row.keys, x: rect.minX, width: rect.width, unit: unit, y: y, height: rowH,
                                        row: ri, align: .center)
            }
            return (placed, unit)
        }

        let half = max(1, (rect.width - gap) / 2)
        let maxHalfUnits = rows.flatMap { row -> [CGFloat] in
            let l = row.keys[..<min(row.splitIndex, row.keys.count)].reduce(0) { $0 + $1.width }
            let r = row.keys[min(row.splitIndex, row.keys.count)...].reduce(0) { $0 + $1.width }
            return [l, r]
        }.max() ?? 8
        let unit = half / maxHalfUnits
        for (ri, row) in rows.enumerated() {
            let y = rect.minY + CGFloat(ri) * rowH
            let cut = min(row.splitIndex, row.keys.count)
            placed += layoutSegment(Array(row.keys[..<cut]), x: rect.minX, width: half, unit: unit, y: y, height: rowH,
                                    row: ri, align: .fill)
            placed += layoutSegment(Array(row.keys[cut...]), x: rect.maxX - half, width: half, unit: unit, y: y, height: rowH,
                                    row: ri, align: .fill)
        }
        return (placed, unit)
    }

    private enum SegmentAlign { case center, fill }

    /// Places one run of keys into `width`. Flexible keys take the leftover space;
    /// without any, `.fill` scales every key so the run still spans the full width.
    private static func layoutSegment(_ keys: [KeyDef], x: CGFloat, width: CGFloat, unit: CGFloat, y: CGFloat,
                                      height: CGFloat, row: Int, align: SegmentAlign) -> [PlacedKey] {
        guard !keys.isEmpty else { return [] }
        let fixed = keys.reduce(CGFloat(0)) { $0 + $1.width * unit }
        let flexCount = CGFloat(keys.filter(\.flexible).count)
        let leftover = max(0, width - fixed)
        var scale: CGFloat = 1
        var extra: CGFloat = 0
        var cursor = x
        if flexCount > 0 { extra = leftover / flexCount }
        else if align == .fill, fixed > 0 { scale = width / fixed }
        else { cursor += leftover / 2 }
        var out: [PlacedKey] = []
        for key in keys {
            let w = key.width * unit * scale + (key.flexible ? extra : 0)
            out.append(PlacedKey(def: key, frame: CGRect(x: cursor, y: y, width: w, height: height), row: row))
            cursor += w
        }
        return out
    }
}
