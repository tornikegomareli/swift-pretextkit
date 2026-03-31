#if canImport(UIKit)
import UIKit
import CoreText

/// A UIView that renders text using precomputed `PreparedText` layout.
///
/// Unlike UILabel, `PretextLabel` never triggers UIKit's layout engine for
/// text measurement. `sizeThatFits(_:)` uses pure arithmetic over cached
/// segment widths — sub-microsecond cost regardless of text length.
///
/// Usage:
/// ```swift
/// let label = PretextLabel()
/// label.font = UIFont.systemFont(ofSize: 16)
/// label.lineHeight = 22
/// label.text = "Hello, world!"  // Calls prepare() internally
/// ```
///
/// For maximum performance (e.g., in collection view cells), pre-compute
/// the `PreparedTextWithSegments` on a background thread and assign it
/// directly via `preparedText`.
public final class PretextLabel: UIView {

    // MARK: - Public Properties

    /// The font used for text measurement and rendering.
    /// Changing this re-prepares the text.
    public var font: UIFont = .systemFont(ofSize: 16) {
        didSet {
            guard font != oldValue else { return }
            fontDescriptor = FontDescriptor(font)
            reprepare()
        }
    }

    /// The line height used for layout calculations.
    public var lineHeight: CGFloat = 20 {
        didSet {
            guard lineHeight != oldValue else { return }
            invalidateIntrinsicContentSize()
            setNeedsDisplay()
        }
    }

    /// The text color for rendering.
    public var textColor: UIColor = .label {
        didSet { setNeedsDisplay() }
    }

    /// The text to display. Setting this calls `prepare()` synchronously.
    /// For background preparation, use `preparedText` directly.
    public var text: String? {
        didSet {
            guard text != oldValue else { return }
            reprepare()
        }
    }

    /// Directly set a pre-computed prepared text handle.
    /// Use this when you've prepared text on a background thread.
    public var preparedText: PreparedTextWithSegments? {
        didSet {
            invalidateIntrinsicContentSize()
            setNeedsDisplay()
        }
    }

    // MARK: - Private

    private var fontDescriptor: FontDescriptor

    // MARK: - Init

    public override init(frame: CGRect) {
        self.fontDescriptor = FontDescriptor(UIFont.systemFont(ofSize: 16))
        super.init(frame: frame)
        isOpaque = false
        contentMode = .redraw
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    // MARK: - Sizing

    /// Returns the height for a given width using pure arithmetic.
    /// No UIKit layout engine involved.
    public func heightForWidth(_ width: CGFloat) -> CGFloat {
        guard let prepared = preparedText else { return 0 }
        return PretextKit.layout(prepared, maxWidth: width, lineHeight: lineHeight).height
    }

    public override func sizeThatFits(_ size: CGSize) -> CGSize {
        guard let prepared = preparedText else { return .zero }
        let result = PretextKit.layout(prepared, maxWidth: size.width, lineHeight: lineHeight)
        return CGSize(width: size.width, height: result.height)
    }

    public override var intrinsicContentSize: CGSize {
        guard let prepared = preparedText else {
            return CGSize(width: UIView.noIntrinsicMetric, height: UIView.noIntrinsicMetric)
        }
        let result = PretextKit.layout(prepared, maxWidth: bounds.width, lineHeight: lineHeight)
        return CGSize(width: UIView.noIntrinsicMetric, height: result.height)
    }

    // MARK: - Rendering

    public override func draw(_ rect: CGRect) {
        guard let prepared = preparedText,
              let ctx = UIGraphicsGetCurrentContext() else { return }

        let linesResult = layoutWithLines(prepared, maxWidth: bounds.width, lineHeight: lineHeight)

        ctx.saveGState()
        // CoreText draws in a flipped coordinate system
        ctx.textMatrix = .identity
        ctx.translateBy(x: 0, y: bounds.height)
        ctx.scaleBy(x: 1, y: -1)

        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: textColor,
        ]

        for (i, line) in linesResult.lines.enumerated() {
            let attrStr = NSAttributedString(string: line.text, attributes: attrs)
            let ctLine = CTLineCreateWithAttributedString(attrStr as CFAttributedString)
            let y = bounds.height - (CGFloat(i) * lineHeight + font.ascender)
            ctx.textPosition = CGPoint(x: 0, y: y)
            CTLineDraw(ctLine, ctx)
        }

        ctx.restoreGState()
    }

    // MARK: - Private

    private func reprepare() {
        guard let text, !text.isEmpty else {
            preparedText = nil
            return
        }
        preparedText = prepareWithSegments(text, font: fontDescriptor)
    }
}
#endif
