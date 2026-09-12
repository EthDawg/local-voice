#!/bin/bash
# Extract native action metadata before signing. CLT-only builds stay useful for
# development; release/CI packages must have real Apple-generated metadata.
set -euo pipefail
APP_DIR="$1"
if ! PROCESSOR="$(xcrun --find appintentsmetadataprocessor 2>/dev/null)"; then
    if [ "${REQUIRE_APP_INTENTS:-0}" = 1 ]; then
        echo 'Full Xcode is required to package Apple Shortcuts actions.' >&2
        exit 1
    fi
    echo 'Development build: Apple Shortcuts metadata unavailable with Command Line Tools.' >&2
    exit 0
fi
SDK="$(xcrun --sdk macosx --show-sdk-path)"
TOOLCHAIN="$(dirname "$(dirname "$(dirname "$(xcrun --find swiftc)")")")"
XCODE_VERSION="$(xcodebuild -version | awk '/Build version/ {print $3}')"
printf '%s\n' "$PWD/Sources/LocalVoice/Shortcuts.swift" > "$PWD/.build/intent-sources.txt"
printf '%s\n' "$VOICE_INTENT_VALUES" > "$PWD/.build/intent-values.txt"
"$PROCESSOR" --module-name LocalVoice --platform-family macOS \
    --deployment-target 14.0 --target-triple "$(uname -m)-apple-macos14.0" \
    --sdk-root "$SDK" --toolchain-dir "$TOOLCHAIN" --xcode-version "$XCODE_VERSION" \
    --output "$APP_DIR/Contents/Resources" \
    --source-file-list "$PWD/.build/intent-sources.txt" \
    --swift-const-vals-list "$PWD/.build/intent-values.txt"
test -s "$APP_DIR/Contents/Resources/Metadata.appintents/extract.actionsdata"
python3 - "$APP_DIR/Contents/Resources/Metadata.appintents/extract.actionsdata" <<'PYMETA'
import json, sys
metadata = json.load(open(sys.argv[1]))
action = metadata['actions']['TranscribeWithWorkbench']
assert action['isDiscoverable'] and not action['openAppWhenRun']
assert action['fullyQualifiedTypeName'] == 'LocalVoice.TranscribeWithWorkbench'
assert len(action['parameters']) == 1
assert action.get('outputType'), 'Dictation must return an action result'
print('Verified native Transcribe with Workbench action metadata')
PYMETA
