import XCTest
@testable import ToolboxCore

final class VersionTests: XCTestCase {
    func testParsing() {
        XCTAssertEqual(Version("v1.2.3")?.components, [1, 2, 3])
        XCTAssertEqual(Version("0.1")?.description, "0.1")
        XCTAssertEqual(Version("1.0.0-beta.2")?.prerelease, "beta.2")
        XCTAssertNil(Version("latest"))
        XCTAssertNil(Version(""))
    }

    func testOrdering() {
        XCTAssertLessThan(Version("0.1.0")!, Version("0.2.0")!)
        XCTAssertLessThan(Version("0.9.0")!, Version("0.10.0")!)
        XCTAssertEqual(Version("1.0")!, Version("v1.0.0")!)
        XCTAssertLessThan(Version("1.0.0-beta.2")!, Version("1.0.0")!)
        XCTAssertLessThan(Version("1.0.0-beta.2")!, Version("1.0.0-beta.10")!)
        XCTAssertFalse(Version("1.0.0")! < Version("1.0.0-rc.1")!)
    }
}

final class ReleaseParsingTests: XCTestCase {
    func json(_ assets: [String]) -> Data {
        let list = assets.map {
            #"{"name":"\#($0)","browser_download_url":"https://example.com/\#($0)","size":42}"#
        }.joined(separator: ",")
        return Data(#"{"tag_name":"v0.2.0","html_url":"https://github.com/x/y/releases/v0.2.0","assets":[\#(list)]}"#.utf8)
    }

    func testPrefersAppNamedZip() throws {
        let r = try GitHubReleases.parse(json(["checksums.txt", "Other.zip", "PyIDE-v0.2.0.zip"]), appName: "PyIDE")
        XCTAssertEqual(r.zipURL.lastPathComponent, "PyIDE-v0.2.0.zip")
        XCTAssertEqual(r.version, Version("0.2.0"))
        XCTAssertEqual(r.zipSize, 42)
    }

    func testFallsBackToAnyZip() throws {
        let r = try GitHubReleases.parse(json(["app.zip"]), appName: "GoIDE")
        XCTAssertEqual(r.zipURL.lastPathComponent, "app.zip")
    }

    func testNoZip() {
        XCTAssertThrowsError(try GitHubReleases.parse(json(["notes.txt"]), appName: "GoIDE"))
    }
}

final class FileSystemTests: XCTestCase {
    var tmp: URL!
    let tool = Tool(id: "com.example.fake", appName: "FakeIDE", repo: "x/y", summary: "", symbol: "",
                    cliName: "fakeide", acceptsFolderArgument: true)

