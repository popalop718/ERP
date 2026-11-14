import UIKit

struct Suggestion {
    enum Kind { case literal, correction, completion, prediction, emoji, math, replacement, grammar, spelling, swipeAlternative }
    var text: String
    var display: String
    var kind: Kind
    /// Bold = this is what Space will apply (autocorrection / text replacement).
    var isDefault = false
    var issue: TextIssue?

    init(_ text: String, kind: Kind, display: String? = nil, isDefault: Bool = false, issue: TextIssue? = nil) {
        self.text = text
        self.display = display ?? text
        self.kind = kind
        self.isDefault = isDefault
        self.issue = issue
    }
}

enum ToolAction: CaseIterable {
    case cut, copy, paste, wordLeft, wordRight, lineStart, lineEnd, split, oneHandedLeft, oneHandedRight, fullWidth, dismiss

    var symbol: String {
        switch self {
        case .cut: return "scissors"
        case .copy: return "doc.on.doc"
        case .paste: return "doc.on.clipboard"
        case .wordLeft: return "arrow.left.to.line.compact"
        case .wordRight: return "arrow.right.to.line.compact"
        case .lineStart: return "arrow.left.to.line"
        case .lineEnd: return "arrow.right.to.line"
        case .split: return "rectangle.split.2x1"
        case .oneHandedLeft: return "keyboard.onehanded.left"
        case .oneHandedRight: return "keyboard.onehanded.right"
        case .fullWidth: return "keyboard"
        case .dismiss: return "keyboard.chevron.compact.down"
        }
    }

    var title: String {
        switch self {
        case .cut: return "Cut"
        case .copy: return "Copy"
        case .paste: return "Paste"
        case .wordLeft: return "Word ←"
        case .wordRight: return "Word →"
        case .lineStart: return "Home"
        case .lineEnd: return "End"
        case .split: return "Split"
        case .oneHandedLeft: return "Left"
        case .oneHandedRight: return "Right"
        case .fullWidth: return "Full"
        case .dismiss: return "Hide"
        }
    }
}

/// The bar above the keys: three suggestion slots (like iOS) with a toggle that
/// swaps them for an editing/layout toolbar.
final class SuggestionBar: UIView {
    var onSelect: ((Suggestion) -> Void)?
    var onTool: ((ToolAction) -> Void)?
    var theme = KeyboardTheme(isDark: false) { didSet { applyTheme() } }

