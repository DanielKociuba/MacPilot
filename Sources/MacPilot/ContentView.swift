import SwiftUI
import Charts

enum Panel: String, CaseIterable, Identifiable {
    case dashboard = "Overview", cleaner = "Storage", toggles = "Quick controls", clipboard = "Clipboard", workbench = "Workbench"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .dashboard: return "square.grid.2x2"
        case .cleaner: return "internaldrive"
        case .toggles: return "slider.horizontal.3"
        case .clipboard: return "doc.on.clipboard"
        case .workbench: return "wrench.and.screwdriver"
        }
    }
}

struct ContentView: View {
    @State private var panel: Panel? = .dashboard
    @State private var showCommands = false
    @State private var commandQuery = ""
    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 0) {
                Label("MacPilot", systemImage: "command.circle.fill")
                    .font(.title2.bold()).padding(20)
                List(Panel.allCases, selection: $panel) { item in
                    Label(item.rawValue, systemImage: item.icon).padding(.vertical, 6).tag(item)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Label("On your Mac", systemImage: "lock.shield")
                    Text("No account. No telemetry.").font(.caption)
                }
                .foregroundStyle(.secondary).padding(20)
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 210)
        } detail: {
            switch panel ?? .dashboard {
            case .dashboard: DashboardView(panel: $panel)
            case .cleaner: CleanerView()
            case .toggles: TogglesView()
            case .clipboard: ClipboardView()
            case .workbench: WorkbenchView()
            }
        }
        .tint(.teal)
        .toolbar {
            Button { showCommands = true } label: { Label("Find a tool", systemImage: "magnifyingglass") }
                .keyboardShortcut("k", modifiers: .command)
        }
        .sheet(isPresented: $showCommands) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Find a tool").font(.title2.bold())
                TextField("Search sections", text: $commandQuery).textFieldStyle(.roundedBorder)
                ForEach(Panel.allCases.filter { commandQuery.isEmpty || $0.rawValue.localizedCaseInsensitiveContains(commandQuery) }) { item in
                    Button { panel = item; showCommands = false } label: { Label(item.rawValue, systemImage: item.icon) }
                }
                Button("Close") { showCommands = false }.keyboardShortcut(.cancelAction)
            }.padding(24).frame(width: 360)
        }
    }
}

struct PageHeading: View {
    let title: String
    let subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.largeTitle.bold())
            Text(subtitle).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct Surface<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        content.padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .background(.background, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.primary.opacity(0.08)))
    }
}

struct StatCard: View {
    let title: String
    let value: String
    let detail: String
    let icon: String
    let fraction: Double
    var body: some View {
        Surface {
            VStack(alignment: .leading, spacing: 12) {
                Label(title, systemImage: icon).foregroundStyle(.secondary)
                Text(value).font(.system(size: 26, weight: .semibold, design: .rounded)).monospacedDigit()
                ProgressView(value: min(max(fraction, 0), 1)).accessibilityLabel(title)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

struct DashboardView: View {
    @EnvironmentObject var s: SystemStats
    @EnvironmentObject var t: Tools
    @EnvironmentObject var c: ClipboardStore
    @Binding var panel: Panel?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                PageHeading(title: "Your Mac, at a glance.", subtitle: "Live system readings and the tools you reach for every day.")
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 14)], spacing: 14) {
                    StatCard(title: "Processor", value: s.cpuReady ? "\(Int(s.cpu))%" : "Sampling…", detail: "System-wide CPU utilization", icon: "cpu", fraction: s.cpu / 100)
                    StatCard(title: "Memory", value: String(format: "%.1f GB", s.memUsed), detail: String(format: "Estimated use of %.0f GB · not memory pressure", s.memTotal), icon: "memorychip", fraction: s.memUsed / max(s.memTotal, 1))
                    StatCard(title: "Available storage", value: s.diskTotal > 0 ? fmt(s.diskFree) : "Unavailable", detail: "Includes space macOS can reclaim", icon: "internaldrive", fraction: Double(s.diskFree) / Double(max(s.diskTotal, 1)))
                    if let battery = s.battery {
                        StatCard(title: "Battery", value: "\(battery)%", detail: s.charging ? "Connected and charging" : "Not charging", icon: "battery.100", fraction: Double(battery) / 100)
                    }
                }
                Surface {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Label("CPU activity", systemImage: "waveform.path.ecg").font(.headline)
                            Spacer()
                            Text("Last 60 samples · every 2 seconds").font(.caption).foregroundStyle(.secondary)
                        }
                        if s.history.count < 2 {
                            Text("Collecting live samples…").foregroundStyle(.secondary).frame(height: 130)
                        } else {
                            Chart(s.history) { sample in
                                AreaMark(x: .value("Time", sample.date), y: .value("CPU", sample.cpu))
                                    .foregroundStyle(.teal.opacity(0.12))
                                LineMark(x: .value("Time", sample.date), y: .value("CPU", sample.cpu))
                                    .foregroundStyle(.teal)
                            }
                            .chartYScale(domain: 0...100)
                            .chartXAxis(.hidden)
                            .frame(height: 130)
                            .accessibilityLabel("CPU activity. Current utilization \(Int(s.cpu)) percent.")
                        }
                    }
                }
                Text("Make yourself at home").font(.title2.bold())
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 14)], spacing: 14) {
                    Surface {
                        VStack(alignment: .leading, spacing: 12) {
                            Label("Stay focused", systemImage: "cup.and.saucer.fill").font(.headline)
                            Text(t.keepAwake ? "Keep Awake is active." : "Keep your display and Mac awake for a task.").foregroundStyle(.secondary)
                            Button(t.keepAwake ? "Stop Keep Awake" : "Keep awake for 1 hour") { t.setKeepAwake(!t.keepAwake, minutes: 60) }
                        }
                    }
                    Surface {
                        VStack(alignment: .leading, spacing: 12) {
                            Label("Review your storage", systemImage: "externaldrive").font(.headline)
                            Text("See app caches before deciding what to remove.").foregroundStyle(.secondary)
                            Button("Review caches") { panel = .cleaner }
                        }
                    }
                    Surface {
                        VStack(alignment: .leading, spacing: 12) {
                            Label("Find that copied text", systemImage: "doc.on.clipboard").font(.headline)
                            Text(c.enabled ? "\(c.items.count) items in this session." : "Optional history, kept only in memory.").foregroundStyle(.secondary)
                            Button("Open clipboard") { panel = .clipboard }
                        }
                    }
                }
            }.padding(28)
        }
        .background(Color.primary.opacity(0.025))
        .navigationTitle("Overview")
    }
}

