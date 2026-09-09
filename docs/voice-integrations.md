# Shortcuts dictation and optional Speko reading

Matt ([@mattywhitenz](https://github.com/mattywhitenz)) proposed these workflows in [#10](https://github.com/EthDawg/local-voice/issues/10) and [#11](https://github.com/EthDawg/local-voice/issues/11). Credit is for the proposals; no unsubmitted contributor code has been attributed.

## Dictate into Notes or another app

Create a shortcut with three actions:

1. **Record Audio** (Apple’s built-in action).
2. **Transcribe with Workbench**, taking the recorded audio.
3. **Create Note**, **Copy to Clipboard**, or another action accepting text.

Run the saved shortcut, speak, and stop the recording in Shortcuts. Voice uses its existing local recognition, cleanup preferences, dictionary and history, returning only that invocation’s transcript. It does not copy, paste or submit. You can also supply an existing audio file up to 30 minutes long. Set up Voice’s speech model first; busy/missing-model/invalid-audio cases report errors.

Apple owns the microphone and its cancellation controls in this workflow. Workbench’s action never opens a microphone. Subsequent actions control the text’s destination, including any online syncing. Voice’s existing keyboard dictation remains independent.

**Why this composition:** native testing on macOS 26.5.1 confirmed the prototype’s direct recording action could return live text, but Shortcuts’ Stop did not reliably cancel an app-owned microphone capture, even with task/progress cancellation handlers. The shipped design reuses Apple’s Record Audio lifecycle. The direct recording action was removed; it is not a hidden microphone fallback. Cancellation during local processing may finish the current recognition work; it cannot keep recording audio.

## Optional Speko reading

Mac voices remain the default, offline and account-free. Choosing **Read aloud → Speko · online** explicitly enables online readings. Create a personal account at [Speko](https://platform.speko.ai), choose **Gateway + Router** during onboarding, create an API key and save it in Voice’s secure field. No gateway worker is needed.

Only text you explicitly submit for a Speko reading goes to its Router and selected voice provider. Accepted text may be billed, including cancelled requests. Dictation/cleanup gain no cloud fallback. Keys are kept in this edition’s macOS Keychain, separate between Preview and production; never in app JSON, logs or the repository. Removing a key returns reading to Mac voices.

The initial scope uses automatic balanced routing and the route’s default voice, with 5,000 characters per request. Provider-specific voices and pace controls are absent for Speko; Mac voices retain pace and a 50,000-character limit. Requests have bounded duration/response size, unique idempotency keys, no automatic retry, no cookies/cache and no redirects. Error bodies are not displayed/logged. Raw mono 24 kHz PCM is wrapped in WAV for playback and M4A export. Listen/Save reuse unchanged generated audio; key replacement/removal invalidates it.

## Build and validation

Full Xcode extracts real action metadata. Command Line Tools can compile/test source, but their packages explicitly disclose that native discovery is unavailable. `REQUIRE_APP_INTENTS=1 bash scripts/build.sh` fails without Apple’s processor. The app target alone emits constant values; packaging verifies the generated action identifier, input and output. CI applies the same gate and retains the tested package.

On 9 September 2026, Xcode 26.6 (17F113) generated native metadata and the Developer ID-signed Preview updated in place without deleting data or resetting permissions. The regression suite includes 28 synthetic invocation/API/audio checks. The user entered their key directly in Preview and authorised one sentence: “Your table is ready.” Speko playback completed, M4A export reused cached audio, and local recognition confirmed that sentence. No private text or key was retrieved. Record Audio composition testing is recorded in the release/PR when complete.

## Research

[Apple App Intents](https://developer.apple.com/documentation/appintents/creating-your-first-app-intent) supplies typed results to Shortcuts. A keyboard shortcut or URL that merely opens Voice cannot do that. Recording is delegated to Apple’s existing action after native cancellation testing exposed the lifecycle gap described above.

[Speko’s speech API](https://docs.speko.ai/relay/tts/speech) supports one-shot raw PCM with automatic routing. A small HTTPS client fits this reading feature. Its [MIT-licensed Gateway](https://github.com/SpekoAI/gateway) is an early-preview runtime for voice agents; no gateway code, telemetry, additional runtime or generic provider framework is bundled.
