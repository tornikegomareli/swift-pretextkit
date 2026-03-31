import Foundation

/// Measures per-grapheme widths within a segment for overflow-wrap breaking.
func measureGraphemeWidths(
    _ text: String,
    measurer: SegmentMeasurer
) -> ContiguousArray<Float>? {
    let graphemeCount = text.count
    guard graphemeCount > 1 else { return nil }
    return measurer.measureGraphemeWidths(text)
}

// MARK: - Prepared Segment Builder

/// Collects measured segments during the measurement phase, handling CJK grapheme splitting.
struct PreparedSegmentBuilder {
    var widths: [Float] = []
    var lineEndFitAdvances: [Float] = []
    var lineEndPaintAdvances: [Float] = []
    var kinds: [SegmentBreakKind] = []
    var breakableWidths: [ContiguousArray<Float>?] = []
    var segments: [String] = []
    var simpleLineWalkFastPath = true

    mutating func push(
        text: String,
        width: Float,
        fitAdvance: Float,
        paintAdvance: Float,
        kind: SegmentBreakKind,
        breakable: ContiguousArray<Float>? = nil
    ) {
        widths.append(width)
        lineEndFitAdvances.append(fitAdvance)
        lineEndPaintAdvances.append(paintAdvance)
        kinds.append(kind)
        breakableWidths.append(breakable)
        segments.append(text)
        if kind != .text && kind != .space && kind != .zeroWidthBreak {
            simpleLineWalkFastPath = false
        }
    }
}

// MARK: - Main Measurement

/// Result of measurement: the PreparedCore plus the expanded segment texts
/// (which may differ from analysis segments due to CJK splitting).
struct MeasurementResult {
    let core: PreparedCore
    let segments: [String]
}

/// Measures all segments in the analysis and builds the PreparedCore.
///
/// Key difference from a naive port: CJK text segments are split into
/// individual graphemes (with kinsoku merging) so each CJK character
/// becomes its own segment in the prepared data. This matches how
/// CTFramesetter breaks CJK text.
func measureAnalysis(
    _ analysis: TextAnalysis,
    font: FontDescriptor,
    measurer: SegmentMeasurer
) -> MeasurementResult {
    let seg = analysis.segmentation
    var builder = PreparedSegmentBuilder()

    let spaceWidth = measurer.measureSpaceWidth()
    let hyphenWidth = measurer.measureHyphenWidth()
    let tabStopAdvance = spaceWidth * 8

    for i in 0..<seg.count {
        let text = seg.texts[i]
        let kind = seg.kinds[i]
        let isWord = seg.isWordLike[i]

        switch kind {
        case .softHyphen:
            builder.push(text: text, width: 0, fitAdvance: hyphenWidth, paintAdvance: hyphenWidth, kind: kind)

        case .hardBreak:
            builder.push(text: text, width: 0, fitAdvance: 0, paintAdvance: 0, kind: kind)

        case .tab:
            builder.push(text: text, width: 0, fitAdvance: 0, paintAdvance: 0, kind: kind)

        case .space:
            let w = sharedMetricsCache.getOrMeasure(text, font: font, measurer: measurer).width
            builder.push(text: text, width: w, fitAdvance: 0, paintAdvance: 0, kind: kind)

        case .preservedSpace:
            let w = sharedMetricsCache.getOrMeasure(text, font: font, measurer: measurer).width
            builder.push(text: text, width: w, fitAdvance: 0, paintAdvance: 0, kind: kind)

        case .glue:
            let w = sharedMetricsCache.getOrMeasure(text, font: font, measurer: measurer).width
            builder.push(text: text, width: w, fitAdvance: w, paintAdvance: w, kind: kind)

        case .zeroWidthBreak:
            builder.push(text: text, width: 0, fitAdvance: 0, paintAdvance: 0, kind: kind)

        case .text:
            let metrics = sharedMetricsCache.getOrMeasure(text, font: font, measurer: measurer)

            if metrics.containsCJK {
                splitCJKIntoGraphemes(text, font: font, measurer: measurer, builder: &builder)
            } else {
                let w = metrics.width
                let breakable: ContiguousArray<Float>? = (isWord && text.count > 1)
                    ? measureGraphemeWidths(text, measurer: measurer)
                    : nil
                builder.push(text: text, width: w, fitAdvance: w, paintAdvance: w, kind: .text, breakable: breakable)
            }
        }
    }

    // CJK splitting changes segment count, so chunk boundaries must be remapped.
    let chunks: [PreparedLineChunk]
    if analysis.chunks.count <= 1 {
        if builder.widths.isEmpty {
            chunks = []
        } else {
            chunks = [PreparedLineChunk(
                startSegmentIndex: 0,
                endSegmentIndex: builder.widths.count,
                consumedEndSegmentIndex: builder.widths.count
            )]
        }
    } else {
        chunks = remapChunksFromBuilder(builder)
    }

    let core = PreparedCore(
        widths: builder.widths,
        lineEndFitAdvances: builder.lineEndFitAdvances,
        lineEndPaintAdvances: builder.lineEndPaintAdvances,
        kinds: builder.kinds,
        simpleLineWalkFastPath: builder.simpleLineWalkFastPath,
        breakableWidths: builder.breakableWidths,
        discretionaryHyphenWidth: hyphenWidth,
        tabStopAdvance: tabStopAdvance,
        chunks: chunks
    )
    return MeasurementResult(core: core, segments: builder.segments)
}

