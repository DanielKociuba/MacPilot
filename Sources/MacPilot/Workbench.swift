import SwiftUI
import AppKit
import UniformTypeIdentifiers
import Charts

struct DiagnosticsView: View {
    @EnvironmentObject var stats: SystemStats
    @State private var processes = ""
    @State private var busy = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PageHeading(title: "Understand the slowdown", subtitle: "Observations, not a synthetic health score. Refresh to inspect current processes.")
                Text(stats.cpu > 80 ? "CPU utilization is high right now. Check whether a busy app is doing expected work." : "CPU utilization alone does not currently explain a slowdown.")
                if stats.diskTotal > 0 && Double(stats.diskFree) / Double(stats.diskTotal) < 0.1 {
                    Text("Less than 10% of reported storage capacity is available. Review large files before removing anything.")
                }
                Text("Thermal state: \(thermalDescription)")
                Text("Memory pressure event: \(stats.memoryPressure)")
                Text("Memory use alone is not memory pressure. Open Activity Monitor’s Memory tab to inspect pressure and swap.").foregroundStyle(.secondary)
                HStack {
                    Button("Open Activity Monitor") { NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app")) }
                    Button(busy ? "Reading…" : "Refresh process snapshot") {
                        busy = true
                        Task {
                            let result = await Task.detached { runCommand("/bin/ps", ["-A", "-r", "-o", "pid=,pcpu=,pmem=,comm="]) }.value
                            processes = result.succeeded ? result.output.split(separator: "\n").prefix(20).joined(separator: "\n") : result.output
                            busy = false
                        }
                    }.disabled(busy)
                }
                Text("PID · CPU % · Memory % · Executable\nCPU figures from ps are sampled differently from the overview and can exceed 100% across cores.").font(.caption).foregroundStyle(.secondary)
                Text(processes).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
            }.padding(24)
        }
    }
    private var thermalDescription: String {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: return "Nominal"
        case .fair: return "Elevated"
        case .serious: return "Serious — reduce sustained workloads"
        case .critical: return "Critical — let the Mac cool down"
        @unknown default: return "Unknown"
        }
    }
}

struct LargeFile: Identifiable, Sendable {
    let url: URL
    let bytes: Int64
    var id: URL { url }
}

struct FileExplorerView: View {
    @State private var files: [LargeFile] = []
    @State private var scan: Task<Void, Never>?
    @State private var busy = false
    @State private var status = "Choose a folder to inspect. Review files before choosing Move to Trash."
    @State private var query = ""
    @State private var pendingTrash: URL?
    @State private var ageDays = 0
    private var filtered: [LargeFile] {
        files.filter { file in
            let matches = query.isEmpty || file.url.lastPathComponent.localizedCaseInsensitiveContains(query)
            guard ageDays > 0 else { return matches }
            let date = (try? file.url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date()
            return matches && date < Date().addingTimeInterval(-Double(ageDays) * 86400)
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PageHeading(title: "Find your biggest files", subtitle: "Inspect a folder you choose, then reveal files in Finder for review.")
            HStack {
                Button("Choose folder…") { choose() }.disabled(busy)
                Button("Cancel scan") { scan?.cancel() }.disabled(!busy)
                if busy { ProgressView().controlSize(.small) }
                TextField("Filter name or extension", text: $query).textFieldStyle(.roundedBorder)
            }
            Text(status).font(.caption).foregroundStyle(.secondary)
            Picker("Last modified", selection: $ageDays) { Text("Any age").tag(0); Text("Over 30 days").tag(30); Text("Over 90 days").tag(90) }
            if !filtered.isEmpty {
                Chart(Array(filtered.prefix(6))) { file in
                    BarMark(x: .value("Bytes", file.bytes), y: .value("File", file.url.lastPathComponent))
                }.frame(height: 130).accessibilityLabel("Largest matching files by logical size")
            }
            List(filtered) { file in
                HStack {
                    VStack(alignment: .leading) {
                        Text(file.url.lastPathComponent).font(.headline)
                        Text(file.url.deletingLastPathComponent().path).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer()
                    Text(fmt(file.bytes)).monospacedDigit()
                    Button("Reveal") { NSWorkspace.shared.activateFileViewerSelecting([file.url]) }
                    Button("Trash…", role: .destructive) { pendingTrash = file.url }
                }.padding(.vertical, 4)
            }
        }.padding(24).onDisappear { scan?.cancel() }
        .alert("Move this file to Trash?", isPresented: Binding(get: { pendingTrash != nil }, set: { if !$0 { pendingTrash = nil } })) {
            Button("Cancel", role: .cancel) { pendingTrash = nil }
            Button("Move to Trash", role: .destructive) {
                guard let url = pendingTrash else { return }
                do {
                    guard FileSafety.regular(url) else { throw CocoaError(.fileReadNoPermission) }
                    try ActionHistory.shared.trash(url, reason: "Large file cleanup")
                    files.removeAll { $0.url == url }; status = ActionHistory.shared.status
                } catch { status = error.localizedDescription }
                pendingTrash = nil
            }
        } message: { Text(pendingTrash?.path ?? "") }
    }
    private func choose() {
        let picker = NSOpenPanel()
        picker.canChooseDirectories = true
        picker.canChooseFiles = false
        guard picker.runModal() == .OK, let root = picker.url else { return }
        busy = true
        files = []
        status = "Scanning \(root.lastPathComponent)…"
        scan = Task {
            let worker = Task.detached { () -> ([LargeFile], Int, Bool) in
                var result: [LargeFile] = []
                var errors = 0
                let keys: Set<URLResourceKey> = [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]
                guard let iterator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: Array(keys), options: [.skipsPackageDescendants], errorHandler: { _, _ in errors += 1; return true }) else { return ([], 1, false) }
                for case let url as URL in iterator {
                    if Task.isCancelled { return ([], errors, true) }
                    do {
                        let values = try url.resourceValues(forKeys: keys)
                        if values.isSymbolicLink == true { iterator.skipDescendants(); continue }
                        if values.isRegularFile == true { result.append(LargeFile(url: url, bytes: Int64(values.fileSize ?? 0))) }
                        if result.count >= 2000 { result = Array(result.sorted { $0.bytes > $1.bytes }.prefix(1000)) }
                    } catch { errors += 1 }
                }
                return (Array(result.sorted { $0.bytes > $1.bytes }.prefix(1000)), errors, false)
            }
            let result = await withTaskCancellationHandler(operation: { await worker.value }, onCancel: { worker.cancel() })
            files = result.0
            status = result.2 || Task.isCancelled ? "Scan cancelled." : "Largest \(files.count) files by logical size · \(result.1) unreadable locations · packages and symlinks excluded."
            busy = false
        }
    }
}

enum TextTransform {
    static func uniqueLines(_ text: String) -> String {
        var seen = Set<String>()
        return text.components(separatedBy: "\n").filter { seen.insert($0).inserted }.joined(separator: "\n")
    }
    static func prettyJSON(_ text: String) throws -> String {
        let object = try JSONSerialization.jsonObject(with: Data(text.utf8), options: [.fragmentsAllowed])
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .fragmentsAllowed])
        return String(decoding: data, as: UTF8.self)
    }
}

