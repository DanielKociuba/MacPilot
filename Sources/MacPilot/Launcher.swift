import SwiftUI
import Carbon

extension Notification.Name {
    static let pilotNavigate = Notification.Name("MacPilot.navigate")
    static let pilotLauncher = Notification.Name("MacPilot.launcher")
}

@MainActor final class Launcher: ObservableObject {
    static let shared = Launcher()
    @Published var status = ""
    var openWindow: (() -> Void)?
    var requested = false
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    func register() {
        guard hotKey == nil else { return }
        var event = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let installed = InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            Task { @MainActor in
                Launcher.shared.requested = true
                Launcher.shared.openWindow?()
                NSApp.activate(ignoringOtherApps: true)
                NotificationCenter.default.post(name: .pilotLauncher, object: nil)
            }
            return noErr
        }, 1, &event, nil, &handler)
        guard installed == noErr else { status = "Global shortcut unavailable. Use Command–K inside MacPilot."; return }
        let result = RegisterEventHotKey(UInt32(kVK_Space), UInt32(cmdKey | shiftKey), EventHotKeyID(signature: 0x4D504C54, id: 1), GetApplicationEventTarget(), 0, &hotKey)
        status = result == noErr ? "Global launcher: Command–Shift–Space" : "Command–Shift–Space is unavailable. Use Command–K inside MacPilot."
    }
}

struct MenuPanel: View {
    @EnvironmentObject var stats: SystemStats
    @EnvironmentObject var tools: Tools
    @EnvironmentObject var clipboard: ClipboardStore
    @Environment(\.openWindow) private var openWindow
    @AppStorage("favoritePanels") private var favorites = "Overview,Clipboard,Large files"
    @ObservedObject private var modes = ModeStore.shared
    var body: some View {
        ScrollView {
        VStack(alignment: .leading, spacing: 14) {
            HStack { Label("MacPilot", systemImage: "command.circle.fill").font(.title2.bold()); Spacer(); Button("Open") { open(.dashboard) } }
            HStack {
                Text("CPU \(Int(stats.cpu))%")
                Spacer()
                Text(String(format: "RAM %.1f GB", stats.memUsed))
                if let b = stats.battery { Text("\(b)%") }
            }.font(.caption).monospacedDigit()
            Divider()
            Toggle("Keep Awake · 1 hour", isOn: Binding(get: { tools.keepAwake }, set: { tools.setKeepAwake($0, minutes: 60) }))
            Toggle("Capture clipboard", isOn: Binding(get: { clipboard.enabled }, set: { clipboard.setEnabled($0) }))
            if let until = tools.awakeUntil { Text("Awake until \(until.formatted(date: .omitted, time: .shortened))").font(.caption) }
            HStack {
                Menu("Start a work mode") {
                    ForEach(modes.modes) { mode in Button(mode.name) { modes.start(mode, tools: tools, clipboard: clipboard) } }
                }.disabled(modes.active != nil || tools.keepAwake)
                if modes.active != nil { Button("End mode") { modes.stop(tools: tools, clipboard: clipboard) } }
            }
            Divider()
            Text(modes.status).font(.caption).foregroundStyle(.secondary).lineLimit(3)
            Text("Favorites").font(.headline)
            ForEach(Panel.allCases.filter { favorites.components(separatedBy: ",").contains($0.rawValue) }) { panel in
                Button { open(panel) } label: { Label(panel.rawValue, systemImage: panel.icon) }
            }
            Menu("Customize favorites") {
                ForEach(Panel.allCases) { panel in
                    Toggle(panel.rawValue, isOn: Binding(get: { favorites.components(separatedBy: ",").contains(panel.rawValue) }, set: { value in
                        var values = Set(favorites.components(separatedBy: ",")); if value { values.insert(panel.rawValue) } else { values.remove(panel.rawValue) }; favorites = values.sorted().joined(separator: ",")
                    }))
                }
            }
            Divider()
            Text("Recent clipboard").font(.headline)
            if clipboard.items.isEmpty { Text("No captured text").foregroundStyle(.secondary) }
            ForEach(Array(clipboard.items.prefix(3)), id: \.self) { item in Button { clipboard.copy(item) } label: { Text(item).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading) } }
            Text(clipboard.feedback).font(.caption).foregroundStyle(.secondary)
            HStack { Button("Find a tool") { openWindow(id: "main"); NSApp.activate(ignoringOtherApps: true); NotificationCenter.default.post(name: .pilotLauncher, object: nil) }; Spacer(); Button("Quit") { NSApp.terminate(nil) } }
        }.padding(20)
        }.frame(width: 360, height: 570)
    }
    private func open(_ panel: Panel) {
        UserDefaults.standard.set(panel.rawValue, forKey: "requestedPanel")
        openWindow(id: "main"); NSApp.activate(ignoringOtherApps: true)
        NotificationCenter.default.post(name: .pilotNavigate, object: panel.rawValue)
    }
}
