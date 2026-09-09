# Dictation in Apple Shortcuts

Matt ([@mattywhitenz](https://github.com/mattywhitenz)) proposed a focused native dictation action in [#10](https://github.com/EthDawg/local-voice/issues/10). This implementation credits his proposal; no contributor code has been submitted or attributed.

## Your workflow

With a verified package, add **Dictate with Workbench** in Apple Shortcuts, followed by **Create Note**, **Copy to Clipboard**, or another action that accepts text. Run it, speak, and choose **Finish** in Voice’s visible capture panel. The next action receives that recording’s transcript. Downstream apps control what they do with the text and whether they sync online.

Set up Voice’s local speech model first. The action uses the existing microphone permission, local recognition, cleanup preferences, dictionary and history. It never automatically copies, pastes or submits. Concurrent work is rejected; cancellation, permission failures and shutdown return an error, never an earlier draft. Keyboard shortcuts and Apple Shortcuts are separate features.

## Build and validation status

The implementation compiles with the existing Command Line Tools. Request ownership checks cover concurrent calls, incorrect IDs, duplicate completion, cancellation, late callbacks and errors. The existing regression suite passes.

Apple Shortcuts discovery requires metadata extracted by full Xcode. `REQUIRE_APP_INTENTS=1 bash scripts/build.sh` refuses to package without it. A Command Line Tools build explicitly reports this limitation in Voice’s Shortcuts page. Installed action discovery and a live Shortcuts → dictation → text output workflow must pass before this feature is promoted as a supported download.

CI packaging/extraction is being checked in the PR. Adding a downloadable CI artifact also needs a workflow update; the current command-line GitHub authorization lacks the workflow scope. No signing credentials are sent to CI.

## Speko is a separate experiment

Matt also proposed [optional Speko reading (#11)](https://github.com/EthDawg/local-voice/issues/11). [Speko](https://speko.ai/) is a hosted router for online voice providers, not the installed Mac voices Voice already uses. It requires a personal account/API key, sends selected text to Speko and a provider, and can incur usage charges.

A prototype was implemented and 28 synthetic integration checks passed, including its PCM-to-M4A path. It is preserved on the separate `experiment/speko-reading` branch and excluded from the Shortcuts candidate. It has not been tested with a real key or released. First establish the user benefit (such as a specific higher-quality voice) before asking anyone to open an account or introducing a network provider into the public app.

The prototype uses a fixed HTTPS endpoint, explicit opt-in, Keychain, bounded requests, no automatic retries, no redirects, and cancellation. It adds no cloud dictation. Mac voices remain the default. Prototype code is not a product or privacy-policy commitment.

## Research — 9 September 2026

[Apple’s App Intents documentation](https://developer.apple.com/documentation/appintents/creating-your-first-app-intent) supports typed action results. Merely opening Voice from a keyboard shortcut or URL does not return a recording to the next action.

[Speko’s speech API](https://docs.speko.ai/relay/tts/speech) provides automatic routing and raw PCM for one-shot speech. A native HTTPS client is sufficient if this option is later adopted. Its [MIT-licensed Gateway](https://github.com/SpekoAI/gateway) is an early-preview voice-agent runtime; embedding that runtime would be disproportionate for one optional reading feature. No gateway code or telemetry has been copied.
