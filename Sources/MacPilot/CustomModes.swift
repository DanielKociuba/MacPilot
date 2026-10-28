import SwiftUI
import AppKit

struct WorkMode: Codable, Identifiable {
    var id = UUID()
    var name: String
    var minutes: Int
    var pauseClipboard: Bool
    var apps: [URL] = []
}

@MainActor final class ModeStore: ObservableObject {
    static let shared = ModeStore()
    @Published var modes: [WorkMode] = []
    @Published var active: UUID?
    @Published var status = ""
    private var previousCapture = false
    private var pausedCapture = false
    init() {
        if let data = UserDefaults.standard.data(forKey: "workModes"), let decoded = try? JSONDecoder().decode([WorkMode].self, from: data) { modes = decoded }
        else { modes = [WorkMode(name: "Presenting", minutes: 60, pauseClipboard: true), WorkMode(name: "Focus", minutes: 30, pauseClipboard: false), WorkMode(name: "Gaming", minutes: 120, pauseClipboard: true)] }
    }
    func save() { if let data = try? JSONEncoder().encode(modes) { UserDefaults.standard.set(data, forKey: "workModes") } }
    func start(_ mode: WorkMode, tools: Tools, clipboard: ClipboardStore) {
        guard active == nil, !tools.keepAwake else { status = "End the current mode or Keep Awake session first."; return }
        if mode.minutes > 0 {
            tools.setKeepAwake(true, minutes: mode.minutes)
            guard tools.keepAwake else { status = tools.status; return }
        }
        previousCapture = clipboard.enabled; pausedCapture = mode.pauseClipboard
        if mode.pauseClipboard { clipboard.setEnabled(false) }
        active = mode.id
        status = "\(mode.name) started. Ending the mode stops its Keep Awake session and restores clipboard capture; launched apps stay open."
        ActionHistory.shared.note("Started work mode: \(mode.name)")
        for app in mode.apps {
            NSWorkspace.shared.openApplication(at: app, configuration: .init()) { [weak self] _, error in
                if let error {
                    Task { @MainActor [weak self] in self?.status += "\nCould not open \(app.lastPathComponent): \(error.localizedDescription)" }
                }
            }
        }
    }
    func stop(tools: Tools, clipboard: ClipboardStore) {
        guard active != nil else { return }
        tools.setKeepAwake(false)
        if pausedCapture { clipboard.setEnabled(previousCapture) }
        active = nil
        status = "Mode ended. Opened apps remain open."
        ActionHistory.shared.note("Ended work mode")
    }
}

struct CustomModesView: View {
    @ObservedObject private var store = ModeStore.shared
    @EnvironmentObject var tools: Tools
    @EnvironmentObject var clipboard: ClipboardStore
    @State private var draft = WorkMode(name: "My mode", minutes: 60, pauseClipboard: true)
    @State private var editing = false
    @State private var status = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PageHeading(title: "Your routine, one action", subtitle: "Create presets for Keep Awake, clipboard privacy, and launching selected apps. Changes are shown before you start.")
            HStack {
                Button("New mode") { draft = WorkMode(name: "My mode", minutes: 60, pauseClipboard: true); editing = true }
                Button("End active mode") { store.stop(tools: tools, clipboard: clipboard) }.disabled(store.active == nil)
            }
            PresentationCheckView()
            Text(store.status).foregroundStyle(.secondary)
            List(store.modes) { mode in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(mode.name).font(.headline)
                        if store.active == mode.id { Text("Active").foregroundStyle(.teal) }
                        Spacer()
                        Button("Start") { store.start(mode, tools: tools, clipboard: clipboard) }.disabled(store.active != nil || tools.keepAwake)
                        Button("Edit") { draft = mode; editing = true }.disabled(store.active == mode.id)
                        Button("Delete", role: .destructive) { store.modes.removeAll { $0.id == mode.id }; store.save() }.disabled(store.active == mode.id)
                    }
                    Text("Keep Awake: \(mode.minutes == 0 ? "off" : "\(mode.minutes) minutes") · Clipboard: \(mode.pauseClipboard ? "pause" : "unchanged")").font(.caption)
                    Text(mode.apps.isEmpty ? "No apps launched" : "Open: " + mode.apps.map(\.lastPathComponent).joined(separator: ", ")).font(.caption).foregroundStyle(.secondary)
                }.padding(.vertical, 6)
            }
            Text("Keep Awake expires on its timer. The mode remains active until ended, so clipboard capture stays paused. Modes do not alter Focus, audio, or notifications.").font(.caption).foregroundStyle(.secondary)
        }.padding(24)
        .sheet(isPresented: $editing) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Edit work mode").font(.title2.bold())
                TextField("Name", text: $draft.name)
                Picker("Keep Awake", selection: $draft.minutes) {
                    Text("Off").tag(0); Text("15 minutes").tag(15); Text("30 minutes").tag(30); Text("1 hour").tag(60); Text("2 hours").tag(120)
                }
                Toggle("Pause clipboard capture", isOn: $draft.pauseClipboard)
                Button("Add apps…") {
                    let picker = NSOpenPanel(); picker.allowedContentTypes = [.applicationBundle]; picker.allowsMultipleSelection = true
                    if picker.runModal() == .OK { draft.apps = Array(Set(draft.apps + picker.urls)).sorted { $0.path < $1.path } }
                }
                ForEach(draft.apps, id: \.self) { app in
                    HStack { Text(app.lastPathComponent); Spacer(); Button("Remove") { draft.apps.removeAll { $0 == app } } }
                }
                HStack {
                    Button("Cancel") { editing = false }
                    Button("Save mode") {
                        draft.name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
                        if let i = store.modes.firstIndex(where: { $0.id == draft.id }) { store.modes[i] = draft } else { store.modes.append(draft) }
                        store.save(); editing = false
                    }.disabled(draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }.padding(24).frame(width: 450)
        }
    }
}
