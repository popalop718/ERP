import Foundation

enum EmojiData {
    struct Category {
        let name: String
        let symbol: String
        let emoji: [String]
    }

    private static func list(_ s: String) -> [String] { s.split(separator: " ").map(String.init) }

    static let categories: [Category] = [
        Category(name: "Smileys & People", symbol: "face.smiling", emoji: list("""
        😀 😃 😄 😁 😆 😅 🤣 😂 🙂 🙃 🫠 😉 😊 😇 🥰 😍 🤩 😘 😗 ☺️ 😚 😙 🥲 😋 😛 😜 🤪 😝 🤑 🤗 🤭 🫢 🫣 🤫 🤔 🫡 🤐 🤨 😐 😑 😶 🫥 😏 😒 🙄 😬 😮‍💨 🤥 🫨 😌 😔 😪 🤤 😴 😷 🤒 🤕 🤢 🤮 🤧 🥵 🥶 🥴 😵 😵‍💫 🤯 🤠 🥳 🥸 😎 🤓 🧐 😕 🫤 😟 🙁 ☹️ 😮 😯 😲 😳 🥺 🥹 😦 😧 😨 😰 😥 😢 😭 😱 😖 😣 😞 😓 😩 😫 🥱 😤 😡 😠 🤬 😈 👿 💀 ☠️ 💩 🤡 👹 👺 👻 👽 👾 🤖 😺 😸 😹 😻 😼 😽 🙀 😿 😾 🙈 🙉 🙊 💋 💌 💘 💝 💖 💗 💓 💞 💕 💟 ❣️ 💔 ❤️‍🔥 ❤️‍🩹 ❤️ 🩷 🧡 💛 💚 💙 🩵 💜 🤎 🖤 🩶 🤍 💯 💢 💥 💫 💦 💨 🕳️ 💬 💭 💤 👋 🤚 🖐️ ✋ 🖖 🫱 🫲 🫳 🫴 👌 🤌 🤏 ✌️ 🤞 🫰 🤟 🤘 🤙 👈 👉 👆 🖕 👇 ☝️ 🫵 👍 👎 ✊ 👊 🤛 🤜 👏 🙌 🫶 👐 🤲 🤝 🙏 ✍️ 💅 🤳 💪 🦾 🦵 🦶 👂 🦻 👃 🧠 🫀 🫁 🦷 🦴 👀 👁️ 👅 👄 🫦 👶 🧒 👦 👧 🧑 👱 👨 🧔 👩 🧓 👴 👵 🙍 🙎 🙅 🙆 💁 🙋 🧏 🙇 🤦 🤷 🧑‍⚕️ 🧑‍🎓 🧑‍🏫 🧑‍⚖️ 🧑‍🌾 🧑‍🍳 🧑‍🔧 🧑‍🏭 🧑‍💼 🧑‍🔬 🧑‍💻 🧑‍🎤 🧑‍🎨 🧑‍✈️ 🧑‍🚀 🧑‍🚒 👮 🕵️ 💂 🥷 👷 🫅 🤴 👸 👳 👲 🧕 🤵 👰 🤰 🫄 🤱 👼 🎅 🤶 🦸 🦹 🧙 🧚 🧛 🧜 🧝 🧞 🧟 🧌 💆 💇 🚶 🧍 🧎 🏃 💃 🕺 🕴️ 👯 🧖 🧗 🤺 🏇 ⛷️ 🏂 🏌️ 🏄 🚣 🏊 ⛹️ 🏋️ 🚴 🚵 🤸 🤼 🤽 🤾 🤹 🧘 🛀 🛌 👭 👫 👬 💏 💑 👪 🗣️ 👤 👥 🫂 👣
        """)),
        Category(name: "Animals & Nature", symbol: "leaf", emoji: list("""
        🐵 🐒 🦍 🦧 🐶 🐕 🦮 🐕‍🦺 🐩 🐺 🦊 🦝 🐱 🐈 🐈‍⬛ 🦁 🐯 🐅 🐆 🐴 🫎 🫏 🐎 🦄 🦓 🦌 🦬 🐮 🐂 🐃 🐄 🐷 🐖 🐗 🐽 🐏 🐑 🐐 🐪 🐫 🦙 🦒 🐘 🦣 🦏 🦛 🐭 🐁 🐀 🐹 🐰 🐇 🐿️ 🦫 🦔 🦇 🐻 🐻‍❄️ 🐨 🐼 🦥 🦦 🦨 🦘 🦡 🐾 🦃 🐔 🐓 🐣 🐤 🐥 🐦 🐧 🕊️ 🦅 🦆 🦢 🦉 🦤 🪶 🦩 🦚 🦜 🪽 🐦‍⬛ 🪿 🐸 🐊 🐢 🦎 🐍 🐲 🐉 🦕 🦖 🐳 🐋 🐬 🦭 🐟 🐠 🐡 🦈 🐙 🐚 🪸 🪼 🐌 🦋 🐛 🐜 🐝 🪲 🐞 🦗 🪳 🕷️ 🕸️ 🦂 🦟 🪰 🪱 🦠 💐 🌸 💮 🪷 🏵️ 🌹 🥀 🌺 🌻 🌼 🌷 🪻 🌱 🪴 🌲 🌳 🌴 🌵 🌾 🌿 ☘️ 🍀 🍁 🍂 🍃 🪹 🪺 🍄 🌍 🌎 🌏 🌑 🌒 🌓 🌔 🌕 🌖 🌗 🌘 🌙 🌚 🌛 🌜 ☀️ 🌝 🌞 🪐 ⭐ 🌟 🌠 🌌 ☁️ ⛅ ⛈️ 🌤️ 🌥️ 🌦️ 🌧️ 🌨️ 🌩️ 🌪️ 🌫️ 🌬️ 🌀 🌈 🌂 ☂️ ☔ ⛱️ ⚡ ❄️ ☃️ ⛄ ☄️ 🔥 💧 🌊
        """)),
        Category(name: "Food & Drink", symbol: "fork.knife", emoji: list("""
        🍇 🍈 🍉 🍊 🍋 🍌 🍍 🥭 🍎 🍏 🍐 🍑 🍒 🍓 🫐 🥝 🍅 🫒 🥥 🥑 🍆 🥔 🥕 🌽 🌶️ 🫑 🥒 🥬 🥦 🧄 🧅 🥜 🫘 🌰 🫚 🫛 🍞 🥐 🥖 🫓 🥨 🥯 🥞 🧇 🧀 🍖 🍗 🥩 🥓 🍔 🍟 🍕 🌭 🥪 🌮 🌯 🫔 🥙 🧆 🥚 🍳 🥘 🍲 🫕 🥣 🥗 🍿 🧈 🧂 🥫 🍱 🍘 🍙 🍚 🍛 🍜 🍝 🍠 🍢 🍣 🍤 🍥 🥮 🍡 🥟 🥠 🥡 🦀 🦞 🦐 🦑 🦪 🍦 🍧 🍨 🍩 🍪 🎂 🍰 🧁 🥧 🍫 🍬 🍭 🍮 🍯 🍼 🥛 ☕ 🫖 🍵 🍶 🍾 🍷 🍸 🍹 🍺 🍻 🥂 🥃 🫗 🥤 🧋 🧃 🧉 🧊 🥢 🍽️ 🍴 🥄 🔪 🫙 🏺
        """)),
        Category(name: "Activity", symbol: "soccerball", emoji: list("""
        🎃 🎄 🎆 🎇 🧨 ✨ 🎈 🎉 🎊 🎋 🎍 🎎 🎏 🎐 🎑 🧧 🎀 🎁 🎗️ 🎟️ 🎫 🎖️ 🏆 🏅 🥇 🥈 🥉 ⚽ ⚾ 🥎 🏀 🏐 🏈 🏉 🎾 🥏 🎳 🏏 🏑 🏒 🥍 🏓 🏸 🥊 🥋 🥅 ⛳ ⛸️ 🎣 🤿 🎽 🎿 🛷 🥌 🎯 🪀 🪁 🔫 🎱 🔮 🪄 🎮 🕹️ 🎰 🎲 🧩 🧸 🪅 🪩 🪆 ♠️ ♥️ ♦️ ♣️ ♟️ 🃏 🀄 🎴 🎭 🖼️ 🎨 🧵 🪡 🧶 🪢 🎤 🎧 🎼 🎵 🎶 🎷 🪗 🎸 🎹 🎺 🎻 🪕 🥁 🪘 🪇 🪈
        """)),
        Category(name: "Travel & Places", symbol: "car", emoji: list("""
        🗺️ 🗾 🧭 🏔️ ⛰️ 🌋 🗻 🏕️ 🏖️ 🏜️ 🏝️ 🏞️ 🏟️ 🏛️ 🏗️ 🧱 🪨 🪵 🛖 🏘️ 🏚️ 🏠 🏡 🏢 🏣 🏤 🏥 🏦 🏨 🏩 🏪 🏫 🏬 🏭 🏯 🏰 💒 🗼 🗽 ⛪ 🕌 🛕 🕍 ⛩️ 🕋 ⛲ ⛺ 🌁 🌃 🏙️ 🌄 🌅 🌆 🌇 🌉 ♨️ 🎠 🛝 🎡 🎢 💈 🎪 🚂 🚃 🚄 🚅 🚆 🚇 🚈 🚉 🚊 🚝 🚞 🚋 🚌 🚍 🚎 🚐 🚑 🚒 🚓 🚔 🚕 🚖 🚗 🚘 🚙 🛻 🚚 🚛 🚜 🏎️ 🏍️ 🛵 🦽 🦼 🛺 🚲 🛴 🛹 🛼 🚏 🛣️ 🛤️ 🛢️ ⛽ 🛞 🚨 🚥 🚦 🛑 🚧 ⚓ 🛟 ⛵ 🛶 🚤 🛳️ ⛴️ 🛥️ 🚢 ✈️ 🛩️ 🛫 🛬 🪂 💺 🚁 🚟 🚠 🚡 🛰️ 🚀 🛸 🛎️ 🧳 ⌛ ⏳ ⌚ ⏰ ⏱️ ⏲️ 🕰️
        """)),
        Category(name: "Objects", symbol: "lightbulb", emoji: list("""
        👓 🕶️ 🥽 🥼 🦺 👔 👕 👖 🧣 🧤 🧥 🧦 👗 👘 🥻 🩱 🩲 🩳 👙 👚 🪭 👛 👜 👝 🛍️ 🎒 🩴 👞 👟 🥾 🥿 👠 👡 🩰 👢 🪮 👑 👒 🎩 🎓 🧢 🪖 ⛑️ 📿 💄 💍 💎 🔇 🔈 🔉 🔊 📢 📣 📯 🔔 🔕 📻 📱 📲 ☎️ 📞 📟 📠 🔋 🪫 🔌 💻 🖥️ 🖨️ ⌨️ 🖱️ 🖲️ 💽 💾 💿 📀 🧮 🎥 🎞️ 📽️ 🎬 📺 📷 📸 📹 📼 🔍 🔎 🕯️ 💡 🔦 🏮 🪔 📔 📕 📖 📗 📘 📙 📚 📓 📒 📃 📜 📄 📰 🗞️ 📑 🔖 🏷️ 💰 🪙 💴 💵 💶 💷 💸 💳 🧾 💹 ✉️ 📧 📨 📩 📤 📥 📦 📫 📪 📬 📭 📮 🗳️ ✏️ ✒️ 🖋️ 🖊️ 🖌️ 🖍️ 📝 💼 📁 📂 🗂️ 📅 📆 🗒️ 🗓️ 📇 📈 📉 📊 📋 📌 📍 📎 🖇️ 📏 📐 ✂️ 🗃️ 🗄️ 🗑️ 🔒 🔓 🔏 🔐 🔑 🗝️ 🔨 🪓 ⛏️ ⚒️ 🛠️ 🗡️ ⚔️ 💣 🪃 🏹 🛡️ 🪚 🔧 🪛 🔩 ⚙️ 🗜️ ⚖️ 🦯 🔗 ⛓️ 🪝 🧰 🧲 🪜 ⚗️ 🧪 🧫 🧬 🔬 🔭 📡 💉 🩸 💊 🩹 🩼 🩺 🩻 🚪 🛗 🪞 🪟 🛏️ 🛋️ 🪑 🚽 🪠 🚿 🛁 🪤 🪒 🧴 🧷 🧹 🧺 🧻 🪣 🧼 🫧 🪥 🧽 🧯 🛒 🚬 ⚰️ 🪦 ⚱️ 🧿 🪬 🗿 🪧 🪪
        """)),
        Category(name: "Symbols", symbol: "heart", emoji: list("""
        🏧 🚮 🚰 ♿ 🚹 🚺 🚻 🚼 🚾 🛂 🛃 🛄 🛅 ⚠️ 🚸 ⛔ 🚫 🚳 🚭 🚯 🚱 🚷 📵 🔞 ☢️ ☣️ ⬆️ ↗️ ➡️ ↘️ ⬇️ ↙️ ⬅️ ↖️ ↕️ ↔️ ↩️ ↪️ ⤴️ ⤵️ 🔃 🔄 🔙 🔚 🔛 🔜 🔝 🛐 ⚛️ 🕉️ ✡️ ☸️ ☯️ ✝️ ☦️ ☪️ ☮️ 🕎 🔯 🪯 ♈ ♉ ♊ ♋ ♌ ♍ ♎ ♏ ♐ ♑ ♒ ♓ ⛎ 🔀 🔁 🔂 ▶️ ⏩ ⏭️ ⏯️ ◀️ ⏪ ⏮️ 🔼 ⏫ 🔽 ⏬ ⏸️ ⏹️ ⏺️ ⏏️ 🎦 🔅 🔆 📶 🛜 📳 📴 ♀️ ♂️ ⚧️ ✖️ ➕ ➖ ➗ 🟰 ♾️ ‼️ ⁉️ ❓ ❔ ❕ ❗ 〰️ 💱 💲 ⚕️ ♻️ ⚜️ 🔱 📛 🔰 ⭕ ✅ ☑️ ✔️ ❌ ❎ ➰ ➿ 〽️ ✳️ ✴️ ❇️ ©️ ®️ ™️ #️⃣ *️⃣ 0️⃣ 1️⃣ 2️⃣ 3️⃣ 4️⃣ 5️⃣ 6️⃣ 7️⃣ 8️⃣ 9️⃣ 🔟 🔠 🔡 🔢 🔣 🔤 🅰️ 🆎 🅱️ 🆑 🆒 🆓 ℹ️ 🆔 Ⓜ️ 🆕 🆖 🅾️ 🆗 🅿️ 🆘 🆙 🆚 🈁 🔴 🟠 🟡 🟢 🔵 🟣 🟤 ⚫ ⚪ 🟥 🟧 🟨 🟩 🟦 🟪 🟫 ⬛ ⬜ ◼️ ◻️ ◾ ◽ ▪️ ▫️ 🔶 🔷 🔸 🔹 🔺 🔻 💠 🔘 🔳 🔲
        """)),
        Category(name: "Flags", symbol: "flag", emoji: list("🏁 🚩 🎌 🏴 🏳️ 🏳️‍🌈 🏳️‍⚧️ 🏴‍☠️") + flags),
    ]

