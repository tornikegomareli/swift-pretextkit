import SwiftUI
import UIKit
import CoreText
import CoreGraphics
import PretextKit

struct DynamicDragScene: View {
    @State private var reflowUs: Double = 0
    @State private var lineCount: Int = 0

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                Text(String(format: "%.0f", reflowUs))
                    .font(.system(size: isPad ? 28 : 22, weight: .bold, design: .monospaced))
                    .foregroundStyle(reflowUs < 1000 ? .green : reflowUs < 5000 ? .yellow : .red)
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

            ArticleCanvasWrapper(onStats: { lines, us in
                lineCount = lines; reflowUs = us
            })
        }
    }
}

struct ArticleCanvasWrapper: UIViewRepresentable {
    let onStats: @MainActor (Int, Double) -> Void
    func makeUIView(context: Context) -> ArticleRenderView {
        let v = ArticleRenderView(); v.onStats = onStats; return v
    }
    func updateUIView(_ v: ArticleRenderView, context: Context) {}
}

final class ArticleRenderView: UIView {
    var onStats: (@MainActor (Int, Double) -> Void)?
    private var prepared: PreparedTextWithSegments?
    private var lines: [PositionedLine] = []
    private var dragIndex: Int? = nil
    private var dragOffset: CGPoint = .zero

    private let bodyFont: CTFont
    private let lineHeight: CGFloat
    private let margin: CGFloat

    private var elements: [FloatingElement] = []

    private static let articleText = """
    Building dynamic text layouts on iOS has always been one of the hardest challenges in mobile development. Unlike the web, where CSS float and exclusion properties handle text wrapping natively, iOS developers have historically been forced to choose between TextKit's buggy exclusion paths or manual CoreText line breaking — both expensive, both fragile. PretextKit changes this equation entirely. By precomputing segment widths once and performing pure arithmetic reflow, it enables the kind of fluid, magazine-quality text layouts that were previously impractical in production apps. Consider this article you are reading right now. The text flows around a floating image, wraps beside a pull quote, and routes around an author avatar — all computed in under a millisecond. Drag any element and watch every line recompute instantly. On a traditional iOS stack, this layout would require either a full TextKit setup with NSTextContainer exclusion paths — which frequently breaks on rotation and has known viewport estimation bugs in TextKit 2 — or a manual CTTypesetter loop that reshapes every glyph on every frame. Both approaches cost 5-20ms per reflow. PretextKit does it in microseconds because the expensive font shaping was already done during prepare(). The layout() call simply walks cached Float arrays with basic arithmetic. No font engine, no glyph lookup, no attributed string creation. This is not a marginal improvement. It is a categorical change in what is possible. Instagram, Telegram, and Twitter all built custom text engines for exactly this reason. PretextKit brings that same capability to any iOS app as a simple Swift package. The API is intentionally minimal: prepare() once when text arrives, layout() on every resize or reflow. For advanced use cases like this article, layoutNextLine() gives you one line at a time with a different maxWidth each call — the building block for any obstacle-aware text flow.
    """

    private static let iPadExtraText = """
     What makes this demonstration particularly compelling on iPad is the sheer amount of screen real estate available for text flow. With a 12.9-inch display, you are looking at roughly 200 lines of text that must reflow around six independent obstacles every time you drag one. Each drag gesture fires 60 touch events per second, and each event triggers a complete relayout of every line on screen. That is 12,000 line-break decisions per second — and PretextKit handles all of them in well under a millisecond total. The secret is in the data model. After prepare() runs, every segment's width is stored in a flat Float array. The layout engine walks this array with a single pointer, accumulating widths until it exceeds maxWidth, then emitting a line break. There are no hash table lookups, no string comparisons, no object allocations, and no virtual dispatch. The entire operation is branch-prediction-friendly because the common case — "this segment fits on the current line" — dominates. On Apple Silicon, the layout loop runs almost entirely out of the L1 cache. The implications for real applications are significant. A news reader can reflow articles instantly when entering Split View. A document editor can show live text wrapping around floating images as the user drags them. A chat application can predict exact bubble heights for tens of thousands of messages without a single UILabel measurement. A forms engine can compute dynamic heights for every field as the keyboard appears and the safe area changes. All of these use cases share the same fundamental requirement: fast, repeated text measurement at arbitrary widths. PretextKit makes this not just possible, but trivial.
    """

