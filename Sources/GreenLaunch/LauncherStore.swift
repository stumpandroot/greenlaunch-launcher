import AppKit
import SwiftUI

struct InstalledApp: Equatable {
    let url: URL
    let version: String?
}

enum Phase: Equatable {
    case idle
    case downloading(fraction: Double, written: Int64, total: Int64)
    case installing
    case failed(String)

    var isBusy: Bool {
        switch self {
        case .downloading, .installing: return true
        default: return false
        }
    }
}

struct AppState {
    var installed: InstalledApp?
    var release: GHRelease?
    var asset: GHAsset?
    var checkMessage: String?
    var phase: Phase = .idle
}

enum AppStatus {
    case noBuild
    case notInstalled
    case upToDate
    case updateAvailable
    case installedUnknown
}

@MainActor
final class LauncherStore: ObservableObject {
    @Published private(set) var states: [String: AppState] = [:]
    @Published private(set) var isChecking = false
    @Published private(set) var lastChecked: Date?
    @Published private(set) var hasToken: Bool
    @Published var appToQuit: CatalogApp? = nil
    @Published var includeDrafts: Bool {
        didSet { UserDefaults.standard.set(includeDrafts, forKey: "includeDrafts") }
    }

    init() {
        includeDrafts = UserDefaults.standard.object(forKey: "includeDrafts") as? Bool ?? true
        hasToken = TokenStore.read() != nil
        for app in Catalog.apps {
            states[app.id] = AppState()
        }
        refreshInstalled()
    }

    func state(_ app: CatalogApp) -> AppState { states[app.id] ?? AppState() }

    func status(_ app: CatalogApp) -> AppStatus {
        let current = state(app)
        guard let installed = current.installed else {
            return current.asset == nil ? .noBuild : .notInstalled
        }
        guard let release = current.release, current.asset != nil, let latest = AppVersion(release.tag_name) else {
            return .installedUnknown
        }
        guard let have = installed.version.flatMap({ AppVersion($0) }) else { return .updateAvailable }
        return have < latest ? .updateAvailable : .upToDate
    }

    var appsWithUpdates: [CatalogApp] { Catalog.apps.filter { status($0) == .updateAvailable } }
    var updateCount: Int { appsWithUpdates.count }
    var installedCount: Int { Catalog.apps.filter { state($0).installed != nil }.count }

    func refreshInstalled() {
        for app in Catalog.apps where !state(app).phase.isBusy {
            states[app.id, default: AppState()].installed = Locator.find(app)
        }
    }

    // MARK: Token

    func saveToken(_ token: String) {
        TokenStore.save(token)
        hasToken = TokenStore.read() != nil
    }

    func removeToken() {
        TokenStore.delete()
        hasToken = false
    }

    // MARK: Checking

    func checkForUpdates() async {
        guard !isChecking else { return }
        isChecking = true
        refreshInstalled()
        let client = GitHubClient(token: TokenStore.read())
        let showDrafts = includeDrafts && hasToken

        for app in Catalog.apps where app.repo == nil {
            states[app.id]?.release = nil
            states[app.id]?.asset = nil
            states[app.id]?.checkMessage = "No GitHub repo yet."
        }

        await withTaskGroup(of: (String, Result<[GHRelease], Error>).self) { group in
            for app in Catalog.apps {
                guard let repo = app.repo else { continue }
                let id = app.id
                group.addTask {
                    do {
                        return (id, .success(try await client.releases(repo: repo)))
                    } catch {
                        return (id, .failure(error))
                    }
                }
            }
            for await (id, result) in group {
                switch result {
                case .success(let releases):
                    let pick = ReleasePicker.newest(releases, includeDrafts: showDrafts)
                    states[id]?.release = pick?.release
                    states[id]?.asset = pick?.asset
                    if pick != nil {
                        states[id]?.checkMessage = nil
                    } else if !showDrafts && releases.contains(where: { $0.draft }) {
                        states[id]?.checkMessage = "Only draft builds so far. Turn on drafts in Settings."
                    } else {
                        states[id]?.checkMessage = "No Mac build published yet."
                    }
                case .failure(let error):
                    states[id]?.checkMessage = error.localizedDescription
                }
            }
        }

        lastChecked = Date()
        isChecking = false
    }

    // MARK: Actions

    func requestInstall(_ app: CatalogApp) {
        if let url = state(app).installed?.url, Installer.isRunning(url) {
            appToQuit = app
            return
        }
        Task { await install(app) }
    }

    func quitAndInstall(_ app: CatalogApp) {
        Task {
            if let url = state(app).installed?.url {
                await Installer.quit(url)
            }
            await install(app)
        }
    }

    func updateAll() {
        Task {
            for app in appsWithUpdates {
                if let url = state(app).installed?.url, Installer.isRunning(url) {
                    await Installer.quit(url)
                }
                await install(app)
            }
        }
    }

    func install(_ app: CatalogApp) async {
        guard let asset = state(app).asset, !state(app).phase.isBusy else { return }
        let id = app.id
        states[id]?.phase = .downloading(fraction: 0, written: 0, total: Int64(asset.size))
        let client = GitHubClient(token: TokenStore.read())
        do {
            let dmg = try await Downloader().download(client.downloadRequest(for: asset)) { fraction, written, total in
                Task { @MainActor in
                    if case .downloading = self.states[id]?.phase {
                        self.states[id]?.phase = .downloading(fraction: fraction, written: written, total: total)
                    }
                }
            }
            states[id]?.phase = .installing
            let name = app.name
            let existing = state(app).installed?.url
            let destination = try await Task.detached {
                try Installer.install(dmg: dmg, preferredName: name, replacing: existing)
            }.value
            states[id]?.installed = Locator.read(destination)
            states[id]?.phase = .idle
        } catch {
            states[id]?.phase = .failed(error.localizedDescription)
        }
    }

    func open(_ app: CatalogApp) {
        guard let url = state(app).installed?.url else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { _, _ in }
    }

    func reveal(_ app: CatalogApp) {
        guard let url = state(app).installed?.url else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func openRelease(_ app: CatalogApp) {
        guard let link = state(app).release?.html_url, let url = URL(string: link) else { return }
        NSWorkspace.shared.open(url)
    }

    func openRepo(_ app: CatalogApp) {
        guard let repo = app.repo, let url = URL(string: "https://github.com/\(repo)") else { return }
        NSWorkspace.shared.open(url)
    }
}
