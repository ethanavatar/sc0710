#!/bin/bash
# Extract ECP5 firmware from the Elgato 4K Pro Windows driver installer
# and install it for Fedora Atomic (Bazzite, Silverblue, Aurora, etc.)
#
# On atomic distros, /lib/firmware/ is read-only. This script installs
# the firmware to /var/lib/sc0710/firmware/ and creates a symlink at
# /etc/firmware/sc0710/ (writable, persists across updates) so the
# kernel firmware loader can find it.
#
# Requires: curl, 7z (p7zip — layered via rpm-ostree)
# Usage: sudo bash atomic-extract-firmware.sh

set -e

DOWNLOAD_URL="https://edge.elgato.com/egc/windows/drivers/4K_Pro/Elgato_4KPro_1.1.0.202.exe"
FIRMWARE_STORE="/var/lib/sc0710/firmware"
FIRMWARE_FILE="SC0710.FWI.HEX"
INSTALLER="Elgato_4KPro_1.1.0.202.exe"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
BOLD='\033[1m'
NC='\033[0m'

msg()  { echo -e "${BLUE}::${NC} ${BOLD}$*${NC}"; }
msg2() { echo -e " ${BLUE}->${NC} $*"; }
error(){ echo -e "${RED}error:${NC} $*" >&2; }

# --- Root check ---
if [[ $EUID -ne 0 ]]; then
    error "This script must be run as root."
    echo -e "Usage: ${BOLD}sudo bash atomic-extract-firmware.sh${NC}"
    exit 1
fi

# --- Detect atomic distro ---
is_atomic() {
    [[ -f /run/ostree-booted ]] || command -v rpm-ostree &>/dev/null
}

if ! is_atomic; then
    error "This script is for Fedora Atomic distros (Bazzite, Silverblue, etc.)."
    echo -e "For standard distros, use: ${BOLD}sudo bash extract-firmware.sh${NC}"
    exit 1
fi

# --- Check if firmware is already present ---
# Check both the writable location and the standard location
if [[ -f "$FIRMWARE_STORE/$FIRMWARE_FILE" ]]; then
    echo -e "${GREEN}[OK]${NC} Firmware already present at $FIRMWARE_STORE/$FIRMWARE_FILE"
    exit 0
fi

if [[ -f "/lib/firmware/sc0710/$FIRMWARE_FILE" ]]; then
    echo -e "${GREEN}[OK]${NC} Firmware already present at /lib/firmware/sc0710/$FIRMWARE_FILE"
    exit 0
fi

# --- Install dependencies via rpm-ostree ---
install_deps() {
    local need_curl=0
    local need_7z=0

    command -v curl >/dev/null 2>&1 || need_curl=1
    command -v 7z   >/dev/null 2>&1 || need_7z=1

    if [[ "$need_curl" -eq 0 && "$need_7z" -eq 0 ]]; then
        return 0
    fi

    local pkgs=""
    [[ "$need_curl" -eq 1 ]] && pkgs="$pkgs curl"
    [[ "$need_7z"   -eq 1 ]] && pkgs="$pkgs p7zip p7zip-plugins"

    if [[ -n "$pkgs" ]]; then
        msg "Installing dependencies via rpm-ostree:$pkgs"
        if rpm-ostree install --apply-live $pkgs 2>&1; then
            msg2 "Dependencies installed."
        else
            error "Failed to install dependencies."
            echo -e "Try manually: ${BOLD}sudo rpm-ostree install$pkgs${NC}"
            echo -e "Then reboot and re-run this script."
            exit 1
        fi
    fi
}

msg "Elgato 4K Pro Firmware Extractor (Atomic Edition)"
echo ""

install_deps

# --- Download and extract ---
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

msg "Downloading Elgato 4K Pro driver installer..."
curl -L -o "$TMPDIR/$INSTALLER" "$DOWNLOAD_URL"

msg "Extracting firmware..."
7z x -y -o"$TMPDIR/extracted" "$TMPDIR/$INSTALLER" "Final/Game_Capture_4K_Pro/$FIRMWARE_FILE" > /dev/null

SRC="$TMPDIR/extracted/Final/Game_Capture_4K_Pro/$FIRMWARE_FILE"
if [[ ! -f "$SRC" ]]; then
    error "$FIRMWARE_FILE not found in installer."
    exit 1
fi

# --- Install firmware to writable location ---
msg "Installing firmware..."

mkdir -p "$FIRMWARE_STORE"
cp "$SRC" "$FIRMWARE_STORE/$FIRMWARE_FILE"
msg2 "Firmware stored at: $FIRMWARE_STORE/$FIRMWARE_FILE"

# Create a symlink from the standard firmware path if possible.
# On atomic distros /lib/firmware is read-only, so we use /etc/firmware instead.
# The kernel firmware loader checks /etc/firmware/ as a fallback on Fedora.
if [[ ! -d "/lib/firmware/sc0710" ]]; then
    # /lib/firmware/sc0710 doesn't exist (expected on atomic), use /etc path
    mkdir -p "/etc/firmware/sc0710"
    ln -sf "$FIRMWARE_STORE/$FIRMWARE_FILE" "/etc/firmware/sc0710/$FIRMWARE_FILE"
    msg2 "Symlink created: /etc/firmware/sc0710/$FIRMWARE_FILE -> $FIRMWARE_STORE/$FIRMWARE_FILE"
fi

echo ""
echo -e "${GREEN}[OK]${NC} Firmware installed successfully."
echo ""
echo -e "${BOLD}Note:${NC} The driver module must be reloaded to pick up the firmware."
echo -e "Run: ${BOLD}sc0710-cli --restart${NC}"
echo ""
