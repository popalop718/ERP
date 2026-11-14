import UIKit

/// One visual key. Purely visual — all touches are handled by `KeyboardView` so a
/// single finger can slide across keys (swipe typing, trackpad, long-press menus).
final class KeyCapView: UIView {
    let cap = UIView()
    private let label = UILabel()
    private let secondaryLabel = UILabel()
    private let icon = UIImageView()
    private(set) var def: KeyDef
    private var theme = KeyboardTheme(isDark: false)
    var isPressed = false { didSet { applyColors() } }
    var isActive = false { didSet { applyColors() } } // shift / caps lit

    init(def: KeyDef) {
        self.def = def
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        cap.layer.cornerRadius = 5
        cap.layer.shadowOffset = CGSize(width: 0, height: 1)
        cap.layer.shadowRadius = 0
        cap.layer.shadowOpacity = 1
        addSubview(cap)
        label.textAlignment = .center
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.5
        label.isAccessibilityElement = false
        cap.addSubview(label)
        secondaryLabel.textAlignment = .right
        secondaryLabel.font = .systemFont(ofSize: 10, weight: .regular)
        cap.addSubview(secondaryLabel)
        icon.contentMode = .scaleAspectFit
        cap.addSubview(icon)
        isAccessibilityElement = true
        accessibilityTraits = .keyboardKey
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(def: KeyDef, shifted: Bool, shiftState: ShiftState, theme: KeyboardTheme, showSecondary: Bool) {
        self.def = def
        self.theme = theme
        let text = def.displayLabel(shifted: shifted)
        accessibilityLabel = def.symbolName == nil ? text : def.label
        if let symbol = def.symbolName {
            var name = symbol
            if case .shift = def.action {
                name = shiftState == .locked ? "capslock.fill" : (shiftState == .once ? "shift.fill" : "shift")
            }
            if case .capsLock = def.action, shiftState == .locked { name = "capslock.fill" }
            icon.image = UIImage(systemName: name, withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .regular))
            icon.isHidden = false
            label.isHidden = true
        } else {
            icon.isHidden = true
            label.isHidden = false
            label.text = text
            let isChar = def.character != nil && def.style == .letter
            label.font = isChar ? .systemFont(ofSize: def.isLetter ? 22 : 19, weight: .regular)
                                : .systemFont(ofSize: 15, weight: .regular)
            if case .space = def.action { label.font = .systemFont(ofSize: 14) }
        }
        if showSecondary, let sec = def.secondary, !shifted {
            secondaryLabel.text = sec
            secondaryLabel.isHidden = false
        } else {
            secondaryLabel.isHidden = true
        }
        applyColors()
        setNeedsLayout()
    }

    private func applyColors() {
        let base: UIColor
        switch def.style {
        case .letter: base = isPressed ? theme.pressedLetter : theme.letterKey
        case .special: base = isPressed ? theme.pressedSpecial : (isActive ? theme.letterKey : theme.specialKey)
        case .accent: base = isPressed ? theme.pressedSpecial : theme.accentKey
        }
        cap.backgroundColor = base
        cap.layer.shadowColor = theme.shadow.cgColor
        let fg: UIColor = def.style == .accent ? .white : theme.text
        label.textColor = fg
        icon.tintColor = fg
        secondaryLabel.textColor = theme.secondaryText
        if case .space = def.action { label.textColor = theme.secondaryText }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let inset = UIEdgeInsets(top: 4, left: 3, bottom: 4, right: 3)
        cap.frame = bounds.inset(by: inset)
        cap.layer.shadowPath = UIBezierPath(roundedRect: cap.bounds, cornerRadius: 5).cgPath
        label.frame = cap.bounds.insetBy(dx: 2, dy: 0)
        icon.frame = cap.bounds.insetBy(dx: max(2, (cap.bounds.width - 24) / 2), dy: max(2, (cap.bounds.height - 22) / 2))
        secondaryLabel.frame = CGRect(x: 2, y: 1, width: cap.bounds.width - 5, height: 12)
        if !secondaryLabel.isHidden {
            label.frame = cap.bounds.insetBy(dx: 2, dy: 0).offsetBy(dx: 0, dy: 3)
        }
    }

    /// The cap's frame in the keyboard view's coordinates.
    var capFrameInSuperview: CGRect { cap.frame.offsetBy(dx: frame.minX, dy: frame.minY) }
}
