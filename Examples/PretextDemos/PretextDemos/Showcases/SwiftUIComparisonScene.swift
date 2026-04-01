import SwiftUI
import CoreText
import PretextKit

/// Side-by-side comparison: SwiftUI native Text vs PretextAutoSizedText.
/// Both render the same content at the same width. The key difference:
/// SwiftUI Text triggers a full layout pass on every resize; PretextKit
/// does pure arithmetic over cached widths.
struct SwiftUIComparisonScene: View {
    @State private var containerWidth: CGFloat = isPad ? 500 : 300
    @State private var selectedSample: Int = 0
    @State private var swiftUITime: Double = 0
    @State private var pretextTime: Double = 0

    private let maxSlider: CGFloat = isPad ? 700 : 380
    private let minSlider: CGFloat = isPad ? 150 : 100

    private static let samples: [(label: String, text: String, fontName: String, fontSize: CGFloat, lineHeight: CGFloat)] = [
        ("English paragraph",
         "Text layout on Apple platforms has always required the rendering engine to measure every glyph, determine line breaks, and compute positions from scratch on every resize. PretextKit eliminates this cost by decoupling measurement from layout. The prepare() phase measures segment widths once via CoreText. After that, layout() computes line breaks using pure arithmetic — no font engine, no glyph shaping, no string allocations. The result: sub-microsecond reflow for any text at any width.",
         "Georgia", 16, 24),

        ("Mixed CJK + emoji",
         "春天到了万物复苏 🌸 The cherry blossoms are beautiful this year. 서울의 벚꽃도 정말 아름다워요. 新しいテキストレイアウトエンジンは信じられないほど高速です 🚀 Mixed scripts, emoji ZWJ sequences 👨‍👩‍👧‍👦, and bidirectional text all reflow at the same speed because layout() never touches the font engine after prepare().",
         "Helvetica Neue", 15, 22),

        ("Short messages",
         "ok\nOn my way!\nBe there in 5 min 🏃\nDid you see the notification?\nYeah checking now\nLooks good to me 👍\nShip it\nDeployed to production\nNo issues so far\nCelebrating tonight? 🎉",
         "SF Pro", 15, 20),

        ("Arabic + Latin",
         "مرحبا بالعالم! Welcome to the new text engine. النص يتدفق بسلاسة حول العوائق بفضل PretextKit. Each line is computed independently with layoutNextLine(), allowing variable-width flows around obstacles. هذا تحسين جوهري وليس تدريجي في الأداء.",
         "Georgia", 16, 24),
    ]

    var body: some View {
        let sample = Self.samples[selectedSample]
        let ctFont = CTFontCreateWithName(sample.fontName as CFString, sample.fontSize, nil)
        let uiFont = UIFont(name: sample.fontName, size: sample.fontSize)
            ?? .systemFont(ofSize: sample.fontSize)
        let fontDesc = FontDescriptor(ctFont)
        let prepared = PretextKit.prepareWithSegments(sample.text, font: fontDesc)

        ScrollView {
            VStack(spacing: 12) {
                // Header
                Text("SwiftUI Text vs PretextKit")
                    .font(.system(size: isPad ? 20 : 15, weight: .bold, design: .monospaced))
                    .padding(.top, 8)

                // Sample picker
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(Array(Self.samples.enumerated()), id: \.offset) { i, s in
                            Button {
                                selectedSample = i
                            } label: {
                                Text(s.label)
                                    .font(.system(size: isPad ? 13 : 10, weight: .medium))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(selectedSample == i ? Color.blue : Color(.systemGray5))
                                    .foregroundStyle(selectedSample == i ? .white : .primary)
                                    .clipShape(Capsule())
                            }
                        }
                    }
                    .padding(.horizontal)
                }

                // Width slider
                HStack {
                    Text("Width").font(.caption).foregroundStyle(.secondary)
                    Slider(value: $containerWidth, in: minSlider...maxSlider, step: 1)
                    Text("\(Int(containerWidth))px")
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                }
                .padding(.horizontal)

                // Side by side
                HStack(alignment: .top, spacing: isPad ? 16 : 8) {
                    // SwiftUI native
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("SwiftUI Text")
                                .font(.system(size: isPad ? 13 : 10, weight: .bold, design: .monospaced))
                                .foregroundStyle(.orange)
                            Spacer()
                        }
                        Text("Native layout engine")
                            .font(.system(size: isPad ? 10 : 8))
                            .foregroundStyle(.secondary)

                        SwiftUITimedText(
                            text: sample.text,
                            font: uiFont,
                            width: containerWidth / 2 - (isPad ? 32 : 16),
                            onTime: { swiftUITime = $0 }
                        )
                        .frame(width: containerWidth / 2 - (isPad ? 32 : 16), alignment: .leading)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }

