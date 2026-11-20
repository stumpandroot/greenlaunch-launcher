import AppKit
import SwiftUI

enum SidebarItem: Hashable {
    case all
    case installed
    case updates
}

struct ContentView: View {
    @EnvironmentObject private var store: LauncherStore
    @State private var selection: SidebarItem? = .all
    @State private var search = ""

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Label("All apps", systemImage: "square.grid.2x2")
                    .tag(SidebarItem.all)
                Label("On this Mac", systemImage: "checkmark.circle")
                    .tag(SidebarItem.installed)
                Label("Updates", systemImage: "arrow.triangle.2.circlepath")
                    .badge(store.updateCount)
                    .tag(SidebarItem.updates)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
        } detail: {
            Group {
                switch selection ?? .all {
                case .all:
                    AppsPage(title: "Your apps", apps: Catalog.apps, search: search, emptyMessage: "No app matches that name.")
                case .installed:
                    AppsPage(title: "On this Mac", apps: store.installedApps, search: search, emptyMessage: "None of your apps are on this Mac yet.")
                case .updates:
                    UpdatesPage()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Refined.paper)
        }
        .tint(Refined.accentText)
        .searchable(text: $search, placement: .toolbar, prompt: "Find an app")
        .onSubmit(of: .search) { openFirstMatch() }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await store.checkForUpdates() }
                } label: {
                    if store.isChecking {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("Check for updates", systemImage: "arrow.clockwise")
                    }
                }
                .help("Check for updates (⌘R)")
                .disabled(store.isChecking)
            }
        }
        .task { await store.checkForUpdates() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            store.refreshInstalled()
        }
        .alert(item: $store.appToQuit) { app in
            Alert(
                title: Text("Quit \(app.name) and update it?"),
                message: Text("\(app.name) is open. The launcher quits it and installs the new version. You can open it again afterward."),
                primaryButton: .default(Text("Quit and update")) { store.quitAndInstall(app) },
                secondaryButton: .cancel()
            )
        }
    }

    /// Return in the search field opens the first match that's on this Mac.
    private func openFirstMatch() {
        let query = search.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty,
              let app = Catalog.apps.first(where: { $0.name.localizedCaseInsensitiveContains(query) && store.state($0).installed != nil })
        else { return }
        store.open(app)
    }
}

/// A page of app cards grouped by family.
struct AppsPage: View {
    @EnvironmentObject private var store: LauncherStore
    let title: String
    let apps: [CatalogApp]
    let search: String
    let emptyMessage: String

    private var eyebrow: String {
        var text = "\(store.installedCount) of \(Catalog.apps.count) on this Mac"
        if let checked = store.lastChecked {
            text += " · Checked \(checked.formatted(date: .omitted, time: .shortened))"
        }
        return text
    }

    private var shown: [CatalogApp] {
        let query = search.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return apps }
        return apps.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        let visible = shown
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                LargeSerifTitle(title: title, eyebrow: eyebrow)
                if visible.isEmpty {
                    EmptyCard(message: emptyMessage)
                }
                ForEach(Family.allCases, id: \.self) { family in
                    let group = visible.filter { $0.family == family }
                    if !group.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            SectionTitle(family.rawValue)
                            AppGrid(apps: group)
                        }
                    }
                }
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct AppGrid: View {
    let apps: [CatalogApp]

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 380), spacing: 12, alignment: .top)], alignment: .leading, spacing: 12) {
            ForEach(apps) { app in
                AppCard(app: app)
            }
        }
    }
}

struct EmptyCard: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.system(size: 13.5))
            .foregroundStyle(Refined.dim)
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Refined.cardRadius, style: .continuous).fill(Refined.card))
    }
}

struct UpdatesPage: View {
    @EnvironmentObject private var store: LauncherStore

    private var problems: [CatalogApp] {
        Catalog.apps.filter { $0.repo != nil && store.state($0).checkMessage != nil && store.state($0).asset == nil }
    }

