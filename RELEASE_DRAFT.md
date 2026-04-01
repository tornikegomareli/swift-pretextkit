v0.1.0 — Initial release

The problem:

UILabel.sizeThatFits, NSAttributedString.boundingRect, NSLayoutManager,
NSTextLayoutManager, and SwiftUI Text all depend on CoreText for glyph
shaping and measurement. Load font tables, normalize Unicode, shape glyphs
into positioned runs, determine line breaks from glyph advances, and compute
vertical positions. Every step depends on the previous one. Most steps
allocate. A single sizeThatFits call costs ~0.05ms. Multiply by 500
collection view cells reloading: 25ms of main-thread
work purely from text measurement. This is the dominant layout bottleneck
in mobile apps that display text at scale — chat apps, social feeds,
virtualized lists, document editors, any UI with dynamic text heights.

The architecture (from chenglou/pretext):

Cheng Lou's Pretext library (github.com/chenglou/pretext) identified that
text measurement has two distinct phases: shaping and breaking. Shaping
(converting characters to positioned glyphs) is genuinely expensive — it
requires font table lookups, Unicode normalization, script itemization, and
contextual glyph substitution. Breaking (deciding where lines end) is cheap.
Once you know the width of each word, line breaking is just arithmetic:
accumulate widths until you exceed the container width, then emit a break.
The entire history of text engines has coupled these two phases into a single
operation. Pretext decouples them.

PretextKit is a Swift port of that architecture for Apple platforms.

How it works:

prepare() walks the text once: segments it into words and break opportunities
via CFStringTokenizer, classifies each segment into one of eight break kinds
(text, collapsible space, preserved space, tab, non-breaking glue, zero-width
break opportunity, soft hyphen, hard break), applies 13+ preprocessing merge
rules for script-specific edge cases (Arabic no-space punctuation clusters,
CJK kinsoku line-start/end prohibitions, Myanmar medial glue, emoji ZWJ
sequence preservation, contextual escaped quotes, numeric/time ranges),
measures each segment via CTLine, and caches all widths in flat Float arrays
alongside break-kind metadata.

layout() then computes line breaks using only those cached arrays. It walks
segment widths with a single pointer, accumulating until overflow, tracking
pending break positions for backtracking, and handling overflow-wrap grapheme
breaking for words wider than the container. The hot-path arrays are accessed
via withUnsafeBufferPointer to eliminate Swift bounds checks. The entire
operation produces line count + height in sub-microsecond time. Zero CoreText
calls. Zero string work. Zero allocations. 500 texts reflow in 0.05ms total —
the same budget UILabel spends on a single measurement.

layoutNextLine() extends this to variable-width flows: each line can have a
different maxWidth, enabling text that flows around arbitrary obstacles
(images, pull quotes, game objects) at 60fps — something that was
architecturally impractical with UIKit's text stack.

What changed in the Swift port:

The core algorithm — segment identification, measurement caching, two-phase
prepare/layout, CJK grapheme splitting with kinsoku merging, and line
breaking — is a direct 1:1 port from the original TypeScript implementation.
The changes are platform-specific:

- Measurement: CTLine + CTLineGetTypographicBounds replaces canvas.measureText.
  A reusable CFMutableAttributedString reduces allocations during prepare().
- Segmentation: CFStringTokenizer replaces Intl.Segmenter. Both use the OS
  native word segmenter and produce identical boundaries.
- Thread safety: OSAllocatedUnfairLock protects the shared metrics cache.
  The original is single-threaded (browser main thread); Swift apps need
  concurrent prepare() calls from prefetch queues.
- Engine profile simplified: the original detects Safari vs Chrome vs Firefox
  and applies per-browser line-fit epsilon values and soft-hyphen timing rules.
  iOS has a single text engine (CoreText), so a fixed epsilon of 0.005 is used.
- Emoji correction removed: the original corrects for canvas vs DOM emoji width
  mismatches on macOS browsers. CoreText measures consistently, so no
  correction is needed.
- Hot-path optimization: the line walker uses withUnsafeBufferPointer for
  bounds-check-free array access, and all builder arrays use reserveCapacity
  to eliminate incremental reallocation.

Not yet ported: bidi rendering metadata (segLevels) for custom RTL rendering,
and URL-specific segmentation rules for cleaner URL line breaks. These are
tracked for future releases.

Core API:
- prepare() / prepareWithSegments() — one-time CoreText measurement
- layout() — sub-microsecond arithmetic reflow at any width
- layoutWithLines() / walkLineRanges() — rich line geometry
- layoutNextLine() — variable-width obstacle-aware text flow
- clearCache() / setLocale() — cache and locale management
- Full i18n: CJK with kinsoku, Arabic RTL, Thai segmentation, emoji ZWJ,
  soft hyphens, NBSP glue, mixed-script text

UIKit integration:
- PretextLabel — drop-in UILabel replacement with arithmetic sizeThatFits
- PretextSizingCache — thread-safe background prefetch + main-thread sizing
  for UICollectionView/UITableView cells

SwiftUI integration:
- PretextText — Canvas-based text rendering from prepared segments
- PretextAutoSizedText — GeometryReader-driven auto-sizing view
- pretextFrame() modifier — height prediction for any view

Demo app with 7 interactive showcases:
- Pretext Breaker (Breakout game — text flows around ball, paddle, word-bricks)
- Tetris (falling pieces swim in reflowing text)
- Shrinkwrap Showdown (standard sizing vs binary-search minimum width)
- Testimonial (fixed card height vs PretextKit-computed optimal height)
- Bouncing Orbs (60fps physics with text flowing around moving obstacles)
- Dynamic Layout (draggable magazine elements with real-time text reflow)
- Editorial Spread (two-column text flow with floating obstacles)

Dynamic Layout tab compares 5 text engines head-to-head:
PretextKit, CoreText raw, TextKit 1, TextKit 2, UILabel
