import UIKit
import AudioToolbox

/// Duo Keyboard's principal class. Owns the suggestion bar, the key grid and the
/// emoji / GIF panels, and turns key events into text edits on the host app via
/// `textDocumentProxy`.
final class KeyboardViewController: UIInputViewController, KeyboardViewDelegate {

    private enum PanelMode { case keys, emoji, gif }

    private let settings = KeyboardSettings.shared
    private var engine: TypingEngine!
    private let gifService = GIFService()

    private let bar = SuggestionBar()
    private let keyboardView = KeyboardView()
    private let emojiPanel = EmojiPanelView()
    private let gifPanel = GIFPanelView()
    private let sideButton = UIButton(type: .system)
    private var heightConstraint: NSLayoutConstraint?
    private var barHeight: CGFloat { isLaptopMode ? 48 : 42 }

    private var language: KeyboardLanguage = .english
    private var page: KeyboardPage = .letters
    private var shiftState: ShiftState = .off
    private var panel: PanelMode = .keys
    private var gifSearchActive = false
    private var gifQuery = ""
    private var loadedLayoutSignature = ""

    // Typing state
    private var lastShiftTap: Date?
    private var lastSpaceTap: Date?
    private var lastSwipeWord: String?
    private var swipeAlternatives: [String] = []
    private var pendingSpace = false
    private var autoSpaceInserted = false
    private var lastCorrection: (original: String, corrected: String, separator: String)?
    private var issue: (issue: TextIssue, snapshot: String)?
    private var topCompletion: String?
    private lazy var haptic = UIImpactFeedbackGenerator(style: .light)

    // MARK: Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        language = settings.currentLanguage
        engine = TypingEngine(language: language)

        keyboardView.delegate = self
        view.addSubview(keyboardView)
        view.addSubview(bar)
        emojiPanel.isHidden = true
        gifPanel.isHidden = true
        gifPanel.service = gifService
        view.addSubview(emojiPanel)
        view.addSubview(gifPanel)
        sideButton.isHidden = true
        sideButton.addAction(UIAction { [weak self] _ in self?.flipOneHanded() }, for: .touchUpInside)
        view.addSubview(sideButton)

        bar.onSelect = { [weak self] in self?.applySuggestion($0) }
        bar.onTool = { [weak self] in self?.performTool($0) }
        emojiPanel.onEmoji = { [weak self] in self?.insertEmoji($0) }
        emojiPanel.onBack = { [weak self] in self?.showPanel(.keys) }
        emojiPanel.onDelete = { [weak self] in self?.backspace() }
        gifPanel.onBack = { [weak self] in self?.showPanel(.keys) }
        gifPanel.onCategory = { [weak self] in self?.loadGIFs($0) }
        gifPanel.onSearchTap = { [weak self] in self?.beginGIFSearch() }
        gifPanel.onSelect = { [weak self] in self?.copyGIF($0) }

        requestSupplementaryLexicon { [weak self] lexicon in
            guard let self else { return }
            self.engine.loadLexicon(lexicon, custom: self.settings.textReplacements)
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        let newLang = settings.currentLanguage
        if newLang != language { language = newLang; engine.setLanguage(newLang) }
        if heightConstraint == nil {
            let c = view.heightAnchor.constraint(equalToConstant: desiredHeight())
            c.priority = UILayoutPriority(999)
            c.isActive = true
            heightConstraint = c
        }
        applySettings()
        reloadKeys(force: true)
        updateShiftFromContext()
        refreshSuggestions()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        engine.persist()
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        coordinator.animate(alongsideTransition: { _ in
            self.reloadKeys(force: true)
        })
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        heightConstraint?.constant = desiredHeight()
        layoutViews()
        // Width-dependent (automatic split) layout.
        reloadKeys(force: false)
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        engine.persist()
    }

    // MARK: Settings & layout

    private var theme: KeyboardTheme {
        switch settings.theme {
        case .light: return KeyboardTheme(isDark: false)
        case .dark: return KeyboardTheme(isDark: true)
        case .system:
            return KeyboardTheme(isDark: textDocumentProxy.keyboardAppearance == .dark
                                 || traitCollection.userInterfaceStyle == .dark)
        }
    }

    private func applySettings() {
        let t = theme
        keyboardView.theme = t
        bar.theme = t
        emojiPanel.theme = t
        gifPanel.theme = t
        sideButton.tintColor = t.barText
        view.backgroundColor = settings.theme == .system ? .clear : t.background
        keyboardView.swipeEnabled = settings.bool(.slideToType)
        keyboardView.characterPreview = settings.bool(.characterPreview)
        keyboardView.trackpadEnabled = settings.bool(.spaceTrackpad)
        keyboardView.showSecondary = settings.bool(.showSecondarySymbols)
        keyboardView.languageChoices = settings.enabledLanguages.map(\.displayName)
        keyboardView.update(shiftState: shiftState)
    }

