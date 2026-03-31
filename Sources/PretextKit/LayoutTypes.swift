import CoreGraphics

// MARK: - Layout Result

/// The result of `layout()` — just line count and total height.
/// This is the cheap output of the arithmetic hot path.
public struct LayoutResult: Sendable {
    /// Number of lines the text wraps to at the given width.
    public let lineCount: Int
    /// Total height: `lineCount * lineHeight`.
    public let height: CGFloat

    public init(lineCount: Int, height: CGFloat) {
        self.lineCount = lineCount
        self.height = height
    }
}

// MARK: - Layout Cursor

/// A position within prepared text, expressed as segment + grapheme indices.
///
/// Used to track where a line starts and ends, and to resume iteration
/// with `layoutNextLine()`. The dual index is necessary because some
/// segments can break mid-grapheme (overflow-wrap, soft hyphens).
public struct LayoutCursor: Sendable, Equatable {
    /// Index into the segment array.
    public let segmentIndex: Int
    /// Index into the grapheme array within the segment (0 for whole-segment positions).
    public let graphemeIndex: Int

    public init(segmentIndex: Int, graphemeIndex: Int) {
        self.segmentIndex = segmentIndex
        self.graphemeIndex = graphemeIndex
    }

    /// The starting cursor (beginning of text).
    public static let start = LayoutCursor(segmentIndex: 0, graphemeIndex: 0)
}

// MARK: - Layout Line

/// A single laid-out line with its text content and cursor boundaries.
public struct LayoutLine: Sendable {
    /// The text content of this line.
    public let text: String
    /// The measured width of this line's content.
    public let width: CGFloat
    /// Cursor position at the start of this line.
    public let start: LayoutCursor
    /// Cursor position at the end of this line (start of next line).
    public let end: LayoutCursor
}

// MARK: - Layout Line Range

/// Like `LayoutLine` but without the text string — used by `walkLineRanges()`
/// to avoid the cost of text materialization when only geometry is needed.
public struct LayoutLineRange: Sendable {
    /// The measured width of this line's content.
    public let width: CGFloat
    /// Cursor position at the start of this line.
    public let start: LayoutCursor
    /// Cursor position at the end of this line.
    public let end: LayoutCursor
}

// MARK: - Layout Lines Result

/// Full result of `layoutWithLines()` — line count, height, and all lines.
public struct LayoutLinesResult: Sendable {
    public let lineCount: Int
    public let height: CGFloat
    public let lines: [LayoutLine]
}
