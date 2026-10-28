import Combine
import Foundation
import IOKit.ps

struct CPUSample: Identifiable {
    let id = UUID()
    let date: Date
    let cpu: Double
}

@MainActor
final class SystemStats: ObservableObject {
    @Published var history: [CPUSample] = []
    @Published var cpuReady = false
    @Published var cpu: Double = 0              // percent
    @Published var memUsed: Double = 0          // GB
    @Published var memTotal: Double = Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824
    @Published var diskFree: Int64 = 0
    @Published var diskTotal: Int64 = 0
    @Published var battery: Int?                // nil on desktops
    @Published var charging = false

    private var prevTicks: [UInt32]?
    private var timer: Timer?

    init() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func refresh() {
        readCPU(); readMemory(); readDisk(); readBattery()
        if cpuReady {
            history.append(CPUSample(date: Date(), cpu: cpu))
            history = Array(history.suffix(60))
        }
    }

    private func readCPU() {
        var size = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.stride / MemoryLayout<integer_t>.stride)
        var info = host_cpu_load_info()
        let r = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(size)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &size)
            }
        }
        guard r == KERN_SUCCESS else { return }
        let t = info.cpu_ticks   // (user, system, idle, nice)
        let now = [t.0, t.1, t.2, t.3]
        if let p = prevTicks {
            let d = zip(now, p).map { Double($0 &- $1) }
            let total = d.reduce(0, +)
            if total > 0 { cpu = (d[0] + d[1] + d[3]) / total * 100; cpuReady = true }
        }
        prevTicks = now
    }

    private func readMemory() {
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride)
        var s = vm_statistics64()
        let r = withUnsafeMutablePointer(to: &s) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard r == KERN_SUCCESS else { return }
        let page = Double(getpagesize())
        let pages = Double(s.active_count) + Double(s.wire_count) + Double(s.compressor_page_count)
        memUsed = pages * page / 1_073_741_824
    }

    private func readDisk() {
        let keys: Set<URLResourceKey> = [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey]
        if let v = try? URL(fileURLWithPath: "/").resourceValues(forKeys: keys) {
            diskFree = v.volumeAvailableCapacityForImportantUsage ?? 0
            diskTotal = Int64(v.volumeTotalCapacity ?? 0)
        }
    }

    private func readBattery() {
        let snap = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        let list = IOPSCopyPowerSourcesList(snap).takeRetainedValue() as [CFTypeRef]
        battery = nil
        charging = false
        for ps in list {
            guard let d = IOPSGetPowerSourceDescription(snap, ps)?.takeUnretainedValue() as? [String: Any] else { continue }
            guard d[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                  let current = d[kIOPSCurrentCapacityKey] as? Int,
                  let maximum = d[kIOPSMaxCapacityKey] as? Int, maximum > 0 else { continue }
            battery = min(100, max(0, Int(Double(current) / Double(maximum) * 100)))
            charging = (d[kIOPSIsChargingKey] as? Bool) ?? false
        }
    }
}
