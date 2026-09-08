#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"
swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"
APP_DIR="$PROJECT_DIR/dist/Local Voice.app"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
rm -rf "$APP_DIR/Contents/MacOS/FluidAudio_FluidAudio.bundle"
cp "$BIN_DIR/LocalVoice" "$APP_DIR/Contents/MacOS/LocalVoice"
for bundle in "$BIN_DIR"/*.bundle; do
    [ -e "$bundle" ] || continue
    ditto "$bundle" "$APP_DIR/Contents/Resources/$(basename "$bundle")"
    # These resources belong to FluidAudio's unused LuxTTS module. ASR has no bundle-resource lookup.
done
cp "$PROJECT_DIR/scripts/Info.plist" "$APP_DIR/Contents/Info.plist"
if [ -f "$PROJECT_DIR/scripts/AppIcon.icns" ]; then cp "$PROJECT_DIR/scripts/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"; fi
codesign --force --deep --sign - "$APP_DIR"
codesign --verify --deep --strict "$APP_DIR"
echo "Built: $APP_DIR"
