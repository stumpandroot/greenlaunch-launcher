#!/bin/bash
# Signs "dist/Stump & Root Apps.app", puts it in dist/StumpAndRootApps.dmg, notarizes the DMG, and staples the ticket.
#
# Environment:
#   SIGN_IDENTITY       "Developer ID Application: Your Name (TEAMID)". Without it, the DMG holds the
#                       ad-hoc signed app (fine on your own Mac after "Open Anyway", not for anyone else).
#   APPLE_ID, APPLE_APP_PASSWORD, APPLE_TEAM_ID   for notarizing. Without them, the DMG is signed but not notarized.
set -euo pipefail
cd "$(dirname "$0")/.."

APP="dist/Stump & Root Apps.app"
DMG="dist/StumpAndRootApps.dmg"

if [ -n "${SIGN_IDENTITY:-}" ]; then
  echo "Signing the app with $SIGN_IDENTITY"
  codesign --force --timestamp --options runtime --sign "$SIGN_IDENTITY" "$APP"
  codesign --verify --deep --strict --verbose=2 "$APP"
else
  echo "SIGN_IDENTITY isn't set, so the app keeps its ad-hoc signature."
fi

echo "Making $DMG"
STAGE="$(mktemp -d)"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
rm -f "$DMG"
hdiutil create -volname "Stump & Root Apps" -srcfolder "$STAGE" -ov -format UDZO "$DMG"
rm -rf "$STAGE"

if [ -n "${SIGN_IDENTITY:-}" ]; then
  codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DMG"
  if [ -n "${APPLE_ID:-}" ] && [ -n "${APPLE_APP_PASSWORD:-}" ] && [ -n "${APPLE_TEAM_ID:-}" ]; then
    echo "Notarizing (this usually takes a few minutes)"
    OUT="$(xcrun notarytool submit "$DMG" --apple-id "$APPLE_ID" --password "$APPLE_APP_PASSWORD" --team-id "$APPLE_TEAM_ID" --wait --timeout 45m --output-format json)"
    echo "$OUT"
    STATUS="$(echo "$OUT" | /usr/bin/python3 -c 'import json,sys; print(json.load(sys.stdin).get("status",""))')"
    if [ "$STATUS" != "Accepted" ]; then
      ID="$(echo "$OUT" | /usr/bin/python3 -c 'import json,sys; print(json.load(sys.stdin).get("id",""))')"
      [ -n "$ID" ] && xcrun notarytool log "$ID" --apple-id "$APPLE_ID" --password "$APPLE_APP_PASSWORD" --team-id "$APPLE_TEAM_ID" || true
      echo "Notarization status: $STATUS" >&2
      exit 1
    fi
    xcrun stapler staple "$DMG"
    xcrun stapler validate "$DMG"
    spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG"
  else
    echo "Apple ID secrets aren't set, so the DMG is signed but not notarized."
  fi
fi

hdiutil verify "$DMG"

# A zip of the same app, for installing without mounting the disk image.
rm -f dist/StumpAndRootApps.zip
ditto -c -k --keepParent "$APP" dist/StumpAndRootApps.zip
echo "Packaged $DMG"