// MARK: - CJK Grapheme Splitting

/// Splits a CJK-containing segment into individual graphemes, applying kinsoku rules.
///
/// Kinsoku-end characters (opening brackets) stick to the following grapheme.
/// Kinsoku-start characters (closing brackets, periods) stick to the preceding grapheme.
private func splitCJKIntoGraphemes(
    _ text: String,
    font: FontDescriptor,
    measurer: SegmentMeasurer,
    builder: inout PreparedSegmentBuilder
) {
    var unitText = ""

    for char in text {
        let grapheme = String(char)

        if unitText.isEmpty {
            unitText = grapheme
            continue
        }

        let graphemeScalar = grapheme.unicodeScalars.first!

        if isKinsokuEndUnit(unitText)
            || kinsokuStartScalars.contains(graphemeScalar)
            || leftStickyPunctuation.contains(graphemeScalar) {
            unitText += grapheme
            continue
        }

        let w = sharedMetricsCache.getOrMeasure(unitText, font: font, measurer: measurer).width
        builder.push(text: unitText, width: w, fitAdvance: w, paintAdvance: w, kind: .text)

        unitText = grapheme
    }

    if !unitText.isEmpty {
        let w = sharedMetricsCache.getOrMeasure(unitText, font: font, measurer: measurer).width
        builder.push(text: unitText, width: w, fitAdvance: w, paintAdvance: w, kind: .text)
    }
}

/// Whether the text consists only of kinsoku-end (line-end prohibited) characters.
private func isKinsokuEndUnit(_ text: String) -> Bool {
    for scalar in text.unicodeScalars {
        if !kinsokuEndScalars.contains(scalar) { return false }
    }
    return !text.isEmpty
}

// MARK: - Chunk Remapping

/// Rebuild chunk boundaries from the builder output for pre-wrap mode.
private func remapChunksFromBuilder(_ builder: PreparedSegmentBuilder) -> [PreparedLineChunk] {
    var chunks: [PreparedLineChunk] = []
    var chunkStart = 0

    for i in 0..<builder.kinds.count {
        if builder.kinds[i] == .hardBreak {
            chunks.append(PreparedLineChunk(
                startSegmentIndex: chunkStart,
                endSegmentIndex: i,
                consumedEndSegmentIndex: i + 1
            ))
            chunkStart = i + 1
        }
    }

    if chunkStart < builder.kinds.count {
        chunks.append(PreparedLineChunk(
            startSegmentIndex: chunkStart,
            endSegmentIndex: builder.kinds.count,
            consumedEndSegmentIndex: builder.kinds.count
        ))
    } else if chunks.isEmpty && !builder.kinds.isEmpty {
        chunks.append(PreparedLineChunk(
            startSegmentIndex: 0,
            endSegmentIndex: builder.kinds.count,
            consumedEndSegmentIndex: builder.kinds.count
        ))
    }

    return chunks
}
