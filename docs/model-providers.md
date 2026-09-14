# Speech models

Workbench has one transcription engine used by the window, global shortcuts and Apple Shortcuts. Settings selects the provider for the next request. Each request retains its original selection until it completes. Recording and processing disable model changes in the UI; the engine also rejects changes during setup or transcription.

| Choice | Model and execution | Setup | Readiness means |
| --- | --- | --- | --- |
| Parakeet | Parakeet TDT v2, English, FluidAudio 0.15.6, on-device Core ML | Download on first preparation; reuse FluidAudio's local model cache | Model loaded and ready for local inference |
| Local model server | Model requested from a transcription server on this Mac; routing depends on that server | Run and configure the server yourself; enter its full endpoint and model ID | Configuration valid; connection and response are checked on the first real transcription, not the server's actual model identity |

The default is Parakeet. There is no automatic fallback to another provider or cloud. Workbench does not accept arbitrary downloaded model files: format, tokenizer, runtime and model architecture must be supported by an explicit provider. Models supported by a separately managed server can change without changing Workbench's UI or recording implementation.

## Local-server contract

Use the full URL, for example `http://127.0.0.1:8080/v1/audio/transcriptions`. `whisper-1` is an example model identifier, not a bundled Whisper model. Replace it with the identifier your server exposes. An example of software exposing this API is [Speaches](https://github.com/speaches-ai/speaches); its installation, model availability and hardware requirements belong to that server. This integration does not install a server or promise compatibility with every version.

Workbench sends one `POST` with multipart fields `file`, `model` and `response_format=json`. The server must return JSON containing a non-empty string `text`. The file is named `audio.wav` (or its accepted extension), so the original filename is not disclosed. The UI accepts WAV, M4A, MP3 and FLAC for this provider; actual decoding support is determined by the chosen server. Workbench's microphone recordings are WAV. Unsupported imported formats fail explicitly; convert them or choose Parakeet.

Some servers choose a model from the request; others keep one model loaded. Workbench passes the configured `model` field but cannot prove a server honoured it. In particular, whisper.cpp 1.9.2 loads the model given at startup and changes it through a separate `/load` endpoint. Its transcription handler does not use the request's `model` field to select a different model. Changing that field in Workbench therefore does not switch a whisper.cpp model; restart or reconfigure the server, or use an endpoint that supports per-request model selection. [Official 1.9.2 server source](https://github.com/ggml-org/whisper.cpp/blob/v1.9.2/examples/server/server.cpp)

Only exact `127.0.0.1`, `localhost` and IPv6 `::1` hosts are accepted. `localhost` is rewritten to `127.0.0.1` to avoid DNS or hosts-file resolution. HTTPS retains normal certificate validation against the actual numeric address; self-signed or localhost-only certificates may therefore fail. Plain HTTP on the loopback interface is the usual local-server setup. Credentials, URL query strings, fragments, non-HTTP schemes and every redirect are rejected. Sessions have no cookies, stored credentials, disk cache or configured proxies. There is no API-key field: this preview supports local servers that do not require authentication. Do not bind an unauthenticated server to a public network interface.

An audio upload is limited to 64 MB and a response to 2 MB as it arrives. A request has a three-minute deadline, cancellation cancels the URLSession task, and concurrent transcription requests are rejected. Cancellation cannot guarantee a separately running server immediately stops its own inference. Workbench sends only to the local endpoint; the server is user-controlled software and may itself forward requests. Its configuration determines end-to-end privacy.

Saved settings live in the current app's defaults domain, under `workbench.recognition.configuration.v1`. The preview bundle therefore keeps its choice separate from production and the old Voice app. Unreadable settings prevent inference and remain untouched until the user explicitly applies a valid choice. Changing provider releases the unused in-memory Parakeet manager; it preserves the downloaded cache for later reuse.

## Adding another provider

Add an explicit `RecognitionProvider` choice and one dispatch branch in `RecognitionEngine`, including its readiness, availability, cancellation and input contract. Keep microphone capture, text cleanup, history, hotkeys and presentation outside provider implementations. Changes should not alter the public `prepare`, `isReady` or `transcribe` call pattern.

Apple Speech is not offered in this preview. A future on-device provider must check authorization, locale and on-device availability, require on-device recognition for every request, and report unavailable rather than silently using Apple's network recognizer.

The FluidAudio integration is pinned to [0.15.6](https://github.com/FluidInference/FluidAudio/tree/0.15.6); do not assume APIs or model support from its latest README exist in the pinned dependency. URLSession redirect rejection uses Apple's [task delegate](https://developer.apple.com/documentation/foundation/urlsessiontaskdelegate/urlsession(_:task:willperformhttpredirection:newrequest:completionhandler:)).

## Verification

`--check-providers` runs the deterministic checks and real HTTP transport against synthetic loopback fixtures: success, redirect refusal, HTTP failure, declared and streamed response limits, cancellation, and in-flight model selection. These checks use synthetic bytes and isolated temporary defaults. They establish protocol behaviour, not recognition accuracy.

### Real server checked on 12 September 2026

An independent harness using the exact production `RecognitionConfiguration`, `LocalTranscriptionEndpoint` and `LocalTranscriptionTransport` source successfully transcribed synthetic speech with installed Homebrew whisper.cpp 1.9.2 and the official English tiny model. There were no model or server stubs. The harness exercised the request builder, HTTP transport and response decoder; it did not exercise Workbench's installed UI, actor wrapper or a user's saved provider settings.

| Item | Observed evidence |
| --- | --- |
| Model | Official `ggml-tiny.en.bin`, 77,704,715 bytes |
| Model SHA-256 | `921e4cf8686fdd993dcd081a5da5b6c365bfde1162e72b08d75ac75289920b1f` |
| Provider source SHA-256 at verification | `7dacf976987248c10fbc3b5036eb94adf96477704bb4e44e6c1c6e13cd3f4153` |
| Endpoint / model field | `http://127.0.0.1:18789/v1/audio/transcriptions` / `tiny.en` |
| Server execution | CPU, four threads; `--convert` with installed ffmpeg |
| Input | macOS Samantha synthesis, 5.561625 seconds; no microphone |
| WAV result | Expected sentence returned; request completed in 0.410 seconds |
| M4A result | Expected sentence returned; request completed in 0.414 seconds |

The content check required “blue notebook”, “tomorrow” and “morning”. Both results contained the test sentence, with line breaks and without its first “The”. These are single short compatibility checks, not an accuracy or performance benchmark. MP3, FLAC, other models, languages and hardware were not covered by this real-model run. The temporary server was stopped afterwards; app preferences and credentials were untouched.

To reproduce the server setup, use whisper.cpp 1.9.2 and ffmpeg already installed on the Mac. The model URL is the one used by the project's [official download script](https://github.com/ggml-org/whisper.cpp/blob/v1.9.2/models/download-ggml-model.sh). In one terminal:

```sh
mkdir -p /tmp/workbench-model-check
curl --fail --location --proto '=https' --max-filesize 150000000 \
  --output /tmp/workbench-model-check/ggml-tiny.en.bin \
  https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-tiny.en.bin
shasum -a 256 /tmp/workbench-model-check/ggml-tiny.en.bin
whisper-server --host 127.0.0.1 --port 18789 \
  --inference-path /v1/audio/transcriptions \
  --model /tmp/workbench-model-check/ggml-tiny.en.bin \
  --language en --threads 4 --no-gpu --convert \
  --tmp-dir /tmp/workbench-model-check
```

Check the model hash against the table. The server remains in the foreground; stop it with Control-C after testing. M4A was verified with `--convert`, which requires ffmpeg. WAV worked without that option as well. This setting follows the [server's documented conversion support](https://github.com/ggml-org/whisper.cpp/tree/v1.9.2/examples/server).

In a second terminal, generate the same public test sentence and reproduce the server's multipart contract:

```sh
say -v Samantha -r 165 -o /tmp/workbench-model-check/synthetic.aiff \
  'The quick brown fox jumps over the lazy dog. Please bring the blue notebook to the meeting tomorrow morning.'
afconvert -f WAVE -d LEI16@16000 -c 1 \
  /tmp/workbench-model-check/synthetic.aiff /tmp/workbench-model-check/synthetic.wav
afconvert -f m4af -d aac@44100 -b 96000 \
  /tmp/workbench-model-check/synthetic.aiff /tmp/workbench-model-check/synthetic.m4a
curl --fail --noproxy '*' \
  --form 'file=@/tmp/workbench-model-check/synthetic.wav;type=audio/wav' \
  --form 'model=tiny.en' --form 'response_format=json' \
  http://127.0.0.1:18789/v1/audio/transcriptions
curl --fail --noproxy '*' \
  --form 'file=@/tmp/workbench-model-check/synthetic.m4a;type=audio/mp4' \
  --form 'model=tiny.en' --form 'response_format=json' \
  http://127.0.0.1:18789/v1/audio/transcriptions
```

Each response should be JSON with a `text` field containing the spoken sentence. These curl commands reproduce server compatibility; they do not independently validate Workbench's UI. To check that remaining path, explicitly select this endpoint and `tiny.en` in Workbench Settings and import the two generated audio files, then restore the preferred provider. That installed-app test remains separate from the completed harness evidence.
