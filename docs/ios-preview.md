# Workbench on iPhone and iPad

Status: native **iOS/iPadOS 26+ Preview in development**, not a published App Store or TestFlight release. The Mac app remains a separate target with its existing contract. This record owns mobile scope, build instructions and acceptance evidence; [mobile research](mobile-research.md) explains the decisions, and GitHub issues remain the contribution queue.

## The useful mobile baseline

Open Workbench for a short, complete job. **Tools** introduces Dictate, Read aloud, Mark up, Backdrops and Wallpapers; **Saved** returns to local work. Dictation has first emphasis. iPad uses the same workflows with adaptive layouts and native Pencil tools, not a separate feature tier.

| Job | Implemented journey | Boundary |
| --- | --- | --- |
| Speak → text | Prepare Apple's supported speech model explicitly; record in the foreground or choose audio; retain original words and audio; review, apply optional Light cleanup and approved replacements, save, copy, share or read aloud | No custom keyboard, automatic cross-app paste, background microphone or silent cloud fallback. The Mac's Parakeet, server and Natural refinement choices are not mobile providers. |
| Text → speech | Write, paste or import text; choose an installed Apple voice and rate; read, pause, resume or stop | One reading owner, with controls available across tabs and system media-control integration. No online voice account, document/PDF reader or audio-export promise. Physical background/audio-route behaviour still needs testing. |
| Explain an image | Choose a screenshot/photo; draw with PencilKit, undo/redo; retain editable ink and export a flattened PNG copy | Workbench's own image canvas, not an overlay over another app. No PDF editor or verified redaction tool. |
| Prepare a backdrop | Choose a background; optionally add an image, logo, finished persona and caption; replace individual layers; save, show inside Workbench or export a 16:9 PNG | A bounded composition, not a general design editor, live capture host or verified audience-display route. The Mac remains the USB device-presentation host. |
| Enjoy a wallpaper | Choose a photo or starter; adjust a separate portrait crop; preview and export PNG; finish in Apple's Wallpaper picker | No automatic wallpaper installation, continuous background video or Focus changes. Apple's final wallpaper crop can differ from the exported composition. |
| Reuse | Search saved text and image projects; reopen or deliberately reuse an image's original for another job | Separate crop, ink and layout per project. No implicit Mac sync, clipboard monitoring or coupled edits. |

Photos and Files are the primary image inputs. A small set of starters provides a quick first result; Coast is a generated app asset, not a customer image. Still-image imports are bounded to 64 MB and 50 megapixels. Animated images and PDF are outside this path. Exports render the composition, rather than taking a screenshot, and cap the long edge at 3,840 pixels. Each export uses a distinct temporary PNG and the native share sheet.

Wallpaper and backdrop are independent journeys. Wallpaper retains its chosen aspect with the project, so an iPad rotation does not silently change its crop. Accessible horizontal, vertical and zoom controls accompany gestures. Backdrops keep a fixed landscape output; their foreground image, logo, persona and caption are optional. Imported artwork is not automatically turned into a labelled persona card.

## Selected-photo handoff

[The photo handoff contract](photo-handoff.md) owns this additional, optional job: native camera or selected Photos input → a durable local copy → explicit private iCloud send → Mac arrival. Tools and Saved remain the two tabs. Whole-library sync is outside this feature. Default builds keep cloud access off; a signed paired Preview and a real transfer test are required before claiming device delivery.

## State and lifecycle

- `MobileDocument` keeps a versioned manifest and immutable original assets in the app's own container. Validated writes are atomic; an unreadable or unsupported library pauses writes and preserves its bytes.
- A project owns its edits. Reuse shares the original asset by explicit choice and starts independent edits. Removing a project currently retains imported assets for recovery and other references; it is not a storage-cleanup command. Export important work before uninstalling the app.
- Original transcript text stays separate from editing and deterministic cleanup. Copy and Share are deliberate actions and never submit a message. Save failures remain visible rather than being reported as success.
- Recording is foreground only, capped at five minutes. Imported audio is capped at 64 MB and 30 minutes. Backgrounding, interruption and cancellation release the microphone. Recoverable audio remains available for retry or explicit discard; stale work cannot publish a cancelled result.
- `SpeechAnalyzer`/`SpeechTranscriber` check device, locale and installed assets. Preparation may download Apple's model assets through an explicit action; recognition has no fallback to a different service. A successful Simulator build does not establish device model availability or speech quality.
- Reading uses installed Apple voices through `AVSpeechSynthesizer`. Starting capture stops reading; a new reading supersedes the old one. Media controls and audio interruptions have app-owned state, with physical-device routing and background acceptance still pending.
- **Present on this device** displays only the composition inside Workbench. **End** restores the controls and previous idle-timer state; leaving the foreground releases the keep-awake request. It does not alter wallpaper or another app.
- Dynamic Type, VoiceOver traversal, touch targets, light/dark appearance, Pencil behaviour and reduced-motion settings need native acceptance evidence beyond a compiling accessibility label.

