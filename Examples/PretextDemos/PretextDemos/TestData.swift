import Foundation

/// Shared test corpus covering diverse scripts, lengths, and edge cases.
enum TestData {

    // MARK: - English

    static let englishShort = [
        "Hello, world!",
        "OK",
        "The quick brown fox.",
        "A",
        "Testing 123.",
    ]

    static let englishMedium = [
        "The quick brown fox jumps over the lazy dog. Pack my box with five dozen liquor jugs.",
        "How vexingly quick daft zebras jump! Sphinx of black quartz, judge my vow.",
        "Two driven jocks help fax my big quiz. The five boxing wizards jump quickly.",
        "Jackdaws love my big sphinx of quartz. Few quips galvanized the mock jury box.",
        "The job requires extra pluck and zeal from every young wage earner.",
    ]

    static let englishLong = [
        "In the beginning, the universe was created. This has made a lot of people very angry and been widely regarded as a bad move. Many solutions were proposed for this problem, but most of these were largely concerned with the movements of small green pieces of paper, which is odd because on the whole it wasn't the small green pieces of paper that were unhappy.",
        "It is a truth universally acknowledged, that a single man in possession of a good fortune, must be in want of a wife. However little known the feelings or views of such a man may be on his first entering a neighbourhood, this truth is so well fixed in the minds of the surrounding families.",
        "Call me Ishmael. Some years ago, never mind how long precisely, having little or no money in my purse, and nothing particular to interest me on shore, I thought I would sail about a little and see the watery part of the world.",
    ]

    // MARK: - CJK

    static let chinese = [
        "春天到了万物复苏百花齐放鸟语花香大地回暖生机勃勃",
        "中华人民共和国是工人阶级领导的以工农联盟为基础的人民民主专政的社会主义国家",
        "床前明月光疑是地上霜举头望明月低头思故乡",
        "人工智能正在改变我们的生活方式和工作方式",
    ]

    static let japanese = [
        "東京タワーは日本の有名な観光名所です。Tokyo Towerは333メートルです。",
        "吾輩は猫である。名前はまだ無い。どこで生れたかとんと見当がつかぬ。",
        "桜の花が咲く季節になりました。春はとても美しい季節です。",
    ]

    static let korean = [
        "서울은 대한민국의 수도이며 가장 큰 도시입니다.",
        "한글은 세종대왕이 창제한 문자로 과학적이고 체계적입니다.",
        "인공지능 기술이 빠르게 발전하고 있습니다.",
    ]

    // MARK: - Arabic / RTL

    static let arabic = [
        "مرحبا بالعالم هذا اختبار للنص العربي",
        "الذكاء الاصطناعي يغير حياتنا بطرق لم نكن نتخيلها",
        "بسم الله الرحمن الرحيم الحمد لله رب العالمين",
    ]

    // MARK: - Thai

    static let thai = [
        "สวัสดีครับ ยินดีต้อนรับสู่ประเทศไทย",
        "ปัญญาประดิษฐ์กำลังเปลี่ยนแปลงโลกของเรา",
    ]

    // MARK: - Emoji

    static let emoji = [
        "Hello 🌍🌎🌏 World 🚀✨ Testing 👨‍👩‍👧‍👦 emojis 🎉🎊",
        "🇺🇸🇬🇧🇫🇷🇩🇪🇯🇵 Flag emojis in a row",
        "Text 😀😃😄😁😆😅🤣😂 more text 🏳️‍🌈🏴‍☠️",
        "Complex: 👩‍💻👨‍🔬👩‍🚀👨‍🍳 ZWJ sequences",
    ]

    // MARK: - Mixed Script

    static let mixed = [
        "Hello 你好 مرحبا สวัสดี こんにちは 안녕하세요 World",
        "Meeting at 3pm 下午三点 about the AI 人工智能 project",
        "Price: $29.99 / ¥3,200 / €27.50 — discounted 20% off!",
        "Visit https://example.com/path?q=hello+world&lang=en for details.",
        "Email: user@example.com | Phone: +1-555-123-4567",
    ]

    // MARK: - Special Characters

    static let specialChars = [
        "word1\u{00A0}word2\u{00A0}word3", // NBSP
        "super\u{00AD}cali\u{00AD}fragil\u{00AD}istic\u{00AD}expiali\u{00AD}docious", // Soft hyphens
        "zero\u{200B}width\u{200B}space\u{200B}break", // ZWSP
    ]

    // MARK: - Stress Cases

    static let stressCases = [
        String(repeating: "a", count: 500),
        String(repeating: "ab ", count: 200),
        String(repeating: "你", count: 200),
        String(repeating: "🚀", count: 100),
        (0..<100).map { "word\($0)" }.joined(separator: " "),
    ]

    /// Full corpus for accuracy testing.
    static let fullCorpus: [String] = {
        var all: [String] = []
        all.append(contentsOf: englishShort)
        all.append(contentsOf: englishMedium)
        all.append(contentsOf: englishLong)
        all.append(contentsOf: chinese)
        all.append(contentsOf: japanese)
        all.append(contentsOf: korean)
        all.append(contentsOf: arabic)
        all.append(contentsOf: thai)
        all.append(contentsOf: emoji)
        all.append(contentsOf: mixed)
        all.append(contentsOf: specialChars)
        return all
    }()

    /// Large dataset for scroll stress testing (2000 items).
    static let scrollStressData: [String] = {
        var items: [String] = []
        let sources = fullCorpus + stressCases
        for i in 0..<2000 {
            items.append(sources[i % sources.count])
        }
        return items
    }()
}
