import SwiftUI

/// Mirrors iOS Settings → General → Keyboard, for Duo Keyboard.
struct SettingsView: View {
    @AppStorage(SettingKey.characterPreview.rawValue, store: sharedDefaults) private var characterPreview = true
    @AppStorage(SettingKey.hapticFeedback.rawValue, store: sharedDefaults) private var hapticFeedback = false
    @AppStorage(SettingKey.sound.rawValue, store: sharedDefaults) private var sound = false
    @AppStorage(SettingKey.autoCapitalization.rawValue, store: sharedDefaults) private var autoCapitalization = true
    @AppStorage(SettingKey.autoCorrection.rawValue, store: sharedDefaults) private var autoCorrection = true
    @AppStorage(SettingKey.showMathResults.rawValue, store: sharedDefaults) private var showMathResults = true
    @AppStorage(SettingKey.enableCapsLock.rawValue, store: sharedDefaults) private var enableCapsLock = true
    @AppStorage(SettingKey.smartPunctuation.rawValue, store: sharedDefaults) private var smartPunctuation = true
    @AppStorage(SettingKey.periodShortcut.rawValue, store: sharedDefaults) private var periodShortcut = true
    @AppStorage(SettingKey.predictiveText.rawValue, store: sharedDefaults) private var predictiveText = true
    @AppStorage(SettingKey.showPredictionsInline.rawValue, store: sharedDefaults) private var showPredictionsInline = true
    @AppStorage(SettingKey.checkSpellingGrammar.rawValue, store: sharedDefaults) private var checkSpellingGrammar = true
    @AppStorage(SettingKey.slideToType.rawValue, store: sharedDefaults) private var slideToType = true
    @AppStorage(SettingKey.deleteSlideToTypeByWord.rawValue, store: sharedDefaults) private var deleteSlideToTypeByWord = true
    @AppStorage(SettingKey.emojiSuggestions.rawValue, store: sharedDefaults) private var emojiSuggestions = true
    @AppStorage(SettingKey.gifsEnabled.rawValue, store: sharedDefaults) private var gifsEnabled = true
    @AppStorage(SettingKey.gifProvider.rawValue, store: sharedDefaults) private var gifProvider = GIFProvider.tenor.rawValue
    @AppStorage(SettingKey.gifAPIKey.rawValue, store: sharedDefaults) private var gifAPIKey = ""
    @AppStorage(SettingKey.splitGap.rawValue, store: sharedDefaults) private var splitGap = 0.16
    @AppStorage(SettingKey.numberRow.rawValue, store: sharedDefaults) private var numberRow = true
    @AppStorage(SettingKey.showSecondarySymbols.rawValue, store: sharedDefaults) private var showSecondarySymbols = true
    @AppStorage(SettingKey.keyHeight.rawValue, store: sharedDefaults) private var keyHeight = KeyHeightOption.normal.rawValue
    @AppStorage(SettingKey.spaceTrackpad.rawValue, store: sharedDefaults) private var spaceTrackpad = true
    @AppStorage(SettingKey.theme.rawValue, store: sharedDefaults) private var theme = ThemeOption.system.rawValue
    @AppStorage(SettingKey.creaseSplit.rawValue, store: sharedDefaults) private var creaseSplit = true
    @State private var laptopMode = KeyboardSettings.shared.bool(.laptopMode)
    @State private var profile = DeviceProfile.current(for: UIScreen.main)

    // Synced with the keyboard toolbar (newest change wins), so go through KeyboardSettings.
    @State private var oneHanded = KeyboardSettings.shared.oneHanded
    @State private var splitMode = KeyboardSettings.shared.splitMode
    @State private var languageCount = KeyboardSettings.shared.enabledLanguages.count

