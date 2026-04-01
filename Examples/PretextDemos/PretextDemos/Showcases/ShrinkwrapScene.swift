import SwiftUI
import UIKit
import CoreText
import CoreGraphics
import PretextKit

struct ShrinkwrapScene: View {
    @State private var containerWidth: CGFloat = isPad ? 500 : 320
    @State private var standardWaste: CGFloat = 0
    @State private var pretextWaste: CGFloat = 0

    private let maxSlider: CGFloat = isPad ? 700 : 400
    private let minSlider: CGFloat = isPad ? 200 : 150

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 2) {
                Text("Shrinkwrap Showdown")
                    .font(.system(size: isPad ? 20 : 15, weight: .bold, design: .monospaced))
                    .foregroundStyle(.primary)
                Text("UILabel sizing vs PretextKit exact minimum width")
                    .font(.system(size: isPad ? 12 : 10, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 8).padding(.bottom, 4)

            // Width slider
            HStack {
                Text("Container width")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(containerWidth))px")
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
            }
            .padding(.horizontal)
            Slider(value: $containerWidth, in: minSlider...maxSlider, step: 1)
                .padding(.horizontal).padding(.bottom, 8)

            Divider()

            ScrollView {
                VStack(spacing: 12) {
                    HStack(alignment: .top, spacing: 4) {
                        BubbleColumnView(
                            title: "Standard",
                            subtitle: "maxWidth constraint — dead space on short lines.",
                            titleColor: .orange,
                            containerWidth: containerWidth / 2,
                            useShrinkwrap: false,
                            wastedPixels: $standardWaste
                        )

                        Divider()

                        BubbleColumnView(
                            title: "PretextKit",
                            subtitle: "Tightest width, same line count. Zero waste.",
                            titleColor: .green,
                            containerWidth: containerWidth / 2,
                            useShrinkwrap: true,
                            wastedPixels: $pretextWaste
                        )
                    }
                    .padding(.horizontal, 4)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Why can't UILabel do this?")
                            .font(.system(size: isPad ? 16 : 13, weight: .bold, design: .monospaced))
                        Text("UILabel only knows sizeThatFits — the size needed to fit all text within a max width. If a paragraph wraps to 3 lines and the last line is short, UILabel still sizes the container to the longest line. There's no UIKit API for \"find the narrowest width that still produces exactly 3 lines.\" That requires measuring text at multiple widths and comparing line counts — exactly what PretextKit's walkLineRanges() does, without touching CoreText again. Pure arithmetic, no reflows, instant results.")
                            .font(.system(size: isPad ? 13 : 11))
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                    .background(Color(.tertiarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal)
                }
                .padding(.vertical)
            }
            .background(Color(.systemGroupedBackground))
        }
    }
}

// MARK: - Bubble Column

private struct BubbleColumnView: View {
    let title: String
    let subtitle: String
    let titleColor: Color
    let containerWidth: CGFloat
    let useShrinkwrap: Bool
    @Binding var wastedPixels: CGFloat

    private let font = CTFontCreateWithName("Helvetica Neue" as CFString, isPad ? 15 : 13, nil)
    private let lineHeight: CGFloat = isPad ? 20 : 18

    private static let messages: [(text: String, isMine: Bool)] = [
        ("Did you book the flights for Tokyo yet?", false),
        ("Yep! We land at Narita on the 14th, then Shinkansen to Kyoto the next morning 🚅", true),
        ("東京タワーの近くのホテルにしたよ。駅から歩いて5分くらい", false),
        ("Perfect. I packed way too much but whatever 🧳", true),
        ("Bring an umbrella — rainy season starts mid-June", false),
        ("Already got one. Also downloaded offline maps for the whole Kansai region just in case.", true),
        ("smart", false),
        ("The izakaya near Pontocho that Maya recommended — should we reserve? Last time it was packed by 7.", true),
        ("On it 🍶", false),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.system(size: isPad ? 14 : 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(titleColor)
                Spacer()
                Text(String(format: "%.0fpx wasted", computeTotalWaste()))
                    .font(.system(size: isPad ? 13 : 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(useShrinkwrap ? .green : .red)
            }

            Text(subtitle)
                .font(.system(size: isPad ? 11 : 9))
                .foregroundStyle(.secondary)
                .padding(.bottom, 4)

            ForEach(Array(Self.messages.enumerated()), id: \.offset) { _, msg in
                BubbleView(
                    text: msg.text,
                    isMine: msg.isMine,
                    maxBubbleWidth: containerWidth * 0.8,
                    font: font,
                    lineHeight: lineHeight,
                    useShrinkwrap: useShrinkwrap
                )
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
    }

    private func computeTotalWaste() -> CGFloat {
        let fontDesc = FontDescriptor(font)
        let maxW = containerWidth * 0.8
        var totalWaste: CGFloat = 0

        for msg in Self.messages {
            let prepared = PretextKit.prepareWithSegments(msg.text, font: fontDesc)
            let result = PretextKit.layout(prepared, maxWidth: maxW, lineHeight: lineHeight)

            if useShrinkwrap {
                // Shrinkwrap: zero waste by definition
            } else {
                // Standard: waste = (maxW - tightestWidth) * lineCount
                var maxLineW: CGFloat = 0
                PretextKit.walkLineRanges(prepared, maxWidth: maxW) { line in
                    if line.width > maxLineW { maxLineW = line.width }
                }
                totalWaste += (maxW - maxLineW) * CGFloat(result.lineCount)
            }
        }

        DispatchQueue.main.async {
            wastedPixels = totalWaste
        }
        return totalWaste
    }
}

// MARK: - Single Bubble

private struct BubbleView: View {
    let text: String
    let isMine: Bool
    let maxBubbleWidth: CGFloat
    let font: CTFont
    let lineHeight: CGFloat
    let useShrinkwrap: Bool

    var body: some View {
        let bubbleWidth = computeWidth()

        HStack {
            if isMine { Spacer() }
            Text(text)
                .font(Font(font))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .frame(width: bubbleWidth, alignment: .leading)
                .background(isMine ? Color.blue : Color(.systemGray4))
                .foregroundStyle(isMine ? .white : .primary)
                .clipShape(RoundedRectangle(cornerRadius: 16))
            if !isMine { Spacer() }
        }
    }

    private func computeWidth() -> CGFloat {
        let fontDesc = FontDescriptor(font)
        let prepared = PretextKit.prepareWithSegments(text, font: fontDesc)

        if useShrinkwrap {
            // Binary search for tightest width that keeps same line count
            let baseResult = PretextKit.layout(prepared, maxWidth: maxBubbleWidth, lineHeight: lineHeight)
            let targetLines = baseResult.lineCount

            var lo: CGFloat = 20
            var hi = maxBubbleWidth

            while hi - lo > 0.5 {
                let mid = (lo + hi) / 2
                let r = PretextKit.layout(prepared, maxWidth: mid, lineHeight: lineHeight)
                if r.lineCount <= targetLines {
                    hi = mid
                } else {
                    lo = mid
                }
            }

            // Find max line width at the tight width for pixel-perfect sizing
            var maxLineW: CGFloat = 0
            PretextKit.walkLineRanges(prepared, maxWidth: hi) { line in
                if line.width > maxLineW { maxLineW = line.width }
            }
            return min(ceil(maxLineW) + 22, maxBubbleWidth)
        } else {
            // Standard: just use maxBubbleWidth (like CSS fit-content with max-width)
            return maxBubbleWidth
        }
    }
}
