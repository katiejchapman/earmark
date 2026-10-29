# Validation

- Xcode 26.6; iPhone 17 Pro simulator running iOS 26.5.
- 20 checks covered: 14 library/resolver/playback checks and 6 interface checks. The full run passed 19; after correcting tap/drag gesture composition, both affected archive interaction checks passed in a focused rerun.
- Imported M4A was copied into app storage, its original was removed, the library reopened, playback restored the saved position, and playback advanced successfully.
- An actual MP4 containing AAC audio was imported, deduplicated, its original removed, and its saved copy successfully loaded after reopening the library.
- Folder renaming preserves contents and positions, rejects conflicting names, and survives reopening. Swipe deletion returns recordings to Archive.
- Press-and-drag from Archive into a folder passed, including persistence after terminating and reopening the app.
- Tapping an archive item offers loading, renaming, marking listened/unlistened, moving, and deleting. Renaming and loading passed together with dragging. Listened status persists and older backups without that field still open.
- Reset clears audio, errors, and the last-player selection without removing the archive or saved positions. Import audio appears above playback errors.
- Interface tests use separate libraries so test folders and URLs do not enter the normal preview library.
- Repeated file imports match SHA-256 content, including renamed files and older libraries without saved hashes; folder and position are retained. Distinct file contents remain separate.
- Link matching handles fragments, host casing, default ports, Archive.org server aliases, and resolved page/direct-audio aliases. Meaningful query parameters remain distinct.
- Disc, centered light icon, charms, silver scrubber, speaker mesh, compact controls, lowercase archive heading, and small rounded reset button were visually inspected. Latest screenshot: `Preview/earmark-ios-v3.png`; previous previews remain intact.
- Files import picker opens and cancels correctly.
- Folder and link persistence across app termination passed.
- Theme choice persists across app termination.
- Unsigned physical-iPhone build succeeded (`generic/platform=iOS`). Installing on a phone requires selecting a signing team in Xcode.
- HTML entry points and every numbered preview match the hashes recorded before iOS work started.

Result bundles for this machine: `/tmp/earmark-archive-final-tests.xcresult` (full run before the final gesture adjustment), `/tmp/earmark-archive-interaction-v2-tests.xcresult` (both archive interaction checks passed after the adjustment).

Still requires a physical iPhone: lock-screen/background audio, Bluetooth/headphone route changes, phone-call interruptions, and receiving a document from another app through Open in Earmark. The document types and background-audio capability are configured; these device behaviors have not been claimed as tested.


2026-10-25 sleep and archive update:
- Added 5/15/30/45/60-minute sleep timers with cancellation and automatic pause. The playback test confirms expiration pauses an actual local audio asset.
- Explicit Save link leaves the player unchanged. Pasted links still save immediately.
- Player displays its current folder (Unarchived for ungrouped recordings).
- Scrubs of at least 60 seconds retain a persisted return position. The intended destination saves before the asynchronous seek completes. Local-audio tests verify seeking, returning, small skips, and persistence.
- Folder titles now expand/collapse contents; a separate ellipsis menu offers Rename. Disabled scrubbers no longer intercept scrolling.
- Signed iPhone build and installation succeeded; existing archive was compared before and after installation and remained unchanged. A local backup is in backups/iphone-2026-10-25-before-sleep-timer.
- First validation run: 16 unit checks and the Save link/sleep menu UI check passed (/tmp/earmark-sleep-save-tests.xcresult). The additional local-playback seek/sleep check passed in /tmp/earmark-seek-sleep-tests.xcresult; that run also exposed folder UI tests scrolling through the scrubber, which was addressed afterward.
- Final folder checks passed (2/2) in /tmp/earmark-folder-sleep-v4-tests.xcresult, including tap-to-expand, separate rename menu, swipe deletion, dragging, and persistence. Save link and sleep-menu interaction also passed after the scrolling fix in /tmp/earmark-folder-sleep-v3-tests.xcresult.

