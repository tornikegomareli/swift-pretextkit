import Foundation

// MARK: - Analysis Output Types

/// The result of text analysis: normalized text, segments, and chunk boundaries.
struct TextAnalysis {
    let normalized: String
    let chunks: [AnalysisChunk]
    let segmentation: MergedSegmentation
}

/// Hard-break chunk boundaries within the segment array.
struct AnalysisChunk {
    let startSegmentIndex: Int
    let endSegmentIndex: Int
    let consumedEndSegmentIndex: Int
}

/// The merged segmentation of analyzed text.
struct MergedSegmentation {
    var texts: [String]
    var isWordLike: [Bool]
    var kinds: [SegmentBreakKind]
    var starts: [Int]

    var count: Int { texts.count }

    /// Remove empty entries (compact in-place).
    ///
    /// Uses `removeLast(_:)` instead of `removeSubrange` to avoid
    /// intermediate range allocation — mirrors the TS `.length = n` truncation.
    mutating func compact() {
        var write = 0
        for read in 0..<texts.count {
            if texts[read].isEmpty { continue }
            if write != read {
                texts[write] = texts[read]
                isWordLike[write] = isWordLike[read]
                kinds[write] = kinds[read]
                starts[write] = starts[read]
            }
            write += 1
        }
        let excess = texts.count - write
        if excess > 0 {
            texts.removeLast(excess)
            isWordLike.removeLast(excess)
            kinds.removeLast(excess)
            starts.removeLast(excess)
        }
    }
}

// MARK: - Whitespace Normalization

/// Collapses whitespace runs to a single space and trims edges (CSS `white-space: normal`).
func normalizeWhitespaceNormal(_ text: String) -> String {
    // Fast path: if no special whitespace, return as-is
    let needsNormalization = text.unicodeScalars.contains {
        $0 == "\t" || $0 == "\n" || $0 == "\r" || $0 == "\u{000C}"
    } || text.contains("  ") || text.hasPrefix(" ") || text.hasSuffix(" ")

    guard needsNormalization else { return text }

    var result = ""
    result.reserveCapacity(text.utf8.count)
    var lastWasSpace = true
    for scalar in text.unicodeScalars {
        if scalar == " " || scalar == "\t" || scalar == "\n" || scalar == "\r" || scalar == "\u{000C}" {
            if !lastWasSpace {
                result.unicodeScalars.append(" ")
                lastWasSpace = true
            }
        } else {
            result.unicodeScalars.append(scalar)
            lastWasSpace = false
        }
    }

    // Trim trailing space
    if result.hasSuffix(" ") {
        result.removeLast()
    }
    return result
}

/// Normalizes line endings for pre-wrap mode.
///
/// Single-pass scalar walk instead of three chained `replacingOccurrences`
/// calls, which would allocate three intermediate strings.
func normalizeWhitespacePreWrap(_ text: String) -> String {
    var needsWork = false
    for s in text.unicodeScalars {
        if s == "\r" || s == "\u{000C}" { needsWork = true; break }
    }
    guard needsWork else { return text }

    var result = ""
    result.reserveCapacity(text.utf8.count)
    var prev: Unicode.Scalar?
    for s in text.unicodeScalars {
        if s == "\n" && prev == "\r" { prev = s; continue } // skip \n after \r
        if s == "\r" || s == "\u{000C}" {
            result.unicodeScalars.append("\n")
        } else {
            result.unicodeScalars.append(s)
        }
        prev = s
    }
    return result
}

// MARK: - Shared Locale State

private var _segmenterLocale: Locale?
private let _localeLock = NSLock()

func setAnalysisLocale(_ locale: Locale?) {
    _localeLock.lock()
    _segmenterLocale = locale
    _localeLock.unlock()
}

func getAnalysisLocale() -> Locale? {
    _localeLock.lock()
    defer { _localeLock.unlock() }
    return _segmenterLocale
}

// MARK: - Main Analysis Entry Point

/// Analyzes text: normalizes whitespace, segments, applies merge rules,
/// classifies segments, and compiles chunk boundaries.
func analyzeText(
    _ text: String,
    whiteSpace: WhiteSpaceMode = .normal
) -> TextAnalysis {
    let normalized: String
    switch whiteSpace {
    case .preWrap:
        normalized = normalizeWhitespacePreWrap(text)
    case .normal:
        normalized = normalizeWhitespaceNormal(text)
    }

    guard !normalized.isEmpty else {
        return TextAnalysis(
            normalized: normalized,
            chunks: [],
            segmentation: MergedSegmentation(texts: [], isWordLike: [], kinds: [], starts: [])
        )
    }

    let segmentation = buildMergedSegmentation(normalized, whiteSpace: whiteSpace)
    let chunks = compileAnalysisChunks(segmentation, whiteSpace: whiteSpace)

    return TextAnalysis(
        normalized: normalized,
        chunks: chunks,
        segmentation: segmentation
    )
}

// MARK: - Build Merged Segmentation