    var body: some View {
        Form {
            Section {
                SetupCard()
                NavigationLink("Try Duo Keyboard") { PlaygroundView() }
            }

            Section {
                LabeledContent("This Display", value: profile.displayName)
                Toggle("Split Along the Crease", isOn: $creaseSplit)
                Toggle("Laptop Mode", isOn: $laptopMode)
                    .onChange(of: laptopMode) { KeyboardSettings.shared.set($0, for: .laptopMode) }
            } header: {
                Text("iPhone Duo")
            } footer: {
                Text("Inner display held wide (book pose): with Split Keyboard on Automatic, the keyboard splits into two equal halves, one for each thumb. The gap sits on the fold, so no key is ever on the crease. Inner display held upright: keys always stay below the fold. Laptop Mode fills the whole lower half, so with iPhone Duo half-open on a table it works like a laptop keyboard. Outer display: the full keyboard, sized to the same physical key size (460 ppi vs 430 ppi inside).")
            }

            Section {
                NavigationLink { LanguagesView() } label: {
                    LabeledContent("Keyboards", value: "\(languageCount)")
                }
            }

            Section {
                NavigationLink("Text Replacement") { TextReplacementView() }
                Picker("One-Handed Keyboard", selection: $oneHanded) {
                    ForEach(OneHandedMode.allCases) { Text($0.title).tag($0) }
                }
                .onChange(of: oneHanded) { KeyboardSettings.shared.oneHanded = $0 }
            }

            Section {
                Toggle("Character Preview", isOn: $characterPreview)
                Toggle("Haptic Feedback", isOn: $hapticFeedback)
                Toggle("Sound", isOn: $sound)
            } footer: {
                Text("Haptic feedback and sound need Allow Full Access. Sound follows your iPhone's ring/silent switch.")
            }

            Section {
                Toggle("Auto-Capitalization", isOn: $autoCapitalization)
                Toggle("Auto-Correction", isOn: $autoCorrection)
                Toggle("Show Math Results", isOn: $showMathResults)
                Toggle("Enable Caps Lock", isOn: $enableCapsLock)
                Toggle("Smart Punctuation", isOn: $smartPunctuation)
                Toggle("\u{201C}.\u{201D} Shortcut", isOn: $periodShortcut)
            } header: {
                Text("All Keyboards")
            } footer: {
                Text("Double tapping the space bar will insert a period followed by a space.")
            }

            Section {
                Picker("Split Keyboard", selection: $splitMode) {
                    ForEach(SplitMode.allCases) { Text($0.title).tag($0) }
                }
                .onChange(of: splitMode) { KeyboardSettings.shared.splitMode = $0 }
                VStack(alignment: .leading) {
                    Text("Split Gap: \(Int(splitGap * 100))% of width")
                    Slider(value: $splitGap, in: 0.06...0.4, step: 0.01)
                }
                Toggle("Number Row", isOn: $numberRow)
                Toggle("Show Symbols on Keys", isOn: $showSecondarySymbols)
                Picker("Key Height", selection: $keyHeight) {
                    ForEach(KeyHeightOption.allCases) { Text($0.title).tag($0.rawValue) }
                }
                Toggle("Space Bar Trackpad", isOn: $spaceTrackpad)
                Picker("Appearance", selection: $theme) {
                    ForEach(ThemeOption.allCases) { Text($0.title).tag($0.rawValue) }
                }
            } header: {
                Text("Layout")
            } footer: {
                Text("Split works in portrait and landscape. Automatic splits along the crease on iPhone Duo's inner display when it's held wide, and on other devices when the keyboard is at least 600 pt wide. You can also switch Split, Left, Right and Full from the toolbar (⋯) above the keys.")
            }

            Section {
                LabeledContent("Enable Dictation", value: "System only")
            } header: {
                Text("Dictation")
            } footer: {
                Text("iOS does not let third-party keyboards use the microphone. For dictation, switch to the Apple keyboard with the globe key and tap the microphone.")
            }

            Section {
                Toggle("Predictive Text", isOn: $predictiveText)
                Toggle("Show Predictions Inline", isOn: $showPredictionsInline)
                Toggle("Check Spelling and Grammar", isOn: $checkSpellingGrammar)
                Toggle("Slide to Type", isOn: $slideToType)
                Toggle("Delete Slide-to-Type by Word", isOn: $deleteSlideToTypeByWord)
            } header: {
                Text("English · Español · Français · Deutsch")
            } footer: {
                Text("With Show Predictions Inline on, the top completion is highlighted and Tab accepts it. iOS does not let third-party keyboards draw grey text inside the app's text field.")
            }

            Section {
                Toggle("Emoji Suggestions", isOn: $emojiSuggestions)
                Toggle("GIFs", isOn: $gifsEnabled)
                if gifsEnabled {
                    Picker("GIF Provider", selection: $gifProvider) {
                        ForEach(GIFProvider.allCases) { Text($0.title).tag($0.rawValue) }
                    }
                    SecureField("API key", text: $gifAPIKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
            } header: {
                Text("Emoji & GIFs")
            } footer: {
                Text("GIFs need Allow Full Access and a free API key from Tenor (developers.google.com/tenor) or GIPHY (developers.giphy.com). Tapping a GIF copies it; then paste it into your message. Genmoji and Stickers are Apple-only features and not available to third-party keyboards.")
            }

            Section("About") {
                LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")
                Text("Word frequencies come from the wordfreq project by Robyn Speer (data licensed CC BY-SA 4.0). Spelling uses Apple's on-device dictionaries. Nothing you type leaves your device; only GIF searches go to the GIF provider you choose.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Duo Keyboard")
        .onAppear {
            oneHanded = KeyboardSettings.shared.oneHanded
            splitMode = KeyboardSettings.shared.splitMode
            languageCount = KeyboardSettings.shared.enabledLanguages.count
            laptopMode = KeyboardSettings.shared.bool(.laptopMode)
            profile = DeviceProfile.current(for: UIScreen.main)
        }
    }
}

struct SetupCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Set up Duo Keyboard", systemImage: "keyboard").font(.headline)
            Text("1. Open Settings → General → Keyboard → Keyboards → Add New Keyboard… → Duo Keyboard.")
            Text("2. Tap Duo Keyboard → turn on Allow Full Access. It's needed for settings sync, GIFs, haptics, sound and the clipboard.")
            Text("3. In any text field, hold 🌐 and pick Duo Keyboard.")
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            }
            .buttonStyle(.borderedProminent)
        }
        .font(.subheadline)
        .padding(.vertical, 4)
    }
}

