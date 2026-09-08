#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"
bash scripts/build.sh
APP_DEST="$HOME/Applications/Local Voice.app"
mkdir -p "$HOME/Applications"
if pgrep -x LocalVoice >/dev/null; then
    echo "Quit Local Voice before installing an update, then run this installer again." >&2
    exit 1
fi
ditto "$PROJECT_DIR/dist/Local Voice.app" "$APP_DEST"
codesign --verify --deep --strict "$APP_DEST"
echo "Preparing the speech model. The first download can take a few minutes."
"$APP_DEST/Contents/MacOS/LocalVoice" --prepare-model
echo "Checking actual speech generation, transcription, and export."
"$APP_DEST/Contents/MacOS/LocalVoice" --self-test
if [ "${LOCALVOICE_NO_OPEN:-0}" != "1" ]; then open "$APP_DEST"; fi
echo "Installed: $APP_DEST"
