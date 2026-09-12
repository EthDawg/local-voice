# Workbench 2 Preview: current evidence

Updated 12 September 2026. Voice and StageMark share one app. The final signed local
package and full regression run passed, and the Preview was installed. This record
is not a public release announcement or a claim that all acceptance checks pass.

## Current implementation

- The recording HUD has compact and expanded controls for the same operation.
  Stop remains available while recording; opening or closing options preserves
  the recording and intended Mac paste target. Each capture freezes its cleanup
  and delivery settings.
- The presentation tile starts collapsed at the right edge centre. Click or
  Command-Slash opens its device controls; Escape closes open controls first,
  then ends the presentation on a later press. Source closes the controls before
  opening its chooser. Ordinary pointer movement does not open the tile.
- Recording and presentation share eight named positions, anchor-preserving
  resizing, screen clamping and drag-only snap previews. Each remembers its own
  placement. The presentation tile contains no Mac dictation or model controls.
- Finished persona images can float over a browser or appear in a saved mobile
  scene. Imports preserve artwork and transparency, create durable local copies,
  and support size, position and click-through locking. Floating personas start
  hidden on launch. Removing a library entry retains images used by scenes.
- Original and Light use no text-refinement model. Natural uses Apple's
  on-device model or explicitly selected loopback Ollama. Models owns discovery,
  download and load controls. Remote endpoints, redirects and reported cloud
  aliases are refused; server metadata does not audit the user's server.
  Model downloads require network access. Failed or rejected refinement falls
  back visibly to Light, with the original transcription retained.

See the [interaction specification](product-spec.md), [persona guide](personas.md)
and [privacy page](../site/privacy.html) for behavior and data boundaries.

## Latest native checks

These checks exercised the local signed Preview. Public-download verification is recorded separately in the release notes:

- Recording controls opened compact and expanded, and their positioning controls
  worked. This is interaction evidence, not a new speech-quality benchmark.
- The Models view downloaded and loaded actual Ollama `gemma3:1b`. The tested
  choice was not saved as the user's active refinement configuration.
- A synthetic persona was imported, shown, locked and displayed inside a scene.
- Presentation click and Command-Slash opening, Escape priority, the source
  chooser and drag snapping were exercised. No current physical-phone feed or
  meeting receiver was verified in this pass.
- A focused real-model run accepted punctuation-only edits in five of eight
  synthetic cases; three used the conservative fallback. This small check is
  not a quality or performance benchmark.

The final `scripts/test.sh` run passed: release and installer tests; core,
cleanup, history, library, integration, keyboard, clipboard, provider and capture
checks; **50 refinement checks plus 23 transport/deadline checks**; and
**61 StageKit tests / 1,553 assertions / 0 failures**. The exact signed archive
was installed after this run. Signature and native App Intents metadata checks
also passed. The regression tests use isolated fixtures; any notarization text
from mocked release-tool tests is not an actual Apple submission.

A subsequent review found that manual draft cleanup did not retain its task for
cancellation. The fix uses the same cancellation lifecycle and clears stale
delivery context. Thirteen checks execute the exact production methods against
an isolated delayed engine: immediate cancellation, an uncooperative late
response, concurrent edits, unchanged originals and successful cleanup.

## Historical evidence

The following observations came from earlier local builds on 12 September.
They establish what was checked then, not fresh acceptance of the current package.

| Area | Earlier observation | Limit |
| --- | --- | --- |
| Packaging and migration | Developer ID validation, isolated Preview installation, real App Intents metadata, launch/reopen/quit and preservation of existing Voice/StageMark data passed. | Fresh-Mac download and Gatekeeper first opening remain separate. |
| Speech and handoff | Built-in recognition processed synthetic audio; real whisper.cpp `tiny.en` processed WAV and M4A; a saved Apple Shortcut returned a transcript. Record Audio → Transcribe → Stop and Output also worked. | The separate Shortcuts Show Content flow was not accepted. [Provider evidence](model-providers.md#real-server-checked-on-12-september-2026). |
| Mac interaction | Physical microphone dictation pasted into a scratch Mac text field. Drawing, Undo, saved boards, timer controls and keyboard practice were exercised. | This does not establish input forwarding to a physical phone. |
| USB device feed | With Camera permission, the native iPhone feed reached 1320 × 2868. After manual Reconnect, it eventually resumed. | Physical unplug/replug and automatic hardware recovery were not established. |
| Capture recovery | Tests verified that teardown invalidates old frame tokens, so queued frames cannot mark a replacement session live. | Policy coverage is distinct from physical cable testing. |
| CI | [Run 34686749639](https://github.com/EthDawg/local-voice/actions/runs/34686749639) passed at `0651133`. | This is a historical commit, not evidence for subsequent changes. |

An earlier presentation toolbar used top-edge hover reveal and a visibility
pin. That interaction has been superseded by the current click-only tile;
its earlier test counts and screenshots do not describe the current controls.
QuickTime and iPhone Mirroring were opened as separate Apple apps. Those
handoffs do not prove Workbench USB capture or embedded phone control.

No personal recordings or phone images are included in this record. Synthetic
QA data was isolated or removed with guarded restoration of existing data.
The optional founder introduction was checked as an editable email draft;
Workbench did not send it or claim delivery.

## Remaining checks and release gates

- Recheck physical USB unplug/replug, actual display changes and VoiceOver use.
- Verify what a real recipient sees in Teams and Zoom for the chosen sharing
  surface; do not claim presenter-only controls or infer receiver behavior.
- Check a fresh Mac's download, first model setup and Gatekeeper first opening.
- Publish the reviewed source, tested guide and signed Preview archive with its
  checksum, then verify downloaded bytes. Publication remains pending.

App Store submission and notarization upload remain on hold. A signed local
package is not a published or notarized release.
