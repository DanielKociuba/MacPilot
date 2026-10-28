import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct WorkbenchView: View {
    var body: some View {
        TabView {
            DiagnosticsView().tabItem { Label("Diagnostics", systemImage: "stethoscope") }
            FileExplorerView().tabItem { Label("Large files", systemImage: "folder") }
            ModesView().tabItem { Label("Work modes", systemImage: "sparkles") }
            TextWorkbenchView().tabItem { Label("Text tools", systemImage: "textformat") }
            ImageWorkbenchView().tabItem { Label("Images", systemImage: "photo") }
            DrivesView().tabItem { Label("Drives", systemImage: "externaldrive") }
        }.padding().navigationTitle("Workbench")
    }
}

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
    @State private var status = "Choose a folder to inspect. Files are never deleted by this explorer."
    @State private var query = ""
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
            List(files.filter { query.isEmpty || $0.url.lastPathComponent.localizedCaseInsensitiveContains(query) }) { file in
                HStack {
                    VStack(alignment: .leading) {
                        Text(file.url.lastPathComponent).font(.headline)
                        Text(file.url.deletingLastPathComponent().path).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer()
                    Text(fmt(file.bytes)).monospacedDigit()
                    Button("Reveal") { NSWorkspace.shared.activateFileViewerSelecting([file.url]) }
                }.padding(.vertical, 4)
            }
        }.padding(24).onDisappear { scan?.cancel() }
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

struct ModesView: View {
    @EnvironmentObject var tools: Tools
    @EnvironmentObject var clipboard: ClipboardStore
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            PageHeading(title: "Ready for your next task", subtitle: "An explicit presentation preset with a reversible clipboard change.")
            Text("Presentation mode starts a one-hour Keep Awake session and pauses clipboard capture. It does not change Focus, notifications, audio, or display settings.")
            Text("Before presenting: check battery, select the correct audio output, and close private windows.").foregroundStyle(.secondary)
            Button(tools.presentationCapture == nil ? "Start presentation mode" : "End presentation mode") {
                if let previous = tools.presentationCapture {
                    tools.setKeepAwake(false)
                    clipboard.setEnabled(previous)
                    tools.presentationCapture = nil
                } else {
                    tools.presentationCapture = clipboard.enabled
                    clipboard.setEnabled(false)
                    tools.setKeepAwake(true, minutes: 60)
                }
            }.buttonStyle(.borderedProminent).disabled(tools.presentationCapture == nil && tools.keepAwake)
            if tools.keepAwake && tools.presentationCapture == nil { Text("Stop your existing Keep Awake session before starting this mode.").font(.caption) }
            if tools.presentationCapture != nil { Text("Mode active. Clipboard capture remains paused until you end the mode, even after Keep Awake expires.") }
            Spacer()
        }.padding(24)
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

struct ImageWorkbenchView: View {
    @State private var status = "Choose an image to export a new PNG or JPEG. The source stays unchanged."
    @State private var jpeg = false
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            PageHeading(title: "A simpler image export", subtitle: "Convert a local image without uploading it.")
            Toggle("Export JPEG instead of PNG", isOn: $jpeg)
            Text("JPEG flattens transparency onto white. Export uses the image’s pixel dimensions. Animated and multi-page inputs export only one image.").foregroundStyle(.secondary)
            Button("Choose image and export…") {
                let input = NSOpenPanel()
                input.allowedContentTypes = [.png, .jpeg, .tiff, .heic]
                guard input.runModal() == .OK, let url = input.url,
                      let source = NSImage(contentsOf: url),
                      let cg = source.cgImage(forProposedRect: nil, context: nil, hints: nil) else { status = "No readable image selected."; return }
                let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: cg.width, pixelsHigh: cg.height, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
                guard let bitmap, let context = NSGraphicsContext(bitmapImageRep: bitmap) else { status = "Could not allocate image."; return }
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = context
                let rect = NSRect(x: 0, y: 0, width: cg.width, height: cg.height)
                if jpeg { NSColor.white.setFill(); rect.fill() }
                context.cgContext.draw(cg, in: rect)
                NSGraphicsContext.restoreGraphicsState()
                let output = NSSavePanel()
                output.allowedContentTypes = jpeg ? [.jpeg] : [.png]
                output.nameFieldStringValue = url.deletingPathExtension().lastPathComponent + "-export." + (jpeg ? "jpg" : "png")
                guard output.runModal() == .OK, let destination = output.url else { return }
                guard destination.standardizedFileURL != url.standardizedFileURL else { status = "Choose a different destination to preserve the source."; return }
                do {
                    guard let data = bitmap.representation(using: jpeg ? .jpeg : .png, properties: [.compressionFactor: 0.85]) else { status = "Encoding failed."; return }
                    try data.write(to: destination, options: .atomic)
                    status = "Exported \(destination.lastPathComponent)"
                } catch { status = error.localizedDescription }
            }
            Text(status).textSelection(.enabled)
            Spacer()
        }.padding(24)
    }
}

struct DrivesView: View {
    @State private var volumes: [URL] = []
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PageHeading(title: "Connected storage", subtitle: "Inspect mounted volumes. Use Finder’s eject control when finished.")
            Button("Refresh") { refresh() }
            List(volumes, id: \.self) { url in
                HStack {
                    Label(url.lastPathComponent, systemImage: "externaldrive")
                    Spacer()
                    if let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityKey]), let capacity = values.volumeAvailableCapacity { Text("\(fmt(Int64(capacity))) available") }
                    Button("Open in Finder") { NSWorkspace.shared.open(url) }
                }
            }
        }.padding(24).onAppear { refresh() }
    }
    private func refresh() { volumes = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: [.volumeAvailableCapacityKey], options: [.skipHiddenVolumes]) ?? [] }
}
