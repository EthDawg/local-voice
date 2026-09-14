#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"
# Repeated local installs update Preview; production requires a notarized archive.
if [ "${1:-}" = "--preview" ]; then shift; fi
exec python3 scripts/release/preview.py install "$@"
