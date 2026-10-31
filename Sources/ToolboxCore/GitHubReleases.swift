import Foundation

public struct Release: Sendable, Equatable {
    public let tag: String
    public let version: Version?
    public let pageURL: URL
    public let zipURL: URL
    public let zipSize: Int
}

public enum ReleaseError: LocalizedError {
    case http(Int)
    case noZipAsset(String)

    public var errorDescription: String? {
        switch self {
        case .http(403): return "GitHub rate limit hit — try again later"
        case .http(let code): return "GitHub returned HTTP \(code)"
        case .noZipAsset(let tag): return "Release \(tag) has no .zip asset"
        }
    }
}

public struct GitHubReleases: Sendable {
    let session: URLSession

    public init(session: URLSession = .shared) { self.session = session }

    /// Latest published release, or `nil` when the repo has none yet.
    public func latest(for tool: Tool) async throws -> Release? {
        var req = URLRequest(url: URL(string: "https://api.github.com/repos/\(tool.repo)/releases/latest")!)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("IDEToolbox", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 404 { return nil }
        guard status == 200 else { throw ReleaseError.http(status) }
        return try Self.parse(data, appName: tool.appName)
    }

    struct Payload: Decodable {
        struct Asset: Decodable {
            let name: String
            let browser_download_url: URL
            let size: Int
        }
        let tag_name: String
        let html_url: URL
        let assets: [Asset]
    }

    /// Picks the zip asset, preferring one named after the app.
    static func parse(_ data: Data, appName: String) throws -> Release {
        let p = try JSONDecoder().decode(Payload.self, from: data)
        let zips = p.assets.filter { $0.name.lowercased().hasSuffix(".zip") }
        guard let asset = zips.first(where: { $0.name.hasPrefix(appName) }) ?? zips.first else {
            throw ReleaseError.noZipAsset(p.tag_name)
        }
        return Release(tag: p.tag_name, version: Version(p.tag_name), pageURL: p.html_url,
                       zipURL: asset.browser_download_url, zipSize: asset.size)
    }
}
