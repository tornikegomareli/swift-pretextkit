import SwiftUI
import UIKit
import CoreText
import CoreGraphics
import PretextKit

// MARK: - Scene selector

enum PhysicsScene: String, CaseIterable {
    case orbs = "Bouncing Orbs"
    case dynamic = "Dynamic Layout"
}

struct TextPhysicsView: View {
    @State private var scene: PhysicsScene = .orbs

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(PhysicsScene.allCases, id: \.self) { s in
                            Button {
                                scene = s
                            } label: {
                                Text(s.rawValue)
                                    .font(.caption.bold())
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(scene == s ? Color.blue : Color(.systemGray5))
                                    .foregroundStyle(scene == s ? .white : .primary)
                                    .clipShape(Capsule())
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 6)
                }
                Divider()

                switch scene {
                case .orbs:
                    BouncingOrbsScene()
                case .dynamic:
                    DynamicDragScene()
                }
            }
            .navigationTitle("Showcases")
        }
    }
}

// MARK: =========================================================
// MARK: 1. BOUNCING ORBS (slow, elegant)
// MARK: =========================================================

private struct BouncingOrbsScene: View {
    @State private var reflowUs: Double = 0
    @State private var lineCount: Int = 0
    @State private var orbCount: Int = 4

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                Text(String(format: "%.0f", reflowUs))
                    .font(.system(size: 22, weight: .bold, design: .monospaced))
                    .foregroundStyle(reflowUs < 2000 ? .green : reflowUs < 8000 ? .yellow : .red)
                Text("μs")
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.4))
                Spacer()
                Text("\(orbCount) orbs · \(lineCount) lines · Tap to add")
                    .font(.caption2).foregroundStyle(.white.opacity(0.25))
            }
            .padding(.horizontal).padding(.vertical, 6).background(.black)
            Divider()

            OrbCanvasWrapper(onStats: { lines, us, orbs in
                lineCount = lines; reflowUs = us; orbCount = orbs
            })
        }
    }
}

private struct OrbCanvasWrapper: UIViewRepresentable {
    let onStats: @MainActor (Int, Double, Int) -> Void
    func makeUIView(context: Context) -> OrbRenderView {
        let v = OrbRenderView(); v.onStats = onStats; return v
    }
    func updateUIView(_ v: OrbRenderView, context: Context) {}
}

final class OrbRenderView: UIView {
    var onStats: (@MainActor (Int, Double, Int) -> Void)?
    private var displayLink: CADisplayLink?
    private var prepared: PreparedTextWithSegments?
    private var lines: [PositionedLine] = []
    private var orbs: [Orb] = []
    private let textFont = CTFontCreateWithName("Georgia" as CFString, 13, nil)
    private let lineHeight: CGFloat = 17

