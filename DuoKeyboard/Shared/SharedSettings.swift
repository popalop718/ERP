import Foundation

/// Every user-facing option, mirroring iOS Settings → General → Keyboard plus the
/// Duo-specific layout options (split, one-handed, number row, GIF provider).
enum SettingKey: String, CaseIterable {
    // Feedback
    case characterPreview, hapticFeedback, sound
    // All Keyboards
    case autoCapitalization, autoCorrection, showMathResults, enableCapsLock
    case smartPunctuation, periodShortcut
    // Typing (per-language section in iOS)
    case predictiveText, showPredictionsInline, checkSpellingGrammar
    case slideToType, deleteSlideToTypeByWord
    // Emoji & GIFs
    case emojiSuggestions, gifsEnabled, gifProvider, gifAPIKey
    // Layout
    case oneHanded, splitMode, splitGap, numberRow, showSecondarySymbols
    case keyHeight, spaceTrackpad, theme
    // Languages & text
    case enabledLanguages, currentLanguage, textReplacements
}

enum OneHandedMode: String, CaseIterable, Identifiable {
    case off, left, right
    var id: String { rawValue }
    var title: String { ["off": "Off", "left": "Left", "right": "Right"][rawValue]! }
}

enum SplitMode: String, CaseIterable, Identifiable {
    case off, on, auto
    var id: String { rawValue }
    var title: String {
        switch self {
        case .off: return "Off"
        case .on: return "Always"
        case .auto: return "Automatic (wide screens)"
        }
    }
}

enum KeyHeightOption: String, CaseIterable, Identifiable {
    case compact, normal, large
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var points: Double { ["compact": 40, "normal": 46, "large": 54][rawValue]! }
}

enum ThemeOption: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

enum GIFProvider: String, CaseIterable, Identifiable {
    case tenor, giphy
    var id: String { rawValue }
    var title: String { self == .tenor ? "Tenor" : "GIPHY" }
}

/// Settings live in the shared App Group so the container app can edit what the
/// keyboard reads. Without "Allow Full Access" iOS hides the App Group from the
/// keyboard, so it falls back to the defaults registered here plus values it saved
/// locally (layout changes made from the keyboard's own toolbar).
final class KeyboardSettings {
    static let shared = KeyboardSettings()

    static var appGroupID: String {
        (Bundle.main.object(forInfoDictionaryKey: "AppGroupIdentifier") as? String)
            ?? "group.com.example.duokeyboard"
    }

    static let defaultValues: [String: Any] = [
        SettingKey.characterPreview.rawValue: true,
        SettingKey.hapticFeedback.rawValue: false,
        SettingKey.sound.rawValue: false,
        SettingKey.autoCapitalization.rawValue: true,
        SettingKey.autoCorrection.rawValue: true,
        SettingKey.showMathResults.rawValue: true,
        SettingKey.enableCapsLock.rawValue: true,
        SettingKey.smartPunctuation.rawValue: true,
        SettingKey.periodShortcut.rawValue: true,
        SettingKey.predictiveText.rawValue: true,
        SettingKey.showPredictionsInline.rawValue: true,
        SettingKey.checkSpellingGrammar.rawValue: true,
        SettingKey.slideToType.rawValue: true,
        SettingKey.deleteSlideToTypeByWord.rawValue: true,
        SettingKey.emojiSuggestions.rawValue: true,
        SettingKey.gifsEnabled.rawValue: true,
        SettingKey.gifProvider.rawValue: GIFProvider.tenor.rawValue,
        SettingKey.gifAPIKey.rawValue: "",
        SettingKey.oneHanded.rawValue: OneHandedMode.off.rawValue,
        SettingKey.splitMode.rawValue: SplitMode.auto.rawValue,
        SettingKey.splitGap.rawValue: 0.16,
        SettingKey.numberRow.rawValue: true,
        SettingKey.showSecondarySymbols.rawValue: true,
        SettingKey.keyHeight.rawValue: KeyHeightOption.normal.rawValue,
        SettingKey.spaceTrackpad.rawValue: true,
        SettingKey.theme.rawValue: ThemeOption.system.rawValue,
        SettingKey.enabledLanguages.rawValue: KeyboardLanguage.allCases.map(\.rawValue),
        SettingKey.currentLanguage.rawValue: KeyboardLanguage.english.rawValue,
        SettingKey.textReplacements.rawValue: ["omw": "On my way!", "brb": "Be right back"],
    ]

    /// Keys the keyboard itself can change; the newest write (app or keyboard) wins.
    private static let syncedKeys: Set<SettingKey> = [.currentLanguage, .splitMode, .oneHanded]

    let group: UserDefaults
    private let local = UserDefaults.standard

    init() {
        group = UserDefaults(suiteName: Self.appGroupID) ?? .standard
        group.register(defaults: Self.defaultValues)
        local.register(defaults: Self.defaultValues)
    }

    private func store(for key: SettingKey) -> UserDefaults {
        guard Self.syncedKeys.contains(key) else { return group }
        let g = group.double(forKey: key.rawValue + ".ts")
        let l = local.double(forKey: key.rawValue + ".ts")
        return l > g ? local : group
    }

    func bool(_ key: SettingKey) -> Bool { store(for: key).bool(forKey: key.rawValue) }
    func string(_ key: SettingKey) -> String { store(for: key).string(forKey: key.rawValue) ?? "" }
    func double(_ key: SettingKey) -> Double { store(for: key).double(forKey: key.rawValue) }

    func set(_ value: Any?, for key: SettingKey) {
        let ts = Date().timeIntervalSince1970
        group.set(value, forKey: key.rawValue)
        group.set(ts, forKey: key.rawValue + ".ts")
        if Self.syncedKeys.contains(key) {
            local.set(value, forKey: key.rawValue)
            local.set(ts, forKey: key.rawValue + ".ts")
        }
    }

    // MARK: Typed accessors

    var enabledLanguages: [KeyboardLanguage] {
        get {
            let raw = group.stringArray(forKey: SettingKey.enabledLanguages.rawValue) ?? []
            let langs = raw.compactMap(KeyboardLanguage.init(rawValue:))
            return langs.isEmpty ? [.english] : langs
        }
        set { set(newValue.map(\.rawValue), for: .enabledLanguages) }
    }

    var currentLanguage: KeyboardLanguage {
        get {
            let lang = KeyboardLanguage(rawValue: string(.currentLanguage)) ?? .english
            return enabledLanguages.contains(lang) ? lang : enabledLanguages[0]
        }
        set { set(newValue.rawValue, for: .currentLanguage) }
    }

    var oneHanded: OneHandedMode {
        get { OneHandedMode(rawValue: string(.oneHanded)) ?? .off }
        set { set(newValue.rawValue, for: .oneHanded) }
    }

    var splitMode: SplitMode {
        get { SplitMode(rawValue: string(.splitMode)) ?? .auto }
        set { set(newValue.rawValue, for: .splitMode) }
    }

    var keyHeight: KeyHeightOption { KeyHeightOption(rawValue: string(.keyHeight)) ?? .normal }
    var theme: ThemeOption { ThemeOption(rawValue: string(.theme)) ?? .system }
    var gifProvider: GIFProvider { GIFProvider(rawValue: string(.gifProvider)) ?? .tenor }

    var textReplacements: [String: String] {
        get { group.dictionary(forKey: SettingKey.textReplacements.rawValue) as? [String: String] ?? [:] }
        set { set(newValue, for: .textReplacements) }
    }
}
