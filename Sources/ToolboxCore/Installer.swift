import Foundation

public struct InstalledApp: Sendable, Equatable {
    public let url: URL
    public let version: Version?
    public let versionString: String
}

public enum InstallError: LocalizedError {
    case noAppInArchive
    case wrongBundle(expected: String, found: String?)
    case command(String, Int32)

    public var errorDescription: String? {
        switch self {
        case .noAppInArchive: return "The download didn't contain an .app"
        case .wrongBundle(let e, let f): return "Expected bundle \(e), got \(f ?? "none")"
        case .command(let c, let s): return "\(c) failed (exit \(s))"
        }
    }
}

public struct Installer: Sendable {
    /// Where the Toolbox installs apps. `~/Applications` needs no admin rights.
    public let installDirectory: URL
    /// Also searched for already-installed copies (not written to).
    public let searchDirectories: [URL]

    public init(installDirectory: URL = Installer.defaultInstallDirectory,
                searchDirectories: [URL] = [URL(fileURLWithPath: "/Applications")]) {
        self.installDirectory = installDirectory
        self.searchDirectories = searchDirectories
    }

    public static var defaultInstallDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications")
    }

    /// Finds the installed copy whose bundle id matches, preferring the install directory.
    public func installed(_ tool: Tool) -> InstalledApp? {
        for dir in [installDirectory] + searchDirectories {
            let url = dir.appendingPathComponent("\(tool.appName).app")
            guard let info = Self.info(at: url), info["CFBundleIdentifier"] as? String == tool.bundleID else { continue }
            let v = info["CFBundleShortVersionString"] as? String ?? "?"
            return InstalledApp(url: url, version: Version(v), versionString: v)
        }
        return nil
    }

    static func info(at app: URL) -> [String: Any]? {
        let plist = app.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: plist) else { return nil }
        return try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
    }

    /// Downloads the release zip and installs it, replacing (and trashing) any previous copy.
    /// `progress` receives 0...1 while downloading.
    @discardableResult
    public func install(_ tool: Tool, release: Release,
                        progress: @escaping @Sendable (Double) -> Void = { _ in }) async throws -> URL {
        let zip = try await Downloader.download(release.zipURL, expectedSize: release.zipSize, progress: progress)
        defer { try? FileManager.default.removeItem(at: zip) }
        return try installArchive(zip, for: tool)
    }

    /// Unpacks a zipped `.app` and moves it into the install directory.
    public func installArchive(_ zip: URL, for tool: Tool) throws -> URL {
        let fm = FileManager.default
        let staging = fm.temporaryDirectory.appendingPathComponent("IDEToolbox-\(UUID().uuidString)")
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: staging) }

        try Self.run("/usr/bin/ditto", ["-x", "-k", zip.path, staging.path])
        guard let app = try fm.contentsOfDirectory(at: staging, includingPropertiesForKeys: nil)
            .first(where: { $0.pathExtension == "app" }) else { throw InstallError.noAppInArchive }
        let found = Self.info(at: app)?["CFBundleIdentifier"] as? String
        guard found == tool.bundleID else { throw InstallError.wrongBundle(expected: tool.bundleID, found: found) }

        // The apps are ad-hoc signed, not notarized; we downloaded them ourselves on purpose.
        try? Self.run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", app.path])

        try fm.createDirectory(at: installDirectory, withIntermediateDirectories: true)
        let dest = installDirectory.appendingPathComponent("\(tool.appName).app")
        if fm.fileExists(atPath: dest.path) { try fm.trashItem(at: dest, resultingItemURL: nil) }
        try fm.moveItem(at: app, to: dest)
        return dest
    }

    /// Moves the app the Toolbox installed to the Trash.
    public func uninstall(_ tool: Tool) throws {
        let dest = installDirectory.appendingPathComponent("\(tool.appName).app")
        try FileManager.default.trashItem(at: dest, resultingItemURL: nil)
    }

    static func run(_ path: String, _ args: [String]) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try p.run()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else {
            throw InstallError.command(URL(fileURLWithPath: path).lastPathComponent, p.terminationStatus)
        }
    }
}

/// URLSession download with byte-level progress.
enum Downloader {
    static func download(_ url: URL, expectedSize: Int,
                         progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        let (bytes, response) = try await URLSession.shared.bytes(from: url)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw ReleaseError.http(status) }
        let total = max(Int(response.expectedContentLength), expectedSize, 1)

        let dest = FileManager.default.temporaryDirectory.appendingPathComponent("IDEToolbox-\(UUID().uuidString).zip")
        FileManager.default.createFile(atPath: dest.path, contents: nil)
        let handle = try FileHandle(forWritingTo: dest)
        defer { try? handle.close() }

        var buffer = Data()
        buffer.reserveCapacity(1 << 16)
        var written = 0
        for try await byte in bytes {
            buffer.append(byte)
            if buffer.count >= 1 << 16 {
                try handle.write(contentsOf: buffer)
                written += buffer.count
                buffer.removeAll(keepingCapacity: true)
                progress(min(Double(written) / Double(total), 1))
            }
        }
        try handle.write(contentsOf: buffer)
        progress(1)
        return dest
    }
}