/// Main segmentation pipeline: word segment → classify → merge rules.
private func buildMergedSegmentation(
    _ normalized: String,
    whiteSpace: WhiteSpaceMode
) -> MergedSegmentation {
    let locale = getAnalysisLocale()
    let wordSegments = segmentWords(normalized, locale: locale)

    var texts: [String] = []
    var wordLikes: [Bool] = []
    var kinds: [SegmentBreakKind] = []
    var starts: [Int] = []

    let estimatedCapacity = wordSegments.count * 2
    texts.reserveCapacity(estimatedCapacity)
    wordLikes.reserveCapacity(estimatedCapacity)
    kinds.reserveCapacity(estimatedCapacity)
    starts.reserveCapacity(estimatedCapacity)

    for seg in wordSegments {
        let pieces = splitSegmentByBreakKind(seg.text, isWordLike: seg.isWordLike, start: seg.utf16Start, whiteSpace: whiteSpace)

        for piece in pieces {
            let isText = piece.kind == .text
            let count = texts.count

            // CJK kinsoku-start: line-start-prohibited chars merge into preceding segment
            if isText, count > 0, kinds[count - 1] == .text,
               isCJKLineStartProhibitedSegment(piece.text),
               isCJK(texts[count - 1]) {
                texts[count - 1] += piece.text
                wordLikes[count - 1] = wordLikes[count - 1] || piece.isWordLike
                continue
            }

            // Myanmar medial glue: merge across boundaries
            if isText, count > 0, kinds[count - 1] == .text,
               endsWithMyanmarMedialGlue(texts[count - 1]) {
                texts[count - 1] += piece.text
                wordLikes[count - 1] = wordLikes[count - 1] || piece.isWordLike
                continue
            }

            // Arabic no-space punctuation: Arabic text + punctuation + Arabic text
            if isText, count > 0, kinds[count - 1] == .text,
               piece.isWordLike,
               containsArabicScript(piece.text),
               endsWithArabicNoSpacePunctuation(texts[count - 1]) {
                texts[count - 1] += piece.text
                wordLikes[count - 1] = true
                continue
            }

            // Repeated single-char punctuation run
            if isText, !piece.isWordLike, count > 0, kinds[count - 1] == .text,
               piece.text.unicodeScalars.count == 1,
               piece.text != "-", piece.text != "—",
               isRepeatedSingleCharRun(texts[count - 1], char: piece.text) {
                texts[count - 1] += piece.text
                continue
            }

            // Left-sticky punctuation: trailing ".", ",", etc. merge with preceding word
            if isText, !piece.isWordLike, count > 0, kinds[count - 1] == .text,
               (isLeftStickyPunctuationSegment(piece.text) || (piece.text == "-" && wordLikes[count - 1])) {
                texts[count - 1] += piece.text
                continue
            }

            // Default: new segment
            texts.append(piece.text)
            wordLikes.append(piece.isWordLike)
            kinds.append(piece.kind)
            starts.append(piece.start)
        }
    }

    // Phase 2: Escaped quote attachment (backward pass)
    for i in 1..<texts.count {
        if kinds[i] == .text, !wordLikes[i],
           isEscapedQuoteClusterSegment(texts[i]),
           kinds[i - 1] == .text {
            texts[i - 1] += texts[i]
            wordLikes[i - 1] = wordLikes[i - 1] || wordLikes[i]
            texts[i] = ""
        }
    }

    // Phase 3: Forward-sticky cluster carry (reverse pass)
    for i in stride(from: texts.count - 2, through: 0, by: -1) {
        if kinds[i] == .text, !wordLikes[i], isForwardStickyClusterSegment(texts[i]) {
            var j = i + 1
            while j < texts.count && texts[j].isEmpty { j += 1 }
            if j < texts.count, kinds[j] == .text {
                texts[j] = texts[i] + texts[j]
                starts[j] = starts[i]
                texts[i] = ""
            }
        }
    }

    var seg = MergedSegmentation(texts: texts, isWordLike: wordLikes, kinds: kinds, starts: starts)
    seg.compact()

    // Phase 4: Apply remaining merge rules in sequence
    seg = mergeGlueConnectedTextRuns(seg)
    seg = mergeUrlLikeRuns(seg)
    seg = mergeUrlQueryRuns(seg)
    seg = mergeNumericRuns(seg)
    seg = splitHyphenatedNumericRuns(seg)
    seg = mergeAsciiPunctuationChains(seg)
    seg = carryTrailingForwardStickyAcrossCJKBoundary(seg)

    // Phase 5: Split leading space+marks before Arabic text
    for i in 0..<(seg.count - 1) {
        guard let split = splitLeadingSpaceAndMarks(seg.texts[i]) else { continue }
        if (seg.kinds[i] != .space && seg.kinds[i] != .preservedSpace) || seg.kinds[i + 1] != .text {
            continue
        }
        if !containsArabicScript(seg.texts[i + 1]) { continue }

        seg.texts[i] = split.space
        seg.isWordLike[i] = false
        seg.texts[i + 1] = split.marks + seg.texts[i + 1]
        seg.starts[i + 1] = seg.starts[i] + split.space.utf16.count
    }

    return seg
}

// MARK: - Chunk Compilation

private func compileAnalysisChunks(_ seg: MergedSegmentation, whiteSpace: WhiteSpaceMode) -> [AnalysisChunk] {
    guard seg.count > 0 else { return [] }

    // Normal mode: one chunk covering everything
    if whiteSpace == .normal {
        return [AnalysisChunk(
            startSegmentIndex: 0,
            endSegmentIndex: seg.count,
            consumedEndSegmentIndex: seg.count
        )]
    }

    // Pre-wrap mode: split at hard breaks
    var chunks: [AnalysisChunk] = []
    var chunkStart = 0

    for i in 0..<seg.count {
        if seg.kinds[i] == .hardBreak {
            chunks.append(AnalysisChunk(
                startSegmentIndex: chunkStart,
                endSegmentIndex: i,
                consumedEndSegmentIndex: i + 1
            ))
            chunkStart = i + 1
        }
    }

    if chunkStart < seg.count {
        chunks.append(AnalysisChunk(
            startSegmentIndex: chunkStart,
            endSegmentIndex: seg.count,
            consumedEndSegmentIndex: seg.count
        ))
    }

    return chunks
}
