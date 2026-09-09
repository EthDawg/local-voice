# Workbench Preview 1.3

Local test release · 9 September 2026

Voice and StageMark remain two independent native apps. This release connects preparation and recovery through a small resource library and reusable presentation scenes, with a separate installation channel that retains its data across updates.

## Try the new workflows

- **Voice — Control–Option–J:** search saved prompts, links, videos, decks and files by name, product or persona. Copy exact text, open a local resource, or reconnect a missing file. Save a transcript as a prompt, or use Command–Shift–S inside Voice to review and save clipboard text.
- **StageMark — Control–Option–P:** add a customer backdrop, position a phone frame and save the layout under a memorable name. Export a PNG or apply it to the current display, with desktop restoration available afterward.
- **Both:** Preview is installed alongside production, with a separate identity and its own settings/data. Run one edition of each app at a time to retain familiar shortcuts. Quit Preview before updating it; the installer keeps data and a rollback archive.

Prompts, persona labels and notes are plain local content. The library does not act as a persona, store a password vault or send messages. Files remain in their existing locations; download cloud files before an offline demo. JSON exchange includes metadata, prompts, notes, links and file paths, not the media or access bookmarks. Imported resources cannot execute applications or scripts through the library's Open action.

Unfinished resource edits are preserved if the clipboard shortcut is pressed again. Save or cancel the current resource before starting another prompt.

## Keep the ecosystem open

Resource links open in the default browser, and documents open in their existing apps. A saved Excalidraw link or exported diagram, a local video, a deck and an import fixture all use the same simple library. Workbench does not embed another whiteboard, video editor or automation platform. The versioned JSON format is a portable starting point for future integrations; there is no plugin runtime or agent protocol in this release.

Chrome password updates are deferred. Google documents CSV import and Chromium handles conflicting saved passwords with explicit selection; a supported cross-profile update integration has not been established. No Chrome password database was read or changed. [Google password import](https://support.google.com/chrome/answer/13068232?hl=en), [Chromium importer](https://github.com/chromium/chromium/blob/main/components/password_manager/core/browser/import/password_importer.cc).

Native screenshot capture and autonomous persona conversations are also deferred. StageMark retains its existing annotation tools; QuickTime remains responsible for live iPhone video and manual movie-window placement. There is no Windows application in this release. StageMark now packages Intel and Apple Silicon code, while Voice retains its Apple Silicon speech dependency.

## Verified local Preview

The signed installed Voice Preview (build 20260908224017) passed 21 core, 16 cleanup and 36 library checks plus model checks. StageMark (build 20260908224244) passed 35 native tests and 253 assertions. Seven installer regressions cover preservation, identities, process inventory and rollback; four release-script checks also pass. Both Preview apps are Developer ID signed local builds; neither has been notarised or publicly released. The existing App Store submission was not changed.

Native acceptance on 9 September verified first-launch copies of all 100 Voice captures, drafts, dictionary and reading settings, plus StageMark's saved boards and drawing preferences. Production bundles, data and preferences were preserved. Preview data survived signed app replacements and restarts.

Voice's prompt save, persona search, favorites, exact multiline copy, clipboard-save shortcut, new-prompt shortcut, JSON export/import without duplicates, local-file opening after a move/rename, and browser-link opening were exercised. Recall now focuses search after the editor is ready, and recall/clipboard shortcuts preserve unfinished drafts. Light, dark and smaller-window layouts were inspected, and the shared appearance was returned to System. Global hotkey registration passes native checks; physical keyboard recall from other apps remains a user acceptance check because automated app-targeted keys do not establish system-wide delivery.

StageMark imported the supplied reception image, saved its customer name and phone position, exported a 1920 × 1080 PNG, and retained the scene through two updates. A delayed macOS wallpaper response found during UI testing is now confirmed asynchronously, with recovery retained on timeout. Restoration across an app update and a fresh apply/restore cycle both passed. Readback confirmed all three attached displays returned to their original wallpaper and the completed recovery journal was removed. Voice's suite switcher opened StageMark Preview.

The customer scene and exported image are ready locally; Voice's library also includes that image and an Excalidraw launch link. Synthetic prompt entries were removed after testing. No live microphone, physical iPhone/Intel Mac, remote audience, display hot-plug/Spaces, or new sandbox acceptance is claimed. File reconnection failure paths have automated coverage; a physically disconnected source volume was not tested.

The overnight interruption was traced to the 20-minute screensaver followed by immediate locking. The new [unattended-session helper](unattended.md) keeps both the system and display awake only for a chosen command and releases its assertions afterward. It changes no authentication settings. Assertion lifetime, cancellation and exit-status checks pass; this is not a claim of a full overnight idle trial.

Canonical release workflow: [Developer ID and Preview updates](../scripts/release/README.md). Canonical suite contract: [Workbench](workbench.md). StageMark source and QA live in its own repository.
