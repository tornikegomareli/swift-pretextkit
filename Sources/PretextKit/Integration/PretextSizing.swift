#if canImport(UIKit)
import UIKit
#endif
import Foundation

/// A thread-safe cache that maps identifiers to `PreparedText` handles.
///
/// Designed for UICollectionView/UITableView cells: prepare text on a
/// background thread during prefetch, then compute heights synchronously
/// during cell sizing with pure arithmetic.
///
/// ```swift
/// // In your data source:
/// let sizingCache = PretextSizingCache()
///
/// // During prefetch:
/// func collectionView(_ cv: UICollectionView, prefetchItemsAt indexPaths: [IndexPath]) {
///     for ip in indexPaths {
///         let text = dataSource[ip.item].text
///         sizingCache.prepare(text, font: font, identifier: ip)
///     }
/// }
///
/// // During sizing (main thread, sub-microsecond):
/// let height = sizingCache.height(for: indexPath, width: cellWidth, lineHeight: 22)
/// ```
public final class PretextSizingCache: @unchecked Sendable {

    private let queue = DispatchQueue(
        label: "com.pretextkit.sizing",
        qos: .userInitiated,
        attributes: .concurrent
    )

    private var cache: [AnyHashable: PreparedText] = [:]
    private let lock = NSLock()

    public init() {}

    // MARK: - Prepare

    /// Prepare text on a background thread and cache the result.
    ///
    /// - Parameters:
    ///   - text: The text to prepare.
    ///   - font: The font to measure with.
    ///   - identifier: A hashable key (e.g., `IndexPath`, model ID).
    ///   - options: White-space mode.
    public func prepare(
        _ text: String,
        font: FontDescriptor,
        identifier: some Hashable,
        options: PrepareOptions = PrepareOptions()
    ) {
        let key = AnyHashable(identifier)
        queue.async { [self] in
            let prepared = PretextKit.prepare(text, font: font, options: options)
            lock.lock()
            cache[key] = prepared
            lock.unlock()
        }
    }

    /// Prepare text synchronously and cache the result.
    public func prepareSync(
        _ text: String,
        font: FontDescriptor,
        identifier: some Hashable,
        options: PrepareOptions = PrepareOptions()
    ) {
        let prepared = PretextKit.prepare(text, font: font, options: options)
        let key = AnyHashable(identifier)
        lock.lock()
        cache[key] = prepared
        lock.unlock()
    }

    // MARK: - Layout

    /// Compute height for a cached identifier. Returns `nil` if not yet prepared.
    ///
    /// This is the hot path: pure arithmetic, sub-microsecond.
    public func height(
        for identifier: some Hashable,
        width: CGFloat,
        lineHeight: CGFloat
    ) -> CGFloat? {
        let key = AnyHashable(identifier)
        lock.lock()
        let prepared = cache[key]
        lock.unlock()
        guard let prepared else { return nil }
        return PretextKit.layout(prepared, maxWidth: width, lineHeight: lineHeight).height
    }

    /// Get the full layout result for a cached identifier.
    public func layout(
        for identifier: some Hashable,
        width: CGFloat,
        lineHeight: CGFloat
    ) -> LayoutResult? {
        let key = AnyHashable(identifier)
        lock.lock()
        let prepared = cache[key]
        lock.unlock()
        guard let prepared else { return nil }
        return PretextKit.layout(prepared, maxWidth: width, lineHeight: lineHeight)
    }

    // MARK: - Cache Management

    /// Remove cached entries for the given identifiers.
    /// Call from `cancelPrefetchingForItemsAt`.
    public func cancel(identifiers: [some Hashable]) {
        lock.lock()
        for id in identifiers {
            cache.removeValue(forKey: AnyHashable(id))
        }
        lock.unlock()
    }

    /// Remove a single cached entry.
    public func remove(identifier: some Hashable) {
        lock.lock()
        cache.removeValue(forKey: AnyHashable(identifier))
        lock.unlock()
    }

    /// Clear all cached entries.
    public func clear() {
        lock.lock()
        cache.removeAll()
        lock.unlock()
    }

    /// Number of cached entries.
    public var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return cache.count
    }
}
