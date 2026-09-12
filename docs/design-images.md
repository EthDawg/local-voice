# Product-guide image experiments

Generated with the built-in image-generation tool on 12 September 2026. These are design concepts, not shipping screenshots. All selected files are stored in `site/assets/guide/`; the public guide labels their status.

## Jobs study, first experiment

File: `site/assets/guide/jobs-study.png`

Use case: ui-mockup. Asset type: durable Workbench product-guide illustration, landscape 3:2, polished editorial product design, not a marketing poster.
Create three clearly separated numbered horizontal rows with generous whitespace on a warm off-white background, finely rendered native Mac windows and restrained graphite panels. Large title "The right control for the job." Small subtitle "Workbench · interaction study".
Row 1 title "01  Dictate on your Mac". A Mac text-editor window with fictional short bullet note. At its bottom a small charcoal recording capsule with red dot, "0:18", short waveform, square stop button, chevron. Nearby a restrained expanded detail panel showing "Recording", "Light cleanup", "Stop", "Cancel". Include short caption "The Mac field receives your text."
Row 2 title "02  Present a phone". A landscape presentation window showing a single upright iPhone over a quiet coastal background. A TINY tile at the right edge centre contains only outline phone icon, thin vertical divider, right chevron. Small open popover illustration outside window shows "Presentation", "Change source…", "Reconnect", "End presentation". Show separate physical phone held at side with native keyboard microphone highlighted. Caption "Type or dictate on the phone."
Row 3 title "03  Explain a browser demo". A Mac browser fictional service dashboard, a simple hand-drawn circle on a card, and a small round persona portrait card at bottom right labelled "Site manager". Separate modest app controls labelled "Move · Resize · Lock". Caption "The browser keeps normal page input."
Use actual readable concise labels, no invented brand logos, no neon, no purple gradients, no fake broadcast badge, no word Live or Demo on collapsed tiles, no microphone anywhere in phone-presentation controls. Maintain clear boundary between audience-visible content and utility controls. Footer "Design concept · not a screenshot". Elegant system sans typography, hairline borders, realistic but quiet shadows; focus on usable UI, not decoration.

## Refined jobs study, selected for the guide

File: `site/assets/guide/jobs-refined.png`. Corrects the settings control, phone-video parity and persona position from the first experiment.

Refine this Workbench product-guide concept while preserving its three-row composition, restrained native styling, typography and exact three jobs. Make ONLY these corrections:
1 In the expanded recording panel, replace the interactive blue checkbox and the filler caption with plain, non-interactive text: "This recording" then "Light cleanup". Add small note "Changes apply next time." Preserve Stop and Cancel. This is frozen per-recording status, not a checkbox.
2 The phone inside the middle presentation window must display the SAME simple Notes editor state as the physical phone on the right (a text field titled "Client update", keyboard visible). This is a video preview of the physical device. The small presentation tile must remain phone icon, divider, chevron only. No microphone controls in its menu.
3 Move the small Site manager persona card so it sits INSIDE the lower right corner of the browser content, overlaying that content. Remove its green availability dot. The card is a static persona image, not a person online. Keep its plain label and friendly portrait.
4 Footer must say "Design concept · not a screenshot".
Do not add other modes, features or text. Professional editorial visual, calm, clear, hand-crafted feel.

## Earlier studies retained

- `voice-experiments.png`: compact capsule, labelled strip and expanded details.
- `presentation-study.png`: phone/chevron control and separate persona artwork.
- `voice-placement-study.png`: anchored expansion, snap hints and named positions.

These earlier studies were generated and reviewed in the task before this specification. Their frozen-setting and input-ownership details are governed by `product-spec.md`, not incidental generated labels.


## Example persona artwork

File: `site/assets/guide/site-manager-persona.png`. Generated as a reusable finished persona image, not an app screenshot.

Prompt brief: a fictional friendly woman working as a site manager, wearing a white hardhat and olive work shirt, inside a warm gold circular portrait with a restrained dark teal outline and a matching lower name plate reading “Site manager”. Transparent background outside the card, no real company marks, no online-status dot. Polished, approachable illustration for a browser or phone demonstration.

The generated PNG has an alpha channel. Its actual import, floating display and placement inside a scene were checked in Workbench Preview.

## Commodity utility studies — 13 September 2026

Four new image-generation experiments were shown inline during the review and retained in `site/assets/guide/`. They are concepts, not screenshots. The actual implementation map is in `commodity-strategy.md`; the feature contracts are in `utility-comparison.md`.

| File | Generation brief and decision |
| --- | --- |
| `commodity-first-study.png` | Explore four useful moments: listening, exporting a board, presenting a phone, recalling a file. Rejected the generated reversed device-video direction, an unsupported audience-view verification indicator, and word highlighting without timing data. Retained for traceability. |
| `commodity-architecture-first.png` | Stable jobs above small contracts and replaceable implementations, with user-owned originals and a reviewed upgrade loop. Rejected the camera metaphor, implied file-version history and an overly literal hardware-rack illustration. It also omitted Saved resources. |
| `commodity-features-refined.png` | Four precise native UI panels: ±15-second reading navigation in existing audio; board-only Copy/PNG export; a resizable Mac scene showing phone video with icon/chevron controls; search/selection/Return to deliberately copy a saved resource. No word highlighting, invisible audience controls or reverse phone input. This grounded the chosen interactions. Existing app styling/layout remains the implementation owner. |
| `commodity-architecture-refined.png` | One app and five explicit jobs; native Mac controls; recognition/refinement/speech-generation modules; candidate → same inputs → quality/speed comparison → reviewed release; keep originals, read older files, preserve unknown formats. Phone video points to a Mac scene. This is direction; voice engines do not serve every non-voice utility. |

Final image-generation prompt for the architecture refinement:

> Make a professional product architecture decision illustration for a small free native Mac utility called Workbench. Wide landscape, white background, restrained mint/charcoal, clean sans serif. Exact title 'One app. Five useful jobs.' Top row five simple line icons and labels: 'Dictate', 'Read aloud', 'Annotate', 'Present a device', 'Saved resources'. Beneath show one understated long bar 'Native Mac controls'. Beneath show three equally sized small modules 'Recognition', 'Text refinement', 'Speech generation'. Caption directly underneath 'Replace an engine when a measured improvement earns it.' Bottom left show an ordered review sequence as four simple cards: 'Candidate' → 'Same test inputs' → 'Compare quality + speed' → 'Reviewed release'. Bottom right protected outlined box with document icon and exact text 'Keep originals' then 'Read older files' then 'Preserve unknown formats'. Do not draw arrows that imply every job depends on models; modules apply to voice jobs only. Five jobs must all be present; no camera metaphor, no plugged hardware racks, no claims of automatic updates or saved version history. A small separate inset with an iPhone screen sending a single arrow to a Mac display, labeled 'Phone video → Mac scene'. This means video display only, no remote phone input. Footer 'Architecture direction • actual boundaries are recorded in the specification'. Precise professional diagram, not marketing poster; no invented labels or paragraphs.

Actual `reading-playback-actual.png` and `library-recall-actual.png` were captured through native computer controls using production UI/methods in disposable apps. Their diagnostics identify the isolated state and simulated library effects. `board-export-actual.png` is the actual PNG produced by the native Save action, not generated artwork.
