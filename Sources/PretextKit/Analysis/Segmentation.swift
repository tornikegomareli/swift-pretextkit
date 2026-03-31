import Foundation

// MARK: - Word Segmentation via CFStringTokenizer

/// A single piece from word segmentation + break-kind classification.
struct SegmentationPiece {
    var text: String
    var isWordLike: Bool
    var kind: SegmentBreakKind
    var start: Int // UTF-16 offset into normalized string
}

/// Segments text into words using CFStringTokenizer, then classifies
/// each character within segments by break kind.
func segmentWords(_ text: String, locale: Locale?) -> [(text: String, isWordLike: Bool, utf16Start: Int)] {
    let cfStr = text as CFString
    let length = CFStringGetLength(cfStr)
    guard length > 0 else { return [] }

    let cfLocale = locale.map { $0 as CFLocale }
    let tokenizer = CFStringTokenizerCreate(
        kCFAllocatorDefault,
        cfStr,
        CFRangeMake(0, length),
        kCFStringTokenizerUnitWord,
        cfLocale
    )

    var results: [(text: String, isWordLike: Bool, utf16Start: Int)] = []
    var lastEnd = 0

    while true {
        let tokenType = CFStringTokenizerAdvanceToNextToken(tokenizer)
        if tokenType == [] { break }

        let range = CFStringTokenizerGetCurrentTokenRange(tokenizer)

        // Gap before this token = non-word segment
        if range.location > lastEnd {
            let gapRange = CFRange(location: lastEnd, length: range.location - lastEnd)
            let gapStr = CFStringCreateWithSubstring(kCFAllocatorDefault, cfStr, gapRange) as String
            results.append((text: gapStr, isWordLike: false, utf16Start: lastEnd))
        }

        // The token itself = word-like segment
        let tokenStr = CFStringCreateWithSubstring(kCFAllocatorDefault, cfStr, range) as String
        results.append((text: tokenStr, isWordLike: true, utf16Start: range.location))
        lastEnd = range.location + range.length
    }

    // Trailing non-word content
    if lastEnd < length {
        let gapRange = CFRange(location: lastEnd, length: length - lastEnd)
        let gapStr = CFStringCreateWithSubstring(kCFAllocatorDefault, cfStr, gapRange) as String
        results.append((text: gapStr, isWordLike: false, utf16Start: lastEnd))
    }

    return results
}

// MARK: - Break Kind Classification

/// Splits a single word segment into sub-pieces based on per-character break kind.
/// E.g., "hello\u{00AD}world" splits into ["hello", SHY, "world"].
func splitSegmentByBreakKind(
    _ segment: String,
    isWordLike: Bool,
    start: Int,
    whiteSpace: WhiteSpaceMode
) -> [SegmentationPiece] {
    var pieces: [SegmentationPiece] = []
    var currentKind: SegmentBreakKind?
    var currentText = ""
    var currentStart = start
    var currentWordLike = false
    var offset = 0

    for scalar in segment.unicodeScalars {
        let kind = classifyBreakKindForMode(scalar, whiteSpace: whiteSpace)
        let wordLike = kind == .text && isWordLike

        if let prevKind = currentKind, kind == prevKind, wordLike == currentWordLike {
            currentText.unicodeScalars.append(scalar)
            offset += Int(scalar.utf16.count)
            continue
        }

        if currentKind != nil {
            pieces.append(SegmentationPiece(
                text: currentText,
                isWordLike: currentWordLike,
                kind: currentKind!,
                start: currentStart
            ))
        }

        currentKind = kind
        currentText = String(scalar)
        currentStart = start + offset
        currentWordLike = wordLike
        offset += Int(scalar.utf16.count)
    }

    if let kind = currentKind {
        pieces.append(SegmentationPiece(
            text: currentText,
            isWordLike: currentWordLike,
            kind: kind,
            start: currentStart
        ))
    }

    return pieces
}

/// Classify a scalar's break kind, respecting white-space mode.
private func classifyBreakKindForMode(_ scalar: Unicode.Scalar, whiteSpace: WhiteSpaceMode) -> SegmentBreakKind {
    if whiteSpace == .preWrap {
        switch scalar {
        case " ": return .preservedSpace
        case "\t": return .tab
        case "\n": return .hardBreak
        default: break
        }
    }
    return classifyBreakKind(scalar)
}
