#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

# UI tests use a fresh app-owned temporary library, never the user's library.
# Supply MOBILE_SIMULATOR_UDID to select an already configured iPhone or iPad.
if [[ -z "${MOBILE_SIMULATOR_UDID:-}" ]]; then
  MOBILE_SIMULATOR_UDID="$(xcrun simctl list devices available -j | MOBILE_DEVICE_FAMILY="${MOBILE_DEVICE_FAMILY:-iPhone}" python3 -c '
import json,os,sys
devices=json.load(sys.stdin)["devices"]
family=os.environ["MOBILE_DEVICE_FAMILY"]
if family not in ["iPhone", "iPad"]: sys.exit("MOBILE_DEVICE_FAMILY must be iPhone or iPad.")
choices=[d["udid"] for runtime,items in devices.items() if "iOS-26" in runtime for d in items if d.get("isAvailable") and d["name"].startswith(family)]
if not choices: sys.exit("Install an iOS 26 simulator runtime in Xcode Settings > Components.")
print(choices[0])')"
fi

test_dir="${MOBILE_TEST_OUTPUT:-$(mktemp -d /private/tmp/workbench-mobile-tests.XXXXXX)}"
mkdir -p "$test_dir"
python3 scripts/mobile-project.py
xcodebuild -project Mobile/Workbench.xcodeproj -scheme WorkbenchMobile \
  -configuration Debug -destination "platform=iOS Simulator,id=$MOBILE_SIMULATOR_UDID" \
  -derivedDataPath "$test_dir/DerivedData" -resultBundlePath "$test_dir/Results.xcresult" \
  -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO test
printf 'Native test evidence: %s\n' "$test_dir/Results.xcresult"
