#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"
PYTHONDONTWRITEBYTECODE=1 python3 scripts/release/test_release.py
PYTHONDONTWRITEBYTECODE=1 python3 scripts/release/test_preview.py
PYTHONDONTWRITEBYTECODE=1 python3 scripts/test-clean-draft.py
swift build -c release --disable-sandbox
BIN_DIR="$(swift build -c release --disable-sandbox --show-bin-path)"
"$BIN_DIR/LocalVoice" --check-core

"$BIN_DIR/LocalVoice" --check-providers
"$BIN_DIR/LocalVoice" --check-refinement
bash scripts/test-stage.sh --ci
