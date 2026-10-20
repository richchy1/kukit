#!/bin/zsh
# Builds a Release Kukit.app for Apple Silicon and packs it into build/Kukit-<version>.dmg.
#
# The app is signed ad hoc, so macOS shows an "unidentified developer" warning on other Macs:
# open it once with right-click ▸ Open, or System Settings ▸ Privacy & Security ▸ Open Anyway.
# A Developer ID certificate + notarization (Apple Developer Program) removes the warning.
set -euo pipefail
cd "$(dirname "$0")/.."

command -v xcodegen >/dev/null && xcodegen generate >/dev/null

# Build outside the project folder: Desktop/iCloud folders add Finder metadata to files, and
# codesign refuses to sign an app bundle that contains any.
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
DERIVED="$WORK/DerivedData"
xcodebuild -project Kukit.xcodeproj -scheme Kukit-macOS -configuration Release \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath "$DERIVED" \
  CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= build | tail -3

APP="$DERIVED/Build/Products/Release/Kukit.app"
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP/Contents/Info.plist")
STAGE="$WORK/stage"
mkdir -p "$STAGE" build
cp -R "$APP" "$STAGE/Kukit.app"
xattr -cr "$STAGE/Kukit.app"
ln -s /Applications "$STAGE/Applications"

OUT="build/Kukit-$VERSION.dmg"
rm -f "$OUT"
hdiutil create -volname "Kukit $VERSION" -srcfolder "$STAGE" -ov -format UDZO "$OUT" >/dev/null
echo "Created $OUT"
codesign -dv "$APP" 2>&1 | grep -E "Signature|Identifier" || true
