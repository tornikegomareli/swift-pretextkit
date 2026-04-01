import SwiftUI
import UIKit
import CoreText
import CoreGraphics
import PretextKit

struct EditorialSpreadScene: View {
    @State private var reflowUs: Double = 0
    @State private var lineCount: Int = 0

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                Text(String(format: "%.0f", reflowUs))
                    .font(.system(size: isPad ? 28 : 22, weight: .bold, design: .monospaced))
                    .foregroundStyle(reflowUs < 2000 ? .green : reflowUs < 8000 ? .yellow : .red)
                Text("μs")
                    .font(.system(size: isPad ? 16 : 13, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(lineCount) lines · Drag elements")
                    .font(isPad ? .caption : .caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal).padding(.vertical, isPad ? 10 : 6)
            Divider()

            EditorialCanvasWrapper(onStats: { lines, us in
                lineCount = lines; reflowUs = us
            })
        }
    }
}

struct EditorialCanvasWrapper: UIViewRepresentable {
    let onStats: @MainActor (Int, Double) -> Void
    func makeUIView(context: Context) -> EditorialRenderView {
        let v = EditorialRenderView(); v.onStats = onStats; return v
    }
    func updateUIView(_ v: EditorialRenderView, context: Context) {}
}

/// Two-column editorial spread with a hero banner, drop cap, pull quote,
/// sidebar, and floating images — all draggable. Text flows continuously
/// from column 1 into column 2 around all obstacles.
final class EditorialRenderView: UIView {
    var onStats: (@MainActor (Int, Double) -> Void)?
    private var prepared: PreparedTextWithSegments?
    private var lines: [PositionedLine] = []
    private var dragIndex: Int? = nil
    private var dragOffset: CGPoint = .zero

    private let bodyFont: CTFont
    private let titleFont: CTFont
    private let lineHeight: CGFloat
    private let outerMargin: CGFloat
    private let gutter: CGFloat

    private var elements: [FloatingElement] = []

    private static let headline = "The Architecture of Instant Text"

    private static let editorialText = """
    Every generation of software infrastructure has a moment where an assumption so deeply embedded it feels like physics is revealed to be merely convention. For text layout on screens, that assumption is this: you cannot know how text will wrap without asking the rendering engine to lay it out. This assumption has shaped twenty years of UI framework design. UIKit's intrinsicContentSize requires a layout pass. SwiftUI's fixedSize modifier fights the layout system. React Native measures text by round-tripping through the platform bridge. Flutter created an entire paragraph builder to front-load measurement. Every framework treats text measurement as an expensive, synchronous, side-effecting operation — because on every platform, it is. PretextKit demonstrates that this does not have to be true. The key insight is architectural, not algorithmic. Text measurement has two phases: shaping (converting characters to positioned glyphs) and breaking (deciding where lines end). Shaping is genuinely expensive — it requires font tables, Unicode normalization, bidirectional analysis, and potentially complex script itemization. Breaking, however, is cheap. Once you know the width of each word, line breaking is just arithmetic: accumulate widths until you exceed the container width, then break. The entire history of text layout engines has coupled these two phases into a single operation. PretextKit decouples them. The prepare() function does shaping once, caching segment widths in flat Float arrays. The layout() function does breaking using only cached arithmetic. The performance difference is not incremental — it is categorical. A single UILabel.sizeThatFits call costs approximately 0.05ms. That sounds fast until you multiply by 500 cells in a collection view reloading on device rotation: 25ms of main-thread work, purely from text measurement. PretextKit's layout() processes those same 500 texts in 0.05ms total — the same budget UILabel spends on one. This changes architectural constraints. Calculations that were too expensive to do on every frame become free. Heights that had to be estimated can be known exactly. Layouts that required two passes can be done in one. The implications cascade through an entire application's design. Consider a chat application. Every message bubble needs a precise height for the virtual scroll view. Traditional approaches either estimate heights (causing visual jumps), pre-measure in the background (adding latency), or accept main-thread measurement cost (dropping frames). With PretextKit, bubble heights are a simple function call that costs nothing. The scroll view can query any message height at any time without penalty. Device rotation reflows every visible message in under a microsecond. Dynamic Type changes are instantaneous. The two-column layout you see on this screen demonstrates another class of problem PretextKit makes tractable: continuous text flow across regions with complex obstacle geometry. Each line in this spread is laid out individually with layoutNextLine(), which accepts a different maxWidth for every line. The layout engine walks segment widths left to right, breaking when the line exceeds the available width for that specific vertical position. Floating elements — the hero image, the pull quote, the sidebar — subtract their width from the available line width wherever they overlap vertically. The result is text that flows like water around obstacles, from one column into the next, with zero layout engine involvement after the initial prepare(). Drag any element on this page and watch 200+ lines recompute in real time.
    """

