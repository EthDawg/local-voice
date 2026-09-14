# Workbench 2 Preview: current evidence

Updated 14 September 2026. Voice and StageMark share one app. [Preview 3](https://github.com/EthDawg/workbench/releases/tag/v2.0.0-preview.3) from `48bc7c0` is Developer ID signed, notarized, stapled and published. The downloaded ZIP passed checksum and Gatekeeper verification, then installed while retaining existing scenes and the saved photo. The earlier publication hold is superseded. iOS 2.1.0 (1) completed Apple processing and is awaiting remaining store preparation and physical acceptance; see [the iOS guide](ios-preview.md#release-preparation--14-september-2026).

The exact release source passed Mac, iPhone and iPad [CI](https://github.com/EthDawg/workbench/actions/runs/34761974846). The final Mac regression run included **91 StageKit checks / 2,165 assertions / 0 failures**, native global-input checks, speech/audio round trips, required cloud capabilities and Shortcuts metadata. Installed smoke checks covered opening the retained scene, presentation controls, the stale-frame message with a locked phone, and ending the presentation. A fresh live feed and audience receiver were not established. Publication does not mean all acceptance checks pass; earlier increments below are dated evidence.

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

## Earlier native checks — 13 September 2026

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
| CI | [Run 34686749639](https://github.com/EthDawg/workbench/actions/runs/34686749639) passed at `0651133`. | This is a historical commit, not evidence for subsequent changes. |

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

## Published evaluation Preview

[2.0.0-preview.1](https://github.com/EthDawg/workbench/releases/tag/v2.0.0-preview.1)
was published on 12 September 2026 from app source
`67eef5111016548524729633f14d449f15ed26e5`, build `20260912133744`.
[GitHub CI 34697004573](https://github.com/EthDawg/workbench/actions/runs/34697004573)
passed for that exact source, including packaging and native Shortcuts metadata.
The final local rerun also passed, including all thirteen draft-cleanup checks.

The public ZIP was downloaded again. Its checksum, release manifest and bundle
identity matched the installed signed Preview:
`2992d703ab5130500cad0f6a0bf5fe5c78e7a58a818be5c683a9ab8dd43d6b96`.
The archive, checksum and machine-readable `release.json` are release assets.
The [public guide](https://workbench-mac.vercel.app/guide/) is maintained with the
site source; subsequent guide-only commits do not change this app archive.

At publication, App Store submission and notarization upload were on hold. This evaluation
archive is Developer ID signed with hardened runtime and a secure timestamp,
but **not notarized**. It is outside the normal notarized release pipeline and
may be blocked by Gatekeeper on a fresh download. No human co-maintainer approval
is claimed; the implementation pull request remains a draft.

## Correction increment: 2.0.0-preview.2

This increment adds **Remember correction…** to transcript review, with explicit heard/preferred spelling, exact draft preview, reuse of the local dictionary and Undo that preserves newer edits. Earlier captures and recognizer originals stay unchanged; saving does not paste again. See the [comparison, decision and checks](dictation-comparison.md).

The complete local regression suite passed again, including 43 correction-rule and 43 transaction checks. Native interface checks used production UI and methods with synthetic, in-memory state. Signed packaging and native Shortcuts metadata validation passed. Apple submission and notarization were on hold at that stage. The release asset manifest records the source and archive identity; this Preview 2 evidence is historical.

## Everyday utilities increment: 2.0.0-preview.3

Read aloud now seeks/skips in existing audio; boards copy/save PNG images; presentations can start in a normal resizable window and switch fullscreen without ending; saved resources use Return for the selected primary action and report copy failures truthfully. See [the comparison and acceptance contracts](utility-comparison.md) and [commodity architecture](commodity-strategy.md).

Focused checks added 32 production playback-method checks, 8 real AVAudioPlayer checks and 29 saved-resource/model/view checks. Stage coverage is now 66 tests and 1,613 assertions. Native fixtures exercised playback reuse, keyboard resource recall/failure/editing, Save cancellation/export and window/fullscreen transitions. Fixtures use synthetic content and isolated stores/effects. No live draft or library was replaced. The release manifest identifies the exact signed source and archive.

The first full build exposed an actor-isolation error in the new test seam; fixed in production and mirrored in its fixture. A sandboxed run could not use the native audio encoder; normal approved execution passed that integration. Stage shortcut checks initially conflicted with the running Preview and passed after it released the keys. These are retained as validation history. The final Preview 3 publication and notarization are recorded at the top of this page. Physical-device, meeting-receiver, VoiceOver and fresh-Mac checks remain separate.
