#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"
if pgrep -x LocalVoice >/dev/null; then
    echo "Quit Workbench Voice before installing an update, then run this installer again." >&2
    exit 1
fi
bash scripts/build.sh
APP_DEST="$HOME/Applications/Workbench Voice.app"
mkdir -p "$HOME/Applications"
INSTALL_STAGE="$(mktemp -d "$PROJECT_DIR/.build/install.XXXXXX")"
trap 'rm -rf -- "$INSTALL_STAGE"' EXIT
ditto -x -k "$PROJECT_DIR/dist/Workbench Voice.zip" "$INSTALL_STAGE"
STAGED_APP="$INSTALL_STAGE/Workbench Voice.app"
codesign --verify --deep --strict "$STAGED_APP"
"$STAGED_APP/Contents/MacOS/LocalVoice" --prepare-model
"$STAGED_APP/Contents/MacOS/LocalVoice" --check-core
"$STAGED_APP/Contents/MacOS/LocalVoice" --self-test
# Preserve the last installed version for rollback without duplicate Spotlight apps.
for old in "$APP_DEST" "$HOME/Applications/Local Voice.app"; do
    if [ -d "$old" ]; then
        ditto -c -k --sequesterRsrc --keepParent "$old" "$PROJECT_DIR/dist/Previous-$(basename "$old").zip"
        rm -rf -- "$old"
    fi
done
mv "$STAGED_APP" "$APP_DEST"
codesign --verify --deep --strict "$APP_DEST"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP_DEST"
if [ "${LOCALVOICE_NO_OPEN:-0}" != "1" ]; then open "$APP_DEST"; fi
echo "Installed: $APP_DEST"
