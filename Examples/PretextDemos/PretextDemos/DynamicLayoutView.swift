import SwiftUI
import UIKit
import CoreText
import CoreGraphics
import PretextKit

/// Interactive editorial layout demo — compare 5 text engines.
///
/// A draggable orb floats over the text. Text reflows around the orb in
/// real-time. Toggle between engines to compare performance:
///
/// 1. **PretextKit** — `layoutNextLine()` arithmetic reflow (zero CT calls)
/// 2. **CoreText raw** — `CTTypesetter` + `SuggestLineBreak` per line per frame
/// 3. **TextKit 1** — `NSLayoutManager` + exclusion paths
/// 4. **TextKit 2** — `NSTextLayoutManager` + exclusion zones
/// 5. **UILabel** — one UILabel with exclusion via CoreText fallback
struct DynamicLayoutView: View {
    enum LayoutMode: String, CaseIterable {
        case pretext = "PretextKit"
        case coretext = "CoreText"
        case textkit1 = "TextKit 1"
        case textkit2 = "TextKit 2"
        case uilabel = "UILabel"
    }

    @State private var orbPosition = CGPoint(x: 160, y: 400)
    @State private var orbRadius: CGFloat = 80
    @State private var preparedBody: PreparedTextWithSegments?
    @State private var mode: LayoutMode = .pretext

    // Stats
    @State private var lineCount = 0
    @State private var reflowUs: Double = 0

    static let sharedBodyText = """
    The web renders text through a pipeline that was designed thirty years ago for static documents. A browser loads a font, shapes the text into glyphs, measures their width, determines where lines break, and positions each line vertically. Every step depends on the previous one. Every step requires the rendering engine to consult its internal layout tree — a structure so expensive to maintain that browsers guard access to it behind synchronous reflow barriers that can freeze the main thread for tens of milliseconds at a time. For a paragraph in a blog post, this pipeline is invisible. The browser loads, lays out, and paints before the reader's eye has traveled from the address bar to the first word. But the web is no longer a collection of static documents. It is a platform for applications, and those applications need to know about text in ways the original pipeline never anticipated. A messaging application needs to know the exact height of every message bubble before rendering a virtualized list. A masonry layout needs the height of every card to position them without overlap. An editorial page needs text to flow around images, advertisements, and interactive elements. A responsive dashboard needs to resize and reflow text in real time as the user drags a panel divider. Every one of these operations requires text measurement. And every text measurement on the web today requires a synchronous layout reflow. The cost is devastating. Measuring the height of a single text block forces the browser to recalculate the position of every element on the page. When you measure five hundred text blocks in sequence, you trigger five hundred full layout passes. This pattern, known as layout thrashing, is the single largest performance bottleneck in modern web applications that deal with text at scale.
    """

    private let font = CTFontCreateWithName("Georgia" as CFString, 15, nil)
    private let lineHeight: CGFloat = 24
    private let padding: CGFloat = 16
    private let orbPadding: CGFloat = 14

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                statsBar
                Divider()
                modePicker
                Divider()

