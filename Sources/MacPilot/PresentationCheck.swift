import SwiftUI
import CoreAudio

struct PresentationCheckView: View {
    @EnvironmentObject var stats: SystemStats
    @State private var audio = ""
    @State private var displays: [String] = []
    var body: some View {
        DisclosureGroup("Presentation check") {
            VStack(alignment: .leading, spacing: 8) {
                if let b = stats.battery {
                    Text("Battery: \(b)% · \(stats.onAC ? "External power" : "Battery power")")
                        .foregroundStyle(b < 20 && !stats.onAC ? Color.orange : Color.primary)
                    if b < 20 && !stats.onAC { Text("Connect power before a long presentation.").foregroundStyle(.orange) }
                }
                Text("Displays: " + displays.joined(separator: ", "))
                Text("Audio output: " + audio)
                Text("Close private windows and verify notification settings before sharing your screen.").font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("Refresh devices") { refresh() }
                    Button("Sound settings") { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Sound-Settings.extension")!) }
                }
            }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 8)
        }.onAppear { refresh() }
    }
    private func refresh() {
        displays = NSScreen.screens.map { "\($0.localizedName) (\(Int($0.frame.width)) × \(Int($0.frame.height)) points)" }
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr else { audio = "Unavailable"; return }
        address.mSelector = kAudioObjectPropertyName
        var name: CFString = "Unknown" as CFString
        size = UInt32(MemoryLayout<CFString>.size)
        let result = withUnsafeMutablePointer(to: &name) { pointer in
            AudioObjectGetPropertyData(device, &address, 0, nil, &size, pointer)
        }
        audio = result == noErr ? name as String : "Unavailable"
    }
}