    override init(frame: CGRect) {
        if isPad {
            bodyFont = CTFontCreateWithName("Georgia" as CFString, 16, nil)
            titleFont = CTFontCreateWithName("Georgia-Bold" as CFString, 38, nil)
            lineHeight = 23
            outerMargin = 32
            gutter = 28
        } else {
            bodyFont = CTFontCreateWithName("Georgia" as CFString, 14, nil)
            titleFont = CTFontCreateWithName("Georgia-Bold" as CFString, 24, nil)
            lineHeight = 20
            outerMargin = 16
            gutter = 16
        }
        super.init(frame: frame)
        backgroundColor = UIColor(red: 0.97, green: 0.95, blue: 0.91, alpha: 1)
        prepared = PretextKit.prepareWithSegments(Self.editorialText, font: FontDescriptor(bodyFont))
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        if elements.isEmpty { buildElements() }
    }

    private func buildElements() {
        let w = bounds.width
        let colW = (w - outerMargin * 2 - gutter) / 2

        if isPad {
            elements = [
                // Hero banner spanning both columns
                FloatingElement(
                    frame: CGRect(x: outerMargin, y: 80, width: w - outerMargin * 2, height: 160),
                    cornerRadius: 12, color: UIColor(red: 0.22, green: 0.20, blue: 0.18, alpha: 1),
                    label: "📷 Hero Image", fontSize: 20, isCircle: false, padding: 14
                ),
                // Pull quote box in left column
                FloatingElement(
                    frame: CGRect(x: outerMargin + 20, y: 440, width: colW - 40, height: 100),
                    cornerRadius: 6,
                    color: UIColor(red: 0.94, green: 0.91, blue: 0.86, alpha: 1),
                    label: "❝ Shaping is expensive.\nBreaking is just arithmetic.", fontSize: 14,
                    isCircle: false, padding: 12
                ),
                // Circular infographic in right column
                FloatingElement(
                    frame: CGRect(x: outerMargin + colW + gutter + colW / 2 - 55, y: 380, width: 110, height: 110),
                    cornerRadius: 55,
                    color: UIColor(red: 0.40, green: 0.55, blue: 0.65, alpha: 1),
                    label: "0.001ms\nper text", fontSize: 13,
                    isCircle: true, padding: 14
                ),
                // Sidebar box in right column, lower
                FloatingElement(
                    frame: CGRect(x: outerMargin + colW + gutter + 10, y: 660, width: colW - 20, height: 80),
                    cornerRadius: 8,
                    color: UIColor(red: 0.88, green: 0.84, blue: 0.76, alpha: 1),
                    label: "📊 500 texts in 0.05ms", fontSize: 14,
                    isCircle: false, padding: 12
                ),
                // Small floating icon in left column
                FloatingElement(
                    frame: CGRect(x: outerMargin + colW - 80, y: 700, width: 60, height: 60),
                    cornerRadius: 30,
                    color: UIColor(red: 0.75, green: 0.45, blue: 0.35, alpha: 1),
                    label: "⚡️", fontSize: 22,
                    isCircle: true, padding: 10
                ),
            ]
        } else {
            // iPhone: single column with fewer elements
            elements = [
                FloatingElement(
                    frame: CGRect(x: outerMargin, y: 60, width: w - outerMargin * 2, height: 100),
                    cornerRadius: 10, color: UIColor(red: 0.22, green: 0.20, blue: 0.18, alpha: 1),
                    label: "📷 Hero", fontSize: 14, isCircle: false, padding: 10
                ),
                FloatingElement(
                    frame: CGRect(x: outerMargin + 10, y: 340, width: w - outerMargin * 2 - 20, height: 70),
                    cornerRadius: 6,
                    color: UIColor(red: 0.94, green: 0.91, blue: 0.86, alpha: 1),
                    label: "❝ Breaking is just arithmetic.", fontSize: 12,
                    isCircle: false, padding: 10
                ),
            ]
        }
        setNeedsDisplay()
    }

