import Testing
import CoreText
import Foundation
@testable import PretextKit

@Suite("Performance")
struct PerformanceTests {

    private let font = CTFontCreateWithName("Helvetica" as CFString, 16, nil)
    private var fontDesc: FontDescriptor { FontDescriptor(font) }

    /// Generate a batch of realistic text strings for benchmarking.
    private func generateTextBatch(count: Int = 100) -> [String] {
        let templates = [
            "The quick brown fox jumps over the lazy dog near the river bank.",
            "Pack my box with five dozen liquor jugs and send them overnight.",
            "春天到了万物复苏百花齐放鸟语花香大地回暖生机勃勃",
            "Hello 🌍 World 🚀 Testing emojis in mixed text content here.",
            "東京タワーは日本の有名な観光名所です。Tokyo Tower is 333 meters tall.",
            "A short string.",
            "The sun was shining brightly over the mountain peaks as the hikers made their way along the narrow trail that wound through the ancient forest.",
            "你好世界这是一个测试文本用来检验中文排版",
            "Mixed: Hello 你好 مرحبا สวัสดี こんにちは 안녕하세요 World",
            "https://example.com/path/to/resource?query=value&other=123 and some trailing text after the URL.",
        ]

        var texts: [String] = []
        for i in 0..<count {
            texts.append(templates[i % templates.count])
        }
        return texts
    }

    @Test("prepare() batch timing")
    func prepareBatchTiming() {
        let texts = generateTextBatch(count: 100)
        clearCache() // Cold start

        let start = CFAbsoluteTimeGetCurrent()
        for text in texts {
            _ = prepare(text, font: fontDesc)
        }
        let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000

        // Report timing
        let perText = elapsed / Double(texts.count)
        #expect(perText < 1.0, "prepare() avg \(String(format: "%.3f", perText))ms per text exceeds 1ms target")
    }

    @Test("layout() batch timing — the hot path")
    func layoutBatchTiming() {
        let texts = generateTextBatch(count: 500)
        let prepared = texts.map { prepare($0, font: fontDesc) }

        // Warm up
        for p in prepared {
            _ = layout(p, maxWidth: 320, lineHeight: 20)
        }

        let iterations = 10
        var totalMs: Double = 0

        for _ in 0..<iterations {
            let start = CFAbsoluteTimeGetCurrent()
            for p in prepared {
                _ = layout(p, maxWidth: 320, lineHeight: 20)
            }
            totalMs += (CFAbsoluteTimeGetCurrent() - start) * 1000
        }

        let avgBatchMs = totalMs / Double(iterations)
        let perTextMs = avgBatchMs / Double(prepared.count)

        // layout() should be sub-millisecond for the whole batch
        #expect(avgBatchMs < 5.0, "layout() batch avg \(String(format: "%.3f", avgBatchMs))ms exceeds 5ms target")
        #expect(perTextMs < 0.01, "layout() per-text avg \(String(format: "%.6f", perTextMs))ms exceeds 0.01ms target")
    }

    @Test("layout() at multiple widths — resize simulation")
    func layoutResizeSimulation() {
        let text = "The quick brown fox jumps over the lazy dog. Pack my box with five dozen liquor jugs."
        let prepared = prepare(text, font: fontDesc)

        let widths: [CGFloat] = Array(stride(from: 50, through: 500, by: 5))

        let start = CFAbsoluteTimeGetCurrent()
        for _ in 0..<100 { // 100 resize cycles
            for w in widths {
                _ = layout(prepared, maxWidth: w, lineHeight: 20)
            }
        }
        let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000
        let callCount = 100 * widths.count

        let perCallMs = elapsed / Double(callCount)
        #expect(perCallMs < 0.01, "layout() resize avg \(String(format: "%.6f", perCallMs))ms per call exceeds 0.01ms")
    }

    @Test("prepare() cache hit performance")
    func prepareCacheHits() {
        let texts = generateTextBatch(count: 50)

        // First pass: cold cache
        let coldStart = CFAbsoluteTimeGetCurrent()
        for text in texts {
            _ = prepare(text, font: fontDesc)
        }
        let coldMs = (CFAbsoluteTimeGetCurrent() - coldStart) * 1000

        // Second pass: warm cache (segment metrics cached)
        let warmStart = CFAbsoluteTimeGetCurrent()
        for text in texts {
            _ = prepare(text, font: fontDesc)
        }
        let warmMs = (CFAbsoluteTimeGetCurrent() - warmStart) * 1000

        // Warm should be faster (cache hits on segment measurement)
        #expect(warmMs < coldMs, "Warm cache (\(String(format: "%.2f", warmMs))ms) should be faster than cold (\(String(format: "%.2f", coldMs))ms)")
    }

