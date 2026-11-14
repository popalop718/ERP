import UIKit

/// Full emoji picker: Frequently Used + 8 categories, horizontal paging like the
/// iOS keyboard, skin tones on long-press, ABC and delete keys.
final class EmojiPanelView: UIView, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    var onEmoji: ((String) -> Void)?
    var onBack: (() -> Void)?
    var onDelete: (() -> Void)?
    var theme = KeyboardTheme(isDark: false) { didSet { applyTheme() } }

    private var sections: [EmojiData.Category] = []
    private let collection: UICollectionView
    private let bottomBar = UIStackView()
    private let header = UILabel()
    private var categoryButtons: [UIButton] = []
    private var tonePopup: UIStackView?
    private static let recentsKey = "emoji.recents"

    override init(frame: CGRect) {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .horizontal
        layout.minimumLineSpacing = 0
        layout.minimumInteritemSpacing = 0
        collection = UICollectionView(frame: .zero, collectionViewLayout: layout)
        super.init(frame: frame)
        collection.backgroundColor = .clear
        collection.dataSource = self
        collection.delegate = self
        collection.showsHorizontalScrollIndicator = false
        collection.register(EmojiCell.self, forCellWithReuseIdentifier: "e")
        addSubview(collection)
        header.font = .systemFont(ofSize: 12, weight: .semibold)
        addSubview(header)
        bottomBar.axis = .horizontal
        bottomBar.distribution = .fillEqually
        addSubview(bottomBar)
        let lp = UILongPressGestureRecognizer(target: self, action: #selector(longPress(_:)))
        lp.minimumPressDuration = 0.35
        collection.addGestureRecognizer(lp)
        reloadSections()
    }

    required init?(coder: NSCoder) { fatalError() }

    private var recents: [String] {
        get { UserDefaults.standard.stringArray(forKey: Self.recentsKey) ?? [] }
        set { UserDefaults.standard.set(Array(newValue.prefix(32)), forKey: Self.recentsKey) }
    }

    func reloadSections() {
        let r = recents
        sections = (r.isEmpty ? [] : [EmojiData.Category(name: "Frequently Used", symbol: "clock", emoji: r)]) + EmojiData.categories
        bottomBar.arrangedSubviews.forEach { $0.removeFromSuperview() }
        categoryButtons = []
        let abc = UIButton(type: .system)
        abc.setTitle("ABC", for: .normal)
        abc.titleLabel?.font = .systemFont(ofSize: 15, weight: .medium)
        abc.addAction(UIAction { [weak self] _ in self?.onBack?() }, for: .touchUpInside)
        bottomBar.addArrangedSubview(abc)
        for (i, s) in sections.enumerated() {
            let b = UIButton(type: .system)
            b.setImage(UIImage(systemName: s.symbol), for: .normal)
            b.accessibilityLabel = s.name
            b.addAction(UIAction { [weak self] _ in self?.scroll(to: i) }, for: .touchUpInside)
            bottomBar.addArrangedSubview(b)
            categoryButtons.append(b)
        }
        let del = UIButton(type: .system)
        del.setImage(UIImage(systemName: "delete.left"), for: .normal)
        del.addAction(UIAction { [weak self] _ in self?.onDelete?() }, for: .touchUpInside)
        bottomBar.addArrangedSubview(del)
        collection.reloadData()
        applyTheme()
        updateHeader()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        header.frame = CGRect(x: 12, y: 2, width: bounds.width - 24, height: 18)
        bottomBar.frame = CGRect(x: 0, y: bounds.height - 40, width: bounds.width, height: 40)
        collection.frame = CGRect(x: 0, y: 20, width: bounds.width, height: bounds.height - 60)
        collection.collectionViewLayout.invalidateLayout()
    }

    private var cellSide: CGFloat {
        let rows = max(3, floor(collection.bounds.height / 44))
        return collection.bounds.height / rows
    }

    private func scroll(to section: Int) {
        guard section < sections.count, !sections[section].emoji.isEmpty else { return }
        collection.scrollToItem(at: IndexPath(item: 0, section: section), at: .left, animated: false)
        updateHeader()
    }

    private func updateHeader() {
        let visible = collection.indexPathsForVisibleItems.map(\.section)
        let s = visible.min() ?? 0
        header.text = s < sections.count ? sections[s].name.uppercased() : nil
        for (i, b) in categoryButtons.enumerated() { b.alpha = i == s ? 1 : 0.5 }
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) { updateHeader() }

    func numberOfSections(in collectionView: UICollectionView) -> Int { sections.count }

    func collectionView(_ cv: UICollectionView, numberOfItemsInSection section: Int) -> Int { sections[section].emoji.count }

    func collectionView(_ cv: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = cv.dequeueReusableCell(withReuseIdentifier: "e", for: indexPath) as! EmojiCell
        cell.label.text = sections[indexPath.section].emoji[indexPath.item]
        return cell
    }

    func collectionView(_ cv: UICollectionView, layout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        CGSize(width: cellSide, height: cellSide)
    }

    func collectionView(_ cv: UICollectionView, layout: UICollectionViewLayout, insetForSectionAt section: Int) -> UIEdgeInsets {
        UIEdgeInsets(top: 0, left: 6, bottom: 0, right: 10)
    }

    func collectionView(_ cv: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        pick(sections[indexPath.section].emoji[indexPath.item])
    }

    private func pick(_ e: String) {
        onEmoji?(e)
        var r = recents.filter { $0 != e }
        r.insert(e, at: 0)
        recents = r
    }

    @objc private func longPress(_ g: UILongPressGestureRecognizer) {
        let p = g.location(in: collection)
        switch g.state {
        case .began:
            guard let ip = collection.indexPathForItem(at: p) else { return }
            let tones = EmojiData.skinTones(for: sections[ip.section].emoji[ip.item])
            guard !tones.isEmpty, let cell = collection.cellForItem(at: ip) else { return }
            let stack = UIStackView()
            stack.axis = .horizontal
            stack.distribution = .fillEqually
            stack.backgroundColor = theme.letterKey
            stack.layer.cornerRadius = 8
            stack.layer.shadowOpacity = 0.3
            stack.layer.shadowRadius = 4
            for t in tones {
                let l = UILabel()
                l.text = t
                l.font = .systemFont(ofSize: 28)
                l.textAlignment = .center
                l.layer.cornerRadius = 6
                l.layer.masksToBounds = true
                stack.addArrangedSubview(l)
            }
            let w = CGFloat(tones.count) * 44
            let f = convert(cell.frame, from: collection)
            stack.frame = CGRect(x: min(max(0, f.midX - w / 2), bounds.width - w), y: max(0, f.minY - 50), width: w, height: 46)
            addSubview(stack)
            tonePopup = stack
            highlightTone(at: g.location(in: self))
        case .changed:
            highlightTone(at: g.location(in: self))
        case .ended:
            if let stack = tonePopup, let idx = toneIndex(at: g.location(in: self)),
               let l = stack.arrangedSubviews[idx] as? UILabel, let t = l.text { pick(t) }
            fallthrough
        default:
            tonePopup?.removeFromSuperview()
            tonePopup = nil
        }
    }

    private func toneIndex(at p: CGPoint) -> Int? {
        guard let stack = tonePopup else { return nil }
        let local = convert(p, to: stack)
        let i = Int(local.x / 44)
        return i >= 0 && i < stack.arrangedSubviews.count ? i : nil
    }

    private func highlightTone(at p: CGPoint) {
        let idx = toneIndex(at: p)
        for (i, v) in (tonePopup?.arrangedSubviews ?? []).enumerated() {
            v.backgroundColor = i == idx ? .systemBlue.withAlphaComponent(0.35) : .clear
        }
    }

    private func applyTheme() {
        header.textColor = theme.secondaryText
        bottomBar.arrangedSubviews.forEach { $0.tintColor = theme.barText }
    }
}

private final class EmojiCell: UICollectionViewCell {
    let label = UILabel()
    override init(frame: CGRect) {
        super.init(frame: frame)
        label.textAlignment = .center
        label.font = .systemFont(ofSize: 30)
        label.adjustsFontSizeToFitWidth = true
        contentView.addSubview(label)
    }
    required init?(coder: NSCoder) { fatalError() }
    override func layoutSubviews() {
        super.layoutSubviews()
        label.frame = contentView.bounds.insetBy(dx: 2, dy: 2)
    }
}
