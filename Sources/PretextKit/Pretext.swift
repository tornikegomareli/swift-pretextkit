import CoreGraphics
import CoreText
import Foundation

// MARK: - Prepare (Expensive, One-Time, Any Thread)

/// Segments text, measures each segment via CoreText, and caches widths.
///
/// This is the expensive one-time operation. Call once per `(text, font)` pair.
/// The returned `PreparedText` can then be used with `layout()` for cheap
/// arithmetic reflow at any width.
///
/// Thread-safe: can be called from any thread.
///
/// - Parameters:
///   - text: The text to prepare.
///   - font: The font to measure with.
///   - options: White-space mode and other options.
/// - Returns: An opaque handle for use with `layout()`.
public func prepare(
    _ text: String,
    font: FontDescriptor,
    options: PrepareOptions = PrepareOptions()
) -> PreparedText {
    let analysis = analyzeText(text, whiteSpace: options.whiteSpace)
    let measurer = SegmentMeasurer(font: font.font)
    let result = measureAnalysis(analysis, font: font, measurer: measurer)
    return PreparedText(core: result.core)
}

/// Rich variant that also exposes segment text for custom rendering.
///
/// Use with `layoutWithLines()`, `walkLineRanges()`, or `layoutNextLine()`.
public func prepareWithSegments(
    _ text: String,
    font: FontDescriptor,
    options: PrepareOptions = PrepareOptions()
) -> PreparedTextWithSegments {
    let analysis = analyzeText(text, whiteSpace: options.whiteSpace)
    let measurer = SegmentMeasurer(font: font.font)
    let result = measureAnalysis(analysis, font: font, measurer: measurer)
    return PreparedTextWithSegments(core: result.core, segments: result.segments)
}

// MARK: - Layout (Cheap, Every Resize, Any Thread)

/// Pure arithmetic over cached widths. Zero CoreText calls, zero string work.
///
/// Call this on every resize — it's designed to be extremely fast (~0.001ms per text).
///
/// - Parameters:
///   - prepared: The result of `prepare()`.
///   - maxWidth: The maximum line width.
///   - lineHeight: The height of each line.
/// - Returns: Line count and total height.
public func layout(
    _ prepared: PreparedText,
    maxWidth: CGFloat,
    lineHeight: CGFloat
) -> LayoutResult {
    let lineCount = countPreparedLines(prepared.core, maxWidth: Float(maxWidth))
    return LayoutResult(lineCount: lineCount, height: CGFloat(lineCount) * lineHeight)
}

/// Layout overload for `PreparedTextWithSegments`.
public func layout(
    _ prepared: PreparedTextWithSegments,
    maxWidth: CGFloat,
    lineHeight: CGFloat
) -> LayoutResult {
    let lineCount = countPreparedLines(prepared.core, maxWidth: Float(maxWidth))
    return LayoutResult(lineCount: lineCount, height: CGFloat(lineCount) * lineHeight)
}

// MARK: - Rich Layout APIs

/// Returns all lines with text content and cursor positions.
///
/// More expensive than `layout()` because it materializes line text strings.
/// Use when you need the actual text content of each line for rendering.
public func layoutWithLines(
    _ prepared: PreparedTextWithSegments,
    maxWidth: CGFloat,
    lineHeight: CGFloat
) -> LayoutLinesResult {
    var lines: [LayoutLine] = []

    walkPreparedLines(prepared.core, segments: prepared.segments, maxWidth: Float(maxWidth)) { internal_line in
        let text = materializeLineText(
            prepared.segments,
            core: prepared.core,
            line: internal_line
        )
        lines.append(LayoutLine(
            text: text,
            width: CGFloat(internal_line.width),
            start: LayoutCursor(segmentIndex: internal_line.startSegmentIndex, graphemeIndex: internal_line.startGraphemeIndex),
            end: LayoutCursor(segmentIndex: internal_line.endSegmentIndex, graphemeIndex: internal_line.endGraphemeIndex)
        ))
    }

    let height = CGFloat(lines.count) * lineHeight
    return LayoutLinesResult(lineCount: lines.count, height: height, lines: lines)
}

/// Walks lines without materializing text strings.
///
/// The most efficient way to get line geometry (widths, cursors) when you
/// don't need the text content. Ideal for shrink-wrap width calculation.
///
/// - Returns: The total number of lines.
@discardableResult
public func walkLineRanges(
    _ prepared: PreparedTextWithSegments,
    maxWidth: CGFloat,
    onLine: (LayoutLineRange) -> Void
) -> Int {
    var lineCount = 0
    walkPreparedLines(prepared.core, segments: prepared.segments, maxWidth: Float(maxWidth)) { internal_line in
        onLine(LayoutLineRange(
            width: CGFloat(internal_line.width),
            start: LayoutCursor(segmentIndex: internal_line.startSegmentIndex, graphemeIndex: internal_line.startGraphemeIndex),
            end: LayoutCursor(segmentIndex: internal_line.endSegmentIndex, graphemeIndex: internal_line.endGraphemeIndex)
        ))
        lineCount += 1
    }
    return lineCount
}