2026-10-26 global filters and rhinestone update:
- Global Listening/Listened filters below folders show the folder beneath each title; expanded folders have independent filters backed by the same listened status. Filled checkmarks sit at the trailing edge.
- Sleep is a small outlined text button offering 5, 15, or 30 minutes. Both jewel strips use 13 identical 13-point rhinestones with matching insets; the loose charms use faceted artwork with pale silver edges.
- Approved disc C and dark-background icon preserve the original smooth disc colors, omit the decorative rim, and use smaller rhinestone charms. Native logo/icon assets were exported at 1024 square.
- Renaming/loading and drag persistence passed in /tmp/earmark-global-tabs-fresh-tests.xcresult. Global/per-folder status changes passed in /tmp/earmark-global-status-final-tests.xcresult after waiting for filtered rows to disappear. Save-without-loading and sleep interaction passed in /tmp/earmark-global-tabs-tests.xcresult.
- iPhone library was backed up under backups/iphone-2026-10-25-before-global-tabs and verified unchanged after the update.
- Decorate is a separate interactive HTML mockup: previews/rhinestone-stereo-v12.html. Browser checks cover stereo-only drops, reusable sheet stickers, trash removal, Done persistence, reload, and mobile touch drag. This feature is not yet part of the native app.

2026-10-26 header and typography preview:
- Header uses locally bundled Modak (with its OFL license) as a rounded interpretation of the supplied reference. Registration and rendering were verified in the simulator, including the unchanged disc C.
- Import audio is restored to a compact pink text-only control. Player and archive behavior are unchanged.
- Signed iPhone and simulator builds passed. Three separate body-font mockups (Quicksand, Manrope, Varela Round) are available in previews/typography-v13.html; all fonts load locally, and the decorate panel still opens and saves. Body-font choices remain previews only.
- Existing HTML and image previews were preserved. iPhone backup before this update: backups/iphone-2026-10-26-before-typography.

2026-10-26 Quicksand selection and header studies:
- Applied Quicksand to app content and stereo text buttons using the original variable font, with weights configured through the CoreText variation attribute. The green display block remains monospaced at its existing sizes and weights.
- Skip arrows and numbers are grouped and centered inside their fixed circular controls. Native rendering was visually checked, and simulator/device builds passed.
- Header alternatives in previews/header-options-v14.html keep these typography choices and offer three flatter reference-inspired treatments. These headers remain previews only; the installed header has not been replaced by an unselected option.
- Previous HTML and screenshots remain intact. Before-update library backup: backups/iphone-2026-10-26-before-quicksand.


2026-10-26 approved sticker studio release (supersedes earlier preview-only notes):
- Applied header C with subtle spacing, the larger disc opening, inward heart placement, white gem borders, Quicksand content/buttons, and the muted inset green display. The LCD remains monospaced. Native screenshot: `Preview/earmark-ios-v4.png`.
- Links save on load automatically; the separate Save link control and paste-only saving are removed. Renamed URLs and identical imported audio retain their original archive entry and show a duplicate notice. File actions retain drag-to-folder but omit Move.
- The sleep control is neutral while off and pink while running; its countdown appears inside the LCD, including while paused. Menu cancellation and automatic expiration passed.
- Significant scrubs retain a tappable horizontal return notch. Remaining time has no “left” label. The file-picker control is `add file` with its import icon.
- Native decoration editing now supports 48 white-bordered gems, five per swipeable page, reusable sources, stereo-only placement, repositioning, trash removal, and atomic layout persistence. Native gesture tests cover pinch and rotation before releasing a source gem.
- Full native run `/tmp/earmark-release-all-tests.xcresult`: 29 of 30 passed; the remaining source-page swipe exposed a direction-classification issue subsequently corrected and checked separately (see final result below).
- Original standalone web player: 17 of 17 Node checks passed. New v17 HTML preview passed browser checks for five-item pages, header-only sheet text, automatic saving, renamed duplicate detection, and no JavaScript errors. Earlier previews remain intact.
- Signed device build and installation succeeded. The before/after library comparison retained all entry IDs and folder data; the only changed entry field was playback position. Decorations use a separate JSON file. Device copies remain in ignored `backups/`.
- Physical-device background audio, Bluetooth routing, interruptions, and receiving files from another app remain manual checks; installation alone does not establish these behaviors.
- Final focused result: `/tmp/earmark-sticker-approved-tests.xcresult` passed both the native source-page swipe/drag/relaunch UI check and the pre-drop pinch/rotation check. Together with the full run, all 30 native checks passed after the paging correction.