## Native architecture and platform limits

The `WorkbenchMobile` target uses SwiftUI with UIKit, PhotosUI, PencilKit, AVFoundation, Speech and MediaPlayer. Its deployment target is iOS/iPadOS 26. It is an iPhone/iPad app, not a Catalyst or Mac overlay target. It shares the selected-photo state/store/CloudKit sources in `PhotoHandoffKit` plus three portable text sources with the Mac: `TextPrimitives.swift`, `DictationCleanup.swift` and `CorrectionRule.swift`. It does not link StageKit, Carbon, AppKit, FluidAudio or Mac shell-based reading.

| Source owner | Responsibility |
| --- | --- |
| `Mobile/Workbench/WorkbenchApp.swift`, `SavedView.swift` | Tools/Saved navigation, shared operation ownership and reopening local work |
| `MobileDocument.swift`, `MobileStore.swift` | Validated local records, atomic persistence, original assets and independent reuse |
| `SpeechService.swift`, `ReadingService.swift`, `TextWorkspaces.swift` | Explicit speech readiness, recoverable capture, text editing/delivery and installed-voice playback |
| `ImageWorkspace.swift`, `ImageCanvas.swift`, `ImageRendering.swift` | Image imports, PencilKit editing, per-job composition and bounded PNG rendering |
| `Mobile/WorkbenchTests`, `Mobile/WorkbenchUITests` | Storage/rendering checks and native navigation/persistence tests |

The app window is the entry point; Photos/Files import selected items and the system share sheet exports results. No Share extension, App Group sync, custom keyboard, global shortcut, cross-app paste or arbitrary overlay is included. Adding an extension requires its own process-safe import and recovery design.