/// Steps one line at a time for variable-width flows.
///
/// Returns the next line starting from `start`, or `nil` if the text is exhausted.
/// Chain the returned line's `end` cursor as the next `start` to iterate.
///
/// This enables text flowing around obstacles where each line may have a different width.
public func layoutNextLine(
    _ prepared: PreparedTextWithSegments,
    start: LayoutCursor,
    maxWidth: CGFloat
) -> LayoutLine? {
    let core = prepared.core
    let segments = prepared.segments
    let totalSegments = segments.count

    guard start.segmentIndex < totalSegments else { return nil }

    var result: LayoutLine?
    walkSingleLine(core, segments: segments, start: start, maxWidth: Float(maxWidth)) { internal_line in
        let text = materializeLineText(segments, core: core, line: internal_line)
        result = LayoutLine(
            text: text,
            width: CGFloat(internal_line.width),
            start: LayoutCursor(segmentIndex: internal_line.startSegmentIndex, graphemeIndex: internal_line.startGraphemeIndex),
            end: LayoutCursor(segmentIndex: internal_line.endSegmentIndex, graphemeIndex: internal_line.endGraphemeIndex)
        )
    }
    return result
}

// MARK: - Cache Management

/// Clears all cached segment measurements.
///
/// Call when fonts change dynamically or to free memory.
public func clearCache() {
    sharedMetricsCache.clear()
}

/// Sets the locale for word segmentation. Also clears the cache.
///
/// Use before `prepare()` when the app needs a specific locale for
/// word breaking (e.g., Thai requires locale context).
public func setLocale(_ locale: Locale?) {
    setAnalysisLocale(locale)
    sharedMetricsCache.clear()
}

// MARK: - Internal Text Materialization

/// Build the text string for a laid-out line from segments.
private func materializeLineText(
    _ segments: [String],
    core: PreparedCore,
    line: InternalLayoutLine
) -> String {
    var text = ""

    for i in line.startSegmentIndex..<line.endSegmentIndex {
        let segText = segments[i]
        let kind = core.kinds[i]

        if kind == .space && i == line.endSegmentIndex - 1 { continue }

        if i == line.startSegmentIndex && line.startGraphemeIndex > 0 {
            let graphemes = Array(segText)
            text += graphemes[line.startGraphemeIndex...].map(String.init).joined()
        } else if i == line.endSegmentIndex - 1 && line.endGraphemeIndex > 0 {
            let graphemes = Array(segText)
            let endIdx = min(line.endGraphemeIndex, graphemes.count)
            text += graphemes[..<endIdx].map(String.init).joined()
        } else if kind == .softHyphen {
            if i == line.endSegmentIndex - 1 {
                text += "-"
            }
        } else {
            text += segText
        }
    }

    return text
}

/// Walk a single line from a given start position.
private func walkSingleLine(
    _ core: PreparedCore,
    segments: [String],
    start: LayoutCursor,
    maxWidth: Float,
    onLine: (InternalLayoutLine) -> Void
) {
    let totalSegments = segments.count
    guard start.segmentIndex < totalSegments else { return }

    var lineW: Float = 0
    var hasContent = false
    var pendingBreakIndex = -1
    var pendingBreakPaintWidth: Float = 0
    let lineStart = start.segmentIndex
    let lineStartGrapheme = start.graphemeIndex

    for i in start.segmentIndex..<totalSegments {
        let kind = core.kinds[i]

        if kind == .hardBreak {
            onLine(InternalLayoutLine(
                startSegmentIndex: lineStart,
                startGraphemeIndex: lineStartGrapheme,
                endSegmentIndex: i + 1,
                endGraphemeIndex: 0,
                width: lineW
            ))
            return
        }

        let w = core.widths[i]
        let advance: Float = kind == .tab
            ? getTabAdvance(lineW: lineW, tabStopAdvance: core.tabStopAdvance)
            : w

        if !hasContent {
            if kind.isSimpleCollapsibleSpace { continue }
            lineW = advance
            hasContent = true
            if kind.canBreakAfter {
                pendingBreakIndex = i
                pendingBreakPaintWidth = core.lineEndPaintAdvances[i]
            }
            continue
        }

        let fitW = lineW + core.lineEndFitAdvances[i]
        if fitW <= maxWidth + lineFitEpsilon {
            lineW += advance
            if kind.canBreakAfter {
                pendingBreakIndex = i
                pendingBreakPaintWidth = lineW
            }
        } else if kind.isSimpleCollapsibleSpace {
            if kind.canBreakAfter {
                pendingBreakIndex = i
                pendingBreakPaintWidth = lineW
            }
        } else {
            let endSeg = pendingBreakIndex >= 0 ? pendingBreakIndex + 1 : i
            let paintW = pendingBreakIndex >= 0 ? pendingBreakPaintWidth : lineW
            onLine(InternalLayoutLine(
                startSegmentIndex: lineStart,
                startGraphemeIndex: lineStartGrapheme,
                endSegmentIndex: endSeg,
                endGraphemeIndex: 0,
                width: paintW
            ))
            return
        }
    }

    if hasContent {
        onLine(InternalLayoutLine(
            startSegmentIndex: lineStart,
            startGraphemeIndex: lineStartGrapheme,
            endSegmentIndex: totalSegments,
            endGraphemeIndex: 0,
            width: lineW
        ))
    }
}