    /// Country flags built from regional-indicator pairs.
    private static let flags: [String] = {
        let codes = "US GB CA AU NZ IE ES MX AR CO CL PE VE EC UY PY BO CR CU DO GT HN NI PA PR SV FR BE CH LU MC DE AT LI IT PT NL DK NO SE FI IS PL CZ SK HU RO BG GR TR UA RU HR SI RS BA ME MK AL EE LV LT BY MD GE AM AZ IL EG MA DZ TN NG GH KE ZA ET SN CI CM IN PK BD LK NP CN JP KR TW HK SG MY ID PH TH VN AE SA QA KW BH OM JO LB IR IQ BR JM HT TT"
        return codes.split(separator: " ").map { code in
            String(String.UnicodeScalarView(code.unicodeScalars.compactMap { Unicode.Scalar(127397 + $0.value) }))
        }
    }()

    /// Emoji that accept Fitzpatrick skin-tone modifiers (long-press in the panel).
    static let skinToneable: Set<String> = Set(list("""
    👋 🤚 🖐️ ✋ 🖖 🫱 🫲 🫳 🫴 👌 🤌 🤏 ✌️ 🤞 🫰 🤟 🤘 🤙 👈 👉 👆 🖕 👇 ☝️ 🫵 👍 👎 ✊ 👊 🤛 🤜 👏 🙌 🫶 👐 🤲 🙏 ✍️ 💅 🤳 💪 🦵 🦶 👂 🦻 👃 👶 🧒 👦 👧 🧑 👱 👨 🧔 👩 🧓 👴 👵 🙍 🙎 🙅 🙆 💁 🙋 🧏 🙇 🤦 🤷 👮 🕵️ 💂 🥷 👷 🫅 🤴 👸 👳 👲 🧕 🤵 👰 🤰 🫄 🤱 👼 🎅 🤶 🦸 🦹 🧙 🧚 🧛 🧜 🧝 💆 💇 🚶 🧍 🧎 🏃 💃 🕺 🧖 🧗 🏇 🏂 🏄 🚣 🏊 🚴 🚵 🤸 🤽 🤾 🤹 🧘 🛀 🛌
    """))

