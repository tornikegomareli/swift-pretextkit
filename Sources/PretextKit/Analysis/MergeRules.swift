import Foundation

// MARK: - Segment Classification Helpers

/// Additional kinsoku/sticky sets not in UnicodeData.swift

private let forwardStickyGlueScalars: Set<Unicode.Scalar> = [
    "'", "\u{2018}", // ' and '
]

private let arabicNoSpaceTrailingPunctuation: Set<Unicode.Scalar> = [
    ":", ".", "\u{060C}", "\u{061B}",
]

private let myanmarMedialGlueScalars: Set<Unicode.Scalar> = [
    "\u{104F}",
]

private let closingQuoteChars: Set<Unicode.Scalar> = [
    "\"", "\u{2019}", "\u{201D}", "\u{00BB}", "\u{203A}",
    "\u{300D}", "\u{300F}", "\u{3011}", "\u{300B}", "\u{3009}", "\u{3015}", "\u{FF09}",
]

private let numericJoinerChars: Set<Unicode.Scalar> = [
    ":", "-", "/", "\u{00D7}", ",", ".", "+",
    "\u{2013}", // en dash
    "\u{2014}", // em dash
]

// MARK: - Segment Predicate Helpers

func isLeftStickyPunctuationSegment(_ segment: String) -> Bool {
    if isEscapedQuoteClusterSegment(segment) { return true }
    var sawPunctuation = false
    for scalar in segment.unicodeScalars {
        if leftStickyPunctuation.contains(scalar) {
            sawPunctuation = true
            continue
        }
        if sawPunctuation && isCombiningMark(scalar) { continue }
        return false
    }
    return sawPunctuation
}

func isCJKLineStartProhibitedSegment(_ segment: String) -> Bool {
    guard !segment.isEmpty else { return false }
    for scalar in segment.unicodeScalars {
        if !kinsokuStartScalars.contains(scalar) && !leftStickyPunctuation.contains(scalar) {
            return false
        }
    }
    return true
}

func isForwardStickyClusterSegment(_ segment: String) -> Bool {
    if isEscapedQuoteClusterSegment(segment) { return true }
    guard !segment.isEmpty else { return false }
    for scalar in segment.unicodeScalars {
        if !kinsokuEndScalars.contains(scalar)
            && !forwardStickyGlueScalars.contains(scalar)
            && !isCombiningMark(scalar) {
            return false
        }
    }
    return true
}

func isEscapedQuoteClusterSegment(_ segment: String) -> Bool {
    var sawQuote = false
    for scalar in segment.unicodeScalars {
        if scalar == "\\" || isCombiningMark(scalar) { continue }
        if kinsokuEndScalars.contains(scalar)
            || leftStickyPunctuation.contains(scalar)
            || forwardStickyGlueScalars.contains(scalar) {
            sawQuote = true
            continue
        }
        return false
    }
    return sawQuote
}

func endsWithArabicNoSpacePunctuation(_ segment: String) -> Bool {
    guard !segment.isEmpty, containsArabicScript(segment) else { return false }
    guard let last = segment.unicodeScalars.last else { return false }
    return arabicNoSpaceTrailingPunctuation.contains(last)
}

func endsWithMyanmarMedialGlue(_ segment: String) -> Bool {
    guard let last = segment.unicodeScalars.last else { return false }
    return myanmarMedialGlueScalars.contains(last)
}

func isRepeatedSingleCharRun(_ segment: String, char: String) -> Bool {
    guard !segment.isEmpty, !char.isEmpty else { return false }
    let target = char.unicodeScalars.first!
    for scalar in segment.unicodeScalars {
        if scalar != target { return false }
    }
    return true
}

func splitLeadingSpaceAndMarks(_ segment: String) -> (space: String, marks: String)? {
    guard segment.utf16.count >= 2 else { return nil }
    guard segment.unicodeScalars.first == " " else { return nil }
    let marks = String(segment.dropFirst())
    let allMarks = marks.unicodeScalars.allSatisfy { isCombiningMark($0) }
    guard allMarks else { return nil }
    return (" ", marks)
}

func splitTrailingForwardStickyCluster(_ text: String) -> (head: String, tail: String)? {
    let chars = Array(text.unicodeScalars)
    var splitIndex = chars.count

    while splitIndex > 0 {
        let ch = chars[splitIndex - 1]
        if isCombiningMark(ch) { splitIndex -= 1; continue }
        if kinsokuEndScalars.contains(ch) || forwardStickyGlueScalars.contains(ch) {
            splitIndex -= 1; continue
        }
        break
    }

    guard splitIndex > 0, splitIndex < chars.count else { return nil }
    let head = String(String.UnicodeScalarView(chars[..<splitIndex]))
    let tail = String(String.UnicodeScalarView(chars[splitIndex...]))
    return (head, tail)
}

// MARK: - Text Run Boundary

private func isTextRunBoundary(_ kind: SegmentBreakKind) -> Bool {
    kind == .space || kind == .preservedSpace || kind == .zeroWidthBreak || kind == .hardBreak
}

