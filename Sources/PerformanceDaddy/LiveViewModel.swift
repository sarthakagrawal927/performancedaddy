import AppKit
import Combine
import PerformanceCore
import UniformTypeIdentifiers

enum LivePage: String, CaseIterable, Identifiable {
    case workloads = "Processes", ports = "Ports", agents = "Agent sessions", memory = "Memory"
    var id: Self { self }
    var icon: String {
        switch self {
        case .workloads: "list.bullet.indent"
        case .ports: "network"
        case .agents: "terminal"
        case .memory: "memorychip"
        }
    }
    var subtitle: String {
        switch self {
        case .workloads: "See what is running. Follow its children, inspect its footprint, or stop it."
        case .ports: "Find a local listener and the process keeping its port occupied."
        case .agents: "Local coding-agent families, their projects and resource use."
        case .memory: "Watch memory pressure, RAM headroom and the largest resident processes."
        }
    }
}

@MainActor
final class LiveViewModel: ObservableObject {
    struct MemoryPoint: Identifiable { let id = UUID(); let date: Date; let used: Double }
    struct Review: Identifiable { let id = UUID(); let targets: [LiveProcess] }
    @Published var snapshot: LiveSnapshot? {
        didSet { index = WorkloadIndex(snapshot?.processes ?? []); rowCache.removeAll(); agentRows = nil; cachedRoots = nil }
    }
    @Published var search = "" { didSet { rowCache.removeAll() } }
    @Published var sortOrder = [KeyPathComparator(\LiveProcess.sortCPU, order: .reverse)] { didSet { rowCache.removeAll() } }
    @Published var selection: Set<ProcessIdentity> = []
    @Published var paused = false { didSet { if paused != oldValue { needsNewMeasurementWindow = true } } }
    @Published var includeSystem = false { didSet { rowCache.removeAll() } }
    @Published var memoryHistory: [MemoryPoint] = []
    @Published var review: Review?
    @Published var outcomes: [StopResult] = []
    @Published var performingAction = false
    @Published var refreshing = false
    @Published var exportNotice: String?
    private let sampler = WorkloadSampler()
    private var task: Task<Void, Never>?
    private var index = WorkloadIndex([])
    private var rowCache: [LivePage: [LiveProcess]] = [:]
    private var agentRows: [LiveProcess]?
    private var cachedRoots: [LiveProcess]?
    private var agentRoots: [LiveProcess] {
        if let cachedRoots { return cachedRoots }
        let roots = index.agentRoots
        cachedRoots = roots
        return roots
    }
    private var needsNewMeasurementWindow = false
    private var processHistory = ProcessMemoryHistory()
    private let historyOrigin = ContinuousClock.now
    private(set) var lifecycle = ProcessLifecycleJournal()
    private let lifecycleStore: LifecycleHistoryStore
    private var lifecycleSaveTask: Task<Void, Never>?
    private var lifecycleLoaded = false
    private var confirmedExits: Set<ProcessIdentity> = []
    private var wakeObserver: NSObjectProtocol?

    init(lifecycleStore: LifecycleHistoryStore = LifecycleHistoryStore()) {
        self.lifecycleStore = lifecycleStore
    }