2026-10-26 archive and stereo refinements (current):
- Compact folder creation uses the archive heading’s + button and a system name dialog. File/folder deletion offers undo; undo retains intervening playback progress and additions and avoids duplicating a re-added recording. Imported audio bytes remain available for undo during the session.
- Archive icons save links or import files without replacing the loaded recording. Actual local-audio playback continued while another link was archived.
- Removed NOW PLAYING and the explanatory footer; playback failures read “error”. Added a small recessed glowing red loaded indicator above the speaker, restored the folded-sheet decorate icon without text, and tightened the add-file icon spacing.
- Significant scrubbing retains one vertical inset return notch across repeated moves. It stays inside the bar and expires after 30 seconds; intended listening positions continue to save immediately.
- Five-item sticker pages mix shapes/colors. The transparent glossy sheet has sharp corners and the “sticker sheet” heading. Native swipes, source drag, existing layout persistence, and the one-finger resize/rotate handle passed. Pinch sensitivity increases smoothly and supports 8-point gems; rotation and tiny sizes persist after reopening.
- A stable equatable sleep control prevents LCD countdown updates from rebuilding an open system menu. Countdown, selection, cancellation, and neutral/active button styling passed, including a second focused run.
- 24 unit checks passed in /tmp/earmark-refinements-stickers-v2.xcresult; the updated playback/queue check also passed in /tmp/earmark-refinements-final-checks.xcresult. All 10 interface checks passed across the full and focused runs: /tmp/earmark-refinements-full.xcresult, /tmp/earmark-refinements-focused.xcresult, /tmp/earmark-refinements-sleep-handle.xcresult, and /tmp/earmark-refinements-theme-check.xcresult. Final focused runs had zero failures.
- Signed iPhone build and installation succeeded. The original archive and decorations are preserved in ignored backups/iphone-2026-10-26-before-refinements; a post-install copy is also retained privately. Earlier HTML and PNG previews remain intact. New native screenshots: Preview/earmark-ios-v5.png and Preview/earmark-ios-v5-sticker-sheet.png.
- Alternate-theme sheet transparency was visually checked in Preview/earmark-ios-v5-sticker-sheet-light.png. The final sleep cancellation check passed twice after stabilizing the menu.
- Normal simulator library cleanup removed 69 old test entries and seven generated test folders after saving an ignored backup; only the original sample remains in Unarchived. The iPhone was also cleared of custom folders; a link newly added during this work was preserved instead of overwriting that subsequent device edit.


2026-10-26 compact controls, safe decorations, and project consolidation:
- The active Xcode project is ios/earmark.xcodeproj; project.yml generates the same lowercase project name. The app retains its existing bundle identifier and storage paths. Closed the obsolete Xcode window that recreated its old directory; preserved both sets of workspace/window-state remnants under saved/ (ignored). Earlier HTML and native previews remain intact.
- The previous archive cleanup removed the then-current podcast. This update performs no archive cleanup. Both currently saved phone recordings, selected recording, names, folders, and positions were compared before and after the signed installation; all were preserved. Private before/after backups are under backups/iphone-2026-10-26-layout-*.
- Selection now persists synchronously when loading begins. A regression check reopens storage before audio resolution completes. The actual M4A playback test now uses restoreLast(), verifying selection and saved position after reopening.
- Shorter 11-gem top strip, no bottom strip, bottom-left loaded LED, vertically centered wordmark/disc, shorter input, and inline load/add file/save controls. Save offers links or files without changing playback; adding files while audio is loaded also leaves playback intact.
- Sticker placement includes rotated bounds and four-point gaps from the screen, scrubber/time, buttons, mesh, top jewels, stereo edges, and other gems. Invalid drops/resizes preserve the prior placement. Existing layouts are adjusted to nearby free metal surfaces; new placements are refused when no space is available. Dragging now follows the actual finger location, correcting an offset caused by UIPanGestureRecognizer's recognition threshold.
- Normal crescent artwork exported in six colors. Sheet title/trash/Done sit above its glossy border. Five mixed-shape choices, swiping, one-finger shrink/rotation, and persistence after relaunch passed. Native screenshots: Preview/earmark-ios-v6.png and Preview/earmark-ios-v6-sticker-sheet.png.
- 26 unit checks and four affected UI checks passed across /tmp/earmark-layout-regressions.xcresult, /tmp/earmark-layout-focused.xcresult, and /tmp/earmark-layout-gesture-v2.xcresult. Initial failures identified an incorrect resize-test expectation and the finger offset; both were resolved and affected checks rerun. Signed physical-iPhone build and installation succeeded.
- Separate HTML widget concept: previews/mini-stereo-widget-v1.html, with small/medium stereo-only layouts and dark/light PNG previews. Assets loaded and the mock playback/theme toggles worked in Chromium. No WidgetKit target was added.


