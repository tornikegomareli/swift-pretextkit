#if canImport(SwiftUI)
import SwiftUI
import CoreText

/// A SwiftUI view that renders text using PretextKit's precomputed layout.
///
/// Unlike SwiftUI's `Text`, this view computes layout using pure arithmetic
/// over cached segment widths — no TextKit or CoreText calls during reflow.
///
/// ```swift
/// let prepared = prepareWithSegments("Hello, world!", font: FontDescriptor(myFont))
///
/// PretextText(prepared: prepared, font: myFont, lineHeight: 22)
///     .foregroundStyle(.primary)
/// ```
@available(iOS 16.0, macOS 13.0, *)
public struct PretextText: View {
    let prepared: PreparedTextWithSegments
    let font: CTFont
    let lineHeight: CGFloat
    var textColor: Color

    public init(
        prepared: PreparedTextWithSegments,
        font: CTFont,
        lineHeight: CGFloat,
        textColor: Color = .primary
    ) {
        self.prepared = prepared
        self.font = font
        self.lineHeight = lineHeight
        self.textColor = textColor
    }

    public var body: some View {
        Canvas { context, size in
            let linesResult = layoutWithLines(prepared, maxWidth: size.width, lineHeight: lineHeight)
            for (i, line) in linesResult.lines.enumerated() {
                let resolved = context.resolve(
                    Text(line.text)
                        .font(Font(font))
                        .foregroundColor(textColor)
                )
                let y = CGFloat(i) * lineHeight
                context.draw(resolved, at: CGPoint(x: 0, y: y), anchor: .topLeading)
            }
        }
        .frame(height: computeHeight())
    }

    private func computeHeight() -> CGFloat? {
        // We need GeometryReader for the width, but as a simple default
        // we return nil and let the parent constrain us
        nil
    }
}

/// A view modifier that sizes its content based on PretextKit layout.
///
/// ```swift
/// Color.clear
///     .pretextFrame(prepared: myPrepared, lineHeight: 22)
/// ```
@available(iOS 16.0, macOS 13.0, *)
public struct PretextFrameModifier: ViewModifier {
    let prepared: PreparedText
    let lineHeight: CGFloat

    public func body(content: Content) -> some View {
        content.background(
            GeometryReader { geometry in
                Color.clear.preference(
                    key: PretextHeightPreferenceKey.self,
                    value: PretextKit.layout(
                        prepared,
                        maxWidth: geometry.size.width,
                        lineHeight: lineHeight
                    ).height
                )
            }
        )
        .onPreferenceChange(PretextHeightPreferenceKey.self) { _ in }
    }
}

@available(iOS 16.0, macOS 13.0, *)
struct PretextHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

@available(iOS 16.0, macOS 13.0, *)
public extension View {
    /// Size this view's height based on PretextKit text layout.
    func pretextFrame(prepared: PreparedText, lineHeight: CGFloat) -> some View {
        modifier(PretextFrameModifier(prepared: prepared, lineHeight: lineHeight))
    }
}

/// A SwiftUI view that uses GeometryReader to automatically size
/// PretextText based on available width.
///
/// Measures the available width via GeometryReader, computes the exact
/// height using `layout()`, and renders lines via Canvas. The height
/// feeds back through a preference key so the view sizes itself correctly
/// without requiring an explicit frame.
@available(iOS 16.0, macOS 13.0, *)
public struct PretextAutoSizedText: View {
    let prepared: PreparedTextWithSegments
    let font: CTFont
    let lineHeight: CGFloat
    var textColor: Color

    @State private var computedHeight: CGFloat = 0

    public init(
        prepared: PreparedTextWithSegments,
        font: CTFont,
        lineHeight: CGFloat,
        textColor: Color = .primary
    ) {
        self.prepared = prepared
        self.font = font
        self.lineHeight = lineHeight
        self.textColor = textColor
    }

    public var body: some View {
        GeometryReader { geometry in
            let height = PretextKit.layout(prepared, maxWidth: geometry.size.width, lineHeight: lineHeight).height
            Canvas { context, size in
                let linesResult = layoutWithLines(prepared, maxWidth: size.width, lineHeight: lineHeight)
                for (i, line) in linesResult.lines.enumerated() {
                    let resolved = context.resolve(
                        Text(line.text)
                            .font(Font(font))
                            .foregroundColor(textColor)
                    )
                    context.draw(resolved, at: CGPoint(x: 0, y: CGFloat(i) * lineHeight), anchor: .topLeading)
                }
            }
            .frame(width: geometry.size.width, height: height)
            .onAppear { computedHeight = height }
            .onChange(of: geometry.size.width) { newWidth in
                computedHeight = PretextKit.layout(prepared, maxWidth: newWidth, lineHeight: lineHeight).height
            }
        }
        .frame(height: computedHeight > 0 ? computedHeight : nil)
    }
}
#endif
