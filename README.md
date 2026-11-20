# Stump & Root Apps (personal build)

Stump & Root Apps is a Mac launcher for your own apps. It shows which ones are on this Mac, opens them, and installs or updates the ones that publish builds on GitHub. This build is for your own use, so it has no license check. It replaces GreenLaunch 0.1.

## What it does

- Lists every app in three groups: Verbose, Studio tools, and Personal.
- Finds each app and shows its installed version. It checks an app you chose by hand, the Applications folders, and the app's ID first, then asks Spotlight to search the whole Mac. It skips copies in the Trash, inside disk images, and nested inside other apps. An app with a known ID only matches a bundle with that ID.
- Opens an app when you click its card or press **Open**. Type in the search field and press Return to open the first match.
- Installs or updates an app that has GitHub releases: it downloads the DMG, quits the app if it's open (after asking), puts the old copy in the Trash, and copies the new one into place.
- Sends you to TestFlight for an app that ships through it.
- Lets you point it at an app it can't find, such as a build in Xcode's build folder: right-click the card and choose **Choose app…**.
- Sees draft releases and private repos when you add a GitHub token in **Settings** (⌘,).

## Where each app comes from

| App | File in Applications | Source | Version check |
| --- | --- | --- | --- |
| Verbose | `Verbatim.app` | `stumpandroot/verbose-updates` releases | Build number against `beta-N` tags |
| Verbose Tasks | `Verbose Tasks.app` | TestFlight | None; TestFlight updates it |
| Verbose Cut | `Verbose Cut.app` | Xcode on this Mac | None |
| Verbose Script | `Verbose Script.app` | A build file you install by hand | None |
| Verbose Projects | none | No Mac build yet | None |
| Verbose for iPhone | `Verbose.app` | TestFlight | None; TestFlight updates it |
| Keep | `Keep.app` | `stumpandroot/keep-updates` releases | Version against `vX.Y.Z` tags |
| Versa | `Versa.app` | `stumpandroot/versa` releases (private; needs a token) | Version against `vX.Y.Z` tags |
| Vectorize | `Vectorize.app` | `stumpandroot/Vectorize` releases | Version against `vX.Y.Z` tags |
| Aptus | `Aptus.app` | `stumpandroot/aptus-mac` releases | Version against `vX.Y.Z` tags |
| Steel Shelf | `Steel Shelf.app` | Xcode on this Mac | None |

Verbose also updates itself through Sparkle. The launcher reads the same releases, so the two agree.

## Get the app

1. Open the [latest release](https://github.com/stumpandroot/greenlaunch-launcher/releases/latest) and download `StumpAndRootApps.dmg`.
2. Open the DMG and drag **Stump & Root Apps** onto the **Applications** shortcut.
3. Open Stump & Root Apps from Applications.
4. Move the old **GreenLaunch** app to the Trash.

Without the signing secrets below, the build isn't notarized and macOS blocks it. To open an unsigned build, run this in Terminal once, then open the app again:

```
xattr -dr com.apple.quarantine "/Applications/Stump & Root Apps.app"
```

## Sign and notarize the build (once)

These are the same six secrets your Vectorize repo uses, with the same values. GitHub doesn't let you copy secrets between repos, so add them here again.

1. In this repo, go to **Settings > Secrets and variables > Actions**.
2. Click **New repository secret** for each of these:

   | Name | Value |
   | --- | --- |
   | `MACOS_CERTIFICATE` | Your Developer ID Application certificate as base64 text (from `base64 -i Certificates.p12 \| pbcopy`) |
   | `MACOS_CERTIFICATE_PWD` | The password you set when you exported `Certificates.p12` |
   | `MACOS_SIGN_IDENTITY` | `Developer ID Application: Your Name (TEAMID)`, exactly as Keychain Access shows it |
   | `APPLE_ID` | The email address of your Apple developer account |
   | `APPLE_APP_PASSWORD` | An app-specific password from [account.apple.com](https://account.apple.com) |
   | `APPLE_TEAM_ID` | Your 10-character team ID |

3. On the **Actions** tab, click **Build Stump & Root Apps**, then **Run workflow**.

The next release is signed and notarized, and it opens without warnings.

## Add a GitHub token

Your Vectorize and Aptus builds are drafts until you publish them, and Versa's repo is private. The launcher needs a read-only token to see them.

1. Open [GitHub's new fine-grained token page](https://github.com/settings/personal-access-tokens/new).
2. Name it `Stump & Root Apps`, and set **Expiration** to the longest option you're comfortable with.
3. Under **Resource owner**, choose **stumpandroot**.
4. Under **Repository access**, choose **All repositories**.
5. Under **Permissions > Repository permissions**, set **Contents** to **Read-only**. GitHub adds **Metadata: Read-only** automatically.
6. Click **Generate token** and copy it.
7. In the launcher, press ⌘, to open Settings, paste the token, and click **Save token**.

The token stays in your Mac's keychain. A token you saved in GreenLaunch carries over; macOS asks once whether Stump & Root Apps can use it. Click **Always Allow**.

## Add or change an app

The list of apps is in `Sources/StumpRootApps/Catalog.swift`. Each entry has the app's name, its file name in Applications, its family, its source, its bundle identifier if it has one, and the palette fill that stands in for its icon while the app isn't installed.

Sources:

- `.github(repo:tags:)`: the launcher installs and updates the app from the repo's releases. Use `.version` for tags like `v1.2.0` and `.build(prefix:)` for tags like `beta-361`.
- `.testFlight`: the launcher opens TestFlight.
- `.xcode`: you build and run the app from Xcode.
- `.file`: you install the app by hand from a build file.
- `.none`: the app has no Mac build yet.

## Design

The launcher follows the Verbose family look (Verbose's `mac/DESIGN.md`, section 13). The system draws the sidebar, toolbar, menus, and Settings. The app draws the paper page, off-white cards with no outlines, serif titles, and the palette fills. The values are in `Sources/StumpRootApps/Tokens.swift`. A card rises slightly under the pointer; Reduce Motion keeps it still.

## How a build happens

Every push to `main` runs `.github/workflows/build.yml` on GitHub's Macs. It builds one app that runs on Apple silicon and Intel, runs the self-test, and publishes a release named **Stump & Root Apps 0.2.*N*** with `StumpAndRootApps.dmg` attached. A push to a `claude/` branch publishes a preview (a prerelease) instead.

To build on a Mac instead, run `bash scripts/build_app.sh`. The app lands in `dist/`.
