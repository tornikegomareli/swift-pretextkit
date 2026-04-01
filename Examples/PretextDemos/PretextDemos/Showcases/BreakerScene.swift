import SwiftUI
import UIKit
import CoreText
import CoreGraphics
import PretextKit

struct BreakerScene: View {
    var body: some View {
        BreakerWrapper().ignoresSafeArea(edges: .bottom)
    }
}

private struct BreakerWrapper: UIViewRepresentable {
    func makeUIView(context: Context) -> BreakerView { BreakerView() }
    func updateUIView(_ v: BreakerView, context: Context) {}
}

private struct WordBrick {
    var rect: CGRect
    let text: String
    let color: UIColor
    var alive: Bool
    let points: Int
}

/// Breakout where the entire screen is filled with flowing text.
/// Ball, paddle, and word-bricks are all obstacles that text reflows
/// around every frame using `layoutNextLine()`.
final class BreakerView: UIView {
    private var displayLink: CADisplayLink?
    private var prepared: PreparedTextWithSegments?
    private var lines: [PositionedLine] = []

    private var bricks: [WordBrick] = []
    private var ballPos: CGPoint = .zero
    private var ballVel: CGPoint = .zero
    private let ballRadius: CGFloat = isPad ? 8 : 6
    private var paddleX: CGFloat = 0
    private let paddleW: CGFloat = isPad ? 160 : 110
    private let paddleH: CGFloat = isPad ? 16 : 12
    private var paddleY: CGFloat = 0
    private var score: Int = 0
    private var lives: Int = 3
    private var launched: Bool = false
    private var gameOver: Bool = false

    private let textFont = CTFontCreateWithName("Georgia" as CFString, isPad ? 13 : 11, nil)
    private let lineHeight: CGFloat = isPad ? 17 : 14
    private let brickFontUI = UIFont(name: "Menlo-Bold", size: isPad ? 12 : 10)!
    private let brickH: CGFloat = isPad ? 24 : 20
    private let topMargin: CGFloat = isPad ? 28 : 20

    private static let targetWords = [
        "prepare", "layout", "measure", "segment", "reflow",
        "glyph", "cursor", "inline", "stream", "cache",
        "width", "break", "render", "offset", "font",
    ]

    private let brickColors: [UIColor] = [
        UIColor(red: 0.9, green: 0.35, blue: 0.3, alpha: 1),
        UIColor(red: 0.9, green: 0.55, blue: 0.2, alpha: 1),
        UIColor(red: 0.85, green: 0.75, blue: 0.2, alpha: 1),
        UIColor(red: 0.3, green: 0.75, blue: 0.4, alpha: 1),
        UIColor(red: 0.3, green: 0.6, blue: 0.85, alpha: 1),
    ]

