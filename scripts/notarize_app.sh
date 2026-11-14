#!/usr/bin/env bash
# ==============================================================================
# scripts/notarize_app.sh
# Submits the built DMG to Apple's Notary Service and staples the ticket.
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

DMG_PATH="${PROJECT_ROOT}/build/LivelyWallpaper.dmg"
KEYCHAIN_PROFILE=""
APPLE_ID=""
PASSWORD=""
TEAM_ID=""

usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

Options:
  -p, --keychain-profile <name>  Keychain credentials profile stored via notarytool store-credentials
  -u, --apple-id <email>         Apple ID email address (alternative to keychain profile)
  -w, --password <app-pass>      App-specific password (required if --apple-id is used)
  -t, --team-id <team-id>        10-character Apple Developer Team ID
  -d, --dmg <path>               Path to DMG to notarize (default: build/LivelyWallpaper.dmg)
  -h, --help                     Display this help message and exit

Examples:
  # Using stored notarytool credentials profile:
  $(basename "$0") --keychain-profile "AC_PROFILE"

  # Using credentials directly:
  $(basename "$0") --apple-id "dev@example.com" --password "xxxx-xxxx-xxxx-xxxx" --team-id "ABC123XYZ0"
EOF
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -p|--keychain-profile)
            KEYCHAIN_PROFILE="$2"
            shift 2
            ;;
        -u|--apple-id)
            APPLE_ID="$2"
            shift 2
            ;;
        -w|--password)
            PASSWORD="$2"
            shift 2
            ;;
        -t|--team-id)
            TEAM_ID="$2"
            shift 2
            ;;
        -d|--dmg)
            DMG_PATH="$2"
            shift 2
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo "Error: Unknown argument '$1'" >&2
            usage
            ;;
    esac
done

if [[ ! -f "${DMG_PATH}" ]]; then
    echo "Error: DMG file not found at ${DMG_PATH}. Please run scripts/create_dmg.sh first." >&2
    exit 1
fi

echo "=========================================================="
echo " Notarizing Lively Wallpaper DMG with Apple Notary Service"
echo " DMG Target: ${DMG_PATH}"
echo "=========================================================="

if [[ -n "${KEYCHAIN_PROFILE}" ]]; then
    echo "==> Submitting to notarytool using keychain profile '${KEYCHAIN_PROFILE}'..."
    xcrun notarytool submit "${DMG_PATH}" --keychain-profile "${KEYCHAIN_PROFILE}" --wait
elif [[ -n "${APPLE_ID}" && -n "${PASSWORD}" && -n "${TEAM_ID}" ]]; then
    echo "==> Submitting to notarytool using Apple ID credentials..."
    xcrun notarytool submit "${DMG_PATH}" --apple-id "${APPLE_ID}" --password "${PASSWORD}" --team-id "${TEAM_ID}" --wait
else
    echo "Error: Either --keychain-profile or (--apple-id, --password, --team-id) must be specified." >&2
    exit 1
fi

echo "==> Stapling notarization ticket to ${DMG_PATH}..."
xcrun stapler staple "${DMG_PATH}"

echo "==> Validating Gatekeeper assessment..."
spctl -a -t open --context context:primary-signature -v "${DMG_PATH}"

echo "=========================================================="
echo " Successfully Notarized and Stapled LivelyWallpaper.dmg!"
echo " The DMG is now ready for public release on macOS."
echo "=========================================================="
