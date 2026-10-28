import Foundation

struct CacheEntry: Identifiable, Sendable {
    let url: URL
    let bytes: Int64
    let unreadableItems: Int
    var id: URL { url }
    var name: String { url.lastPathComponent }
}

struct CacheScan: Sendable {
    let entries: [CacheEntry]
    let skipped: Int
}

struct CleanupResult: Sendable {
    var moved = 0
    var failures: [String] = []
}

/// Never follows symbolic links or accepts paths outside the scanned cache root.
enum CleanupService {
    static func isEligible(_ url: URL, root: URL) -> Bool {
        let root = root.standardizedFileURL
        let candidate = url.standardizedFileURL
        guard root.resolvingSymlinksInPath() == root,
              candidate.deletingLastPathComponent() == root,
              candidate.resolvingSymlinksInPath() == candidate,
              let values = try? candidate.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
              values.isDirectory == true, values.isSymbolicLink != true else { return false }
        return true
    }

    static func scan(root: URL) throws -> CacheScan {
        let fm = FileManager.default
        let children = try fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        var entries: [CacheEntry] = []
        var skipped = 0
        for child in children {
            guard isEligible(child, root: root) else { skipped += 1; continue }
            var unreadable = 0
            var bytes: Int64 = 0
            let keys: Set<URLResourceKey> = [.isRegularFileKey, .isSymbolicLinkKey, .fileAllocatedSizeKey]
            if let enumerator = fm.enumerator(at: child, includingPropertiesForKeys: Array(keys), options: [], errorHandler: { _, _ in
                unreadable += 1
                return true
            }) {
                for case let file as URL in enumerator {
                    do {
                        let values = try file.resourceValues(forKeys: keys)
                        if values.isSymbolicLink == true { enumerator.skipDescendants(); continue }
                        if values.isRegularFile == true { bytes += Int64(values.fileAllocatedSize ?? 0) }
                    } catch { unreadable += 1 }
                }
            } else { unreadable += 1 }
            entries.append(CacheEntry(url: child, bytes: bytes, unreadableItems: unreadable))
        }
        return CacheScan(entries: entries.sorted { $0.bytes > $1.bytes }, skipped: skipped)
    }

    static func moveToTrash(_ entries: [CacheEntry], root: URL,
                            move: (URL) throws -> Void = { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) }) -> CleanupResult {
        var result = CleanupResult()
        for entry in entries {
            guard isEligible(entry.url, root: root) else {
                result.failures.append("\(entry.name): folder changed or is no longer eligible.")
                continue
            }
            do { try move(entry.url); result.moved += 1 }
            catch { result.failures.append("\(entry.name): \(error.localizedDescription)") }
        }
        return result
    }
}