    // MARK: iPhone Duo geometry

    private var screen: UIScreen { view.window?.windowScene?.screen ?? UIScreen.main }
    private var profile: DeviceProfile { DeviceProfile.current(for: screen) }
    private var crease: DeviceProfile.Crease? { profile.crease(screenBounds: screen.bounds) }

    /// Inner display held wide: the fold runs top-to-bottom through the keyboard.
    private var creaseIsVertical: Bool {
        if let c = crease, case .vertical = c { return true }
        return false
    }

    /// Inner display held tall: screen y of the fold.
    private var horizontalCreaseY: CGFloat? {
        if let c = crease, case .horizontal(let y) = c { return y }
        return nil
    }

    /// Space the system leaves between the bottom of the keyboard view and the
    /// bottom of the screen (home indicator / globe strip).
    private var bottomInset: CGFloat {
        guard view.window != nil else { return 34 }
        let f = view.convert(view.bounds, to: screen.coordinateSpace)
        let inset = screen.bounds.height - f.maxY
        return (0...160).contains(inset) ? inset : 34
    }

    /// Duo inner display held tall: the crease runs across the screen. Laptop mode
    /// makes the keyboard fill the lower half, like a laptop's keyboard deck.
    private var isLaptopMode: Bool {
        horizontalCreaseY != nil && settings.bool(.laptopMode)
    }

    /// Clear area kept on either side of the fold.
    private var creaseClearance: CGFloat { profile.points(mm: 4) }

    private var isLandscapePhone: Bool {
        let b = screen.bounds
        return b.width > b.height && b.height < 500
    }

    private var rowCount: Int { settings.bool(.numberRow) || page != .letters ? 5 : 4 }

    private func keyHeight() -> CGFloat {
        // Same physical key height on every screen (Duo inner is 430 ppi, outer 460 ppi).
        let base = profile.physical(CGFloat(settings.keyHeight.points))
        return isLandscapePhone ? min(base, profile.physical(36)) : base
    }

    private func desiredHeight() -> CGFloat {
        let normal = barHeight + CGFloat(rowCount) * keyHeight() + 4
        guard let creaseY = horizontalCreaseY else { return normal }
        // Everything must stay below the fold: from the crease (+ clearance) to our bottom edge.
        let belowFold = screen.bounds.height - creaseY - creaseClearance - bottomInset
        guard belowFold > 120 else { return normal }
        return isLaptopMode ? belowFold : min(normal, belowFold)
    }

    private var effectiveSplit: Bool {
        guard settings.oneHanded == .off else { return false }
        switch settings.splitMode {
        case .off: return false
        case .on: return true
        case .auto:
            // Duo inner display held wide: split along the crease, one half per thumb.
            if creaseIsVertical { return settings.bool(.creaseSplit) }
            return profile.display == .other && view.bounds.width >= 600
        }
    }

    private var splitGap: CGFloat {
        let base = view.bounds.width * CGFloat(settings.double(.splitGap))
        if creaseIsVertical { return max(base, 2 * creaseClearance) }
        return base
    }

    private var fieldKind: FieldKind {
        let type: UIKeyboardType = textDocumentProxy.keyboardType ?? .default
        switch type {
        case .emailAddress: return .email
        case .URL: return .url
        case .webSearch: return .web
        default: return .normal
        }
    }

    private var returnLabel: String {
        if gifSearchActive { return "search" }
        let type: UIReturnKeyType = textDocumentProxy.returnKeyType ?? .default
        switch type {
        case .go: return "go"
        case .google, .yahoo, .search: return "search"
        case .send: return "send"
        case .done: return "done"
        case .next: return "next"
        case .join: return "join"
        case .route: return "route"
        case .continue: return "continue"
        case .emergencyCall: return "SOS"
        default:
            switch language {
            case .english: return "return"
            case .spanish: return "intro"
            case .french: return "retour"
            case .german: return "Eingabe"
            }
        }
    }

    private func layoutContext() -> LayoutContext {
        LayoutContext(language: language, page: page, split: effectiveSplit, needsGlobe: needsInputModeSwitchKey,
                      fieldKind: fieldKind, numberRow: settings.bool(.numberRow), returnLabel: returnLabel,
                      gifsEnabled: settings.bool(.gifsEnabled))
    }