    override init(frame: CGRect) {
        if isPad {
            bodyFont = CTFontCreateWithName("Georgia" as CFString, 18, nil)
            lineHeight = 26
            margin = 24
        } else {
            bodyFont = CTFontCreateWithName("Georgia" as CFString, 15, nil)
            lineHeight = 22
            margin = 16
        }
        super.init(frame: frame)
        backgroundColor = UIColor(red: 0.98, green: 0.97, blue: 0.95, alpha: 1)

        let fullText = isPad ? Self.articleText + Self.iPadExtraText : Self.articleText
        prepared = PretextKit.prepareWithSegments(fullText, font: FontDescriptor(bodyFont))

        if isPad {
            elements = [
                FloatingElement(
                    frame: CGRect(x: 24, y: 24, width: 200, height: 150),
                    cornerRadius: 14, color: UIColor(red: 0.85, green: 0.75, blue: 0.6, alpha: 1),
                    label: "📸 Hero Image", fontSize: 17, isCircle: false, padding: 16
                ),
                FloatingElement(
                    frame: CGRect(x: 500, y: 180, width: 220, height: 130),
                    cornerRadius: 12, color: UIColor(red: 0.93, green: 0.9, blue: 0.85, alpha: 1),
                    label: "❝ Pull Quote", fontSize: 15, isCircle: false, padding: 14
                ),
                FloatingElement(
                    frame: CGRect(x: 30, y: 480, width: 100, height: 100),
                    cornerRadius: 50, color: UIColor(red: 0.58, green: 0.38, blue: 0.24, alpha: 1),
                    label: "👤", fontSize: 30, isCircle: true, padding: 14
                ),
                FloatingElement(
                    frame: CGRect(x: 450, y: 550, width: 180, height: 120),
                    cornerRadius: 12, color: UIColor(red: 0.78, green: 0.85, blue: 0.82, alpha: 1),
                    label: "📊 Chart", fontSize: 16, isCircle: false, padding: 14
                ),
                FloatingElement(
                    frame: CGRect(x: 250, y: 380, width: 90, height: 90),
                    cornerRadius: 45, color: UIColor(red: 0.45, green: 0.55, blue: 0.75, alpha: 1),
                    label: "🔗", fontSize: 28, isCircle: true, padding: 12
                ),
                FloatingElement(
                    frame: CGRect(x: 620, y: 700, width: 160, height: 100),
                    cornerRadius: 10, color: UIColor(red: 0.9, green: 0.82, blue: 0.7, alpha: 1),
                    label: "💬 Comment", fontSize: 14, isCircle: false, padding: 14
                ),
            ]
        } else {
            elements = [
                FloatingElement(
                    frame: CGRect(x: 16, y: 16, width: 130, height: 100),
                    cornerRadius: 10, color: UIColor(red: 0.85, green: 0.75, blue: 0.6, alpha: 1),
                    label: "📸 Photo", fontSize: 14, isCircle: false, padding: 12
                ),
                FloatingElement(
                    frame: CGRect(x: 210, y: 240, width: 160, height: 90),
                    cornerRadius: 8, color: UIColor(red: 0.93, green: 0.9, blue: 0.85, alpha: 1),
                    label: "❝ Pull Quote", fontSize: 12, isCircle: false, padding: 10
                ),
                FloatingElement(
                    frame: CGRect(x: 20, y: 430, width: 70, height: 70),
                    cornerRadius: 35, color: UIColor(red: 0.58, green: 0.38, blue: 0.24, alpha: 1),
                    label: "👤", fontSize: 24, isCircle: true, padding: 10
                ),
            ]
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let loc = touches.first?.location(in: self) else { return }
        for i in stride(from: elements.count - 1, through: 0, by: -1) {
            let hitFrame = elements[i].frame.insetBy(dx: -12, dy: -12)
            if hitFrame.contains(loc) {
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

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext(), let prepared else { return }

        let start = CFAbsoluteTimeGetCurrent()
        lines = layoutArticle(prepared: prepared, size: bounds.size)
        let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1_000_000

        let attrs: [NSAttributedString.Key: Any] = [
            .font: bodyFont as UIFont,
            .foregroundColor: UIColor(red: 0.15, green: 0.12, blue: 0.1, alpha: 1),
        ]
        for line in lines {
            NSAttributedString(string: line.text, attributes: attrs).draw(at: CGPoint(x: line.x, y: line.y))
        }

        for el in elements { drawElement(el, in: ctx) }
        onStats?(lines.count, elapsed)
    }

    private func drawElement(_ el: FloatingElement, in ctx: CGContext) {
        let path: CGPath
        if el.isCircle {
            path = CGPath(ellipseIn: el.frame, transform: nil)
        } else {
            path = CGPath(roundedRect: el.frame, cornerWidth: el.cornerRadius, cornerHeight: el.cornerRadius, transform: nil)
        }

        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: 3), blur: isPad ? 12 : 8,
                      color: UIColor.black.withAlphaComponent(0.18).cgColor)
        ctx.setFillColor(el.color.cgColor)
        ctx.addPath(path)
        ctx.fillPath()
        ctx.restoreGState()

        ctx.setStrokeColor(UIColor.black.withAlphaComponent(0.08).cgColor)
        ctx.setLineWidth(0.5)
        ctx.addPath(path)
        ctx.strokePath()

        let labelAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: el.fontSize, weight: .medium),
            .foregroundColor: UIColor(red: 0.3, green: 0.25, blue: 0.2, alpha: 0.8),
        ]
        let labelStr = NSAttributedString(string: el.label, attributes: labelAttrs)
        let labelSize = labelStr.size()
        labelStr.draw(at: CGPoint(x: el.frame.midX - labelSize.width / 2, y: el.frame.midY - labelSize.height / 2))
    }

    private func layoutArticle(prepared: PreparedTextWithSegments, size: CGSize) -> [PositionedLine] {
        var cursor = LayoutCursor.start
        var y = margin
        var result: [PositionedLine] = []
        let fL = margin, fR = size.width - margin
        let minS: CGFloat = isPad ? 60 : 40
        let lh = lineHeight

        while y + lh <= size.height - margin {
            var slots = [Slot(left: fL, right: fR)]

            for el in elements {
                let elRect = el.frame.insetBy(dx: -el.padding, dy: -el.padding)
                guard y + lh > elRect.minY && y < elRect.maxY else { continue }

                let blockLeft: CGFloat
                let blockRight: CGFloat

                if el.isCircle {
                    let centerX = el.frame.midX
                    let centerY = el.frame.midY
                    let radius = el.frame.width / 2 + el.padding
                    var bL = CGFloat.greatestFiniteMagnitude, bR = -CGFloat.greatestFiniteMagnitude
                    var sy = y
                    while sy <= y + lh {
                        let dy = sy - centerY
                        if abs(dy) < radius {
                            let dx = sqrt(radius * radius - dy * dy)
                            bL = min(bL, centerX - dx)
                            bR = max(bR, centerX + dx)
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
                guard let line = PretextKit.layoutNextLine(prepared, start: cursor, maxWidth: slot.right - slot.left) else { return result }
                result.append(PositionedLine(text: line.text, x: slot.left, y: y, width: line.width))
                cursor = line.end
            }
            y += lh
        }
        return result
    }
}
