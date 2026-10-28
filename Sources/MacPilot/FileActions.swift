import SwiftUI
import AppKit

struct MoveRecord: Codable, Identifiable {
    var id = UUID()
    var date = Date()
    let source: URL
    let destination: URL
    let identity: String
    let reason: String
    var undone = false
}

enum FileSafety {
    static func identity(_ url: URL) throws -> String {
        let a = try FileManager.default.attributesOfItem(atPath: url.path)
        guard let inode = a[.systemFileNumber] as? NSNumber, let device = a[.systemNumber] as? NSNumber else { throw CocoaError(.fileReadUnknown) }
        return "\(device):\(inode)"
    }
    static func regular(_ url: URL) -> Bool {
        guard let v = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]) else { return false }
        return v.isRegularFile == true && v.isSymbolicLink != true
    }
    static func category(_ url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "png", "jpg", "jpeg", "heic", "gif", "tiff", "webp": return "Images"
        case "pdf", "txt", "doc", "docx", "rtf", "csv", "xlsx": return "Documents"
        case "zip", "gz", "tar", "7z", "rar": return "Archives"
        case "dmg", "pkg": return "Installers"
        case "mov", "mp4", "mkv": return "Video"
        case "mp3", "wav", "m4a", "flac": return "Audio"
        default: return "Other"
        }
    }
    static func restore(_ record: MoveRecord) throws {
        let fm = FileManager.default
        guard !fm.fileExists(atPath: record.source.path),
              try identity(record.destination) == record.identity else { throw CocoaError(.fileWriteFileExists) }
        // Never replace an item or create a missing parent during undo.
        guard fm.fileExists(atPath: record.source.deletingLastPathComponent().path),
              (try record.source.deletingLastPathComponent().resourceValues(forKeys: [.isSymbolicLinkKey])).isSymbolicLink != true else { throw CocoaError(.fileNoSuchFile) }
        try fm.moveItem(at: record.destination, to: record.source)
    }
}

@MainActor final class ActionHistory: ObservableObject {
    static let shared = ActionHistory()
    @Published private(set) var moves: [MoveRecord] = []
    @Published private(set) var notes: [String] = []
    @Published var status = ""
    private let file = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/MacPilot/history.json")
    init() {
        if let data = try? Data(contentsOf: file), let saved = try? JSONDecoder().decode([MoveRecord].self, from: data) { moves = saved }
    }
    private func save() {
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(moves).write(to: file, options: .atomic)
        } catch { status += " History could not be saved: \(error.localizedDescription). Undo remains available this session." }
    }
    func note(_ text: String) { notes.insert("\(Date().formatted(date: .omitted, time: .shortened)) · \(text)", at: 0); notes = Array(notes.prefix(100)) }
    func move(_ source: URL, to destination: URL, reason: String) throws {
        let fm = FileManager.default
        guard !fm.fileExists(atPath: destination.path) else { throw CocoaError(.fileWriteFileExists) }
        let identity = try FileSafety.identity(source)
        try fm.moveItem(at: source, to: destination)
        moves.insert(MoveRecord(source: source, destination: destination, identity: identity, reason: reason), at: 0)
        status = "Moved \(source.lastPathComponent)."
        save()
    }
    func trash(_ source: URL, reason: String) throws {
        var destination: NSURL?
        try FileManager.default.trashItem(at: source, resultingItemURL: &destination)
        guard let url = destination as URL? else { status = "Moved to Trash; Finder did not return a restore location."; return }
        let identity = try FileSafety.identity(url)
        moves.insert(MoveRecord(source: source, destination: url, identity: identity, reason: reason), at: 0)
        status = "Moved \(source.lastPathComponent) to Trash."
        save()
    }
    func undo(_ record: MoveRecord) {
        do {
            try FileSafety.restore(record)
            if let index = moves.firstIndex(where: { $0.id == record.id }) { moves[index].undone = true }
            status = "Restored \(record.source.lastPathComponent)."
            save()
        } catch { status = "Cannot restore \(record.source.lastPathComponent): \(error.localizedDescription). The destination may have changed or the original path may be occupied." }
    }
    func clear() { moves = []; notes = []; status = "History cleared; files are unchanged."; save() }
}

