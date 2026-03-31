/// Classification of how a text segment participates in line breaking.
///
/// Each segment produced by the analysis phase carries one of these kinds,
/// which the line breaker uses to decide where lines can wrap.
public enum SegmentBreakKind: UInt8, Sendable {
    /// Regular word text — not a break opportunity by itself.
    case text

    /// Collapsible space (white-space: normal). Hangs past line edge.
    case space

    /// Preserved space (white-space: pre-wrap). Visible, but still a break opportunity.
    case preservedSpace

    /// Tab character. Width computed dynamically from tab stops.
    case tab

    /// Non-breaking glue (NBSP U+00A0, NNBSP U+202F, WJ U+2060).
    /// Visible content that prevents wrapping.
    case glue

    /// Zero-width break opportunity (ZWSP U+200B).
    /// Invisible, but allows line breaking.
    case zeroWidthBreak

    /// Soft hyphen (SHY U+00AD). Invisible unless chosen as a break point,
    /// in which case a visible `-` appears at end of line.
    case softHyphen

    /// Hard break (newline in pre-wrap mode). Forces a new line.
    case hardBreak
}

extension SegmentBreakKind {
    /// Whether the line breaker can break after this segment.
    var canBreakAfter: Bool {
        switch self {
        case .space, .preservedSpace, .tab, .zeroWidthBreak, .softHyphen:
            return true
        case .text, .glue, .hardBreak:
            return false
        }
    }

    /// Whether this is a simple collapsible space.
    var isSimpleCollapsibleSpace: Bool {
        self == .space
    }
}