    override func setUpWithError() throws {
        tmp = FileManager.default.temporaryDirectory.appendingPathComponent("toolbox-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: tmp) }

    func makeApp(at dir: URL, bundleID: String, version: String) throws -> URL {
        let app = dir.appendingPathComponent("FakeIDE.app")
        try FileManager.default.createDirectory(at: app.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        let plist: [String: Any] = ["CFBundleIdentifier": bundleID, "CFBundleShortVersionString": version]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            .write(to: app.appendingPathComponent("Contents/Info.plist"))
        return app
    }

    func testInstallArchiveReplacesAndDetectsVersion() throws {
        let src = tmp.appendingPathComponent("src")
        let apps = tmp.appendingPathComponent("Applications")
        try FileManager.default.createDirectory(at: src, withIntermediateDirectories: true)
        let installer = Installer(installDirectory: apps, searchDirectories: [])
        XCTAssertNil(installer.installed(tool))

        for version in ["0.1.0", "0.2.0"] {
            let app = try makeApp(at: src, bundleID: tool.bundleID, version: version)
            let zip = tmp.appendingPathComponent("\(version).zip")
            try Installer.run("/usr/bin/ditto", ["-c", "-k", "--keepParent", app.path, zip.path])
            try FileManager.default.removeItem(at: app)
            try installer.installArchive(zip, for: tool)
        }
        XCTAssertEqual(installer.installed(tool)?.versionString, "0.2.0")
    }

    func testInstallArchiveRejectsWrongBundle() throws {
        let app = try makeApp(at: tmp, bundleID: "com.example.other", version: "1.0")
        let zip = tmp.appendingPathComponent("bad.zip")
        try Installer.run("/usr/bin/ditto", ["-c", "-k", "--keepParent", app.path, zip.path])
        let installer = Installer(installDirectory: tmp.appendingPathComponent("Applications"), searchDirectories: [])
        XCTAssertThrowsError(try installer.installArchive(zip, for: tool))
    }

    func testRecentsRoundTrip() throws {
        let store = RecentsStore(directory: tmp.appendingPathComponent("recents"))
        let a = tmp.appendingPathComponent("a"), b = tmp.appendingPathComponent("b")
        try FileManager.default.createDirectory(at: a, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: b, withIntermediateDirectories: true)
        try store.record(a.path, bundleID: tool.bundleID)
        try store.record(b.path, bundleID: tool.bundleID)
        try store.record(a.path, bundleID: tool.bundleID)
        try store.record(tmp.appendingPathComponent("gone").path, bundleID: tool.bundleID)
        XCTAssertEqual(store.recents(for: tool).map(\.path), [a.path, b.path])
    }

    func testLaunchersDoNotClobberForeignFiles() throws {
        let launchers = Launchers(directory: tmp)
        let app = URL(fileURLWithPath: "/Applications/FakeIDE.app")
        try launchers.install(tool, app: app)
        XCTAssertTrue(launchers.isInstalled(tool))
        let script = try String(contentsOf: launchers.url(for: tool), encoding: .utf8)
        XCTAssertTrue(script.contains(#"open -n -a "$APP" --args "$target" -NSTreatUnknownArgumentsAsOpen NO"#))

        launchers.remove(tool)
        try "#!/bin/sh\necho mine\n".write(to: launchers.url(for: tool), atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try launchers.install(tool, app: app))
        launchers.remove(tool)
        XCTAssertTrue(FileManager.default.fileExists(atPath: launchers.url(for: tool).path))
    }

    func testLauncherScriptRuns() throws {
        // Syntax-check the generated shell for both launcher shapes.
        for accepts in [true, false] {
            let t = Tool(id: "x", appName: "X", repo: "", summary: "", symbol: "", cliName: "x\(accepts)",
                         acceptsFolderArgument: accepts)
            let url = tmp.appendingPathComponent(t.cliName)
            try Launchers.script(for: t, app: URL(fileURLWithPath: "/Applications/X.app"))
                .write(to: url, atomically: true, encoding: .utf8)
            XCTAssertNoThrow(try Installer.run("/bin/sh", ["-n", url.path]))
        }
    }
}

/// Hits GitHub for real: `TOOLBOX_NETWORK_TESTS=1 swift test --filter NetworkTests`.
final class NetworkTests: XCTestCase {
    func testInstallEveryCatalogAppIntoTempDir() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["TOOLBOX_NETWORK_TESTS"] == "1")
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("toolbox-net-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let installer = Installer(installDirectory: dir, searchDirectories: [])
        for tool in Catalog.tools + [Catalog.toolbox] {
            let release = try await XCTUnwrapAsync(try await GitHubReleases().latest(for: tool))
            let box = ProgressBox()
            let app = try await installer.install(tool, release: release) { box.last = $0 }
            XCTAssertEqual(box.last, 1, tool.appName)
            XCTAssertEqual(installer.installed(tool)?.version, release.version, tool.appName)
            XCTAssertNoThrow(try Installer.run("/usr/bin/codesign", ["-v", app.path]), tool.appName)
        }
    }

    func XCTUnwrapAsync<T>(_ value: T?) async throws -> T { try XCTUnwrap(value) }
}

final class ProgressBox: @unchecked Sendable { var last: Double = 0 }
