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
  Escape ended the session and returned to the scene editor. Live USB video
  remains unverified without the video-access grant.

## Still to verify or deliver

- Automatic paste into a harmless target needs the new app's Accessibility
  grant. Copy is available without it.
- Full live Apple Shortcuts Record Audio → Transcribe → downstream action flow
  with first-use permissions. The action is discoverable and Stop cancels
  Apple's recording step. File-to-text dispatch is verified below; live capture
  and the separate Show Content presentation remain unverified.
- Workbench's native USB selection, reconnection and actual video; display
  changes and an audience's real screen-sharing view.
- Fresh-Mac download, first model setup and normal Gatekeeper first opening.
- Public notarized Preview, downloaded-byte verification and the unified site.

The optional introduction opens a draft; Workbench does not send email or
claim delivery. No website signup, transcript or device/usage data is included.

Imported custom shortcuts remain saved. The keyboard page flags known native
and cross-action conflicts; users choose replacements. No App Store submission
has been changed.