struct HistoryView: View {
    @ObservedObject var history = ActionHistory.shared
    @State private var confirmClear = false
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            PageHeading(title: "Changes you can trace", subtitle: "File moves are stored locally across launches. Undo never overwrites an existing file. Settings notes last for this session.")
            Text(history.status).foregroundStyle(.secondary).textSelection(.enabled)
            Button("Clear history…") { confirmClear = true }
            List {
                ForEach(history.moves) { record in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(record.reason + " · " + record.source.lastPathComponent).font(.headline)
                            Spacer()
                            Button(record.undone ? "Restored" : "Undo move") { history.undo(record) }.disabled(record.undone)
                        }
                        Text(record.source.path + " → " + record.destination.path).font(.caption).textSelection(.enabled)
                        Text(record.date.formatted()).font(.caption).foregroundStyle(.secondary)
                    }
                }
                ForEach(Array(history.notes.enumerated()), id: \.offset) { _, note in Text(note).font(.callout) }
            }
        }.padding(24).alert("Clear saved undo history?", isPresented: $confirmClear) {
            Button("Cancel", role: .cancel) { }
            Button("Clear", role: .destructive) { history.clear() }
        } message: { Text("This removes MacPilot’s restore records, not the files themselves.") }
    }
}

struct OrganizationPlan: Identifiable {
    let source: URL
    let destination: URL
    let identity: String
    var id: URL { source }
}

struct OrganizerView: View {
    @State private var plan: [OrganizationPlan] = []
    @State private var selection = Set<URL>()
    @State private var root: URL?
    @State private var minimumDays = 7
    @State private var status = ""
    @State private var confirm = false
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PageHeading(title: "A tidier Downloads folder", subtitle: "Preview immediate files grouped by type. No recursion, no overwrites, no automatic selection.")
            HStack {
                Picker("Older than", selection: $minimumDays) { Text("Any age").tag(0); Text("7 days").tag(7); Text("30 days").tag(30) }.frame(width: 230)
                Button("Choose folder and preview…") { preview() }
                Button("Move selected…") { confirm = true }.disabled(selection.isEmpty)
            }
            Text("Changing the age filter takes effect on the next preview. Uses last modification date; active downloads and symbolic links are excluded.").font(.caption).foregroundStyle(.secondary)
            Text(status).textSelection(.enabled)
            List(plan) { item in
                Toggle(isOn: Binding(get: { selection.contains(item.id) }, set: { if $0 { selection.insert(item.id) } else { selection.remove(item.id) } })) {
                    Text(item.source.lastPathComponent + " → " + item.destination.deletingLastPathComponent().lastPathComponent)
                }.toggleStyle(.checkbox)
            }
        }.padding(24).alert("Move \(selection.count) files into category folders?", isPresented: $confirm) {
            Button("Cancel", role: .cancel) { }
            Button("Move files") { apply() }
        } message: { Text("Existing files will never be replaced. You can undo successful moves in Change history.") }
    }
    private func preview() {
        let panel = NSOpenPanel(); panel.canChooseFiles = false; panel.canChooseDirectories = true
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        root = folder.resolvingSymlinksInPath(); plan = []; selection = []
        do {
            let children = try FileManager.default.contentsOfDirectory(at: root!, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles])
            let cutoff = Date().addingTimeInterval(-Double(minimumDays) * 86400)
            var skipped = 0
            for url in children {
                guard FileSafety.regular(url), !["download", "crdownload", "part", "partial"].contains(url.pathExtension.lowercased()),
                      let modified = try url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate, modified <= cutoff else { skipped += 1; continue }
                let destination = root!.appendingPathComponent(FileSafety.category(url)).appendingPathComponent(url.lastPathComponent)
                guard !FileManager.default.fileExists(atPath: destination.path) else { skipped += 1; continue }
                plan.append(OrganizationPlan(source: url, destination: destination, identity: try FileSafety.identity(url)))
            }
            status = "\(plan.count) eligible files · \(skipped) skipped, including folders, recent files, and conflicts."
        } catch { status = error.localizedDescription }
    }
    private func apply() {
        var moved = Set<URL>(); var failures: [String] = []
        for item in plan where selection.contains(item.id) {
            do {
                let parent = item.destination.deletingLastPathComponent()
                guard FileSafety.regular(item.source), try FileSafety.identity(item.source) == item.identity,
                      parent.resolvingSymlinksInPath().path == parent.path else { throw CocoaError(.fileReadNoPermission) }
                try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: false)
                try ActionHistory.shared.move(item.source, to: item.destination, reason: "Organize downloads")
                moved.insert(item.id)
            } catch { failures.append("\(item.source.lastPathComponent): \(error.localizedDescription)") }
        }
        plan.removeAll { moved.contains($0.id) }; selection.subtract(moved)
        status = "Moved \(moved.count) files.\n" + failures.joined(separator: "\n")
    }
}