struct PlaygroundView: View {
    @State private var text = ""
    var body: some View {
        VStack(alignment: .leading) {
            Text("Switch to Duo Keyboard with 🌐, then type, swipe, split, or try emoji and GIFs.")
                .font(.footnote).foregroundStyle(.secondary)
            TextEditor(text: $text)
                .padding(8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))
        }
        .padding()
        .navigationTitle("Try It")
    }
}

struct LanguagesView: View {
    @State private var enabled: [KeyboardLanguage] = KeyboardSettings.shared.enabledLanguages

    var body: some View {
        List {
            Section {
                ForEach(enabled) { lang in
                    VStack(alignment: .leading) {
                        Text(lang.displayName)
                        Text(lang.layoutName).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .onMove { from, to in enabled.move(fromOffsets: from, toOffset: to); save() }
                .onDelete { idx in
                    guard enabled.count - idx.count >= 1 else { return }
                    enabled.remove(atOffsets: idx); save()
                }
            } header: {
                Text("Enabled")
            } footer: {
                Text("Tap the language key (EN) on the keyboard to cycle; hold it to pick. The space bar shows the active language.")
            }
            let available = KeyboardLanguage.allCases.filter { !enabled.contains($0) }
            if !available.isEmpty {
                Section("Add Language") {
                    ForEach(available) { lang in
                        Button { enabled.append(lang); save() } label: {
                            Label(lang.displayName + " — " + lang.layoutName, systemImage: "plus.circle.fill")
                        }
                    }
                }
            }
        }
        .toolbar { EditButton() }
        .navigationTitle("Keyboards")
    }

    private func save() { KeyboardSettings.shared.enabledLanguages = enabled }
}

struct Replacement: Identifiable, Hashable {
    var shortcut: String
    var phrase: String
    var id: String { shortcut }
}

struct TextReplacementView: View {
    @State private var items: [Replacement] = []
    @State private var adding = false
    @State private var newPhrase = ""
    @State private var newShortcut = ""

    var body: some View {
        List {
            Section {
                ForEach(items) { item in
                    VStack(alignment: .leading) {
                        Text(item.phrase)
                        Text(item.shortcut).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .onDelete { idx in
                    items.remove(atOffsets: idx)
                    save()
                }
            } footer: {
                Text("Type the shortcut and press space to expand it. Your iOS Text Replacements (Settings → General → Keyboard → Text Replacement) are also used automatically.")
            }
        }
        .navigationTitle("Text Replacement")
        .toolbar {
            Button { adding = true } label: { Image(systemName: "plus") }
        }
        .sheet(isPresented: $adding) {
            NavigationStack {
                Form {
                    TextField("Phrase", text: $newPhrase)
                    TextField("Shortcut", text: $newShortcut)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                .navigationTitle("New Replacement")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { adding = false } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            let key = newShortcut.trimmingCharacters(in: .whitespaces).lowercased()
                            guard !key.isEmpty, !newPhrase.isEmpty else { return }
                            items.removeAll { $0.shortcut == key }
                            items.append(Replacement(shortcut: key, phrase: newPhrase))
                            save()
                            newPhrase = ""; newShortcut = ""; adding = false
                        }
                    }
                }
            }
            .presentationDetents([.medium])
        }
        .onAppear(perform: load)
    }

    private func load() {
        items = KeyboardSettings.shared.textReplacements
            .map { Replacement(shortcut: $0.key, phrase: $0.value) }
            .sorted { $0.shortcut < $1.shortcut }
    }

    private func save() {
        KeyboardSettings.shared.textReplacements = Dictionary(items.map { ($0.shortcut, $0.phrase) }, uniquingKeysWith: { $1 })
    }
}