    @Test("layoutWithLines() timing")
    func layoutWithLinesTiming() {
        let texts = generateTextBatch(count: 100)
        let prepared = texts.map { prepareWithSegments($0, font: fontDesc) }

        let start = CFAbsoluteTimeGetCurrent()
        for p in prepared {
            _ = layoutWithLines(p, maxWidth: 320, lineHeight: 20)
        }
        let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000
        let perText = elapsed / Double(prepared.count)

        #expect(perText < 0.5, "layoutWithLines() avg \(String(format: "%.3f", perText))ms per text exceeds 0.5ms target")
    }

    @Test("walkLineRanges() is faster than layoutWithLines()")
    func walkLineRangesVsLayoutWithLines() {
        let text = "The quick brown fox jumps over the lazy dog. Pack my box with five dozen liquor jugs. Sphinx of black quartz, judge my vow."
        let prepared = prepareWithSegments(text, font: fontDesc)

        // Time walkLineRanges
        let walkStart = CFAbsoluteTimeGetCurrent()
        for _ in 0..<1000 {
            walkLineRanges(prepared, maxWidth: 120) { _ in }
        }
        let walkMs = (CFAbsoluteTimeGetCurrent() - walkStart) * 1000

        // Time layoutWithLines
        let linesStart = CFAbsoluteTimeGetCurrent()
        for _ in 0..<1000 {
            _ = layoutWithLines(prepared, maxWidth: 120, lineHeight: 20)
        }
        let linesMs = (CFAbsoluteTimeGetCurrent() - linesStart) * 1000

        // walkLineRanges should be faster (no text materialization)
        #expect(walkMs <= linesMs, "walkLineRanges (\(String(format: "%.2f", walkMs))ms) should be <= layoutWithLines (\(String(format: "%.2f", linesMs))ms)")
    }
}

@Suite("Thread Safety")
struct ThreadSafetyTests {

    private let font = CTFontCreateWithName("Helvetica" as CFString, 16, nil)
    private var fontDesc: FontDescriptor { FontDescriptor(font) }

    @Test("Concurrent prepare() does not crash")
    func concurrentPrepare() async {
        let texts = [
            "Hello, world!",
            "The quick brown fox jumps over the lazy dog.",
            "春天到了万物复苏百花齐放",
            "Hello 🌍 World 🚀",
            "Mixed: Hello 你好 مرحبا World",
        ]

        await withTaskGroup(of: PreparedText.self) { group in
            for _ in 0..<50 {
                for text in texts {
                    group.addTask {
                        prepare(text, font: self.fontDesc)
                    }
                }
            }
            for await _ in group { }
        }
        // If we get here without crashing, the test passes
    }

    @Test("Concurrent layout() does not crash")
    func concurrentLayout() async {
        let texts = [
            "Hello, world!",
            "The quick brown fox jumps over the lazy dog.",
            "春天到了万物复苏百花齐放",
        ]
        let prepared = texts.map { prepare($0, font: fontDesc) }

        await withTaskGroup(of: LayoutResult.self) { group in
            for _ in 0..<100 {
                for p in prepared {
                    group.addTask {
                        layout(p, maxWidth: CGFloat.random(in: 50...500), lineHeight: 20)
                    }
                }
            }
            for await _ in group { }
        }
    }

    @Test("PretextSizingCache concurrent access")
    func sizingCacheConcurrency() async {
        let cache = PretextSizingCache()
        let texts = (0..<20).map { "Text item \($0) with some content for testing" }

        // Concurrent prepare
        await withTaskGroup(of: Void.self) { group in
            for (i, text) in texts.enumerated() {
                group.addTask {
                    cache.prepareSync(text, font: self.fontDesc, identifier: i)
                }
            }
            for await _ in group { }
        }

        // Concurrent height queries
        await withTaskGroup(of: CGFloat?.self) { group in
            for _ in 0..<100 {
                for i in 0..<texts.count {
                    group.addTask {
                        cache.height(for: i, width: 200, lineHeight: 20)
                    }
                }
            }
            for await _ in group { }
        }

        #expect(cache.count == texts.count)
    }
}