2026-10-26 archive progress and compact stereo footer:
- Added optional persisted recording duration and clamped position/duration progress. Older libraries and backups without duration remain readable. Durations are learned from AVPlayer readiness and updated without repeated writes for unchanged values. Listening entries show live progress and percent in global and folder views; unplayed recordings show 0%, and older played entries without a known duration show —% until loaded.
- Link field, add file, load, and icon-only save share one horizontal row with transparent outlined controls. Reduced scrubber/time-row heights and moved playback controls closer.
- New folded-sheet artwork with miniature heart/star/diamond. The decorate button sits at the lower right, opposite the red loaded light, with narrower mesh between them. Existing protected sticker regions follow these controls. Light-mode background darkened to #d8ceca.
- 32/32 checks passed in /tmp/earmark-progress-controls.xcresult: all 27 unit checks plus archive progress/undo, top-row order and save/sleep, file importer, sticker drag/resize/swipe/persistence, and theme UI checks. Real M4A playback confirms duration and progress persist.
- Native screenshots saved as Preview/earmark-ios-v7*.png. Widget concepts saved separately as previews/mini-stereo-widget-v2.html and v2 dark/light PNGs; both sizes, image loading, footer bounds, and mock playback/theme controls verified in Chromium. Prior preview versions unchanged.
- Signed iPhone build and installation succeeded. The before/after phone libraries retained all recordings, selection, folders, names, listened status, and positions. Private backups are saved under backups/iphone-2026-10-26-progress-*. The updated app was relaunched.


2026-10-26 approved inline source controls and continuous sticker limits:
- Implemented approved B/v4: leftmost link/file selector, source field or file picker, filled pink load, and direct icon-only save on one row. File selection creates a temporary private copy preserving the original name; neither the player nor archive changes until load/save. Load archives and loads the first selected file; save retains the current player. Link load still archives automatically.
- Sleep and reset now share the playback-control row directly below the time bar; smaller playback circles retain centered labels. The sticker-sheet button is borderless. Listening progress is a 41-point bar with percent beside the filename, in both global and folder rows. The light background remains #d8ceca.
- Default gems are smaller and distributed over the dedicated free metal strip above the mesh. Existing custom layouts are retained and adjusted only for protected regions. Drag/resize/rotation previews resolve collisions continuously in subpixel steps, preventing tunnelling and allowing translation along obstacle edges. Protected regions and other gems remain solid limits. The selected corner handle has priority while decorating so it remains reachable when it extends over a protected region.
- All 35 affected checks passed across /tmp/earmark-inline-controls.xcresult (29 unit and five UI checks passed; the handle interaction failed initially) and /tmp/earmark-inline-gesture-fix.xcresult (the drag/resize/rotation/page/relaunch check passed after the handle-priority fix). New checks cover thin obstacles, sliding/reversal, other-gem limits, resize limits, deferred file selection, original filename retention, and save without replacing selection.
- Native screenshots: Preview/earmark-ios-v8.png and Preview/earmark-ios-v8-sticker-sheet.png. All earlier previews retained. Approved source-flow HTML mockups v3/v4 are saved separately.
- Updated small/medium widget concepts in previews/mini-stereo-widget-v3.html and dark/light PNGs. Images loaded and both themes rendered in Chromium; medium sleep/reset controls share the transport row, while the small concept retains its compact transport. These remain mockups, not a WidgetKit extension.
- Signed physical-device build and installation succeeded. Two archive entries, selected recording, folders, titles, URLs, listened status, saved positions, and decoration bytes were compared before/after installation and preserved. Private backups: backups/iphone-2026-10-26-inline-preinstall and backups/iphone-2026-10-26-inline-postinstall. No archive cleanup or library replacement performed.
- Automatic post-install launch was denied because the physical iPhone was locked. Installation and data comparison succeeded; open the app from its Home Screen icon after unlocking.


