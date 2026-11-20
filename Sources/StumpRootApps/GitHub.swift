import Foundation

struct GHAsset: Decodable, Hashable {
    let id: Int
    let name: String
    let size: Int
    /// API address for the file. Works for drafts and private repos when a token is sent.
    let url: String
    let browser_download_url: String
}

struct GHRelease: Decodable, Hashable {
    let tag_name: String
    let name: String?
    let draft: Bool
    let prerelease: Bool
    let created_at: String
    let html_url: String
    let assets: [GHAsset]
}

enum GitHubError: LocalizedError {
    case http(Int)

    var errorDescription: String? {
        switch self {
        case .http(401):
            return "GitHub rejected your token. Replace it in Settings."
        case .http(403), .http(429):
            return "GitHub's hourly limit for checks without a token was reached. Add a token in Settings."
        case .http(404):
            return "Couldn't see this repo. If it's private, add a GitHub token in Settings."
        case .http(let code):
            return "GitHub returned an error (\(code))."
        }
    }
}

struct GitHubClient {
    var token: String?

    private func authorize(_ request: inout URLRequest) {
        if let token, !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
    }

    /// The repo's newest releases, drafts included when the token allows it.
    func releases(repo: String) async throws -> [GHRelease] {
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/\(repo)/releases?per_page=20")!)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        authorize(&request)
        let (data, response) = try await URLSession.shared.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else { throw GitHubError.http(code) }
        return try JSONDecoder().decode([GHRelease].self, from: data)
    }

    /// A request that downloads the asset's file.
    func downloadRequest(for asset: GHAsset) -> URLRequest {
        var request = URLRequest(url: URL(string: asset.url)!)
        request.setValue("application/octet-stream", forHTTPHeaderField: "Accept")
        authorize(&request)
        return request
    }
}

enum ReleasePicker {
    /// The DMG for this Mac's chip. Falls back to the only DMG, or the first one.
    static func pickDMG(_ assets: [GHAsset], isARM: Bool = Machine.isARM) -> GHAsset? {
        let dmgs = assets.filter { $0.name.lowercased().hasSuffix(".dmg") }
        guard dmgs.count > 1 else { return dmgs.first }
        func normalized(_ text: String) -> String {
            text.lowercased().filter { $0.isLetter || $0.isNumber }
        }
        let keys = isARM ? ["arm64", "applesilicon", "aarch64", "universal"] : ["x8664", "intel", "universal"]
        return dmgs.first { asset in keys.contains { normalized(asset.name).contains($0) } } ?? dmgs.first
    }

    /// The highest-versioned release that has a DMG for this Mac. A release whose tag doesn't fit the repo's scheme
    /// (a moving tag like `beta-latest`, say) is skipped.
    static func newest(_ releases: [GHRelease], includeDrafts: Bool, scheme: TagScheme = .version, isARM: Bool = Machine.isARM) -> (release: GHRelease, asset: GHAsset)? {
        let usable: [(release: GHRelease, asset: GHAsset, version: AppVersion)] = releases
            .filter { includeDrafts || !$0.draft }
            .compactMap { release in
                guard let version = TagReader.version(of: release.tag_name, scheme: scheme),
                      let asset = pickDMG(release.assets, isARM: isARM)
                else { return nil }
                return (release, asset, version)
            }
        let best = usable.max { a, b in
            if a.version != b.version { return a.version < b.version }
            return a.release.created_at < b.release.created_at
        }
        return best.map { ($0.release, $0.asset) }
    }
}

/// Reads a release tag under a repo's scheme.
enum TagReader {
    static func version(of tag: String, scheme: TagScheme) -> AppVersion? {
        switch scheme {
        case .version:
            return AppVersion(tag)
        case .build(let prefix):
            guard tag.hasPrefix(prefix), let number = Int(tag.dropFirst(prefix.count)), number >= 0 else { return nil }
            return AppVersion(String(number))
        }
    }

    /// A tag as the launcher shows it: `v1.2.3` or `build 361`.
    static func label(_ tag: String, scheme: TagScheme) -> String {
        switch scheme {
        case .version:
            return displayVersion(tag)
        case .build(let prefix):
            return "build " + (tag.hasPrefix(prefix) ? String(tag.dropFirst(prefix.count)) : tag)
        }
    }
}
