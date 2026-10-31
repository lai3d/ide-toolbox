import AppKit
import SwiftUI
import ToolboxCore

@main
struct IDEToolboxApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            ToolboxView(model: delegate.model)
        } label: {
            Image(systemName: delegate.model.updateCount > 0 ? "square.grid.2x2.fill" : "square.grid.2x2")
        }
        .menuBarExtraStyle(.window)
    }
}

/// Owns the model; with `--window` also shows the panel in a regular window
/// (handy when the menu bar is too crowded to show the status item).
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = ToolboxModel()
    private var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if CommandLine.arguments.contains("--window") { showWindow() }
        if CommandLine.arguments.contains("--update-self") {
            // Waits for the launch-time update check, then updates and relaunches if there is something newer.
            Task {
                while model.lastChecked == nil { try? await Task.sleep(for: .milliseconds(200)) }
                await model.updateSelf()
            }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        showWindow()
        return false
    }

    func showWindow() {
        if window == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: ToolboxView(model: model)))
            w.title = "IDE Toolbox"
            w.styleMask = [.titled, .closable]
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

struct ToolboxView: View {
    @Bindable var model: ToolboxModel

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            VStack(spacing: 2) {
                ForEach(model.tools) { ToolRow(model: model, state: $0) }
            }
            .padding(6)
            Divider()
            footer
        }
        .frame(width: 360)
        .onAppear { model.refreshLocal() }
    }

    private var header: some View {
        HStack {
            Text("IDE Toolbox").font(.headline)
            Spacer()
            if model.checking {
                ProgressView().controlSize(.small)
            } else {
                Button {
                    Task { await model.checkForUpdates() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help(model.lastChecked.map { "Checked \($0.formatted(.relative(presentation: .named)))" } ?? "Check for updates")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let update = model.selfUpdate {
                HStack {
                    Text(model.selfUpdateError ?? "IDE Toolbox \(update.version?.description ?? update.tag) is available")
                        .font(.caption)
                        .foregroundStyle(model.selfUpdateError == nil ? Color.accentColor : .red)
                    Spacer()
                    if model.selfUpdating {
                        ProgressView().controlSize(.small)
                    } else if ToolboxModel.replaceableBundle != nil {
                        Button("Update & Relaunch") { Task { await model.updateSelf() } }
                            .controlSize(.small)
                    } else {
                        Button("Download") { NSWorkspace.shared.open(update.pageURL) }
                            .controlSize(.small)
                    }
                }
            }
            Toggle(isOn: $model.launchersEnabled) {
                Text("Command-line launchers in ~/.local/bin")
            }
            .toggleStyle(.checkbox)
            .help("Adds goide, rustide, pyide, javaide, espide, dbide and grove commands, e.g. `pyide .`")
            HStack {
                Text("Installs to ~/Applications").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
                    .buttonStyle(.borderless)
                    .keyboardShortcut("q")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

struct ToolRow: View {
    let model: ToolboxModel
    let state: ToolState
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                icon
                VStack(alignment: .leading, spacing: 1) {
                    Text(state.tool.appName).font(.system(size: 13, weight: .semibold))
                    Text(status).font(.caption).foregroundStyle(statusColor).lineLimit(1)
                }
                Spacer()
                action
                menu
            }
            if let progress = state.progress {
                ProgressView(value: progress).controlSize(.small)
            }
            if !state.recents.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(state.recents.prefix(4), id: \.path) { recent in
                        RecentRow(recent: recent) { model.launch(state, folder: recent.url) }
                    }
                }
                .padding(.leading, 38)
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 6).fill(hovering ? Color.primary.opacity(0.06) : .clear))
        .onHover { hovering = $0 }
    }

    @ViewBuilder private var icon: some View {
        if let url = state.installed?.url {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable().frame(width: 28, height: 28)
        } else {
            Image(systemName: state.tool.symbol)
                .font(.system(size: 15))
                .frame(width: 28, height: 28)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.15)))
        }
    }

    private var status: String {
        if let error = state.error { return error }
        let latest = state.latest.map { $0.version?.description ?? $0.tag }
        if let installed = state.installed {
            if state.updateAvailable, let latest { return "\(installed.versionString) → \(latest) available" }
            return installed.versionString
        }
        if !state.checked { return state.tool.summary }
        if let latest { return "\(state.tool.summary) · \(latest)" }
        return "\(state.tool.summary) · no release yet"
    }

    private var statusColor: Color {
        if state.error != nil { return .red }
        if state.updateAvailable { return .accentColor }
        return .secondary
    }

    @ViewBuilder private var action: some View {
        if state.progress != nil {
            EmptyView()
        } else if state.updateAvailable {
            Button("Update") { Task { await model.install(state) } }
        } else if state.installed != nil {
            Button("Open") { model.launch(state) }
        } else if state.latest != nil {
            Button("Install") { Task { await model.install(state) } }
        }
    }

    private var menu: some View {
        Menu {
            if state.installed != nil {
                if state.tool.acceptsFolderArgument {
                    Button("Open Folder…") { model.chooseFolderAndLaunch(state) }
                }
                Button("Show in Finder") {
                    if let url = state.installed?.url { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                }
            }
            if let page = state.latest?.pageURL {
                Button("Release Notes") { NSWorkspace.shared.open(page) }
            }
            Button("GitHub Repository") { NSWorkspace.shared.open(state.tool.repoURL) }
            if state.installed != nil, state.installed?.url.deletingLastPathComponent() == Installer.defaultInstallDirectory {
                Divider()
                Button("Uninstall") { model.uninstall(state) }
            }
        } label: {
            Image(systemName: "ellipsis")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}

struct RecentRow: View {
    let recent: RecentProject
    let open: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: open) {
            HStack(spacing: 6) {
                Image(systemName: "folder").font(.caption).foregroundStyle(.secondary)
                Text(recent.name).font(.caption)
                Text(abbreviated).font(.caption2).foregroundStyle(.tertiary).lineLimit(1).truncationMode(.head)
                Spacer()
            }
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(hovering ? Color.accentColor : .primary)
        .onHover { hovering = $0 }
        .help(recent.path)
    }

    private var abbreviated: String {
        let parent = recent.url.deletingLastPathComponent().path
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return parent.hasPrefix(home) ? "~" + parent.dropFirst(home.count) : parent
    }
}
