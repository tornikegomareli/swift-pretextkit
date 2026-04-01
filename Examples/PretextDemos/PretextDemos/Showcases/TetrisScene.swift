import SwiftUI
import UIKit
import CoreText
import CoreGraphics
import PretextKit

struct TetrisScene: View {
    var body: some View {
        TetrisWrapper().ignoresSafeArea(edges: .bottom)
    }
}

private struct TetrisWrapper: UIViewRepresentable {
    func makeUIView(context: Context) -> TetrisView { TetrisView() }
    func updateUIView(_ v: TetrisView, context: Context) {}
}

// MARK: - Tetromino definitions

private enum TetrominoShape: Int, CaseIterable {
    case I = 0, O, T, S, Z, L, J

    var cells: [(Int, Int)] {
        switch self {
        case .I: return [(0,0),(1,0),(2,0),(3,0)]
        case .O: return [(0,0),(1,0),(0,1),(1,1)]
        case .T: return [(0,0),(1,0),(2,0),(1,1)]
        case .S: return [(1,0),(2,0),(0,1),(1,1)]
        case .Z: return [(0,0),(1,0),(1,1),(2,1)]
        case .L: return [(0,0),(1,0),(2,0),(2,1)]
        case .J: return [(0,0),(1,0),(2,0),(0,1)]
        }
    }

    var color: UIColor {
        switch self {
        case .I: return UIColor(red: 0.3, green: 0.85, blue: 0.9, alpha: 1)
        case .O: return UIColor(red: 0.9, green: 0.85, blue: 0.3, alpha: 1)
        case .T: return UIColor(red: 0.7, green: 0.3, blue: 0.8, alpha: 1)
        case .S: return UIColor(red: 0.3, green: 0.8, blue: 0.4, alpha: 1)
        case .Z: return UIColor(red: 0.9, green: 0.35, blue: 0.3, alpha: 1)
        case .L: return UIColor(red: 0.9, green: 0.6, blue: 0.2, alpha: 1)
        case .J: return UIColor(red: 0.3, green: 0.5, blue: 0.9, alpha: 1)
        }
    }
}

private struct Tetromino {
    var shape: TetrominoShape
    var cells: [(Int, Int)]
    var col: Int
    var row: Int

    init(shape: TetrominoShape, col: Int) {
        self.shape = shape
        self.cells = shape.cells
        self.col = col
        self.row = 0
    }

    func rotated() -> [(Int, Int)] {
        cells.map { (-$0.1, $0.0) }
    }

    func worldCells() -> [(col: Int, row: Int)] {
        cells.map { (col + $0.0, row + $0.1) }
    }
}

// MARK: - Tetris View

final class TetrisView: UIView {
    private var displayLink: CADisplayLink?
    private var prepared: PreparedTextWithSegments?
    private var textLines: [PositionedLine] = []

    private let cols = 10
    private let rows = 20
    private var grid: [[TetrominoShape?]] = []
    private var cellSize: CGFloat = 0
    private var gridOrigin: CGPoint = .zero

    private var current: Tetromino?
    private var score: Int = 0
    private var linesCleared: Int = 0
    private var gameOver: Bool = false
    private var dropTimer: CFTimeInterval = 0
    private var dropInterval: CFTimeInterval = 0.6
    private var lastTime: CFTimeInterval = 0

    /// Smooth vertical offset: 0.0 = just dropped, progresses to 1.0 = ready for next row
    private var smoothProgress: CGFloat = 0

    private var touchStart: CGPoint = .zero
    private var touchStartTime: CFTimeInterval = 0
    private var didSwipe = false

    private let textFont = CTFontCreateWithName("Georgia" as CFString, isPad ? 12 : 10, nil)
    private let lineHeight: CGFloat = isPad ? 16 : 13