    private static let bodyText = """
    Text becomes a first-class participant in the visual composition — not a static block, but a fluid material that adapts in real time. The performance improvement is not incremental — it is categorical. Zero reflows versus five hundred. The web renders text through a pipeline designed thirty years ago for static documents. A browser loads a font, shapes the text into glyphs, measures their width, determines where lines break, and positions each line vertically. Every step depends on the previous one. Every step requires the rendering engine to consult its internal layout tree — a structure so expensive to maintain that browsers guard access behind synchronous reflow barriers. But the web is no longer a collection of static documents. It is a platform for applications. A messaging application needs exact heights. A masonry layout needs card heights. An editorial page needs text to flow around obstacles. A responsive dashboard needs real-time reflow. Every operation requires text measurement. The cost is devastating. Measuring five hundred text blocks triggers five hundred full layout passes. PretextKit solves this. Prepare once. Reflow infinitely. Pure arithmetic. Zero allocations. Sub-microsecond per text block. The future of text layout is not faster engines — it is no engine at all in the hot path.
    """

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        prepared = PretextKit.prepareWithSegments(Self.bodyText, font: FontDescriptor(textFont))
    }
    required init?(coder: NSCoder) { fatalError() }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil {
            if orbs.isEmpty { spawnOrbs() }
            displayLink = CADisplayLink(target: self, selector: #selector(tick))
            displayLink?.add(to: .main, forMode: .common)
        } else { displayLink?.invalidate(); displayLink = nil }
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let loc = touches.first?.location(in: self) else { return }
        let colors: [(Double, Double, Double)] = [
            (0.2, 0.5, 0.9), (0.9, 0.3, 0.4), (0.3, 0.8, 0.5),
            (0.8, 0.6, 0.2), (0.6, 0.3, 0.8), (0.9, 0.5, 0.7),
        ]
        orbs.append(Orb(
            position: loc,
            velocity: CGPoint(x: .random(in: -40...40), y: .random(in: -40...40)),
            radius: .random(in: 40...60),
            color: colors[orbs.count % colors.count]
        ))
    }

    @objc private func tick(_ link: CADisplayLink) {
        stepPhysics()
        setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext(), let prepared else { return }
        let start = CFAbsoluteTimeGetCurrent()
        lines = layoutAroundOrbs(prepared: prepared, size: bounds.size)
        let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1_000_000

        let attrs: [NSAttributedString.Key: Any] = [
            .font: textFont as UIFont,
            .foregroundColor: UIColor.white.withAlphaComponent(0.85),
        ]
        for line in lines {
            NSAttributedString(string: line.text, attributes: attrs).draw(at: CGPoint(x: line.x, y: line.y))
        }

        for orb in orbs { drawOrb(orb, in: ctx) }
        onStats?(lines.count, elapsed, orbs.count)
    }

    private func spawnOrbs() {
        let w = max(bounds.width, 200)
        let h = max(bounds.height, 300)
        let colors: [(Double, Double, Double)] = [
            (0.2, 0.5, 0.9), (0.9, 0.3, 0.4), (0.3, 0.8, 0.5), (0.8, 0.6, 0.2),
        ]
        orbs = (0..<4).map { i in
            Orb(
                position: CGPoint(x: .random(in: 80...(w - 80)), y: .random(in: 80...(h - 80))),
                velocity: CGPoint(x: .random(in: -35...35), y: .random(in: -35...35)),
                radius: .random(in: 50...70),
                color: colors[i]
            )
        }
    }

    private func stepPhysics() {
        let dt: CGFloat = 1.0 / 60.0
        let rest: CGFloat = 0.9
        let s = bounds.size

        for i in 0..<orbs.count {
            orbs[i].position.x += orbs[i].velocity.x * dt
            orbs[i].position.y += orbs[i].velocity.y * dt
            let r = orbs[i].radius

            if orbs[i].position.x - r < 0 {
                orbs[i].position.x = r
                orbs[i].velocity.x = abs(orbs[i].velocity.x) * rest
            }
            if orbs[i].position.x + r > s.width {
                orbs[i].position.x = s.width - r
                orbs[i].velocity.x = -abs(orbs[i].velocity.x) * rest
            }
            if orbs[i].position.y - r < 0 {
                orbs[i].position.y = r
                orbs[i].velocity.y = abs(orbs[i].velocity.y) * rest
            }
            if orbs[i].position.y + r > s.height {
                orbs[i].position.y = s.height - r
                orbs[i].velocity.y = -abs(orbs[i].velocity.y) * rest
            }

            for j in (i + 1)..<orbs.count {
                let dx = orbs[j].position.x - orbs[i].position.x
                let dy = orbs[j].position.y - orbs[i].position.y
                let dist = sqrt(dx * dx + dy * dy)
                let minD = orbs[i].radius + orbs[j].radius
                if dist < minD && dist > 0.01 {
                    let nx = dx / dist, ny = dy / dist, ov = minD - dist
                    orbs[i].position.x -= nx * ov * 0.5
                    orbs[i].position.y -= ny * ov * 0.5
                    orbs[j].position.x += nx * ov * 0.5
                    orbs[j].position.y += ny * ov * 0.5
                    let dvx = orbs[i].velocity.x - orbs[j].velocity.x
                    let dvy = orbs[i].velocity.y - orbs[j].velocity.y
                    let dot = dvx * nx + dvy * ny
                    if dot > 0 {
                        orbs[i].velocity.x -= dot * nx * rest
                        orbs[i].velocity.y -= dot * ny * rest
                        orbs[j].velocity.x += dot * nx * rest
                        orbs[j].velocity.y += dot * ny * rest
                    }
                }
            }
        }
    }

    private func layoutAroundOrbs(prepared: PreparedTextWithSegments, size: CGSize) -> [PositionedLine] {
        var cursor = LayoutCursor.start
        var y: CGFloat = 10
        var result: [PositionedLine] = []
        let fL: CGFloat = 10, fR = size.width - 10, minS: CGFloat = 35, lh = lineHeight

        while y + lh <= size.height {
            var slots = [Slot(left: fL, right: fR)]
            for orb in orbs {
                let er = orb.radius + 12
                guard y + lh > orb.position.y - er && y < orb.position.y + er else { continue }
                var bL = CGFloat.greatestFiniteMagnitude, bR = -CGFloat.greatestFiniteMagnitude
                var sy = y
                while sy <= y + lh {
                    let dy = sy - orb.position.y
                    if abs(dy) < er { let dx = sqrt(er * er - dy * dy); bL = min(bL, orb.position.x - dx); bR = max(bR, orb.position.x + dx) }
                    sy += 2
                }
                guard bL < bR else { continue }
                var ns: [Slot] = []
                for s in slots {
                    if bR <= s.left || bL >= s.right { ns.append(s) } else {
                        if bL > s.left + minS { ns.append(Slot(left: s.left, right: bL)) }
                        if bR < s.right - minS { ns.append(Slot(left: bR, right: s.right)) }
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

    private func drawOrb(_ orb: Orb, in ctx: CGContext) {
        let r = orb.radius
        let c = orb.color
        let cs = CGColorSpaceCreateDeviceRGB()

        let glowC = [UIColor(red: c.0, green: c.1, blue: c.2, alpha: 0.4).cgColor, UIColor.clear.cgColor]
        if let g = CGGradient(colorsSpace: cs, colors: glowC as CFArray, locations: [0, 1]) {
            ctx.drawRadialGradient(g, startCenter: orb.position, startRadius: 0, endCenter: orb.position, endRadius: r * 1.4, options: [])
        }
        let coreC = [UIColor(red: c.0 * 1.1, green: c.1 * 1.1, blue: c.2 * 1.1, alpha: 0.7).cgColor,
                     UIColor(red: c.0 * 0.3, green: c.1 * 0.3, blue: c.2 * 0.3, alpha: 0.15).cgColor]
        if let g = CGGradient(colorsSpace: cs, colors: coreC as CFArray, locations: [0, 1]) {
            ctx.drawRadialGradient(g, startCenter: CGPoint(x: orb.position.x - r * 0.15, y: orb.position.y - r * 0.15),
                                   startRadius: 0, endCenter: orb.position, endRadius: r, options: [])
        }
        // Specular highlight
        let hlC = CGPoint(x: orb.position.x - r * 0.2, y: orb.position.y - r * 0.25)
        let hlColors = [UIColor.white.withAlphaComponent(0.18).cgColor, UIColor.clear.cgColor]
        if let g = CGGradient(colorsSpace: cs, colors: hlColors as CFArray, locations: [0, 1]) {
            ctx.drawRadialGradient(g, startCenter: hlC, startRadius: 0, endCenter: hlC, endRadius: r * 0.45, options: [])
        }
    }
}

// MARK: =========================================================
// MARK: 2. DYNAMIC LAYOUT — Magazine-style article reader
// MARK: =========================================================

/// A realistic magazine article where text flows around:
/// - A draggable hero image (top-left float)
/// - A pull quote box (right side)
/// - A circular author avatar (inline)
///
/// Drag any element and the entire article reflows instantly.
/// This layout is genuinely hard on iOS without PretextKit —
/// TextKit exclusion paths are buggy, CoreText line-by-line is slow.
private struct DynamicDragScene: View {
    @State private var reflowUs: Double = 0
    @State private var lineCount: Int = 0

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                Text(String(format: "%.0f", reflowUs))
                    .font(.system(size: 22, weight: .bold, design: .monospaced))
                    .foregroundStyle(reflowUs < 1000 ? .green : reflowUs < 5000 ? .yellow : .red)
                Text("μs")
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(lineCount) lines · Drag elements")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            .padding(.horizontal).padding(.vertical, 6)
            Divider()

            ArticleCanvasWrapper(onStats: { lines, us in
                lineCount = lines; reflowUs = us
            })
        }
    }
}

private struct ArticleCanvasWrapper: UIViewRepresentable {
    let onStats: @MainActor (Int, Double) -> Void
    func makeUIView(context: Context) -> ArticleRenderView {
        let v = ArticleRenderView(); v.onStats = onStats; return v
    }
    func updateUIView(_ v: ArticleRenderView, context: Context) {}
}

/// A floating obstacle on the page (image, pull quote, avatar).
private struct FloatingElement {
    var frame: CGRect
    let cornerRadius: CGFloat
    let color: UIColor
    let label: String
    let fontSize: CGFloat
    let isCircle: Bool
    let padding: CGFloat
}

final class ArticleRenderView: UIView {
    var onStats: (@MainActor (Int, Double) -> Void)?
    private var prepared: PreparedTextWithSegments?
    private var lines: [PositionedLine] = []
    private var dragIndex: Int? = nil
    private var dragOffset: CGPoint = .zero

    private let bodyFont = CTFontCreateWithName("Georgia" as CFString, 15, nil)
    private let lineHeight: CGFloat = 22
    private let margin: CGFloat = 16

    // Floating elements the user can drag
    private var elements: [FloatingElement] = []

    private static let articleText = """
    Building dynamic text layouts on iOS has always been one of the hardest challenges in mobile development. Unlike the web, where CSS float and exclusion properties handle text wrapping natively, iOS developers have historically been forced to choose between TextKit's buggy exclusion paths or manual CoreText line breaking — both expensive, both fragile. PretextKit changes this equation entirely. By precomputing segment widths once and performing pure arithmetic reflow, it enables the kind of fluid, magazine-quality text layouts that were previously impractical in production apps. Consider this article you are reading right now. The text flows around a floating image, wraps beside a pull quote, and routes around an author avatar — all computed in under a millisecond. Drag any element and watch every line recompute instantly. On a traditional iOS stack, this layout would require either a full TextKit setup with NSTextContainer exclusion paths — which frequently breaks on rotation and has known viewport estimation bugs in TextKit 2 — or a manual CTTypesetter loop that reshapes every glyph on every frame. Both approaches cost 5-20ms per reflow. PretextKit does it in microseconds because the expensive font shaping was already done during prepare(). The layout() call simply walks cached Float arrays with basic arithmetic. No font engine, no glyph lookup, no attributed string creation. This is not a marginal improvement. It is a categorical change in what is possible. Instagram, Telegram, and Twitter all built custom text engines for exactly this reason. PretextKit brings that same capability to any iOS app as a simple Swift package. The API is intentionally minimal: prepare() once when text arrives, layout() on every resize or reflow. For advanced use cases like this article, layoutNextLine() gives you one line at a time with a different maxWidth each call — the building block for any obstacle-aware text flow.
    """

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor(red: 0.98, green: 0.97, blue: 0.95, alpha: 1) // Warm paper
        prepared = PretextKit.prepareWithSegments(Self.articleText, font: FontDescriptor(bodyFont))

        elements = [
            // Floating image (top-left)
            FloatingElement(
                frame: CGRect(x: 16, y: 16, width: 130, height: 100),
                cornerRadius: 10, color: UIColor(red: 0.85, green: 0.75, blue: 0.6, alpha: 1),
                label: "📸 Photo", fontSize: 14, isCircle: false, padding: 12
            ),
            // Pull quote (right side, mid-page)
            FloatingElement(
                frame: CGRect(x: 210, y: 240, width: 160, height: 90),
                cornerRadius: 8, color: UIColor(red: 0.93, green: 0.9, blue: 0.85, alpha: 1),
                label: "❝ Pull Quote", fontSize: 12, isCircle: false, padding: 10
            ),
            // Author avatar (left, lower)
            FloatingElement(
                frame: CGRect(x: 20, y: 430, width: 70, height: 70),
                cornerRadius: 35, color: UIColor(red: 0.58, green: 0.38, blue: 0.24, alpha: 1),
                label: "👤", fontSize: 24, isCircle: true, padding: 10
            ),
        ]
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: Touch handling — drag floating elements

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let loc = touches.first?.location(in: self) else { return }
        // Find which element was touched (reverse order for z-order)
        for i in stride(from: elements.count - 1, through: 0, by: -1) {
            let el = elements[i]
            let hitFrame = el.frame.insetBy(dx: -10, dy: -10)
            if hitFrame.contains(loc) {
                dragIndex = i
                dragOffset = CGPoint(x: loc.x - el.frame.origin.x, y: loc.y - el.frame.origin.y)
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

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        dragIndex = nil
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        dragIndex = nil
    }

    // MARK: Draw

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext(), let prepared else { return }

        let start = CFAbsoluteTimeGetCurrent()
        lines = layoutArticle(prepared: prepared, size: bounds.size)
        let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1_000_000

        // Draw text
        let attrs: [NSAttributedString.Key: Any] = [
            .font: bodyFont as UIFont,
            .foregroundColor: UIColor(red: 0.15, green: 0.12, blue: 0.1, alpha: 1),
        ]
        for line in lines {
            NSAttributedString(string: line.text, attributes: attrs).draw(at: CGPoint(x: line.x, y: line.y))
        }

        // Draw floating elements
        for el in elements {
            drawElement(el, in: ctx)
        }

        onStats?(lines.count, elapsed)
    }

    private func drawElement(_ el: FloatingElement, in ctx: CGContext) {
        let path: CGPath
        if el.isCircle {
            path = CGPath(ellipseIn: el.frame, transform: nil)
        } else {
            path = CGPath(roundedRect: el.frame, cornerWidth: el.cornerRadius, cornerHeight: el.cornerRadius, transform: nil)
        }

        // Shadow
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: 2), blur: 8, color: UIColor.black.withAlphaComponent(0.15).cgColor)
        ctx.setFillColor(el.color.cgColor)
        ctx.addPath(path)
        ctx.fillPath()
        ctx.restoreGState()

        // Border
        ctx.setStrokeColor(UIColor.black.withAlphaComponent(0.08).cgColor)
        ctx.setLineWidth(0.5)
        ctx.addPath(path)
        ctx.strokePath()

        // Label
        let labelAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: el.fontSize, weight: .medium),
            .foregroundColor: UIColor(red: 0.3, green: 0.25, blue: 0.2, alpha: 0.8),
        ]
        let labelStr = NSAttributedString(string: el.label, attributes: labelAttrs)
        let labelSize = labelStr.size()
        let labelX = el.frame.midX - labelSize.width / 2
        let labelY = el.frame.midY - labelSize.height / 2
        labelStr.draw(at: CGPoint(x: labelX, y: labelY))
    }

    // MARK: Layout — text flows around all floating elements

    private func layoutArticle(prepared: PreparedTextWithSegments, size: CGSize) -> [PositionedLine] {
        var cursor = LayoutCursor.start
        var y: CGFloat = margin
        var result: [PositionedLine] = []
        let fL = margin, fR = size.width - margin
        let minS: CGFloat = 40
        let lh = lineHeight

        while y + lh <= size.height - margin {
            // Start with full width
            var slots = [Slot(left: fL, right: fR)]

            // Subtract each floating element from the available slots
            for el in elements {
                let elRect = el.frame.insetBy(dx: -el.padding, dy: -el.padding)
                guard y + lh > elRect.minY && y < elRect.maxY else { continue }

                // For circles, compute actual x-extent at this y
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

// MARK: - Shared types

struct Orb {
    var position: CGPoint
    var velocity: CGPoint
    var radius: CGFloat
    var color: (r: Double, g: Double, b: Double)
}