    private let toggle = UIButton(type: .system)
    private let slots = UIStackView()
    private let toolsScroll = UIScrollView()
    private let tools = UIStackView()
    private var items: [Suggestion] = []
    private(set) var showingTools = false
    private let titleLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        toggle.setImage(UIImage(systemName: "ellipsis.circle"), for: .normal)
        toggle.addTarget(self, action: #selector(toggleTools), for: .touchUpInside)
        toggle.accessibilityLabel = "Toolbar"
        addSubview(toggle)

        slots.axis = .horizontal
        slots.distribution = .fillEqually
        addSubview(slots)

        tools.axis = .horizontal
        tools.spacing = 6
        toolsScroll.showsHorizontalScrollIndicator = false
        toolsScroll.addSubview(tools)
        toolsScroll.isHidden = true
        addSubview(toolsScroll)
        for action in ToolAction.allCases {
            var cfg = UIButton.Configuration.plain()
            cfg.image = UIImage(systemName: action.symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 14))
            cfg.title = action.title
            cfg.imagePadding = 4
            cfg.contentInsets = NSDirectionalEdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8)
            let b = UIButton(configuration: cfg)
            b.addAction(UIAction { [weak self] _ in self?.onTool?(action) }, for: .touchUpInside)
            tools.addArrangedSubview(b)
        }

        titleLabel.textAlignment = .center
        titleLabel.font = .systemFont(ofSize: 15, weight: .medium)
        titleLabel.isHidden = true
        addSubview(titleLabel)
        applyTheme()
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        let h = bounds.height
        toggle.frame = CGRect(x: 4, y: 0, width: 40, height: h)
        let rest = CGRect(x: 48, y: 0, width: bounds.width - 52, height: h)
        slots.frame = rest
        toolsScroll.frame = rest
        let size = tools.systemLayoutSizeFitting(CGSize(width: UIView.layoutFittingExpandedSize.width, height: h))
        tools.frame = CGRect(x: 0, y: 0, width: size.width, height: h)
        toolsScroll.contentSize = tools.frame.size
        titleLabel.frame = rest
    }

    @objc private func toggleTools() {
        showingTools.toggle()
        toolsScroll.isHidden = !showingTools
        slots.isHidden = showingTools || !titleLabel.isHidden
        toggle.setImage(UIImage(systemName: showingTools ? "xmark.circle" : "ellipsis.circle"), for: .normal)
    }

    /// Shows a plain title instead of suggestions (e.g. the GIF search query).
    func showTitle(_ text: String?) {
        titleLabel.text = text
        titleLabel.isHidden = text == nil
        slots.isHidden = text != nil || showingTools
    }

    func set(_ suggestions: [Suggestion]) {
        items = Array(suggestions.prefix(3))
        slots.arrangedSubviews.forEach { $0.removeFromSuperview() }
        // Keep the iOS ordering: the default/primary choice sits in the middle.
        var ordered = items
        if ordered.count == 3, let i = ordered.firstIndex(where: { $0.isDefault }), i != 1 {
            ordered.swapAt(i, 1)
        }
        for (idx, s) in ordered.enumerated() {
            let b = UIButton(type: .system)
            var title = s.display
            switch s.kind {
            case .literal: title = "\u{201C}\(s.display)\u{201D}"
            case .grammar, .spelling: title = "✎ " + s.display
            case .math: title = "= " + s.display
            default: break
            }
            b.setTitle(title, for: .normal)
            b.titleLabel?.font = .systemFont(ofSize: 16, weight: s.isDefault ? .semibold : .regular)
            b.titleLabel?.adjustsFontSizeToFitWidth = true
            b.titleLabel?.minimumScaleFactor = 0.6
            b.titleLabel?.lineBreakMode = .byTruncatingMiddle
            b.setTitleColor(s.kind == .grammar || s.kind == .spelling ? .systemOrange : theme.barText, for: .normal)
            if s.isDefault {
                b.backgroundColor = theme.chip
                b.layer.cornerRadius = 6
            }
            b.addAction(UIAction { [weak self] _ in self?.onSelect?(s) }, for: .touchUpInside)
            let wrap = UIView()
            wrap.addSubview(b)
            b.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                b.leadingAnchor.constraint(equalTo: wrap.leadingAnchor, constant: 3),
                b.trailingAnchor.constraint(equalTo: wrap.trailingAnchor, constant: -3),
                b.topAnchor.constraint(equalTo: wrap.topAnchor, constant: 4),
                b.bottomAnchor.constraint(equalTo: wrap.bottomAnchor, constant: -4),
            ])
            if idx > 0 {
                let div = UIView()
                div.backgroundColor = theme.divider
                div.translatesAutoresizingMaskIntoConstraints = false
                wrap.addSubview(div)
                NSLayoutConstraint.activate([
                    div.leadingAnchor.constraint(equalTo: wrap.leadingAnchor),
                    div.widthAnchor.constraint(equalToConstant: 1),
                    div.centerYAnchor.constraint(equalTo: wrap.centerYAnchor),
                    div.heightAnchor.constraint(equalTo: wrap.heightAnchor, multiplier: 0.5),
                ])
            }
            slots.addArrangedSubview(wrap)
        }
    }

    private func applyTheme() {
        toggle.tintColor = theme.barText
        titleLabel.textColor = theme.barText
        tools.arrangedSubviews.forEach { ($0 as? UIButton)?.tintColor = theme.barText }
        set(items)
    }
}
