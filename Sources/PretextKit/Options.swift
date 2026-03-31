@preconcurrency import CoreText
#if canImport(UIKit)
import UIKit
#endif

// MARK: - White Space Mode

/// Controls how whitespace is handled during text analysis.
///
/// Mirrors the CSS `white-space` property behavior:
/// - `.normal`: Collapses runs of whitespace to a single space, trims edges.
/// - `.preWrap`: Preserves ordinary spaces, tabs, and hard breaks.
public enum WhiteSpaceMode: Sendable {
    case normal
    case preWrap
}

// MARK: - Prepare Options

/// Options for the `prepare()` function.
public struct PrepareOptions: Sendable {
    /// How whitespace should be handled. Defaults to `.normal`.
    public var whiteSpace: WhiteSpaceMode

    public init(whiteSpace: WhiteSpaceMode = .normal) {
        self.whiteSpace = whiteSpace
    }
}

// MARK: - Font Descriptor

/// A lightweight, hashable wrapper around `CTFont` for cache keying and thread-safe use.
///
/// Unlike the JS version which uses a CSS font string like `"16px Inter"`,
/// iOS uses `CTFont` / `UIFont` objects directly.
public struct FontDescriptor: Hashable, Sendable {
    /// The underlying CoreText font.
    public let font: CTFont

    /// Cache key string: `"FontName|Size"`.
    public let cacheKey: String

    /// The font size in points.
    public let size: CGFloat

    public init(_ font: CTFont) {
        self.font = font
        let name = CTFontCopyPostScriptName(font) as String
        let size = CTFontGetSize(font)
        self.size = size
        self.cacheKey = "\(name)|\(size)"
    }

    #if canImport(UIKit)
    public init(_ uiFont: UIFont) {
        self.init(uiFont as CTFont)
    }
    #endif

    public static func == (lhs: FontDescriptor, rhs: FontDescriptor) -> Bool {
        lhs.cacheKey == rhs.cacheKey
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(cacheKey)
    }
}