struct TextWorkbenchView: View {
    @State private var text = ""
    @State private var status = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PageHeading(title: "Text, tidied up", subtitle: "Local transformations. Clipboard content is read only when you press Paste.")
            HStack {
                Button("Paste") { text = NSPasteboard.general.string(forType: .string) ?? "" }
                Button("UPPERCASE") { text = text.uppercased() }
                Button("lowercase") { text = text.lowercased() }
                Button("Unique lines") { text = TextTransform.uniqueLines(text) }
                Button("Format JSON") {
                    do { text = try TextTransform.prettyJSON(text); status = "JSON formatted" }
                    catch { status = "Invalid JSON: \(error.localizedDescription)" }
                }
            }
            TextEditor(text: $text).font(.system(.body, design: .monospaced))
            HStack {
                Button("Copy plain text") {
                    NSPasteboard.general.clearContents()
                    status = NSPasteboard.general.setString(text, forType: .string) ? "Copied" : "Copy failed"
                }
                Button("Clear") { text = ""; status = "" }
                Text(status).font(.caption).foregroundStyle(.secondary)
            }
        }.padding(24)
    }
}

struct DrivesView: View {
    @State private var volumes: [URL] = []
    @State private var status = ""
    @State private var eject: URL?
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PageHeading(title: "Connected storage", subtitle: "Inspect mounted volumes and safely eject removable media.")
            Button("Refresh") { refresh() }
            Text(status).foregroundStyle(.secondary)
            List(volumes, id: \.self) { url in
                HStack {
                    Label(url.lastPathComponent, systemImage: "externaldrive")
                    Spacer()
                    if let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityKey]), let capacity = values.volumeAvailableCapacity { Text("\(fmt(Int64(capacity))) available") }
                    Button("Open in Finder") { NSWorkspace.shared.open(url) }
                    if (try? url.resourceValues(forKeys: [.volumeIsEjectableKey]).volumeIsEjectable) == true {
                        Button("Eject…") { eject = url }
                    }
                }
            }
        }.padding(24).onAppear { refresh() }
        .alert("Eject this volume?", isPresented: Binding(get: { eject != nil }, set: { if !$0 { eject = nil } })) {
            Button("Cancel", role: .cancel) { eject = nil }
            Button("Eject") {
                guard let url = eject else { return }
                do { try NSWorkspace.shared.unmountAndEjectDevice(at: url); status = "Ejected \(url.lastPathComponent)."; refresh() }
                catch { status = "Could not eject: \(error.localizedDescription). Close files and apps using the drive, then try again." }
                eject = nil
            }
        } message: { Text("Finish file transfers first. MacPilot does not force-eject busy drives.") }
    }
    private func refresh() { volumes = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: [.volumeAvailableCapacityKey], options: [.skipHiddenVolumes]) ?? [] }
}