2026-10-26 rename folder choices, inbox, and native widget release:
- Rename uses a native text field with an accessible × clear button and a folder menu listing inbox, existing folders, and New folder. A new name/folder is applied only on Save; Cancel preserves the entry. Tests cover clearing, disabled empty-name Save, selecting an existing folder, creating one from the editor, canceling a move, rename/load, and persistence across relaunch. Initial rapid sheet-transition taps were synchronized by waiting for and focusing the title field; the final full suite passes.
- The default nil-folder display label is now lowercase inbox throughout the player, archive, editor, and widget snapshot. No library schema or stored folder assignments were changed.
- Added the embedded EarmarkWidget target inside the sole ios/earmark.xcodeproj, small and medium mini stereo layouts, the shared folded-sheet icon and all 48 gem assets. A display-only WidgetSnapshot is shared through group.com.katiechapman.earmark; the existing library/audio/decorations storage remains unchanged. Registered and verified matching App Group entitlements in both signed provisioning profiles.
- AppIntent widget configuration offers Match app, Dark, and Light. Confirmed the native widget appears in the simulator gallery, renders the mini stereo, and exposes all three appearance choices in Edit Widget. Controls open earmark for playback/skip/sleep/reset/decorate actions. Sleep and reset appear in both sizes; the loaded indicator depends on the current selection. iOS controls timeline refresh timing.
- Widget snapshots include the saved app sticker layout and its reference dimensions. Gems retain shapes, colors, normalized position and rotation, shrink uniformly, and are omitted if too small or if their rotated bounds would overlap protected widget regions, the widget edge, or an accepted sticker. Filtering never changes the app's saved decorations.
- Sleep menu action is Cancel. The countdown starts only during actual AVPlayer playback, freezes while paused/loading/buffering, and resumes from its remaining time when playback resumes. Active paused timers remain visible in the green display and retain the active button state. Tests cover paused replacement/cancel/reset, actual playback pause/resume/expiry, and widget position projection capped at its sleep deadline.
- Final full native run: /tmp/earmark-widget-sleep-all.xcresult — 43 passed, zero failed. Includes every library/playback unit check and all archive/folder, rename, import, sleep, theme, sticker gesture and relaunch interface checks. Signed iPhone and simulator builds succeeded.
- Installed and launched on the connected iPhone. Compared both saved recording IDs, selected recording, names, URLs, folders, listened flags, saved positions, and decoration JSON bytes before/after: preserved. Private copies are in backups/iphone-2026-10-26-widget-preinstall and -postinstall. No cleanup, deletion, or library replacement performed.
- New native previews: Preview/earmark-ios-v9.png and Preview/earmark-ios-v9-rename.png. Earlier HTML/PNG previews remain unchanged. Direct devicectl copy of the shared App Group snapshot hit an Apple file-service path error; this does not affect the verified app archive copy or installation. Physical Home Screen widget refresh/tap behavior is not claimed as tested by the simulator checks.

