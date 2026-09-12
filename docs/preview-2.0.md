# Workbench 2 Preview: current evidence

This branch combines Voice and StageMark in one app. It is a working Preview,
not a published release or a claim of complete acceptance testing.

## Verified locally on 12 September 2026

- Packaged `Workbench Preview.app`, Developer ID signature validation and isolated
  installation into the current user's Applications folder.
- Incremental packaging regenerates real Apple App Intents metadata. The Swift
  module remains `LocalVoice`; the packaged process is `WorkbenchPreview`.
- Release-binary core, cleanup, resource-library, provider and keyboard checks;
  42 synthetic integration checks, including real WAV/M4A App Intents data inputs.
- Real loopback HTTP transport: success, redirect refusal, HTTP failure, response
  size limits, cancellation and in-flight model selection. This is a protocol
  fixture using synthetic bytes.
- A separate real-model check used installed whisper.cpp 1.9.2, official tiny.en
  and the exact production provider request/transport/decoder in an independent
  harness. A 5.562-second synthetic sentence transcribed correctly as WAV and
  M4A in 0.410 and 0.414 seconds respectively. M4A used `--convert` and ffmpeg.
  The installed selection and executable were also checked below.
  [Commands, model hash and limits](model-providers.md#real-server-checked-on-12-september-2026).
- StageKit: 53 tests, 919 assertions, zero failures. The old standalone status
  popover test is excluded because this module no longer owns a status item.
- Eleven release-tooling checks and seven Preview installer checks.
- Installed app launches into the home window; annotation controls, saved scenes
  and keyboard coach are reachable in that window. The menu bar quick controls
  open and return to the home window.
- Closing the home window leaves one `WorkbenchPreview` process running;
  reopening the app restores its home window. Native Quit allows replacement
  by the Preview installer. Older Voice/StageMark processes were not running.
- Keyboard practice accepts three complete shortcut presses without starting
  dictation. An assignment already used by another action is rejected.
- Installed built-in speech engine transcribes a synthetic Mac-voice sentence,
  exports M4A, and transcribes the export successfully.
- Voice session and resource-library files match the legacy Preview originals
  byte for byte after migration. Existing scene choices appear in the new app.
- In the installed app, a real drawing stroke increased the count from zero to
  one; Undo returned it to zero. The saved board retained its eight strokes.
- The installed timer starts, pauses, hides and reopens, and resets successfully.
- iPhone Mirroring handoff opens Apple's app with a live phone connection.
  QuickTime handoff opens Apple's app. These are separate app windows, not proof
  that Workbench's USB device capture works.

An installed-app launch check found that reopening the unified app's own
preferences domain as a separate suite could return nil. Both modules now use
the host's standard preferences for shared appearance; the corrected app opens.

Additional installed checks: after the user granted Microphone access, Start
entered recording and Discard returned to Ready with "Recording discarded."
In the installed Models screen, selecting `tiny.en` at the verified local
endpoint was consumed by the installed app's CLI/RecognitionEngine for both
synthetic WAV and M4A inference. Both contained the expected brown fox, blue
notebook and tomorrow phrases. Parakeet and the original inactive endpoint were
restored; the temporary server was stopped. This did not exercise the Import
audio sheet or add test captures to the user's history.

- The optional founder card opened an editable Apple Mail draft to Ethan and
  Matt with the intended subject and greeting. Nothing was sent; the test draft
  was discarded. Not now hides the Home card; Settings retains contact access.
- The landing-page build and five feedback tests pass. Its nine-second silent
  annotation illustration contains only synthetic content and is labelled as
  an illustration rather than a recording of the app.

- A real saved Apple Shortcut invoked the installed Preview with a synthetic
  WAV and returned the correct 108-byte transcript through `shortcuts run`
  to a local output file. Runtime logs identify the installed Preview bundle
  and completed action. An earlier run waited in the downstream Show Content
  flow; returning the text directly succeeded. No metadata rewrite was needed.
- Native device presentation entered its first-use video permission state;
  Escape ended the session and returned to the scene editor. At that point,
  live USB video had not been verified; the later permission and feed check
  is recorded below.

## HUD follow-up on 12 September

The locally installed Preview was exercised with its updated native recording,
clipboard and presentation controls:

- The final signed package build and full regression suite pass, including 25
  clipboard checks and StageKit's 54 tests / 959 assertions (40 new presentation
  visibility assertions). Run the exclusive global-shortcut tests with the
  installed app quit; an earlier concurrent run correctly found its occupied
  shortcuts, and the final run passed after quitting it.

