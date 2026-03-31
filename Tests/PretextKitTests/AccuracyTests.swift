import Testing
import CoreText
import CoreGraphics
@testable import PretextKit

/// Reference line count using CTFramesetter — the ground truth for iOS text layout.
private func referenceLineCount(_ text: String, font: CTFont, maxWidth: CGFloat) -> Int {
    guard !text.isEmpty else { return 0 }
    let attrs = [kCTFontAttributeName: font] as CFDictionary
    let attrStr = CFAttributedStringCreate(kCFAllocatorDefault, text as CFString, attrs)!
    let framesetter = CTFramesetterCreateWithAttributedString(attrStr)
    let path = CGPath(rect: CGRect(x: 0, y: 0, width: maxWidth, height: 100000), transform: nil)
    let frame = CTFramesetterCreateFrame(framesetter, CFRangeMake(0, 0), path, nil)
    let lines = CTFrameGetLines(frame) as? [CTLine] ?? []
    return lines.count
}

@Suite("Accuracy vs CTFramesetter")
struct AccuracyTests {

    private let font = CTFontCreateWithName("Helvetica" as CFString, 16, nil)
    private var fontDesc: FontDescriptor { FontDescriptor(font) }

    // MARK: - English

    @Test("English text matches CTFramesetter across widths")
    func englishAccuracy() {
        let text = "The quick brown fox jumps over the lazy dog. Pack my box with five dozen liquor jugs."

        for width in stride(from: 50, through: 400, by: 25) {
            let w = CGFloat(width)
            let pretextResult = layout(prepare(text, font: fontDesc), maxWidth: w, lineHeight: 20)
            let reference = referenceLineCount(text, font: font, maxWidth: w)

            #expect(
                pretextResult.lineCount == reference,
                "English mismatch at width \(width): pretext=\(pretextResult.lineCount), CTFramesetter=\(reference)"
            )
        }
    }

    // MARK: - CJK

    @Test("Chinese text matches CTFramesetter across widths")
    func chineseAccuracy() {
        let text = "春天到了万物复苏百花齐放鸟语花香"

        for width in stride(from: 20, through: 300, by: 20) {
            let w = CGFloat(width)
            let pretextResult = layout(prepare(text, font: fontDesc), maxWidth: w, lineHeight: 20)
            let reference = referenceLineCount(text, font: font, maxWidth: w)

            #expect(
                pretextResult.lineCount == reference,
                "Chinese mismatch at width \(width): pretext=\(pretextResult.lineCount), CTFramesetter=\(reference)"
            )
        }
    }

    @Test("Japanese mixed text matches CTFramesetter")
    func japaneseAccuracy() {
        let text = "東京タワーは日本の観光名所です。Tokyo Towerは333メートルです。"

        for width in stride(from: 60, through: 400, by: 30) {
            let w = CGFloat(width)
            let pretextResult = layout(prepare(text, font: fontDesc), maxWidth: w, lineHeight: 20)
            let reference = referenceLineCount(text, font: font, maxWidth: w)

            #expect(
                pretextResult.lineCount == reference,
                "Japanese mismatch at width \(width): pretext=\(pretextResult.lineCount), CTFramesetter=\(reference)"
            )
        }
    }

    // MARK: - Emoji

    @Test("Emoji text matches CTFramesetter")
    func emojiAccuracy() {
        let text = "Hello 🌍🌎🌏 World 🚀✨ Testing 👨‍👩‍👧‍👦 emojis"

        for width in stride(from: 60, through: 300, by: 30) {
            let w = CGFloat(width)
            let pretextResult = layout(prepare(text, font: fontDesc), maxWidth: w, lineHeight: 20)
            let reference = referenceLineCount(text, font: font, maxWidth: w)

            #expect(
                pretextResult.lineCount == reference,
                "Emoji mismatch at width \(width): pretext=\(pretextResult.lineCount), CTFramesetter=\(reference)"
            )
        }
    }

    // MARK: - Mixed Script

    @Test("Mixed script text handles correctly")
    func mixedScriptAccuracy() {
        let text = "Hello 你好 مرحبا สวัสดี World"

        for width in stride(from: 50, through: 300, by: 25) {
            let w = CGFloat(width)
            let pretextResult = layout(prepare(text, font: fontDesc), maxWidth: w, lineHeight: 20)
            let reference = referenceLineCount(text, font: font, maxWidth: w)

            #expect(
                pretextResult.lineCount == reference,
                "Mixed script mismatch at width \(width): pretext=\(pretextResult.lineCount), CTFramesetter=\(reference)"
            )
        }
    }

    // MARK: - Edge Cases

    @Test("Single long word overflow-wraps correctly")
    func singleLongWord() {
        let text = "Supercalifragilisticexpialidocious"
        let prepared = prepare(text, font: fontDesc)

        // Very narrow: must break within the word
        let result = layout(prepared, maxWidth: 30, lineHeight: 20)
        #expect(result.lineCount > 1)
    }

    @Test("Single character per line at minimal width")
    func minimalWidth() {
        let text = "AB"
        let prepared = prepare(text, font: fontDesc)

        // Width of 1px: each grapheme on its own line
        let result = layout(prepared, maxWidth: 1, lineHeight: 20)
        #expect(result.lineCount >= 2)
    }

    @Test("Very wide width fits on one line")
    func veryWide() {
        let text = "Short text"
        let prepared = prepare(text, font: fontDesc)
        let result = layout(prepared, maxWidth: 10000, lineHeight: 20)
        #expect(result.lineCount == 1)
    }
}

