import UIKit

/// GIF browser: trending/featured on open, category chips, a search box that types
/// with the keyboard itself, and a horizontally scrolling grid. Tapping a GIF copies
/// it so it can be pasted into the conversation.
final class GIFPanelView: UIView, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    var onBack: (() -> Void)?
    var onSearchTap: (() -> Void)?
    var onCategory: ((String) -> Void)?
    var onSelect: ((GIFItem) -> Void)?
    var theme = KeyboardTheme(isDark: false) { didSet { applyTheme() } }
    weak var service: GIFService?

    private let abc = UIButton(type: .system)
    private let searchButton = UIButton(type: .system)
    private let chipsScroll = UIScrollView()
    private let chips = UIStackView()
    private let collection: UICollectionView
    private let message = UILabel()
    private let spinner = UIActivityIndicatorView(style: .medium)
    private var items: [GIFItem] = []

    static let categories = ["Trending", "Haha", "Love", "Yes", "No", "Thank you", "Wow", "Sad", "Hi", "Bye",
                             "Dance", "Party", "Congrats", "OMG", "Facepalm", "Sleepy", "Hungry", "Excited"]

    override init(frame: CGRect) {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .horizontal
        layout.minimumLineSpacing = 4
        layout.minimumInteritemSpacing = 4
        collection = UICollectionView(frame: .zero, collectionViewLayout: layout)
        super.init(frame: frame)

        abc.setTitle("ABC", for: .normal)
        abc.titleLabel?.font = .systemFont(ofSize: 15, weight: .medium)
        abc.addAction(UIAction { [weak self] _ in self?.onBack?() }, for: .touchUpInside)
        addSubview(abc)

        var cfg = UIButton.Configuration.gray()
        cfg.image = UIImage(systemName: "magnifyingglass")
        cfg.imagePadding = 6
        cfg.cornerStyle = .capsule
        cfg.title = "Search GIFs"
        searchButton.configuration = cfg
        searchButton.contentHorizontalAlignment = .leading
        searchButton.addAction(UIAction { [weak self] _ in self?.onSearchTap?() }, for: .touchUpInside)
        addSubview(searchButton)

        chips.axis = .horizontal
        chips.spacing = 6
        chipsScroll.showsHorizontalScrollIndicator = false
        chipsScroll.addSubview(chips)
        addSubview(chipsScroll)
        for c in Self.categories {
            var cc = UIButton.Configuration.tinted()
            cc.title = c
            cc.cornerStyle = .capsule
            cc.buttonSize = .small
            let b = UIButton(configuration: cc)
            b.addAction(UIAction { [weak self] _ in self?.onCategory?(c == "Trending" ? "" : c) }, for: .touchUpInside)
            chips.addArrangedSubview(b)
        }

        collection.backgroundColor = .clear
        collection.dataSource = self
        collection.delegate = self
        collection.showsHorizontalScrollIndicator = false
        collection.register(GIFCell.self, forCellWithReuseIdentifier: "g")
        addSubview(collection)

        message.numberOfLines = 0
        message.textAlignment = .center
        message.font = .systemFont(ofSize: 14)
        addSubview(message)
        addSubview(spinner)
        applyTheme()
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        abc.frame = CGRect(x: 6, y: 6, width: 50, height: 32)
        searchButton.frame = CGRect(x: 62, y: 6, width: min(260, bounds.width * 0.4), height: 32)
        let chipsX = searchButton.frame.maxX + 8
        chipsScroll.frame = CGRect(x: chipsX, y: 6, width: bounds.width - chipsX - 6, height: 32)
        let size = chips.systemLayoutSizeFitting(CGSize(width: UIView.layoutFittingExpandedSize.width, height: 32))
        chips.frame = CGRect(x: 0, y: 0, width: size.width, height: 32)
        chipsScroll.contentSize = chips.frame.size
        collection.frame = CGRect(x: 0, y: 44, width: bounds.width, height: bounds.height - 48)
        message.frame = collection.frame.insetBy(dx: 24, dy: 10)
        spinner.center = CGPoint(x: collection.frame.midX, y: collection.frame.midY)
        collection.collectionViewLayout.invalidateLayout()
    }

    func setQuery(_ q: String) {
        searchButton.configuration?.title = q.isEmpty ? "Search GIFs" : q
    }

    func setLoading() {
        items = []
        collection.reloadData()
        message.isHidden = true
        spinner.startAnimating()
    }

    func show(_ result: Result<[GIFItem], Error>) {
        spinner.stopAnimating()
        switch result {
        case .success(let list):
            items = list
            message.isHidden = !list.isEmpty
            message.text = list.isEmpty ? "No GIFs found." : nil
        case .failure(let e):
            items = []
            message.isHidden = false
            message.text = e.localizedDescription
        }
        collection.reloadData()
        collection.setContentOffset(.zero, animated: false)
    }

    func collectionView(_ cv: UICollectionView, numberOfItemsInSection section: Int) -> Int { items.count }

    func collectionView(_ cv: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = cv.dequeueReusableCell(withReuseIdentifier: "g", for: indexPath) as! GIFCell
        let item = items[indexPath.item]
        cell.itemID = item.id
        cell.image.image = nil
        service?.preview(item.previewURL) { [weak cell] img in
            guard let cell, cell.itemID == item.id else { return }
            cell.image.image = img
        }
        return cell
    }

    func collectionView(_ cv: UICollectionView, layout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        let h = (cv.bounds.height - 4) / 2
        return CGSize(width: max(h * 0.6, min(h * 2, h * items[indexPath.item].aspect)), height: h)
    }

    func collectionView(_ cv: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        onSelect?(items[indexPath.item])
    }

    private func applyTheme() {
        abc.tintColor = theme.barText
        message.textColor = theme.secondaryText
        spinner.color = theme.barText
    }
}

private final class GIFCell: UICollectionViewCell {
    let image = UIImageView()
    var itemID: String?
    override init(frame: CGRect) {
        super.init(frame: frame)
        image.contentMode = .scaleAspectFill
        image.clipsToBounds = true
        image.layer.cornerRadius = 6
        image.backgroundColor = UIColor(white: 0.5, alpha: 0.2)
        contentView.addSubview(image)
    }
    required init?(coder: NSCoder) { fatalError() }
    override func layoutSubviews() {
        super.layoutSubviews()
        image.frame = contentView.bounds
    }
}