    private func reloadKeys(force: Bool) {
        let ctx = layoutContext()
        let signature = "\(ctx.language)|\(ctx.page)|\(ctx.split)|\(ctx.needsGlobe)|\(ctx.fieldKind)|\(ctx.numberRow)|\(ctx.returnLabel)|\(ctx.gifsEnabled)|\(settings.oneHanded)|\(view.bounds.width)|\(profile.display)|\(String(describing: crease))|\(isLaptopMode)"
        guard force || signature != loadedLayoutSignature else { return }
        loadedLayoutSignature = signature
        keyboardView.load(rows: KeyLayouts.build(ctx), shiftState: shiftState, split: ctx.split, gap: splitGap)
        heightConstraint?.constant = desiredHeight()
        layoutViews()
    }

    private func layoutViews() {
        let w = view.bounds.width
        bar.frame = CGRect(x: 0, y: 0, width: w, height: barHeight)
        let area = CGRect(x: 0, y: barHeight, width: w, height: max(0, view.bounds.height - barHeight - 2))
        emojiPanel.frame = area
        gifPanel.frame = CGRect(x: 0, y: 0, width: w, height: view.bounds.height)
        switch settings.oneHanded {
        case .off:
            keyboardView.frame = area
            sideButton.isHidden = true
        case .left, .right:
            var kw = min(area.width * 0.8, area.width - 56)
            // Duo inner held wide: use one panel of the fold, never straddle the crease.
            if creaseIsVertical { kw = area.width / 2 - creaseClearance }
            let left = settings.oneHanded == .left
            keyboardView.frame = CGRect(x: left ? 0 : area.width - kw, y: area.minY, width: kw, height: area.height)
            sideButton.frame = CGRect(x: left ? kw : 0, y: area.minY, width: area.width - kw, height: area.height)
            sideButton.setImage(UIImage(systemName: left ? "chevron.right" : "chevron.left",
                                        withConfiguration: UIImage.SymbolConfiguration(pointSize: 22, weight: .semibold)), for: .normal)
            sideButton.isHidden = panel != .keys
        }
    }

    private func flipOneHanded() {
        settings.oneHanded = settings.oneHanded == .left ? .right : .left
        reloadKeys(force: true)
    }

    private func showPanel(_ mode: PanelMode) {
        panel = mode
        keyboardView.cancelAllTouches()
        keyboardView.isHidden = mode != .keys
        emojiPanel.isHidden = mode != .emoji
        gifPanel.isHidden = mode != .gif
        bar.isHidden = mode == .gif
        if mode == .emoji { emojiPanel.reloadSections() }
        if mode == .keys && gifSearchActive == false { reloadKeys(force: true) }
        layoutViews()
        refreshSuggestions()
    }

    // MARK: Text helpers

    private var proxy: UITextDocumentProxy { textDocumentProxy }
    private var before: String { proxy.documentContextBeforeInput ?? "" }

    private static func isWordChar(_ c: Character) -> Bool {
        c.isLetter || c.isNumber || c == "'" || c == "\u{2019}" || c == "\u{00B7}"
    }

    private func currentWord() -> String {
        var out = ""
        for c in before.reversed() {
            guard Self.isWordChar(c) else { break }
            out.insert(c, at: out.startIndex)
        }
        // Leading apostrophes are quotes, not part of the word.
        while let f = out.first, f == "'" || f == "\u{2019}" { out.removeFirst() }
        return out
    }

    private func previousWord(skippingCurrent: Bool = true) -> String? {
        var text = Substring(before)
        if skippingCurrent { while let l = text.last, Self.isWordChar(l) { text.removeLast() } }
        while let l = text.last, l == " " { text.removeLast() }
        if let l = text.last, ".!?\n".contains(l) { return nil }
        var out = ""
        for c in text.reversed() {
            guard Self.isWordChar(c) else { break }
            out.insert(c, at: out.startIndex)
        }
        return out.isEmpty ? nil : out
    }

    private func needsSpaceBefore() -> Bool {
        guard let last = before.last else { return false }
        return !last.isWhitespace && !"([{¿¡\"“«„‘‚/@#\u{00A0}\u{202F}".contains(last)
    }

    private func removeBackward(_ count: Int) {
        for _ in 0..<max(0, count) { proxy.deleteBackward() }
    }

    private func resetTransientState() {
        lastSwipeWord = nil
        swipeAlternatives = []
        pendingSpace = false
        autoSpaceInserted = false
        lastCorrection = nil
    }

    // MARK: Auto-capitalisation

    private func shouldCapitalize() -> Bool {
        guard settings.bool(.autoCapitalization), page == .letters else { return false }
        let type: UITextAutocapitalizationType = proxy.autocapitalizationType ?? .sentences
        switch type {
        case .none: return false
        case .allCharacters: return true
        case .words: return before.isEmpty || (before.last?.isWhitespace ?? true)
        default: return startsSentence()
        }
    }

