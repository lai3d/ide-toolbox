import Foundation

public struct RecentProject: Hashable, Sendable, Codable {
    public let path: String
    public let openedAt: Date?

    public init(path: String, openedAt: Date? = nil) {
        self.path = path
        self.openedAt = openedAt
    }

    public var url: URL { URL(fileURLWithPath: path) }
    public var name: String { url.lastPathComponent }
}

/// Recent projects shared between the IDEs and the Toolbox.
///
/// Each IDE writes `~/Library/Application Support/IDEToolbox/recents/<bundle-id>.json`:
///
///     { "projects": [ { "path": "/Users/me/code/app", "openedAt": "2026-10-31T13:00:00Z" } ] }
///
/// newest first. `RecentsStore.record(_:bundleID:)` does exactly that and can be copied into an IDE.
/// Apps that predate the format are read from a string-array key in their own defaults domain.
public struct RecentsStore: Sendable {
    public let directory: URL

    public init(directory: URL = RecentsStore.defaultDirectory) { self.directory = directory }

    public static var defaultDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("IDEToolbox/recents")
    }

    struct File: Codable { var projects: [RecentProject] }

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    public func fileURL(for bundleID: String) -> URL {
        directory.appendingPathComponent("\(bundleID).json")
    }

    /// Recents for a tool, newest first, skipping folders that no longer exist.
    public func recents(for tool: Tool, limit: Int = 8) -> [RecentProject] {
        var list: [RecentProject] = []
        if let data = try? Data(contentsOf: fileURL(for: tool.bundleID)),
           let file = try? Self.decoder.decode(File.self, from: data) {
            list = file.projects
        } else if let key = tool.recentsDefaultsKey,
                  let paths = UserDefaults(suiteName: tool.bundleID)?.stringArray(forKey: key) {
            list = paths.map { RecentProject(path: $0) }
        }
        var seen = Set<String>()
        return list
            .filter { seen.insert($0.path).inserted && FileManager.default.fileExists(atPath: $0.path) }
            .prefix(limit)
            .map { $0 }
    }

    /// Moves `path` to the front of the bundle's recents (keeping at most 20).
    public func record(_ path: String, bundleID: String, at date: Date = Date()) throws {
        let url = fileURL(for: bundleID)
        var file = (try? Data(contentsOf: url)).flatMap { try? Self.decoder.decode(File.self, from: $0) }
            ?? File(projects: [])
        file.projects.removeAll { $0.path == path }
        file.projects.insert(RecentProject(path: path, openedAt: date), at: 0)
        file.projects = Array(file.projects.prefix(20))
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Self.encoder.encode(file).write(to: url, options: .atomic)
    }
}
