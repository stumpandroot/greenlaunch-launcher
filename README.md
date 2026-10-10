# GreenLaunch launcher (personal build)

GreenLaunch is a Mac app that lists your GreenLaunch apps, opens them, and installs or updates them from each app's GitHub Releases. This build is for your own use, so it has no license check.

## What it does

- Finds each app in Applications and shows its installed version.
- Checks each app's GitHub repo for the newest release that has a DMG for your Mac's chip, Apple silicon or Intel.
- Installs or updates an app: it downloads the DMG, quits the app if it's open (after asking), puts the old copy in the Trash, and copies the new one into place.
- Opens an app, shows it in Finder, or opens its release page on GitHub. Right-click a row for the last two.
- Sees draft releases and private repos when you add a GitHub token in **Settings** (⌘,).

## Get the app

1. Open the [latest release](https://github.com/stumpandroot/greenlaunch-launcher/releases/latest) and download `GreenLaunch.zip`.
2. Unzip it and drag **GreenLaunch** to your Applications folder.
3. Open it. The first time, macOS blocks it because it isn't notarized. Go to **System Settings > Privacy & Security**, scroll down, and click **Open Anyway** next to the GreenLaunch message.

## Add a GitHub token

Your Vectorize and Aptus builds are drafts until you publish them, and Versa's repo is private. GreenLaunch needs a read-only token to see them.

1. Open [GitHub's new fine-grained token page](https://github.com/settings/personal-access-tokens/new).
2. Name it `GreenLaunch`, and set **Expiration** to the longest option you're comfortable with.
3. Under **Resource owner**, choose **stumpandroot**.
4. Under **Repository access**, choose **All repositories**.
5. Under **Permissions > Repository permissions**, set **Contents** to **Read-only**. GitHub adds **Metadata: Read-only** automatically.
6. Click **Generate token** and copy it.
7. In GreenLaunch, press ⌘, to open Settings, paste the token, and click **Save token**.

The token stays in your Mac's keychain. After each GreenLaunch update, macOS may ask once whether GreenLaunch can use it. Click **Always Allow**.

## Add or change an app

The list of apps is in `Sources/GreenLaunch/Catalog.swift`. Each entry has the app's name (its file name in Applications), the GitHub repo that holds its releases, and its bundle identifier if it has one. Set `repo` to `nil` for an app with no builds yet.

## How a build happens

Every push to `main` runs `.github/workflows/build.yml` on GitHub's Macs. It builds one app that runs on Apple silicon and Intel, runs the self-test, and publishes a release named **GreenLaunch 0.1.*N*** with `GreenLaunch.zip` attached.

To build on a Mac instead, run `bash scripts/build_app.sh`. The app lands in `dist/`.