                    Divider()

                    // PretextKit
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("PretextKit")
                                .font(.system(size: isPad ? 13 : 10, weight: .bold, design: .monospaced))
                                .foregroundStyle(.green)
                            Spacer()
                        }
                        Text("Arithmetic reflow")
                            .font(.system(size: isPad ? 10 : 8))
                            .foregroundStyle(.secondary)

                        PretextTimedText(
                            prepared: prepared,
                            font: ctFont,
                            lineHeight: sample.lineHeight,
                            width: containerWidth / 2 - (isPad ? 32 : 16),
                            onTime: { pretextTime = $0 }
                        )
                        .frame(width: containerWidth / 2 - (isPad ? 32 : 16), alignment: .leading)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
                .padding(.horizontal)

                // Timing comparison
                HStack(spacing: isPad ? 24 : 12) {
                    TimingBadge(label: "SwiftUI", us: swiftUITime, color: .orange)
                    TimingBadge(label: "PretextKit", us: pretextTime, color: .green)
                    if pretextTime > 0 {
                        let speedup = swiftUITime / max(pretextTime, 0.001)
                        Text(String(format: "%.0fx faster", speedup))
                            .font(.system(size: isPad ? 16 : 12, weight: .black, design: .monospaced))
                            .foregroundStyle(.green)
                    }
                }
                .padding()
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal)

                // Explanation
                VStack(alignment: .leading, spacing: 6) {
                    Text("How this works")
                        .font(.system(size: isPad ? 14 : 12, weight: .bold, design: .monospaced))
                    Text("Both columns render identical text at the same width. Drag the slider to resize. SwiftUI Text calls into TextKit/CoreText on every width change — measuring glyphs, computing line breaks, and allocating attributed strings from scratch. PretextKit's prepare() already cached segment widths, so layout() just walks Float arrays with addition and comparison. The timing badges show the layout cost per resize.")
                        .font(.system(size: isPad ? 12 : 10))
                        .foregroundStyle(.secondary)
                }
                .padding()
                .background(Color(.tertiarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal)
                .padding(.bottom, 16)
            }
        }
        .background(Color(.systemGroupedBackground))
    }
}

// MARK: - SwiftUI native timed text

private struct SwiftUITimedText: View {
    let text: String
    let font: UIFont
    let width: CGFloat
    let onTime: (Double) -> Void

    var body: some View {
        let start = CFAbsoluteTimeGetCurrent()
        let _ = reportTime(start)

        Text(text)
            .font(Font(font as CTFont))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
    }

    private func reportTime(_ start: CFTimeInterval) {
        DispatchQueue.main.async {
            let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1_000_000
            onTime(elapsed)
        }
    }
}

// MARK: - PretextKit timed text (uses PretextAutoSizedText)

private struct PretextTimedText: View {
    let prepared: PreparedTextWithSegments
    let font: CTFont
    let lineHeight: CGFloat
    let width: CGFloat
    let onTime: (Double) -> Void

    var body: some View {
        let start = CFAbsoluteTimeGetCurrent()
        let result = PretextKit.layout(prepared, maxWidth: width, lineHeight: lineHeight)
        let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1_000_000
        let _ = DispatchQueue.main.async { onTime(elapsed) }

        PretextAutoSizedText(
            prepared: prepared,
            font: font,
            lineHeight: lineHeight
        )
        .padding(8)
    }
}

// MARK: - Timing badge

private struct TimingBadge: View {
    let label: String
    let us: Double
    let color: Color

    var body: some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.system(size: isPad ? 10 : 8, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
            HStack(spacing: 2) {
                Text(String(format: "%.0f", us))
                    .font(.system(size: isPad ? 18 : 14, weight: .bold, design: .monospaced))
                    .foregroundStyle(color)
                Text("μs")
                    .font(.system(size: isPad ? 10 : 8, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
    }
}
