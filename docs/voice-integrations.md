# Apple Shortcuts and optional Speko reading

Matt ([@mattywhitenz](https://github.com/mattywhitenz)) proposed these two focused contributions in [#10](https://github.com/EthDawg/local-voice/issues/10) and [#11](https://github.com/EthDawg/local-voice/issues/11). Implementation is maintained here; credit is for the proposals, not unsubmitted code.

## Dictate into your own workflow

In Apple Shortcuts, add **Dictate with Workbench**, followed by **Create Note**, **Copy to Clipboard**, or another action that accepts text. Run it, speak, and choose **Finish** in Voice’s visible capture panel. The next action receives that recording’s transcript. Downstream apps control what they do with the text and whether they sync it online.

Set up Voice’s local speech model first. The action uses the existing microphone permission, local recognition, cleanup preferences, dictionary and history. It never automatically copies, pastes or submits. Concurrent work is rejected; cancellation, permission failures and shutdown return an error, never an earlier draft. Keyboard shortcuts and Apple Shortcuts are separate features.

The App Intent requires Apple-generated package metadata. A full Xcode toolchain is needed to package it; Command Line Tools can compile and test the implementation but cannot make the action discoverable. `REQUIRE_APP_INTENTS=1 bash scripts/build.sh` fails if metadata cannot be created. CI uses this gate and saves the resulting package. Do not call a CLT-only package Shortcuts-ready.

## Choose a reading voice

Mac voices remain the default, offline and account-free. In **Read aloud**, choosing **Speko · online** shows what leaves the Mac and lets you save/remove your personal API key in this edition’s macOS Keychain. The key is not stored in app JSON, preferences, logs, exports or the repository. Preview and production keys are separate.

Only text explicitly submitted for a Speko reading goes to `https://router.speko.dev/v1/tts/speech`, then its selected voice provider. Speko may bill accepted text even if you cancel. Dictation and cleanup do not gain any cloud fallback. Removing the key returns reading to Mac voices. The first scope uses automatic, balanced routing and the route’s default voice, with 5,000 characters per request; provider-specific voice IDs and pace controls are intentionally absent for Speko. Mac voices retain their existing pace and 50,000-character limit.

Requests have unique idempotency keys, no automatic retries, bounded duration/response size, no cookies/cache, and no redirects. Error bodies are not shown or logged. Raw mono PCM at 24 kHz is wrapped in WAV for the existing player and M4A export. A repeated Listen/Save of unchanged rendered text reuses the temporary audio; removing/replacing the key invalidates it.

## Research and scope decision — 9 September 2026

- [Apple App Intents](https://developer.apple.com/documentation/appintents/creating-your-first-app-intent): native actions provide typed results to Shortcuts. A URL that merely opens Voice cannot provide an invocation-owned transcript.
- [Speko speech API](https://docs.speko.ai/relay/tts/speech): the one-shot endpoint supports raw PCM, automatic routing and a default voice. A small native HTTPS client fits the existing playback workflow.
- [Speko Gateway](https://github.com/SpekoAI/gateway): MIT, early preview, customer-side voice-agent runtime with streaming integrations. Embedding its runtime would add unnecessary processes and dependencies for one optional reading provider. No gateway code or telemetry is included.

## Validation

`bash scripts/test.sh` includes synthetic request ownership, duplicate/stale completion, cancellation/error, HTTP contract, invalid input/audio and PCM-to-M4A checks. These use no real key or private text. CI additionally requires extracted Shortcuts metadata.

Before promoting downloads, record installed action discovery, live Shortcuts → dictation → text output, cancellation and ordinary dictation regression. A real Speko request needs a user-configured key and agreed synthetic text; mocks and successful compilation do not establish provider playback, billing or production reliability. See the accompanying PR/release for current verification status.