    private func startsSentence() -> Bool {
        let text = before
        if text.isEmpty || text.last == "\n" { return true }
        guard let last = text.last, last.isWhitespace else { return false }
        var trimmed = Substring(text)
        while let l = trimmed.last, l.isWhitespace { trimmed.removeLast() }
        guard var p = trimmed.last else { return true }
        if p == "\u{201D}" || p == "\u{00BB}" || p == ")" {
            trimmed.removeLast()
            p = trimmed.last ?? " "
        }
        return ".!?…".contains(p)
    }

    private func updateShiftFromContext() {
        guard shiftState != .locked else { return }
        let want: ShiftState = shouldCapitalize() ? .once : .off
        if want != shiftState { shiftState = want; keyboardView.update(shiftState: want) }
    }

    // MARK: Feedback

    private func playFeedback(for key: KeyDef) {
        if settings.bool(.hapticFeedback), hasFullAccess { haptic.impactOccurred() }
        guard settings.bool(.sound) else { return }
        switch key.action {
        case .backspace: AudioServicesPlaySystemSound(1155)
        case .character, .space, .text: AudioServicesPlaySystemSound(1104)
        default: AudioServicesPlaySystemSound(1156)
        }
    }

    // MARK: KeyboardViewDelegate

    func keyboardView(_ view: KeyboardView, didTouchDown key: KeyDef) {
        playFeedback(for: key)
    }

    func keyboardView(_ view: KeyboardView, didTap key: KeyDef) {
        switch key.action {
        case .character:
            if let s = key.output(shifted: shiftState != .off) { typeText(s) }
        case .text(let s):
            typeText(s, raw: true)
        case .space: space()
        case .backspace: backspace()
        case .returnKey: returnKey()
        case .tab: tab()
        case .shift: shiftTapped()
        case .capsLock:
            shiftState = shiftState == .locked ? .off : .locked
            keyboardView.update(shiftState: shiftState)
        case .nextKeyboard: advanceToNextInputMode()
        case .switchLanguage: cycleLanguage()
        case .symbols: page = .symbols; reloadKeys(force: true)
        case .moreSymbols: page = .moreSymbols; reloadKeys(force: true)
        case .letters: page = .letters; reloadKeys(force: true); updateShiftFromContext()
        case .emoji: showPanel(.emoji)
        case .gif: openGIFs()
        case .cursorLeft: moveCursor(-1)
        case .cursorRight: moveCursor(1)
        case .dismiss: dismissKeyboard()
        }
    }

    func keyboardView(_ view: KeyboardView, didChoose text: String, from key: KeyDef) {
        if case .text = key.action { typeText(text, raw: true) } else { typeText(text) }
    }

    func keyboardView(_ view: KeyboardView, didChooseLanguageAt index: Int) {
        let langs = settings.enabledLanguages
        guard index < langs.count else { return }
        setLanguage(langs[index])
    }

    func keyboardView(_ view: KeyboardView, moveCursorBy offset: Int) { moveCursor(offset) }

    func keyboardViewBackspaceRepeat(_ view: KeyboardView, wordMode: Bool) {
        if gifSearchActive { if !gifQuery.isEmpty { gifQuery.removeLast() }; refreshSuggestions(); return }
        if wordMode {
            var n = 0
            for c in before.reversed() { if c.isWhitespace { n += 1 } else { break } }
            let trimmed = before.dropLast(n)
            for c in trimmed.reversed() { if Self.isWordChar(c) { n += 1 } else { break } }
            removeBackward(max(1, n))
        } else {
            proxy.deleteBackward()
        }
        resetTransientState()
        afterEdit()
    }

    func keyboardView(_ view: KeyboardView, didSwipe path: [CGPoint]) {
        let prev = previousWord(skippingCurrent: false)
        let eng: TypingEngine = engine
        let results = SwipeDecoder.decode(path: path, centers: keyboardView.letterCenters, unit: keyboardView.unit,
                                          words: eng.words) { w in eng.bigramBoost(previous: prev, word: w) }
        guard let best = results.first else { return }
        let cased = { (w: String) -> String in
            switch self.shiftState {
            case .locked: return w.uppercased()
            case .once: return w.prefix(1).uppercased() + w.dropFirst()
            case .off: return self.engine.casedForLanguage(w)
            }
        }
        let word = cased(best.word)
        if gifSearchActive {
            gifQuery += (gifQuery.isEmpty || gifQuery.hasSuffix(" ") ? "" : " ") + word
            refreshSuggestions()
            return
        }
        if needsSpaceBefore() { proxy.insertText(" ") }
        proxy.insertText(word)
        engine.learn(word: word, previous: prev)
        lastCorrection = nil
        autoSpaceInserted = false
        lastSwipeWord = word
        swipeAlternatives = results.dropFirst().map { cased($0.word) }.filter { $0 != word }
        pendingSpace = true
        if shiftState == .once { shiftState = .off; keyboardView.update(shiftState: .off) }
        issue = nil
        refreshSuggestions()
    }

