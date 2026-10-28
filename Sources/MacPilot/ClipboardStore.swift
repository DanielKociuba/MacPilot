import AppKit

/// In-memory clipboard history (text only, never written to disk).
@MainActor
final class ClipboardStore: ObservableObject {
    @Published var items: [String] = []
    private var lastCount = NSPasteboard.general.changeCount
    private var timer: Timer?

    init() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.7, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
    }

    private func poll() {
        let pb = NSPasteboard.general
        guard pb.changeCount != lastCount else { return }
        lastCount = pb.changeCount
        guard let s = pb.string(forType: .string), !s.isEmpty else { return }
        items.removeAll { $0 == s }
        items.insert(s, at: 0)
        items = Array(items.prefix(30))
    }

    func copy(_ s: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(s, forType: .string)
        lastCount = pb.changeCount
    }

    func clear() { items = [] }
}
