#!/usr/bin/env bash
# ==============================================================================
# scripts/bundle_app.sh
# Builds the SPM executable and packages it into a standalone LivelyWallpaper.app
# ==============================================================================
set -euo pipefail

# 1. Resolve Project Root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# 2. Defaults
CONFIGURATION="release"
OUTPUT_DIR="${PROJECT_ROOT}/build"
APP_NAME="LivelyWallpaper.app"
SKIP_BUILD=false
VERBOSE=false

# 3. Help Text
usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

Options:
  -c, --configuration <debug|release>  Build configuration (default: release)
  -o, --output <path>                  Output directory for .app bundle (default: ./build)
  -s, --skip-build                     Skip swift build and package existing binary
  -v, --verbose                        Enable verbose output
  -h, --help                           Display this help message and exit

Examples:
  $(basename "$0") -c release
  $(basename "$0") -c debug -o ~/Applications
EOF
    exit 0
}

# 4. Parse Arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        -c|--configuration)
            CONFIGURATION="$2"
            shift 2
            ;;
        -o|--output)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        -s|--skip-build)
            SKIP_BUILD=true
            shift 1
            ;;
        -v|--verbose)
            VERBOSE=true
            shift 1
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

if [[ "$CONFIGURATION" != "release" && "$CONFIGURATION" != "debug" ]]; then
    echo "Error: Configuration must be 'release' or 'debug', got '$CONFIGURATION'" >&2
    exit 1
fi

echo "=========================================================="
echo " Packaging Lively Wallpaper for macOS"
echo " Configuration: ${CONFIGURATION}"
echo " Project Root:  ${PROJECT_ROOT}"
echo " Output Dir:    ${OUTPUT_DIR}"
echo "=========================================================="

# 5. Compile via Swift Package Manager
if [[ "$SKIP_BUILD" = false ]]; then
    echo "==> Building WallpaperApp (${CONFIGURATION})..."
    BUILD_FLAGS=("-c" "${CONFIGURATION}" "--package-path" "${PROJECT_ROOT}")
    if [[ "$VERBOSE" = true ]]; then
        swift build "${BUILD_FLAGS[@]}"
    else
        swift build "${BUILD_FLAGS[@]}" > /dev/null
    fi
else
    echo "==> Skipping build as requested (--skip-build)..."
fi

# 6. Locate Executable Binary
BIN_DIR="$(swift build -c "${CONFIGURATION}" --package-path "${PROJECT_ROOT}" --show-bin-path)"
EXECUTABLE_SOURCE="${BIN_DIR}/WallpaperApp"

if [[ ! -f "${EXECUTABLE_SOURCE}" ]]; then
    echo "Error: Compiled executable not found at ${EXECUTABLE_SOURCE}" >&2
    exit 1
fi

# 7. Create App Bundle Directory Structure
APP_BUNDLE="${OUTPUT_DIR}/${APP_NAME}"
CONTENTS_DIR="${APP_BUNDLE}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"

echo "==> Assembling bundle at ${APP_BUNDLE}..."
rm -rf "${APP_BUNDLE}"
mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}"

# 8. Copy Binary and Set Permissions
cp "${EXECUTABLE_SOURCE}" "${MACOS_DIR}/WallpaperApp"
chmod +x "${MACOS_DIR}/WallpaperApp"

# 9. Copy and Validate Info.plist
PLIST_SOURCE="${PROJECT_ROOT}/Resources/Info.plist"
if [[ -f "${PLIST_SOURCE}" ]]; then
    cp "${PLIST_SOURCE}" "${CONTENTS_DIR}/Info.plist"
    plutil -lint "${CONTENTS_DIR}/Info.plist" > /dev/null
else
    echo "Error: Missing Info.plist at ${PLIST_SOURCE}" >&2
    exit 1
fi

# 10. Write PkgInfo (Standard macOS bundle marker)
echo -n "APPL????" > "${CONTENTS_DIR}/PkgInfo"

# 11. Copy Resources and Sample Assets
if [[ -d "${PROJECT_ROOT}/Resources/Samples" ]]; then
    echo "==> Copying sample test assets..."
    cp -R "${PROJECT_ROOT}/Resources/Samples" "${RESOURCES_DIR}/"
fi

# Copy any additional resource files excluding Info.plist
for item in "${PROJECT_ROOT}/Resources"/*; do
    if [[ -e "$item" ]]; then
        filename="$(basename "$item")"
        if [[ "$filename" != "Info.plist" && "$filename" != "Samples" ]]; then
            cp -R "$item" "${RESOURCES_DIR}/"
        fi
    fi
done

# 12. Ad-Hoc Code Signing (Satisfies arm64 macOS gatekeeper requirements)
echo "==> Applying ad-hoc code signature..."
codesign --force --deep --sign - "${APP_BUNDLE}"

# 13. Verify Bundle Integrity
echo "==> Verifying signature and bundle validity..."
codesign --verify --verbose "${APP_BUNDLE}" 2>&1 | while read -r line; do
    echo "    $line"
done

echo "=========================================================="
echo " Successfully created ${APP_NAME}!"
echo " Location: ${APP_BUNDLE}"
echo " Binary:   ${MACOS_DIR}/WallpaperApp ($(du -h "${MACOS_DIR}/WallpaperApp" | awk '{print $1}'))"
echo " Launch command: open \"${APP_BUNDLE}\""
echo "=========================================================="
