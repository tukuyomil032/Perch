#!/usr/bin/env bash
# build-dmg.sh — Professional DMG installer for Perch using create-dmg
#
# Usage (from repo root):
#   bash scripts/build-dmg.sh <version> <path/to/perch.app> <output_dir>
#
# Dependency: brew install create-dmg

set -euo pipefail

if [[ $# -lt 3 ]]; then
    echo "Usage: $0 <version> <app.app> <output_dir>" >&2
    exit 1
fi

VERSION="$1"
APP_BUNDLE="$2"
OUTPUT_DIR="$3"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

BACKGROUND="${DMG_BACKGROUND:-$REPO_ROOT/assets/dmg/background.png}"
STAGING="$REPO_ROOT/build/dmg-staging"
OUTPUT_DMG="$OUTPUT_DIR/perch-${VERSION}.dmg"

[[ -d "$APP_BUNDLE" ]] || { echo "Error: app bundle not found: $APP_BUNDLE" >&2; exit 1; }
[[ -f "$BACKGROUND" ]] || { echo "Error: background not found: $BACKGROUND" >&2; exit 1; }
command -v create-dmg &>/dev/null || { echo "Error: install with: brew install create-dmg" >&2; exit 1; }

rm -rf "$STAGING"
mkdir -p "$STAGING" "$OUTPUT_DIR"
cp -R "$APP_BUNDLE" "$STAGING/perch.app"
rm -f "$OUTPUT_DMG"

create-dmg \
    --volname "Perch" \
    --background "$BACKGROUND" \
    --window-pos 200 120 \
    --window-size 660 400 \
    --icon-size 128 \
    --icon "perch.app" 180 200 \
    --hide-extension "perch.app" \
    --app-drop-link 480 200 \
    "$OUTPUT_DMG" \
    "$STAGING"

echo "Done: $OUTPUT_DMG"
ls -lh "$OUTPUT_DMG"
