#!/bin/bash
# Prove that a real update preserves identity without admitting other signers.
set -euo pipefail
IDENTITY="${CODESIGN_IDENTITY:-$(cat "$HOME/Library/Application Support/Loro/Signing/identity")}"
[ -n "$IDENTITY" ] && [ "$IDENTITY" != - ] || { echo 'A persistent identity is required.' >&2; exit 1; }
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
for VERSION in 1 2; do
    APP="$WORK/$VERSION/Loro.app"
    mkdir -p "$APP/Contents/MacOS"
    cp /usr/bin/true "$APP/Contents/MacOS/loro"
    cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.brunozapico.loro.signing-test</string>
<key>CFBundleExecutable</key><string>loro</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>$VERSION</string>
</dict></plist>
PLIST
    codesign --force --sign "$IDENTITY" "$APP"
    codesign --verify --strict "$APP"
done
REQUIREMENT="$(codesign -d -r- "$WORK/1/Loro.app" 2>&1 | sed -n 's/^designated => //p')"
[ -n "$REQUIREMENT" ] || { echo 'Missing certificate-based requirement' >&2; exit 1; }
codesign --verify --strict -R "=$REQUIREMENT" "$WORK/2/Loro.app"
HASH1="$(codesign -d --verbose=4 "$WORK/1/Loro.app" 2>&1 | sed -n 's/^CDHash=//p')"
HASH2="$(codesign -d --verbose=4 "$WORK/2/Loro.app" 2>&1 | sed -n 's/^CDHash=//p')"
[ "$HASH1" != "$HASH2" ] || { echo 'Fixture must actually change' >&2; exit 1; }
codesign --force --sign - "$WORK/2/Loro.app"
if codesign --verify -R "=$REQUIREMENT" "$WORK/2/Loro.app" 2>/dev/null; then
    echo 'Different signer was incorrectly accepted' >&2
    exit 1
fi
echo 'PASS: changed versions share certificate identity; another signer is rejected.'
