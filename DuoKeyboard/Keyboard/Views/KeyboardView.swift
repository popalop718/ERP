import UIKit

protocol KeyboardViewDelegate: AnyObject {
    func keyboardView(_ view: KeyboardView, didTouchDown key: KeyDef)
    func keyboardView(_ view: KeyboardView, didTap key: KeyDef)
    func keyboardView(_ view: KeyboardView, didChoose text: String, from key: KeyDef)
    func keyboardView(_ view: KeyboardView, didChooseLanguageAt index: Int)
    func keyboardView(_ view: KeyboardView, didSwipe path: [CGPoint])
    func keyboardView(_ view: KeyboardView, moveCursorBy offset: Int)
    func keyboardViewBackspaceRepeat(_ view: KeyboardView, wordMode: Bool)
}

/// The key grid. Owns every touch so one finger can tap, slide-to-type across keys,
/// flick down for a key's secondary symbol, long-press for accents, drag the space
/// bar like a trackpad, or hold delete to repeat.
final class KeyboardView: UIView {
    weak var delegate: KeyboardViewDelegate?

    var swipeEnabled = true
    var characterPreview = true
    var trackpadEnabled = true
    var showSecondary = true
    var languageChoices: [String] = []
    var theme = KeyboardTheme(isDark: false)

    private(set) var rows: [KeyRow] = []
    private var keyViews: [KeyCapView] = []
    private var split = false
    private var gap: CGFloat = 0
    private var shiftState: ShiftState = .off
    private var lastLayoutSize: CGSize = .zero
    private(set) var unit: CGFloat = 40
    /// Centre of each letter key, used by the swipe decoder.
    private(set) var letterCenters: [Character: CGPoint] = [:]

    private let trail = CAShapeLayer()

    private enum Mode { case tap, swipe, trackpad, popup, flick, backspace, consumed }

    private final class Tracker {
        let touch: UITouch
        var keyView: KeyCapView?
        let start: CGPoint
        var points: [CGPoint]
        var mode: Mode = .tap
        var timer: Timer?
        var anchorX: CGFloat = 0
        var repeats = 0
        init(touch: UITouch, keyView: KeyCapView?, start: CGPoint) {
            self.touch = touch; self.keyView = keyView; self.start = start; self.points = [start]
        }
    }

    private var trackers: [Tracker] = []
    private var preview: KeyPreviewView?
    private var popup: AlternatesPopupView?
    private weak var popupOwner: Tracker?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true
        clipsToBounds = false
        trail.fillColor = UIColor.clear.cgColor
        trail.lineWidth = 7
        trail.lineCap = .round
        trail.lineJoin = .round
        layer.addSublayer(trail)
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: Layout

    func load(rows: [KeyRow], shiftState: ShiftState, split: Bool, gap: CGFloat) {
        self.rows = rows
        self.split = split
        self.gap = gap
        self.shiftState = shiftState
        keyViews.forEach { $0.removeFromSuperview() }
        keyViews = rows.flatMap { $0.keys }.map { KeyCapView(def: $0) }
        keyViews.forEach { insertSubview($0, at: 0) }
        lastLayoutSize = .zero
        setNeedsLayout()
        layoutIfNeeded()
    }

