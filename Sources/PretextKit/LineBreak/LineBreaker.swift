import Foundation

/// Line-fit rounding tolerance. On iOS there's only one text engine (CoreText),
/// so we use a single fixed epsilon rather than per-browser values.
let lineFitEpsilon: Float = 0.005

/// Internal representation of a laid-out line for the line walker.
struct InternalLayoutLine {
    var startSegmentIndex: Int
    var startGraphemeIndex: Int
    var endSegmentIndex: Int
    var endGraphemeIndex: Int
    var width: Float
}

// MARK: - Simple Line Counter (Fast Path)

/// Ultra-fast line counter for text that only contains `.text`, `.space`,
/// and `.zeroWidthBreak` segments. No tabs, soft hyphens, or hard breaks.
///
/// This is the hot path: pure arithmetic on cached widths, zero allocations.
func countPreparedLinesSimple(_ core: PreparedCore, maxWidth: Float) -> Int {
    let count = core.widths.count
    guard count > 0 else { return 0 }

    var lineCount = 1
    var lineW: Float = 0
    var hasContent = false

    return core.widths.withUnsafeBufferPointer { widthsBuf in
        core.kinds.withUnsafeBufferPointer { kindsBuf in
            core.breakableWidths.withUnsafeBufferPointer { breakableBuf in

                for i in 0..<count {
                    let w = widthsBuf[i]
                    let kind = kindsBuf[i]

                    if !hasContent {
                        if kind.isSimpleCollapsibleSpace { continue }
                        lineW = w
                        hasContent = true

                        if w > maxWidth + lineFitEpsilon, let graphemeWidths = breakableBuf[i] {
                            lineCount += breakOverflowGraphemes(
                                graphemeWidths: graphemeWidths,
                                lineW: &lineW,
                                maxWidth: maxWidth,
                                hasContent: &hasContent
                            )
                        }
                        continue
                    }

                    if lineW + w <= maxWidth + lineFitEpsilon {
                        lineW += w
                    } else if kind.isSimpleCollapsibleSpace {
                        continue
                    } else {
                        lineCount += 1
                        lineW = w
                        hasContent = true

                        if w > maxWidth + lineFitEpsilon, let graphemeWidths = breakableBuf[i] {
                            lineCount += breakOverflowGraphemes(
                                graphemeWidths: graphemeWidths,
                                lineW: &lineW,
                                maxWidth: maxWidth,
                                hasContent: &hasContent
                            )
                        }
                    }
                }

                return lineCount
            }
        }
    }
}

/// Break a single overflowing segment at grapheme boundaries.
/// Returns the number of *additional* lines created.
private func breakOverflowGraphemes(
    graphemeWidths: ContiguousArray<Float>,
    lineW: inout Float,
    maxWidth: Float,
    hasContent: inout Bool
) -> Int {
    var additionalLines = 0
    var currentW: Float = 0

    for gw in graphemeWidths {
        if currentW + gw > maxWidth + lineFitEpsilon, currentW > 0 {
            additionalLines += 1
            currentW = gw
        } else {
            currentW += gw
        }
    }

    lineW = currentW
    hasContent = currentW > 0
    return additionalLines
}

// MARK: - Complex Line Counter

/// Full-featured line counter that handles all segment kinds:
/// tabs, soft hyphens, hard breaks, preserved spaces, glue.
func countPreparedLines(_ core: PreparedCore, maxWidth: Float) -> Int {
    // Use fast path when possible
    if core.simpleLineWalkFastPath {
        return countPreparedLinesSimple(core, maxWidth: maxWidth)
    }

    var lineCount = 0
    for chunk in core.chunks {
        lineCount += countChunkLines(core, chunk: chunk, maxWidth: maxWidth)
    }
    return max(lineCount, core.chunks.isEmpty ? 0 : lineCount)
}

