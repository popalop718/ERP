import UIKit

enum KeyAction: Equatable {
    case character(String)
    case backspace, shift, capsLock, tab, returnKey, space
    case nextKeyboard        // system globe (advanceToNextInputMode)
    case switchLanguage      // cycle Duo languages, long-press lists them
    case symbols, letters, moreSymbols
    case emoji, gif
    case cursorLeft, cursorRight
    case dismiss
    case text(String)        // multi-char insert such as ".com"
}

enum KeyStyle { case letter, special, accent }

struct KeyDef {
    var action: KeyAction
    var label: String
    /// Inserted / shown while Shift is on. `nil` = uppercase of `label`.
    var shiftLabel: String?
    /// Small corner label; flick down or long-press to type it.
    var secondary: String?
    var alternates: [String]
    /// Width in key units (the minimum width when `flexible`).
    var width: CGFloat
    /// Flexible keys share whatever space the row has left over.
    var flexible: Bool
    var style: KeyStyle
    var symbolName: String?

    init(_ action: KeyAction, label: String, shift: String? = nil, secondary: String? = nil,
         alternates: [String] = [], width: CGFloat = 1, flexible: Bool = false, style: KeyStyle = .letter,
         symbol: String? = nil) {
        self.action = action
        self.label = label
        self.shiftLabel = shift
        self.secondary = secondary
        self.alternates = alternates
        self.width = width
        self.flexible = flexible
        self.style = style
        self.symbolName = symbol
    }

    var isLetter: Bool {
        if case .character(let s) = action, s.count == 1, let c = s.first { return c.isLetter }
        return false
    }

    var character: String? {
        if case .character(let s) = action { return s }
        return nil
    }

    func output(shifted: Bool) -> String? {
        guard case .character(let s) = action else { return nil }
        if shifted { return shiftLabel ?? s.uppercased() }
        return s
    }

    func displayLabel(shifted: Bool) -> String {
        guard case .character = action else { return label }
        if shifted { return shiftLabel ?? label.uppercased() }
        return label
    }

    /// Long-press choices: the secondary symbol first, then accents/variants.
    func popupChoices(shifted: Bool) -> [String] {
        var out: [String] = []
        if let s = secondary { out.append(s) }
        for a in alternates { out.append(shifted && isLetter ? a.uppercased() : a) }
        return out
    }
}

struct KeyRow {
    var keys: [KeyDef]
    /// Keys before this index go to the left half when the keyboard is split.
    var splitIndex: Int
}

enum KeyboardPage { case letters, symbols, moreSymbols }

enum ShiftState { case off, once, locked }

/// A key placed on screen.
struct PlacedKey {
    let def: KeyDef
    let frame: CGRect
    let row: Int
}
