# Persona overlays

A persona is a finished image, reused over a browser or inside a saved mobile scene. Workbench preserves the artwork's proportions and existing transparency; it does not generate a new card design or remove a baked background.

## Over a browser

Open **Persona overlay…** from Workbench's menu, or **Personas…** in Present a device. Import an image or paste one copied from a browser or Finder, then choose **Show over browser**.

Drag the image to move it. The library also offers a Position menu and size slider. Enable **Lock position · clicks pass through** to interact with the software underneath. Reopen the library to unlock, resize, change or hide the persona. The floating image starts hidden when Workbench launches.

Share the whole display to include this floating window. Browser-tab sharing does not include it. Inclusion in individual-window capture depends on the meeting app's capture behavior and needs receiver-side validation; do not promise it.

## In a mobile scene

Choose **Add persona…** beneath the scene preview, select an image, then **Use in scene**. Drag it in the preview or use its Position and Size controls. The same layer is rendered in the preview, exported PNG and live device presentation. It stays separate from the backdrop and logo.

Starting a scene hides the independent floating persona to avoid showing two copies. Use the persona saved in the scene when sharing the presentation window.

## Storage and recovery

The shared scene directory owns normalized PNG copies and `persona-library.json`. `persona-overlay.json` stores desktop placement and lock preference separately from each scene's placement. Removing a library entry retains its image because saved scenes can reference it. Existing scenes without a persona continue to decode unchanged.

Unreadable or newer archives are preserved. A missing persona must be replaced or removed before presenting or exporting its scene. Tests use synthetic artwork and isolated directories, not customer assets.

This feature does not add a browser extension or change the recording and presentation HUD designs.
