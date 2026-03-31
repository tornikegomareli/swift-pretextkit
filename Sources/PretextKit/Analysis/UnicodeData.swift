import Foundation

// MARK: - CJK Detection

/// Returns true if the string contains any CJK ideograph, kana, or hangul character.
///
/// Covers: CJK Unified Ideographs, Extensions A–G, Compatibility Ideographs,
/// CJK Symbols, Hiragana, Katakana, Hangul Syllables, Fullwidth Forms.
func isCJK(_ s: String) -> Bool {
    for scalar in s.unicodeScalars {
        if isCJKScalar(scalar) {
            return true
        }
    }
    return false
}

func isCJKScalar(_ scalar: Unicode.Scalar) -> Bool {
    let c = scalar.value
    return (c >= 0x4E00 && c <= 0x9FFF)       // CJK Unified Ideographs
        || (c >= 0x3400 && c <= 0x4DBF)       // CJK Extension A
        || (c >= 0x20000 && c <= 0x2A6DF)     // CJK Extension B
        || (c >= 0x2A700 && c <= 0x2B73F)     // CJK Extension C
        || (c >= 0x2B740 && c <= 0x2B81F)     // CJK Extension D
        || (c >= 0x2B820 && c <= 0x2CEAF)     // CJK Extension E
        || (c >= 0x2CEB0 && c <= 0x2EBEF)     // CJK Extension F
        || (c >= 0x30000 && c <= 0x3134F)     // CJK Extension G
        || (c >= 0xF900 && c <= 0xFAFF)       // CJK Compatibility Ideographs
        || (c >= 0x2F800 && c <= 0x2FA1F)     // CJK Compatibility Supplement
        || (c >= 0x3000 && c <= 0x303F)       // CJK Symbols and Punctuation
        || (c >= 0x3040 && c <= 0x309F)       // Hiragana
        || (c >= 0x30A0 && c <= 0x30FF)       // Katakana
        || (c >= 0xAC00 && c <= 0xD7AF)       // Hangul Syllables
        || (c >= 0xFF00 && c <= 0xFFEF)       // Halfwidth and Fullwidth Forms
}

// MARK: - Kinsoku Sets

/// Characters prohibited at the start of a line (kinsoku-start / line-start prohibited).
/// Closing brackets, periods, commas, and other trailing punctuation in CJK.
let kinsokuStartScalars: Set<Unicode.Scalar> = [
    "\u{FF0C}",  // ，
    "\u{FF0E}",  // ．
    "\u{FF01}",  // ！
    "\u{FF1A}",  // ：
    "\u{FF1B}",  // ；
    "\u{FF1F}",  // ？
    "\u{3001}",  // 、
    "\u{3002}",  // 。
    "\u{30FB}",  // ・
    "\u{FF09}",  // ）
    "\u{3015}",  // 〕
    "\u{FF3D}",  // ］
    "\u{FF5D}",  // ｝
    "\u{3009}",  // 〉
    "\u{300B}",  // 》
    "\u{300D}",  // 」
    "\u{300F}",  // 』
    "\u{3011}",  // 】
    "\u{FF5E}",  // ～
    "\u{2019}",  // '
    "\u{201D}",  // "
    "\u{2026}",  // …
    "\u{3005}",  // 々 (CJK ideographic iteration mark)
    "\u{309D}",  // ゝ (hiragana iteration mark)
    "\u{309E}",  // ゞ (hiragana voiced iteration mark)
    "\u{30FD}",  // ヽ (katakana iteration mark)
    "\u{30FE}",  // ヾ (katakana voiced iteration mark)
    "\u{FF05}",  // ％
    "\u{00B0}",  // °
    "\u{2032}",  // ′
    "\u{2033}",  // ″
]

/// Characters prohibited at the end of a line (kinsoku-end / line-end prohibited).
/// Opening brackets and similar opening punctuation in CJK.
let kinsokuEndScalars: Set<Unicode.Scalar> = [
    "\u{FF08}",  // （
    "\u{3014}",  // 〔
    "\u{FF3B}",  // ［
    "\u{FF5B}",  // ｛
    "\u{3008}",  // 〈
    "\u{300A}",  // 《
    "\u{300C}",  // 「
    "\u{300E}",  // 『
    "\u{3010}",  // 【
    "\u{2018}",  // '
    "\u{201C}",  // "
]

/// Left-sticky (trailing) punctuation that merges with the preceding segment.
let leftStickyPunctuation: Set<Unicode.Scalar> = [
    ".", ",", ":", "!", "?", ";", "%",
    ")", "]", "}",
    "\u{2019}", // '
    "\u{201D}", // "
    "'", "\"",
]

// MARK: - Character Classification

/// Whether a scalar is an Arabic script character.
func isArabicScript(_ scalar: Unicode.Scalar) -> Bool {
    let v = scalar.value
    return (v >= 0x0600 && v <= 0x06FF)     // Arabic
        || (v >= 0x0750 && v <= 0x077F)     // Arabic Supplement
        || (v >= 0x08A0 && v <= 0x08FF)     // Arabic Extended-A
        || (v >= 0xFB50 && v <= 0xFDFF)     // Arabic Presentation Forms-A
        || (v >= 0xFE70 && v <= 0xFEFF)     // Arabic Presentation Forms-B
}

/// Whether a string contains any Arabic script character.
func containsArabicScript(_ text: String) -> Bool {
    text.unicodeScalars.contains { isArabicScript($0) }
}

/// Whether a scalar is a Unicode combining mark.
func isCombiningMark(_ scalar: Unicode.Scalar) -> Bool {
    scalar.properties.generalCategory == .nonspacingMark
        || scalar.properties.generalCategory == .spacingMark
        || scalar.properties.generalCategory == .enclosingMark
}

/// Whether a scalar is a decimal digit (any script).
func isDecimalDigit(_ scalar: Unicode.Scalar) -> Bool {
    scalar.properties.numericType == .decimal
}

/// Check if a character is a special break character.
func classifyBreakKind(_ scalar: Unicode.Scalar) -> SegmentBreakKind {
    switch scalar {
    case " ":
        return .space
    case "\t":
        return .tab
    case "\n", "\r", "\u{000C}": // LF, CR, FF
        return .hardBreak
    case "\u{00A0}", "\u{202F}", "\u{2060}", "\u{FEFF}": // NBSP, NNBSP, WJ, ZWNBSP
        return .glue
    case "\u{200B}": // ZWSP
        return .zeroWidthBreak
    case "\u{00AD}": // SHY
        return .softHyphen
    default:
        return .text
    }
}

/// Whether the character closes a quote (right single/double quote, ASCII quotes).
func isClosingQuote(_ scalar: Unicode.Scalar) -> Bool {
    switch scalar {
    case "\u{2019}", "\u{201D}", "'", "\"":
        return true
    default:
        return false
    }
}

/// Whether the character opens a quote.
func isOpeningQuote(_ scalar: Unicode.Scalar) -> Bool {
    switch scalar {
    case "\u{2018}", "\u{201C}":
        return true
    default:
        return false
    }
}

/// Whether the string ends with a closing quote character.
func endsWithClosingQuote(_ text: String) -> Bool {
    guard let last = text.unicodeScalars.last else { return false }
    return isClosingQuote(last)
}