// MARK: - URL Merging

private func isUrlSchemeSegment(_ text: String) -> Bool {
    guard text.hasSuffix(":") else { return false }
    let prefix = text.dropLast()
    guard !prefix.isEmpty else { return false }
    return prefix.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "+" || $0 == "." || $0 == "-") }
}

private func isUrlLikeRunStart(_ seg: MergedSegmentation, index: Int) -> Bool {
    let text = seg.texts[index]
    if text.hasPrefix("www.") { return true }
    if isUrlSchemeSegment(text),
       index + 1 < seg.count,
       seg.kinds[index + 1] == .text,
       seg.texts[index + 1] == "//" {
        return true
    }
    return false
}

private func isUrlQueryBoundarySegment(_ text: String) -> Bool {
    text.contains("?") && (text.contains("://") || text.hasPrefix("www."))
}

func mergeUrlLikeRuns(_ seg: MergedSegmentation) -> MergedSegmentation {
    var result = seg
    for i in 0..<result.count {
        guard result.kinds[i] == .text, isUrlLikeRunStart(result, index: i) else { continue }
        var j = i + 1
        while j < result.count, !isTextRunBoundary(result.kinds[j]) {
            result.texts[i] += result.texts[j]
            result.isWordLike[i] = true
            let endsQuery = result.texts[j].contains("?")
            result.texts[j] = ""
            j += 1
            if endsQuery { break }
        }
    }
    result.compact()
    return result
}

func mergeUrlQueryRuns(_ seg: MergedSegmentation) -> MergedSegmentation {
    var texts: [String] = []
    var wordLikes: [Bool] = []
    var kinds: [SegmentBreakKind] = []
    var starts: [Int] = []

    var i = 0
    while i < seg.count {
        let text = seg.texts[i]
        texts.append(text)
        wordLikes.append(seg.isWordLike[i])
        kinds.append(seg.kinds[i])
        starts.append(seg.starts[i])

        if isUrlQueryBoundarySegment(text) {
            let next = i + 1
            if next < seg.count, !isTextRunBoundary(seg.kinds[next]) {
                var queryText = ""
                let queryStart = seg.starts[next]
                var j = next
                while j < seg.count, !isTextRunBoundary(seg.kinds[j]) {
                    queryText += seg.texts[j]
                    j += 1
                }
                if !queryText.isEmpty {
                    texts.append(queryText)
                    wordLikes.append(true)
                    kinds.append(.text)
                    starts.append(queryStart)
                    i = j
                    continue
                }
            }
        }
        i += 1
    }

    return MergedSegmentation(texts: texts, isWordLike: wordLikes, kinds: kinds, starts: starts)
}

// MARK: - Numeric Run Merging

private func segmentContainsDecimalDigit(_ text: String) -> Bool {
    text.unicodeScalars.contains { isDecimalDigit($0) }
}

private func isNumericRunSegment(_ text: String) -> Bool {
    guard !text.isEmpty else { return false }
    for scalar in text.unicodeScalars {
        if isDecimalDigit(scalar) || numericJoinerChars.contains(scalar) { continue }
        return false
    }
    return true
}

func mergeNumericRuns(_ seg: MergedSegmentation) -> MergedSegmentation {
    var texts: [String] = []
    var wordLikes: [Bool] = []
    var kinds: [SegmentBreakKind] = []
    var starts: [Int] = []

    var i = 0
    while i < seg.count {
        let text = seg.texts[i]
        let kind = seg.kinds[i]

        if kind == .text, isNumericRunSegment(text), segmentContainsDecimalDigit(text) {
            var merged = text
            var j = i + 1
            while j < seg.count, seg.kinds[j] == .text, isNumericRunSegment(seg.texts[j]) {
                merged += seg.texts[j]
                j += 1
            }
            texts.append(merged)
            wordLikes.append(true)
            kinds.append(.text)
            starts.append(seg.starts[i])
            i = j
            continue
        }

        texts.append(text)
        wordLikes.append(seg.isWordLike[i])
        kinds.append(kind)
        starts.append(seg.starts[i])
        i += 1
    }

    return MergedSegmentation(texts: texts, isWordLike: wordLikes, kinds: kinds, starts: starts)
}

// MARK: - Hyphenated Numeric Splitting

func splitHyphenatedNumericRuns(_ seg: MergedSegmentation) -> MergedSegmentation {
    var texts: [String] = []
    var wordLikes: [Bool] = []
    var kinds: [SegmentBreakKind] = []
    var starts: [Int] = []

    for i in 0..<seg.count {
        let text = seg.texts[i]
        if seg.kinds[i] == .text, text.contains("-") {
            let parts = text.split(separator: "-", omittingEmptySubsequences: false).map(String.init)
            var shouldSplit = parts.count > 1
            if shouldSplit {
                for part in parts {
                    if part.isEmpty || !segmentContainsDecimalDigit(part) || !isNumericRunSegment(part) {
                        shouldSplit = false
                        break
                    }
                }
            }

            if shouldSplit {
                var offset = 0
                for (j, part) in parts.enumerated() {
                    let splitText = j < parts.count - 1 ? part + "-" : part
                    texts.append(splitText)
                    wordLikes.append(true)
                    kinds.append(.text)
                    starts.append(seg.starts[i] + offset)
                    offset += splitText.utf16.count
                }
                continue
            }
        }

        texts.append(text)
        wordLikes.append(seg.isWordLike[i])
        kinds.append(seg.kinds[i])
        starts.append(seg.starts[i])
    }

    return MergedSegmentation(texts: texts, isWordLike: wordLikes, kinds: kinds, starts: starts)
}

