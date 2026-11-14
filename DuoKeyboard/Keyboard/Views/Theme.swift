import UIKit

struct KeyboardTheme {
    let isDark: Bool

    var letterKey: UIColor { isDark ? UIColor(white: 0.42, alpha: 1) : .white }
    var specialKey: UIColor { isDark ? UIColor(white: 0.26, alpha: 1) : UIColor(red: 0.67, green: 0.70, blue: 0.74, alpha: 1) }
    var accentKey: UIColor { .systemBlue }
    var pressedLetter: UIColor { isDark ? UIColor(white: 0.26, alpha: 1) : UIColor(red: 0.67, green: 0.70, blue: 0.74, alpha: 1) }
    var pressedSpecial: UIColor { isDark ? UIColor(white: 0.42, alpha: 1) : .white }
    var text: UIColor { isDark ? .white : .black }
    var secondaryText: UIColor { isDark ? UIColor(white: 0.75, alpha: 1) : UIColor(white: 0.35, alpha: 1) }
    var shadow: UIColor { isDark ? UIColor(white: 0, alpha: 0.6) : UIColor(white: 0, alpha: 0.35) }
    var barText: UIColor { isDark ? .white : .black }
    var divider: UIColor { isDark ? UIColor(white: 1, alpha: 0.15) : UIColor(white: 0, alpha: 0.15) }
    var trail: UIColor { UIColor.systemBlue.withAlphaComponent(0.55) }
    var chip: UIColor { isDark ? UIColor(white: 0.32, alpha: 1) : UIColor(white: 1, alpha: 0.85) }
    var background: UIColor { isDark ? UIColor(white: 0.08, alpha: 1) : UIColor(red: 0.82, green: 0.84, blue: 0.86, alpha: 1) }
}
