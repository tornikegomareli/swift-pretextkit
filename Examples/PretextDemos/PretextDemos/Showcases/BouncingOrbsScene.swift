import SwiftUI
import UIKit
import CoreText
import CoreGraphics
import PretextKit

struct BouncingOrbsScene: View {
    @State private var reflowUs: Double = 0
    @State private var lineCount: Int = 0
    @State private var orbCount: Int = 4

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                Text(String(format: "%.0f", reflowUs))
                    .font(.system(size: isPad ? 28 : 22, weight: .bold, design: .monospaced))
                    .foregroundStyle(reflowUs < 2000 ? .green : reflowUs < 8000 ? .yellow : .red)
                Text("μs")
                    .font(.system(size: isPad ? 16 : 13, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.4))
                Spacer()
                Text("\(orbCount) orbs · \(lineCount) lines · Tap to add")
                    .font(isPad ? .caption : .caption2)
                    .foregroundStyle(.white.opacity(0.25))
            }
            .padding(.horizontal).padding(.vertical, isPad ? 10 : 6).background(.black)
            Divider()

            OrbCanvasWrapper(onStats: { lines, us, orbs in
                lineCount = lines; reflowUs = us; orbCount = orbs
            })
        }
    }
}

struct OrbCanvasWrapper: UIViewRepresentable {
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

    private let textFont: CTFont
    private let lineHeight: CGFloat

    private static let bodyText = """
    Text becomes a first-class participant in the visual composition — not a static block, but a fluid material that adapts in real time. The performance improvement is not incremental — it is categorical. Zero reflows versus five hundred. The web renders text through a pipeline designed thirty years ago for static documents. A browser loads a font, shapes the text into glyphs, measures their width, determines where lines break, and positions each line vertically. Every step depends on the previous one. Every step requires the rendering engine to consult its internal layout tree — a structure so expensive to maintain that browsers guard access behind synchronous reflow barriers. But the web is no longer a collection of static documents. It is a platform for applications. A messaging application needs exact heights. A masonry layout needs card heights. An editorial page needs text to flow around obstacles. A responsive dashboard needs real-time reflow. Every operation requires text measurement. The cost is devastating. Measuring five hundred text blocks triggers five hundred full layout passes. PretextKit solves this. Prepare once. Reflow infinitely. Pure arithmetic. Zero allocations. Sub-microsecond per text block. The future of text layout is not faster engines — it is no engine at all in the hot path.
    """

    private static let iPadExtraText = """
     The architecture is simple but the consequences are profound. Traditional text engines couple measurement and layout into a single pass — you cannot know where lines break without shaping every glyph, and you cannot shape glyphs without consulting the font engine. PretextKit breaks this coupling. The prepare() phase walks the text once, segments it into words and break opportunities using the system's word segmenter, measures each segment via CoreText, and caches the widths in flat Float arrays. From that point forward, layout() is pure arithmetic: walk the cached widths, accumulate until overflow, break, repeat. No font engine. No glyph shaping. No attributed string allocation. The numbers speak for themselves: on an M1 iPad Pro, layout() processes 10,000 text blocks in under 2 milliseconds. That is not a typo. Ten thousand paragraphs reflowed in the time it takes UILabel to measure three. This changes what is architecturally possible. You can reflow on every frame of a 120Hz ProMotion display. You can predict exact heights for every cell in a collection view without a single layout pass. You can flow text around moving obstacles at 60fps with microsecond reflow latency. You can build editorial layouts that respond to finger position in real time. The prepare-once-reflow-infinitely model means that device rotation, split view changes, and Dynamic Type adjustments all cost essentially nothing after the initial measurement. International text is a first-class citizen: CJK text breaks per-character with kinsoku rules, Arabic flows right-to-left, Thai uses dictionary-based segmentation, emoji ZWJ sequences stay intact, and mixed-script paragraphs just work.
    """

    override init(frame: CGRect) {
        if isPad {
            textFont = CTFontCreateWithName("Georgia" as CFString, 17, nil)
            lineHeight = 23
        } else {
            textFont = CTFontCreateWithName("Georgia" as CFString, 13, nil)
            lineHeight = 17
        }
        super.init(frame: frame)
        backgroundColor = .black
        let fullText = isPad ? Self.bodyText + Self.iPadExtraText : Self.bodyText
        prepared = PretextKit.prepareWithSegments(fullText, font: FontDescriptor(textFont))
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
        let r: ClosedRange<CGFloat> = isPad ? 60...90 : 40...60
        let v: ClosedRange<CGFloat> = isPad ? -50...50 : -40...40
        orbs.append(Orb(
            position: loc,
            velocity: CGPoint(x: .random(in: v), y: .random(in: v)),
            radius: .random(in: r),
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
            (0.6, 0.3, 0.8), (0.9, 0.5, 0.7), (0.4, 0.7, 0.8), (0.9, 0.4, 0.6),
        ]

        let count = isPad ? 8 : 4
        let radiusRange: ClosedRange<CGFloat> = isPad ? 60...100 : 50...70
        let velRange: ClosedRange<CGFloat> = isPad ? -45...45 : -35...35

        orbs = (0..<count).map { i in
            Orb(
                position: CGPoint(x: .random(in: 100...(w - 100)), y: .random(in: 100...(h - 100))),
                velocity: CGPoint(x: .random(in: velRange), y: .random(in: velRange)),
                radius: .random(in: radiusRange),
                color: colors[i % colors.count]
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
        let pad: CGFloat = isPad ? 16 : 10
        var y: CGFloat = pad
        var result: [PositionedLine] = []
        let fL = pad, fR = size.width - pad, minS: CGFloat = isPad ? 50 : 35, lh = lineHeight

        while y + lh <= size.height {
            var slots = [Slot(left: fL, right: fR)]
            for orb in orbs {
                let er = orb.radius + (isPad ? 16 : 12)
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
        let hlC = CGPoint(x: orb.position.x - r * 0.2, y: orb.position.y - r * 0.25)
        let hlColors = [UIColor.white.withAlphaComponent(0.18).cgColor, UIColor.clear.cgColor]
        if let g = CGGradient(colorsSpace: cs, colors: hlColors as CFArray, locations: [0, 1]) {
            ctx.drawRadialGradient(g, startCenter: hlC, startRadius: 0, endCenter: hlC, endRadius: r * 0.45, options: [])
        }
    }
}