/// Count lines within a single hard-break chunk.
private func countChunkLines(_ core: PreparedCore, chunk: PreparedLineChunk, maxWidth: Float) -> Int {
    let start = chunk.startSegmentIndex
    let end = chunk.endSegmentIndex

    if start >= end { return 1 }

    var lineCount = 1
    var lineW: Float = 0
    var hasContent = false
    var pendingBreakIndex = -1

    for i in start..<end {
        let w = core.widths[i]
        let kind = core.kinds[i]

        let advance: Float = kind == .tab
            ? getTabAdvance(lineW: lineW, tabStopAdvance: core.tabStopAdvance) : w

        if !hasContent {
            if kind.isSimpleCollapsibleSpace { continue }
            lineW = advance
            hasContent = true
            if kind.canBreakAfter { pendingBreakIndex = i }

            if advance > maxWidth + lineFitEpsilon, let graphemeWidths = core.breakableWidths[i] {
                lineCount += breakOverflowGraphemes(
                    graphemeWidths: graphemeWidths, lineW: &lineW,
                    maxWidth: maxWidth, hasContent: &hasContent
                )
                pendingBreakIndex = -1
            }
            continue
        }

        let fitW = lineW + core.lineEndFitAdvances[i]
        if fitW <= maxWidth + lineFitEpsilon {
            lineW += advance
            if kind.canBreakAfter { pendingBreakIndex = i }
        } else if kind.isSimpleCollapsibleSpace {
            if kind.canBreakAfter { pendingBreakIndex = i }
        } else if pendingBreakIndex >= 0 {
            lineCount += 1
            lineW = advance
            hasContent = true
            pendingBreakIndex = -1
            if kind.canBreakAfter { pendingBreakIndex = i }

            if advance > maxWidth + lineFitEpsilon, let graphemeWidths = core.breakableWidths[i] {
                lineCount += breakOverflowGraphemes(
                    graphemeWidths: graphemeWidths,
                    lineW: &lineW,
                    maxWidth: maxWidth,
                    hasContent: &hasContent
                )
                pendingBreakIndex = -1
            }
        } else {
            // No pending break: force break here
            lineCount += 1
            lineW = advance
            hasContent = true
            pendingBreakIndex = -1

            if advance > maxWidth + lineFitEpsilon, let graphemeWidths = core.breakableWidths[i] {
                lineCount += breakOverflowGraphemes(
                    graphemeWidths: graphemeWidths,
                    lineW: &lineW,
                    maxWidth: maxWidth,
                    hasContent: &hasContent
                )
            }
        }
    }

    return lineCount
}

// MARK: - Tab Advance

func getTabAdvance(lineW: Float, tabStopAdvance: Float) -> Float {
    guard tabStopAdvance > 0 else { return 0 }
    let remainder = lineW.truncatingRemainder(dividingBy: tabStopAdvance)
    if abs(remainder) <= 1e-6 { return tabStopAdvance }
    return tabStopAdvance - remainder
}

// MARK: - Line Walker (Rich Path)

/// Walks all lines, calling `onLine` for each. Used by `layoutWithLines()` and `walkLineRanges()`.
func walkPreparedLines(
    _ core: PreparedCore,
    segments: [String],
    maxWidth: Float,
    onLine: (InternalLayoutLine) -> Void
) {
    for chunk in core.chunks {
        walkChunkLines(core, segments: segments, chunk: chunk, maxWidth: maxWidth, onLine: onLine)
    }
}

