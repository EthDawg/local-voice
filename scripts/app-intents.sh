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
TOOLCHAIN="$(dirname "$(dirname "$(xcrun --find swiftc)")")"
"$PROCESSOR" --module-name LocalVoice --platform-family macOS \
    --deployment-target 14.0 --target-triple "$(uname -m)-apple-macos14.0" \
    --sdk-root "$SDK" --toolchain-dir "$TOOLCHAIN" \
    --binary-file "$APP_DIR/Contents/MacOS/LocalVoice" \
    --output "$APP_DIR/Contents/Resources" \
    --source-files "$PWD/Sources/LocalVoice/Shortcuts.swift"
test -s "$APP_DIR/Contents/Resources/Metadata.appintents/extract.actionsdata"