// MARK: - ASCII Punctuation Chain Merging

private func isAsciiPunctuationChainSegment(_ text: String) -> Bool {
    guard !text.isEmpty else { return false }
    for ch in text {
        if ch.isASCII && (ch.isLetter || ch.isNumber || ch == "_" || ch == "," || ch == ":" || ch == ";") {
            continue
        }
        return false
    }
    return true
}

private func hasTrailingAsciiPunctuationJoiners(_ text: String) -> Bool {
    guard let last = text.last else { return false }
    return last == "," || last == ":" || last == ";"
}

func mergeAsciiPunctuationChains(_ seg: MergedSegmentation) -> MergedSegmentation {
    var texts: [String] = []
    var wordLikes: [Bool] = []
    var kinds: [SegmentBreakKind] = []
    var starts: [Int] = []

    var i = 0
    while i < seg.count {
        let text = seg.texts[i]
        let kind = seg.kinds[i]
        let wordLike = seg.isWordLike[i]

        if kind == .text, wordLike, isAsciiPunctuationChainSegment(text) {
            var merged = text
            var j = i + 1

            while hasTrailingAsciiPunctuationJoiners(merged),
                  j < seg.count,
                  seg.kinds[j] == .text,
                  seg.isWordLike[j],
                  isAsciiPunctuationChainSegment(seg.texts[j]) {
                merged += seg.texts[j]
                j += 1
            }

            texts.append(merged)
            wordLikes.append(true)
            kinds.append(.text)
            starts.append(seg.starts[i])
            i = j
            continue
        }

        texts.append(text)
        wordLikes.append(wordLike)
        kinds.append(kind)
        starts.append(seg.starts[i])
        i += 1
    }

    return MergedSegmentation(texts: texts, isWordLike: wordLikes, kinds: kinds, starts: starts)
}

// MARK: - Glue-Connected Text Run Merging

func mergeGlueConnectedTextRuns(_ seg: MergedSegmentation) -> MergedSegmentation {
    var texts: [String] = []
    var wordLikes: [Bool] = []
    var kinds: [SegmentBreakKind] = []
    var starts: [Int] = []

    var read = 0
    while read < seg.count {
        var text = seg.texts[read]
        var wordLike = seg.isWordLike[read]
        var kind = seg.kinds[read]
        var start = seg.starts[read]

        if kind == .glue {
            var glueText = text
            let glueStart = start
            read += 1
            while read < seg.count, seg.kinds[read] == .glue {
                glueText += seg.texts[read]
                read += 1
            }

            if read < seg.count, seg.kinds[read] == .text {
                text = glueText + seg.texts[read]
                wordLike = seg.isWordLike[read]
                kind = .text
                start = glueStart
                read += 1
            } else {
                texts.append(glueText)
                wordLikes.append(false)
                kinds.append(.glue)
                starts.append(glueStart)
                continue
            }
        } else {
            read += 1
        }

        if kind == .text {
            while read < seg.count, seg.kinds[read] == .glue {
                var glueText = ""
                while read < seg.count, seg.kinds[read] == .glue {
                    glueText += seg.texts[read]
                    read += 1
                }
                if read < seg.count, seg.kinds[read] == .text {
                    text += glueText + seg.texts[read]
                    wordLike = wordLike || seg.isWordLike[read]
                    read += 1
                    continue
                }
                text += glueText
            }
        }

        texts.append(text)
        wordLikes.append(wordLike)
        kinds.append(kind)
        starts.append(start)
    }

    return MergedSegmentation(texts: texts, isWordLike: wordLikes, kinds: kinds, starts: starts)
}

// MARK: - CJK Forward-Sticky Carry

func carryTrailingForwardStickyAcrossCJKBoundary(_ seg: MergedSegmentation) -> MergedSegmentation {
    var result = seg
    for i in 0..<(result.count - 1) {
        guard result.kinds[i] == .text, result.kinds[i + 1] == .text else { continue }
        guard isCJK(result.texts[i]), isCJK(result.texts[i + 1]) else { continue }

        guard let split = splitTrailingForwardStickyCluster(result.texts[i]) else { continue }
        result.texts[i] = split.head
        result.texts[i + 1] = split.tail + result.texts[i + 1]
        result.starts[i + 1] = result.starts[i] + split.head.utf16.count
    }
    return result
}