    func update(shiftState: ShiftState) {
        self.shiftState = shiftState
        let shifted = shiftState != .off
        for v in keyViews {
            v.configure(def: v.def, shifted: shifted, shiftState: shiftState, theme: theme, showSecondary: showSecondary)
            switch v.def.action {
            case .shift: v.isActive = shiftState != .off
            case .capsLock: v.isActive = shiftState == .locked
            default: v.isActive = false
            }
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.size != lastLayoutSize, bounds.width > 0 else { return }
        lastLayoutSize = bounds.size
        let area = bounds.insetBy(dx: 2, dy: 0)
        let (placed, unit) = KeyLayouts.place(rows, in: area, split: split, gap: gap)
        self.unit = unit
        letterCenters = [:]
        for (v, p) in zip(keyViews, placed) {
            v.frame = p.frame
            if p.def.isLetter, let c = p.def.character?.first {
                letterCenters[Character(c.lowercased())] = CGPoint(x: p.frame.midX, y: p.frame.midY)
            }
        }
        update(shiftState: shiftState)
        trail.frame = bounds
    }

    private func keyView(at point: CGPoint) -> KeyCapView? {
        if let hit = keyViews.first(where: { $0.frame.contains(point) }) { return hit }
        // In the split gap or on an edge: snap to the nearest key in the same row band.
        return keyViews.min { a, b in
            dist(point, a.frame) < dist(point, b.frame)
        }.flatMap { dist(point, $0.frame) < unit * 1.2 ? $0 : nil }
    }

    private func dist(_ p: CGPoint, _ r: CGRect) -> CGFloat {
        let dx = max(r.minX - p.x, 0, p.x - r.maxX)
        let dy = max(r.minY - p.y, 0, p.y - r.maxY)
        return hypot(dx, dy)
    }

    // MARK: Touches

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            let p = touch.location(in: self)
            let kv = keyView(at: p)
            // Rollover: a new finger lands before the previous one lifted — commit it now.
            for other in trackers where other.mode == .tap {
                if let k = other.keyView?.def, k.character != nil {
                    other.mode = .consumed
                    other.timer?.invalidate()
                    other.keyView?.isPressed = false
                    hidePreview()
                    delegate?.keyboardView(self, didTap: k)
                }
            }
            let t = Tracker(touch: touch, keyView: kv, start: p)
            trackers.append(t)
            guard let kv else { t.mode = .consumed; continue }
            kv.isPressed = true
            delegate?.keyboardView(self, didTouchDown: kv.def)

            if case .backspace = kv.def.action {
                t.mode = .backspace
                delegate?.keyboardView(self, didTap: kv.def)
                t.timer = Timer.scheduledTimer(withTimeInterval: 0.45, repeats: false) { [weak self, weak t] _ in
                    guard let self, let t else { return }
                    t.timer = Timer.scheduledTimer(withTimeInterval: 0.09, repeats: true) { [weak self, weak t] _ in
                        guard let self, let t else { return }
                        t.repeats += 1
                        self.delegate?.keyboardViewBackspaceRepeat(self, wordMode: t.repeats > 12)
                    }
                }
                continue
            }
            if characterPreview, kv.def.character != nil, kv.def.style == .letter {
                showPreview(for: kv)
            }
            let choices = popupChoices(for: kv.def)
            if !choices.isEmpty {
                t.timer = Timer.scheduledTimer(withTimeInterval: 0.42, repeats: false) { [weak self, weak t] _ in
                    guard let self, let t, t.mode == .tap || t.mode == .flick else { return }
                    self.showPopup(choices, for: t)
                }
            }
        }
    }

    private func popupChoices(for def: KeyDef) -> [String] {
        if case .switchLanguage = def.action { return languageChoices.count > 1 ? languageChoices : [] }
        if case .text = def.action { return [def.label] + def.alternates }
        return def.popupChoices(shifted: shiftState != .off)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            guard let t = trackers.first(where: { $0.touch === touch }) else { continue }
            let p = touch.location(in: self)
            t.points.append(p)
            switch t.mode {
            case .tap, .flick:
                guard let kv = t.keyView else { break }
                let dx = p.x - t.start.x, dy = p.y - t.start.y
                if case .space = kv.def.action, trackpadEnabled, abs(dx) > 14 {
                    t.mode = .trackpad
                    t.timer?.invalidate()
                    t.anchorX = p.x
                    kv.isPressed = false
                } else if kv.def.isLetter, swipeEnabled, hypot(dx, dy) > max(unit * 0.7, 16) {
                    t.mode = .swipe
                    t.timer?.invalidate()
                    kv.isPressed = false
                    hidePreview()
                    // A swipe cancels any other pending taps.
                    trackers.filter { $0 !== t && $0.mode == .tap }.forEach { $0.mode = .consumed; $0.keyView?.isPressed = false }
                    updateTrail(t.points)
                } else if kv.def.secondary != nil, dy > kv.bounds.height * 0.45, abs(dx) < unit * 0.8 {
                    t.mode = .flick
                    hidePreview()
                    if characterPreview, let sec = kv.def.secondary { showPreview(for: kv, text: sec) }
                } else if !kv.def.isLetter || !swipeEnabled, t.mode == .tap,
                          let other = keyView(at: p), other !== kv, other.def.character != nil, kv.def.character != nil {
                    // Slide onto a neighbouring key (no swipe typing here): retarget.
                    kv.isPressed = false
                    t.timer?.invalidate()
                    t.keyView = other
                    other.isPressed = true
                    if characterPreview, other.def.style == .letter { showPreview(for: other) } else { hidePreview() }
                }
            case .swipe:
                updateTrail(t.points)
            case .trackpad:
                let step: CGFloat = 9
                let n = Int((p.x - t.anchorX) / step)
                if n != 0 {
                    delegate?.keyboardView(self, moveCursorBy: n)
                    t.anchorX += CGFloat(n) * step
                }
            case .popup:
                popup?.track(point: p)
            case .backspace, .consumed:
                break
            }
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            guard let t = trackers.first(where: { $0.touch === touch }) else { continue }
            let def = t.keyView?.def
            switch t.mode {
            case .tap:
                if let def { delegate?.keyboardView(self, didTap: def) }
            case .flick:
                if let def, let sec = def.secondary { delegate?.keyboardView(self, didChoose: sec, from: def) }
            case .popup:
                if let pop = popup, let def {
                    if case .switchLanguage = def.action {
                        delegate?.keyboardView(self, didChooseLanguageAt: pop.selectedIndex)
                    } else {
                        delegate?.keyboardView(self, didChoose: pop.selected, from: def)
                    }
                }
            case .swipe:
                delegate?.keyboardView(self, didSwipe: t.points)
                fadeTrail()
            case .trackpad, .backspace, .consumed:
                break
            }
            finish(t)
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            if let t = trackers.first(where: { $0.touch === touch }) { finish(t) }
        }
        fadeTrail()
    }

    private func finish(_ t: Tracker) {
        t.timer?.invalidate()
        t.keyView?.isPressed = false
        if popupOwner === t { popup?.removeFromSuperview(); popup = nil }
        trackers.removeAll { $0 === t }
        if trackers.isEmpty { hidePreview() }
    }

    func cancelAllTouches() {
        trackers.forEach { $0.timer?.invalidate(); $0.keyView?.isPressed = false }
        trackers.removeAll()
        hidePreview()
        popup?.removeFromSuperview(); popup = nil
        trail.path = nil
    }

    // MARK: Popups & trail

    private func showPreview(for kv: KeyCapView, text: String? = nil) {
        hidePreview()
        let cap = kv.capFrameInSuperview
        let label = text ?? kv.def.displayLabel(shifted: shiftState != .off)
        let v = KeyPreviewView(text: label, theme: theme)
        let w = max(cap.width * 1.25, 44)
        v.frame = CGRect(x: cap.midX - w / 2, y: cap.minY - 54, width: w, height: 52)
        v.frame.origin.x = min(max(v.frame.minX, 0), bounds.width - w)
        addSubview(v)
        preview = v
    }

    private func hidePreview() {
        preview?.removeFromSuperview()
        preview = nil
    }

    private func showPopup(_ choices: [String], for t: Tracker) {
        guard let kv = t.keyView else { return }
        hidePreview()
        t.mode = .popup
        let cellW = max(min(unit, 46), 34) * (choices.contains { $0.count > 2 } ? 1.4 : 1)
        let pop = AlternatesPopupView(choices: choices, theme: theme, cellWidth: cellW)
        let size = pop.preferredSize
        let cap = kv.capFrameInSuperview
        var x = cap.midX - cellW / 2 - 4
        if x + size.width > bounds.width { x = cap.maxX - size.width }
        x = max(0, x)
        pop.frame = CGRect(x: x, y: cap.minY - size.height - 4, width: size.width, height: size.height)
        addSubview(pop)
        pop.track(point: t.points.last ?? t.start)
        popup = pop
        popupOwner = t
    }

    private func updateTrail(_ pts: [CGPoint]) {
        guard pts.count > 1 else { return }
        trail.removeAllAnimations()
        trail.opacity = 1
        trail.strokeColor = theme.trail.cgColor
        let path = UIBezierPath()
        path.move(to: pts[0])
        for p in pts.dropFirst() { path.addLine(to: p) }
        trail.path = path.cgPath
    }

    private func fadeTrail() {
        let anim = CABasicAnimation(keyPath: "opacity")
        anim.fromValue = 1
        anim.toValue = 0
        anim.duration = 0.25
        trail.opacity = 0
        trail.add(anim, forKey: "fade")
    }
}