    private static let bgText = """
    tetris blocks fall through text while every line reflows around them in real time the grid the pieces and the placed blocks are all obstacles that text wraps around using layoutNextLine at sixty frames per second pretext layout measure cursor segment wrap glyph inline reflow stream the field recomposes every frame as pieces descend rotate and lock into place each cleared line removes obstacles and text rushes in to fill the gap pure arithmetic zero allocations sub microsecond per text block tetris blocks fall through text while every line reflows around them in real time the grid the pieces and the placed blocks are all obstacles that text wraps around using layoutNextLine at sixty frames per second pretext layout measure cursor segment wrap glyph inline reflow stream the field recomposes every frame as pieces descend rotate and lock into place each cleared line removes obstacles and text rushes in to fill the gap pure arithmetic zero allocations sub microsecond per text block tetris blocks fall through text while every line reflows around them in real time the grid the pieces and the placed blocks are all obstacles pretext layout measure cursor segment wrap glyph inline reflow stream the field recomposes every frame pure arithmetic zero allocations sub microsecond per text block
    """

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor(red: 0.06, green: 0.07, blue: 0.10, alpha: 1)
        prepared = PretextKit.prepareWithSegments(Self.bgText, font: FontDescriptor(textFont))
        grid = Array(repeating: Array(repeating: nil, count: cols), count: rows)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil {
            displayLink = CADisplayLink(target: self, selector: #selector(tick))
            displayLink?.add(to: .main, forMode: .common)
            lastTime = CACurrentMediaTime()
        } else { displayLink?.invalidate(); displayLink = nil }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let bottomInset = safeAreaInsets.bottom
        let usableH = bounds.height - bottomInset
        let maxCellH = (usableH - (isPad ? 80 : 50)) / CGFloat(rows)
        let maxCellW = (bounds.width * 0.5) / CGFloat(cols)
        cellSize = min(maxCellH, maxCellW).rounded(.down)
        let gridW = cellSize * CGFloat(cols)
        let gridH = cellSize * CGFloat(rows)
        gridOrigin = CGPoint(x: (bounds.width - gridW) / 2, y: (usableH - gridH) / 2)
        if current == nil && !gameOver { spawnPiece() }
    }

    // MARK: Touch

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let loc = touches.first?.location(in: self) else { return }
        if gameOver { resetGame(); return }
        touchStart = loc
        touchStartTime = CACurrentMediaTime()
        didSwipe = false
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let loc = touches.first?.location(in: self) else { return }
        let dx = loc.x - touchStart.x
        let dy = loc.y - touchStart.y
        let threshold: CGFloat = cellSize * 0.7

        if !didSwipe && abs(dx) > threshold && abs(dx) > abs(dy) {
            move(dx: dx > 0 ? 1 : -1)
            touchStart = loc
            didSwipe = true
        } else if !didSwipe && dy > threshold {
            hardDrop()
            didSwipe = true
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        if !didSwipe && CACurrentMediaTime() - touchStartTime < 0.3 {
            rotatePiece()
        }
    }

    // MARK: Game logic

    private func resetGame() {
        grid = Array(repeating: Array(repeating: nil, count: cols), count: rows)
        score = 0; linesCleared = 0; gameOver = false
        dropInterval = 0.6; smoothProgress = 0
        spawnPiece()
    }

    private func spawnPiece() {
        let shape = TetrominoShape.allCases.randomElement()!
        current = Tetromino(shape: shape, col: cols / 2 - 1)
        smoothProgress = 0
        if !isValid(current!) { gameOver = true; current = nil }
    }

    private func isValid(_ piece: Tetromino) -> Bool {
        for c in piece.worldCells() {
            if c.col < 0 || c.col >= cols || c.row < 0 || c.row >= rows { return false }
            if grid[c.row][c.col] != nil { return false }
        }
        return true
    }

    private func move(dx: Int) {
        guard var p = current else { return }
        p.col += dx
        if isValid(p) { current = p }
    }

    private func rotatePiece() {
        guard var p = current else { return }
        let rotated = p.rotated()
        let old = p.cells
        p.cells = rotated
        if isValid(p) { current = p; return }
        for kick in [-1, 1, -2, 2] {
            p.col += kick
            if isValid(p) { current = p; return }
            p.col -= kick
        }
        p.cells = old
    }

