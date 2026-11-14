#!/usr/bin/env bash
# ==============================================================================
# Lively Wallpaper - macOS Disk Image (DMG) Packaging Script
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
BUILD_DIR="${PROJECT_ROOT}/build"
APP_BUNDLE="${BUILD_DIR}/LivelyWallpaper.app"
DMG_NAME="LivelyWallpaper.dmg"
DMG_PATH="${BUILD_DIR}/${DMG_NAME}"
VOL_NAME="Lively Wallpaper"

echo "=========================================================="
echo " Packaging Lively Wallpaper Disk Image (DMG)"
echo " App Bundle:  ${APP_BUNDLE}"
echo " Output DMG:  ${DMG_PATH}"
echo "=========================================================="

# 1. Ensure the .app bundle exists
if [[ ! -d "${APP_BUNDLE}" ]]; then
    echo "==> App bundle not found, building release app first..."
    "${SCRIPT_DIR}/bundle_app.sh" -c release
fi

# 2. Prepare staging directory
STAGING_DIR=$(mktemp -d /tmp/lively_dmg_staging.XXXXXX)
trap 'rm -rf "${STAGING_DIR}"' EXIT

echo "==> Staging files..."
cp -R "${APP_BUNDLE}" "${STAGING_DIR}/"

# 3. Create Applications symlink for drag-and-drop installation
ln -s /Applications "${STAGING_DIR}/Applications"

# 4. Remove any existing DMG
rm -f "${DMG_PATH}"

# 5. Create compressed read-only DMG with hdiutil
echo "==> Creating compressed disk image with hdiutil..."
hdiutil create \
    -volname "${VOL_NAME}" \
    -srcfolder "${STAGING_DIR}" \
    -ov \
    -format UDZO \
    "${DMG_PATH}"

# 6. Verify DMG
if [[ -f "${DMG_PATH}" ]]; then
    DMG_SIZE=$(du -h "${DMG_PATH}" | cut -f1)
    echo "=========================================================="
    echo " Successfully created ${DMG_NAME} (${DMG_SIZE})!"
    echo " Location: ${DMG_PATH}"
    echo "=========================================================="
else
    echo "Error: Failed to create DMG." >&2
    exit 1
fi
