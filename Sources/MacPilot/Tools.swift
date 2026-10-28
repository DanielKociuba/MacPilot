import Combine
import Foundation
import AppKit

struct CommandResult: Sendable {
    let succeeded: Bool
    let output: String
}

/// One pipe drains both streams so a full stderr pipe cannot deadlock the child.
func runCommand(_ executable: String, _ arguments: [String]) -> CommandResult {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe
    do {
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return CommandResult(succeeded: process.terminationStatus == 0,
                             output: String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
    } catch { return CommandResult(succeeded: false, output: error.localizedDescription) }
}

func fmt(_ bytes: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
}

@MainActor
final class Tools: ObservableObject {
    @Published private(set) var keepAwake = false
    @Published private(set) var awakeUntil: Date?
    @Published private(set) var hiddenFiles = false
    @Published private(set) var entries: [CacheEntry] = []
    @Published private(set) var scanning = false
    @Published private(set) var cleaning = false
    @Published private(set) var changingFinder = false
    @Published private(set) var lastScan: Date?
    @Published private(set) var skipped = 0
    @Published private(set) var cleanupReport = ""
    @Published private(set) var status = ""
    private var caffeinate: Process?
    private var awakeTimer: Timer?
    let caches = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Caches")
    var cacheSize: Int64 { entries.reduce(0) { $0 + $1.bytes } }

    init() {
        hiddenFiles = UserDefaults(suiteName: "com.apple.finder")?.bool(forKey: "AppleShowAllFiles") ?? false
    }

    func setKeepAwake(_ on: Bool, minutes: Int? = nil) {
        awakeTimer?.invalidate(); awakeTimer = nil
        caffeinate?.terminationHandler = nil
        if caffeinate?.isRunning == true { caffeinate?.terminate() }
        caffeinate = nil
        keepAwake = false
        awakeUntil = nil
        guard on else { ActionHistory.shared.note("Stopped Keep Awake"); return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/caffeinate")
        var arguments = ["-d", "-i", "-w", String(ProcessInfo.processInfo.processIdentifier)]
        if let minutes { arguments += ["-t", String(minutes * 60)] }
        process.arguments = arguments
        process.terminationHandler = { [weak self] ended in
            Task { @MainActor [weak self] in
                guard self?.caffeinate === ended else { return }
                self?.keepAwake = false
                self?.awakeUntil = nil
                self?.caffeinate = nil
            }
        }
        do {
            try process.run()
            caffeinate = process
            keepAwake = true
            if let minutes {
                awakeUntil = Date().addingTimeInterval(Double(minutes * 60))
                awakeTimer = Timer.scheduledTimer(withTimeInterval: Double(minutes * 60), repeats: false) { [weak self] _ in
                    Task { @MainActor [weak self] in self?.setKeepAwake(false) }
                }
            }
            ActionHistory.shared.note("Started Keep Awake")
            status = "Keep Awake started. Closing the lid can still put your Mac to sleep."
        } catch { status = "Could not start Keep Awake: \(error.localizedDescription)" }
    }

    func setHiddenFiles(_ on: Bool) async {
        guard !changingFinder else { return }
        changingFinder = true
        defer { changingFinder = false }
        let result = await Task.detached {
            runCommand("/usr/bin/defaults", ["write", "com.apple.finder", "AppleShowAllFiles", "-bool", on ? "true" : "false"])
        }.value
        guard result.succeeded else { status = "Finder setting failed: \(result.output)"; return }
        hiddenFiles = on
        ActionHistory.shared.note("Finder hidden files: \(on ? "shown" : "hidden")")
        let restart = await Task.detached { runCommand("/usr/bin/killall", ["Finder"]) }.value
        status = restart.succeeded ? "Finder setting updated." : "Setting saved. Reopen Finder to apply it."
    }

    func refreshSizes() async {
        guard !scanning, !cleaning else { return }
        scanning = true
        defer { scanning = false }
        let root = caches
        do {
            let scan = try await Task.detached { try CleanupService.scan(root: root) }.value
            entries = scan.entries
            skipped = scan.skipped
            lastScan = Date()
        } catch {
            entries = []
            lastScan = nil
            status = "Could not scan caches: \(error.localizedDescription)"
        }
    }

    func cleanCaches(ids: Set<URL>) async {
        guard !scanning, !cleaning else { return }
        let selected = entries.filter { ids.contains($0.id) }
        guard !selected.isEmpty else { return }
        cleaning = true
        var result = CleanupResult()
        for entry in selected {
            do {
                guard CleanupService.isEligible(entry.url, root: caches) else { throw CocoaError(.fileReadNoPermission) }
                try ActionHistory.shared.trash(entry.url, reason: "Cache cleanup")
                result.moved += 1
            } catch { result.failures.append("\(entry.name): \(error.localizedDescription)") }
        }
        cleanupReport = "Moved \(result.moved) folder(s) to Trash. Undo is available in Change history until Trash is emptied. Space is reclaimed only after you empty Trash in Finder."
        if !result.failures.isEmpty { cleanupReport += "\n\n" + result.failures.joined(separator: "\n") }
        cleaning = false
        await refreshSizes()
    }
}