                GeometryReader { _ in
                    ZStack {
                        Color.black

                        // Engine-specific rendering
                        switch mode {
                        case .pretext:
                            pretextCanvas
                        case .coretext, .uilabel:
                            CoreTextLayoutView(
                                bodyText: Self.sharedBodyText,
                                font: font as UIFont,
                                lineHeight: lineHeight,
                                orbCenter: orbPosition,
                                orbRadius: orbRadius + orbPadding,
                                padding: padding,
                                onStats: { lineCount = $0; reflowUs = $1 }
                            )
                        case .textkit1:
                            TextKit1LayoutView(
                                bodyText: Self.sharedBodyText,
                                font: font as UIFont,
                                lineHeight: lineHeight,
                                orbCenter: orbPosition,
                                orbRadius: orbRadius + orbPadding,
                                padding: padding,
                                onStats: { lineCount = $0; reflowUs = $1 }
                            )
                        case .textkit2:
                            TextKit2LayoutView(
                                bodyText: Self.sharedBodyText,
                                font: font as UIFont,
                                lineHeight: lineHeight,
                                orbCenter: orbPosition,
                                orbRadius: orbRadius + orbPadding,
                                padding: padding,
                                onStats: { lineCount = $0; reflowUs = $1 }
                            )
                        }

                        OrbView(radius: orbRadius)
                            .position(orbPosition)
                            .allowsHitTesting(false)

                        Color.clear
                            .contentShape(Rectangle())
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { orbPosition = $0.location }
                            )
                    }
                }
            }
            .navigationTitle("Dynamic Layout")
            .onAppear { prepareText() }
        }
    }

    // MARK: - Mode picker (scrollable for 5 items)

    private var modePicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(LayoutMode.allCases, id: \.self) { m in
                    Button {
                        mode = m
                    } label: {
                        Text(m.rawValue)
                            .font(.caption.bold())
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(mode == m ? Color.blue : Color(.systemGray5))
                            .foregroundStyle(mode == m ? .white : .primary)
                            .clipShape(Capsule())
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 6)
        }
    }

    // MARK: - Stats bar

    private var statsBar: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(String(format: "%.0f", reflowUs))
                        .font(.system(size: 24, weight: .bold, design: .monospaced))
                        .foregroundStyle(reflowUs < 1000 ? .green : reflowUs < 5000 ? .yellow : .red)
                    Text("μs")
                        .font(.system(size: 14, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.5))
                }
                HStack(spacing: 12) {
                    Text("\(lineCount) lines")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.4))
                    if lineCount > 0 {
                        Text(String(format: "%.1f μs/line", reflowUs / Double(lineCount)))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.white.opacity(0.4))
                    }
                }
            }
            Spacer()
            Text("Drag the orb")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.25))
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.black)
    }

    // MARK: - Prepare

    private func prepareText() {
        let fontDesc = FontDescriptor(font)
        preparedBody = PretextKit.prepareWithSegments(Self.sharedBodyText, font: fontDesc)
    }

    // MARK: - PretextKit canvas

    private var pretextCanvas: some View {
        let ctFont = font
        return Canvas { context, size in
            guard let prepared = preparedBody else { return }
            let start = CFAbsoluteTimeGetCurrent()
            let lines = Self.layoutAroundOrb(
                prepared: prepared, size: size,
                orbCenter: orbPosition, orbRadius: orbRadius + orbPadding,
                padding: padding, lineHeight: lineHeight
            )
            let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1_000_000

            for line in lines {
                let resolved = context.resolve(
                    Text(line.text).font(Font(ctFont)).foregroundColor(.white.opacity(0.85))
                )
                context.draw(resolved, at: CGPoint(x: line.x, y: line.y), anchor: .topLeading)
            }
            DispatchQueue.main.async {
                self.lineCount = lines.count
                self.reflowUs = elapsed
            }
        }
    }

    // MARK: - Layout around orb (fills BOTH sides)

    nonisolated static func layoutAroundOrb(
        prepared: PreparedTextWithSegments, size: CGSize,
        orbCenter: CGPoint, orbRadius: CGFloat,
        padding: CGFloat, lineHeight: CGFloat
    ) -> [PositionedLine] {
        var cursor = LayoutCursor.start
        var y: CGFloat = padding
        var lines: [PositionedLine] = []
        let fullLeft = padding
        let fullRight = size.width - padding
        let minSlotWidth: CGFloat = 40

        while y + lineHeight <= size.height {
            let slots = carveSlots(
                fullLeft: fullLeft, fullRight: fullRight,
                orbCenter: orbCenter, orbRadius: orbRadius,
                bandTop: y, bandBottom: y + lineHeight, minWidth: minSlotWidth
            )
            if slots.isEmpty { y += lineHeight; continue }

            for slot in slots {
                guard slot.right - slot.left >= minSlotWidth else { continue }
                guard let line = PretextKit.layoutNextLine(prepared, start: cursor, maxWidth: slot.right - slot.left) else { return lines }
                lines.append(PositionedLine(text: line.text, x: slot.left, y: y, width: line.width))
                cursor = line.end
            }
            y += lineHeight
        }
        return lines
    }

    // MARK: - Slot carving

    nonisolated static func carveSlots(
        fullLeft: CGFloat, fullRight: CGFloat,
        orbCenter: CGPoint, orbRadius: CGFloat,
        bandTop: CGFloat, bandBottom: CGFloat, minWidth: CGFloat
    ) -> [Slot] {
        let orbTop = orbCenter.y - orbRadius
        let orbBottom = orbCenter.y + orbRadius
        guard bandBottom > orbTop && bandTop < orbBottom else {
            return [Slot(left: fullLeft, right: fullRight)]
        }

        var blockLeft = CGFloat.greatestFiniteMagnitude
        var blockRight = -CGFloat.greatestFiniteMagnitude
        var sampleY = bandTop
        while sampleY <= bandBottom {
            let dy = sampleY - orbCenter.y
            if abs(dy) < orbRadius {
                let dx = sqrt(orbRadius * orbRadius - dy * dy)
                blockLeft = min(blockLeft, orbCenter.x - dx)
                blockRight = max(blockRight, orbCenter.x + dx)
            }
            sampleY += 1
        }
        guard blockLeft < blockRight else {
            return [Slot(left: fullLeft, right: fullRight)]
        }

        var slots: [Slot] = []
        if blockLeft > fullLeft + minWidth { slots.append(Slot(left: fullLeft, right: blockLeft)) }
        if blockRight < fullRight - minWidth { slots.append(Slot(left: blockRight, right: fullRight)) }
        return slots
    }
}

