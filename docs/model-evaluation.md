# Model change evidence

Use this template in a pull request that changes a default recognition/refinement engine, model or model dependency. It is a process/template, not an existing accuracy benchmark or automatic quality guarantee. No evaluation corpus has yet been claimed as completed.

## Scope and inputs

- Job under test: raw recognition / prepared dictation / text refinement / speech generation.
- Current app commit, candidate commit, macOS, hardware/RAM and power mode.
- Provider and runtime version, configured model, immutable model revision or file hash if available. Mark a user-managed server's configured name as configured, not independently verified.
- Corpus version, item IDs, source/license or documented consent. Commit only redistribution-safe data. Do not collect users' history automatically.
- Use a small fixed set initially (roughly 15–30 varied samples): short and longer speech, pauses, noise, several accents, names, numbers/times, lists, corrections and silence. A synthetic fixture tests wiring; it does not represent natural speech by itself.
- Keep a few held-out samples so tuning to the fixture does not masquerade as general improvement.

## Run the comparison

1. Run the current and candidate implementations on identical input bytes and settings. Separate cold preparation/download from warm inference. Do not time a network download as transcription.
2. Repeat timed cases enough to expose variation; record raw measurements and failures rather than only the best run. Stop/cancel and unavailable-provider behavior require their own checks.
3. Save raw engine output and prepared output separately. For prepared dictation, record dictionary/refinement/delivery settings. A raw CLI result cannot establish the app's cleanup quality.
4. Inspect proper names, numbers, negations, omissions and invented text. Record optional word-error rate alongside these checks; punctuation/case normalisation must be declared. For refinement, judge fidelity to the supplied transcript separately from audio recognition.
5. Report time to usable text/audio, warm/cold latency, peak memory if measured, downloads/storage, and any cost/network requirement. Mark unmeasured fields explicitly.
6. State the user-visible gain, regressions, fallback and rollback. A default change requires a maintainer's decision; a small average gain does not excuse a critical meaning change.

A simple CSV is enough; keep one row per input/engine/repetition:

```csv
run_id,item_id,job,app_commit,engine_version,model_identity,identity_verification,hardware,settings_id,repeat,cold,latency_ms,name_errors,number_errors,meaning_error,output_path,review_note
```

Keep corpus metadata and settings in a small accompanying Markdown/JSON file. Hash or otherwise identify input files. Do not copy private output into a public report. Evaluations are evidence artifacts, not a new production database.

## PR decision

| Question | Evidence / answer |
| --- | --- |
| What became better for a user? | |
| Same inputs/settings/hardware? | |
| Names, numbers, omissions and meaning regressions? | |
| Cold/warm latency and resource tradeoffs? | |
| Cancel, offline, unavailable and recovery behavior? | |
| Old user data preserved? | |
| What remains untested? | |
| Keep current / offer optional candidate / change default? | |
| Rollback source/model revision? | |

Interface tests and output-quality comparisons answer different questions. Keep both. No source or model update should silently alter an active recording, the selected privacy boundary or existing originals.