struct RemovalCandidate: Identifiable {
    let url: URL
    let detail: String
    let identity: String?
    init(url: URL, detail: String) { self.url = url; self.detail = detail; self.identity = try? FileSafety.identity(url) }
    var id: URL { url }
}

struct AppRemovalView: View {
    @State private var app: URL?
    @State private var bundleID = ""
    @State private var candidates: [RemovalCandidate] = []
    @State private var selected = Set<URL>()
    @State private var status = ""
    @State private var confirm = false
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PageHeading(title: "Remove an app with a review", subtitle: "Choose a non-system app. Review its bundle and exact bundle-ID matches in your user Library.")
            Text("Associated files may contain preferences or app data. Shared containers, extensions, launch agents, and ambiguous matches are deliberately excluded. This is not a guarantee that every leftover is found.").foregroundStyle(.secondary)
            HStack {
                Button("Choose app…") { inspect() }
                Button("Move selected to Trash…", role: .destructive) { confirm = true }.disabled(selected.isEmpty)
            }
            Text(status).textSelection(.enabled)
            List(candidates) { candidate in
                HStack {
                    Toggle(isOn: Binding(get: { selected.contains(candidate.id) }, set: { if $0 { selected.insert(candidate.id) } else { selected.remove(candidate.id) } })) {
                        VStack(alignment: .leading) { Text(candidate.url.lastPathComponent); Text(candidate.detail + " · " + candidate.url.path).font(.caption).foregroundStyle(.secondary) }
                    }.toggleStyle(.checkbox)
                    Button("Reveal") { NSWorkspace.shared.activateFileViewerSelecting([candidate.url]) }
                }
            }
        }.padding(24).alert("Move \(selected.count) reviewed items to Trash?", isPresented: $confirm) {
            Button("Cancel", role: .cancel) { }
            Button("Move to Trash", role: .destructive) { remove() }
        } message: { Text("Quit the app first. Selected app data may be important. Successful moves can be restored from Change history until Trash is emptied.") }
    }
    private func inspect() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.applicationBundle]; panel.directoryURL = URL(fileURLWithPath: "/Applications")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        candidates = []; selected = []; app = nil
        let path = url.resolvingSymlinksInPath().path
        guard !path.hasPrefix("/System/"), !path.hasPrefix("/usr/"), url.standardizedFileURL.path == path,
              let bundle = Bundle(url: url), let id = bundle.bundleIdentifier,
              id.contains("."), !id.contains("/"), !id.contains(".."), id != Bundle.main.bundleIdentifier else { status = "Choose a third-party app with a valid bundle identifier, outside system folders."; return }
        app = url; bundleID = id
        candidates = [RemovalCandidate(url: url, detail: "Application bundle")]
        let home = FileManager.default.homeDirectoryForCurrentUser
        for relative in ["Library/Caches/\(id)", "Library/Preferences/\(id).plist", "Library/Application Support/\(id)", "Library/Saved Application State/\(id).savedState"] {
            let candidate = home.appendingPathComponent(relative)
            if FileManager.default.fileExists(atPath: candidate.path), candidate.resolvingSymlinksInPath().path == candidate.path {
                candidates.append(RemovalCandidate(url: candidate, detail: "Exact bundle-ID match; review contents"))
            }
        }
        status = "\(id) · Nothing selected automatically."
    }
    private func remove() {
        guard NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty else { status = "Quit the app before removing its files."; return }
        var removed = Set<URL>(); var errors: [String] = []
        for candidate in candidates where selected.contains(candidate.id) {
            do {
                guard candidate.url.resolvingSymlinksInPath().path == candidate.url.path, let identity = candidate.identity, try FileSafety.identity(candidate.url) == identity else { throw CocoaError(.fileReadNoPermission) }
                try ActionHistory.shared.trash(candidate.url, reason: "App removal")
                removed.insert(candidate.id)
            } catch { errors.append("\(candidate.url.lastPathComponent): \(error.localizedDescription)") }
        }
        candidates.removeAll { removed.contains($0.id) }; selected.subtract(removed)
        status = "Moved \(removed.count) items to Trash.\n" + errors.joined(separator: "\n")
    }
}
