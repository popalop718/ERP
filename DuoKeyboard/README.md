# Duo Keyboard

A full desktop-style custom keyboard designed for **iPhone Duo**, Apple's first foldable
iPhone. It's an iOS app plus a keyboard extension, written in Swift (UIKit keyboard,
SwiftUI settings app). It also works on any other iPhone or iPad running iOS 16 or later.

## Designed for iPhone Duo

Dimensions come from [apple.com/iphone-duo/specs](https://www.apple.com/iphone-duo/specs/).
The keyboard reads the screen's native resolution to tell which display it is on.

| Display | Specs | What the keyboard does |
|---|---|---|
| **Inner, held wide** (book pose) | 7.6", 1878 × 2670 px, 430 ppi; unfolded 164.6 × 117.8 mm. The fold runs top to bottom through the middle. | Splits by default (Split Keyboard: *Automatic*) into **two equal halves**, one per thumb. The gap is centred **on the crease**, at least 4 mm clear on each side, so no key sits on the fold. One-handed mode uses one panel of the fold. |
| **Inner, held upright** (tabletop pose) | The fold runs across the middle of the screen. | Keys always stay **below the fold**. **Laptop Mode** (on by default, toggle in the app or the ⋯ toolbar) fills the whole lower half with large keys, so a half-open Duo on a table types like a mini laptop. |
| **Outer** | 5.4", 1398 × 2034 px, 460 ppi; folded 84.1 × 117.8 mm. | Full unsplit keyboard, like a regular iPhone. |

Key sizes are set in **millimetres**, not points: one point is physically larger on
the 430 ppi inner display than on the 460 ppi outer one, so the keyboard uses about 7%
fewer points there, and keys come out the same size on both displays. Switching
displays or rotating relays the keyboard out immediately.

> The hinge angle isn't exposed to keyboards, so Laptop Mode is chosen by orientation
> (inner display upright) plus your toggle, not by detecting the fold angle. The code
> assumes the specs above; check it on a real device, since I couldn't test on one.

## Features

| Area | What you get |
|---|---|
| **Layout** | Number row on top; Tab, Caps Lock, both Shifts, Return, ←/→ arrow keys; punctuation keys with a shifted symbol on each (flick down or long-press to type it). |
| **Split** | Split keyboard in **any orientation**: *Always*, *Off*, or *Automatic* (splits when the keyboard is ≥ 600 pt wide). Adjustable gap. Toggle from the ⋯ toolbar. |
| **One-handed** | Left/right docked compact keyboard; tap the chevron to flip sides. |
| **Languages** | English (QWERTY), Español (QWERTY + ñ, ¡¿), Français (AZERTY), Deutsch (QWERTZ + äöüß). Tap **EN** to cycle; hold to pick. Each language has its own dictionary, accents (long-press), quotes, and grammar rules. |
| **Slide to Type** | Gesture typing with a visible trail. The decoder matches the swipe's shape against 30k words per language, weighted by frequency and the previous word. Alternatives appear in the bar. |
| **Delete Slide-to-Type by Word** | Delete removes the whole swiped word. |
| **Auto-Correction** | Uses Apple's on-device spell checker plus keyboard-aware edit distance. Delete right after a correction undoes it, and the keyboard stops correcting that word. |
| **Predictive Text** | Word completions and next-word predictions that learn from your typing (stored on-device only). |
| **Show Predictions Inline** | The top completion is highlighted, and **Tab** accepts it. |
| **Check Spelling and Grammar** | Spelling fixes, plus offline grammar rules: *a/an*, *could of*, *their is*, *its a*; Spanish ¿¡, *a el → al*; French elision, *si il → s'il*, *de le → du*, spacing before ;:!?; German comma before *dass/weil/…*, *das → dass*, noun capitalisation. Tap the orange ✎ chip to apply a fix. |
| **Auto-Capitalization / Enable Caps Lock** | Capitalises sentence starts and respects the text field's settings; double-tap Shift (or the Caps key) to lock caps. |
| **Smart Punctuation** | “Curly” quotes per language (“ ” / „ “ / « »), ’ apostrophes, `--` → —, French narrow no-break spaces. |
| **“.” Shortcut** | Double-tap Space for a period and a space. |
| **Show Math Results** | Type `12*(3+4)=` and the bar offers `84`. Supports + − × ÷ ^ % and parentheses. |
| **Text Replacement** | Uses your iOS Text Replacements automatically, plus shortcuts you add in the app. |
| **Character Preview, Haptic Feedback, Sound** | Same toggles as iOS. Haptics and sound need Full Access. |
| **Emoji** | Full picker with Frequently Used, 8 categories, flags, and skin tones (long-press). Emoji suggestions while typing, e.g. *pizza → 🍕*, in all four languages. |
| **GIFs** | Tenor or GIPHY search with trending, category chips, and a search box you type into with the keyboard. Tap a GIF to copy it, then paste. |
| **Editing toolbar (⋯)** | Cut, Copy, Paste, word ←/→, Home/End, Split, Left, Right, Full, Hide. |
| **Space-bar trackpad** | Drag along the space bar to move the cursor. |

## Build & install (needs a Mac with Xcode 15+)

1. `brew install xcodegen`
2. `cd DuoKeyboard && xcodegen generate`, then open `DuoKeyboard.xcodeproj`.
3. In `project.yml` (or in Build Settings), set `BUNDLE_PREFIX` to your own reverse-DNS
   prefix (e.g. `com.yourname`), and choose your Team under *Signing & Capabilities* for
   **both** targets. Make sure the App Group `group.<prefix>.duokeyboard` is ticked on both.
4. Connect your iPhone, select the **DuoKeyboard** scheme, and press Run.
5. On the iPhone: **Settings → General → Keyboard → Keyboards → Add New Keyboard… →
   Duo Keyboard**. Then tap it and turn on **Allow Full Access**.
6. In any text field, hold 🌐 and pick **Duo Keyboard**. Open the Duo Keyboard app to change
   settings, add languages, add text replacements, and paste in a GIF API key.

> A free Apple ID can sideload the app, but free provisioning may not support App Groups.
> Without App Groups the keyboard still works with its default settings, but changes made
> in the app won't reach the keyboard.

## What iOS does not allow third-party keyboards to do

These items from the iOS keyboard settings can't be reproduced exactly. The keyboard
does the closest thing that's allowed:

- **Dictation**: keyboard extensions can't use the microphone. Use 🌐 to switch to the
  Apple keyboard and dictate there.
- **Genmoji and Stickers**: Apple-only features with no public API for keyboards.
- **Inline (grey) predictions inside the text field**: keyboards can't draw in the host
  app. The top completion is highlighted in the bar instead, and Tab accepts it.
- **Inserting GIFs directly**: keyboards can only insert text, so GIFs are copied for you
  to paste (the same approach Gboard uses).
- **Secure fields** (passwords) and phone-number pads always use the system keyboard.
- Haptics, sound, the clipboard, GIFs, and syncing settings from the app all need
  **Allow Full Access**.

## Project layout

```
project.yml                 XcodeGen spec (app + keyboard extension, App Group)
App/                        SwiftUI container app: settings mirroring iOS, languages,
                            text replacement, try-it playground
Shared/                     Settings store (App Group) and language definitions
Keyboard/
  KeyboardViewController    Typing logic: autocorrect, swipe, suggestions, panels
  Layout/                   Key model and per-language desktop layouts, split geometry
  Views/                    Key grid and touch handling, suggestion bar, emoji and GIF panels
  Engine/                   Dictionary, swipe decoder, autocorrect/prediction, grammar,
                            math, smart punctuation, emoji data, GIF service
  Resources/words_*.txt     30,000 most frequent words per language
```

## Credits

Word frequency lists come from [wordfreq](https://github.com/rspeer/wordfreq) by Robyn
Speer. The code is Apache-2.0 and the data is CC BY-SA 4.0. Spelling uses Apple's
on-device dictionaries via `UITextChecker`. Everything you type stays on the device;
only GIF searches go to the provider you choose.
