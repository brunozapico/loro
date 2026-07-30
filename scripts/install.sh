#!/usr/bin/env bash
# Loro installer.
#   curl -fsSL https://raw.githubusercontent.com/brunozapico/loro/main/scripts/install.sh | sh
#
# Fetches and verifies the latest arm64 macOS binary from GitHub Releases,
# drops it in /usr/local/bin, and strips the quarantine xattr so Gatekeeper
# doesn't block the unsigned binary.
#
# Apple Silicon only — WhisperKit uses the Apple Neural Engine via CoreML,
# which only ships on M-series chips.

set -euo pipefail

REPO="brunozapico/loro"
BIN_NAME="loro"
LEGACY_BIN_NAME="parrot"
INSTALL_DIR="/usr/local/bin"
ASSET="loro-macos-arm64.tar.gz"
CHECKSUM_ASSET="${ASSET}.sha256"
LAUNCH_AGENT="${HOME}/Library/LaunchAgents/com.brunozapico.loro.plist"

red()    { printf "\033[31m%s\033[0m\n" "$*" >&2; }
green()  { printf "\033[32m%s\033[0m\n" "$*"; }
dim()    { printf "\033[2m%s\033[0m\n" "$*"; }

# 1. sanity
if [ "$(uname -s)" != "Darwin" ]; then
    red "Loro is macOS-only (detected $(uname -s))"
    exit 1
fi

ARCH=$(uname -m)
if [ "$ARCH" != "arm64" ]; then
    red "Loro requires Apple Silicon (detected $ARCH)"
    red "the on-device inference engine uses the Apple Neural Engine, which Intel Macs don't have."
    exit 1
fi

for cmd in curl tar shasum; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        red "missing dependency: $cmd"
        exit 1
    fi
done

# 2. resolve latest release
dim "→ resolving latest release..."
TAG=$(curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest" \
    | grep -E '"tag_name"' \
    | head -1 \
    | sed -E 's/.*"tag_name": *"([^"]+)".*/\1/')

if [ -z "${TAG:-}" ]; then
    red "couldn't determine latest release tag"
    exit 1
fi
dim "  ${TAG}"

URL="https://github.com/${REPO}/releases/download/${TAG}/${ASSET}"
CHECKSUM_URL="https://github.com/${REPO}/releases/download/${TAG}/${CHECKSUM_ASSET}"

# 3. download + extract
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

dim "→ downloading ${ASSET}..."
curl -fsSL "$URL" -o "$TMP/${ASSET}"
curl -fsSL "$CHECKSUM_URL" -o "$TMP/${CHECKSUM_ASSET}"

dim "→ verifying checksum..."
(
    cd "$TMP"
    shasum -a 256 -c "$CHECKSUM_ASSET"
)

dim "→ extracting..."
tar -xzf "$TMP/${ASSET}" -C "$TMP"

if [ ! -f "$TMP/${BIN_NAME}" ]; then
    red "archive did not contain ${BIN_NAME}"
    exit 1
fi

chmod +x "$TMP/${BIN_NAME}"

# 4. strip quarantine so Gatekeeper lets the unsigned binary run
xattr -d com.apple.quarantine "$TMP/${BIN_NAME}" 2>/dev/null || true

# 5. stop the existing LaunchAgent before replacing its executable
AGENT_WAS_INSTALLED=0
if [ -f "$LAUNCH_AGENT" ]; then
    AGENT_WAS_INSTALLED=1
    dim "→ stopping the current Loro service..."
    launchctl bootout "gui/$(id -u)" "$LAUNCH_AGENT" 2>/dev/null || true
fi

# 6. install
SUDO=""
if [ ! -w "$INSTALL_DIR" ]; then
    if [ ! -d "$INSTALL_DIR" ]; then
        dim "→ creating ${INSTALL_DIR} (sudo)..."
        sudo mkdir -p "$INSTALL_DIR"
    fi
    SUDO="sudo"
fi

dim "→ installing to ${INSTALL_DIR}/${BIN_NAME}..."
$SUDO mv "$TMP/${BIN_NAME}" "${INSTALL_DIR}/${BIN_NAME}"
$SUDO chmod +x "${INSTALL_DIR}/${BIN_NAME}"

LEGACY_BIN="${INSTALL_DIR}/${LEGACY_BIN_NAME}"
if [ -f "$LEGACY_BIN" ]; then
    dim "→ removing legacy binary ${LEGACY_BIN}..."
    $SUDO rm -f "$LEGACY_BIN"
fi

# 7. restart the LaunchAgent when it was already configured
if [ "$AGENT_WAS_INSTALLED" -eq 1 ]; then
    dim "→ restarting Loro..."
    launchctl bootstrap "gui/$(id -u)" "$LAUNCH_AGENT"
fi

green "✓ Loro ${TAG} installed at ${INSTALL_DIR}/${BIN_NAME}"
echo
if [ "$AGENT_WAS_INSTALLED" -eq 1 ]; then
    echo "Important after an unsigned Loro update:"
    echo "  macOS may keep the old Accessibility entry while rejecting the new binary."
    echo "  If the shortcut does not respond, remove Loro from Accessibility and add:"
    echo "  ${INSTALL_DIR}/${BIN_NAME}"
    echo
fi
echo "next:"
echo "  loro setup                       # grant mic + accessibility"
echo "  loro install --launch-at-login   # (optional) start at login"
echo "  loro                             # run the daemon"