struct CleanerView: View {
    @EnvironmentObject var t: Tools
    @State private var selected: Set<URL> = []
    @State private var confirm = false
    private var selectedBytes: Int64 { t.entries.filter { selected.contains($0.id) }.reduce(0) { $0 + $1.bytes } }
    private var busy: Bool { t.scanning || t.cleaning }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PageHeading(title: "Space to breathe.", subtitle: "Review user cache folders. Choose what goes, and keep control.")
                Surface {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(t.lastScan == nil ? "Ready when you are" : "\(fmt(t.cacheSize)) in scanned caches").font(.title2.bold())
                                if let date = t.lastScan { Text("Scanned \(date.formatted(date: .omitted, time: .shortened))").font(.caption).foregroundStyle(.secondary) }
                            }
                            Spacer()
                            if busy { ProgressView().controlSize(.small) }
                            Button(t.lastScan == nil ? "Scan caches" : "Rescan") {
                                selected = []
                                Task { await t.refreshSizes() }
                            }.disabled(busy)
                        }
                        Text("Close affected apps first. Caches may contain offline content and will often be rebuilt. Moving folders to Trash does not immediately free disk space.")
                            .foregroundStyle(.secondary)
                        Text("Only ~/Library/Caches is scanned. Nothing is selected automatically.").font(.caption).foregroundStyle(.secondary)
                    }
                }
                if !t.entries.isEmpty {
                    HStack {
                        Text("\(selected.count) selected · \(fmt(selectedBytes))").font(.headline)
                        Spacer()
                        Button("Deselect all") { selected = [] }.disabled(selected.isEmpty || busy)
                        Button("Move selected to Trash", role: .destructive) { confirm = true }.disabled(selected.isEmpty || busy)
                    }
                    LazyVStack(spacing: 8) {
                        ForEach(t.entries) { entry in
                            Surface {
                                HStack(spacing: 12) {
                                    Toggle(isOn: Binding(get: { selected.contains(entry.id) }, set: { value in
                                        if value { selected.insert(entry.id) } else { selected.remove(entry.id) }
                                    })) {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(entry.name).font(.headline).textSelection(.enabled)
                                            if entry.unreadableItems > 0 { Text("Partial size · \(entry.unreadableItems) unreadable items").font(.caption).foregroundStyle(.orange) }
                                        }
                                    }.toggleStyle(.checkbox).disabled(busy)
                                    Spacer()
                                    Text(fmt(entry.bytes)).monospacedDigit().foregroundStyle(.secondary)
                                    Button { NSWorkspace.shared.activateFileViewerSelecting([entry.url]) } label: { Image(systemName: "folder") }
                                        .help("Reveal in Finder").accessibilityLabel("Reveal \(entry.name) in Finder")
                                }
                            }
                        }
                    }
                } else if t.lastScan != nil && !busy {
                    Text("No eligible cache folders found.").foregroundStyle(.secondary)
                }
                if t.skipped > 0 { Text("Skipped \(t.skipped) non-folder or symbolic-link entries.").font(.caption).foregroundStyle(.secondary) }
                if !t.cleanupReport.isEmpty { Text(t.cleanupReport).textSelection(.enabled).foregroundStyle(.secondary) }
                if !t.status.isEmpty { Text(t.status).font(.callout).foregroundStyle(.secondary) }
            }.padding(28)
        }
        .navigationTitle("Storage")
        .alert("Move \(selected.count) cache folders to Trash?", isPresented: $confirm) {
            Button("Cancel", role: .cancel) { }
            Button("Move to Trash", role: .destructive) {
                let ids = selected
                selected = []
                Task { await t.cleanCaches(ids: ids) }
            }
        } message: {
            Text("Quit affected apps first. You can inspect the moved folders in Trash. MacPilot will not empty it; use Finder when you are ready to permanently remove them.")
        }
    }
}

