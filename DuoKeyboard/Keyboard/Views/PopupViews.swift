import UIKit

/// Character preview balloon shown above a pressed key.
final class KeyPreviewView: UIView {
    private let label = UILabel()

    init(text: String, theme: KeyboardTheme) {
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        backgroundColor = theme.letterKey
        layer.cornerRadius = 8
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.3
        layer.shadowRadius = 3
        layer.shadowOffset = CGSize(width: 0, height: 1)
        label.text = text
        label.textAlignment = .center
        label.font = .systemFont(ofSize: 32)
        label.textColor = theme.text
        addSubview(label)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        label.frame = bounds
    }
}

/// Long-press menu (accents, secondary symbols, languages). Selection follows the finger.
final class AlternatesPopupView: UIView {
    let choices: [String]
    private var labels: [UILabel] = []
    private let theme: KeyboardTheme
    private(set) var selectedIndex: Int = 0
    let cellWidth: CGFloat

    init(choices: [String], theme: KeyboardTheme, cellWidth: CGFloat) {
        self.choices = choices
        self.theme = theme
        self.cellWidth = cellWidth
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        backgroundColor = theme.letterKey
        layer.cornerRadius = 8
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.35
        layer.shadowRadius = 4
        layer.shadowOffset = CGSize(width: 0, height: 1)
        for c in choices {
            let l = UILabel()
            l.text = c
            l.textAlignment = .center
            l.font = .systemFont(ofSize: c.count > 2 ? 15 : 22)
            l.adjustsFontSizeToFitWidth = true
            l.minimumScaleFactor = 0.5
            l.layer.cornerRadius = 6
            l.layer.masksToBounds = true
            addSubview(l)
            labels.append(l)
        }
        select(0)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        for (i, l) in labels.enumerated() {
            l.frame = CGRect(x: 4 + CGFloat(i) * cellWidth, y: 4, width: cellWidth, height: bounds.height - 8)
        }
    }

    var preferredSize: CGSize { CGSize(width: CGFloat(choices.count) * cellWidth + 8, height: 50) }

    func select(_ index: Int) {
        selectedIndex = max(0, min(choices.count - 1, index))
        for (i, l) in labels.enumerated() {
            let on = i == selectedIndex
            l.backgroundColor = on ? .systemBlue : .clear
            l.textColor = on ? .white : theme.text
        }
    }

    /// Update the selection from a point in this view's superview.
    func track(point: CGPoint) {
        let local = convert(point, from: superview)
        select(Int(floor((local.x - 4) / cellWidth)))
    }

    var selected: String { choices[selectedIndex] }
}

/// Small transient message ("GIF copied — paste it").
final class ToastView: UILabel {
    static func show(_ text: String, in view: UIView) {
        let t = ToastView()
        t.text = "  \(text)  "
        t.font = .systemFont(ofSize: 14, weight: .medium)
        t.textColor = .white
        t.backgroundColor = UIColor(white: 0.1, alpha: 0.9)
        t.layer.cornerRadius = 12
        t.layer.masksToBounds = true
        t.textAlignment = .center
        t.numberOfLines = 2
        let size = t.sizeThatFits(CGSize(width: view.bounds.width - 40, height: 60))
        t.frame = CGRect(x: (view.bounds.width - size.width - 16) / 2, y: 6, width: size.width + 16, height: size.height + 10)
        view.addSubview(t)
        UIView.animate(withDuration: 0.3, delay: 2.2, options: []) { t.alpha = 0 } completion: { _ in t.removeFromSuperview() }
    }
}
