import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct InstalledApp: Equatable {
    let url: URL
    let version: String?
    /// The build number (CFBundleVersion).
    let build: String?

    var isInApplications: Bool { Locator.isInApplications(url) }

    /// Where the app is, for apps outside Applications, like "in Downloads".
    var locationNote: String? {
        guard !isInApplications else { return nil }
        let folder = url.deletingLastPathComponent()
        if folder.path == FileManager.default.homeDirectoryForCurrentUser.path { return "in your home folder" }
        return "in \(FileManager.default.displayName(atPath: folder.path))"
    }
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
    /// Not on this Mac, and the launcher has no way to get it (no build, or one it can't see).
    case unavailable
    /// Not on this Mac, and the launcher can install it or send you to TestFlight for it.
    case notInstalled
    case upToDate
    case updateAvailable
    /// On this Mac, with nothing to compare its version with.
    case installed
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
            switch app.source {
            case .github: return current.asset == nil ? .unavailable : .notInstalled
            case .testFlight: return .notInstalled
            case .xcode, .file, .none: return .unavailable
            }
        }
        guard case .github(_, let scheme) = app.source,
              let release = current.release, current.asset != nil,
              let latest = TagReader.version(of: release.tag_name, scheme: scheme)
        else { return .installed }
        guard let have = installedVersion(installed, scheme: scheme).flatMap({ AppVersion($0) }) else { return .updateAvailable }
        return have < latest ? .updateAvailable : .upToDate
    }

    /// The installed number a repo's tags compare with: the version, or the build number.
    private func installedVersion(_ installed: InstalledApp, scheme: TagScheme) -> String? {
        switch scheme {
        case .version: return installed.version
        case .build: return installed.build
        }
    }

    /// The installed copy's version as the launcher shows it: `v1.2.0`, or `build 361` for an app tagged by build.
    func installedLabel(_ app: CatalogApp) -> String {
        guard let installed = state(app).installed else { return "" }
        if case .build = app.tagScheme, let build = installed.build { return "build \(build)" }
        return installed.version.map(displayVersion) ?? "Unknown version"
    }

    /// The newest release's version as the launcher shows it.
    func latestLabel(_ app: CatalogApp) -> String {
        state(app).release.map { TagReader.label($0.tag_name, scheme: app.tagScheme) } ?? ""
    }

    var appsWithUpdates: [CatalogApp] { Catalog.apps.filter { status($0) == .updateAvailable } }
    var updateCount: Int { appsWithUpdates.count }
    var installedApps: [CatalogApp] { Catalog.apps.filter { state($0).installed != nil } }
    var installedCount: Int { installedApps.count }

    private var isSearching = false

    /// Finds each app. The fast check runs right away; apps it can't find get a Spotlight search in the background.
    func refreshInstalled() {
        var missing: [CatalogApp] = []
        for app in Catalog.apps where !state(app).phase.isBusy {
            let found = Locator.find(app)
            if found == nil, let previous = state(app).installed,
               FileManager.default.fileExists(atPath: previous.url.path) {
                // Keep a copy Spotlight found earlier, re-reading its version.
                states[app.id]?.installed = Locator.read(previous.url)
                continue
            }
            states[app.id, default: AppState()].installed = found
            if found == nil { missing.append(app) }
        }
        guard !missing.isEmpty, !isSearching else { return }
        isSearching = true
        Task {
            let results = await Task.detached {
                missing.map { ($0.id, Locator.findWithSpotlight($0)) }
            }.value
            for (id, found) in results {
                guard let found, states[id]?.installed == nil, states[id]?.phase.isBusy == false else { continue }
                states[id]?.installed = found
            }
            isSearching = false
        }
    }

    /// Asks for an app's location and remembers it, for a copy the launcher can't find by itself.
    func chooseApp(_ app: CatalogApp) {
        let panel = NSOpenPanel()
        panel.title = "Choose \(app.name)"
        panel.prompt = "Choose"
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard Locator.matches(app, at: url) else {
            states[app.id]?.phase = .failed("That isn't \(app.name). Its app ID doesn't match.")
            return
        }
        Links.set(url, for: app)
        states[app.id]?.installed = Locator.read(url)
        states[app.id]?.phase = .idle
    }

    func hasChosenApp(_ app: CatalogApp) -> Bool { Links.url(for: app) != nil }

    func forgetChosenApp(_ app: CatalogApp) {
        Links.set(nil, for: app)
        states[app.id]?.installed = nil
        refreshInstalled()
    }

    func moveToApplications(_ app: CatalogApp) {
        guard let url = state(app).installed?.url else { return }
        if Installer.isRunning(url) {
            states[app.id]?.phase = .failed("Quit \(app.name), then move it to Applications.")
            return
        }
        do {
            let destination = try Installer.moveToApplications(url)
            if hasChosenApp(app) { Links.set(destination, for: app) }
            states[app.id]?.installed = Locator.read(destination)
            states[app.id]?.phase = .idle
        } catch {
            states[app.id]?.phase = .failed("Couldn't move \(app.name). \(error.localizedDescription)")
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
            states[app.id]?.checkMessage = nil
        }

        let schemes = Dictionary(uniqueKeysWithValues: Catalog.apps.map { ($0.id, $0.tagScheme) })
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
                    let pick = ReleasePicker.newest(releases, includeDrafts: showDrafts, scheme: schemes[id] ?? .version)
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
            let name = app.fileName
            let existing = state(app).installed?.url
            let destination = try await Task.detached {
                try Installer.install(dmg: dmg, preferredName: name, replacing: existing)
            }.value
            if hasChosenApp(app) { Links.set(destination, for: app) }
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

    /// Opens TestFlight, where an app that ships through it is installed and updated.
    func openTestFlight() {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.TestFlight") {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { _, _ in }
        } else if let url = URL(string: "https://apps.apple.com/app/testflight/id899247664") {
            NSWorkspace.shared.open(url)
        }
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
