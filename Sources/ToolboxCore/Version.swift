import Foundation

/// A dotted numeric version such as `0.1.0` or `v1.2`. Missing components count as zero,
/// and a pre-release suffix (`-beta.1`) sorts before the plain release.
public struct Version: Comparable, CustomStringConvertible, Sendable {
    public let components: [Int]
    public let prerelease: String?

    public init?(_ string: String) {
        var s = string.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("v") || s.hasPrefix("V") { s.removeFirst() }
        let parts = s.split(separator: "-", maxSplits: 1)
        guard let core = parts.first, !core.isEmpty else { return nil }
        let nums = core.split(separator: ".", omittingEmptySubsequences: false).map { Int($0) }
        guard !nums.contains(where: { $0 == nil }) else { return nil }
        components = nums.compactMap { $0 }
        prerelease = parts.count > 1 ? String(parts[1]) : nil
    }

    public var description: String {
        components.map(String.init).joined(separator: ".") + (prerelease.map { "-\($0)" } ?? "")
    }

    public static func == (a: Version, b: Version) -> Bool { !(a < b) && !(b < a) }

    public static func < (a: Version, b: Version) -> Bool {
        let n = max(a.components.count, b.components.count)
        for i in 0..<n {
            let x = i < a.components.count ? a.components[i] : 0
            let y = i < b.components.count ? b.components[i] : 0
            if x != y { return x < y }
        }
        switch (a.prerelease, b.prerelease) {
        case (nil, nil), (nil, _?): return false
        case (_?, nil): return true
        case let (x?, y?): return x.compare(y, options: .numeric) == .orderedAscending
        }
    }
}