// MARK: - CoreText raw (CTTypesetter per line per frame)

struct CoreTextLayoutView: UIViewRepresentable {
    let bodyText: String; let font: UIFont; let lineHeight: CGFloat
    let orbCenter: CGPoint; let orbRadius: CGFloat; let padding: CGFloat
    let onStats: @MainActor (Int, Double) -> Void

    func makeUIView(context: Context) -> EngineLayoutCanvas {
        let v = EngineLayoutCanvas(); v.backgroundColor = .clear; v.engine = .coretext; return v
    }
    func updateUIView(_ v: EngineLayoutCanvas, context: Context) {
        v.configure(bodyText: bodyText, font: font, lineHeight: lineHeight, orbCenter: orbCenter, orbRadius: orbRadius, padding: padding, onStats: onStats)
    }
}

// MARK: - TextKit 1 (NSLayoutManager + exclusion paths)

struct TextKit1LayoutView: UIViewRepresentable {
    let bodyText: String; let font: UIFont; let lineHeight: CGFloat
    let orbCenter: CGPoint; let orbRadius: CGFloat; let padding: CGFloat
    let onStats: @MainActor (Int, Double) -> Void

    func makeUIView(context: Context) -> EngineLayoutCanvas {
        let v = EngineLayoutCanvas(); v.backgroundColor = .clear; v.engine = .textkit1; return v
    }
    func updateUIView(_ v: EngineLayoutCanvas, context: Context) {
        v.configure(bodyText: bodyText, font: font, lineHeight: lineHeight, orbCenter: orbCenter, orbRadius: orbRadius, padding: padding, onStats: onStats)
    }
}

// MARK: - TextKit 2 (NSTextLayoutManager + exclusion)

struct TextKit2LayoutView: UIViewRepresentable {
    let bodyText: String; let font: UIFont; let lineHeight: CGFloat
    let orbCenter: CGPoint; let orbRadius: CGFloat; let padding: CGFloat
    let onStats: @MainActor (Int, Double) -> Void

    func makeUIView(context: Context) -> EngineLayoutCanvas {
        let v = EngineLayoutCanvas(); v.backgroundColor = .clear; v.engine = .textkit2; return v
    }
    func updateUIView(_ v: EngineLayoutCanvas, context: Context) {
        v.configure(bodyText: bodyText, font: font, lineHeight: lineHeight, orbCenter: orbCenter, orbRadius: orbRadius, padding: padding, onStats: onStats)
    }
}

// MARK: - Unified engine canvas (CoreText / TextKit 1 / TextKit 2)

enum EngineKind { case coretext, textkit1, textkit2 }

final class EngineLayoutCanvas: UIView {
    var engine: EngineKind = .coretext
    private var labels: [UILabel] = []
    private var bodyText = ""
    private var textFont = UIFont.systemFont(ofSize: 15)
    private var lineHeight: CGFloat = 24
    private var orbCenter = CGPoint.zero
    private var orbRadius: CGFloat = 0
    private var padding: CGFloat = 16
    private var onStats: (@MainActor (Int, Double) -> Void)?

    func configure(bodyText: String, font: UIFont, lineHeight: CGFloat,
                   orbCenter: CGPoint, orbRadius: CGFloat, padding: CGFloat,
                   onStats: @escaping @MainActor (Int, Double) -> Void) {
        self.bodyText = bodyText; self.textFont = font; self.lineHeight = lineHeight
        self.orbCenter = orbCenter; self.orbRadius = orbRadius; self.padding = padding
        self.onStats = onStats; setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        switch engine {
        case .coretext: layoutWithCoreText()
        case .textkit1: layoutWithTextKit1()
        case .textkit2: layoutWithTextKit2()
        }
    }

