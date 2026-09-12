# Speech models

Workbench has one transcription engine used by the window, global shortcuts and Apple Shortcuts. Settings selects the provider for the next request. Each request retains its original selection until it completes. Recording and processing disable model changes in the UI; the engine also rejects changes during setup or transcription.

| Choice | Model and execution | Setup | Readiness means |
| --- | --- | --- | --- |
| Parakeet | Parakeet TDT v2, English, FluidAudio 0.15.6, on-device Core ML | Download on first preparation; reuse FluidAudio's local model cache | Model loaded and ready for local inference |
| Local model server | Model named by the user, served through an OpenAI-compatible audio transcription endpoint on this Mac | Run and configure the server yourself; enter its full endpoint and exact model ID | Configuration valid; connection and model are checked on the first real transcription |

The default is Parakeet. There is no automatic fallback to another provider or cloud. Workbench does not accept arbitrary downloaded model files: format, tokenizer, runtime and model architecture must be supported by an explicit provider. Models supported by a separately managed server can change without changing Workbench's UI or recording implementation.

## Local-server contract

Use the full URL, for example `http://127.0.0.1:8080/v1/audio/transcriptions`. `whisper-1` is an example model identifier, not a bundled Whisper model. Replace it with the identifier your server exposes. An example of software exposing this API is [Speaches](https://github.com/speaches-ai/speaches); its installation, model availability and hardware requirements belong to that server. This integration does not install a server or promise compatibility with every version.

Workbench sends one `POST` with multipart fields `file`, `model` and `response_format=json`. The server must return JSON containing a non-empty string `text`. The file is named `audio.wav` (or its accepted extension), so the original filename is not disclosed. The UI accepts WAV, M4A, MP3 and FLAC for this provider; actual decoding support is determined by the chosen server. Workbench's microphone recordings are WAV. Unsupported imported formats fail explicitly; convert them or choose Parakeet.

Only exact `127.0.0.1`, `localhost` and IPv6 `::1` hosts are accepted. `localhost` is rewritten to `127.0.0.1` to avoid DNS or hosts-file resolution. HTTPS retains normal certificate validation against the actual numeric address; self-signed or localhost-only certificates may therefore fail. Plain HTTP on the loopback interface is the usual local-server setup. Credentials, URL query strings, fragments, non-HTTP schemes and every redirect are rejected. Sessions have no cookies, stored credentials, disk cache or configured proxies. There is no API-key field: this preview supports local servers that do not require authentication. Do not bind an unauthenticated server to a public network interface.

An audio upload is limited to 64 MB and a response to 2 MB as it arrives. A request has a three-minute deadline, cancellation cancels the URLSession task, and concurrent transcription requests are rejected. Cancellation cannot guarantee a separately running server immediately stops its own inference. Workbench sends only to the local endpoint; the server is user-controlled software and may itself forward requests. Its configuration determines end-to-end privacy.

Saved settings live in the current app's defaults domain, under `workbench.recognition.configuration.v1`. The preview bundle therefore keeps its choice separate from production and the old Voice app. Unreadable settings prevent inference and remain untouched until the user explicitly applies a valid choice. Changing provider releases the unused in-memory Parakeet manager; it preserves the downloaded cache for later reuse.

## Adding another provider

Add an explicit `RecognitionProvider` choice and one dispatch branch in `RecognitionEngine`, including its readiness, availability, cancellation and input contract. Keep microphone capture, text cleanup, history, hotkeys and presentation outside provider implementations. Changes should not alter the public `prepare`, `isReady` or `transcribe` call pattern.

Apple Speech is not offered in this preview. A future on-device provider must check authorization, locale and on-device availability, require on-device recognition for every request, and report unavailable rather than silently using Apple's network recognizer.

The FluidAudio integration is pinned to [0.15.6](https://github.com/FluidInference/FluidAudio/tree/0.15.6); do not assume APIs or model support from its latest README exist in the pinned dependency. URLSession redirect rejection uses Apple's [task delegate](https://developer.apple.com/documentation/foundation/urlsessiontaskdelegate/urlsession(_:task:willperformhttpredirection:newrequest:completionhandler:)).

## Verification

`ProviderChecks.run()` checks endpoint rejection, request format and filename privacy, configuration persistence/isolation, malformed/empty/oversized responses and oversized/unsupported audio. It uses synthetic bytes and an isolated temporary defaults suite. Runtime checks must additionally exercise a loopback server, redirects, cancellation and response-size enforcement. Passing these protocol checks does not establish accuracy or compatibility of a user's chosen real model.