    // MARK: Typing

    private static let correctionTriggers: Set<String> = [" ", ".", ",", "!", "?", ";", ":", "\n", ")", "\"", "…", "¿", "¡"]

    private func typeText(_ s: String, raw: Bool = false) {
        if gifSearchActive { gifQuery += s; refreshSuggestions(); return }
        let chars = Array(s)
        let isWordInput = !raw && chars.count == 1 && (chars[0].isLetter || chars[0].isNumber)
        let isApostropheInWord = !raw && (s == "'" || s == "\u{2019}") && (before.last?.isLetter ?? false)

        if isWordInput || isApostropheInWord {
            if isWordInput, pendingSpace, needsSpaceBefore() { proxy.insertText(" ") }
            let out = isApostropheInWord && settings.bool(.smartPunctuation) ? "\u{2019}" : s
            proxy.insertText(out)
            resetTransientState()
            if shiftState == .once { shiftState = .off; keyboardView.update(shiftState: .off) }
            issue = nil
            refreshSuggestions()
            return
        }

        if raw {
            if pendingSpace, needsSpaceBefore(), s.first?.isLetter == true { proxy.insertText(" ") }
            proxy.insertText(s)
            resetTransientState()
            afterEdit()
            return
        }
        commitWord(separator: s, correct: Self.correctionTriggers.contains(s))
    }

    /// Applies text replacement / autocorrection to the word before the cursor,
    /// then inserts the separator (with smart punctuation), learns, and re-checks grammar.
    private func commitWord(separator: String, correct: Bool) {
        let isSpaceLike = separator == " " || separator == "\n"
        // "word |" + "." → "word." (remove the space we added after a suggestion/swipe).
        if !isSpaceLike, autoSpaceInserted, before.hasSuffix(" ") { proxy.deleteBackward() }
        pendingSpace = false

        let word = currentWord()
        let prev = previousWord()
        var final = word
        lastCorrection = nil
        if correct, !word.isEmpty {
            var replacement: String?
            if let rep = engine.shortcuts[word.lowercased()] {
                replacement = rep
            } else if settings.bool(.autoCorrection), proxy.autocorrectionType != .no, fieldKind == .normal {
                replacement = engine.autocorrection(for: word, previous: prev)
            } else if settings.bool(.autoCapitalization), language == .english, word == "i" {
                replacement = "I"
            }
            if let r = replacement, r != word {
                removeBackward(word.count)
                proxy.insertText(r)
                final = r
                lastCorrection = (word, r, separator)
            }
        }

        if settings.bool(.smartPunctuation) {
            switch SmartPunctuation.transform(separator, before: before, language: language) {
            case .insert(let t): proxy.insertText(t)
            case .replacePrevious(let n, let t): removeBackward(n); proxy.insertText(t)
            }
        } else {
            proxy.insertText(separator)
        }
        if lastCorrection != nil {
            // Remember exactly what followed the correction (smart punctuation may have
            // expanded it) so Delete can undo it.
            lastCorrection?.separator = String(before.suffix(lastCorrectionTailLength(separator)))
        }
        if !word.isEmpty, !final.contains(" ") { engine.learn(word: final, previous: prev) }
        autoSpaceInserted = false
        lastSwipeWord = nil
        swipeAlternatives = []
        afterEdit(checkGrammar: true)
    }

    /// Smart punctuation can expand a separator (e.g. French " ?" → "\u{202F}?").
    private func lastCorrectionTailLength(_ separator: String) -> Int {
        guard let c = lastCorrection, let r = before.range(of: c.corrected, options: .backwards) else { return separator.count }
        return before.distance(from: r.upperBound, to: before.endIndex)
    }

    private func space() {
        if gifSearchActive { gifQuery += " "; refreshSuggestions(); return }
        let now = Date()
        if settings.bool(.periodShortcut), let t = lastSpaceTap, now.timeIntervalSince(t) < 0.45,
           before.hasSuffix(" "), let p = before.dropLast().last, p.isLetter || p.isNumber || p == "\u{201D}" || p == ")" {
            proxy.deleteBackward()
            proxy.insertText(". ")
            lastSpaceTap = nil
            resetTransientState()
            afterEdit(checkGrammar: true)
            return
        }
        lastSpaceTap = now
        commitWord(separator: " ", correct: true)
    }

