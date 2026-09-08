# Implementation decisions

The requested outcome is an installed, dependable Mac voice tool. The supplied video demonstrates speech-to-text dictation, while the wording also requests text-to-speech. Both directions are included, with dictation as the main workflow.

## Engine choice

Native SwiftUI/AppKit avoids a web server, browser lifecycle, Python environment, and runtime port conflicts. FluidAudio's pinned 0.15.6 Swift package runs Parakeet TDT v2 through CoreML on Apple Silicon. The English model is downloaded and warmed during installation. Each transcription uses fresh decoder state to avoid carrying words across recordings. Audio-file conversion is handled by FluidAudio, not handwritten WAV parsing.

Apple's built-in recognizer would avoid a third-party model but introduces a separate speech-recognition permission and OS-dependent offline assets. A packaged local Parakeet model gives a more explicit, testable engine. Large Whisper models and cloud APIs were unnecessary for the initial English dictation workflow.

Text-to-speech uses installed macOS voices through `/usr/bin/say`, generating a real audio file, with AVAudioPlayer for playback and `/usr/bin/afconvert` for M4A export. The process receives an argument array and a temporary UTF-8 input file; user text is never interpolated into a shell command. This needs neither a paid API nor another neural-model download. Kokoro is a potential later voice-quality upgrade, not a prerequisite for first use.

## Data and operations

The app owns its state file and temporary recordings. Imported files are read only. Completed transcripts are editable and copied to the clipboard. Optional automatic paste requires Accessibility and checks that the application where capture began still has focus. No Return key is sent. Clipboard delivery is the fallback and default.

Microphone capture is explicitly started and capped at five minutes. Audio-file import is capped at 30 minutes. Very short and effectively silent captures are rejected before recognition. Errors keep the editor available and expose model/transcription retry where applicable. The app does not register a login item or install a daemon.

## Research checked 2026-09-08

- [FluidAudio source, pinned release](https://github.com/FluidInference/FluidAudio/tree/v0.15.6): actual integration API verified against source, because the README used older transcription signatures.
- [FluidAudio ASR guidance](https://github.com/FluidInference/FluidAudio/blob/v0.15.6/Documentation/ASR/GettingStarted.md): English v2 selection and audio conversion approach.
- [FluidVoice](https://github.com/altic-dev/FluidVoice): existing native dictation pattern and permission requirements. No app code copied.
- [Kokoro ONNX](https://github.com/thewh1teagle/kokoro-onnx): feasible local TTS alternative, rejected for the initial app to reduce installation dependencies.

## Upgrade triggers

Add multilingual recognition if English is insufficient. Add Kokoro if built-in voice quality becomes a real limitation. Add selectable shortcuts if users encounter conflicts. Add signed, notarized releases when distributing beyond a personal source build. Add text cleanup only with explicit user controls; dictation should not silently change the meaning of what was said.
