import SwiftUI
import ImageIO
import UniformTypeIdentifiers

struct ImageExportOptions: Sendable {
    var jpeg = false
    var quality = 0.85
    var maxPixels = 1920
    var prefix = ""
}

enum ImageExporter {
    static func export(_ sourceURL: URL, to output: URL, options: ImageExportOptions) throws {
        guard !FileManager.default.fileExists(atPath: output.path),
              let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil) else { throw CocoaError(.fileReadCorruptFile) }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let width = properties?[kCGImagePropertyPixelWidth] as? Int ?? 0
        let height = properties?[kCGImagePropertyPixelHeight] as? Int ?? 0
        guard width > 0, height > 0 else { throw CocoaError(.fileReadCorruptFile) }
        let limit = options.maxPixels == 0 ? max(width, height) : min(options.maxPixels, max(width, height))
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: limit] as CFDictionary),
              let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw CocoaError(.fileReadCorruptFile) }
        let rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        if options.jpeg { context.setFillColor(CGColor(gray: 1, alpha: 1)); context.fill(rect) }
        context.draw(image, in: rect)
        guard let rendered = context.makeImage() else { throw CocoaError(.fileReadCorruptFile) }
        let data = NSMutableData()
        guard let writer = CGImageDestinationCreateWithData(data, (options.jpeg ? UTType.jpeg.identifier : UTType.png.identifier) as CFString, 1, nil) else { throw CocoaError(.fileWriteUnknown) }
        // Only pixel data and encoder settings are transferred: no EXIF/GPS or source metadata.
        CGImageDestinationAddImage(writer, rendered, [kCGImageDestinationLossyCompressionQuality: options.quality] as CFDictionary)
        guard CGImageDestinationFinalize(writer) else { throw CocoaError(.fileWriteUnknown) }
        try (data as Data).write(to: output, options: .withoutOverwriting)
    }
    static func name(source: URL, index: Int, options: ImageExportOptions) -> String {
        let stem = options.prefix.isEmpty ? source.deletingPathExtension().lastPathComponent + "-export" : options.prefix + "-" + String(format: "%03d", index + 1)
        return stem + (options.jpeg ? ".jpg" : ".png")
    }
}

struct BatchImagesView: View {
    @State private var inputs: [URL] = []
    @State private var options = ImageExportOptions()
    @State private var status = ""
    @State private var completed = 0
    @State private var busy = false
    @State private var job: Task<Void, Never>?
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PageHeading(title: "Images ready to share", subtitle: "Batch resize, convert, compress, rename, and strip metadata locally. Source files stay untouched.")
            HStack {
                Button("Choose images…") {
                    let panel = NSOpenPanel(); panel.allowedContentTypes = [.png, .jpeg, .tiff, .heic]; panel.allowsMultipleSelection = true
                    if panel.runModal() == .OK { inputs = panel.urls }
                }.disabled(busy)
                Button("Export to folder…") { export() }.disabled(inputs.isEmpty || busy || options.prefix.contains("/") || options.prefix.contains(":"))
                Button("Cancel") { job?.cancel() }.disabled(!busy)
            }
            Group {
                Toggle("JPEG (white background for transparent areas)", isOn: $options.jpeg)
                HStack { Text("JPEG quality"); Slider(value: $options.quality, in: 0.1...1); Text("\(Int(options.quality * 100))%").monospacedDigit() }.disabled(!options.jpeg)
                Picker("Longest edge", selection: $options.maxPixels) { Text("Original size").tag(0); Text("3840 px").tag(3840); Text("1920 px").tag(1920); Text("1280 px").tag(1280); Text("800 px").tag(800) }
                TextField("Optional batch name (e.g. holiday → holiday-001)", text: $options.prefix)
            }.disabled(busy)
            Text("Preview names below. Metadata is removed; image orientation is applied. Multi-page images export the first frame. Existing outputs are skipped, never overwritten. PNG is lossless; JPEG quality controls compression.").font(.caption).foregroundStyle(.secondary)
            if busy { ProgressView(value: Double(completed), total: Double(max(inputs.count, 1))) }
            Text(status).textSelection(.enabled)
            List(Array(inputs.enumerated()), id: \.element) { index, url in Text(url.lastPathComponent + " → " + ImageExporter.name(source: url, index: index, options: options)) }
        }.padding(24)
    }
    private func export() {
        let picker = NSOpenPanel(); picker.canChooseFiles = false; picker.canChooseDirectories = true
        guard picker.runModal() == .OK, let folder = picker.url else { return }
        let sources = inputs; let configuration = options
        busy = true; completed = 0; status = ""
        job = Task {
            var exported = 0; var failures: [String] = []
            for (index, source) in sources.enumerated() {
                if Task.isCancelled { break }
                let destination = folder.appendingPathComponent(ImageExporter.name(source: source, index: index, options: configuration))
                do {
                    try await Task.detached { try ImageExporter.export(source, to: destination, options: configuration) }.value
                    exported += 1
                } catch { failures.append("\(source.lastPathComponent): \(error.localizedDescription)") }
                completed = index + 1
            }
            status = "\(Task.isCancelled ? "Cancelled. " : "")Exported \(exported) of \(sources.count).\n" + failures.joined(separator: "\n")
            ActionHistory.shared.note("Exported \(exported) images to \(folder.path); originals unchanged")
            busy = false
        }
    }
}
