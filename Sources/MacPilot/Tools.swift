import Foundation
import AppKit

@discardableResult
func shell(_ exe: String, _ args: [String]) -> String {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: exe)
    p.arguments = args
    let out = Pipe()
    p.standardOutput = out
    p.standardError = Pipe()
    do { try p.run() } catch { return "" }
    let data = out.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
}

func dirSize(_ url: URL) -> Int64 {
    guard let e = FileManager.default.enumerator(
        at: url, includingPropertiesForKeys: [.totalFileAllocatedSizeKey],
        options: [], errorHandler: { _, _ in true }) else { return 0 }
    var total: Int64 = 0
    for case let u as URL in e {
        total += Int64((try? u.resourceValues(forKeys: [.totalFileAllocatedSizeKey]).totalFileAllocatedSize) ?? 0)
    }
    return total
}

func fmt(_ bytes: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
}

@MainActor
final class Tools: ObservableObject {
    @Published var keepAwake = false
    @Published var hiddenFiles = false
    @Published var cacheSize: Int64 = 0
    @Published var trashSize: Int64 = 0
    @Published var status = ""

    private var caffeinate: Process?
    private let home = FileManager.default.homeDirectoryForCurrentUser
    private var caches: URL { home.appendingPathComponent("Library/Caches") }
    private var trash: URL { home.appendingPathComponent(".Trash") }

    init() {
        let v = shell("/usr/bin/defaults", ["read", "com.apple.finder", "AppleShowAllFiles"]).lowercased()
        hiddenFiles = (v == "1" || v == "true" || v == "yes")
        Task { await refreshSizes() }
    }

    // MARK: Keep awake
    func setKeepAwake(_ on: Bool) {
        caffeinate?.terminate(); caffeinate = nil
        if on {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/caffeinate")
            p.arguments = ["-d", "-i"]   // no display sleep, no idle sleep
            try? p.run()
            caffeinate = p
        }
        keepAwake = on
    }

    // MARK: Finder hidden files
    func setHiddenFiles(_ on: Bool) {
        shell("/usr/bin/defaults", ["write", "com.apple.finder", "AppleShowAllFiles", "-bool", on ? "true" : "false"])
        shell("/usr/bin/killall", ["Finder"])
        hiddenFiles = on
    }

    // MARK: Cleaner
    func refreshSizes() async {
        let c = caches, t = trash
        cacheSize = await Task.detached { dirSize(c) }.value
        trashSize = await Task.detached { dirSize(t) }.value
    }

    func cleanCaches() async {
        let url = caches
        let freed = await Task.detached { () -> Int64 in
            let before = dirSize(url)
            let items = (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)) ?? []
            for i in items { try? FileManager.default.removeItem(at: i) }
            return max(0, before - dirSize(url))
        }.value
        status = "Freed \(fmt(freed)) from user caches"
        await refreshSizes()
    }

    func emptyTrash() async {
        await Task.detached {
            shell("/usr/bin/osascript", ["-e", "tell application \"Finder\" to empty trash"])
        }.value
        status = "Trash emptied"
        await refreshSizes()
    }

    deinit { caffeinate?.terminate() }
}
