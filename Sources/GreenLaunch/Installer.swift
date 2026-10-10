import AppKit
import Foundation

enum InstallError: LocalizedError {
    case command(String, String)
    case noAppInDMG
    case badDownload(Int)

    var errorDescription: String? {
        switch self {
        case .command(let name, let output):
            let detail = output.trimmingCharacters(in: .whitespacesAndNewlines)
            return "\(name) failed. \(detail)"
        case .noAppInDMG:
            return "The download didn't contain an app."
        case .badDownload(let code):
            return "The download failed (HTTP \(code))."
        }
    }
}

/// Finds an app on this Mac and reads its version.
enum Locator {
    static var applicationFolders: [URL] {
        [
            URL(fileURLWithPath: "/Applications"),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications"),
        ]
    }

    static func isInApplications(_ url: URL) -> Bool {
        let folder = url.standardizedFileURL.deletingLastPathComponent().path
        return applicationFolders.contains { $0.standardizedFileURL.path == folder }
    }

    /// Fast check: the Applications folders, then wherever macOS has the app's ID registered.
    static func find(_ app: CatalogApp) -> InstalledApp? {
        let fileManager = FileManager.default
        var candidates = applicationFolders.map { $0.appendingPathComponent("\(app.name).app") }
        if let bundleID = app.bundleID,
           let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            candidates.append(url)
        }
        let home = fileManager.homeDirectoryForCurrentUser.path
        for url in candidates where fileManager.fileExists(atPath: url.path) && !usablePaths([url.path], home: home).isEmpty {
            return read(url)
        }
        return nil
    }

    /// Slower check: asks Spotlight for the app by ID, then by name, anywhere on the Mac.
    /// Picks the highest version when it finds more than one copy.
    static func findWithSpotlight(_ app: CatalogApp) -> InstalledApp? {
        var paths: [String] = []
        if let bundleID = app.bundleID {
            paths += spotlight("kMDItemCFBundleIdentifier == '\(bundleID)'")
        }
        paths += spotlight("kMDItemFSName == '\(app.name).app'")
        let fileManager = FileManager.default
        let found = usablePaths(paths, home: fileManager.homeDirectoryForCurrentUser.path)
            .filter { fileManager.fileExists(atPath: $0) }
            .map { read(URL(fileURLWithPath: $0)) }
        return found.max { a, b in
            (a.version.flatMap { AppVersion($0) } ?? AppVersion("0")!) < (b.version.flatMap { AppVersion($0) } ?? AppVersion("0")!)
        }
    }

    /// Keeps app bundles that someone could use: skips the Trash, mounted disk images, and apps nested inside other apps.
    static func usablePaths(_ paths: [String], home: String) -> [String] {
        var seen = Set<String>()
        return paths.filter { path in
            guard path.hasSuffix(".app"),
                  !path.hasPrefix("/Volumes/"),
                  !path.hasPrefix(home + "/.Trash/"),
                  !path.contains("/.Trash/"),
                  !path.dropLast(4).contains(".app/"),
                  seen.insert(path).inserted
            else { return false }
            return true
        }
    }

    private static func spotlight(_ query: String) -> [String] {
        guard let output = try? Installer.shell("/usr/bin/mdfind", [query]) else { return [] }
        return output.split(separator: "\n").map(String.init)
    }

    /// Reads Info.plist directly so the version is fresh after an update.
    static func read(_ url: URL) -> InstalledApp {
        let plist = NSDictionary(contentsOf: url.appendingPathComponent("Contents/Info.plist"))
        return InstalledApp(url: url, version: plist?["CFBundleShortVersionString"] as? String)
    }
}

/// Downloads a file with progress. Drops the GitHub token when GitHub redirects to its file storage.
final class Downloader: NSObject, URLSessionDownloadDelegate {
    private var continuation: CheckedContinuation<URL, Error>?
    private var onProgress: ((Double, Int64, Int64) -> Void)?
    private var lastReport = Date.distantPast

    func download(_ request: URLRequest, progress: @escaping (Double, Int64, Int64) -> Void) async throws -> URL {
        onProgress = progress
        let session = URLSession(configuration: .ephemeral, delegate: self, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            session.downloadTask(with: request).resume()
        }
    }