- The microphone-off positioning preview, live recording meter/timer and direct
  Cancel control were visible and usable. Cancelling discarded the live test.
- A loopback test server held a synthetic response until explicitly released.
  Cancel from the floating processing HUD returned to idle with no session
  change. Releasing the response afterward still left the state file unchanged.
  This is cancellation evidence, not a speech-quality test.
- Copying synthetic text displayed a receipt; pinning kept it visible. Quick
  controls showed the word count and Command-V cue without transcript text.
  Copying unrelated text through a normal native field cleared the pinned
  receipt and the quick-controls shelf.
- A scene-only full-screen demo hid its toolbar, left it hidden during movement
  over the scene, revealed it at the top edge and with Command-Slash, retained
  it when pinned, and ended with Escape. Its device-frame setting was restored.
- The temporary provider was removed from active use and Parakeet plus the
  prior inactive endpoint/model were restored. The test server was stopped.
  One deliberately completed synthetic request was removed by restoring the
  exact guarded pre-test session snapshot, preserving all 100 original history
  entries and the original draft. Imported synthetic audio remained intact.

Audience screen-sharing, VoiceOver interaction and real multiple-display
changes remain separate acceptance checks. The HUD's placement and
presentation-retention policies have synthetic test coverage.

## CI and hardware follow-up on 12 September

- GitHub workflow scope was granted with the user's authorization. The unified
  branch is under review in [draft PR #13](https://github.com/EthDawg/local-voice/pull/13).
  [CI run 34686749639](https://github.com/EthDawg/local-voice/actions/runs/34686749639)
  passed at commit `0651133`. The earlier runner lacked `rg`; the StageKit
  test script now checks its result with macOS's `/usr/bin/grep -Eq` instead.
- With Accessibility enabled and the app reporting Automatic paste ready,
  the user's physical press of their configured Command-3 shortcut produced
  exactly “The purple lantern is beside the window” in a scratch TextEdit
  document. The previous synthetic clipboard content was restored afterward.
  This verifies microphone dictation and automatic paste into that target.
- With Camera access enabled, Workbench's native iPhone feed displayed
  **Live · 1320 × 2868**. Manual Reconnect briefly showed Not live before the
  feed resumed. Physical USB unplug/replug and stale-frame recovery remain
  unverified; this observation does not establish either behavior.
- A separate `Workbench Live QA` shortcut completed Apple Record Audio →
  Transcribe with the installed Preview → Stop and Output. Apple's recording
  helper handled Start/Stop, and the downstream output displayed the expected
  synthetic sentence: “Workbench permission test: the purple lantern is beside
  the window.” The original dictation shortcut was left unchanged.
- After quitting the app, exactly three known synthetic QA captures were
  removed using a guarded snapshot taken after the user's latest real capture.
  All 100 prior history entries and the prior draft were restored byte for byte.
- Local review found that automatic recovery could reuse a session's frame
  token. Every teardown now invalidates that token, so queued frames from a
  previous session cannot mark its replacement Live. The full regression suite
  passed after this change, including StageKit's 54 tests / 965 assertions.
  This covers the stale-frame policy; physical cable recovery remains separate.

No personal recordings or phone images are included in this record. These
checks do not establish a public release or notarization.

## Still to verify or deliver

- The separate Shortcuts Show Content presentation has not been accepted;
  live capture, transcription and downstream Stop and Output are verified above.
- Physical USB unplug/replug and stale-frame recovery; display changes and
  an audience's real screen-sharing view.
- Fresh-Mac download, first model setup and normal Gatekeeper first opening.
- Public notarized Preview, downloaded-byte verification and the unified site.

The optional introduction opens a draft; Workbench does not send email or
claim delivery. No website signup, transcript or device/usage data is included.

Imported custom shortcuts remain saved. The keyboard page flags known native
and cross-action conflicts; users choose replacements. No App Store submission
has been changed.