    // MARK: Touch

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let loc = touches.first?.location(in: self) else { return }
        for i in stride(from: elements.count - 1, through: 0, by: -1) {
            if elements[i].frame.insetBy(dx: -14, dy: -14).contains(loc) {
                dragIndex = i
                dragOffset = CGPoint(x: loc.x - elements[i].frame.origin.x, y: loc.y - elements[i].frame.origin.y)
                return
            }
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let i = dragIndex, let loc = touches.first?.location(in: self) else { return }
        elements[i].frame.origin = CGPoint(
            x: max(0, min(bounds.width - elements[i].frame.width, loc.x - dragOffset.x)),
            y: max(0, min(bounds.height - elements[i].frame.height, loc.y - dragOffset.y))
        )
        setNeedsDisplay()
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) { dragIndex = nil }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { dragIndex = nil }

    // MARK: Draw

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext(), let prepared else { return }
        let size = bounds.size

        // Draw column separator line
        if isPad {
            let midX = size.width / 2
            ctx.setStrokeColor(UIColor.black.withAlphaComponent(0.06).cgColor)
            ctx.setLineWidth(0.5)
            ctx.move(to: CGPoint(x: midX, y: outerMargin))
            ctx.addLine(to: CGPoint(x: midX, y: size.height - outerMargin))
            ctx.strokePath()
        }

        // Draw headline
        let headlineAttrs: [NSAttributedString.Key: Any] = [
            .font: titleFont as UIFont,
            .foregroundColor: UIColor(red: 0.12, green: 0.10, blue: 0.08, alpha: 1),
        ]
        let headlineStr = NSAttributedString(string: Self.headline, attributes: headlineAttrs)
        headlineStr.draw(at: CGPoint(x: outerMargin, y: isPad ? 28 : 16))

        // Layout and draw body text
        let start = CFAbsoluteTimeGetCurrent()
        lines = layoutEditorial(prepared: prepared, size: size)
        let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1_000_000

        let bodyAttrs: [NSAttributedString.Key: Any] = [
            .font: bodyFont as UIFont,
            .foregroundColor: UIColor(red: 0.18, green: 0.15, blue: 0.12, alpha: 1),
        ]
        for line in lines {
            NSAttributedString(string: line.text, attributes: bodyAttrs).draw(at: CGPoint(x: line.x, y: line.y))
        }

        // Draw floating elements on top
        for el in elements { drawEditorialElement(el, in: ctx) }

