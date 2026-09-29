#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION="${1:-0.3.1}"
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo 'Version must be MAJOR.MINOR.PATCH' >&2
    exit 1
fi
# Privacy grants follow the signing identity. Ad-hoc signatures default to a
# binary hash, so every rebuild invalidates the previous Accessibility grant.
IDENTITY="${CODESIGN_IDENTITY:-}"
LOCAL_IDENTITY="$HOME/Library/Application Support/Loro/Signing/identity"
if [ -z "$IDENTITY" ] && [ -f "$LOCAL_IDENTITY" ]; then
    IDENTITY="$(cat "$LOCAL_IDENTITY")"
fi
if [ -z "$IDENTITY" ] && [ "${LORO_ALLOW_ADHOC:-0}" = 1 ]; then IDENTITY=-; fi
if [ -z "$IDENTITY" ] || { [ "$IDENTITY" = - ] && [ "${LORO_ALLOW_ADHOC:-0}" != 1 ]; }; then
    echo 'A persistent signing identity is required. Run scripts/setup-local-signing.sh once on this Mac, or set CODESIGN_IDENTITY. Ad-hoc test artifacts require LORO_ALLOW_ADHOC=1.' >&2
    exit 1
fi
export LORO_SWIFTC="$(xcrun --find swiftc)"
export SWIFT_EXEC="$PWD/scripts/app-swiftc.py"
swift build -c release --arch arm64 -Xswiftc -DLORO_RELEASE_REQUIRES_FOUNDATION_MODELS
BIN_DIR="$(swift build -c release --arch arm64 --show-bin-path)"
# Stage outside cloud-synced Documents: File Provider can add FinderInfo after
# signing, which invalidates strict signature verification of the bundle.
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
APP="$WORK/Loro.app"
mkdir -p dist
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/loro" "$APP/Contents/MacOS/loro"
cp packaging/Info.plist "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
# SwiftPM dependency resources live in the standard, signed Resources directory.
for resource in "$BIN_DIR"/*.bundle; do
    [ -d "$resource" ] || continue
    ditto --norsrc --noextattr "$resource" "$APP/Contents/Resources/$(basename "$resource")"
done
ICON_DIR="$(mktemp -d)/Loro.iconset"
mkdir -p "$ICON_DIR"
swift scripts/make-icon.swift "$ICON_DIR"
iconutil -c icns "$ICON_DIR" -o "$APP/Contents/Resources/Loro.icns"
rm -rf "$(dirname "$ICON_DIR")"
# Reuse the same certificate for updates; never weaken its designated requirement.
chmod -R u+w "$APP"
xattr -cr "$APP"
codesign --force --deep --options runtime --entitlements packaging/entitlements.plist \
    --sign "$IDENTITY" "$APP"
codesign --verify --deep --strict "$APP"
plutil -lint "$APP/Contents/Info.plist"
# Keep a CLI archive, now including the dependency resource bundles.
CLI_STAGE="$(mktemp -d)"
cp "$BIN_DIR/loro" "$CLI_STAGE/loro"
for resource in "$BIN_DIR"/*.bundle; do
    [ -d "$resource" ] || continue
    ditto --norsrc --noextattr "$resource" "$CLI_STAGE/$(basename "$resource")"
done
tar -czf dist/loro-macos-arm64.tar.gz -C "$CLI_STAGE" .
rm -rf "$CLI_STAGE"
ditto -c -k --sequesterRsrc --keepParent "$APP" dist/Loro-macos-arm64.zip
DMG_STAGE="$(mktemp -d)"
ditto --norsrc --noextattr "$APP" "$DMG_STAGE/Loro.app"
ln -s /Applications "$DMG_STAGE/Applications"
hdiutil create -volname Loro -srcfolder "$DMG_STAGE" -ov -format UDZO dist/Loro-macos-arm64.dmg
rm -rf "$DMG_STAGE"
(cd dist && shasum -a 256 Loro-macos-arm64.zip > Loro-macos-arm64.zip.sha256 && \
 shasum -a 256 Loro-macos-arm64.dmg > Loro-macos-arm64.dmg.sha256 && \
 shasum -a 256 loro-macos-arm64.tar.gz > loro-macos-arm64.tar.gz.sha256)
rm -rf dist/Loro.app
ditto --norsrc --noextattr "$APP" dist/Loro.app
echo "Built dist/Loro.app and dist/Loro-macos-arm64.dmg"
