# Workbench distribution

Workbench is free and MIT licensed. Public downloads and open-source contributions are compatible with Apple Developer ID signing; neither signing nor notarization requires charging for the app or distributing through the Mac App Store.

## The path for users

1. The shared Vercel website (`site/` in this repository) explains the apps and links versioned downloads.
2. GitHub Releases own the app ZIPs, release notes and SHA-256 checksums. No binary copies are hosted on the website.
3. A tester installs one app on an Apple Silicon Mac and follows a short real workflow.
4. The website prepares an observation (“task / expected / observed / environment / impact”) for the relevant repository or the tester's coding agent. GitHub issues remain the only work queue.
5. Contributors fork an app repository, validate a scoped improvement, and open a PR. The maintainer reviews and releases it.

The website is not a browser implementation of microphone capture, accessibility paste, global shortcuts or screen overlays. Those need native-app testing. It does not save feedback or post issues automatically.

## Current channel: early access

As checked on 8 September 2026, Voice 1.2.1 and StageMark 1.2.0 are Apple Silicon builds with a macOS 14 deployment target. The actual QA machine was macOS 26.5.1; older supported OS versions still need independent testing. Voice's first launch downloads/prepares the English speech model. Downloaded binaries do not require developer tools.

Both are ad-hoc signed, not Developer ID signed or Apple-notarized. There was no valid code-signing identity on the release Mac at the time of this check. This is suitable for an explicitly labelled early-testing path, not a claim of frictionless general distribution. Use Apple's app-specific opening guidance; do not recommend disabling Gatekeeper or stripping quarantine flags.

There is no automatic updater. Users quit the app and replace the copy in Applications. Settings/history/boards remain outside the app bundle. Website links pin a version and its checksum so feedback can identify exactly what was tested. A checksum detects changed bytes; it is not a substitute for an identified developer signature or notarization.

## Next release gate: ordinary download and open

The maintainer will obtain or renew Apple Developer Program membership. Keep certificate private keys and notarization credentials out of Git, issues, chat, website files, and release assets. The remaining work is:

- Obtain a **Developer ID Application** identity on the release Mac, or a suitably protected release environment.
- Extend packaging to sign nested code and the app with a secure timestamp and hardened runtime. Check Voice's audio-input entitlement and actual speech/recording/paste behavior under that runtime. Do not use `--deep` as a substitute for correct nested-code signing.
- Submit the archive with Apple's `notarytool` or Xcode, inspect the result/log, staple the accepted ticket to the app, and repackage the stapled app.
- Verify signatures and the ticket. Download through a browser onto a separate Mac or clean account so quarantine and first-run permissions are genuinely exercised. Test Voice model setup, microphone, optional paste, and StageMark drawing/shortcuts; a local rebuild does not prove this experience.
- Publish a new versioned release and checksum, then update website links and remove the early-signing notice only after that downloaded build passes.

Keep the existing bundle identifiers and storage locations so current testers retain their data. Do not buy a domain, create an App Store listing, add accounts, or introduce an updater to solve this initial tester path. Consider a signed updater only when repeated releases make manual replacement a real burden.

## Repeatable release checks

Voice: run `bash scripts/test.sh` and `bash scripts/build.sh` from a clean known source commit. Extract `dist/Workbench Voice.zip` to a temporary directory, verify the app signature and Info.plist version, inspect `arm64`, and run the packaged executable's `--self-test` with synthetic speech. Record the source commit and test coverage. This checks speech/file round trips, not a new Mac's live microphone permission.

StageMark: run the full `zsh scripts/test.zsh` on an interactive Mac with the installed app quit, then `zsh scripts/build.zsh`. Hosted CI's explicit `--ci` mode skips the menu-bar popover test and must not be represented as full UI verification. Confirm the archive version, `arm64` and signature.

Publish the final ZIP and a `SHA256SUMS.txt` containing that ZIP's exact name and hash. Download the public assets back and compare the bytes or digest before changing website links. Do not overwrite a version's binary with a different build. A new app build needs a new version and release.

Website: run `node --test site/tests/*.test.mjs` and `node site/build.mjs`. Check desktop/mobile layout, native installation guidance, versioned links, keyboard trial controls, per-app feedback routing, agent copying, and stale-preview invalidation. Never submit synthetic QA reports as real issues. GitHub integration should preview PRs and deploy `main` from the `site` root. Hosting credentials stay in Vercel.

## Sources checked 8 September 2026

- [Apple: Developer ID distribution](https://developer.apple.com/developer-id/)
- [Apple: notarizing macOS software](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)
- [Apple: custom notarization workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow)
- [Apple: opening apps safely](https://support.apple.com/en-au/102445)
- [Vercel: build and root directory settings](https://vercel.com/docs/builds/configure-a-build)
