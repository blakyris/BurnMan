import Foundation

/// Thread-safe collector that batches URLs from drag-and-drop providers,
/// deduplicates by canonical path, preserves insertion order,
/// and calls back on `@MainActor` once all providers have responded.
final class DropURLCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var urls: [URL] = []
    private var seen: Set<String> = []
    private var remaining: Int
    private let callback: @MainActor @Sendable ([URL]) -> Void

    init(total: Int, onComplete: @escaping @MainActor @Sendable ([URL]) -> Void) {
        self.remaining = total
        self.callback = onComplete
    }

    func collected(url: URL?) {
        lock.lock()
        if let url {
            let key = url.standardizedFileURL.resolvingSymlinksInPath().path
            if !seen.contains(key) {
                seen.insert(key)
                urls.append(url)
            }
        }
        remaining -= 1
        let done = remaining == 0
        let batch = urls
        lock.unlock()

        if done && !batch.isEmpty {
            let cb = callback
            Task { @MainActor in
                cb(batch)
            }
        }
    }
}
