#!/bin/bash
# Builds dist/GreenLaunch.app (Apple silicon and Intel in one app). scripts/sign_and_package.sh makes the DMG.
# Needs a Mac with Xcode or the Xcode command line tools.
#   VERSION  the version shown in the app, like 0.1.4 (default 0.1.0)
#   BUILD    the build number (default 1)
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${VERSION:-0.1.0}"
BUILD="${BUILD:-1}"

swift build -c release --arch arm64 --arch x86_64
BIN_DIR="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)"

APP="dist/GreenLaunch.app"
rm -rf dist
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/GreenLaunch" "$APP/Contents/MacOS/GreenLaunch"
sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD/" packaging/Info.plist > "$APP/Contents/Info.plist"
iconutil -c icns packaging/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"

# Ad-hoc signature so the app runs on Apple silicon. It isn't notarized.
codesign --force --deep --sign - "$APP"
codesign --verify --verbose=2 "$APP"
lipo -info "$APP/Contents/MacOS/GreenLaunch"

echo "Built $APP ($VERSION, build $BUILD)"