    private func moveDown() -> Bool {
        guard var p = current else { return false }
        p.row += 1
        if isValid(p) { current = p; smoothProgress = 0; return true }
        return false
    }

    private func hardDrop() {
        while moveDown() {}
        lockPiece()
    }

    private func lockPiece() {
        guard let p = current else { return }
        for c in p.worldCells() {
            if c.row >= 0 && c.row < rows && c.col >= 0 && c.col < cols {
                grid[c.row][c.col] = p.shape
            }
        }
        clearLines()
        spawnPiece()
    }

    private func clearLines() {
        var cleared = 0
        for r in stride(from: rows - 1, through: 0, by: -1) {
            if grid[r].allSatisfy({ $0 != nil }) {
                grid.remove(at: r)
                grid.insert(Array(repeating: nil, count: cols), at: 0)
                cleared += 1
            }
        }
        if cleared > 0 {
            linesCleared += cleared
            score += [0, 100, 300, 500, 800][min(cleared, 4)]
            dropInterval = max(0.15, 0.6 - Double(linesCleared / 10) * 0.05)
        }
    }

    // MARK: Game loop

    @objc private func tick(_ link: CADisplayLink) {
        let now = CACurrentMediaTime()
        let dt = now - lastTime
        lastTime = now

        if !gameOver && current != nil {
            dropTimer += dt
            // Smooth progress: piece visually slides toward next row
            smoothProgress = min(CGFloat(dropTimer / dropInterval), 1.0)

            if dropTimer >= dropInterval {
                dropTimer = 0
                smoothProgress = 0
                if !moveDown() { lockPiece() }
            }
        }
        setNeedsDisplay()
    }

    // MARK: Draw

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext(), let prepared else { return }
        let size = bounds.size
        let lh = lineHeight
        let pad: CGFloat = 4
        let minS: CGFloat = isPad ? 30 : 20

        let gx = gridOrigin.x, gy = gridOrigin.y
        let gw = cellSize * CGFloat(cols), gh = cellSize * CGFloat(rows)

        // Smooth Y offset — only apply if the next row down is valid
        let canDrop: Bool = {
            guard var p = current else { return false }
            p.row += 1
            return isValid(p)
        }()
        let smoothY = canDrop ? smoothProgress * cellSize : 0

        // Collect obstacles
        var obstacles: [CGRect] = []

        // Placed blocks
        for r in 0..<rows {
            for c in 0..<cols {
                if grid[r][c] != nil {
                    obstacles.append(cellRect(col: c, row: r))
                }
            }
        }

        // Current piece with smooth offset
        if let p = current {
            for c in p.worldCells() {
                var r = cellRect(col: c.col, row: c.row)
                r.origin.y += smoothY
                obstacles.append(r)
            }
        }

        // Ghost piece
        var ghostCells: [(Int, Int)] = []
        if var ghost = current {
            while true {
                ghost.row += 1
                if !isValid(ghost) { ghost.row -= 1; break }
            }
            ghostCells = ghost.worldCells().map { ($0.col, $0.row) }
            for c in ghostCells {
                obstacles.append(cellRect(col: c.0, row: c.1))
            }
        }

        // Layout text around all obstacles
        var cursor = LayoutCursor.start
        var y: CGFloat = pad
        textLines = []

        while y + lh <= size.height {
            var slots = [Slot(left: pad, right: size.width - pad)]

            for obs in obstacles {
                guard y + lh > obs.minY && y < obs.maxY else { continue }
                let bL = obs.minX, bR = obs.maxX
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
                textLines.append(PositionedLine(text: line.text, x: slot.left, y: y, width: line.width))
                cursor = line.end
            }
            y += lh
        }

        // Draw background text
        let textAttrs: [NSAttributedString.Key: Any] = [
            .font: textFont as UIFont,
            .foregroundColor: UIColor(white: 0.25, alpha: 1),
        ]
        for line in textLines {
            NSAttributedString(string: line.text, attributes: textAttrs).draw(at: CGPoint(x: line.x, y: line.y))
        }