    // MARK: CoreText raw

    private func layoutWithCoreText() {
        let start = CFAbsoluteTimeGetCurrent()
        clearLabels()

        let attrStr = NSAttributedString(string: bodyText, attributes: [.font: textFont])
        let typesetter = CTTypesetterCreateWithAttributedString(attrStr as CFAttributedString)
        var charIndex: CFIndex = 0
        let totalLength = (attrStr.string as NSString).length
        var y = padding
        let fullLeft = padding, fullRight = bounds.width - padding
        let minSlot: CGFloat = 40

        while y + lineHeight <= bounds.height && charIndex < totalLength {
            let slots = DynamicLayoutView.carveSlots(
                fullLeft: fullLeft, fullRight: fullRight,
                orbCenter: orbCenter, orbRadius: orbRadius,
                bandTop: y, bandBottom: y + lineHeight, minWidth: minSlot
            )
            if slots.isEmpty { y += lineHeight; continue }

            for slot in slots {
                let w = slot.right - slot.left
                guard w >= minSlot, charIndex < totalLength else { continue }
                let count = CTTypesetterSuggestLineBreak(typesetter, charIndex, Double(w))
                guard count > 0 else { continue }
                let ctLine = CTTypesetterCreateLine(typesetter, CFRangeMake(charIndex, count))
                addLineLabel(text: bodyText, range: NSRange(location: charIndex, length: count),
                             x: slot.left, y: y, ctLine: ctLine)
                charIndex += count
            }
            y += lineHeight
        }
        reportStats(start: start)
    }

    // MARK: TextKit 1

    private func layoutWithTextKit1() {
        let start = CFAbsoluteTimeGetCurrent()
        clearLabels()

        let textStorage = NSTextStorage(string: bodyText, attributes: [.font: textFont])
        let layoutManager = NSLayoutManager()
        let textContainer = NSTextContainer(size: CGSize(
            width: bounds.width - padding * 2, height: bounds.height - padding * 2
        ))
        textContainer.lineFragmentPadding = 0

        // Exclusion path: circle for the orb
        let orbRect = CGRect(
            x: orbCenter.x - orbRadius - padding,
            y: orbCenter.y - orbRadius - padding,
            width: orbRadius * 2,
            height: orbRadius * 2
        )
        let exclusionPath = UIBezierPath(ovalIn: orbRect)
        textContainer.exclusionPaths = [exclusionPath]

        layoutManager.addTextContainer(textContainer)
        textStorage.addLayoutManager(layoutManager)

        // Force full layout
        layoutManager.ensureLayout(for: textContainer)

        // Extract line fragments and render
        let glyphRange = layoutManager.glyphRange(for: textContainer)
        var lineIndex = 0
        layoutManager.enumerateLineFragments(forGlyphRange: glyphRange) { [self] rect, usedRect, _, range, _ in
            let charRange = layoutManager.characterRange(forGlyphRange: range, actualGlyphRange: nil)
            let lineText = (bodyText as NSString).substring(with: charRange)
            let label = UILabel()
            label.font = textFont
            label.textColor = UIColor.white.withAlphaComponent(0.85)
            label.text = lineText.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            label.frame = CGRect(x: usedRect.origin.x + padding, y: usedRect.origin.y + padding,
                                 width: usedRect.width, height: usedRect.height)
            addSubview(label)
            labels.append(label)
            lineIndex += 1
        }
        reportStats(start: start)
    }

    // MARK: TextKit 2