    func start() {
        guard task == nil else { return }
        if wakeObserver == nil {
            wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.handleSystemWake() }
            }
        }
        task = Task { [weak self] in
            await self?.restoreLifecycle()
            while !Task.isCancelled {
                guard let self else { return }
                let previousEventCount = lifecycle.events.count
                lifecycle.expire(at: Date())
                if lifecycle.events.count != previousEventCount {
                    objectWillChange.send()
                    persistLifecycle()
                }
                if !paused && review == nil && !performingAction { await refresh() }
                let interval = max(2, min(10, (snapshot?.scanSeconds ?? 0) * 20))
                do { try await Task.sleep(for: .seconds(interval)) } catch { return }
            }
        }
    }

    func refresh() async {
        guard !refreshing else { return }
        refreshing = true
        if needsNewMeasurementWindow {
            needsNewMeasurementWindow = false
            processHistory.reset()
            await sampler.resetMeasurementWindow()
        }
        let result = await sampler.sample()
        let previousEventCount = lifecycle.events.count
        lifecycle.observe(result.processes, at: result.date)
        let checks = Set(lifecycle.pendingExitChecks + outcomes.filter(\.signalSent).map { $0.process.id }).subtracting(confirmedExits)
        let gone = await Task.detached(priority: .utility) {
            checks.filter { ProcessPresence.inspect($0) == .gone }
        }.value
        let checkedAt = Date()
        for identity in gone { lifecycle.confirmExit(identity, presence: .gone, at: checkedAt) }
        confirmedExits.formUnion(gone)
        confirmedExits.formIntersection(Set(lifecycle.pendingExitChecks + outcomes.map { $0.process.id }))
        let elapsed = historyOrigin.duration(to: .now).components
        processHistory.observe(result.processes, at: Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18)
        snapshot = result
        selection.formIntersection(Set(result.processes.map(\.id)))
        if let headroom = result.system.memoryHeadroomRatio, headroom.isFinite, (0...1).contains(headroom) {
            memoryHistory.append(MemoryPoint(date: result.date, used: 1 - headroom))
            memoryHistory.removeAll { $0.date < result.date.addingTimeInterval(-300) }
        }
        refreshing = false
        if lifecycle.events.count != previousEventCount { persistLifecycle() }
    }

    func rows(for page: LivePage) -> [LiveProcess] {
        if let cached = rowCache[page] { return cached }
        let all = snapshot?.processes ?? []
        if page == .agents && agentRows == nil {
            agentRows = agentRoots.map { root in
            let family = index.descendants(of: root)
            return LiveProcess(id: root.id, parent: root.parent, uid: root.uid, name: root.name,
                               executable: root.executable, directory: root.directory,
                               cpu: family.contains(where: { $0.cpu != nil }) ? family.reduce(0) { $0 + ($1.cpu ?? 0) } : nil,
                               memory: family.reduce(0) { total, process in
                                   let sum = total.addingReportingOverflow(process.memory)
                                   return sum.overflow ? UInt64.max : sum.partialValue
                               },
                               ports: Array(Set(family.flatMap(\.ports))).sorted { $0.id < $1.id },
                               portsIncomplete: family.contains(where: \.portsIncomplete))
            }
        }
        let candidates = page == .agents ? (agentRows ?? []) : all
        let result = candidates.filter { process in
            guard includeSystem || process.isUserProcess else { return false }
            if page == .ports && process.ports.isEmpty { return false }
            if page == .agents && process.agent == nil { return false }
            if !search.isEmpty {
                let haystack = "\(process.sortName) \(process.name) \(process.id.pid) \(process.directory) \(process.appPath ?? "") \(ancestorApp(of: process)?.appPath ?? "") \(process.catalog?.category ?? "") \(process.catalog?.role ?? "") \(process.ports.map(\.endpoint).joined(separator: " "))"
                if !haystack.localizedCaseInsensitiveContains(search) { return false }
            }
            return true
        }.sorted(using: sortOrder + [KeyPathComparator(\LiveProcess.id.pid)])
        rowCache[page] = result
        return result
    }

    func family(of process: LiveProcess) -> [LiveProcess] { index.descendants(of: process) }
    func ancestorApp(of process: LiveProcess) -> LiveProcess? {
        index.ancestors(of: process).first { $0.appPath != nil }
    }
    func processSubtitle(_ process: LiveProcess) -> String {
        if let catalog = process.catalog { return "\(catalog.category) · \(process.id.pid)" }
        if let path = process.appPath { return "\(URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent) · \(process.id.pid)" }
        return process.directory.isEmpty || process.directory == "/" ? "PID \(process.id.pid)" : "\(URL(fileURLWithPath: process.directory).lastPathComponent) · \(process.id.pid)"
    }
    func memoryTrend(for process: LiveProcess) -> ProcessMemoryTrend? { processHistory.trend(for: process.id) }
    func observedProcess(_ process: LiveProcess) -> LiveProcess? { snapshot?.processes.first { $0.id == process.id } }

    var selected: LiveProcess? { snapshot?.processes.first { selection.contains($0.id) } }
    var portCount: Int { snapshot?.processes.reduce(0) { $0 + $1.ports.count } ?? 0 }
    var agentCount: Int { agentRoots.count }
    var observerSummary: String {
        guard let snapshot, let own = snapshot.processes.first(where: { $0.id.pid == ProcessInfo.processInfo.processIdentifier }) else { return "Monitor measuring" }
        let cpu = own.cpu.map { String(format: "%.1f%% CPU", $0) } ?? "CPU measuring"
        let duration = snapshot.scanSeconds * 1_000
        let scan = duration.isFinite && duration >= 0 && duration < Double(Int.max) ? "\(Int(duration)) ms" : "unavailable"
        return "Monitor \(cpu) · \(Self.bytes(own.memory)) · scan \(scan)"
    }
    var usedMemory: String {
        guard let headroom = snapshot?.system.memoryHeadroomRatio, headroom.isFinite, (0...1).contains(headroom) else { return "—" }
        return Self.bytes(UInt64(Double(ProcessInfo.processInfo.physicalMemory) * (1 - headroom)))
    }
    // MainActor confinement permits reuse without cross-thread formatter access.
    private static let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .memory
        return formatter
    }()
    static func bytes(_ bytes: UInt64) -> String { byteFormatter.string(fromByteCount: Int64(clamping: bytes)) }

    func exportSnapshot() {
        guard let captured = snapshot else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "performancedaddy-snapshot.json"
        panel.message = "Save all sampled processes, not just the filtered rows. Names, paths, raw PIDs and bind addresses are omitted. Agent types, resource measurements and port numbers remain."
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                let data = try SnapshotExport.data(for: captured, physicalMemory: ProcessInfo.processInfo.physicalMemory)
                try data.write(to: url, options: .atomic)
                self.exportNotice = "Redacted snapshot saved."
            } catch {
                self.exportNotice = "Could not save the snapshot. Choose another writable location and try again."
            }
        }
    }

    func prepare(_ targets: [LiveProcess]) {
        let eligible = targets.filter { $0.stopRestriction == nil }
        guard !eligible.isEmpty else { return }
        review = Review(targets: eligible)
    }
    func prepareSelected() {
        prepare((snapshot?.processes ?? []).filter { selection.contains($0.id) })
    }
    func prepareTree(_ process: LiveProcess) {
        prepare(index.descendants(of: process))
    }
    func prepareFamilies(_ roots: [LiveProcess]) {
        var seen: Set<ProcessIdentity> = []
        prepare(roots.flatMap { index.descendants(of: $0) }.filter { seen.insert($0.id).inserted })
    }
    func confirmStop(force: Bool) async {
        guard let reviewed = review else { return }
        performingAction = true
        review = nil
        let beforeStop = snapshot?.processes ?? []
        outcomes = await Task.detached {
            ProcessControl.stop(reviewed.targets.reversed(), force: force)
        }.value
        for outcome in outcomes {
            guard let date = outcome.signalDate else { continue }
            lifecycle.record(outcome.process, at: date, force: force,
                signalSent: outcome.signalSent, observed: beforeStop)
        }
        persistLifecycle()
        try? await Task.sleep(for: .seconds(1))
        await refresh()
        performingAction = false
    }
    func outcomeText(_ result: StopResult) -> String {
        guard result.signalSent else { return result.message }
        if confirmedExits.contains(result.process.id) { return "Exit confirmed; original process identity is gone" }
        let live = snapshot?.processes.contains { $0.id == result.process.id } ?? false
        return live ? "Signal sent; process still observed" : "Signal sent; exit not confirmed (inspection unavailable)"
    }

    func handleSystemWake() {
        needsNewMeasurementWindow = true
    }

    func restoreLifecycle() async {
        guard !lifecycleLoaded else { return }
        lifecycleLoaded = true
        let events = await lifecycleStore.load()
        lifecycle = ProcessLifecycleJournal(events: events)
        objectWillChange.send()
    }

    func waitForLifecyclePersistence() async {
        await lifecycleSaveTask?.value
    }

    private func persistLifecycle() {
        let events = lifecycle.events
        let previous = lifecycleSaveTask
        let store = lifecycleStore
        lifecycleSaveTask = Task {
            await previous?.value
            try? await store.save(events)
        }
    }
}

// Presentation keys keep native column sorting aligned with the displayed values.
extension LiveProcess {
    var sortRunning: Double { ProcessUnderstanding.duration(id, at: Date()) == nil ? -Double.greatestFiniteMagnitude : -Double(id.started) }
    var sortName: String { agent ?? name }
    var sortCPU: Double { cpu ?? -1 }
    var sortPort: Int { ports.map { Int($0.port) }.min() ?? 65_536 }
    var portLabel: String { Set(ports.map(\.port)).sorted().map(String.init).joined(separator: ", ") }
}
