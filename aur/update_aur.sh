#!/bin/bash

# This script is used only by me (nakildias) to automate the AUR update process.

# Exit immediately if a command exits with a non-zero status
set -e

# Define variables
AUR_REPO_URL="ssh://aur@aur.archlinux.org/sc0710-dkms-git.git"
MAIN_REPO_URL="https://github.com/Nakildias/sc0710.git"
RAW_VERSION_URL="https://raw.githubusercontent.com/Nakildias/sc0710/refs/heads/main/version"
WORK_DIR="/tmp/sc0710_deploy"
MAIN_DIR="$WORK_DIR/main"
AUR_DIR="$WORK_DIR/aur"

# Set up a trap to ensure cleanup happens no matter what
cleanup() {
    echo "Cleaning up workspace and SSH agent..."
    rm -rf "$WORK_DIR"
    eval $(ssh-agent -k) > /dev/null 2>&1
}
trap cleanup EXIT

echo "Starting deployment process..."

# 1. Fetch the latest version from GitHub
VERSION=$(curl -s "$RAW_VERSION_URL")
if [ -z "$VERSION" ]; then
    echo "Error: Failed to fetch version from GitHub."
    exit 1
fi
echo "Fetched version: $VERSION"

# 2. Start the SSH agent and add key
eval $(ssh-agent -s) > /dev/null 2>&1
ssh-add ~/.ssh/aur_nakildias

# 3. Create fresh working directories
mkdir -p "$WORK_DIR"

# 4. Clone the main repository to get the latest PKGBUILD
echo "Cloning main repository..."
git clone "$MAIN_REPO_URL" "$MAIN_DIR"

# 5. Clone the AUR repository
echo "Cloning AUR repository..."
git clone "$AUR_REPO_URL" "$AUR_DIR"

# 6. Copy the updated PKGBUILD from main to AUR
echo "Transferring PKGBUILD..."
cp "$MAIN_DIR/aur/PKGBUILD" "$AUR_DIR/"

# 7. Generate a fresh .SRCINFO (Requires Arch Linux toolchain)
echo "Generating .SRCINFO..."
cd "$AUR_DIR"
makepkg --printsrcinfo > .SRCINFO

# 8. Commit and push the updates directly to AUR
echo "Pushing to AUR..."
git add PKGBUILD .SRCINFO
git commit -m "chore: update version to $VERSION"
git push origin master

echo "Success: AUR package updated to $VERSION."