    private var eyebrow: String {
        switch store.updateCount {
        case 0: return "Everything is up to date"
        case 1: return "1 update available"
        default: return "\(store.updateCount) updates available"
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                HStack(alignment: .bottom) {
                    LargeSerifTitle(title: "Updates", eyebrow: eyebrow)
                    Spacer()
                    if store.updateCount > 1 {
                        Button("Update all") { store.updateAll() }
                            .buttonStyle(RefinedActionStyle(kind: .strong))
                    }
                }
                if store.updateCount == 0 {
                    EmptyCard(message: "The launcher checks the apps it installs from GitHub. TestFlight and Xcode keep the others current.")
                } else {
                    AppGrid(apps: store.appsWithUpdates)
                }
                if !problems.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionTitle("Couldn't check")
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(problems.enumerated()), id: \.element.id) { index, app in
                                if index > 0 {
                                    Rectangle().fill(Refined.separator).frame(height: 1)
                                }
                                HStack(alignment: .firstTextBaseline, spacing: 10) {
                                    Text(app.name)
                                        .font(.system(size: 13.5, weight: .semibold))
                                        .foregroundStyle(Refined.ink)
                                    Text(store.state(app).checkMessage ?? "")
                                        .font(.system(size: 12.5))
                                        .foregroundStyle(Refined.mute)
                                    Spacer(minLength: 0)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 11)
                            }
                        }
                        .background(RoundedRectangle(cornerRadius: Refined.cardRadius, style: .continuous).fill(Refined.card))
                    }
                }
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// The app's own icon when it's on this Mac. Otherwise a square in the app's palette fill with its initial.
struct AppIconView: View {
    let app: CatalogApp
    let installedURL: URL?

    var body: some View {
        Group {
            if let url = installedURL {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                    .resizable()
                    .interpolation(.high)
            } else {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Refined.fill(app.hue))
                    .padding(4)
                    .overlay(
                        Text(String(app.name.prefix(1)))
                            .font(Refined.serif(24, weight: .medium))
                            .foregroundStyle(Refined.inkOn(app.hue))
                    )
            }
        }
        .frame(width: 56, height: 56)
        .accessibilityHidden(true)
    }
}

struct AppCard: View {
    @EnvironmentObject private var store: LauncherStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let app: CatalogApp
    @State private var hovered = false