struct TogglesView: View {
    @EnvironmentObject var t: Tools
    @State private var minutes = 60
    @State private var confirmFinder = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PageHeading(title: "Small controls. Less friction.", subtitle: "A few useful adjustments, always within reach.")
                Surface {
                    VStack(alignment: .leading, spacing: 16) {
                        Label("Keep Awake", systemImage: "cup.and.saucer.fill").font(.title2.bold())
                        Text("Prevent idle system and display sleep during a presentation, download, or focused work. This uses more battery; closing the lid can still put your Mac to sleep.").foregroundStyle(.secondary)
                        Picker("Session length", selection: $minutes) {
                            Text("15 minutes").tag(15)
                            Text("30 minutes").tag(30)
                            Text("1 hour").tag(60)
                            Text("2 hours").tag(120)
                            Text("Until stopped or app quits").tag(0)
                        }.disabled(t.keepAwake)
                        HStack {
                            Button(t.keepAwake ? "Stop session" : "Start session") { t.setKeepAwake(!t.keepAwake, minutes: minutes == 0 ? nil : minutes) }.buttonStyle(.borderedProminent)
                            if let until = t.awakeUntil { Text("Ends at \(until.formatted(date: .omitted, time: .shortened))").foregroundStyle(.secondary) }
                            else if t.keepAwake { Text("Active until stopped or app quits").foregroundStyle(.secondary) }
                        }
                    }
                }
                Surface {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Finder visibility", systemImage: "eye").font(.title2.bold())
                        Text("Hidden files are currently \(t.hiddenFiles ? "visible" : "hidden"). Changing this setting restarts Finder and may interrupt Finder operations.").foregroundStyle(.secondary)
                        Button(t.hiddenFiles ? "Hide hidden files…" : "Show hidden files…") { confirmFinder = true }.disabled(t.changingFinder)
                    }
                }
                if !t.status.isEmpty { Text(t.status).foregroundStyle(.secondary) }
            }.padding(28)
        }
        .navigationTitle("Quick controls")
        .alert("Restart Finder to apply this setting?", isPresented: $confirmFinder) {
            Button("Cancel", role: .cancel) { }
            Button("Apply and restart Finder") { Task { await t.setHiddenFiles(!t.hiddenFiles) } }
        } message: { Text("Wait for any Finder file transfers to finish first.") }
    }
}

struct ClipboardView: View {
    @EnvironmentObject var c: ClipboardStore
    @State private var query = ""
    private var matches: [String] { c.items.filter { query.isEmpty || $0.localizedCaseInsensitiveContains(query) } }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            PageHeading(title: "Good ideas, kept close.", subtitle: "Find and reuse copied text from this session.")
            Surface {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle("Capture clipboard history", isOn: Binding(get: { c.enabled }, set: { c.setEnabled($0) }))
                    Text("Off by default at every launch. Stores up to 50 text items in memory, never on disk. Pausing stops new captures; Clear history removes saved items.").font(.callout).foregroundStyle(.secondary)
                    Text("Items marked concealed by other apps are skipped. Not every app marks passwords or private text—pause capture before copying sensitive information.").font(.caption).foregroundStyle(.secondary)
                }
            }
            HStack {
                TextField("Search copied text", text: $query).textFieldStyle(.roundedBorder)
                Button("Clear history") { c.clear() }.disabled(c.items.isEmpty)
            }
            if matches.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "doc.on.clipboard").font(.system(size: 36)).foregroundStyle(.teal)
                    Text(query.isEmpty ? (c.enabled ? "Copy something to get started" : "Your clipboard, your choice") : "No matching text").font(.headline)
                    Text(query.isEmpty ? (c.enabled ? "New text you copy will appear here." : "Enable capture above when you want a history.") : "Try another search.").foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(matches, id: \.self) { item in
                    HStack(spacing: 12) {
                        Text(item).lineLimit(3).frame(maxWidth: .infinity, alignment: .leading)
                        Button("Copy") { c.copy(item) }
                        Button { c.remove(item) } label: { Image(systemName: "xmark.circle") }
                            .accessibilityLabel("Remove item from history")
                    }.padding(.vertical, 8)
                }.listStyle(.inset)
            }
            HStack {
                Text("\(c.items.count) / 50 items · \(c.enabled ? "Capturing" : "Paused")")
                Spacer()
                Text(c.feedback)
            }.font(.caption).foregroundStyle(.secondary)
        }.padding(28)
        .navigationTitle("Clipboard")
    }
}
