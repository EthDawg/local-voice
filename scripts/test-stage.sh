#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/stage-module-cache
swiftc -swift-version 5 -module-name WorkbenchStageTests -module-cache-path .build/stage-module-cache -framework Carbon Sources/StageKit/*.swift Tests/StageKitLegacy/*.swift -o .build/WorkbenchStageTests
WORKBENCH_TEST_LOG="$(mktemp)"
trap 'rm -f -- "$WORKBENCH_TEST_LOG"' EXIT
.build/WorkbenchStageTests "$@" | tee "$WORKBENCH_TEST_LOG"
/usr/bin/grep -Eq '^[0-9]+ tests · [0-9]+ assertions · 0 failures$' "$WORKBENCH_TEST_LOG"
