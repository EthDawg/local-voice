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

Automatic paste into other applications remains optional and was not enabled or tested, because it requires additional Accessibility access. The global shortcut registered without a conflict; capture was exercised with the app's microphone control. No claim is made that simulated paste works in every target application. Clipboard delivery remains the default.

Recognition tests cover a clean synthetic English passage and a short live microphone sample. This is not an accent/noise benchmark or a long-recording stress test. Other macOS versions and other hardware were not independently tested.

The upstream CoreML runtime prints a nonfatal shape-inference diagnostic during model loading on this OS. Model preparation, actual inference, and offline self-tests all succeed despite that diagnostic.

## Issues caught before delivery

- Moved dependency resources out of the executable folder so the app bundle passes code-signature verification.
- Replaced XCTest-dependent checks with a self-contained executable check suite; full Xcode is not installed on the target Mac.
- Normalized M4A export to 44.1 kHz / 96 kbps AAC after the original bitrate was rejected for a 22.05 kHz system voice.
- Used the actual pinned FluidAudio API, whose decoder-state signature differs from its README example.