    private func returnKey() {
        if gifSearchActive {
            gifSearchActive = false
            showPanel(.gif)
            loadGIFs(gifQuery)
            return
        }
        commitWord(separator: "\n", correct: true)
    }

    private func tab() {
        if settings.bool(.showPredictionsInline), let completion = topCompletion, !currentWord().isEmpty {
            replaceCurrentWord(with: completion, addSpace: true)
            return
        }
        proxy.insertText("\t")
        resetTransientState()
        afterEdit()
    }

    private func shiftTapped() {
        let now = Date()
        if settings.bool(.enableCapsLock), let t = lastShiftTap, now.timeIntervalSince(t) < 0.35 {
            shiftState = .locked
            lastShiftTap = nil
        } else {
            shiftState = shiftState == .off ? .once : .off
            lastShiftTap = now
        }
        keyboardView.update(shiftState: shiftState)
    }

    private func backspace() {
        if gifSearchActive { if !gifQuery.isEmpty { gifQuery.removeLast() }; refreshSuggestions(); return }
        // Undo the autocorrection that just happened ("teh " → "the " → Delete → "teh ").
        if let c = lastCorrection, before.hasSuffix(c.corrected + c.separator) {
            removeBackward(c.corrected.count + c.separator.count)
            proxy.insertText(c.original)
            engine.reject(correctionOf: c.original)
            resetTransientState()
            afterEdit()
            return
        }
        if settings.bool(.deleteSlideToTypeByWord), let w = lastSwipeWord, before.hasSuffix(w) {
            removeBackward(w.count)
            resetTransientState()
            afterEdit()
            return
        }
        proxy.deleteBackward()
        resetTransientState()
        afterEdit()
    }

    private func moveCursor(_ offset: Int) {
        proxy.adjustTextPosition(byCharacterOffset: offset)
        resetTransientState()
        issue = nil
        // The proxy's context updates asynchronously after a cursor move.
        DispatchQueue.main.async { self.afterEdit() }
    }

    private func insertEmoji(_ e: String) {
        if pendingSpace, needsSpaceBefore() { proxy.insertText(" ") }
        proxy.insertText(e)
        resetTransientState()
        afterEdit()
    }

    private func afterEdit(checkGrammar: Bool = false) {
        if checkGrammar { runGrammarCheck() } else if issue.map({ !before.hasSuffix($0.snapshot) }) ?? false { issue = nil }
        updateShiftFromContext()
        refreshSuggestions()
    }

    // MARK: Languages

    private func cycleLanguage() {
        let langs = settings.enabledLanguages
        guard langs.count > 1 else { return }
        let i = langs.firstIndex(of: language) ?? 0
        setLanguage(langs[(i + 1) % langs.count])
    }

    private func setLanguage(_ lang: KeyboardLanguage) {
        guard lang != language else { return }
        language = lang
        settings.currentLanguage = lang
        engine.setLanguage(lang)
        page = .letters
        reloadKeys(force: true)
        ToastView.show(lang.displayName + " · " + lang.layoutName, in: view)
        refreshSuggestions()
    }

    // MARK: Grammar & spelling

    private func runGrammarCheck() {
        issue = nil
        guard settings.bool(.checkSpellingGrammar) else { return }
        // Check the current sentence (or the last ~300 characters).
        let text = String(before.suffix(300))
        var start = text.startIndex
        if let r = text.dropLast(2).lastIndex(where: { "\n".contains($0) }) { start = text.index(after: r) }
        let snapshot = String(text[start...])
        guard snapshot.contains(where: \.isLetter) else { return }
        let eng: TypingEngine = engine
        let issues = GrammarChecker.check(snapshot, language: language) { w in eng.isValid(w) }
        // Only surface issues near the cursor (in the last two sentences).
        let recent = issues.filter { snapshot.count - $0.range.upperBound < 120 }
        if let last = recent.last {
            issue = (last, snapshot)
            return
        }
        // Spelling: the word just committed is still misspelled and wasn't corrected.
        let words = snapshot.split(whereSeparator: { !Self.isWordChar($0) })
        if let w = words.last.map(String.init), w.count > 1, !engine.isValid(w),
           let guess = engine.corrections(for: w, previous: nil).first?.word,
           let r = snapshot.range(of: w, options: .backwards) {
            let s = snapshot.distance(from: snapshot.startIndex, to: r.lowerBound)
            issue = (TextIssue(range: s..<(s + w.count), replacement: engine.applyCase(of: w, to: guess),
                               message: "Spelling", kind: .spelling), snapshot)
        }
    }

