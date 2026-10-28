import SwiftUI

enum Panel: String, CaseIterable, Identifiable {
    case dashboard = "Dashboard", cleaner = "Cleaner", toggles = "Toggles", clipboard = "Clipboard"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .dashboard: return "gauge.with.dots.needle.67percent"
        case .cleaner:   return "sparkles"
        case .toggles:   return "switch.2"
        case .clipboard: return "doc.on.clipboard"
        }
    }
}

struct ContentView: View {
    @State private var panel: Panel? = .dashboard

    var body: some View {
        NavigationSplitView {
            List(Panel.allCases, selection: $panel) { p in
                Label(p.rawValue, systemImage: p.icon).tag(p)
            }
            .navigationSplitViewColumnWidth(min: 160, ideal: 180)
        } detail: {
            switch panel ?? .dashboard {
            case .dashboard: DashboardView()
            case .cleaner:   CleanerView()
            case .toggles:   TogglesView()
            case .clipboard: ClipboardView()
            }
        }
    }
}

struct StatCard: View {
    let title: String, value: String, icon: String, fraction: Double
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: icon).font(.headline).foregroundStyle(.secondary)
            Text(value).font(.system(size: 28, weight: .semibold, design: .rounded))
            ProgressView(value: min(max(fraction, 0), 1))
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 14))
    }
}

struct DashboardView: View {
    @EnvironmentObject var s: SystemStats
    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 16)], spacing: 16) {
                StatCard(title: "CPU", value: "\(Int(s.cpu))%", icon: "cpu", fraction: s.cpu / 100)
                StatCard(title: "Memory",
                         value: String(format: "%.1f / %.0f GB", s.memUsed, s.memTotal),
                         icon: "memorychip", fraction: s.memUsed / max(s.memTotal, 1))
                StatCard(title: "Disk",
                         value: "\(fmt(s.diskFree)) free",
                         icon: "internaldrive",
                         fraction: 1 - Double(s.diskFree) / Double(max(s.diskTotal, 1)))
                if let b = s.battery {
                    StatCard(title: "Battery", value: "\(b)%\(s.charging ? " ⚡︎" : "")",
                             icon: "battery.100", fraction: Double(b) / 100)
                }
            }
            .padding(20)
        }
        .navigationTitle("Dashboard")
    }
}

struct CleanerView: View {
    @EnvironmentObject var t: Tools
    var body: some View {
        Form {
            row("User caches", size: t.cacheSize, button: "Clean") { await t.cleanCaches() }
            row("Trash", size: t.trashSize, button: "Empty") { await t.emptyTrash() }
            if !t.status.isEmpty { Text(t.status).foregroundStyle(.secondary) }
            Text("Caches live in ~/Library/Caches; apps rebuild them as needed.")
                .font(.footnote).foregroundStyle(.tertiary)
        }
        .formStyle(.grouped)
        .navigationTitle("Cleaner")
        .toolbar { Button("Rescan", systemImage: "arrow.clockwise") { Task { await t.refreshSizes() } } }
    }

    private func row(_ title: String, size: Int64, button: String, action: @escaping () async -> Void) -> some View {
        HStack {
            VStack(alignment: .leading) { Text(title).font(.headline); Text(fmt(size)).foregroundStyle(.secondary) }
            Spacer()
            Button(button) { Task { await action() } }
        }
    }
}

struct TogglesView: View {
    @EnvironmentObject var t: Tools
    var body: some View {
        Form {
            Toggle("Keep Mac awake", isOn: Binding(get: { t.keepAwake }, set: { t.setKeepAwake($0) }))
            Toggle("Show hidden files in Finder", isOn: Binding(get: { t.hiddenFiles }, set: { t.setHiddenFiles($0) }))
        }
        .formStyle(.grouped)
        .navigationTitle("Toggles")
    }
}

struct ClipboardView: View {
    @EnvironmentObject var c: ClipboardStore
    var body: some View {
        Group {
            if c.items.isEmpty {
                ContentUnavailableView("Nothing copied yet", systemImage: "doc.on.clipboard",
                                       description: Text("Text you copy will show up here."))
            } else {
                List(c.items, id: \.self) { item in
                    Text(item).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .onTapGesture { c.copy(item) }
                        .help("Click to copy again")
                }
            }
        }
        .navigationTitle("Clipboard")
        .toolbar { Button("Clear", systemImage: "trash") { c.clear() }.disabled(c.items.isEmpty) }
    }
}