    var body: some View {
        let current = store.state(app)
        let status = store.status(app)
        let canOpen = current.installed != nil
        let shape = RoundedRectangle(cornerRadius: Refined.cardRadius, style: .continuous)
        HStack(spacing: 12) {
            // The icon and the words are one button that opens the app. The actions beside it are their own buttons.
            Button {
                store.open(app)
            } label: {
                HStack(spacing: 14) {
                    AppIconView(app: app, installedURL: current.installed?.url)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(app.name)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Refined.ink)
                            .lineLimit(1)
                        Text(app.tagline)
                            .font(.system(size: 12.5))
                            .foregroundStyle(Refined.dim)
                            .lineLimit(1)
                        statusLine(current, status)
                        progress(current)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .allowsHitTesting(canOpen)
            .help(canOpen ? "Open \(app.name)" : "")
            .accessibilityLabel(canOpen ? "Open \(app.name)" : app.name)

            actions(current, status)
        }
        .padding(.leading, 12)
        .padding(.trailing, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, minHeight: 82, alignment: .leading)
        .background(shape.fill(Refined.card))
        .overlay(shape.fill(Refined.hoverWash).opacity(hovered ? 1 : 0).allowsHitTesting(false))
        .shadow(color: Color.black.opacity(hovered && !reduceMotion ? 0.10 : 0), radius: 10, x: 0, y: 4)
        .offset(y: hovered && !reduceMotion ? -2 : 0)
        .animation(.smooth(duration: 0.3), value: hovered)
        .onHover { hovered = $0 }
        .contextMenu { menu(current) }
    }

    @ViewBuilder
    private func menu(_ current: AppState) -> some View {
        if current.installed != nil {
            Button("Open") { store.open(app) }
            Button("Show in Finder") { store.reveal(app) }
            if current.installed?.isInApplications == false {
                Button("Move to Applications") { store.moveToApplications(app) }
            }
            Divider()
        }
        if current.release != nil {
            Button("View release on GitHub") { store.openRelease(app) }
        }
        if app.repo != nil {
            Button("Open repo on GitHub") { store.openRepo(app) }
        }
        if app.source == .testFlight {
            Button("Open TestFlight") { store.openTestFlight() }
        }
        Divider()
        Button("Choose app…") { store.chooseApp(app) }
        if store.hasChosenApp(app) {
            Button("Forget chosen app") { store.forgetChosenApp(app) }
        }
    }

    @ViewBuilder
    private func statusLine(_ current: AppState, _ status: AppStatus) -> some View {
        let installed = store.installedLabel(app) + (current.installed?.locationNote.map { " · \($0)" } ?? "")
        let latest = store.latestLabel(app)
        switch current.phase {
        case .failed(let message):
            Text(message)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(Refined.danger)
                .lineLimit(2)
        case .installing:
            muted("Installing \(latest)")
        case .downloading:
            muted("Downloading \(latest)")
        case .idle:
            switch status {
            case .unavailable:
                muted(current.checkMessage ?? missingNote)
            case .notInstalled:
                muted(app.source == .testFlight ? "Not on this Mac · Get it in TestFlight" : "Not on this Mac · \(latest) available")
            case .upToDate:
                muted("Up to date · \(installed)")
            case .updateAvailable:
                HStack(spacing: 8) {
                    muted(installed)
                    RefinedChipLabel(text: "Update to \(latest)")
                }
            case .installed:
                muted(installedNote(current).map { "\(installed) · \($0)" } ?? installed)
            }
        }
    }

    /// Why an app that isn't on this Mac has no Install button.
    private var missingNote: String {
        switch app.source {
        case .xcode: return "Not found. Run it from Xcode once, or choose the app."
        case .file: return "Not on this Mac."
        case .none: return "No Mac build yet."
        case .github: return "No Mac build published yet."
        case .testFlight: return "Not on this Mac."
        }
    }

    /// How an app on this Mac stays current, when the launcher doesn't update it.
    private func installedNote(_ current: AppState) -> String? {
        switch app.source {
        case .testFlight: return "Updates through TestFlight"
        case .xcode: return "Built in Xcode"
        case .file: return "Installed from a build file"
        case .none: return nil
        case .github: return current.checkMessage == nil ? nil : "Couldn't check for updates"
        }
    }

    @ViewBuilder
    private func progress(_ current: AppState) -> some View {
        if case .downloading(let fraction, let written, let total) = current.phase {
            ProgressView(value: fraction)
                .progressViewStyle(.linear)
                .tint(Refined.ink)
                .frame(maxWidth: 260)
            Text("\(bytes(written)) of \(bytes(total))")
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(Refined.mute)
        }
    }

    @ViewBuilder
    private func actions(_ current: AppState, _ status: AppStatus) -> some View {
        switch current.phase {
        case .downloading(let fraction, _, _):
            Text("\(Int(fraction * 100))%")
                .font(.system(size: 13, weight: .semibold).monospacedDigit())
                .foregroundStyle(Refined.dim)
        case .installing:
            ProgressView().controlSize(.small)
        default:
            HStack(spacing: 8) {
                switch status {
                case .updateAvailable:
                    Button("Update") { store.requestInstall(app) }
                        .buttonStyle(RefinedActionStyle(kind: .quiet))
                    Button("Open") { store.open(app) }
                        .buttonStyle(RefinedActionStyle(kind: .strong))
                case .upToDate, .installed:
                    Button("Open") { store.open(app) }
                        .buttonStyle(RefinedActionStyle(kind: .strong))
                case .notInstalled:
                    if app.source == .testFlight {
                        Button("Open TestFlight") { store.openTestFlight() }
                            .buttonStyle(RefinedActionStyle(kind: .quiet))
                    } else {
                        Button("Install") { store.requestInstall(app) }
                            .buttonStyle(RefinedActionStyle(kind: .strong))
                    }
                case .unavailable:
                    if app.source != Source.none {
                        Button("Choose app…") { store.chooseApp(app) }
                            .buttonStyle(RefinedActionStyle(kind: .quiet))
                    }
                }
            }
        }
    }

    private func muted(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12.5).monospacedDigit())
            .foregroundStyle(Refined.mute)
            .lineLimit(2)
    }

    private func bytes(_ count: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: count, countStyle: .file)
    }
}

struct SettingsView: View {
    @EnvironmentObject private var store: LauncherStore
    @State private var token = ""

    private var trimmedToken: String { token.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        Form {
            Section {
                if store.hasToken {
                    HStack {
                        Label("Token saved in your keychain", systemImage: "checkmark.seal")
                        Spacer()
                        Button("Remove") {
                            store.removeToken()
                            Task { await store.checkForUpdates() }
                        }
                    }
                }
                SecureField(store.hasToken ? "Replace token" : "Paste token", text: $token)
                HStack {
                    Button("Save token") {
                        store.saveToken(trimmedToken)
                        token = ""
                        Task { await store.checkForUpdates() }
                    }
                    .disabled(trimmedToken.isEmpty)
                    Spacer()
                    Link("Create a token on GitHub", destination: URL(string: "https://github.com/settings/personal-access-tokens/new")!)
                }
                Text("Use a fine-grained token for stumpandroot with read-only Contents access. The launcher uses it to see draft builds and private repos, and it stays in your keychain.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } header: {
                Text("GitHub token")
            }

            Section {
                Toggle("Include draft releases", isOn: $store.includeDrafts)
                    .disabled(!store.hasToken)
                Text("Drafts are builds you haven't published yet. Seeing them needs a token.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Builds")
            }
        }
        .formStyle(.grouped)
        .frame(width: 500)
        .onChange(of: store.includeDrafts) {
            Task { await store.checkForUpdates() }
        }
    }
}
