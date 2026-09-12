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
