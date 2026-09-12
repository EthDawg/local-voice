# Workbench consolidation

## Purpose

Free everyday Mac tools for speaking, explaining and presenting. Improve the commodity baseline through better local models and small, dependable workflows. Existing native macOS features are the baseline to improve against. Workbench 2 combines Voice and StageMark in one application process, one home window and one menu-bar item; speech and presentation remain separate internal modules.

## Working implementation

- `LocalVoice` is the app executable target (kept internally for existing App Intents metadata compatibility). `WorkbenchHome` owns app navigation. StageKit is a library, not a child app.
- `StageKitController` owns drawing, boards, timers, scenes and device capture. Its public facade connects shared navigation, busy state and keyboard editing. StageKit cannot quit the host or install another menu-bar item.
- `RecognitionEngine` snapshots a selected provider per invocation. Built-in Parakeet and a loopback OpenAI-compatible transcription endpoint are real choices. Online Speko reading remains explicit opt-in; Mac voices are the default.
- `KeyboardCoachModel` owns assignment and practice. Recording/practice suspends both modules' registered hotkeys, validates duplicates/reserved combinations, probes the OS and restores registration on exit. It never claims knowledge of every shortcut in every installed app.
- New Preview identity `com.ethdawg.workbench.preview`. Data is copied into `Application Support/Workbench Preview/LocalVoice` and `StageMark`. Original app data remains untouched. Preview and production are separate identities.
- USB presentation uses Apple's capture frameworks. QuickTime and iPhone Mirroring are separate Apple app launch paths. Native framework/device/OS support must be verified honestly; no private API embedding of iPhone Mirroring.

## Style and tone

Keep the Workbench name. Use native controls, system type and the existing restrained mint/slate appearance. One verb per primary action: Dictate, Read aloud, Annotate, Present. Explain the immediate benefit; disclose state and failure in plain English. Avoid an onboarding slideshow: the home actions, first-use permission requests and hands-on keyboard practice teach the app in context. Real recordings and user files must never become demo assets.

## Required before completion

This is a working acceptance record, not a claim that any unchecked item is delivered.

Current evidence and remaining installed workflows: [Workbench 2 Preview](preview-2.0.md).

On 12 September 2026, GitHub workflow scope was granted with the user's
authorization. [Draft PR #13](https://github.com/EthDawg/local-voice/pull/13)
is open, and [CI run 34686749639](https://github.com/EthDawg/local-voice/actions/runs/34686749639)
passed at `0651133`. The initial runner lacked `rg`; `scripts/test-stage.sh`
now uses the system `grep` to check the result. Review and public release
remain separate steps.

- [x] Unified native app builds and core, provider, keyboard and StageKit regressions pass. The final HUD regression run passed core 21, cleanup 16, library 36, provider 37 plus real loopback transport, integration 42, keyboard checks, clipboard 25, and StageKit 54 tests/965 assertions on 12 September 2026 after the automatic-recovery token fix.
- [x] One installed Preview process/status item; home, menus, Dock, reopen, close and Quit verified.
- [x] Original Voice and StageMark data preserved; imported data and settings verified.
- [ ] Dictation, cancellation, history, read-aloud/export and App Intents verified in installed package. Physical Command-3 dictation pasted the exact disposable test sentence into TextEdit with Accessibility enabled and Automatic paste ready; the previous synthetic clipboard was restored. Existing-file App Intents dispatch and Apple Record Audio → installed Preview transcription → Stop and Output passed. The separate Show Content presentation remains unverified.
- [x] Switching local speech engines verified with a real compatible local server plus failure/cancellation checks. Installed Settings selection was consumed by the installed executable for synthetic WAV/M4A inference; transport cancellation/failure has separate automated coverage.
- [x] Virtual keyboard assignment/conflicts/practice verified using real keys without activating tools.
- [x] Annotation/board/timer focus and shutdown verified alongside speech.
- [ ] Device presentation, QuickTime and iPhone Mirroring paths exercised with available hardware; limitations disclosed. With Camera access enabled, the native iPhone feed showed Live at 1320 × 2868; manual Reconnect briefly showed Not live before resuming. Physical USB unplug/replug and the audience's screen-sharing view remain unverified. Stale-frame invalidation has regression coverage. Earlier QuickTime and iPhone Mirroring handoffs are recorded in the Preview evidence.
- [ ] Downloadable signed/notarised unified Preview published on GitHub; public bytes and installed copy verified.
- [ ] Unified landing page explains one app and its download. No website signup is needed.
- [x] Optional introduction during app use opens an editable draft to Ethan and Matt in the user's email app. The user explicitly chose this flow on 12 September; Workbench does not send email or claim delivery. No website signup, transcript, device or usage data is included.
- [x] Useful synthetic examples/media for landing page prepared; no heavy image generation. Nine-second silent illustrated annotation workflow, explicitly labelled as an illustration.
- [x] README, contributor/architecture source maps, model docs and migration/release notes match the local unified app. Historical Voice evidence is explicitly scoped; candidate site links target the matching Preview release. Public publication remains a separate unchecked item.
- [x] No App Store submission changed.

## Source preservation

Voice branch base: 1a68b50. StageMark source imported from feature/demo-preview at e7022b7, including the existing uncommitted presenter polish. Original checkouts are not reset or overwritten. Consolidation branch: feature/unified-workbench in the existing local-voice repository. This avoids prematurely renaming or moving the public repositories while the new app is under review.
