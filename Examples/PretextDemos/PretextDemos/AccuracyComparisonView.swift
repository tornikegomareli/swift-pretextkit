import SwiftUI
import CoreText
import PretextKit

struct AccuracyResult: Identifiable, Sendable {
    let id = UUID()
    let text: String
    let width: CGFloat
    let pretextLines: Int
    let referenceLines: Int
    let matches: Bool
}

struct AccuracyComparisonView: View {
    @State private var results: [AccuracyResult] = []
    @State private var isRunning = false
    @State private var totalTests = 0
    @State private var totalMatches = 0
    @State private var filterMismatchesOnly = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                summaryBar
                Divider()

                if isRunning {
                    ProgressView("Running accuracy sweep...")
                        .padding()
                    Spacer()
                } else if results.isEmpty {
                    ContentUnavailableView("No Results", systemImage: "checkmark.circle", description: Text("Tap Run to start the accuracy test"))
                } else {
                    List(displayResults) { result in
                        AccuracyResultRow(result: result)
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Accuracy")
            .toolbar {
                Button(isRunning ? "Running..." : "Run Test") {
                    runAccuracyTest()
                }
                .disabled(isRunning)
            }
        }
    }

    private var summaryBar: some View {
        HStack {
            if totalTests > 0 {
                let pct = Double(totalMatches) / Double(totalTests) * 100
                Text("\(totalMatches)/\(totalTests)")
                    .font(.headline)
                Text(String(format: "%.1f%%", pct))
                    .font(.headline)
                    .foregroundStyle(pct >= 99 ? .green : pct >= 95 ? .orange : .red)
            } else {
                Text("Ready")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("Mismatches", isOn: $filterMismatchesOnly)
                .fixedSize()
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private var displayResults: [AccuracyResult] {
        filterMismatchesOnly ? results.filter { !$0.matches } : results
    }

    private func runAccuracyTest() {
        isRunning = true
        results = []
        totalTests = 0
        totalMatches = 0

        let corpus = TestData.fullCorpus
        Task.detached {
            let font = CTFontCreateWithName("Helvetica" as CFString, 16, nil)
            let fontDesc = FontDescriptor(font)
            var newResults: [AccuracyResult] = []
            var matches = 0
            var total = 0

            for text in corpus {
                let prepared = PretextKit.prepare(text, font: fontDesc)
                let widths: [CGFloat] = Array(stride(from: 30, through: 400, by: 10))

                for width in widths {
                    total += 1
                    let pretextCount = PretextKit.layout(prepared, maxWidth: width, lineHeight: 20).lineCount
                    let refCount = Self.referenceLineCount(text, font: font, maxWidth: width)
                    let match = pretextCount == refCount
                    if match { matches += 1 }

                    // Keep all mismatches and first 200 matches
                    if !match || newResults.count < 200 {
                        newResults.append(AccuracyResult(
                            text: String(text.prefix(60)),
                            width: width,
                            pretextLines: pretextCount,
                            referenceLines: refCount,
                            matches: match
                        ))
                    }
                }
            }

            let finalResults = newResults
            let finalTotal = total
            let finalMatches = matches

            await MainActor.run {
                self.results = finalResults
                self.totalTests = finalTotal
                self.totalMatches = finalMatches
                self.isRunning = false
            }
        }
    }

    /// Reference line count using CTFramesetter — iOS text layout ground truth.
    nonisolated static func referenceLineCount(_ text: String, font: CTFont, maxWidth: CGFloat) -> Int {
        guard !text.isEmpty else { return 0 }
        let attrs = [kCTFontAttributeName: font] as CFDictionary
        let attrStr = CFAttributedStringCreate(kCFAllocatorDefault, text as CFString, attrs)!
        let framesetter = CTFramesetterCreateWithAttributedString(attrStr)
        let path = CGPath(rect: CGRect(x: 0, y: 0, width: maxWidth, height: 100000), transform: nil)
        let frame = CTFramesetterCreateFrame(framesetter, CFRangeMake(0, 0), path, nil)
        let lines = CTFrameGetLines(frame) as? [CTLine] ?? []
        return lines.count
    }
}

private struct AccuracyResultRow: View {
    let result: AccuracyResult

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(result.text)
                .font(.caption)
                .lineLimit(1)
                .foregroundStyle(.secondary)

            HStack {
                Text("w: \(Int(result.width))")
                    .font(.caption2)
                    .monospacedDigit()
                Spacer()
                Text("Pretext: \(result.pretextLines)")
                    .font(.caption2)
                    .foregroundStyle(result.matches ? Color.primary : Color.red)
                Text("CT: \(result.referenceLines)")
                    .font(.caption2)
                    .foregroundStyle(result.matches ? Color.primary : Color.green)

                Image(systemName: result.matches ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(result.matches ? Color.green : Color.red)
                    .font(.caption)
            }
        }
        .padding(.vertical, 2)
    }
}