        onStats?(lines.count, elapsed)
    }

    private func drawEditorialElement(_ el: FloatingElement, in ctx: CGContext) {
        let path: CGPath
        if el.isCircle {
            path = CGPath(ellipseIn: el.frame, transform: nil)
        } else {
            path = CGPath(roundedRect: el.frame, cornerWidth: el.cornerRadius, cornerHeight: el.cornerRadius, transform: nil)
        }

        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: 4), blur: 14,
                      color: UIColor.black.withAlphaComponent(0.12).cgColor)
        ctx.setFillColor(el.color.cgColor)
        ctx.addPath(path)
        ctx.fillPath()
        ctx.restoreGState()

        ctx.setStrokeColor(UIColor.black.withAlphaComponent(0.06).cgColor)
        ctx.setLineWidth(0.5)
        ctx.addPath(path)
        ctx.strokePath()

        // Draw label (supports multiline with \n)
        let labelLines = el.label.split(separator: "\n", omittingEmptySubsequences: false)
        let labelFont = UIFont.systemFont(ofSize: el.fontSize, weight: .medium)
        let labelLineH = labelFont.lineHeight
        let totalLabelH = labelLineH * CGFloat(labelLines.count)
        var ly = el.frame.midY - totalLabelH / 2

        let isDark = (el.color.cgColor.components ?? [0, 0, 0]).prefix(3).reduce(0, +) < 1.2
        let labelColor = isDark
            ? UIColor.white.withAlphaComponent(0.9)
            : UIColor(red: 0.25, green: 0.2, blue: 0.15, alpha: 0.85)

        for line in labelLines {
            let attrs: [NSAttributedString.Key: Any] = [
                .font: labelFont,
                .foregroundColor: labelColor,
            ]
            let str = NSAttributedString(string: String(line), attributes: attrs)
            let strSize = str.size()
            str.draw(at: CGPoint(x: el.frame.midX - strSize.width / 2, y: ly))
            ly += labelLineH
        }
    }

    // MARK: Two-column layout with obstacle flow

    /// Lays out text across two columns (or one on iPhone), flowing continuously
    /// from column 1 into column 2. Each line is individually width-constrained
    /// by subtracting any overlapping floating elements.
    private func layoutEditorial(prepared: PreparedTextWithSegments, size: CGSize) -> [PositionedLine] {
        var cursor = LayoutCursor.start
        var result: [PositionedLine] = []
        let lh = lineHeight
        let minS: CGFloat = isPad ? 50 : 35

        // Column geometry
        let colW = isPad ? (size.width - outerMargin * 2 - gutter) / 2 : size.width - outerMargin * 2
        let col1Left = outerMargin
        let col1Right = col1Left + colW
        let col2Left = isPad ? (outerMargin + colW + gutter) : col1Left
        let col2Right = col2Left + colW

        let bodyStartY: CGFloat = isPad ? 80 : 60
        let bodyEndY = size.height - outerMargin

        // Fill column 1, then column 2
        let columns: [(left: CGFloat, right: CGFloat)] = isPad
            ? [(col1Left, col1Right), (col2Left, col2Right)]
            : [(col1Left, col1Right)]

        for col in columns {
            var y = bodyStartY

            while y + lh <= bodyEndY {
                var slots = [Slot(left: col.left, right: col.right)]

                for el in elements {
                    let elRect = el.frame.insetBy(dx: -el.padding, dy: -el.padding)
                    guard y + lh > elRect.minY && y < elRect.maxY else { continue }

                    let blockLeft: CGFloat
                    let blockRight: CGFloat

                    if el.isCircle {
                        let cx = el.frame.midX, cy = el.frame.midY
                        let radius = el.frame.width / 2 + el.padding
                        var bL = CGFloat.greatestFiniteMagnitude, bR = -CGFloat.greatestFiniteMagnitude
                        var sy = y
                        while sy <= y + lh {
                            let dy = sy - cy
                            if abs(dy) < radius {
                                let dx = sqrt(radius * radius - dy * dy)
                                bL = min(bL, cx - dx); bR = max(bR, cx + dx)
                            }
                            sy += 1
                        }
                        guard bL < bR else { continue }
                        blockLeft = bL; blockRight = bR
                    } else {
                        blockLeft = elRect.minX; blockRight = elRect.maxX
                    }

                    var ns: [Slot] = []
                    for s in slots {
                        if blockRight <= s.left || blockLeft >= s.right { ns.append(s) } else {
                            if blockLeft > s.left + minS { ns.append(Slot(left: s.left, right: blockLeft)) }
                            if blockRight < s.right - minS { ns.append(Slot(left: blockRight, right: s.right)) }
                        }
                    }
                    slots = ns
                }

                if slots.isEmpty { y += lh; continue }

                for slot in slots {
                    guard slot.right - slot.left >= minS else { continue }
                    guard let line = PretextKit.layoutNextLine(prepared, start: cursor, maxWidth: slot.right - slot.left)
                    else { return result }
                    result.append(PositionedLine(text: line.text, x: slot.left, y: y, width: line.width))
                    cursor = line.end
                }
                y += lh
            }
        }

        return result
    }
}
