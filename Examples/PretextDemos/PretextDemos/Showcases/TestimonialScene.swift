import SwiftUI
import UIKit
import CoreText
import CoreGraphics
import PretextKit

struct TestimonialScene: View {
    @State private var currentIndex: Int = 0

    private static let testimonials: [(quote: String, author: String)] = [
        ("\u{201C}As someone who struggles with chronic illness and very complex medical issues, Sollis has been a lifesaver.\u{201D}",
         "Kelsey, Sollis Member"),
        ("\u{201C}The team went above and beyond \u{2014} they coordinated with three specialists in a single afternoon and had results the same day.\u{201D}",
         "David, Sollis Member"),
        ("\u{201C}I never thought healthcare could feel this seamless. From booking to follow-up, everything just works.\u{201D}",
         "Amara, Sollis Member"),
        ("\u{201C}\u{C11C}\u{C6B8}\u{C5D0}\u{C11C} \u{AC11}\u{C790}\u{AE30} \u{C544}\u{D30C}\u{C744} \u{B54C}, \u{C804}\u{D654} \u{D55C} \u{D1B5}\u{C73C}\u{B85C} \u{BAA8}\u{B4E0} \u{AC8C} \u{D574}\u{ACBD}\u{B410}\u{C5B4}\u{C694}. \u{C815}\u{B9D0} \u{AC10}\u{C0AC}\u{D569}\u{B2C8}\u{B2E4}.\u{201D}",
         "Jiyeon, Sollis Member"),
        ("\u{201C}Having 24/7 access to a physician who actually knows my history changed everything for my family.\u{201D}",
         "Rachel, Sollis Member"),
    ]

    var body: some View {
        let item = Self.testimonials[currentIndex]

        ScrollView {
            VStack(spacing: isPad ? 24 : 16) {
                Text("Adaptive Testimonial Sizing")
                    .font(.system(size: isPad ? 20 : 15, weight: .bold, design: .serif))
                    .padding(.top, 12)

                HStack(alignment: .top, spacing: isPad ? 20 : 10) {
                    // Fixed size (naive)
                    TestimonialCard(
                        label: "FIXED SIZE (NAIVE)",
                        labelColor: .secondary,
                        quote: item.quote,
                        author: item.author,
                        usePretextSizing: false
                    )

                    // PretextKit optimised
                    TestimonialCard(
                        label: "PRETEXTKIT-OPTIMISED",
                        labelColor: .secondary,
                        quote: item.quote,
                        author: item.author,
                        usePretextSizing: true
                    )
                }
                .padding(.horizontal, isPad ? 20 : 8)

                // Dots
                HStack(spacing: 6) {
                    ForEach(0..<Self.testimonials.count, id: \.self) { i in
                        Circle()
                            .fill(i == currentIndex ? Color.primary : Color.gray.opacity(0.35))
                            .frame(width: 8, height: 8)
                    }
                }

                // Prev / Next
                HStack(spacing: 16) {
                    Button { if currentIndex > 0 { currentIndex -= 1 } } label: {
                        Image(systemName: "chevron.left")
                            .font(.title3.bold())
                            .foregroundStyle(currentIndex > 0 ? .primary : .quaternary)
                    }
                    .disabled(currentIndex == 0)

                    Button { if currentIndex < Self.testimonials.count - 1 { currentIndex += 1 } } label: {
                        Image(systemName: "chevron.right")
                            .font(.title3.bold())
                            .foregroundStyle(currentIndex < Self.testimonials.count - 1 ? .primary : .quaternary)
                    }
                    .disabled(currentIndex == Self.testimonials.count - 1)
                }

                // Info line
                TestimonialInfoLine(quote: item.quote, author: item.author)
                    .padding(.horizontal, isPad ? 24 : 12)
                    .padding(.bottom, 16)
            }
        }
        .background(Color(UIColor(red: 0.92, green: 0.90, blue: 0.87, alpha: 1)))
    }
}

// MARK: - Card

private struct TestimonialCard: View {
    let label: String
    let labelColor: Color
    let quote: String
    let author: String
    let usePretextSizing: Bool

    private let quoteFont = CTFontCreateWithName("Georgia-Bold" as CFString, isPad ? 28 : 18, nil)
    private let authorFont = CTFontCreateWithName("Georgia" as CFString, isPad ? 15 : 12, nil)
    private let lineHeight: CGFloat = isPad ? 38 : 24

    var body: some View {
        let optimalHeight = computeOptimalHeight()
        let fixedHeight: CGFloat = isPad ? 420 : 280

        VStack(alignment: .leading, spacing: 0) {
            Text(label)
                .font(.system(size: isPad ? 11 : 9, weight: .semibold, design: .monospaced))
                .foregroundStyle(labelColor)
                .tracking(1)
                .padding(.bottom, 6)

            ZStack(alignment: .topTrailing) {
                VStack(alignment: .leading) {
                    Text(quote)
                        .font(Font(quoteFont))
                        .lineSpacing(isPad ? 6 : 3)
                        .foregroundStyle(Color(UIColor(red: 0.15, green: 0.13, blue: 0.11, alpha: 1)))

                    Spacer()

                    Text(author)
                        .font(Font(authorFont))
                        .foregroundStyle(.secondary)
                }
                .padding(isPad ? 28 : 16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: usePretextSizing ? optimalHeight : fixedHeight)
                .background(Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: isPad ? 16 : 12))

                if usePretextSizing {
                    Text("\(Int(optimalHeight))px")
                        .font(.system(size: isPad ? 11 : 9, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color(.systemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .shadow(radius: 2)
                        .offset(x: 4, y: -10)
                }
            }
        }
    }

    private func computeOptimalHeight() -> CGFloat {
        let fontDesc = FontDescriptor(quoteFont)
        let cardPadding: CGFloat = isPad ? 56 : 32
        let authorHeight: CGFloat = isPad ? 60 : 44
        let estimatedWidth: CGFloat = (UIScreen.main.bounds.width / 2) - (isPad ? 60 : 24) - cardPadding

        let prepared = PretextKit.prepare(quote, font: fontDesc)
        let result = PretextKit.layout(prepared, maxWidth: estimatedWidth, lineHeight: lineHeight)
        return result.height + cardPadding + authorHeight
    }
}

// MARK: - Info line

private struct TestimonialInfoLine: View {
    let quote: String
    let author: String

    private let quoteFont = CTFontCreateWithName("Georgia-Bold" as CFString, isPad ? 28 : 18, nil)
    private let lineHeight: CGFloat = isPad ? 38 : 24

    var body: some View {
        let fontDesc = FontDescriptor(quoteFont)
        let estimatedWidth: CGFloat = (UIScreen.main.bounds.width / 2) - (isPad ? 60 : 24) - (isPad ? 56 : 32)

        let prepared = PretextKit.prepare(quote, font: fontDesc)
        let result = PretextKit.layout(prepared, maxWidth: estimatedWidth, lineHeight: lineHeight)
        let optimalH = Int(result.height + (isPad ? 116 : 76))
        let fixedH = isPad ? 420 : 280

        Text("\"\(author)\" — PretextKit computed optimal size: \(optimalH)px (fixed would be \(fixedH)px). Layout calculation is pure arithmetic — no CoreText reflows needed.")
            .font(.system(size: isPad ? 12 : 10))
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
    }
}