No ReplayKit broadcast extension, ScreenCaptureKit stream, external-display scene or custom AirPlay receiver is implemented. **Present on this device** does not establish an audience-only control surface. A native meeting app owns its sharing session; receiver visibility requires a real sender/receiver test. Mobile Teams/Zoom browser limitations are documented in [the research record](mobile-research.md#platform-constraints-that-shape-the-ui).

## Build and test

Use full **Xcode 26.1+** with the iOS 26.1+ SDK and an installed iOS 26 Simulator runtime. The Mac SwiftPM build and Developer ID/notarization scripts do not build or distribute this target.

```sh
python3 scripts/mobile-project.py
open Mobile/Workbench.xcodeproj
bash scripts/test-mobile.sh
```

The generator owns the Xcode project and shared **WorkbenchMobile** scheme. Regenerate after adding source or test files; edit `scripts/mobile-project.py`, rather than hand-maintaining generated project entries. The test script regenerates first, selects an available iOS 26 iPhone Simulator by default, disables signing and parallel testing, and writes a fresh `Results.xcresult` with its path printed on completion. CI selects each device family with `MOBILE_DEVICE_FAMILY=iPhone` or `iPad`. To select a specific simulator:

```sh
xcrun simctl list devices available
MOBILE_SIMULATOR_UDID=YOUR-SIMULATOR-UUID bash scripts/test-mobile.sh
```

UI tests launch with a fresh temporary library through the Debug-only `--ui-testing` argument. They do not use an existing Workbench library. Mac global-shortcut tests and their requirement to quit running Mac copies are a separate workflow.

In Xcode, select **WorkbenchMobile**, a simulator and Run for manual inspection. A generic iOS archive with signing disabled checks compilation and packaging; it is not installable distribution evidence. A physical device needs an available, trusted device, Developer Mode and valid development signing/provisioning through an authorised Apple developer team. Mac Developer ID certificates and notarization do not satisfy iOS provisioning.

TestFlight requires a separate archive, signing and App Store Connect workflow. Neither a TestFlight upload nor an App Store submission has been performed by this work.

## Acceptance record

**Verified 13 September 2026 with Xcode 26.6 / iOS 26.5 Simulator.** Counts describe actual completed runs, not a device-quality claim.

| Evidence | Result | What it establishes |
| --- | --- | --- |
| iPhone 17 Pro Simulator | 18 unit tests + 5 UI tests passed; all 5 UI journeys passed again after the playback-strip fix | Storage, original preservation, image rendering, repair/replacement, focus and native navigation/reopening |
| iPad Pro 13-inch (M5) Simulator | 18 unit tests + 5 UI tests passed; all 5 UI journeys passed again after the playback-strip fix | The same contract on iPad, including its native floating tabs |
| Manual iPad Simulator | Starter backdrop, portrait/landscape presentation, End back to editor, PNG share-sheet handoff; reading Pause/Resume and Stop through the persistent control observed | In-app interactions with synthetic content; no external receiver or physical audio-route claim |
| Shared Mac behavior | Mac debug build passed; 43 correction transaction checks and 13 draft cleanup checks passed | Extracting the three shared sources preserves the affected Mac contracts |
| Generic iOS Release archive | Final source archived successfully with signing disabled | Release compilation and packaging; not installable until signed |
| Signed iOS Release archive | Passed with the issued ad hoc profile and Apple Distribution certificate; signature, exact bundle, container and Production environment verified | Local Release Testing export and physical installation are separate checks; no upload |
| Connected iPhone | Physical iPhone 16 Pro Max connected, Developer Mode enabled and exact device included in its Preview profile | No physical camera, microphone/model or playback acceptance result yet |

Actual screenshots are retained in `site/assets/guide/mobile-*-actual.png` and shown in the [mobile guide](https://workbench-mac.vercel.app/mobile/). iPhone images are unedited XCTest attachments from isolated libraries; iPad presentation/paused-reading images were captured through native computer controls. The generated concepts remain separately labelled. Visual review found and fixed an empty playback accessory overlapping Share, a blank app icon and drawing focus stealing; functional tests alone did not establish those visual outcomes.

Local evidence directories for this session:

- `/private/tmp/workbench-ios/Final-iPhone/Results.xcresult` and `Final-iPad/Results.xcresult`: complete 23-test runs.
- `/private/tmp/workbench-ios/Final-iPhone-UI.xcresult` and `Final-iPad-UI.xcresult`: final five-journey reruns and screenshot attachments.
- `/private/tmp/workbench-ios/WorkbenchMobile-final-unsigned.xcarchive`: local unsigned Release archive.

Temporary paths are session evidence, not durable download links. The committed test script and generated Xcode project reproduce the build/test route. CI now runs both iPhone and iPad jobs; report its actual result separately after the source is pushed.

Still pending on a physical device: real microphone permission/denial, model preparation and recognition quality, interruption/force-quit recovery, Lock Screen audio, Bluetooth/AirPlay, Pencil accuracy, memory/energy, VoiceOver traversal, large Dynamic Type, reduced-motion behavior and native meeting recipients. Apple may apply a different final wallpaper crop. iOS 26.0's fallback playback inset compiles but was not exercised by the 26.5 Simulator runs. Simulator success does not satisfy these checks.

The privacy manifest describes app-owned and user-selected file metadata access (`C617.1`, `3B52.1`), with no collected-data or tracking declarations. See [Apple's API categories and approved reasons](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype). App Store Connect validation remains separate and has not run.

## Platform references

Checked 13 September 2026. Apple documents [running on devices](https://developer.apple.com/documentation/xcode/building-and-running-an-app), [Developer Mode](https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device), [custom keyboard restrictions](https://developer.apple.com/documentation/uikit/configuring-open-access-for-a-custom-keyboard) and [extension storage coordination](https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/ExtensionScenarios.html). [Mobile research](mobile-research.md) links the native baselines and competitor evidence with its review/sample limits.
