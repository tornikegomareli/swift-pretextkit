import CoreGraphics

// MARK: - Internal Core

/// Internal storage shared by both `PreparedText` and `PreparedTextWithSegments`.
/// Contains all cached segment widths and metadata needed for arithmetic reflow.
struct PreparedCore: @unchecked Sendable {
    /// Per-segment measured widths.
    let widths: [Float]

    /// Advance contribution when the line ends after this segment (for fit testing).
    /// Spaces contribute 0 here (they "hang" past the line edge).
    let lineEndFitAdvances: [Float]

    /// Advance contribution when the line ends after this segment (for paint/rendering).
    let lineEndPaintAdvances: [Float]

    /// Break classification for each segment.
    let kinds: [SegmentBreakKind]

    /// True if all segments are text, space, or zero-width-break —
    /// enables a stripped-down fast-path line walker.
    let simpleLineWalkFastPath: Bool

    /// Per-grapheme widths for segments that may need overflow-wrap breaking.
    /// `nil` for segments that don't need grapheme-level breaking.
    let breakableWidths: [ContiguousArray<Float>?]

    /// Width of a visible hyphen `-` in the current font.
    /// Used when a soft-hyphen break is chosen.
    let discretionaryHyphenWidth: Float

    /// Tab stop advance: `spaceWidth * 8`.
    let tabStopAdvance: Float

    /// Hard-break chunk boundaries. Normal text has one chunk covering everything.
    /// Pre-wrap text with `\n` characters splits into multiple chunks.
    let chunks: [PreparedLineChunk]
}

/// A contiguous region between hard breaks.
struct PreparedLineChunk: Sendable {
    let startSegmentIndex: Int
    let endSegmentIndex: Int
    /// Includes the hard-break segment itself (for the line walker to consume it).
    let consumedEndSegmentIndex: Int
}

// MARK: - Public Types

/// The opaque result of `prepare()`.
///
/// Contains all cached segment widths and metadata needed for `layout()` to
/// compute line count and height using pure arithmetic — no CoreText calls,
/// no string work, no allocations.
///
/// Thread-safe and immutable after creation.
public struct PreparedText: @unchecked Sendable {
    let core: PreparedCore
}

/// Rich variant of `PreparedText` that also exposes segment text arrays
/// for custom rendering via `layoutWithLines()`, `walkLineRanges()`, and `layoutNextLine()`.
public struct PreparedTextWithSegments: @unchecked Sendable {
    let core: PreparedCore

    /// The text of each segment, in order.
    public let segments: [String]

    /// The break kind of each segment.
    public var kinds: [SegmentBreakKind] { core.kinds }

    /// The measured width of each segment.
    public var widths: [Float] { core.widths }
}
