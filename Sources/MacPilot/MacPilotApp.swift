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
                .frame(minWidth: 920, minHeight: 640)
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                    tools.setKeepAwake(false)
                }
        }

        MenuBarExtra {
            MenuPanel()
                .environmentObject(stats)
                .environmentObject(tools)
                .environmentObject(clip)
        } label: {
            Label("\(Int(stats.cpu))%", systemImage: "gauge.with.dots.needle.67percent")
        }.menuBarExtraStyle(.window)
    }
}
