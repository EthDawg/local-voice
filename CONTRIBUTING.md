# Contributing to Workbench

A small, useful improvement is a good first contribution. Bug reports, documentation, accessibility checks, design feedback and hardware testing all count.

This branch combines Voice and StageMark into one app. Workbench's purpose is dependable everyday Mac utilities for speaking, annotating and presenting. Improve a concrete workflow and compare against what macOS already offers before adding another feature.

## Choose a first step

1. Check the [open issues](https://github.com/EthDawg/local-voice/issues). An unassigned [good first issue](https://github.com/EthDawg/local-voice/issues?q=is%3Aissue%20is%3Aopen%20label%3A%22good%20first%20issue%22) is a useful starting point. Comment that you want to take it so others can coordinate; no repository write access is needed.
2. A typo or clear, small fix can go directly to a PR. Discuss a larger feature in an issue or [Discussions](https://github.com/EthDawg/local-voice/discussions) first. Agree the smallest useful outcome and who is working on it.
3. Ask for help on the issue when stuck. Incomplete attempts and draft PRs are welcome. Coordinate before replacing work another contributor has offered to do.

**No Mac or no Swift experience?** Edit documentation through GitHub's pencil and fork/PR workflow. Say “documentation only” in the PR; native checks are unnecessary for that change. Hardware findings can be an issue comment with the Mac/device/OS versions and steps tried.

## Build and check

Use an Apple Silicon Mac, macOS 14+, Swift 6.2+ and the macOS 26 SDK. The deployment target and build SDK are different: optional newer Apple features need the newer SDK to compile. Full Xcode is required for App Intents metadata; Command Line Tools support source development.

Fork this repository, then substitute your username. Check out the branch or PR you intend to work on; default-branch and historical release contents may differ from this consolidation.

```sh
git clone https://github.com/YOUR-USERNAME/local-voice.git
cd local-voice
git remote add upstream https://github.com/EthDawg/local-voice.git
git switch -c improve/small-change
bash scripts/doctor.sh
bash scripts/test.sh
bash scripts/build.sh
```

The first build downloads the pinned dependency. The default test script covers release tooling, core and integration behaviour, provider contracts/transport, keyboard practice and StageKit. It does not need a speech-model download or microphone access. The ordinary build creates the ad-hoc `dist/Workbench.zip`; it does not install an app.

For persistent native testing, use the [signed Preview build/install commands](README.md#build-and-install-preview). A Developer ID Application identity is needed for that workflow. Quit the running Preview before installing, and quit legacy Voice/StageMark instances when checking global shortcuts. The installer preserves the previous Preview archive and saved data; it does **not** run the speech round-trip or prepare a model until the app is opened.

`REQUIRE_APP_INTENTS=1` makes packaging fail if real action metadata cannot be extracted. A successful source compile does not establish Shortcuts discovery. See [the integration guide](docs/voice-integrations.md).

CI runs automated checks and packaging on a macOS runner. A maintainer may need to approve a fork's first workflow run. For a behavioural change, add or run focused checks for the actual risk. Record relevant manual evidence: microphone permission/cancellation, cross-app paste, device disconnect/reconnect, keyboard conflicts, light/dark layout or other affected behaviour. Use synthetic content in public screenshots and recordings. If something cannot be tested, say why.

## Find the code

| Area | Start here |
| --- | --- |
| App lifecycle, menu bar and shared navigation | `Sources/LocalVoice/main.swift`, `WorkbenchHome.swift` |
| Dictation, recent captures and delivery | `Sources/LocalVoice/AppModel.swift`, `CaptureHistoryView.swift`, `TextDelivery.swift` |
| Recognition selection and transport | `Sources/LocalVoice/RecognitionProviders.swift`, `ModelSettingsView.swift`, `ProviderChecks.swift` |
| Cleanup and regression cases | `Sources/LocalVoice/Cleanup.swift`, `CleanupChecks.swift` |
| Unified keyboard assignment and practice | `Sources/LocalVoice/KeyboardCoach.swift`, `KeyboardCoachChecks.swift` |
| StageKit's public boundary | `Sources/StageKit/StageKitController.swift` |
| Drawing, boards, timer and presentation | `Sources/StageKit/AppCoordinator.swift`, `DemoScenes.swift`, `DemoPresentation.swift` |
| Device capture and Apple alternatives | `Sources/StageKit/DemoCapture.swift`, `NativePresentationApps.swift` |
| Identity, appearance and legacy-data import | `Sources/LocalVoice/Workbench.swift`, `Sources/StageKit/Workbench.swift` |
| Packaging and Preview install | `scripts/build.sh`, `scripts/release/preview.py`, `scripts/release/config.json` |

[The product contract](docs/workbench.md) owns app-wide behaviour; [the implementation map](docs/design.md) describes boundaries. Voice currently lives in the `LocalVoice` executable target; `StageKit` is a separate Swift library within the same process. Neither module should grow its own app lifecycle or another menu-bar icon. The original checkouts are provenance, not a requirement to maintain matching implementation PRs in two repos.

## Send your change

Keep one clear purpose per PR. Follow surrounding Swift style and avoid unrelated formatting or generated build products.

```sh
git add path/to/changed-file
git commit -m "Describe the user-visible improvement"
git push -u origin improve/small-change
```

Open **Compare & pull request** on your fork. Explain what improves, link the issue, and describe the evidence and limitations. Use `Closes #123` only when the change fully resolves it. Draft means ready for feedback; it does not mean ready to release. Screenshots or short recordings help with UI changes.

AI-assisted work has the same ownership and testing expectations. The submitting person must understand the change and check its claims. Never include private prompts, recordings, credentials or customer assets. There is no CLA or DCO signing step. Contributions use this repository's [MIT license](LICENSE); preserve upstream notices and contribute only material you have the right to share.

## Proposed Ethan–Matt working agreement

**This is a proposal for the two people to agree, not a statement of existing GitHub roles, branch protections or delegated publishing authority.**

- Ethan and Matt share direction and review meaningful changes from each other.
- Either can experiment. Claim a shared issue before implementation; coordinate if the work overlaps an existing contribution.
- Keep independent features in separate PRs. Automated checks and AI review support the other person's review.
- Agree together before introducing services, telemetry, broad permissions, major dependencies, migrations or a public release.
- AI can investigate, implement and draft. Public replies and commitments follow the submitting maintainer's explicit delegation. Writing in Ethan's style alone does not grant permission to speak or commit for him.
- Keep consequential WhatsApp decisions in the relevant issue or PR. Issues are the work queue; releases are the download and change record.

A maintainer review should establish scope, clarity, user-data preservation and relevant validation. A green build, merge, signed archive and published release are distinct states. Keep previews labelled and verify the actual packaged app before promotion. Response times vary; no support SLA is promised.

Be kind and specific. Read [community expectations](CODE_OF_CONDUCT.md) and use [private security reporting](SECURITY.md) for vulnerabilities.