        // Draw grid border
        ctx.setStrokeColor(UIColor(white: 0.25, alpha: 1).cgColor)
        ctx.setLineWidth(1)
        ctx.stroke(CGRect(x: gx - 1, y: gy - 1, width: gw + 2, height: gh + 2))

        // Draw ghost piece
        for c in ghostCells {
            let r = cellRect(col: c.0, row: c.1)
            ctx.setStrokeColor((current?.shape.color ?? .gray).withAlphaComponent(0.25).cgColor)
            ctx.setLineWidth(1)
            ctx.stroke(r.insetBy(dx: 1, dy: 1))
        }

        // Draw placed blocks
        for r in 0..<rows {
            for c in 0..<cols {
                if let shape = grid[r][c] {
                    drawBlock(ctx: ctx, rect: cellRect(col: c, row: r), color: shape.color, alpha: 0.85)
                }
            }
        }

        // Draw current piece with smooth offset
        if let p = current {
            for c in p.worldCells() {
                var r = cellRect(col: c.col, row: c.row)
                r.origin.y += smoothY
                drawBlock(ctx: ctx, rect: r, color: p.shape.color, alpha: 1.0)
            }
        }

        // HUD
        let hudAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont(name: "Menlo-Bold", size: isPad ? 13 : 10)!,
            .foregroundColor: UIColor(red: 0.3, green: 0.85, blue: 0.7, alpha: 0.8),
        ]
        let hudStr = String(format: "SCORE %04d  LINES %d", score, linesCleared)
        NSAttributedString(string: hudStr, attributes: hudAttrs)
            .draw(at: CGPoint(x: pad + 2, y: size.height - (isPad ? 24 : 18)))

        let controlAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont(name: "Menlo", size: isPad ? 11 : 8)!,
            .foregroundColor: UIColor(white: 0.35, alpha: 1),
        ]
        let ctrlStr = NSAttributedString(string: "TAP rotate · SWIPE move · SWIPE DOWN drop", attributes: controlAttrs)
        let ctrlW = ctrlStr.size().width
        ctrlStr.draw(at: CGPoint(x: size.width / 2 - ctrlW / 2, y: size.height - (isPad ? 24 : 18)))

        if gameOver {
            drawCentered(ctx, "GAME OVER", size: isPad ? 32 : 22,
                        color: UIColor(red: 0.9, green: 0.3, blue: 0.3, alpha: 1), y: size.height / 2 - 16)
            drawCentered(ctx, "TAP TO RESTART", size: isPad ? 14 : 11,
                        color: UIColor(white: 0.5, alpha: 0.8), y: size.height / 2 + 16)
        }
    }

    private func cellRect(col: Int, row: Int) -> CGRect {
        CGRect(x: gridOrigin.x + CGFloat(col) * cellSize,
               y: gridOrigin.y + CGFloat(row) * cellSize,
               width: cellSize, height: cellSize)
    }

    private func drawBlock(ctx: CGContext, rect: CGRect, color: UIColor, alpha: CGFloat) {
        let r = rect.insetBy(dx: 1, dy: 1)
        ctx.setFillColor(color.withAlphaComponent(alpha).cgColor)
        ctx.fill(r)
        ctx.setFillColor(UIColor.white.withAlphaComponent(0.15).cgColor)
        ctx.fill(CGRect(x: r.minX, y: r.minY, width: r.width, height: 2))
        ctx.fill(CGRect(x: r.minX, y: r.minY, width: 2, height: r.height))
        ctx.setFillColor(UIColor.black.withAlphaComponent(0.2).cgColor)
        ctx.fill(CGRect(x: r.minX, y: r.maxY - 2, width: r.width, height: 2))
        ctx.fill(CGRect(x: r.maxX - 2, y: r.minY, width: 2, height: r.height))
    }

    private func drawCentered(_ ctx: CGContext, _ text: String, size: CGFloat, color: UIColor, y: CGFloat) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont(name: "Menlo-Bold", size: size)!,
            .foregroundColor: color,
        ]
        let s = NSAttributedString(string: text, attributes: attrs)
        s.draw(at: CGPoint(x: bounds.width / 2 - s.size().width / 2, y: y))
    }
}