    private func finish(_ result: Result<URL, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(with: result)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        let now = Date()
        guard now.timeIntervalSince(lastReport) > 0.1 else { return }
        lastReport = now
        let fraction = totalBytesExpectedToWrite > 0 ? Double(totalBytesWritten) / Double(totalBytesExpectedToWrite) : 0
        onProgress?(fraction, totalBytesWritten, totalBytesExpectedToWrite)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        let code = (downloadTask.response as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else {
            finish(.failure(InstallError.badDownload(code)))
            return
        }
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("GreenLaunch-\(UUID().uuidString).dmg")
        do {
            try FileManager.default.moveItem(at: location, to: destination)
            finish(.success(destination))
        } catch {
            finish(.failure(error))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error { finish(.failure(error)) }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        var next = request
        if next.url?.host != "api.github.com" {
            next.setValue(nil, forHTTPHeaderField: "Authorization")
        }
        completionHandler(next)
    }
}

enum Installer {
    @discardableResult
    static func shell(_ path: String, _ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let output = String(data: data, encoding: .utf8) ?? ""
        guard process.terminationStatus == 0 else {
            throw InstallError.command(URL(fileURLWithPath: path).lastPathComponent, output)
        }
        return output
    }

    /// Mounts the DMG, copies its app over the installed copy (or into Applications), and cleans up.
    static func install(dmg: URL, preferredName: String, replacing existing: URL?) throws -> URL {
        let fileManager = FileManager.default
        let mountPoint = fileManager.temporaryDirectory.appendingPathComponent("GreenLaunch-mount-\(UUID().uuidString)")
        try fileManager.createDirectory(at: mountPoint, withIntermediateDirectories: true)
        try shell("/usr/bin/hdiutil", ["attach", dmg.path, "-nobrowse", "-readonly", "-noautoopen", "-mountpoint", mountPoint.path])
        defer {
            _ = try? shell("/usr/bin/hdiutil", ["detach", mountPoint.path, "-force"])
            try? fileManager.removeItem(at: mountPoint)
            try? fileManager.removeItem(at: dmg)
        }

        let items = try fileManager.contentsOfDirectory(at: mountPoint, includingPropertiesForKeys: nil)
        let apps = items.filter { $0.pathExtension == "app" }
        guard let source = apps.first(where: { $0.deletingPathExtension().lastPathComponent == preferredName }) ?? apps.first else {
            throw InstallError.noAppInDMG
        }

        // Update in place when the app lives in an Applications folder. Otherwise the update lands in Applications
        // and the old copy (in Downloads, say) goes to the Trash.
        let folder = existing.flatMap { Locator.isInApplications($0) ? $0.deletingLastPathComponent() : nil }
            ?? URL(fileURLWithPath: "/Applications")
        let destination = folder.appendingPathComponent(source.lastPathComponent)
        for old in Set([existing, destination].compactMap { $0?.standardizedFileURL }) where fileManager.fileExists(atPath: old.path) {
            try fileManager.trashItem(at: old, resultingItemURL: nil)
        }
        try fileManager.copyItem(at: source, to: destination)
        _ = try? shell("/usr/bin/xattr", ["-dr", "com.apple.quarantine", destination.path])
        return destination
    }

    static func runningCopies(of url: URL) -> [NSRunningApplication] {
        let target = url.standardizedFileURL.path
        return NSWorkspace.shared.runningApplications.filter { $0.bundleURL?.standardizedFileURL.path == target }
    }

    static func isRunning(_ url: URL) -> Bool { !runningCopies(of: url).isEmpty }

    /// Moves an app into /Applications and returns its new location.
    static func moveToApplications(_ url: URL) throws -> URL {
        let fileManager = FileManager.default
        let destination = URL(fileURLWithPath: "/Applications").appendingPathComponent(url.lastPathComponent)
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.trashItem(at: destination, resultingItemURL: nil)
        }
        try fileManager.moveItem(at: url, to: destination)
        return destination
    }

    /// Asks the app to quit and waits up to 10 seconds.
    static func quit(_ url: URL) async {
        let copies = runningCopies(of: url)
        copies.forEach { _ = $0.terminate() }
        for _ in 0..<50 {
            if copies.allSatisfy({ $0.isTerminated }) { return }
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
    }
}
