# Workbench suite contract

Workbench is a collection of small native Mac utilities. Each tool has one job, a common control surface, and an explicit way to hand off to the next tool. This document is the canonical design contract for Voice and StageMark, and the starting point for future Workbench tools.

## Discovery and identity

- User-facing names are `Workbench Voice` and `Workbench StageMark`. Search **Workbench** in Spotlight to find the collection, or the full name for one app.
- Both declare `public.app-category.utilities`. macOS owns Spotlight’s result grouping; applications cannot create a custom Workbench result category. The shared name provides reliable suite discovery within Apps.
- Keep the existing bundle identifiers and storage domains when renaming an app. Voice remains `com.ethdawg.localvoice`; StageMark remains `local.ethan.StageMark`.
- Icons use a slate background, mint symbol, and rounded square. Each symbol identifies the app: waveform for Voice, pencil for StageMark.
- Keep one installed copy per channel. Stable apps retain their existing identifiers. Preview adds ` Preview` to the app name and `.preview` to its bundle ID, runs from `~/Applications`, and uses separate preferences and saved data. Build archives contain the app; temporary unpacked bundles are removed after packaging. Installers retain the prior version as a ZIP for rollback.

## Everyday controls

Native menu-bar popovers are 370 points wide, with the same Workbench header, segmented task tabs, compact native controls, status/notice area, and suite switcher. Left-click opens controls; right-click exposes app actions. A larger editor/settings window handles longer work. Escape closes controls. Closing an editor leaves the menu-bar utility available; Quit stops it.

All primary shortcuts are editable and conflicts are reported. Voice uses Control–Option–Space for dictation and Control–Option–V for controls. StageMark retains Control–Option–S for controls and its existing drawing shortcuts. Toggle and hold modes are explicit choices. Menu buttons latch an action, even when the keyboard is configured for hold.

## Shared appearance

`Workbench.swift` is the small shared shell, currently copied identically into both repositories. Compare its hash before shipping a shell change and update both apps together. It supplies colours, header, switcher, appearance picker, and SwiftUI appearance modifier. The latter matters because status-item popovers do not consistently inherit `NSApp.appearance`.

System, Light, and Dark are persisted in the `com.ethdawg.workbench` preference suite, key `appearance`; Preview uses `com.ethdawg.workbench.preview` with its own notification name. A distributed notification updates the other running app immediately. App-specific settings stay in the app’s existing domain. Use native surfaces, primary/secondary text, restrained mint/teal accents, and clear disabled controls. Do not force a dark theme on the user’s tools.

## Handoff and user control

The Workbench switcher opens the installed sibling app in the same channel. StageMark ends the active drawing interaction and commits text before handing off; saved boards remain intact. Voice closes its panel and stops playback before switching, and disables the switch while recording or processing.

Dictation captures its starting app and focused accessibility element. Automatic delivery rechecks both immediately before pasting. If either changed, access is missing, or the field is secure, copy instead and explain the result. Never press Return or submit a message. Restore the earlier clipboard only after insertion is verified and the app still owns the clipboard change; otherwise retain the transcript for recovery.

The editor always exposes the original transcript. Cleanup must be optional and recoverable. Avoid silently rewriting facts, names, negation, or intentions. Light rules are the default; uncertain language-model edits fall back to those rules. No tool should need an account, server, or paid API to work on its first configured day.

## Shipping a new Workbench tool

Use the naming, native shell, appearance suite, category, and handoff rules above. Choose shortcuts that do not conflict with installed suite apps. Keep a small independent application rather than requiring a new platform service. Verify the actual installed app: menu layout, light/dark appearance, Spotlight name, shortcuts, focus restoration, state migration, and interaction with its siblings. A successful compile alone is insufficient.

References: [Apple Spotlight guidance](https://support.apple.com/guide/mac-help/search-with-spotlight-mchlp1008/mac), [Launch Services keys](https://developer.apple.com/library/archive/documentation/General/Reference/InfoPlistKeyReference/Articles/LaunchServicesKeys.html).

## Local testing and updates

`install.sh` / `install.zsh` install a signed Preview by default, alongside production. The shared `scripts/release/preview.py` is mirrored with its installer regression tests. Preview seeds missing settings and known saved-data files from production on first launch only, then writes exclusively to its own app support folder. Keep the same Developer ID, bundle ID and installation path across updates. Never reset TCC or erase app data as a release step. Run one edition at a time for global shortcut testing. Voice shares the public FluidAudio model cache but isolates all user-authored state. The Mac App Store sandbox candidate remains a separate distribution workflow.

For unattended builds or native acceptance sessions, use the mirrored [unattended-session helper](unattended.md). It holds both system and display idle assertions for the selected command, including a bounded GUI-testing session, and releases them on exit. A system-sleep assertion alone does not prevent the screensaver from locking this Mac. Keep password policy intact and verify the display assertion before leaving a native test running.