    private static let bgText = """
    pretext layout measure cursor segment wrap glyph inline reflow stream bidi kern space split signal static dynamic vector module bounce trail track render flow text snakes between every obstacle and keeps every word alive while the field recomposes around the moving ball and the waiting paddle small copy fills the arena from border to border and the larger block labels stay readable as targets floating above the paragraph wall pretext layout measure cursor segment wrap glyph inline reflow stream bidi kern space split signal static dynamic vector module bounce trail track render flow text snakes between every obstacle and keeps every word alive while the field recomposes around the moving ball and the waiting paddle small copy fills the arena from border to border and the larger block labels stay readable as targets floating above the paragraph wall pretext layout measure cursor segment wrap glyph inline reflow stream bidi kern space split signal static dynamic vector module bounce trail track render flow text snakes between every obstacle and keeps every word alive while the field recomposes around the moving ball and the waiting paddle small copy fills the arena from border to border and the larger block labels stay readable as targets floating above the paragraph wall pretext layout measure cursor segment wrap glyph inline reflow stream bidi kern space split signal static dynamic vector module bounce trail track render flow text snakes between every obstacle and keeps every word alive while the field recomposes around the moving ball and the waiting paddle small copy fills the arena from border to border and the larger block labels stay readable as targets floating above the paragraph wall
    """

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor(red: 0.06, green: 0.07, blue: 0.10, alpha: 1)
        prepared = PretextKit.prepareWithSegments(Self.bgText, font: FontDescriptor(textFont))
    }
    required init?(coder: NSCoder) { fatalError() }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil {
            displayLink = CADisplayLink(target: self, selector: #selector(tick))
            displayLink?.add(to: .main, forMode: .common)
        } else { displayLink?.invalidate(); displayLink = nil }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if bricks.isEmpty { resetGame() }
    }

    private func resetGame() {
        let w = bounds.width
        score = 0; lives = 3; gameOver = false; launched = false
        let bottomInset = safeAreaInsets.bottom
        paddleY = bounds.height - bottomInset - (isPad ? 70 : 50)
        paddleX = w / 2

        bricks = []
        var words = Self.targetWords.shuffled()
        var y = topMargin
        let margin: CGFloat = isPad ? 16 : 8
        let maxRows = isPad ? 5 : 4

        for row in 0..<maxRows {
            var x = margin
            let rowColor = brickColors[row % brickColors.count]
            let rowPoints = (maxRows - row) * 10

            while x < w - margin && !words.isEmpty {
                let word = words.first!
                let wordW = ceil(NSAttributedString(string: word, attributes: [.font: brickFontUI]).size().width) + (isPad ? 16 : 12)
                if x + wordW + margin > w { break }

                bricks.append(WordBrick(
                    rect: CGRect(x: x, y: y, width: wordW, height: brickH),
                    text: word, color: rowColor, alive: true, points: rowPoints
                ))
                x += wordW + 3
                words.removeFirst()
                if words.isEmpty { words = Self.targetWords.shuffled() }
            }
            y += brickH + 3
        }

        ballPos = CGPoint(x: paddleX, y: paddleY - ballRadius - 2)
        ballVel = .zero
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let loc = touches.first?.location(in: self) else { return }
        if gameOver { resetGame(); return }
        if !launched {
            launched = true
            let speed: CGFloat = isPad ? 300 : 240
            let angle = CGFloat.random(in: -0.3...0.3)
            ballVel = CGPoint(x: sin(angle) * speed, y: -cos(angle) * speed)
        }
        paddleX = max(paddleW / 2, min(bounds.width - paddleW / 2, loc.x))
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let loc = touches.first?.location(in: self) else { return }
        paddleX = max(paddleW / 2, min(bounds.width - paddleW / 2, loc.x))
        if !launched { ballPos.x = paddleX }
    }

    @objc private func tick(_ link: CADisplayLink) {
        if launched && !gameOver { stepPhysics() }
        setNeedsDisplay()
    }

    private func stepPhysics() {
        let dt: CGFloat = 1.0 / 60.0
        let w = bounds.width, h = bounds.height

        ballPos.x += ballVel.x * dt
        ballPos.y += ballVel.y * dt

        if ballPos.x - ballRadius < 0 { ballPos.x = ballRadius; ballVel.x = abs(ballVel.x) }
        if ballPos.x + ballRadius > w { ballPos.x = w - ballRadius; ballVel.x = -abs(ballVel.x) }
        if ballPos.y - ballRadius < 0 { ballPos.y = ballRadius; ballVel.y = abs(ballVel.y) }

        if ballPos.y > h + 20 {
            lives -= 1; launched = false
            if lives <= 0 { gameOver = true }
            ballPos = CGPoint(x: paddleX, y: paddleY - ballRadius - 2)
            ballVel = .zero
        }

        let pRect = CGRect(x: paddleX - paddleW / 2, y: paddleY, width: paddleW, height: paddleH)
        if ballVel.y > 0 && ballPos.y + ballRadius >= pRect.minY && ballPos.y + ballRadius <= pRect.maxY + 8
            && ballPos.x >= pRect.minX - ballRadius && ballPos.x <= pRect.maxX + ballRadius {
            let hitRatio = (ballPos.x - paddleX) / (paddleW / 2)
            let speed = sqrt(ballVel.x * ballVel.x + ballVel.y * ballVel.y)
            ballVel.x = sin(hitRatio * 1.1) * speed
            ballVel.y = -cos(hitRatio * 1.1) * speed
            ballPos.y = pRect.minY - ballRadius - 1
        }

        for i in 0..<bricks.count {
            guard bricks[i].alive else { continue }
            let br = bricks[i].rect.insetBy(dx: -ballRadius, dy: -ballRadius)
            guard br.contains(ballPos) else { continue }
            bricks[i].alive = false
            score += bricks[i].points
            let dx1 = abs(ballPos.x - bricks[i].rect.minX)
            let dx2 = abs(ballPos.x - bricks[i].rect.maxX)
            let dy1 = abs(ballPos.y - bricks[i].rect.minY)
            let dy2 = abs(ballPos.y - bricks[i].rect.maxY)
            if min(dy1, dy2) <= min(dx1, dx2) { ballVel.y = -ballVel.y } else { ballVel.x = -ballVel.x }
            break
        }

        if bricks.allSatisfy({ !$0.alive }) { gameOver = true }
    }

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext(), let prepared else { return }
        let size = bounds.size
        let lh = lineHeight
        let pad: CGFloat = 6
        let minS: CGFloat = isPad ? 40 : 25

        var obstacles: [(rect: CGRect, isCircle: Bool)] = []
        for b in bricks where b.alive {
            obstacles.append((b.rect.insetBy(dx: -4, dy: -2), false))
        }
        obstacles.append((CGRect(x: ballPos.x - ballRadius * 2.5, y: ballPos.y - ballRadius * 2.5,
                                  width: ballRadius * 5, height: ballRadius * 5), true))
        let pRect = CGRect(x: paddleX - paddleW / 2 - 4, y: paddleY - 2, width: paddleW + 8, height: paddleH + 4)
        obstacles.append((pRect, false))

        var cursor = LayoutCursor.start
        var y: CGFloat = pad
        lines = []

        while y + lh <= size.height {
            var slots = [Slot(left: pad, right: size.width - pad)]

            for obs in obstacles {
                let oRect = obs.rect
                guard y + lh > oRect.minY && y < oRect.maxY else { continue }

                let bL: CGFloat, bR: CGFloat
                if obs.isCircle {
                    let cx = oRect.midX, cy = oRect.midY, r = oRect.width / 2
                    var lo = CGFloat.greatestFiniteMagnitude, hi = -CGFloat.greatestFiniteMagnitude
                    var sy = y; while sy <= y + lh {
                        let dy = sy - cy
                        if abs(dy) < r { let dx = sqrt(r * r - dy * dy); lo = min(lo, cx - dx); hi = max(hi, cx + dx) }
                        sy += 2
                    }
                    guard lo < hi else { continue }
                    bL = lo; bR = hi
                } else {
                    bL = oRect.minX; bR = oRect.maxX
                }

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
                guard let line = PretextKit.layoutNextLine(prepared, start: cursor, maxWidth: slot.right - slot.left) else {
                    cursor = .start; break
                }
                lines.append(PositionedLine(text: line.text, x: slot.left, y: y, width: line.width))
                cursor = line.end
            }
            y += lh
        }

        let textAttrs: [NSAttributedString.Key: Any] = [
            .font: textFont as UIFont,
            .foregroundColor: UIColor(white: 0.30, alpha: 1),
        ]
        for line in lines {
            NSAttributedString(string: line.text, attributes: textAttrs).draw(at: CGPoint(x: line.x, y: line.y))
        }

        for brick in bricks where brick.alive {
            let r = brick.rect
            ctx.setFillColor(brick.color.withAlphaComponent(0.9).cgColor)
            ctx.addPath(CGPath(roundedRect: r, cornerWidth: 4, cornerHeight: 4, transform: nil))
            ctx.fillPath()
            ctx.setStrokeColor(brick.color.cgColor)
            ctx.setLineWidth(1)
            ctx.addPath(CGPath(roundedRect: r, cornerWidth: 4, cornerHeight: 4, transform: nil))
            ctx.strokePath()

            let ta: [NSAttributedString.Key: Any] = [.font: brickFontUI, .foregroundColor: UIColor.white]
            let ts = NSAttributedString(string: brick.text, attributes: ta)
            let tsz = ts.size()
            ts.draw(at: CGPoint(x: r.midX - tsz.width / 2, y: r.midY - tsz.height / 2))
        }

        let paddleRect = CGRect(x: paddleX - paddleW / 2, y: paddleY, width: paddleW, height: paddleH)
        ctx.setFillColor(UIColor(red: 0.3, green: 0.85, blue: 0.7, alpha: 1).cgColor)
        ctx.addPath(CGPath(roundedRect: paddleRect, cornerWidth: paddleH / 2, cornerHeight: paddleH / 2, transform: nil))
        ctx.fillPath()

        let cs = CGColorSpaceCreateDeviceRGB()
        let gc = [UIColor(red: 1, green: 0.9, blue: 0.5, alpha: 0.5).cgColor, UIColor.clear.cgColor]
        if let g = CGGradient(colorsSpace: cs, colors: gc as CFArray, locations: [0, 1]) {
            ctx.drawRadialGradient(g, startCenter: ballPos, startRadius: 0, endCenter: ballPos, endRadius: ballRadius * 3.5, options: [])
        }
        ctx.setFillColor(UIColor(red: 1, green: 0.95, blue: 0.6, alpha: 1).cgColor)
        ctx.fillEllipse(in: CGRect(x: ballPos.x - ballRadius, y: ballPos.y - ballRadius,
                                    width: ballRadius * 2, height: ballRadius * 2))

        let hudAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont(name: "Menlo-Bold", size: isPad ? 13 : 10)!,
            .foregroundColor: UIColor(red: 0.3, green: 0.85, blue: 0.7, alpha: 0.7),
        ]
        let scoreStr = String(format: "SCORE %04d  %@", score, String(repeating: "♥", count: max(lives, 0)))
        NSAttributedString(string: scoreStr, attributes: hudAttrs).draw(at: CGPoint(x: pad, y: size.height - (isPad ? 24 : 18)))

        if !launched && !gameOver {
            drawCentered("TAP TO LAUNCH", size: isPad ? 18 : 14, color: UIColor(white: 0.5, alpha: 0.8), y: size.height / 2)
        }
        if gameOver {
            let won = bricks.allSatisfy { !$0.alive }
            drawCentered(won ? "YOU WIN!" : "GAME OVER", size: isPad ? 32 : 22,
                        color: won ? UIColor(red: 0.3, green: 0.9, blue: 0.5, alpha: 1) : UIColor(red: 0.9, green: 0.3, blue: 0.3, alpha: 1),
                        y: size.height / 2 - 16)
            drawCentered("TAP TO RESTART", size: isPad ? 14 : 11, color: UIColor(white: 0.5, alpha: 0.8), y: size.height / 2 + 20)
        }
    }

    private func drawCentered(_ text: String, size: CGFloat, color: UIColor, y: CGFloat) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont(name: "Menlo-Bold", size: size)!,
            .foregroundColor: color,
        ]
        let s = NSAttributedString(string: text, attributes: attrs)
        s.draw(at: CGPoint(x: bounds.width / 2 - s.size().width / 2, y: y))
    }
}
