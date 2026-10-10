import SwiftUI

/// One app GreenLaunch knows about.
struct CatalogApp: Identifiable, Hashable {
    /// Short key used internally.
    let id: String
    /// The app's name, which is also its file name in Applications (`Name.app`).
    let name: String
    let tagline: String
    /// The GitHub repo whose releases hold the app's DMGs, like `stumpandroot/verbatim`.
    /// `nil` means the app has no builds yet.
    let repo: String?
    /// The app's bundle identifier, used to find it if it isn't in Applications.
    let bundleID: String?
    /// Color for the placeholder tile when the app isn't installed.
    let tint: Color
}

/// The apps GreenLaunch shows, in order. To add an app, add a line here.
enum Catalog {
    static let apps: [CatalogApp] = [
        CatalogApp(
            id: "verbatim",
            name: "Verbatim",
            tagline: "Paste a video link, get a searchable transcript.",
            repo: "stumpandroot/verbatim",
            bundleID: nil,
            tint: Color(hex: 0x7B5CFF)
        ),
        CatalogApp(
            id: "keep",
            name: "Keep",
            tagline: "Save videos and images from social media.",
            repo: nil,
            bundleID: nil,
            tint: Brand.lime
        ),
        CatalogApp(
            id: "aptus",
            name: "Aptus",
            tagline: "Resize photos for any destination. Grab frames from video.",
            repo: "stumpandroot/aptus-mac",
            bundleID: "co.greenlaunch.aptus",
            tint: Color(hex: 0x3FB8A9)
        ),
        CatalogApp(
            id: "vectorize",
            name: "Vectorize",
            tagline: "Convert PNG and JPEG images to clean SVG.",
            repo: "stumpandroot/Vectorize",
            bundleID: "co.greenlaunch.vectorize",
            tint: Color(hex: 0xF5C518)
        ),
        CatalogApp(
            id: "versa",
            name: "Versa",
            tagline: "One master logo in, every version and format out.",
            repo: "stumpandroot/versa",
            bundleID: nil,
            tint: Color(hex: 0x6495ED)
        ),
    ]
}
