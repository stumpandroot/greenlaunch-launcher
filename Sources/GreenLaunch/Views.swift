import AppKit
import SwiftUI

enum SidebarItem: Hashable {
    case apps
    case updates
}

struct ContentView: View {
    @EnvironmentObject private var store: LauncherStore
    @State private var selection: SidebarItem? = .apps

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Label("My apps", systemImage: "square.grid.2x2")
                    .tag(SidebarItem.apps)
                Label("Updates", systemImage: "arrow.triangle.2.circlepath")
                    .badge(store.updateCount)
                    .tag(SidebarItem.updates)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
        } detail: {
            Group {
                switch selection ?? .apps {
                case .apps: AppsView()
                case .updates: UpdatesView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Brand.cream)
        }
        .tint(Brand.ink)
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
                message: Text("\(app.name) is open. GreenLaunch quits it, installs the new version, and you can open it again."),
                primaryButton: .default(Text("Quit and update")) { store.quitAndInstall(app) },
                secondaryButton: .cancel()
            )
        }
    }
}

struct PageHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(Brand.ink)
            Text(subtitle)
                .font(.system(size: 13))
                .foregroundStyle(Brand.muted)
        }
        .padding(.bottom, 4)
    }
}

struct AppsView: View {
    @EnvironmentObject private var store: LauncherStore

    private var subtitle: String {
        var text = "\(store.installedCount) of \(Catalog.apps.count) installed"
        if let checked = store.lastChecked {
            text += " · Checked \(checked.formatted(date: .omitted, time: .shortened))"
        }
        return text
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                PageHeader(title: "My apps", subtitle: subtitle)
                ForEach(Catalog.apps) { app in
                    AppRow(app: app)
                }
            }
            .padding(28)
        }
    }
}

struct UpdatesView: View {
    @EnvironmentObject private var store: LauncherStore

    private var problems: [CatalogApp] {
        Catalog.apps.filter { $0.repo != nil && store.state($0).checkMessage != nil && store.state($0).asset == nil }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    PageHeader(
                        title: "Updates",
                        subtitle: store.updateCount == 0 ? "Everything is up to date." : "\(store.updateCount) update\(store.updateCount == 1 ? "" : "s") available."
                    )
                    Spacer()
                    if store.updateCount > 1 {
                        Button("Update all") { store.updateAll() }
                            .buttonStyle(PrimaryButtonStyle())
                    }
                }
                ForEach(store.appsWithUpdates) { app in
                    AppRow(app: app)
                }
                if !problems.isEmpty {
                    Text("Couldn't check")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Brand.ink)
                        .padding(.top, 14)
                    ForEach(problems) { app in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(app.name).font(.system(size: 13, weight: .semibold))
                            Text(store.state(app).checkMessage ?? "")
                                .font(.system(size: 13))
                                .foregroundStyle(Brand.muted)
                        }
                    }
                }
            }
            .padding(28)
        }
    }
}

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
                RoundedRectangle(cornerRadius: 10)
                    .fill(app.tint.opacity(0.22))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(Brand.muted.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    )
                    .overlay(
                        Text(String(app.name.prefix(1)))
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(Brand.ink)
                    )
            }
        }
        .frame(width: 44, height: 44)
        .accessibilityHidden(true)
    }
}

struct AppRow: View {
    @EnvironmentObject private var store: LauncherStore
    let app: CatalogApp

    var body: some View {
        let current = store.state(app)
        let status = store.status(app)
        HStack(spacing: 14) {
            AppIconView(app: app, installedURL: current.installed?.url)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(app.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Brand.ink)
                    if current.release?.draft == true {
                        Pill(text: "Draft", fill: Brand.line)
                    }
                }
                statusLine(current, status)
                if case .downloading(let fraction, let written, let total) = current.phase {
                    ProgressView(value: fraction)
                        .progressViewStyle(.linear)
                        .tint(Brand.ink)
                        .frame(maxWidth: 420)
                    Text("\(bytes(written)) of \(bytes(total))")
                        .font(.system(size: 11))
                        .foregroundStyle(Brand.muted)
                }
            }
            Spacer(minLength: 12)
            actions(current, status)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Brand.line, lineWidth: 1))
        .contextMenu {
            if current.installed != nil {
                Button("Show in Finder") { store.reveal(app) }
            }
            if current.release != nil {
                Button("View release on GitHub") { store.openRelease(app) }
            }
            if app.repo != nil {
                Button("Open repo on GitHub") { store.openRepo(app) }
            }
        }
    }

    @ViewBuilder
    private func statusLine(_ current: AppState, _ status: AppStatus) -> some View {
        let installedVersion = (current.installed?.version.map(displayVersion) ?? "Unknown version")
            + (current.installed?.locationNote.map { " · \($0)" } ?? "")
        let latest = current.release.map { displayVersion($0.tag_name) } ?? ""
        switch current.phase {
        case .failed(let message):
            Text(message)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Brand.error)
                .lineLimit(2)
        case .installing:
            muted("Installing \(latest)…")
        case .downloading:
            muted("Downloading \(latest)…")
        case .idle:
            switch status {
            case .noBuild:
                muted(current.checkMessage ?? app.tagline)
            case .notInstalled:
                muted("Not installed · \(latest) available")
            case .upToDate:
                muted("Up to date · \(installedVersion)")
            case .updateAvailable:
                HStack(spacing: 8) {
                    muted(installedVersion)
                    Pill(text: "Update to \(latest)")
                }
            case .installedUnknown:
                muted(current.checkMessage.map { "\(installedVersion) · \($0)" } ?? installedVersion)
            }
        }
    }

    @ViewBuilder
    private func actions(_ current: AppState, _ status: AppStatus) -> some View {
        switch current.phase {
        case .downloading(let fraction, _, _):
            Text("\(Int(fraction * 100))%")
                .font(.system(size: 13, weight: .semibold).monospacedDigit())
                .foregroundStyle(Brand.muted)
        case .installing:
            ProgressView().controlSize(.small)
        default:
            HStack(spacing: 8) {
                switch status {
                case .updateAvailable:
                    Button("Update") { store.requestInstall(app) }
                        .buttonStyle(SecondaryButtonStyle())
                    Button("Open") { store.open(app) }
                        .buttonStyle(PrimaryButtonStyle())
                case .upToDate, .installedUnknown:
                    if current.installed?.isInApplications == false {
                        Button("Move to Applications") { store.moveToApplications(app) }
                            .buttonStyle(SecondaryButtonStyle())
                    }
                    Button("Open") { store.open(app) }
                        .buttonStyle(PrimaryButtonStyle())
                case .notInstalled:
                    Button("Install") { store.requestInstall(app) }
                        .buttonStyle(PrimaryButtonStyle())
                case .noBuild:
                    EmptyView()
                }
            }
        }
    }

    private func muted(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13))
            .foregroundStyle(Brand.muted)
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
                Text("Use a fine-grained token for stumpandroot with read-only Contents access. GreenLaunch uses it to see draft builds and private repos, and it stays in your keychain.")
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
        .onChange(of: store.includeDrafts) { _ in
            Task { await store.checkForUpdates() }
        }
    }
}
