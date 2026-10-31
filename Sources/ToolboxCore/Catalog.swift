import Foundation

/// One app the Toolbox knows how to install, update and launch.
public struct Tool: Identifiable, Hashable, Sendable {
    /// Bundle identifier, also used as the stable id.
    public let id: String
    /// Display name, also the `.app` name (`<appName>.app`).
    public let appName: String
    /// `owner/repo` on GitHub; releases come from here.
    public let repo: String
    public let summary: String
    /// SF Symbol shown before the app is installed.
    public let symbol: String
    /// Name of the generated command-line launcher, e.g. `pyide`.
    public let cliName: String
    /// Whether the app opens a folder passed as its first launch argument.
    public let acceptsFolderArgument: Bool
    /// Legacy recents: a string-array key in the app's own UserDefaults domain.
    public let recentsDefaultsKey: String?

    public var bundleID: String { id }
    public var repoURL: URL { URL(string: "https://github.com/\(repo)")! }

    public init(id: String, appName: String, repo: String, summary: String, symbol: String,
                cliName: String, acceptsFolderArgument: Bool, recentsDefaultsKey: String? = nil) {
        self.id = id
        self.appName = appName
        self.repo = repo
        self.summary = summary
        self.symbol = symbol
        self.cliName = cliName
        self.acceptsFolderArgument = acceptsFolderArgument
        self.recentsDefaultsKey = recentsDefaultsKey
    }
}

public enum Catalog {
    /// Appended after the folder when launching an IDE with one. Without it, AppKit treats the folder
    /// as a document to open at launch, and SwiftUI apps built with the macOS 26 SDK then skip their
    /// default window on a first launch (no saved state). `-Key value` in argv sets that default
    /// for this launch only; the IDEs' own argument parsing ignores it (they take the first folder).
    public static let folderLaunchArguments = ["-NSTreatUnknownArgumentsAsOpen", "NO"]

    /// The Toolbox itself, so it can update from its own releases.
    public static let toolbox = Tool(id: "io.github.lai3d.idetoolbox", appName: "IDEToolbox", repo: "lai3d/ide-toolbox",
                                     summary: "IDE Toolbox", symbol: "square.grid.2x2", cliName: "",
                                     acceptsFolderArgument: false)

    public static let tools: [Tool] = [
        Tool(id: "io.github.lai3d.goide", appName: "GoIDE", repo: "lai3d/golang-ide",
             summary: "Go IDE with gopls", symbol: "chevron.left.forwardslash.chevron.right",
             cliName: "goide", acceptsFolderArgument: true, recentsDefaultsKey: "recentProjects"),
        Tool(id: "io.github.lai3d.pyide", appName: "PyIDE", repo: "lai3d/python-ide",
             summary: "Python IDE with pyright", symbol: "curlybraces",
             cliName: "pyide", acceptsFolderArgument: true),
        Tool(id: "io.github.lai3d.javaide", appName: "JavaIDE", repo: "lai3d/java-ide",
             summary: "Java IDE on Eclipse jdtls", symbol: "cup.and.saucer",
             cliName: "javaide", acceptsFolderArgument: true),
        Tool(id: "io.github.lai3d.csharpide", appName: "CSharpIDE", repo: "lai3d/csharp-ide",
             summary: "C# / .NET IDE with csharp-ls", symbol: "number",
             cliName: "csharpide", acceptsFolderArgument: true),
        Tool(id: "io.github.lai3d.espide", appName: "ESPIDE", repo: "lai3d/esp32-ide",
             summary: "MicroPython on ESP32", symbol: "cpu",
             cliName: "espide", acceptsFolderArgument: true),
        Tool(id: "io.github.lai3d.dbide", appName: "DBIDE", repo: "lai3d/database-ide",
             summary: "Database IDE", symbol: "cylinder.split.1x2",
             cliName: "dbide", acceptsFolderArgument: false),
        Tool(id: "io.github.lai3d.grove", appName: "Grove", repo: "lai3d/grove",
             summary: "Git client", symbol: "arrow.triangle.branch",
             cliName: "grove", acceptsFolderArgument: true, recentsDefaultsKey: "recentRepositories"),
    ]
}
