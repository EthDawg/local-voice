# Workbench Preview 1.3

Local test release · 9 September 2026

Voice and StageMark remain two independent native apps. This release connects preparation and recovery through a small resource library and reusable presentation scenes, with a separate installation channel that retains its data across updates.

## Try the new workflows

- **Voice — Control–Option–J:** search saved prompts, links, videos, decks and files by name, product or persona. Copy exact text, open a local resource, or reconnect a missing file. Save a transcript as a prompt, or use Command–Shift–S inside Voice to review and save clipboard text.
- **StageMark — Control–Option–P:** add a customer backdrop, position a phone frame and save the layout under a memorable name. Export a PNG or apply it to the current display, with desktop restoration available afterward.
- **Both:** Preview is installed alongside production, with a separate identity and its own settings/data. Run one edition of each app at a time to retain familiar shortcuts. Quit Preview before updating it; the installer keeps data and a rollback archive.

Prompts, persona labels and notes are plain local content. The library does not act as a persona, store a password vault or send messages. Files remain in their existing locations; download cloud files before an offline demo. JSON exchange includes metadata, prompts, notes, links and file paths, not the media or access bookmarks. Imported resources cannot execute applications or scripts through the library's Open action.

## Keep the ecosystem open

Resource links open in the default browser, and documents open in their existing apps. A saved Excalidraw link or exported diagram, a local video, a deck and an import fixture all use the same simple library. Workbench does not embed another whiteboard, video editor or automation platform. The versioned JSON format is a portable starting point for future integrations; there is no plugin runtime or agent protocol in this release.

Chrome password updates are deferred. Google documents CSV import and Chromium handles conflicting saved passwords with explicit selection; a supported cross-profile update integration has not been established. No Chrome password database was read or changed. [Google password import](https://support.google.com/chrome/answer/13068232?hl=en), [Chromium importer](https://github.com/chromium/chromium/blob/main/components/password_manager/core/browser/import/password_importer.cc).

Native screenshot capture and autonomous persona conversations are also deferred. StageMark retains its existing annotation tools; QuickTime remains responsible for live iPhone video and manual movie-window placement. There is no Windows application in this release. StageMark now packages Intel and Apple Silicon code, while Voice retains its Apple Silicon speech dependency.

## Verification and next acceptance step

The signed installed Voice Preview passed 21 core, 16 cleanup and 36 library checks plus model checks. StageMark passed 33 native tests and 223 assertions. Seven installer regressions cover preservation, identities, process inventory and rollback. The installed production app bundles remain unchanged. Both Preview apps are Developer ID signed local builds; neither has been notarised or publicly released. The existing App Store submission was not changed.

Visual acceptance is still pending because the Mac locked before the installed Preview apps could be exercised. When unlocked, check first-launch settings/history copies; keyboard recall; prompt save/search/copy; local-file open/reconnect; light/dark layout; scene import/drag/export/apply/restore; restart persistence; and suite switching. No live microphone, iPhone, physical Intel Mac, remote audience or new sandbox acceptance is claimed.

Canonical release workflow: [Developer ID and Preview updates](../scripts/release/README.md). Canonical suite contract: [Workbench](workbench.md). StageMark source and QA live in its own repository.