    private func apply(_ pending: (issue: TextIssue, snapshot: String)) {
        let snapshot = pending.snapshot
        guard before.hasSuffix(snapshot) else { issue = nil; refreshSuggestions(); return }
        let chars = Array(snapshot)
        let lower = pending.issue.range.lowerBound, upper = min(pending.issue.range.upperBound, chars.count)
        let tail = String(chars[upper...])
        removeBackward(chars.count - lower)
        proxy.insertText(pending.issue.replacement + tail)
        issue = nil
        resetTransientState()
        afterEdit(checkGrammar: true)
    }

    // MARK: Suggestions

    private func refreshSuggestions() {
        topCompletion = nil
        if gifSearchActive {
            bar.showTitle("🔍 " + gifQuery + "▏")
            return
        }
        bar.showTitle(nil)
        guard panel != .gif else { return }
        var items: [Suggestion] = []
        let predictive = settings.bool(.predictiveText)
        let ctx = before

        if settings.bool(.showMathResults), let result = MathEvaluator.resultForTrailingExpression(ctx, language: language) {
            bar.set([Suggestion(result, kind: .math, isDefault: true)])
            return
        }

        if let w = lastSwipeWord, ctx.hasSuffix(w) {
            let alts = swipeAlternatives.prefix(2).map { Suggestion($0, kind: .swipeAlternative) }
            items = alts.isEmpty ? [Suggestion(w, kind: .swipeAlternative, isDefault: true)]
                : [alts[0], Suggestion(w, kind: .swipeAlternative, isDefault: true)] + alts.dropFirst()
            bar.set(items)
            return
        }

        let word = currentWord()
        let prev = previousWord()
        if word.isEmpty {
            if let pending = issue {
                items.append(Suggestion(pending.issue.replacement, kind: pending.issue.kind == .spelling ? .spelling : .grammar,
                                        display: pending.issue.replacement, issue: pending.issue))
            }
            if predictive, panel == .keys {
                let prevForNext = previousWord(skippingCurrent: false)
                items += engine.nextWords(after: prevForNext, limit: 3 - items.count).map { Suggestion($0, kind: .prediction) }
            }
            bar.set(items)
            return
        }

        var correction: String?
        if let rep = engine.shortcuts[word.lowercased()] {
            items.append(Suggestion(word, kind: .literal))
            items.append(Suggestion(rep, kind: .replacement, isDefault: true))
        } else if settings.bool(.autoCorrection), proxy.autocorrectionType != .no, fieldKind == .normal,
                  let c = engine.autocorrection(for: word, previous: prev), c != word {
            correction = c
            items.append(Suggestion(word, kind: .literal))
            items.append(Suggestion(c, kind: .correction, isDefault: true))
        }

        var completions: [String] = []
        if predictive {
            completions = engine.completions(prefix: word, previous: prev, limit: 3).filter { $0 != correction }
            topCompletion = completions.first
        }
        if items.isEmpty {
            items.append(Suggestion(word, kind: .literal))
            if settings.bool(.checkSpellingGrammar), !engine.isValid(word), word.count > 2 {
                let guesses = engine.corrections(for: word, previous: prev).prefix(2).map { engine.applyCase(of: word, to: $0.word) }
                items += guesses.map { Suggestion($0, kind: .correction) }
            }
        }
        for c in completions where items.count < 3 { items.append(Suggestion(c, kind: .completion)) }
        if settings.bool(.emojiSuggestions), let e = EmojiData.suggestion(for: word, language: language) {
            if items.count >= 3 { items[items.count - 1] = Suggestion(e, kind: .emoji) } else { items.append(Suggestion(e, kind: .emoji)) }
        }
        if !predictive { items = items.filter { $0.kind != .completion } }
        bar.set(items)
    }

    private func replaceCurrentWord(with text: String, addSpace: Bool) {
        let word = currentWord()
        let prev = previousWord()
        removeBackward(word.count)
        proxy.insertText(text + (addSpace ? " " : ""))
        if !text.contains(" ") { engine.learn(word: text, previous: prev) }
        resetTransientState()
        autoSpaceInserted = addSpace
        afterEdit(checkGrammar: true)
    }

    private func applySuggestion(_ s: Suggestion) {
        switch s.kind {
        case .swipeAlternative:
            guard let w = lastSwipeWord, before.hasSuffix(w) else { break }
            removeBackward(w.count)
            proxy.insertText(s.text)
            let alts = (swipeAlternatives + [w]).filter { $0 != s.text }
            lastSwipeWord = s.text
            swipeAlternatives = alts
            pendingSpace = true
            refreshSuggestions()
        case .literal:
            engine.reject(correctionOf: s.text)
            engine.learn(word: s.text, previous: previousWord())
            proxy.insertText(" ")
            resetTransientState()
            autoSpaceInserted = true
            afterEdit(checkGrammar: true)
        case .correction, .completion, .replacement:
            replaceCurrentWord(with: s.text, addSpace: true)
        case .prediction:
            if needsSpaceBefore() { proxy.insertText(" ") }
            proxy.insertText(s.text + " ")
            engine.learn(word: s.text, previous: previousWord(skippingCurrent: false))
            resetTransientState()
            autoSpaceInserted = true
            afterEdit()
        case .emoji:
            let w = currentWord()
            if !w.isEmpty { removeBackward(w.count) }
            proxy.insertText(s.text)
            resetTransientState()
            afterEdit()
        case .math:
            proxy.insertText(s.text)
            resetTransientState()
            afterEdit()
        case .grammar, .spelling:
            if let pending = issue { apply(pending) }
        }
    }

