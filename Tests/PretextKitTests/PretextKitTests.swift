import Testing
import CoreText
@testable import PretextKit

@Suite("PretextKit Core")
struct PretextKitTests {

    // MARK: - Helpers

    private func makeFont(size: CGFloat = 16) -> FontDescriptor {
        let font = CTFontCreateWithName("Helvetica" as CFString, size, nil)
        return FontDescriptor(font)
    }

    // MARK: - Prepare + Layout

    @Test("prepare and layout returns valid result")
    func prepareAndLayout() {
        let font = makeFont()
        let prepared = prepare("Hello, world!", font: font)
        let result = layout(prepared, maxWidth: 200, lineHeight: 20)

        #expect(result.lineCount >= 1)
        #expect(result.height == CGFloat(result.lineCount) * 20)
    }

    @Test("empty text returns zero lines")
    func emptyText() {
        let font = makeFont()
        let prepared = prepare("", font: font)
        let result = layout(prepared, maxWidth: 200, lineHeight: 20)

        #expect(result.lineCount == 0)
        #expect(result.height == 0)
    }

    @Test("whitespace-only text normalizes to empty")
    func whitespaceOnly() {
        let font = makeFont()
        let prepared = prepare("   \t\n  ", font: font)
        let result = layout(prepared, maxWidth: 200, lineHeight: 20)

        #expect(result.lineCount == 0)
        #expect(result.height == 0)
    }

    @Test("narrower width produces more lines")
    func narrowerWidthMoreLines() {
        let font = makeFont()
        let text = "The quick brown fox jumps over the lazy dog"
        let prepared = prepare(text, font: font)

        let wide = layout(prepared, maxWidth: 500, lineHeight: 20)
        let narrow = layout(prepared, maxWidth: 100, lineHeight: 20)

        #expect(narrow.lineCount >= wide.lineCount)
    }

    @Test("layout is deterministic across calls")
    func layoutDeterministic() {
        let font = makeFont()
        let prepared = prepare("Hello, world! This is a test.", font: font)

        let r1 = layout(prepared, maxWidth: 150, lineHeight: 20)
        let r2 = layout(prepared, maxWidth: 150, lineHeight: 20)

        #expect(r1.lineCount == r2.lineCount)
        #expect(r1.height == r2.height)
    }

    // MARK: - Rich APIs

    @Test("layoutWithLines returns correct line count")
    func layoutWithLinesBasic() {
        let font = makeFont()
        let prepared = prepareWithSegments("Hello world", font: font)
        let result = layoutWithLines(prepared, maxWidth: 200, lineHeight: 20)

        #expect(result.lines.count == result.lineCount)
        #expect(result.height == CGFloat(result.lineCount) * 20)
    }

    @Test("walkLineRanges matches layout line count")
    func walkLineRangesMatchesLayout() {
        let font = makeFont()
        let text = "The quick brown fox jumps over the lazy dog near the river bank"
        let prepared = prepareWithSegments(text, font: font)
        let maxWidth: CGFloat = 120

        let layoutResult = layout(prepared, maxWidth: maxWidth, lineHeight: 20)
        let walkCount = walkLineRanges(prepared, maxWidth: maxWidth) { _ in }

        #expect(walkCount == layoutResult.lineCount)
    }

    @Test("layoutNextLine iterates all lines")
    func layoutNextLineIteration() {
        let font = makeFont()
        let prepared = prepareWithSegments("Hello world, this is a longer text for testing.", font: font)
        let maxWidth: CGFloat = 100

        var cursor = LayoutCursor.start
        var lineCount = 0

        while let line = layoutNextLine(prepared, start: cursor, maxWidth: maxWidth) {
            lineCount += 1
            cursor = line.end
            #expect(!line.text.isEmpty || lineCount == 1) // At least first line can have content
            if lineCount > 100 { break } // Safety
        }

        let expected = layout(prepared, maxWidth: maxWidth, lineHeight: 20).lineCount
        #expect(lineCount == expected)
    }

    // MARK: - Multi-Script

    @Test("CJK text breaks per character")
    func cjkTextBreaking() {
        let font = makeFont()
        let text = "你好世界这是一个测试"
        let prepared = prepare(text, font: font)

        // At a very narrow width, CJK should break per character
        let result = layout(prepared, maxWidth: 20, lineHeight: 20)
        #expect(result.lineCount > 1)
    }

    @Test("mixed script text works")
    func mixedScript() {
        let font = makeFont()
        let text = "Hello 你好 مرحبا World"
        let prepared = prepare(text, font: font)
        let result = layout(prepared, maxWidth: 200, lineHeight: 20)

        #expect(result.lineCount >= 1)
    }

    // MARK: - Special Characters

    @Test("NBSP prevents wrapping")
    func nbspGlue() {
        let font = makeFont()
        // Two words joined by NBSP should not break between them
        let text = "word1\u{00A0}word2"
        let prepared = prepareWithSegments(text, font: font)

        // At a width that would normally break "word1 word2" into two lines,
        // NBSP should keep them together
        let withNbsp = layout(prepared, maxWidth: 60, lineHeight: 20)
        let withSpace = layout(
            prepare("word1 word2", font: font),
            maxWidth: 60,
            lineHeight: 20
        )

        // NBSP version should have equal or fewer lines
        #expect(withNbsp.lineCount <= withSpace.lineCount)
    }

    @Test("soft hyphen is invisible unless breaking")
    func softHyphenBehavior() {
        let font = makeFont()
        let text = "super\u{00AD}cali\u{00AD}fragil\u{00AD}istic"
        let prepared = prepareWithSegments(text, font: font)

        // Wide enough: all on one line, no visible hyphens
        let wide = layoutWithLines(prepared, maxWidth: 500, lineHeight: 20)
        #expect(wide.lineCount == 1)
        #expect(!wide.lines[0].text.contains("-"))
    }

    // MARK: - Pre-Wrap Mode

    @Test("pre-wrap preserves hard breaks")
    func preWrapHardBreaks() {
        let font = makeFont()
        let text = "line1\nline2\nline3"
        let prepared = prepare(text, font: font, options: PrepareOptions(whiteSpace: .preWrap))
        let result = layout(prepared, maxWidth: 500, lineHeight: 20)

        #expect(result.lineCount == 3)
    }

    // MARK: - Cache

    @Test("clearCache does not break subsequent calls")
    func clearCacheWorks() {
        let font = makeFont()
        let prepared = prepare("Hello, world!", font: font)
        let r1 = layout(prepared, maxWidth: 200, lineHeight: 20)

        clearCache()

        let prepared2 = prepare("Hello, world!", font: font)
        let r2 = layout(prepared2, maxWidth: 200, lineHeight: 20)

        #expect(r1.lineCount == r2.lineCount)
    }
}
