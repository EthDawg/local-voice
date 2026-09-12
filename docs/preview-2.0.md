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
  fixture, not a second installed speech model/server.
- StageKit: 53 tests, 919 assertions, zero failures. The old standalone status
  popover test is excluded because this module no longer owns a status item.
- Ten release/Preview installer regression tests.
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
- iPhone Mirroring handoff opens Apple's app with a live phone connection.
  QuickTime handoff opens Apple's app. These are separate app windows.

An installed-app launch check found that reopening the unified app's own
preferences domain as a separate suite could return nil. Both modules now use
the host's standard preferences for shared appearance; the corrected app opens.

## Still to verify or deliver

- Microphone recording/cancellation and automatic paste in the installed app;
  complete Apple Shortcuts Record Audio flow with real first-use permissions.
- A separately installed compatible transcription server with a real model.
- Remaining live drawing/board/timer and USB device workflows.
- Public notarized Preview, downloaded-byte verification and unified landing page.
- Optional founder introduction during app first use, with confirmed delivery.
  The product direction is app download/use, not a website signup form. Do not
  infer an email address from a download or silently report device/usage data.

Imported custom shortcuts remain saved. The keyboard page flags known native
and cross-action conflicts; users choose replacements. No App Store submission
has been changed.