    static func skinTones(for emoji: String) -> [String] {
        guard skinToneable.contains(emoji) else { return [] }
        let base = emoji.replacingOccurrences(of: "\u{FE0F}", with: "")
        guard let first = base.unicodeScalars.first else { return [] }
        let rest = String(String.UnicodeScalarView(base.unicodeScalars.dropFirst()))
        return [emoji] + (0x1F3FB...0x1F3FF).compactMap { Unicode.Scalar($0) }.map { tone in
            String(String.UnicodeScalarView([first, tone])) + rest
        }
    }

    // MARK: Emoji suggestions (word → emoji)

    private static let en: [String: String] = [
        "love": "❤️", "heart": "❤️", "happy": "😊", "smile": "😊", "lol": "😂", "haha": "😂", "funny": "😂", "laugh": "😂",
        "sad": "😢", "cry": "😭", "crying": "😭", "angry": "😠", "mad": "😡", "wow": "😮", "omg": "😱", "cool": "😎",
        "kiss": "😘", "wink": "😉", "think": "🤔", "thinking": "🤔", "sleep": "😴", "tired": "😴", "sick": "🤒",
        "party": "🥳", "birthday": "🎂", "cake": "🎂", "gift": "🎁", "present": "🎁", "celebrate": "🎉", "congrats": "🎉",
        "congratulations": "🎉", "yes": "👍", "ok": "👌", "okay": "👌", "no": "👎", "thanks": "🙏", "thank": "🙏", "please": "🙏",
        "pray": "🙏", "clap": "👏", "strong": "💪", "fire": "🔥", "hot": "🔥", "lit": "🔥", "cold": "🥶", "100": "💯",
        "sun": "☀️", "sunny": "☀️", "rain": "🌧️", "snow": "❄️", "star": "⭐", "moon": "🌙", "rainbow": "🌈",
        "dog": "🐶", "cat": "🐱", "pizza": "🍕", "burger": "🍔", "coffee": "☕", "tea": "🍵", "beer": "🍺", "wine": "🍷",
        "drink": "🍹", "food": "🍽️", "taco": "🌮", "apple": "🍎", "money": "💰", "car": "🚗", "plane": "✈️", "home": "🏠",
        "house": "🏠", "work": "💼", "music": "🎵", "phone": "📱", "computer": "💻", "book": "📖", "time": "⏰",
        "soccer": "⚽", "football": "🏈", "basketball": "🏀", "game": "🎮", "flower": "🌸", "tree": "🌳", "beach": "🏖️",
        "ghost": "👻", "skull": "💀", "poop": "💩", "eyes": "👀", "hug": "🤗", "shh": "🤫", "sorry": "😔", "nervous": "😬",
        "hi": "👋", "hello": "👋", "bye": "👋", "wave": "👋", "rocket": "🚀", "idea": "💡", "check": "✅", "done": "✅",
        "christmas": "🎄", "halloween": "🎃", "baby": "👶", "rose": "🌹", "kisses": "😘", "night": "🌙", "morning": "🌅",
    ]
    private static let es: [String: String] = [
        "amor": "❤️", "corazón": "❤️", "feliz": "😊", "jaja": "😂", "jajaja": "😂", "triste": "😢", "llorar": "😭",
        "enojado": "😠", "fiesta": "🥳", "cumpleaños": "🎂", "regalo": "🎁", "felicidades": "🎉", "sí": "👍", "gracias": "🙏",
        "fuego": "🔥", "sol": "☀️", "lluvia": "🌧️", "perro": "🐶", "gato": "🐱", "café": "☕", "cerveza": "🍺", "vino": "🍷",
        "dinero": "💰", "coche": "🚗", "carro": "🚗", "casa": "🏠", "trabajo": "💼", "música": "🎵", "hola": "👋",
        "adiós": "👋", "beso": "😘", "besos": "😘", "fútbol": "⚽", "playa": "🏖️", "flor": "🌸", "noche": "🌙", "comida": "🍽️",
    ]
    private static let fr: [String: String] = [
        "amour": "❤️", "cœur": "❤️", "coeur": "❤️", "heureux": "😊", "heureuse": "😊", "mdr": "😂", "triste": "😢",
        "pleurer": "😭", "fête": "🥳", "anniversaire": "🎂", "cadeau": "🎁", "félicitations": "🎉", "oui": "👍", "merci": "🙏",
        "feu": "🔥", "soleil": "☀️", "pluie": "🌧️", "chien": "🐶", "chat": "🐱", "café": "☕", "bière": "🍺", "vin": "🍷",
        "argent": "💰", "voiture": "🚗", "maison": "🏠", "travail": "💼", "musique": "🎵", "salut": "👋", "bonjour": "👋",
        "bisous": "😘", "bisou": "😘", "foot": "⚽", "plage": "🏖️", "fleur": "🌸", "nuit": "🌙", "pizza": "🍕", "génial": "😎",
    ]
    private static let de: [String: String] = [
        "liebe": "❤️", "herz": "❤️", "glücklich": "😊", "froh": "😊", "haha": "😂", "traurig": "😢", "weinen": "😭",
        "party": "🥳", "geburtstag": "🎂", "geschenk": "🎁", "glückwunsch": "🎉", "ja": "👍", "danke": "🙏", "bitte": "🙏",
        "feuer": "🔥", "sonne": "☀️", "regen": "🌧️", "schnee": "❄️", "hund": "🐶", "katze": "🐱", "kaffee": "☕",
        "bier": "🍺", "wein": "🍷", "geld": "💰", "auto": "🚗", "haus": "🏠", "arbeit": "💼", "musik": "🎵", "hallo": "👋",
        "tschüss": "👋", "kuss": "😘", "fußball": "⚽", "strand": "🏖️", "blume": "🌸", "nacht": "🌙", "pizza": "🍕", "cool": "😎",
    ]

    static func suggestion(for word: String, language: KeyboardLanguage) -> String? {
        let w = word.lowercased()
        let table: [String: String]
        switch language {
        case .english: table = en
        case .spanish: table = es
        case .french: table = fr
        case .german: table = de
        }
        return table[w] ?? en[w]
    }
}
