import AppKit
import SwiftUI

@main
enum Entry {
    static func main() {
        if CommandLine.arguments.contains("--self-test") {
            exit(SelfTest.run() ? 0 : 1)
        }
        GreenLaunchApp.main()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

struct GreenLaunchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = LauncherStore()

    var body: some Scene {
        Window("GreenLaunch", id: "main") {
            ContentView()
                .environmentObject(store)
                .frame(minWidth: 760, minHeight: 480)
        }
        .defaultSize(width: 940, height: 620)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates") {
                    Task { await store.checkForUpdates() }
                }
                .keyboardShortcut("r", modifiers: .command)
            }
        }

        Settings {
            SettingsView()
                .environmentObject(store)
        }
    }
}

/// Offline checks the GitHub build runs with `--self-test`.
enum SelfTest {
    static func run() -> Bool {
        var passed = true
        func check(_ condition: Bool, _ name: String) {
            print((condition ? "PASS  " : "FAIL  ") + name)
            if !condition { passed = false }
        }

        check(AppVersion("v1.2.10")! > AppVersion("1.2.9")!, "Compares versions number by number")
        check(AppVersion("1.0")! == AppVersion("v1.0.0")!, "Treats 1.0 and v1.0.0 as equal")
        check(AppVersion("v2.0.0-beta")! > AppVersion("1.9")!, "Ignores suffixes like -beta")
        check(AppVersion("latest") == nil, "Rejects tags that aren't versions")

        func asset(_ id: Int, _ name: String) -> GHAsset {
            GHAsset(id: id, name: name, size: 1, url: "https://api.github.com/x/\(id)", browser_download_url: "https://github.com/x/\(id)")
        }
        let aptus = [asset(1, "Aptus-1.0.0-apple-silicon.dmg"), asset(2, "Aptus-1.0.0-intel.dmg"), asset(3, "notes.txt")]
        check(ReleasePicker.pickDMG(aptus, isARM: true)?.id == 1, "Picks the Apple silicon DMG (Aptus naming)")
        check(ReleasePicker.pickDMG(aptus, isARM: false)?.id == 2, "Picks the Intel DMG (Aptus naming)")
        let vectorize = [asset(4, "Vectorize-1.0.0-Intel.dmg"), asset(5, "Vectorize-1.0.0-Apple-Silicon.dmg")]
        check(ReleasePicker.pickDMG(vectorize, isARM: true)?.id == 5, "Picks the Apple silicon DMG (Vectorize naming)")
        let verbatim = [asset(6, "Verbatim-arm64.dmg"), asset(7, "Verbatim-x86_64.dmg")]
        check(ReleasePicker.pickDMG(verbatim, isARM: false)?.id == 7, "Picks the Intel DMG (Verbatim naming)")
        check(ReleasePicker.pickDMG([asset(8, "notes.txt")]) == nil, "Skips releases without a DMG")

        func release(_ tag: String, draft: Bool) -> GHRelease {
            GHRelease(tag_name: tag, name: tag, draft: draft, prerelease: false, created_at: "2026-10-10T00:00:00Z", html_url: "https://github.com", assets: [asset(9, "App-arm64.dmg")])
        }
        let releases = [release("v1.0.0", draft: false), release("v1.1.0", draft: true)]
        check(ReleasePicker.newest(releases, includeDrafts: false)?.release.tag_name == "v1.0.0", "Skips drafts when drafts are off")
        check(ReleasePicker.newest(releases, includeDrafts: true)?.release.tag_name == "v1.1.0", "Picks the newest draft when drafts are on")

        check(Set(Catalog.apps.map(\.id)).count == Catalog.apps.count, "Every catalog app has its own ID")

        let home = "/Users/tim"
        let spotted = Locator.usablePaths([
            "/Users/tim/Downloads/Verbatim.app",
            "/Users/tim/Downloads/Verbatim.app",
            "/Volumes/Verbatim/Verbatim.app",
            "/Users/tim/.Trash/Verbatim.app",
            "/Applications/Big.app/Contents/Helpers/Verbatim.app",
            "/Users/tim/Downloads/Verbatim.dmg",
        ], home: home)
        check(spotted == ["/Users/tim/Downloads/Verbatim.app"], "Spotlight results skip the Trash, disk images, nested apps, and duplicates")
        check(Locator.isInApplications(URL(fileURLWithPath: "/Applications/Verbatim.app")), "Knows /Applications is an Applications folder")
        check(!Locator.isInApplications(URL(fileURLWithPath: "/Users/tim/Downloads/Verbatim.app")), "Knows Downloads isn't an Applications folder")
        check(Catalog.apps.first { $0.id == "verbatim" }?.bundleID == "co.stumpandroot.verbatim", "Uses Verbatim's existing app ID")
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "none"
        print("GreenLaunch version: \(version)")
        print(passed ? "All checks passed." : "Some checks failed.")
        return passed
    }
}