/// Walk lines within a single chunk.
private func walkChunkLines(
    _ core: PreparedCore,
    segments: [String],
    chunk: PreparedLineChunk,
    maxWidth: Float,
    onLine: (InternalLayoutLine) -> Void
) {
    let start = chunk.startSegmentIndex
    let end = chunk.endSegmentIndex

    if start >= end {
        // Empty chunk = one empty line
        onLine(InternalLayoutLine(
            startSegmentIndex: start,
            startGraphemeIndex: 0,
            endSegmentIndex: start,
            endGraphemeIndex: 0,
            width: 0
        ))
        return
    }

    var lineStart = start
    var lineStartGrapheme = 0
    var lineW: Float = 0
    var hasContent = false
    var pendingBreakIndex = -1
    var pendingBreakPaintWidth: Float = 0

    for i in start..<end {
        let w = core.widths[i]
        let kind = core.kinds[i]

        let advance: Float
        if kind == .tab {
            advance = getTabAdvance(lineW: lineW, tabStopAdvance: core.tabStopAdvance)
        } else {
            advance = w
        }

        if !hasContent {
            if kind.isSimpleCollapsibleSpace { continue }
            lineW = advance
            hasContent = true
            if lineStart > i { lineStart = i }
            if kind.canBreakAfter {
                pendingBreakIndex = i
                pendingBreakPaintWidth = core.lineEndPaintAdvances[i]
            }

            // Overflow-wrap with grapheme breaking
            if advance > maxWidth + lineFitEpsilon, let graphemeWidths = core.breakableWidths[i] {
                emitGraphemeBreakLines(
                    segmentIndex: i,
                    graphemeWidths: graphemeWidths,
                    maxWidth: maxWidth,
                    lineStart: &lineStart,
                    lineStartGrapheme: &lineStartGrapheme,
                    lineW: &lineW,
                    hasContent: &hasContent,
                    onLine: onLine
                )
                pendingBreakIndex = -1
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
            // Emit current line
            let endSeg = pendingBreakIndex >= 0 ? pendingBreakIndex + 1 : i
            let paintW = pendingBreakIndex >= 0 ? pendingBreakPaintWidth : lineW
            onLine(InternalLayoutLine(
                startSegmentIndex: lineStart,
                startGraphemeIndex: lineStartGrapheme,
                endSegmentIndex: endSeg,
                endGraphemeIndex: 0,
                width: paintW
            ))

            // Start new line
            lineStart = pendingBreakIndex >= 0 ? pendingBreakIndex + 1 : i
            lineStartGrapheme = 0
            lineW = advance
            hasContent = true
            pendingBreakIndex = -1

            if kind.canBreakAfter {
                pendingBreakIndex = i
                pendingBreakPaintWidth = advance
            }

            if advance > maxWidth + lineFitEpsilon, let graphemeWidths = core.breakableWidths[i] {
                emitGraphemeBreakLines(
                    segmentIndex: i,
                    graphemeWidths: graphemeWidths,
                    maxWidth: maxWidth,
                    lineStart: &lineStart,
                    lineStartGrapheme: &lineStartGrapheme,
                    lineW: &lineW,
                    hasContent: &hasContent,
                    onLine: onLine
                )
                pendingBreakIndex = -1
            }
        }
    }

    // Emit final line
    if hasContent || lineStart < end {
        onLine(InternalLayoutLine(
            startSegmentIndex: lineStart,
            startGraphemeIndex: lineStartGrapheme,
            endSegmentIndex: end,
            endGraphemeIndex: 0,
            width: lineW
        ))
    }
}

/// Emit lines when a segment overflows and must be broken at grapheme boundaries.
private func emitGraphemeBreakLines(
    segmentIndex: Int,
    graphemeWidths: ContiguousArray<Float>,
    maxWidth: Float,
    lineStart: inout Int,
    lineStartGrapheme: inout Int,
    lineW: inout Float,
    hasContent: inout Bool,
    onLine: (InternalLayoutLine) -> Void
) {
    var currentW: Float = 0
    var graphemeStart = 0

    for (gi, gw) in graphemeWidths.enumerated() {
        if currentW + gw > maxWidth + lineFitEpsilon, currentW > 0 {
            // Emit line up to this grapheme
            onLine(InternalLayoutLine(
                startSegmentIndex: lineStart,
                startGraphemeIndex: lineStartGrapheme,
                endSegmentIndex: segmentIndex,
                endGraphemeIndex: gi,
                width: currentW
            ))
            lineStart = segmentIndex
            lineStartGrapheme = gi
            graphemeStart = gi
            currentW = gw
        } else {
            currentW += gw
        }
    }

    lineW = currentW
    hasContent = currentW > 0
    lineStartGrapheme = graphemeStart
}
