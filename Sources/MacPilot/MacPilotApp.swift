import SwiftUI

@main
struct MacPilotApp: App {
    @StateObject private var stats = SystemStats()
    @StateObject private var tools = Tools()
    @StateObject private var clip = ClipboardStore()

    var body: some Scene {
        WindowGroup("MacPilot", id: "main") {
            ContentView()
                .environmentObject(stats)
                .environmentObject(tools)
                .environmentObject(clip)
                .frame(minWidth: 760, minHeight: 500)
        }

        MenuBarExtra {
            MenuContent()
                .environmentObject(stats)
                .environmentObject(tools)
        } label: {
            Label("\(Int(stats.cpu))%", systemImage: "gauge.with.dots.needle.67percent")
        }
    }
}

struct MenuContent: View {
    @EnvironmentObject var stats: SystemStats
    @EnvironmentObject var tools: Tools
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text("CPU \(Int(stats.cpu))%  ·  RAM \(String(format: "%.1f", stats.memUsed))/\(String(format: "%.0f", stats.memTotal)) GB")
        Divider()
        Toggle("Keep Awake", isOn: Binding(get: { tools.keepAwake }, set: { tools.setKeepAwake($0) }))
        Button("Open MacPilot") {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }
        Divider()
        Button("Quit") { NSApp.terminate(nil) }
    }
}
