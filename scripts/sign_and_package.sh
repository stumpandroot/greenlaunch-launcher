#!/bin/bash
# Signs dist/GreenLaunch.app, puts it in dist/GreenLaunch.dmg, notarizes the DMG, and staples the ticket.
#
# Environment:
#   SIGN_IDENTITY       "Developer ID Application: Your Name (TEAMID)". Without it, the DMG holds the
#                       ad-hoc signed app (fine on your own Mac after "Open Anyway", not for anyone else).
#   APPLE_ID, APPLE_APP_PASSWORD, APPLE_TEAM_ID   for notarizing. Without them, the DMG is signed but not notarized.
set -euo pipefail
cd "$(dirname "$0")/.."

APP="dist/GreenLaunch.app"
DMG="dist/GreenLaunch.dmg"

if [ -n "${SIGN_IDENTITY:-}" ]; then
  echo "Signing GreenLaunch with $SIGN_IDENTITY"
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
hdiutil create -volname "GreenLaunch" -srcfolder "$STAGE" -ov -format UDZO "$DMG"
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
echo "Packaged $DMG"
