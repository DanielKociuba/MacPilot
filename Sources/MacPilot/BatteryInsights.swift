import SwiftUI
import Charts
import IOKit

struct BatterySample: Codable, Identifiable {
    var id: Date { date }
    let date: Date
    let percent: Int
    let onAC: Bool
}

struct BatteryInsightsView: View {
    @EnvironmentObject var stats: SystemStats
    @State private var hardware = ""
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PageHeading(title: "Know your battery", subtitle: "Charging state and locally recorded history. No per-app drain claims or charge-limit modifications.")
                if let percent = stats.battery {
                    Text("\(percent)% · \(stats.onAC ? "External power" : "Battery power") · \(stats.charging ? "Charging" : "Not charging")").font(.title2.bold())
                    Text(hardware).foregroundStyle(.secondary)
                    if stats.batteryHistory.count > 1 {
                        Chart(stats.batteryHistory) { point in
                            LineMark(x: .value("Time", point.date), y: .value("Charge", point.percent))
                                .foregroundStyle(.teal)
                        }.chartYScale(domain: 0...100).frame(height: 220)
                    } else { Text("History builds while MacPilot runs, sampled once a minute.") }
                    Text(drainDescription).font(.headline)
                    Text("Rate is based on consecutive battery-power samples from the last hour. At least 10 minutes of continuous observations are required; sleep gaps and charging interrupt the estimate. Battery percentage is coarse, so short-window rates vary.").font(.caption).foregroundStyle(.secondary)
                    Button("Clear battery history") { stats.clearBatteryHistory() }
                    Text("Up to seven days of charge level and power-source history are stored locally. Recording stops when MacPilot quits.").font(.caption).foregroundStyle(.secondary)
                } else { Text("No internal battery was reported. Desktop Macs can still use all other tools.") }
            }.padding(24)
        }.onAppear { readHardware() }
    }
    private var drainDescription: String {
        let points = stats.batteryHistory.filter { $0.date > Date().addingTimeInterval(-3600) }
        var segment: [BatterySample] = []
        for point in points {
            if point.onAC { segment = []; continue }
            if let previous = segment.last, point.date.timeIntervalSince(previous.date) > 120 { segment = [] }
            segment.append(point)
        }
        guard let first = segment.first, let last = segment.last, last.date.timeIntervalSince(first.date) >= 600, last.percent <= first.percent, !stats.onAC else { return "Gathering enough continuous battery data for a drain estimate…" }
        let rate = Double(first.percent - last.percent) / last.date.timeIntervalSince(first.date) * 3600
        return String(format: "Observed drain: %.1f percentage points per hour", rate)
    }
    private func readHardware() {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { hardware = "Battery hardware details unavailable."; return }
        defer { IOObjectRelease(service) }
        func number(_ key: String) -> Double? {
            (IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? NSNumber)?.doubleValue
        }
        var parts: [String] = []
        if let cycles = number("CycleCount") { parts.append("Cycle count: \(Int(cycles))") }
        if let full = number("AppleRawMaxCapacity"), let design = number("DesignCapacity"), design > 0, full > 0 {
            parts.append(String(format: "Reported full/design capacity: %.0f%% (estimate)", full / design * 100))
        }
        hardware = parts.isEmpty ? "Capacity details unavailable on this hardware. Use Battery settings for Apple’s condition assessment." : parts.joined(separator: " · ") + "\nUse Battery settings for Apple’s condition assessment."
    }
}
