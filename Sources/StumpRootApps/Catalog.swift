import SwiftUI

/// The group an app is listed under.
enum Family: String, CaseIterable, Hashable {
    case verbose = "Verbose"
    case studio = "Studio tools"
    case personal = "Personal"
}

/// The palette fill that stands in for an app's icon while the app isn't on this Mac.
enum Hue: Hashable {
    case persimmon, butter, sage, petal, neutral
}

/// How a repo names its releases.
enum TagScheme: Hashable {
    /// Tags like `v1.2.0`, compared with the app's version.
    case version
    /// Tags like `beta-361`, compared with the app's build number.
    case build(prefix: String)
}

/// Where an app's builds come from.
enum Source: Hashable {
    /// GitHub Releases with a DMG. The launcher installs and updates these.
    case github(repo: String, tags: TagScheme)
    /// TestFlight installs and updates the app.
    case testFlight
    /// Built and run from Xcode on this Mac.
    case xcode
    /// Installed by hand from a build file.
    case file
    /// No Mac build yet.
    case none
}

/// One app the launcher knows about.
struct CatalogApp: Identifiable, Hashable {
    /// Short key used internally.
    let id: String
    /// The name shown in the launcher.
    let name: String
    /// The app's file name in Applications, without `.app`.
    let fileName: String
    let tagline: String
    let family: Family
    let source: Source
    /// The app's bundle identifier. When set, a copy with another identifier is never taken for this app.
    let bundleID: String?
    let hue: Hue

    var repo: String? {
        if case .github(let repo, _) = source { return repo }
        return nil
    }

    var tagScheme: TagScheme {
        if case .github(_, let tags) = source { return tags }
        return .version
    }
}

/// The apps the launcher shows, in order. To add an app, add an entry here.
enum Catalog {
    static let apps: [CatalogApp] = [
        // Verbose's bundle file is Verbatim.app (its internal name); Finder shows it as Verbose.
        CatalogApp(
            id: "verbose",
            name: "Verbose",
            fileName: "Verbatim",
            tagline: "Dictate anywhere, record meetings, and transcribe files.",
            family: .verbose,
            source: .github(repo: "stumpandroot/verbose-updates", tags: .build(prefix: "beta-")),
            bundleID: "co.stumpandroot.verbatim",
            hue: .persimmon
        ),
        CatalogApp(
            id: "verbose-tasks",
            name: "Verbose Tasks",
            fileName: "Verbose Tasks",
            tagline: "Notes and to-dos, with a brain dump at the center.",
            family: .verbose,
            source: .testFlight,
            bundleID: "co.stumpandroot.verbosetasks",
            hue: .butter
        ),
        CatalogApp(
            id: "verbose-cut",
            name: "Verbose Cut",
            fileName: "Verbose Cut",
            tagline: "Rough-cut video by editing the transcript.",
            family: .verbose,
            source: .xcode,
            bundleID: "co.stumpandroot.VerboseCut",
            hue: .sage
        ),
        CatalogApp(
            id: "verbose-script",
            name: "Verbose Script",
            fileName: "Verbose Script",
            tagline: "Screenwriting with drafts, a title page, and slash commands.",
            family: .verbose,
            source: .file,
            bundleID: "co.stumpandroot.verbosescript",
            hue: .petal
        ),
        CatalogApp(
            id: "verbose-projects",
            name: "Verbose Projects",
            fileName: "Verbose Projects",
            tagline: "Clients, projects, and contract terms in one place.",
            family: .verbose,
            source: .none,
            bundleID: nil,
            hue: .neutral
        ),
        // The iPhone app, which TestFlight installs on a Mac as Verbose.app.
        CatalogApp(
            id: "verbose-iphone",
            name: "Verbose for iPhone",
            fileName: "Verbose",
            tagline: "The iPhone app, running on this Mac.",
            family: .verbose,
            source: .testFlight,
            bundleID: "co.stumpandroot.verbatim.ios",
            hue: .persimmon
        ),
        CatalogApp(
            id: "keep",
            name: "Keep",
            fileName: "Keep",
            tagline: "Save videos and images from social media.",
            family: .studio,
            source: .github(repo: "stumpandroot/keep-updates", tags: .version),
            bundleID: "co.stumpandroot.keep",
            hue: .petal
        ),
        CatalogApp(
            id: "versa",
            name: "Versa",
            fileName: "Versa",
            tagline: "One master logo in, every version and format out.",
            family: .studio,
            source: .github(repo: "stumpandroot/versa", tags: .version),
            bundleID: "co.stumpandroot.versa",
            hue: .persimmon
        ),
        CatalogApp(
            id: "vectorize",
            name: "Vectorize",
            fileName: "Vectorize",
            tagline: "Convert PNG and JPEG images to clean SVG.",
            family: .studio,
            source: .github(repo: "stumpandroot/Vectorize", tags: .version),
            bundleID: "co.greenlaunch.vectorize",
            hue: .butter
        ),
        CatalogApp(
            id: "aptus",
            name: "Aptus",
            fileName: "Aptus",
            tagline: "Resize and optimize photos. Grab frames from video.",
            family: .studio,
            source: .github(repo: "stumpandroot/aptus-mac", tags: .version),
            bundleID: "co.greenlaunch.aptus",
            hue: .sage
        ),
        CatalogApp(
            id: "steel-shelf",
            name: "Steel Shelf",
            fileName: "Steel Shelf",
            tagline: "Your movie collection: steelbooks, stats, and a watch log.",
            family: .personal,
            source: .xcode,
            bundleID: nil,
            hue: .neutral
        ),
    ]

    static func apps(in family: Family) -> [CatalogApp] { apps.filter { $0.family == family } }
}
