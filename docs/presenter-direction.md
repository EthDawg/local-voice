# Presenter direction

Decision recorded 10 September 2026. The sketches express ideas, not a target interface.

## One useful promise

**Prepare a branded mobile demo once. Start it easily. End it cleanly.**

Build one presenter-facing app around this workflow, with internal modules for scenes, branding, capture, annotations and breaks. Let a saved demo be the starting point and Start demo the obvious action. Reveal detailed adjustments when needed. Delight means fewer decisions, reliable recovery and almost no instruction-based onboarding. A smaller feature that completes the job is preferable to a larger toolkit that needs explaining.

## Explain it to three people

- **Someone who rarely presents:** “It makes a phone demo look ready for an audience. Save the background and logo once, open the demo, and close it when you finish.”
- **A presales manager:** “A Mac toolkit for reusable, branded mobile demos that reduces preparation between customer presentations. We are proving that workflow before expanding into team-wide demo operations.”
- **An individual presenter:** “Set up a mobile demo once and bring it back for the next presentation, with drawing tools and a break timer close at hand.”

## Current capability and future scope

The current direct-edition Preview edits and saves local scenes, imports branding, opens a full-screen device stage, and ends that stage and its capture. Device access depends on a connected, unlocked, trusted device and the required macOS permission. End demo returns to the editor. Hardware recovery coverage remains documented separately in [demo-mode.md](demo-mode.md).

Browser profiles, personas, tenant rotation, password updates, team synchronization, geography-specific content and X-Ray value overlays are future concepts. “One-click pack up everything” is not a current capability claim.

If session orchestration is added, record exactly which windows, processes and resources the session created. Cleanup acts on those owned resources and preserves pre-existing work. Versioned team content can describe approved scenes, messages, audience and geography; credentials belong in a separate secure credential system, referenced rather than copied into content files.

## Keep the product small

Split an app only when it serves a frequent independent job, benefits from a separate lifecycle or permissions, and works without making users coordinate multiple apps. Code modularity alone does not justify another app. Voice can remain independent because its everyday purpose extends beyond presenting.

First remove logo-import friction with native supported formats, paste and reuse. [Logo.dev](https://www.logo.dev/docs/introduction) offers domain/name retrieval and requires an API token; evaluate a provider only if finding logos remains a demonstrated bottleneck. No new account is needed now.

Defer X-Ray, team sync and a design kit until repeated use proves the core workflow saves effort without training. Judge additions by steps removed and reliable outcomes, not feature count.
