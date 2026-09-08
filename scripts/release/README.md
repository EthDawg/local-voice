# Developer ID releases

Run from an interactive release Mac, with the installed copy of the app quit.
Ordinary contributors use the existing build/test scripts and do not need paid
Apple accounts. Python 3 and Apple's command-line tools are required here.

1. Install a Developer ID Application certificate and its private key in Keychain.
2. Save a notarization profile using `xcrun notarytool store-credentials Workbench`.
   Enter credentials at its secure prompts. Never put a password, private key,
   signing export or API key in source control, an issue, or a command argument.
3. Bump the app version/build, review the changes, and commit. Keep the existing
   bundle identifier. Quit the installed app so it releases global shortcuts.
4. Run `security find-identity -v -p codesigning` to find the public fingerprint.
5. Run:

```sh
python3 scripts/release/release.py \
  --identity CERTIFICATE_SHA1_FINGERPRINT \
  --team-id APPLE_TEAM_ID \
  --keychain-profile Workbench
```

The command requires a clean commit, validates credentials and identity, runs
regressions, builds, signs nested code inside-out with hardened runtime and a
timestamp, runs configured checks against the signed executable, submits once,
saves Apple's response/log, staples and verifies the ticket, and assesses
Gatekeeper. It extracts the final ZIP again to verify the exact packaged app.
Outputs are in ignored `.build/releases/VERSION-BUILD/`. Existing release output
directories are never overwritten. `release.json` records the source and digest.

If interrupted, consult `submission.json` and use `notarytool info`, `wait` or
`log` with that ID before retrying. If rejected, fix the reported cause and make a
new candidate. No final ZIP or checksum is emitted before successful acceptance,
stapling and Gatekeeper assessment. The local build script's ad-hoc ZIP is a
development artifact, not the signed release output.

## Native acceptance before publication

- Confirm the packaged version and expected developer identity.
- Download the candidate through a browser on a separate Mac or clean account.
  Verify its checksum, normal Gatekeeper opening, and first-run permissions.
  A shell extraction or synthetic quarantine attribute is not this test.
- Voice: initial model download, live microphone start/stop, transcription,
  clipboard-only mode, optional Accessibility paste into a harmless TextEdit
  document, focus-change protection, reading and audio export, restart/history.
- StageMark: menu controls, global shortcuts, draw/erase/undo, board persistence,
  timer, pointer/click effects, display changes and real screen sharing.
- Publish a new GitHub version with the final ZIP and SHA256SUMS.txt; download
  back and compare the digest. Then update the website's versioned links.

## Mac App Store is a separate distribution target

Developer ID notarization does not create an App Store listing. Store releases
need App Sandbox, a registered App ID, appropriate Mac App Distribution and
Installer Distribution certificates/profiles, an App Store Connect record,
screenshots, privacy/support metadata, upload validation and Apple review.

Voice's current `TextDelivery.swift` reads other apps through Accessibility and
posts paste keystrokes. Apple lists assistive Accessibility APIs as incompatible
with App Sandbox. A store edition needs an explicit copy/manual-paste workflow
or a supported alternative, plus sandbox-safe audio rendering/export and model
storage/download validation. Do not silently remove automatic paste from the
direct-download app.

StageMark is the smaller store candidate, but global pointer/click observation,
hotkeys, cross-display overlays, launch at login and shared Workbench preferences
must be tested in a sandboxed build. Passing non-sandboxed tests does not establish
store compatibility. Apple review remains an external release gate.

Sources: [Apple notarization](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution),
[App Sandbox](https://developer.apple.com/documentation/security/protecting-user-data-with-app-sandbox).
