# Local Voice

A native Mac app for local dictation and text-to-speech. Speak a thought, get editable text, and paste it wherever you work. Or paste text, listen to it, and save an M4A reading.

Built for Apple Silicon, with Parakeet v2 through FluidAudio and the voices installed in macOS. No accounts, API keys, subscriptions, Python environment, or background server.

## Install from source

Requires an Apple Silicon Mac, macOS 14 or later, Xcode Command Line Tools (Swift 6 or later), and an internet connection for the initial dependency/model download. Developed and tested on macOS 26.5.1; older supported OS versions are not yet independently tested.

```sh
git clone https://github.com/EthDawg/local-voice.git
cd local-voice
bash scripts/install.sh
```

The installer builds and locally signs `Local Voice.app`, installs it in `~/Applications`, downloads and prepares the English model, runs a real speech/transcription/export round-trip, then opens the app. The first model preparation can take several minutes. Afterward, it works offline. It does not start automatically at login.

For updates, quit the app, pull the repository, and run the installer again. User drafts and history live outside the app bundle.

## Use it

- **Dictate:** click the microphone, speak, then click Stop. macOS asks for microphone permission the first time.
- **From another app:** press **Control + Option + Space** to start, speak, then press it again. The result is copied; press **Command + V** to paste. A small floating indicator shows recording and transcription.
- **Automatic paste:** optional in Setup. Enable macOS Accessibility for Local Voice, then enable “Paste into the app I started in.” A paste is attempted only if the original app still has focus. Local Voice never presses Return or submits your text. Some apps may reject simulated paste; the transcript stays on the clipboard.
- **Read aloud:** choose an installed voice and pace, enter text, and click Listen. Pause, resume, stop, or save an M4A file.
- **Import audio:** transcribe an audio file up to 30 minutes. Original imported files are never modified.
- **Dictionary:** replace recognised words or phrases with your preferred spelling. Matches whole words, ignoring case. This is a deterministic correction list, not an LLM rewrite.
- **Recent transcripts:** the last 30 completed transcripts stay on this Mac.

Closing the window keeps the app in the menu bar. Use **Quit Local Voice** or Command + Q to exit completely.

## Privacy and limits

Audio is processed locally. Recordings are made only after a button or shortcut starts capture. Recordings are limited to five minutes; text-to-speech is limited to 50,000 characters per reading. Dictation is English. Recognition quality varies with the microphone, background noise, and speaker. There is no cloud fallback.

The model is downloaded from FluidInference on Hugging Face during setup. FluidAudio caches it in the user's Application Support directory. No audio, transcript, clipboard content, or telemetry is uploaded by this app.

Drafts, the dictionary, voice preferences, and recent transcripts are stored in `~/Library/Application Support/LocalVoice/state.json`, readable by the current user. Successful microphone recordings and temporary readings are deleted. Failed microphone recordings remain temporarily available for Retry until the next recording or app exit. The clipboard intentionally retains the most recent copied transcript. Imported audio is not copied into history.

This is a locally signed personal build, not an Apple-notarized distribution. Building on your Mac avoids a separate downloaded-binary installation flow. Code changes can cause macOS to ask for permissions again.

## Development and checks

```sh
bash scripts/test.sh
bash scripts/build.sh
"dist/Local Voice.app/Contents/MacOS/LocalVoice" --self-test
"dist/Local Voice.app/Contents/MacOS/LocalVoice" --transcribe /path/to/audio.m4a
```

The self-test synthesizes a known passage with macOS speech, transcribes it with Parakeet, checks key phrases, exports a non-empty M4A, then transcribes that export. Fourteen core checks cover dictionary boundaries and escaping, state persistence, damaged-state behaviour, and input limits. They run without XCTest or a full Xcode installation. Microphone permission, recording, and UI behaviour also need interactive testing; file round-trips alone do not prove microphone capture.

## Design and credits

See [the implementation notes](docs/design.md) and [validation results](docs/validation.md).

- [FluidAudio](https://github.com/FluidInference/FluidAudio), pinned to 0.15.6: Apache 2.0.
- [Parakeet TDT v2 CoreML](https://huggingface.co/FluidInference/parakeet-tdt-0.6b-v2-coreml): see the upstream model card and license.
- Apple AppKit, SwiftUI, AVFoundation, and installed macOS voices.
- Workflow inspiration: [Pat Simmons's local Wispr Flow replacement](https://www.youtube.com/watch?v=IMQw3aHjf2Q&t=437s).

The app code is MIT licensed. Third-party components retain their own licenses.
