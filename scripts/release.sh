#!/bin/bash
# Builds a Developer ID-signed, notarized Contacter.app, zips it, and publishes a GitHub release.
# Usage: scripts/release.sh   (tag = v<MARKETING_VERSION> from project.yml)
# One-time: xcrun notarytool store-credentials tasker-notary --apple-id <you> --team-id SZVSSCJQFN
set -euo pipefail
cd "$(dirname "$0")/.."
PROFILE="${NOTARY_PROFILE:-tasker-notary}"
VERSION=$(awk -F'"' '/MARKETING_VERSION:/ {print $2; exit}' project.yml)
TAG="v$VERSION"
APP=build/release/Contacter.app
ZIP=build/release/Contacter-$VERSION.zip
DEV_ID=$(security find-identity -v -p codesigning | awk -F'"' '/Developer ID Application/ {print $2; exit}')
[[ -n "$DEV_ID" ]] || { echo "No Developer ID Application certificate"; exit 1; }

xcodegen generate
xcodebuild -project Contacter.xcodeproj -scheme Contacter -configuration Release -derivedDataPath build/release-dd \
    CODE_SIGN_IDENTITY="$DEV_ID" DEVELOPMENT_TEAM=SZVSSCJQFN CODE_SIGN_STYLE=Manual \
    ENABLE_HARDENED_RUNTIME=YES OTHER_CODE_SIGN_FLAGS=--timestamp clean build | tail -3
rm -rf build/release/Contacter.app "$ZIP"
mkdir -p build/release
ditto build/release-dd/Build/Products/Release/Contacter.app "$APP"
codesign --verify --strict --verbose=2 "$APP"
codesign -d --entitlements - "$APP" | grep -q addressbook || { echo "Missing Contacts entitlement"; exit 1; }

ditto -c -k --keepParent "$APP" "$ZIP"
xcrun notarytool submit "$ZIP" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$APP"
# Re-zip so the download carries the stapled ticket (Gatekeeper accepts it offline).
rm "$ZIP" && ditto -c -k --keepParent "$APP" "$ZIP"
spctl --assess --type execute --verbose "$APP"

if [[ "${PUBLISH:-1}" == 1 ]]; then
    git tag -f "$TAG" && git push -f origin "$TAG"
    gh release create "$TAG" "$ZIP" --verify-tag --title "Contacter $VERSION" --notes-file scripts/release-notes.md
fi
echo "Done: $ZIP ($(du -h "$ZIP" | cut -f1))"
