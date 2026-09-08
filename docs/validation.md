# Validation

Checked on 2026-09-08 on an Apple Silicon Mac with 16 GB RAM, macOS 26.5.1, and Swift 6.3.3 from Xcode Command Line Tools.

| Check | Result |
| --- | --- |
| Release build and local code-signature verification | Pass |
| Fourteen core checks | Pass: word boundaries, case folding, literal regex characters, Unicode, first-run defaults, draft/history/dictionary persistence, private file permissions, damaged-state handling, input limits, and duration formatting |
| AIFF speech → Parakeet transcription | Pass: the known 21-word passage retained the expected phrases |
| M4A export and audio-file readback | Pass: 44.1 kHz AAC, non-empty audio, 5.51-second self-test recording |
| Exported M4A → Parakeet transcription | Pass |
| Offline execution | Pass: complete self-test under a process sandbox denying all network operations, using the prepared model cache |
| Standalone bundle outside build directory | Pass: self-test in `/tmp/LocalVoice-QA.app` |
| Installed bundle | Pass: installer preflight and self-test from `~/Applications/Local Voice.app` |
| Native interface | Pass: visually inspected Dictate and Read aloud screens; controls and empty states render correctly |
| Playback from Read aloud | Pass: started generation, played, and returned to “Finished reading” |
| Live microphone capture | Pass: user-approved microphone test produced the expected short spoken introduction and returned to idle |
| Microphone recording cleanup | Pass: no remaining app microphone recording files after successful transcription |
| Native audio import | Pass: selected an M4A through the Open dialog and received the expected nine-word transcript |
| Native audio export | Pass: saved from the Save Audio dialog; `afinfo` independently confirmed 9.20 seconds of valid 44.1 kHz AAC |
| Session state | Pass: reading text, draft, selected voice, and two recent transcripts written to the private app state file |
| Full quit and relaunch | Pass: installed app reopened with the saved draft and local engine ready |

## Limits of verification

The original release was tested with clipboard delivery. Automatic paste was subsequently enabled and exercised in the Workbench 1.1 follow-up below. No claim is made that paste works in every target application. The global shortcut registered without a conflict; live microphone capture was exercised with the app's microphone control.

Recognition tests cover a clean synthetic English passage and a short live microphone sample. This is not an accent/noise benchmark or a long-recording stress test. Other macOS versions and other hardware were not independently tested.

The upstream CoreML runtime prints a nonfatal shape-inference diagnostic during model loading on this OS. Model preparation, actual inference, and offline self-tests all succeed despite that diagnostic.

## Issues caught before delivery

- Moved dependency resources out of the executable folder so the app bundle passes code-signature verification.
- Replaced XCTest-dependent checks with a self-contained executable check suite; full Xcode is not installed on the target Mac.
- Normalized M4A export to 44.1 kHz / 96 kbps AAC after the original bitrate was rejected for a 22.05 kHz system voice.
- Used the actual pinned FluidAudio API, whose decoder-state signature differs from its README example.

## Workbench Voice 1.1.0 — 8 September 2026

Tested on this Apple Silicon Mac running macOS 26.5.1. The installed signed binary matches the executable inside `dist/Workbench Voice.zip`; the build-directory binary differs because app signing changes its signature. The shared Workbench source is byte-identical in Voice and StageMark.

- 14 core checks and 16 cleanup checks pass, including the false start/train-time/grocery-list example, other explicit corrections, retained negation, rejected invented/swapped times, quantities, compound list items, ordinary prose, and old state decoding.
- Native input checks pass: exclusive Carbon registration, conflict reporting, repeat suppression, key-up after modifiers are released, and registration cleanup. The UI shortcut editor changed the shortcut and restored the default. Toggle/hold settings were exercised. Releasing a hold while permission is pending cancels the attempt instead of leaving capture armed.
- The real optional Apple language model was exercised. The checked example used the Light fallback because the generated candidate did not meet the fidelity checks. Natural mode is optional; Light is the default.
- The installed editor transformed the supplied example into the final 7pm sentence and three grocery bullets. Its Original sheet showed the full unedited input. Cleaned draft and original survived app updates/relaunch.
- Existing transcript history, dictionary, and reading text were compared with a pre-test snapshot and remained unchanged. The example is left in the editor. Storage and bundle identifiers remain stable.
- Native menu layout, editor, shared Dark appearance, and return to the Mac’s System appearance were visually checked. An initial popover inheritance issue was fixed with an explicit SwiftUI theme modifier.
- StageMark-to-Voice navigation was exercised. Voice’s clipboard fallback was verified in a new TextEdit document: the complete cleaned result was available for manual paste.
- Spotlight metadata resolves exactly the two canonical installed apps, named Workbench Voice and Workbench StageMark. Both declare the Utilities category. This proves index discovery; a screenshot of Spotlight results was not obtained.
- Automatic insertion and clipboard restoration passed the follow-up below after the user-approved Accessibility repair. The installed app is left with Paste automatically, clipboard restoration, Light cleanup, and Toggle activation enabled.

The native speech round-trip and M4A re-transcription pass on the installed build. CoreML still prints the upstream E5RT shape diagnostic during loading, without preventing successful inference. No cloud account or server is required.

Follow-up UI verification: Voice opened StageMark from the shared switcher. With both apps running, choosing Dark in StageMark immediately updated Voice; choosing System in Voice updated StageMark. The initial temporary TextEdit document was saved locally, checked against the exact test transcript, and moved to Trash; the temporary file and its provisional iCloud document no longer exist.

### Accessibility and delivery follow-up

System Settings initially showed Workbench Voice enabled while the installed app's trust check still failed. Relaunching and adding the same app without removing the old entry did not fix it. With explicit user approval, removing only the stale Voice entry and re-adding the exact installed app changed Voice's status to **Automatic paste ready**. The installed app uses an ad-hoc signature whose designated requirement is tied to its code hash; README now includes recovery instructions for local updates.

The real **Paste last transcript** action then confirmed insertion with **Pasted into ChatGPT.** This status requires a changed Accessibility field value containing the complete transcript. The automation operated TextEdit in the background, so the actual destination was the foreground Codex app, reported by macOS as ChatGPT. No Return/send action was issued. The user was informed that the test sample might remain in that message draft; the UI tools cannot edit Codex itself.

Clipboard restoration was independently checked through TextEdit: copying `WORKBENCH_CLIPBOARD_CHECK` before delivery and manually pasting afterward produced that exact sentinel, rather than the transcript. The local scratch document was saved, closed, verified to contain only that sentinel, and moved to Trash. The earlier denied-permission and changed-focus attempts retained a copied transcript without insertion. These checks cover the production delivery path shared by dictation and Paste last transcript; they do not constitute a new microphone-to-paste recording test or a matrix of target apps.