    private func layoutWithTextKit2() {
        let start = CFAbsoluteTimeGetCurrent()
        clearLabels()

        let contentStorage = NSTextContentStorage()
        contentStorage.attributedString = NSAttributedString(string: bodyText, attributes: [
            .font: textFont,
            .foregroundColor: UIColor.white.withAlphaComponent(0.85),
        ])

        let textContainer = NSTextContainer(size: CGSize(
            width: bounds.width - padding * 2, height: bounds.height - padding * 2
        ))
        textContainer.lineFragmentPadding = 0

        let orbRect = CGRect(
            x: orbCenter.x - orbRadius - padding,
            y: orbCenter.y - orbRadius - padding,
            width: orbRadius * 2,
            height: orbRadius * 2
        )
        textContainer.exclusionPaths = [UIBezierPath(ovalIn: orbRect)]

        let textLayoutManager = NSTextLayoutManager()
        textLayoutManager.textContainer = textContainer
        contentStorage.addTextLayoutManager(textLayoutManager)

        // Force full layout
        textLayoutManager.ensureLayout(for: textLayoutManager.documentRange)

        // Enumerate layout fragments (paragraph-level), then line fragments within each
        textLayoutManager.enumerateTextLayoutFragments(
            from: textLayoutManager.documentRange.location,
            options: [.ensuresLayout, .ensuresExtraLineFragment]
        ) { [self] fragment in
            let fragmentOrigin = fragment.layoutFragmentFrame.origin

            // Each layout fragment contains line-level sub-fragments
            for lineFragment in fragment.textLineFragments {
                let lineOrigin = lineFragment.typographicBounds.origin
                let lineText = lineFragment.attributedString.string

                let label = UILabel()
                label.font = textFont
                label.textColor = UIColor.white.withAlphaComponent(0.85)
                label.text = lineText

                let x = fragmentOrigin.x + lineOrigin.x + padding
                let y = fragmentOrigin.y + lineOrigin.y + padding
                let w = lineFragment.typographicBounds.width
                let h = lineFragment.typographicBounds.height

                label.frame = CGRect(x: x, y: y, width: w, height: h)
                addSubview(label)
                labels.append(label)
            }
            return true
        }
        reportStats(start: start)
    }

    // MARK: Helpers

    private func clearLabels() {
        for l in labels { l.removeFromSuperview() }
        labels.removeAll()
    }

    private func addLineLabel(text: String, range: NSRange, x: CGFloat, y: CGFloat, ctLine: CTLine) {
        let label = UILabel()
        label.font = textFont
        label.textColor = UIColor.white.withAlphaComponent(0.85)
        let nsStr = text as NSString
        let safe = NSRange(location: min(range.location, nsStr.length),
                           length: min(range.length, nsStr.length - min(range.location, nsStr.length)))
        label.text = nsStr.substring(with: safe).trimmingCharacters(in: CharacterSet.whitespaces)
        let w = CGFloat(CTLineGetTypographicBounds(ctLine, nil, nil, nil))
        label.frame = CGRect(x: x, y: y, width: w, height: lineHeight)
        addSubview(label)
        labels.append(label)
    }

    private func reportStats(start: CFAbsoluteTime) {
        let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1_000_000
        onStats?(labels.count, elapsed)
    }
}

// MARK: - Supporting types

struct Slot {
    let left: CGFloat
    let right: CGFloat
}

struct PositionedLine {
    let text: String
    let x: CGFloat
    let y: CGFloat
    let width: CGFloat
}

// MARK: - Orb view

private struct OrbView: View {
    let radius: CGFloat
    var body: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(
                    colors: [Color(red: 0.2, green: 0.5, blue: 0.4).opacity(0.6),
                             Color(red: 0.1, green: 0.3, blue: 0.3).opacity(0.3), .clear],
                    center: .center, startRadius: 0, endRadius: radius
                ))
                .frame(width: radius * 2.5, height: radius * 2.5)
            Circle()
                .fill(RadialGradient(
                    colors: [Color(red: 0.3, green: 0.7, blue: 0.5).opacity(0.8),
                             Color(red: 0.1, green: 0.4, blue: 0.3).opacity(0.5),
                             Color(red: 0.05, green: 0.2, blue: 0.15).opacity(0.2)],
                    center: UnitPoint(x: 0.35, y: 0.35), startRadius: 0, endRadius: radius
                ))
                .frame(width: radius * 2, height: radius * 2)
            Circle()
                .fill(RadialGradient(
                    colors: [.white.opacity(0.15), .clear],
                    center: UnitPoint(x: 0.3, y: 0.3), startRadius: 0, endRadius: radius * 0.6
                ))
                .frame(width: radius * 2, height: radius * 2)
        }
    }
}

// MARK: - Stat badge

private struct StatBadge: View {
    let label: String; let value: String; let color: Color
    var body: some View {
        HStack(spacing: 4) {
            Text(label).font(.caption2.bold()).foregroundStyle(.white.opacity(0.5))
            Text(value).font(.caption2.bold().monospacedDigit()).foregroundStyle(color)
                .padding(.horizontal, 5).padding(.vertical, 1)
                .background(color.opacity(0.15), in: RoundedRectangle(cornerRadius: 3))
        }
    }
}
