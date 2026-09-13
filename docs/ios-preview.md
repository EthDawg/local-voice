# Workbench on iPhone and iPad

Native **iOS/iPadOS 26+ Preview**, not a published App Store or TestFlight release. This document owns mobile scope, build instructions and platform limits. The [personal-scenes contract](research/personal-scenes.md) owns the shared scene architecture and preservation rules; the [public scene evidence](https://workbench-mac.vercel.app/scenes/#evidence) is the current cross-device acceptance view. The Mac remains a separate native target. GitHub issues remain the contribution queue.

## The useful mobile baseline

**Tools** opens Dictate, Read aloud, Mark up, Scenes and Wallpapers; **Saved** returns to your work. Dictation has first emphasis. iPad uses the same jobs with adaptive layouts and native Pencil tools. Scenes replaces the primary Backdrops and Take a photo for Mac entries; it does not absorb voice, reading, annotation or wallpaper.

| Job | Current journey | Boundary |
| --- | --- | --- |
| Speak → text | Explicitly prepare Apple's supported speech assets; record in the foreground or choose audio; keep original words/audio; review, optionally apply Light cleanup and approved replacements, then save, copy, share or read aloud | No custom keyboard, automatic cross-app paste, background microphone or silent cloud fallback. Mac Parakeet, server and Natural refinement settings are not mobile providers. |
| Text → speech | Write, paste or import text; choose an installed Apple voice and rate; read, pause, resume or stop | One reading owner with system media controls. No online voice account, PDF reader or audio-export promise. Physical background/audio routes remain separate checks. |
| Explain an image | Choose a screenshot/photo, draw with PencilKit and undo/redo, keep editable ink, share a rendered PNG copy | Workbench's canvas, not an overlay over other apps. No PDF editor or verified redaction tool. |
| Prepare a scene for Mac | Camera, Photos or starting picture → background/crop, device position, optional logo/persona → save an editable scene; optionally enable personal iCloud sync or share a scene file | Mobile prepares a layout; Mac supplies the live device video and presentation window. The phone outline is a placement preview, not a remote capture feed. |
| Enjoy a wallpaper | Choose a photo or starter, adjust the saved crop, then **Save to Photos** or Share; finish in Photos → Share → Use as Wallpaper | Independent project/aspect/crop. No automatic wallpaper installation, continuous background video or Focus changes. Apple's final crop can differ. |
| Reopen or reuse | Open saved texts, scenes, image projects and selected-photo handoffs; deliberately reuse originals | Scene sync is optional and scoped to scenes. Texts, recordings and wallpaper edits do not acquire implicit sync. |

Home Screen quick actions are **Capture for scene** and **Dictate**. They route into an active app with unsaved-edit guards. Camera access remains subject to permission; opening Dictate never itself starts recording. Tools and Saved remain the two top-level tabs.

Markup and wallpaper use Photos/Files imports, bounded to 64 MB and 50 megapixels. Their PNG exports render the image and edits, cap the long edge at 3,840 pixels and use distinct temporary files. Scene imports use the stricter shared asset/package bounds in the [scene contract](research/personal-scenes.md#current-shared-architecture). Camera and Photos inputs copy selected bytes; no full-library scan is needed. Bundled starter artwork is separate from private customer media.

Wallpaper retains its chosen aspect even when the iPad rotates. Horizontal, vertical and zoom controls accompany gestures. Save to Photos requests add-only access and reports the result; permission or save failures must not claim success. Physical Photos saving remains an acceptance check.

## Scenes, photos and earlier work

A saved scene contains an editable background, device geometry and optional artwork, with owned image assets. Mac and mobile compile the same `SceneSyncKit` rules. Personal sync uses one Apple Account across devices; enabling it sends saved scenes and pictures to that person's private iCloud. There is no Workbench account or cross-account team library.

While enabled and active, committed edits coalesce after an 800 ms pause. Foreground refresh checks for remote changes. Backgrounding cancels scheduled and active transfers while retaining waiting work; a failed cycle waits for manual or foreground retry. **In iCloud** confirms the upload, not arrival on another device. This is not a background-delivery or latency promise. Portable `.workbenchscene` import/export remains available independently of cloud.

[Selected-photo handoff](photo-handoff.md) is a separate feeder with its own queue and private zone. On mobile it remains available from **Saved → Photo handoff** (opens **Photo for Mac**) and saved photo rows. Explicit Send queues a chosen photo; enabling photo handoff does not send all older local pictures. A received picture can enter an existing Mac scene through its ordinary replacement preview. Photo removal does not erase the scene's accepted copy.

Earlier Backdrops compositions remain editable from Saved. **Create scene for Mac** creates a new scene and retains the original project plus its pictures, caption, ink and editable values. **Recover mobile original** creates another mobile project from that attachment. Conversion does not flatten or delete the original; the new landscape preview may differ from the earlier collage or wallpaper. Older in-app presentation is not the primary Scenes journey. See [recovery details](research/personal-scenes.md#earlier-work-and-recovery).

## State, lifecycle and platform boundaries

- `MobileStore` owns the versioned local text/image-project manifest and immutable original assets. `SceneLibraryModel` owns the separate portable scene library. Validated writes are atomic; unreadable or unsupported libraries pause writes and preserve their bytes.
- A project owns its edits. Reuse starts independent edits. Removing an item currently retains source assets needed by recovery or other references; it is not storage cleanup. Export important work before uninstalling.
- Original transcript text stays separate from editing and cleanup. Copy and Share are explicit and never submit a message. Save failures remain visible.
- Recording is foreground only, capped at five minutes. Imported audio is capped at 64 MB and 30 minutes. Backgrounding, interruption and cancellation release the microphone; recoverable audio remains available for retry or discard. Cancelled work cannot publish a stale result.
- `SpeechAnalyzer`/`SpeechTranscriber` check device, locale and assets. Explicit preparation may download Apple model assets; recognition does not fall back to another service. Compilation does not establish physical model readiness or speech quality.
- `AVSpeechSynthesizer` supplies installed voices. Starting capture stops reading; a new reading supersedes the old one. Lock Screen, Bluetooth/AirPlay and interruption handling still need physical route checks.
- No arbitrary overlay, global shortcut, custom keyboard, Share extension, App Group exchange, ReplayKit broadcast extension, external-display scene or custom AirPlay receiver is implemented. A meeting app owns its sharing session. Receiving-participant visibility requires a real route test.
- Dynamic Type, VoiceOver traversal, Pencil behaviour, light/dark appearance and reduced-motion settings require native acceptance beyond compiling accessibility labels.

The target uses SwiftUI, UIKit, PhotosUI, Photos, PencilKit, AVFoundation, Speech and MediaPlayer. It compiles shared `SceneSyncKit` and `PhotoHandoffKit` sources plus `TextPrimitives.swift`, `DictationCleanup.swift` and `CorrectionRule.swift`. It does not link StageKit, AppKit, Carbon, FluidAudio or Mac shell-based reading.

| Source owner | Responsibility |
| --- | --- |
| `WorkbenchApp.swift`, `SavedView.swift`, `MobileQuickActions.swift` | Tools/Saved navigation, reopening work, file/quick-action routing and operation guards |
| `MobileDocument.swift`, `MobileStore.swift` | Local text/image records, original assets and independent reuse |
| `MobileScenesView.swift`, `MobileSceneEditor.swift`, `MobileSceneImport.swift` | Scene preparation, personal-sync settings, portable exchange and older-project recovery |
| `SpeechService.swift`, `ReadingService.swift`, `TextWorkspaces.swift` | Speech readiness, recoverable capture, text delivery and installed-voice playback |
| `ImageWorkspace.swift`, `ImageCanvas.swift`, `ImageRendering.swift`, `WallpaperPhotoSaver.swift` | Markup/wallpaper, older compositions, rendering and explicit Photos save |
| `Mobile/WorkbenchTests`, `Mobile/WorkbenchUITests` | Storage/rendering checks and native navigation/persistence tests with disposable data |

## Build and test

Use full **Xcode 26.1+**, an iOS 26.1+ SDK and an installed iOS 26 Simulator runtime. The Mac SwiftPM and Developer ID/notarization scripts do not build or distribute this target.

```sh
python3 scripts/mobile-project.py
open Mobile/Workbench.xcodeproj
bash scripts/test-mobile.sh
```

The generator owns the project and shared **WorkbenchMobile** scheme. Regenerate after adding files; edit `scripts/mobile-project.py` instead of generated project entries. The test script regenerates first, selects an available iOS 26 iPhone Simulator by default, disables signing/parallel testing and prints its fresh `Results.xcresult` path. CI selects a family with `MOBILE_DEVICE_FAMILY=iPhone` or `iPad`. For a specific simulator:

```sh
xcrun simctl list devices available
MOBILE_SIMULATOR_UDID=YOUR-SIMULATOR-UUID bash scripts/test-mobile.sh
```

Debug UI tests use fresh temporary libraries through `--ui-testing`; photo fixtures additionally use `--ui-testing-handoff`. Cloud access is disabled. Tests must never reset a live library. Coordinate simulator/native tests and shared builds with other work; Mac global-shortcut tests are a separate workflow.

A generic unsigned iOS archive checks compilation and packaging only. Installation needs an available trusted device, Developer Mode and authorised iOS signing/provisioning. Mac Developer ID signing and notarization do not satisfy that requirement. Follow the [paired Preview signing commands](photo-handoff.md#signing-and-configuration-gate) for the shared Production container; ordinary mobile builds keep cloud access off. Install and inspect the exact exported app, since export can re-sign it and a Debug Run can replace it.

TestFlight/App Store distribution is a separate workflow. Neither has been performed. A signed local install is not a public release or Apple approval.

## Verification: current versus historical

Use the [canonical scene record](research/personal-scenes.md#evidence-and-remaining-acceptance) and [public evidence table](https://workbench-mac.vercel.app/scenes/#evidence) for cross-device status rather than maintaining another current-results table here.

As of this update, the physical iPhone Preview has installed and **launched normally**; its Scenes and personal-sync settings were visibly inspected through iPhone Mirroring. The Mac has retained a real received iPhone photo and acknowledged uploads for eight scenes with matching revision receipts. Phone-side personal scene-sync opt-in and reception are still pending, so **paired scene delivery remains unverified**. Successful upload is not a receiver result.

The final mobile suite contains **57 unit and 8 UI cases**. All final cases passed across completed runs: the full iPhone run passed 62/65, followed by the remaining three passing; iPad passed 64/65, followed by its remaining scene case passing. The final iPhone scene journey passed again after the native starting-picture menu hit-area fix. This is **not a claim of one clean final full-suite run**. The scene preview and menu hit regions were corrected without removing the persistence, original-data or no-cloud assertions.

The physical phone has the earlier updated Release Testing export installed. A further archive containing the final native menu fix is in progress under the same build identity; do not infer its installation from the version alone. Export, signature and installation receipts identify which artifact was checked. No public binary has been issued.

Earlier 18-unit/5- or 7-UI results, initial unsigned archives and pre-Scenes screenshots are historical evidence. New source checks supersede those product claims without turning the older captures into current UI. Actual screenshots in `site/assets/guide/` use synthetic content and must retain their source/run provenance; generated concepts are labelled separately. Tests and captures do not establish physical microphone/model readiness, wallpaper Save to Photos or paired scene arrival.

Still pending: physical Dictate preparation and recognition, permission denial, interruption/force-quit recovery, wallpaper Photos save, Lock Screen audio, Bluetooth/AirPlay, Pencil accuracy, memory/energy, VoiceOver, large Dynamic Type and meeting recipients. The iOS 26.0 fallback playback inset compiles but was not exercised by the iOS 26.5 Simulator runs.

The privacy manifest describes app-owned/user-selected file metadata access (`C617.1`, `3B52.1`), with no collected-data or tracking declarations. [Apple's API categories and approved reasons](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype) govern that declaration. App Store Connect validation remains separate and has not run.

## Platform references

Research checked 13 September 2026: [running on devices](https://developer.apple.com/documentation/xcode/building-and-running-an-app), [Developer Mode](https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device), [custom keyboard restrictions](https://developer.apple.com/documentation/uikit/configuring-open-access-for-a-custom-keyboard) and [extension storage coordination](https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/ExtensionScenarios.html). [Mobile research](mobile-research.md) retains native and competitor references with their review limits.
