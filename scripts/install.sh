#!/bin/bash
# Optional terminal installer. The DMG is the recommended installation method.
set -euo pipefail
REPO="brunozapico/loro"
ASSET="Loro-macos-arm64.zip"
INSTALL_DIR="${LORO_INSTALL_DIR:-/Applications}"
if [ "$(uname -s)" != Darwin ] || [ "$(uname -m)" != arm64 ]; then
    echo 'Loro requires macOS 14+ on Apple Silicon.' >&2
    exit 1
fi
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" -o "$TMP/release.json"
TAG="$(plutil -extract tag_name raw "$TMP/release.json")"
BASE="https://github.com/$REPO/releases/download/$TAG"
curl -fL "$BASE/$ASSET" -o "$TMP/$ASSET"
curl -fsSL "$BASE/$ASSET.sha256" -o "$TMP/$ASSET.sha256"
(cd "$TMP" && shasum -a 256 -c "$ASSET.sha256")
ditto -x -k "$TMP/$ASSET" "$TMP"
codesign --verify --deep --strict "$TMP/Loro.app"
if pgrep -x loro >/dev/null; then
    echo 'Quit Loro before installing the update, then run this installer again.' >&2
    exit 1
fi
mkdir -p "$INSTALL_DIR"
if [ -e "$INSTALL_DIR/Loro.app" ]; then
    BACKUP="$INSTALL_DIR/Loro.app.backup-$(date +%Y%m%d%H%M%S)"
    mv "$INSTALL_DIR/Loro.app" "$BACKUP"
    echo "Previous version kept at $BACKUP"
fi
ditto "$TMP/Loro.app" "$INSTALL_DIR/Loro.app"
echo "Installed $INSTALL_DIR/Loro.app. Open it from Applications."
open "$INSTALL_DIR/Loro.app"