    // MARK: Toolbar

    private func performTool(_ action: ToolAction) {
        switch action {
        case .cut, .copy:
            guard let sel = proxy.selectedText, !sel.isEmpty else { ToastView.show("Select some text first", in: view); return }
            guard hasFullAccess else { ToastView.show("Allow Full Access to use the clipboard", in: view); return }
            UIPasteboard.general.string = sel
            if action == .cut { proxy.deleteBackward() } else { ToastView.show("Copied", in: view) }
        case .paste:
            guard hasFullAccess else { ToastView.show("Allow Full Access to use the clipboard", in: view); return }
            if let s = UIPasteboard.general.string { proxy.insertText(s) }
        case .wordLeft:
            var n = 0
            for c in before.reversed() { if c.isWhitespace && n == 0 { continue }; if c.isWhitespace { break }; n += 1 }
            let spaces = before.reversed().prefix { $0.isWhitespace }.count
            moveCursor(-(n + spaces))
            return
        case .wordRight:
            let after = proxy.documentContextAfterInput ?? ""
            let spaces = after.prefix { $0.isWhitespace }.count
            let word = after.dropFirst(spaces).prefix { !$0.isWhitespace }.count
            moveCursor(spaces + word)
            return
        case .lineStart:
            let n = before.reversed().prefix { $0 != "\n" }.count
            moveCursor(-n)
            return
        case .lineEnd:
            let n = (proxy.documentContextAfterInput ?? "").prefix { $0 != "\n" }.count
            moveCursor(n)
            return
        case .split:
            settings.oneHanded = .off
            settings.splitMode = effectiveSplit ? .off : .on
            reloadKeys(force: true)
        case .oneHandedLeft:
            settings.oneHanded = .left
            reloadKeys(force: true)
        case .oneHandedRight:
            settings.oneHanded = .right
            reloadKeys(force: true)
        case .fullWidth:
            settings.oneHanded = .off
            settings.splitMode = .off
            reloadKeys(force: true)
        case .laptop:
            settings.set(!settings.bool(.laptopMode), for: .laptopMode)
            if horizontalCreaseY == nil {
                ToastView.show("Laptop mode works on iPhone Duo's inner display held upright", in: view)
            }
            heightConstraint?.constant = desiredHeight()
            reloadKeys(force: true)
        case .dismiss:
            dismissKeyboard()
        }
        resetTransientState()
        afterEdit()
    }

    // MARK: GIFs

    private func openGIFs() {
        showPanel(.gif)
        gifQuery = ""
        gifPanel.setQuery("")
        loadGIFs("")
    }

    private func loadGIFs(_ query: String) {
        gifPanel.setQuery(query)
        guard hasFullAccess else { gifPanel.show(.failure(GIFError.noAccess)); return }
        gifPanel.setLoading()
        gifService.search(query, provider: settings.gifProvider, apiKey: settings.string(.gifAPIKey), language: language) { [weak self] result in
            self?.gifPanel.show(result)
        }
    }

    private func beginGIFSearch() {
        gifSearchActive = true
        gifQuery = ""
        page = .letters
        showPanel(.keys)
        reloadKeys(force: true)
        refreshSuggestions()
    }

    private func copyGIF(_ item: GIFItem) {
        guard hasFullAccess else { ToastView.show(GIFError.noAccess.localizedDescription, in: view); return }
        ToastView.show("Copying GIF…", in: view)
        gifService.copyToPasteboard(item) { [weak self] ok in
            guard let self else { return }
            ToastView.show(ok ? "GIF copied — long-press the message field and tap Paste" : "Couldn't download that GIF", in: self.view)
        }
    }

    // MARK: Host text changes

    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        if let w = lastSwipeWord, !before.hasSuffix(w) { resetTransientState() }
        if let c = lastCorrection, !before.hasSuffix(c.corrected + c.separator) { lastCorrection = nil }
        applySettings()
        reloadKeys(force: false)
        updateShiftFromContext()
        refreshSuggestions()
    }
}