// MARK: - Width Sweep Accuracy Report

@Suite("Width Sweep Accuracy")
struct WidthSweepTests {

    private let font = CTFontCreateWithName("Helvetica" as CFString, 16, nil)
    private var fontDesc: FontDescriptor { FontDescriptor(font) }

    @Test("English corpus width sweep")
    func englishWidthSweep() {
        let texts = [
            "The quick brown fox jumps over the lazy dog.",
            "Pack my box with five dozen liquor jugs.",
            "How vexingly quick daft zebras jump!",
            "Sphinx of black quartz, judge my vow.",
            "Two driven jocks help fax my big quiz.",
        ]

        var mismatches = 0
        var total = 0

        for text in texts {
            let prepared = prepare(text, font: fontDesc)
            for width in stride(from: 30, through: 500, by: 5) {
                total += 1
                let w = CGFloat(width)
                let pretextCount = layout(prepared, maxWidth: w, lineHeight: 20).lineCount
                let refCount = referenceLineCount(text, font: font, maxWidth: w)
                if pretextCount != refCount { mismatches += 1 }
            }
        }

        let accuracy = Double(total - mismatches) / Double(total) * 100
        #expect(accuracy >= 95, "English accuracy \(accuracy)% is below 95% threshold (\(mismatches)/\(total) mismatches)")
    }

    @Test("CJK corpus width sweep")
    func cjkWidthSweep() {
        let texts = [
            "春天到了万物复苏百花齐放",
            "東京タワーは日本の観光名所",
            "서울은 대한민국의 수도입니다",
        ]

        var mismatches = 0
        var total = 0

        for text in texts {
            let prepared = prepare(text, font: fontDesc)
            for width in stride(from: 20, through: 300, by: 5) {
                total += 1
                let w = CGFloat(width)
                let pretextCount = layout(prepared, maxWidth: w, lineHeight: 20).lineCount
                let refCount = referenceLineCount(text, font: font, maxWidth: w)
                if pretextCount != refCount { mismatches += 1 }
            }
        }

        let accuracy = Double(total - mismatches) / Double(total) * 100
        #expect(accuracy >= 95, "CJK accuracy \(accuracy)% is below 95% threshold (\(mismatches)/\(total) mismatches)")
    }
}