2026-10-28 archive, playback, and widget refinements:
- Date added on new recordings; newest/oldest sorting preserves unknown legacy dates. Persistent deduplicated playback queue with clear/remove actions that keep archive files. End-of-track advances the queue. Native source-field clear control.
- Seek notches persist across repeated seeks and reloads until used or explicitly cleared. Red LED follows actual playback. Matching rounded sleep/reset outlines, raised transport buttons, and original light disc rendering.
- File rows use a UIKit held-drag recognizer so vertical swipes reach the list while stationary holds still move files into folders. Direct row scrolling, folder drag/relaunch, and row rename/load passed in /tmp/earmark-held-drag-v15.xcresult (3/3). Native SwiftUI drag/drop was rejected after it failed the existing folder-drop test.
- Sticker protection retains known controls when List preferences temporarily disappear, refreshes geometry during drag/drop, and uses a 0.25-point safety gap. Updated units and gesture checks passed in /tmp/earmark-refinements-final-v12.xcresult (36 passed; its direct-scroll failure was fixed and retested in v15).
- Widget playback/skip now use AudioPlaybackIntent shared with the app target; sleep still opens its picker. Reset/sticker controls removed from widget. Pink progress and a contrasting tinted-screen backing preserve image colors; original saved gem shapes appear larger, capped at two small/three medium, entirely within the free band.
- Full suite /tmp/earmark-refinements-v11.xcresult: 44 passed, zero failed. Later focused unit/sticker/sleep checks passed in v12 and final archive gesture checks passed in v15. Signed device build succeeded. Physical Home Screen playback taps and the selected tint mode still need direct device verification.
- Final signed build installed and launched on the connected iPhone. Before/after comparison preserved all five recording IDs, titles, URLs, folders, listened flags, selected ID, nondecreasing positions, and exact decorations.json bytes. Private snapshots: /tmp/earmark-refinements-preinstall and /tmp/earmark-refinements-postinstall. No library deletion or restore performed.

2026-10-29 convex controls, timed notches, sticker paging, and simplified widget:
- Transport faces use a subtle radial curve with the original border, without drop shadows. The red indicator remains visible as an unlit dark-red lens while stopped. The player is 32 points taller with a narrower LCD and mesh, leaving clear metal beside both for stickers. Dates moved below the archive progress/percentage column.
- Every scrub of at least one second records its prior position as a separate inset notch, expiring after 30 seconds. The clear-notch label is removed. Rapid consecutive seeks now accept the latest request and ignore stale completions; return taps select individual notches. Skip buttons do not create markers.
- Sticker ghosts drag over protected elements freely; only valid release positions commit. Invalid releases preserve existing placements or discard a new sticker. Source gems stay on the sheet until a drag toward the stereo is chosen. Horizontal swipes hide the gem ghost and turn pages with sheet feedback; unchosen touches do not auto-scroll. Pinch/rotation and saved layouts remain supported.
- Widget removes every gem and the scrubber knob, increases the progress track to six points, centers transport, and places the visible red lens bottom left, mesh between, sleep bottom right. Physical Home Screen rendering/taps remain a device check.
- Full suite v16: 46 passed, one sticker UI drop correctly rejected because the old test point intersected the newly positioned mesh. Test moved to the free metal band; v17 passed placement, resize, paging and relaunch. Final /tmp/earmark-notches-final-v18.xcresult: all 35 unit checks plus the sticker interface check passed (36/36), including back-to-back seeks, multiple markers, expiration, free preview/rejected LCD drop, horizontal source swipes and screen/mesh side placement. Other interface checks, including scrolling and folder dragging, passed in v16.
- Native screenshots visually inspected and saved with new filenames: Preview/earmark-ios-2026-10-29-convex.png and Preview/earmark-ios-2026-10-29-sticker-sheet.png. No previous previews overwritten.
- Signed app installed and launched on the connected iPhone. Fresh before/after copies preserve all recording IDs, names, URLs, folders, listened status, selected recording, listening progress, and all seven sticker IDs/shapes/placement/size/rotation. Decoration JSON key order and one normalized coordinate differ only at floating-point serialization precision (1e-16); no meaningful placement change. Backups: /tmp/earmark-convex-preinstall-final and /tmp/earmark-convex-postinstall.
