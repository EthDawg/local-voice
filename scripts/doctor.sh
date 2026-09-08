#!/bin/bash
# Read-only prerequisite check; does not install tools, models, or apps.
set -euo pipefail
fail() { printf 'Setup needed: %s
' "$1" >&2; exit 1; }
[ "$(uname -s)" = Darwin ] || fail "Build and run on macOS. Documentation contributions work on any OS."
[ "$(uname -m)" = arm64 ] || fail "Use an Apple Silicon Mac and a native Terminal (not Rosetta)."
xcode-select -p >/dev/null 2>&1 || fail "Run xcode-select --install, then retry."
command -v swift >/dev/null 2>&1 || fail "Install Apple Command Line Tools with xcode-select --install."
OS_MAJOR="$(sw_vers -productVersion | cut -d. -f1)"
[ "$OS_MAJOR" -ge 14 ] || fail "macOS 14 or later is required."
SDK_VERSION="$(xcrun --sdk macosx --show-sdk-version)"
SWIFT_VERSION="$(swift --version)"
printf '%s
' "$SWIFT_VERSION"
printf 'macOS SDK: %s
' "$SDK_VERSION"
SDK_MAJOR="${SDK_VERSION%%.*}"
[ "$SDK_MAJOR" -ge 26 ] || fail "Select Command Line Tools or Xcode with the macOS 26 SDK."
SWIFT_NUMBER="$(printf '%s
' "$SWIFT_VERSION" | sed -nE 's/.*Swift version ([0-9]+\.[0-9]+).*/\1/p' | head -1)"
SWIFT_MAJOR="${SWIFT_NUMBER%%.*}"
SWIFT_MINOR="${SWIFT_NUMBER#*.}"
[[ "$SWIFT_MAJOR" =~ ^[0-9]+$ && "$SWIFT_MINOR" =~ ^[0-9]+$ ]] || fail "Could not determine Swift version. Run swift --version."
if [ "$SWIFT_MAJOR" -lt 6 ] || { [ "$SWIFT_MAJOR" -eq 6 ] && [ "$SWIFT_MINOR" -lt 2 ]; }; then
  fail "Swift 6.2 or later is required. Select a newer Apple toolchain."
fi
printf 'Ready to build. See CONTRIBUTING.md for the next command.
'
