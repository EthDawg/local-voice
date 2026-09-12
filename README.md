# Workbench

**Free everyday Mac tools for speaking, explaining and presenting.**

[![CI](https://github.com/EthDawg/local-voice/actions/workflows/ci.yml/badge.svg)](https://github.com/EthDawg/local-voice/actions/workflows/ci.yml)
[![MIT license](https://img.shields.io/badge/license-MIT-mintcream.svg)](LICENSE)

[Contribute](CONTRIBUTING.md) · [Issues](https://github.com/EthDawg/local-voice/issues) · [Discussions](https://github.com/EthDawg/local-voice/discussions) · [Project website](https://workbench-mac.vercel.app)

Workbench brings Voice and StageMark into **one native app, one home window and one menu-bar icon**. Dictate a thought, read a draft, draw over a live demo, or give a connected phone a presentation scene. The aim is a useful baseline that improves with better models and small, dependable workflows.

**This branch contains the Workbench 2.0 consolidation.** Feature descriptions below describe its implementation, not proof of a published release or successful testing on every supported Mac. The [acceptance record](docs/unification.md) tracks the remaining verification. Older Voice/StageMark releases and their validation records describe those separate apps.

## What is in the app?

| Capability | What it does |
| --- | --- |
| **Dictate** | Record speech or import audio; keep original and cleaned text, a dictionary and recent transcripts; copy or optionally paste into the original field. |
| **Read aloud** | Listen with installed Mac voices and export M4A. Speko is an explicit online option using your own key. |
| **Annotate** | Draw, highlight, add shapes/text, emphasise the pointer and use saved boards over a live presentation. |
| **Present a device** | Prepare a scene with a background and logo, display a supported USB video source, and use a break timer. QuickTime and iPhone Mirroring can be opened separately. |
| **Saved resources** | Keep searchable prompts, web links and references to local decks, videos and other files. |
| **Keyboard** | See all Workbench assignments, change or disable them, and practise on a virtual keyboard without activating tools. |

The core app requires no account or subscription. Built-in Parakeet recognition and Mac reading work locally after their initial setup. Optional integrations have their own setup and privacy boundaries.

## First use

1. Open **Workbench Preview** and choose an action from Home. **Models** prepares the default Parakeet recognizer; its first download can take several minutes.
2. Try **Dictate** with a short, disposable sentence. Microphone access is requested when recording needs it. Copy works without Accessibility; automatic paste is an optional setting.
3. Open **Keyboard** to see or practise a shortcut. The defaults include **Control–Option–Space** for dictation, **Control–Option–V** for quick controls and **Control–Option–J** for saved resources.
4. For a mobile demo, choose **Present a device**, prepare a scene and select an available source. Workbench's device view is video-only. iPhone Mirroring runs in Apple's own window; Workbench does not embed or control it.

The menu-bar icon provides quick access while another app is active. The normal window is for editing and setup. Closing it leaves the utility available; **Quit Workbench** stops the app. **Open Workbench at login** is optional in Settings.

During dictation, a draggable panel shows the microphone level, elapsed time and **Finish** / **Cancel**. Processing can be cancelled before the transcript is saved. The result shows **Ready to paste**, a confirmed destination, or **Paste unconfirmed**; review uncertain insertion before pasting again. Pin the receipt if useful. A clipboard cue remains in quick controls until that copied text is replaced. Only Workbench transcript copies are tracked, using clipboard change counts; other clipboard contents are not collected.

During a demo, controls hide after four idle seconds. Reach the top edge or press **⌘/** in the presentation window to reveal them. **Keep controls visible** lasts for that session; **Esc** ends it. These controls may appear in a meeting screen share.

Keyboard recording and practice temporarily suspend Workbench's global shortcuts. Practice counts three full presses and releases; Escape, leaving the window or changing the selected action ends the interaction. Workbench checks its own duplicates, common Mac commands and registration failures; macOS does not expose a complete list of other apps' shortcuts. The virtual keyboard uses ANSI geometry with labels from the current input layout.

## Choose your speech tools

| Choice | Included / setup | Boundary |
| --- | --- | --- |
| **Parakeet on this Mac** | Default English recognizer, using FluidAudio and a downloaded Core ML model | On-device inference; no server or API key. |
| **Local model server** | You run a compatible server and supply its full transcription URL and model ID | Loopback addresses only. Workbench does not install the server or bundle a Whisper model. The server may itself forward audio; inspect its configuration. |
| **Mac voices** | Installed macOS reading voices, with pace control | Local text-to-speech and audio export. |
| **Speko** | Optional personal account and Keychain-stored API key | Explicit readings send text online and may be billed. |

Model settings apply to the next request; the active request keeps its original provider. There is no automatic cloud fallback. A valid local-server configuration is not a successful connectivity or model test—the first real transcription checks those. See [model setup and limits](docs/model-providers.md).

**Apple Shortcuts** can compose `Record Audio → Transcribe with Workbench → a text action`. Apple owns recording; Workbench's App Intent transcribes the supplied audio and returns text. Native discovery requires packaging with full Xcode metadata. See [integration setup and earlier validation](docs/voice-integrations.md). Services, Share extensions and Spotlight actions beyond normal app discovery are future options, not implemented entry points in this consolidation.

## Build and install Preview

Source development requires an Apple Silicon Mac, macOS 14+, Swift 6.2+ and the macOS 26 SDK. Run `bash scripts/doctor.sh` to check prerequisites. Full Xcode is required for distributable Apple Shortcuts metadata. The macOS 14 deployment target is not evidence of testing on every older OS or device.

Quit Workbench, Workbench Preview and legacy Voice/StageMark apps before running the test suite. Its exclusive shortcut-registration checks will conflict with a running copy, including in CI test mode.

From the unified source checkout:

```sh
bash scripts/doctor.sh
bash scripts/test.sh
REQUIRE_APP_INTENTS=1 bash scripts/build.sh --preview
bash scripts/install.sh --archive "dist/Workbench Preview.zip" --no-open
```

The Preview build needs a **Developer ID Application certificate and its private key** in Keychain. If more than one exists, select its fingerprint with `--identity`. It creates `dist/Workbench Preview.zip`; the installer places `Workbench Preview.app` in `~/Applications`. Open it when ready. The install preserves the previous Preview as `dist/Previous-Workbench Preview.zip` for rollback. Quit the running Preview before updating.

Without a signing identity, `bash scripts/build.sh --preview --ad-hoc` creates a disposable development archive. The default installer requires Developer ID signing; ad-hoc packages are for disposable development testing. `bash scripts/build.sh` produces the separate, ad-hoc `dist/Workbench.zip`. Neither command alone establishes notarization or publication.

The installer does **not** run the regression suite or speech round-trip. First-open model preparation and optional live checks are separate:

```sh
"$HOME/Applications/Workbench Preview.app/Contents/MacOS/WorkbenchPreview" --self-test
"$HOME/Applications/Workbench Preview.app/Contents/MacOS/WorkbenchPreview" --transcribe /path/to/audio.m4a
```

The Swift target/module retains its internal `LocalVoice` name for compatibility. Packaged executables are `Workbench` and `WorkbenchPreview`. The self-test synthesizes known text, transcribes it with the selected recognizer, exports audio and transcribes the export; it does not prove live microphone capture, paste or device presentation.

Keep a consistent Preview identity and path between updates. Preview has its own macOS permissions. Quit older Voice/StageMark copies when testing global shortcuts; they may compete for the same combinations. Do not clear permissions or erase saved data as an update step. [Release tooling](scripts/release/README.md) describes the separate production workflow.

## Data, privacy and recovery

- **Transcripts:** originals, drafts, dictionary, reading preferences and the last 100 captures are stored locally. Cleanup is optional: Original, deterministic Light, or guarded Natural editing using Apple Intelligence where available. The original remains available; cleanup checks cannot prove meaning is unchanged.
- **Capture and delivery:** microphone capture is explicitly started and limited to five minutes; imported audio to 30 minutes. Automatic paste checks the original app/field, excludes secure fields and never presses Return. If delivery cannot be confirmed, the transcript stays on the clipboard. Imported originals are not modified.
- **Resources:** the library stores prompts, links, notes and local file references, not copies of media or a password vault. Its JSON import preserves existing entries and skips matching IDs. Exported paths may need reconnecting on another Mac. Unreadable data is preserved rather than overwritten.
- **Models and services:** setup downloads Parakeet from FluidInference's Hugging Face hosting. Recognition uses the selected local engine or user-managed loopback server. Speko sends only explicitly submitted readings online. Downstream Shortcuts actions may sync their results elsewhere.
- **Presentation:** the device preview does not record video or microphone audio. Share its presentation window through your meeting app. QuickTime and iPhone Mirroring have their own requirements, permissions and lifecycle.

Unified Preview stores voice files under `~/Library/Application Support/Workbench Preview/LocalVoice` and presentation files under `~/Library/Application Support/Workbench Preview/StageMark`. The non-Preview equivalents are under `Workbench`. First use copies supported legacy data into a missing component directory; it does not move or delete the old app's data. Once a unified component exists, it is not repeatedly merged with later legacy changes. [Architecture and migration details](docs/design.md) explain the boundaries.

Mac reading is limited to 50,000 characters per reading; Speko to 5,000. The local-server option adds a 64 MB input cap and supports WAV, M4A, MP3 and FLAC subject to that server's decoder. English recognition quality, permissions, hardware support and network-provider behaviour need real workflow testing.

## Contribute and verify

A useful first contribution can be a confusing instruction, an accessibility improvement, a synthetic test case or a hardware report. Use [Issues](https://github.com/EthDawg/local-voice/issues) as the work queue and discuss substantial changes before implementing them. [CONTRIBUTING](CONTRIBUTING.md) explains the workflow and proposed two-maintainer practices.

`bash scripts/test.sh` runs release-tool checks, core/cleanup/history/library/integration/keyboard checks, provider checks and StageKit regressions. Checks use synthetic input; model downloads, real microphone input, other apps' focus, signed-package permissions and actual device sharing require additional evidence. See [the current acceptance record](docs/unification.md), [product contract](docs/workbench.md) and [implementation map](docs/design.md).

## Credits and license

- Voice and [StageMark](https://github.com/EthDawg/StageMark) are the sources of this consolidation; [source provenance](docs/consolidation-source.md) records the import.
- [FluidAudio](https://github.com/FluidInference/FluidAudio), pinned to 0.15.6: Apache 2.0.
- [Parakeet TDT v2 CoreML](https://huggingface.co/FluidInference/parakeet-tdt-0.6b-v2-coreml): see its upstream model card and license.
- Apple AppKit, SwiftUI, AVFoundation and installed macOS voices.
- Workflow inspiration: [Pat Simmons's local Wispr Flow replacement](https://www.youtube.com/watch?v=IMQw3aHjf2Q&t=437s).
- Matt ([@mattywhitenz](https://github.com/mattywhitenz)) proposed Apple Shortcuts dictation and optional Speko reading in [#10](https://github.com/EthDawg/local-voice/issues/10) and [#11](https://github.com/EthDawg/local-voice/issues/11).

The app code is [MIT licensed](LICENSE). Third-party components retain their own licenses. Contribution credit does not imply a GitHub permission level or approval of this branch.
