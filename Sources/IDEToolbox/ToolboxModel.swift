import AppKit
import Observation
import ToolboxCore

@MainActor
@Observable
final class ToolState: Identifiable {
    let tool: Tool
    var installed: InstalledApp?
    var latest: Release?
    var checked = false
    var progress: Double?
    var error: String?
    var recents: [RecentProject] = []

    nonisolated var id: String { tool.id }

    init(tool: Tool) { self.tool = tool }

    var updateAvailable: Bool {
        guard let installed, let latestVersion = latest?.version else { return false }
        guard let current = installed.version else { return true }
        return current < latestVersion
    }

    var isRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: tool.bundleID).isEmpty
    }
}

@MainActor
@Observable
final class ToolboxModel {
    let tools: [ToolState] = Catalog.tools.map(ToolState.init)
    var lastChecked: Date?
    var checking = false
    var launchersEnabled: Bool {
        didSet {
            UserDefaults.standard.set(launchersEnabled, forKey: "launchersEnabled")
            syncLaunchers()
        }
    }

    private let installer = Installer()
    private let releases = GitHubReleases()
    private let recentsStore = RecentsStore()
    let launchers = Launchers()
    private var timer: Timer?

    var updateCount: Int { tools.filter(\.updateAvailable).count }

    init() {
        launchersEnabled = UserDefaults.standard.bool(forKey: "launchersEnabled")
        refreshLocal()
        Task { await checkForUpdates() }
        timer = Timer.scheduledTimer(withTimeInterval: 6 * 3600, repeats: true) { [weak self] _ in
            Task { await self?.checkForUpdates() }
        }
    }

    /// Re-reads installed versions and recents from disk (cheap; done whenever the menu opens).
    func refreshLocal() {
        for state in tools {
            state.installed = installer.installed(state.tool)
            state.recents = state.installed == nil ? [] : recentsStore.recents(for: state.tool)
        }
        syncLaunchers()
    }

    func checkForUpdates() async {
        guard !checking else { return }
        checking = true
        defer { checking = false }
        await withTaskGroup(of: Void.self) { group in
            for state in tools {
                group.addTask { await self.fetchLatest(state) }
            }
        }
        lastChecked = Date()
    }

    private func fetchLatest(_ state: ToolState) async {
        do {
            state.latest = try await releases.latest(for: state.tool)
            state.error = nil
        } catch {
            state.error = error.localizedDescription
        }
        state.checked = true
    }

    func install(_ state: ToolState) async {
        guard let release = state.latest, state.progress == nil else { return }
        if state.isRunning {
            state.error = "Quit \(state.tool.appName) first"
            return
        }
        state.error = nil
        state.progress = 0
        defer { state.progress = nil }
        do {
            try await installer.install(state.tool, release: release) { p in
                Task { @MainActor in if state.progress != nil { state.progress = p } }
            }
            refreshLocal()
        } catch {
            state.error = error.localizedDescription
        }
    }

    func uninstall(_ state: ToolState) {
        do {
            try installer.uninstall(state.tool)
            launchers.remove(state.tool)
            refreshLocal()
        } catch {
            state.error = error.localizedDescription
        }
    }

    func launch(_ state: ToolState, folder: URL? = nil) {
        guard let app = state.installed?.url else { return }
        let config = NSWorkspace.OpenConfiguration()
        if let folder, state.tool.acceptsFolderArgument {
            config.arguments = [folder.path]
            // Arguments only reach a freshly launched process, and each IDE window is one project.
            config.createsNewApplicationInstance = state.isRunning
            try? recentsStore.record(folder.path, bundleID: state.tool.bundleID)
        }
        NSWorkspace.shared.openApplication(at: app, configuration: config) { _, error in
            if let error {
                Task { @MainActor in state.error = error.localizedDescription }
            }
        }
    }

    func chooseFolderAndLaunch(_ state: ToolState) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Open in \(state.tool.appName)"
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        launch(state, folder: url)
        refreshLocal()
    }

    private func syncLaunchers() {
        for state in tools {
            if launchersEnabled, let app = state.installed?.url {
                do { try launchers.install(state.tool, app: app) } catch {
                    state.error = "Launcher: \(error.localizedDescription)"
                }
            } else if !launchersEnabled || state.installed == nil {
                launchers.remove(state.tool)
            }
        }
    }
}
