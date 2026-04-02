# PretextKit

[![Swift 5.9+](https://img.shields.io/badge/Swift-5.9+-orange.svg)](https://swift.org)
[![iOS 16+](https://img.shields.io/badge/iOS-16%2B-blue.svg)](https://developer.apple.com/ios/)
[![macOS 13+](https://img.shields.io/badge/macOS-13%2B-blue.svg)](https://developer.apple.com/macos/)
[![SPM](https://img.shields.io/badge/SPM-compatible-green.svg)](https://swift.org/package-manager/)
[![License: MIT](https://img.shields.io/badge/License-MIT-lightgrey.svg)](LICENSE)

Swift port of [Cheng Lou's Pretext](https://github.com/chenglou/pretext) for Apple platforms.

https://github.com/user-attachments/assets/a765c4e8-5418-4f02-8bc8-251001c41e92

---

## Why

`UILabel.sizeThatFits`, `NSAttributedString.boundingRect`, and every other text measurement API on iOS calls CoreText from scratch every time — font tables, Unicode normalization, glyph shaping, line breaking. All of it, every call.

PretextKit does the expensive CoreText work once in `prepare()`, then answers any "how tall is this text at width X?" question with pure arithmetic in `layout()`. No font engine, no allocations, sub-microsecond.

Based on [Cheng Lou's insight](https://github.com/chenglou/pretext) (building on [Sebastian Markbage's text-layout](https://github.com/chenglou/text-layout)) that text shaping and line breaking are two separate problems — and only shaping is expensive.

## Install

```swift
// Package.swift
.package(url: "https://github.com/tornikegomareli/swift-pretextkit.git", from: "0.1.0")
```

---

## API

PretextKit serves two use cases, same as the [original](https://github.com/chenglou/pretext):

### 1. Measure text height without CoreText in the loop

```swift
import PretextKit

let font = FontDescriptor(.systemFont(ofSize: 16))

// One-time: segment, measure, cache
let prepared = prepare("AGI 春天到了. بدأت الرحلة 🚀", font: font)

// On every resize — just arithmetic, no CoreText
let result = layout(prepared, maxWidth: containerWidth, lineHeight: 22)
result.height     // 44.0
result.lineCount  // 2
```

`prepare()` is the expensive call — run it once per (text, font) pair. `layout()` is the cheap call — run it on every resize, rotation, or reflow. Don't re-run `prepare()` when only the width changes.

For textarea-like text where spaces, tabs, and newlines stay visible:

```swift
let prepared = prepare(text, font: font, options: PrepareOptions(whiteSpace: .preWrap))
```

### 2. Lay out lines yourself

Switch `prepare` to `prepareWithSegments`, then pick the API that fits:

**Get all lines at a fixed width:**

```swift
let prepared = prepareWithSegments(text, font: font)
let result = layoutWithLines(prepared, maxWidth: 320, lineHeight: 26)

for (i, line) in result.lines.enumerated() {
    let attrStr = NSAttributedString(string: line.text, attributes: [.font: uiFont])
    let ctLine = CTLineCreateWithAttributedString(attrStr as CFAttributedString)
    context.textPosition = CGPoint(x: 0, y: CGFloat(i) * 26)
    CTLineDraw(ctLine, context)
}
```

**Find the tightest container:**

```swift
var maxLineWidth: CGFloat = 0
walkLineRanges(prepared, maxWidth: 320) { line in
    maxLineWidth = max(maxLineWidth, line.width)
}
// maxLineWidth is now the minimum width that still fits all lines
```

**Flow text around obstacles**

```swift
var cursor = LayoutCursor.start
var y: CGFloat = 0

while let line = layoutNextLine(prepared, start: cursor, maxWidth: widthAtY(y)) {
    let attrStr = NSAttributedString(string: line.text, attributes: [.font: uiFont])
    let ctLine = CTLineCreateWithAttributedString(attrStr as CFAttributedString)
    context.textPosition = CGPoint(x: 0, y: y)
    CTLineDraw(ctLine, context)
    cursor = line.end
    y += 26
}
```

### API summary

| Function | Input | Output | Cost |
|----------|-------|--------|------|
| `prepare(text, font)` | String + font | `PreparedText` | ~0.04ms per text (CoreText) |
| `layout(prepared, maxWidth, lineHeight)` | PreparedText + width | height, lineCount | ~0.0001ms (arithmetic) |
| `prepareWithSegments(text, font)` | String + font | `PreparedTextWithSegments` | Same as prepare() |
| `layoutWithLines(prepared, maxWidth, lineHeight)` | Segments + width | lines with text/width | Arithmetic + string build |
| `walkLineRanges(prepared, maxWidth, onLine)` | Segments + width | line widths/cursors | Arithmetic only |
| `layoutNextLine(prepared, start, maxWidth)` | Segments + cursor + width | single line or nil | Arithmetic + string build |
| `clearCache()` | — | — | Frees measurement cache |
| `setLocale(locale)` | Locale? | — | Retargets word segmenter |

---

## UIKit

### Drop-in label

```swift
let label = PretextLabel()
label.font = .systemFont(ofSize: 16)
label.lineHeight = 22
label.text = "Hello, world!"
// sizeThatFits is now pure arithmetic — no CoreText in the loop
```

```swift
let prepared = prepareWithSegments(text, font: FontDescriptor(.systemFont(ofSize: 16)))
label.preparedText = prepared  // Skips re-preparation
```

### Collection view cell sizing

```swift
class MyDataSource: UICollectionViewDataSource, UICollectionViewDataSourcePrefetching {
    let sizingCache = PretextSizingCache()
    let font = FontDescriptor(.systemFont(ofSize: 16))

    func collectionView(_ cv: UICollectionView, prefetchItemsAt ips: [IndexPath]) {
        for ip in ips {
            sizingCache.prepare(items[ip.item].text, font: font, identifier: ip)
        }
    }

    func collectionView(_ cv: UICollectionView, layout: UICollectionViewLayout,
                        sizeForItemAt ip: IndexPath) -> CGSize {
        let h = sizingCache.height(for: ip, width: cellWidth, lineHeight: 22) ?? 44
        return CGSize(width: cellWidth, height: h)
    }

    func collectionView(_ cv: UICollectionView, cancelPrefetchingForItemsAt ips: [IndexPath]) {
        sizingCache.cancel(identifiers: ips)
    }
}
```

## SwiftUI

**Auto-sized text** (measures available width via GeometryReader, computes exact height):

```swift
let ctFont = CTFontCreateWithName("Georgia" as CFString, 16, nil)
let prepared = prepareWithSegments(text, font: FontDescriptor(ctFont))

PretextAutoSizedText(prepared: prepared, font: ctFont, lineHeight: 24)
```

**Parent-constrained text** (when the parent already provides a fixed size):

```swift
PretextText(prepared: prepared, font: ctFont, lineHeight: 24, textColor: .secondary)
    .frame(width: 300, height: 200)
```

**Size any view based on text layout:**

```swift
Color.clear
    .pretextFrame(prepared: myPrepared, lineHeight: 22)
```

---

## Font setup

On iOS/tvOS, wrap a `UIFont`:

```swift
let font = FontDescriptor(.systemFont(ofSize: 16))
let font = FontDescriptor(.preferredFont(forTextStyle: .body))
```

On macOS (or cross-platform code), use CoreText directly:

```swift
let ctFont = CTFontCreateWithName("Helvetica Neue" as CFString, 16, nil)
let font = FontDescriptor(ctFont)
```

## International text

CJK per-character breaking with kinsoku rules, Arabic RTL, Thai dictionary-based segmentation, emoji ZWJ sequences (`👨‍👩‍👧‍👦` stays intact), soft hyphens, NBSP glue, mixed-script paragraphs.

For text in languages that need locale context for word segmentation (Thai, Lao, Khmer, Myanmar):

```swift
setLocale(Locale(identifier: "th"))
let prepared = prepare(thaiText, font: font)
// Reset to system default when done
setLocale(nil)
```

## Cache management

The measurement cache is global and shared across all `prepare()` calls. Normally you never need to touch it, but:

```swift
// Free memory when fonts change dynamically or on memory warning
clearCache()

// setLocale() also clears the cache automatically
setLocale(Locale(identifier: "ja"))
```

## When to use PretextKit

**Good fit:** Virtual scrolling, collection/table view cell sizing, masonry layouts, text flowing around obstacles, any UI where the same text is re-measured at many widths (rotation, resize, reflow).

**Overkill:** A single static label that renders once, or text that changes every frame (you'd re-run `prepare()` each time, losing the benefit).

**Not supported:** Attributed strings with mixed fonts/sizes within a single text, rich text with inline images, or CSS modes beyond `normal` and `pre-wrap`.

## Caveats

Targets the common text configuration: word wrapping with break-word overflow (same as the original Pretext's `white-space: normal`, `word-break: normal`, `overflow-wrap: break-word`). Pre-wrap mode available for preserved whitespace.

---

## What changed in the Swift port

The core algorithm is a 1:1 port from the [original TypeScript](https://github.com/chenglou/pretext). Changes are platform-specific:

| Area | Original (TS) | Swift port |
|------|---------------|------------|
| Measurement | `canvas.measureText()` | `CTLine` + `CTLineGetTypographicBounds` |
| Segmentation | `Intl.Segmenter` | `CFStringTokenizer` |
| Thread safety | Single-threaded | `OSAllocatedUnfairLock` on shared cache |
| Engine profiles | Per-browser epsilon | Single CoreText epsilon (0.005) |
| Emoji correction | Canvas/DOM mismatch fix | Not needed (CoreText consistent) |
| Hot path | Array indexing | `withUnsafeBufferPointer` |

Not yet ported: bidi rendering metadata (`segLevels`) and URL-specific segmentation rules.

---

## Demo app

Interactive showcases included in the demo app target:

### Breaker
Breakout game — text reflows around ball, paddle, and word-bricks.

https://github.com/user-attachments/assets/08c9b23a-e61d-4865-a994-c4a5c3f71030

### Tetris
Falling tetrominoes swim in reflowing text.

https://github.com/user-attachments/assets/131df357-8707-4e28-ace5-cb9e70271ba4

### Bouncing Orbs
60fps physics with text flowing around moving obstacles.

https://github.com/user-attachments/assets/308d598a-35ce-4de5-a6a0-2fdec59935d4

### Shrinkwrap
Standard sizing vs binary-search minimum bubble width.

https://github.com/user-attachments/assets/d97ccb45-108c-4c23-aa2c-972a9baa391e

### Dynamic Layout
Draggable magazine elements with real-time reflow. Also compares PretextKit against CoreText, TextKit 1, TextKit 2, and UILabel — all rendering the same text around a draggable orb using their real APIs.

https://github.com/user-attachments/assets/aed86de0-6e13-49c4-a3c3-58ae48bd9df2

---

## Acknowledgment

Swift port of [Pretext](https://github.com/chenglou/pretext) by [Cheng Lou](https://github.com/chenglou), building on [Sebastian Markbage's text-layout](https://github.com/chenglou/text-layout). The two-phase architecture, segment model, merge rules, Unicode tables, and line-breaking algorithm are Cheng Lou's work. PretextKit adds CoreText measurement, UIKit/SwiftUI integration, and thread-safe caching for Apple platforms.

## License

MIT
