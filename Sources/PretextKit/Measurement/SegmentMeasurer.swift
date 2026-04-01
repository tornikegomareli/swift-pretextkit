import CoreText
import Foundation

/// Measures text segment widths using CoreText's CTLine.
///
/// Reuses a mutable attributed string to reduce allocation overhead
/// during the measurement phase. Each measurer is bound to a single font.
///
/// Thread safety: Each measurer instance should be used from a single thread.
/// The shared `SegmentMetricsCache` handles cross-thread coordination.
final class SegmentMeasurer {
    private let font: CTFont
    private let mutableAttrString: CFMutableAttributedString

    init(font: CTFont) {
        self.font = font
        self.mutableAttrString = CFAttributedStringCreateMutable(kCFAllocatorDefault, 0)
        CFAttributedStringReplaceString(mutableAttrString, CFRangeMake(0, 0), " " as CFString)
        CFAttributedStringSetAttribute(mutableAttrString, CFRangeMake(0, 1), kCTFontAttributeName, font)
    }

    /// Measures the width of a text segment using CTLine.
    func measureWidth(_ text: String) -> Float {
        let cfStr = text as CFString
        let len = CFStringGetLength(cfStr)
        let currentLen = CFAttributedStringGetLength(mutableAttrString)
        CFAttributedStringReplaceString(mutableAttrString, CFRangeMake(0, currentLen), cfStr)
        CFAttributedStringSetAttribute(mutableAttrString, CFRangeMake(0, len), kCTFontAttributeName, font)
        let line = CTLineCreateWithAttributedString(mutableAttrString)
        return Float(CTLineGetTypographicBounds(line, nil, nil, nil))
    }

    /// Measures the width of a visible hyphen character in this font.
    func measureHyphenWidth() -> Float {
        measureWidth("-")
    }

    /// Measures the width of a space character in this font.
    func measureSpaceWidth() -> Float {
        measureWidth(" ")
    }

    /// Measures per-grapheme widths for a segment (for overflow-wrap breaking).
    ///
    /// Pre-allocates the result array to avoid incremental growth.
    func measureGraphemeWidths(_ text: String) -> ContiguousArray<Float> {
        let count = text.count
        var widths = ContiguousArray<Float>()
        widths.reserveCapacity(count)
        for char in text {
            widths.append(measureWidth(String(char)))
        }
        return widths
    }
}
