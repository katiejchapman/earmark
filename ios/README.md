# Earmark for iPhone

Native SwiftUI app for iOS 17 or newer. Open **earmark.xcodeproj** in Xcode. All HTML files and preview versions remain in the parent folder.

## Install on your iPhone

1. Connect your unlocked iPhone to your Mac and accept **Trust This Computer** if asked.
2. Open `earmark.xcodeproj` in Xcode.
3. In **Xcode → Settings → Apple Accounts**, sign in to your Apple Account.
4. Select the blue **earmark** project, then the **Earmark** app target. Under **Signing & Capabilities**, leave **Automatically manage signing** enabled and choose your team (a Personal Team works for your own device).
5. Choose your connected iPhone in Xcode's run destination menu.
6. Enable **Settings → Privacy & Security → Developer Mode** on the iPhone if Xcode asks. Follow the restart/confirmation prompts.
7. Click Xcode's **Run ▶** button. Earmark installs with its own Home Screen icon.

Keep the same bundle identifier (`com.katiechapman.earmark`) and install updates over the existing app to retain its library. Development installations may require signing renewal through Xcode. Deleting the app removes its local data.

Apple references: [Run on a device](https://developer.apple.com/documentation/Xcode/running-your-app-on-simulated-or-physical-devices), [Developer Mode](https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device).

## Use it

- Paste an audio, Archive.org, episode-page, or RSS feed URL and tap **load**. Links save automatically when loaded; pasting alone does not save them. The icon-only **save** button saves the selected source without changing the player.
- The top row starts with a **link/file** toggle, followed by the source field, pink **load**, and icon-only outlined **save**. Choose the source, then choose an action.
- Tap Play to begin. Tap the right-hand time to switch between total and remaining time. The choice persists.
- The circle beside the header changes light/dark mode. Dark mode is the initial default.
- Select **file**, then **add file** to choose one or several M4A, MP4, MP3, AAC, WAV, AIFF, CAF, or FLAC files from Files. Choosing files prepares temporary private copies; it does not save or change playback yet. **load** archives them and loads the first, while **save** archives them and keeps the current player. Imported audio is stored in the app for offline playback. MP4 plays its audio track without a video display, using formats supported by iOS. Files or another app can also offer **Open in Earmark** for supported documents.
- Links and files without a recognized show appear in **inbox**. Tap a recording for **Load in player**, **Rename**, **Mark as listened**, or **Delete**. Rename has an × clear button for the name and a folder menu with inbox, existing folders, and New folder. Folder changes are applied when you tap Save; Cancel leaves the recording unchanged. Listened recordings use a teal color and checkmark; choose **Mark as unlistened** to undo. Drag a recording onto a folder to move it. Tap a folder name or its chevron to expand it; use the folder’s (…) menu to rename it. Use **+** beside the archive heading to name a folder in a compact dialog. Swipe left on a folder for **Delete**; its recordings return to inbox. Tap **undo** in the bottom bar to reverse the latest file or folder deletion. Deleted local audio is retained for undo.
- RSS feeds import their episodes and group them by show. Supported episode pages and Archive.org metadata can supply titles and show names. Direct MP3/M4A links often expose only a filename; use **Rename** when needed.
- Listening entries show a small progress bar and percentage inline with the filename, including within expanded folders. Durations save after loading audio and remain available across sessions; older entries with an existing position show **—%** until their duration is learned. Unplayed entries start at **0%**.
- Listening/Listened tabs beneath the folders filter all recordings; global entries show their folder below the title. Expanded folders have independent Listening/Listened tabs, using the same saved status. Listened entries have a filled checkmark at the right edge.
- **sleep** pauses playback after 5, 15, or 30 minutes of audio playing. Its countdown freezes while audio is paused or buffering and resumes when playback resumes. Its button turns pink only while active, and the green display shows the countdown. Its menu uses **Cancel** to turn the timer off.
- The borderless bottom-right folded sticker-sheet icon, opposite the red loaded light with the narrower mesh between them, opens a transparent glossy sheet with five mixed gem shapes per page. Swipe for more, drag a gem onto the stereo, and pinch/rotate it during placement. While the sheet is open, move existing gems or drag them into the trash. Drag the selected gem’s corner handle to resize and rotate with one finger; gems can shrink to 8 points. The checkmark saves the layout between sessions. Stickers stay on free metal surfaces: they cannot cover the screen, time bar, buttons, mesh, rhinestone strip, stereo edges, or another sticker. During dragging, resizing, and rotation, gems stop at protected edges; dragging can continue along an edge without bouncing back. Default gems are scattered across the free metal strip above the mesh. The selected resize handle remains reachable even when the handle extends over a protected area.
- Loading a saved URL or reimporting identical audio shows **File already saved.**, retaining its renamed title, folder, and position.
- The player shows the recording’s folder name. Scrubbing at least one minute creates a vertical inset notch inside the time bar; tap it to return. Further scrubs retain that original marker until it expires 30 seconds after appearing. The new listening position saves immediately and persists across reopening.
- **reset**, inline with sleep and the playback buttons below the time bar, clears the loaded audio and error message without removing archive entries or their saved positions.
- **Library options (…) → Export library** saves a JSON backup of links, folders, names, and positions. **Restore backup** replaces the library after confirmation. Audio recordings themselves are not included in JSON backups; keep the original audio files separately.

## Storage and playback

The app stores `library.json` in Application Support/Earmark and imported recordings in its Audio subfolder. Writes are atomic. Re-signing and installing over the existing app with the same bundle identifier preserves its archive and imported audio. Do not delete the app before reinstalling: deleting it removes its local library. Export a library backup first if deleting the app, and keep original imported audio separately. Imported recordings are located using a filename relative to Application Support, so app-container path changes do not break them. There is no server, login, or cross-device sync.

Playback uses AVPlayer, AVAudioSession's playback category, background audio, and system remote commands. Positions save every five seconds, on pause, and when the app leaves the foreground. The selected recording is saved immediately when loading starts, and reopens paused at its saved position. Interrupted audio can resume when iOS permits it; unplugging headphones pauses playback.

A physical iPhone check is still needed for lock-screen playback, headphone/Bluetooth routing, interruptions, and the Files “Open in” flow. Simulator checks cannot prove these device behaviors.

## Build and checks

The generated Xcode project is included, so XcodeGen is not required to open it. If changing `project.yml`, regenerate with:

```sh
rtk proxy xcodegen generate --spec ios/project.yml
```

From the repository root:

```sh
rtk xcodebuild build -project ios/earmark.xcodeproj -scheme Earmark -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/earmark-derived CODE_SIGNING_ALLOWED=NO
rtk xcodebuild test -project ios/earmark.xcodeproj -scheme Earmark -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath /tmp/earmark-derived CODE_SIGNING_ALLOWED=NO
```

Checks cover persistence across reopening, manual-folder preservation, deletion during loading, backup validation, RSS metadata, Archive.org normalization, direct MP3 resolution, local M4A import/playback/resume after removal of the original file, and main interface interactions.

## Mini stereo widget

The app now includes a native small and medium WidgetKit extension, in addition to the preserved HTML concepts. After installing an update, unlock and open earmark once. On the Home Screen, touch and hold an empty area, choose **Edit → Add Widget**, search **earmark**, select a size, and tap **Add Widget**.

The widget shows a separate shared snapshot of the selected title, folder, listening position, saved stickers, theme, loaded-audio light, and sleep timer. Sleep and reset appear in both sizes. Saved stickers keep their shapes, colors, relative positions, and rotation, shrink to the widget, and are omitted when they would cover its protected elements or another sticker; the app’s saved layout is unchanged. Touch and hold the widget, choose **Edit Widget**, then select **Match app**, **Dark**, or **Light** under Appearance. The archive and imported recordings remain in the app's original storage; no migration is needed. iOS controls refresh timing, so progress and play/pause state can lag behind the app. Tapping the small widget opens the player. The medium widget's playback, skip, sleep, reset, and sticker-sheet links open earmark to perform the action; playback does not run inside the extension.

Both targets use `group.com.katiechapman.earmark` for this display-only snapshot. If building on another account, select the same team for Earmark and EarmarkWidget and enable/register the group in Signing & Capabilities. The extension is embedded in the app; there is still one Xcode project.
