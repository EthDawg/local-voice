# Contributing to Workbench Voice

Welcome! A small, useful improvement is a great first contribution. Bug reports, documentation, accessibility checks, design feedback, and hardware testing all count.

## Choose a first step

1. Pick an unassigned [good first issue](https://github.com/EthDawg/local-voice/issues?q=is%3Aissue%20is%3Aopen%20label%3A%22good%20first%20issue%22). Each has starting files and a definition of done. Comment that you would like to work on it so others can coordinate; no invitation or repository write access is needed.
2. For a quick typo or clear small fix, send a PR directly. For a larger feature, start with an [idea](https://github.com/EthDawg/local-voice/discussions) or [feature request](https://github.com/EthDawg/local-voice/issues/new/choose) so we can agree on scope.
3. Need help? Ask on the issue or in [Workbench Discussions](https://github.com/EthDawg/local-voice/discussions). Describe where you got stuck; incomplete attempts are welcome.

**No Mac or no Swift experience?** Open a documentation file on GitHub, click the pencil, make the edit, and follow GitHub's fork-and-pull-request prompts. You do not need to run native checks for a text-only change; say “documentation only” in the PR. A hardware test report can be contributed as an issue comment.

## Build and check

Apple Silicon Mac, macOS 14+, Swift 6.2+, and the macOS 26 SDK. The deployment target is macOS 14; building needs the newer SDK because optional Apple Intelligence support is compiled in. Install current Apple Command Line Tools with `xcode-select --install`, or select a compatible Xcode toolchain. The first build downloads the pinned FluidAudio dependency.

Click **Fork** at the top of this repository, then substitute your GitHub username below:

```sh
git clone https://github.com/YOUR-USERNAME/local-voice.git
cd local-voice
git remote add upstream https://github.com/EthDawg/local-voice.git
git switch -c improve/small-change
bash scripts/doctor.sh
bash scripts/test.sh
bash scripts/build.sh
```

Full Xcode is required to extract Apple Shortcuts metadata for distribution; Command Line Tools still support source development. CI sets `REQUIRE_APP_INTENTS=1` so an undiscoverable action cannot pass packaging. See [integration notes](docs/voice-integrations.md).

The default checks do not download the speech model or require microphone access. They test core state, history, dictionary and cleanup behavior. `bash scripts/build.sh` produces `dist/Workbench Voice.zip` without installing it.

For microphone, speech-engine, or paste changes, quit any running Voice app and use `bash scripts/install.sh` to test the installed bundle. This **updates the separate Voice Preview app**, preserves its previous version as a rollback ZIP, downloads/prepares the model, and runs a speech round-trip. Use only synthetic text/audio for shared examples. Accessibility is optional for paste; microphone permission is needed for recording. See [privacy and limits](README.md#privacy-and-limits) and [validation](docs/validation.md).

CI runs the same tests and package build on a fresh Apple Silicon macOS runner. A maintainer may need to approve the first workflow run from a new fork. CI cannot prove live microphone permissions, cross-app paste, screen sharing, or physical hardware behavior; document relevant manual checks in the PR.

## Find the code

| Area | Start here |
| --- | --- |
| Dictation state and recording | `Sources/LocalVoice/AppModel.swift` |
| Recent transcripts | `Sources/LocalVoice/CaptureHistoryView.swift`, `Core.swift` |
| Cleanup and regression cases | `Sources/LocalVoice/Cleanup.swift`, `CleanupChecks.swift` |
| Focus, clipboard, automatic paste | `Sources/LocalVoice/TextDelivery.swift` |
| Capture panel and quick controls | `Sources/LocalVoice/CapturePanel.swift`, `QuickControls.swift` |
| Core / keyboard checks | `Sources/LocalVoice/CoreChecks.swift`, `InputChecks.swift` |
| Shared suite appearance and switcher | `Sources/LocalVoice/Workbench.swift` |

The [suite contract](https://github.com/EthDawg/local-voice/blob/main/docs/workbench.md) owns shared behavior. `Workbench.swift` is currently mirrored in both repositories. App-specific changes need only one PR; shell changes need linked PRs in both repositories and matching file contents. Discuss extraction before introducing a shared package.

## Send your change

Keep one clear purpose per PR and follow the surrounding Swift style. Add a focused regression check for a behavior change when practical. Avoid unrelated formatting and generated build products.

```sh
git add path/to/changed-file
git commit -m "Describe the user-visible improvement"
git push -u origin improve/small-change
```

Open **Compare & pull request** on your fork. Fill in the short template: what improves, the linked issue (`Closes #123`), and what you checked. Use a draft PR for early feedback. For visible UI changes, include a screenshot or short recording with synthetic content. If a check cannot be run, say why instead of claiming it passed.

The maintainer reviews scope, clarity, data safety, and validation; follow-up edits on the same branch update the PR. There is no CLA or DCO signing step. Your contribution is provided under this repository's [MIT license](LICENSE); only contribute code and assets you have the right to share. AI-assisted contributions are welcome with the same review and testing expectations: understand the change and never include private prompts, recordings, or credentials.

## Project direction and review

EthDawg maintains the project and merges releases. We prefer small independent native utilities, local processing, optional permissions, explicit actions, and recoverable user data. New network services, telemetry, large dependencies, data migrations, or suite-wide changes need a design discussion first. Existing GitHub issues are the backlog; there is no separate project board to maintain. Response times vary; no support SLA is promised.

Be kind and specific in feedback. Read the [community expectations](CODE_OF_CONDUCT.md) and use [private security reporting](SECURITY.md) for vulnerabilities.
