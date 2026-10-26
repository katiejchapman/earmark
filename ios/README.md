# Earmark for iPhone

Native SwiftUI app for iOS 17 or newer. Open **Earmark.xcodeproj** in Xcode. All HTML files and preview versions remain in the parent folder.

## Install on your iPhone

1. Connect your unlocked iPhone to your Mac and accept **Trust This Computer** if asked.
2. Open `Earmark.xcodeproj` in Xcode.
3. In **Xcode → Settings → Apple Accounts**, sign in to your Apple Account.
4. Select the blue **Earmark** project, then the **Earmark** app target. Under **Signing & Capabilities**, leave **Automatically manage signing** enabled and choose your team (a Personal Team works for your own device).
5. Choose your connected iPhone in Xcode's run destination menu.
6. Enable **Settings → Privacy & Security → Developer Mode** on the iPhone if Xcode asks. Follow the restart/confirmation prompts.
7. Click Xcode's **Run ▶** button. Earmark installs with its own Home Screen icon.

Keep the same bundle identifier (`com.katiechapman.earmark`) and install updates over the existing app to retain its library. Development installations may require signing renewal through Xcode. Deleting the app removes its local data.

Apple references: [Run on a device](https://developer.apple.com/documentation/Xcode/running-your-app-on-simulated-or-physical-devices), [Developer Mode](https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device).

## Use it

- Paste an audio, Archive.org, episode-page, or RSS feed URL and tap **load**. Links save automatically when loaded; pasting alone does not save them.
- Tap Play to begin. Tap the right-hand time to switch between total and remaining time. The choice persists.
- The circle beside the header changes light/dark mode. Dark mode is the initial default.
- Tap **add file** to select one or several M4A, MP4, MP3, AAC, WAV, AIFF, CAF, or FLAC files from Files. Earmark copies each recording into its own storage and plays it offline. MP4 plays its audio track without a video display, using formats supported by iOS. Files or another app can also offer **Open in Earmark** for supported documents.
- Links and files without a recognized show appear in **Unarchived**. Tap a recording for **Load in player**, **Rename**, **Mark as listened**, or **Delete**. Rename edits the audio name and folder name. Listened recordings use a teal color and checkmark; choose **Mark as unlistened** to undo. Drag a recording onto a folder to move it. Tap a folder name or its chevron to expand it; use the folder’s (…) menu to rename it. Use **+** beside Folder name to create a folder. Swipe left on a folder for **Delete**; its recordings return to Unarchived.
- RSS feeds import their episodes and group them by show. Supported episode pages and Archive.org metadata can supply titles and show names. Direct MP3/M4A links often expose only a filename; use **Rename** when needed.
- Listening/Listened tabs beneath the folders filter all recordings; global entries show their folder below the title. Expanded folders have independent Listening/Listened tabs, using the same saved status. Listened entries have a filled checkmark at the right edge.
- **sleep** pauses playback after 5, 15, or 30 minutes. Its button turns pink only while active, and the green display shows the countdown. Use its menu to cancel.
- **decorate** opens a clear sticker sheet with five gems per page. Swipe for more, drag a gem onto the stereo, and pinch/rotate it during placement. While the sheet is open, move existing gems or drag them into the trash. The checkmark saves the layout between sessions.
- Loading a saved URL or reimporting identical audio shows **File already saved.**, retaining its renamed title, folder, and position.
- The player shows the recording’s folder name. Scrubbing at least one minute saves a previous-position notch in the time bar; tap the notch to return. The new listening position saves immediately, and both positions persist across reopening.
- **reset**, at the lower right of the player above the speaker mesh, clears the loaded audio and error message without removing archive entries or their saved positions.
- **Library options (…) → Export library** saves a JSON backup of links, folders, names, and positions. **Restore backup** replaces the library after confirmation. Audio recordings themselves are not included in JSON backups; keep the original audio files separately.

## Storage and playback

The app stores `library.json` in Application Support/Earmark and imported recordings in its Audio subfolder. Writes are atomic. Re-signing and installing over the existing app with the same bundle identifier preserves its archive and imported audio. Do not delete the app before reinstalling: deleting it removes its local library. Export a library backup first if deleting the app, and keep original imported audio separately. Imported recordings are located using a filename relative to Application Support, so app-container path changes do not break them. There is no server, login, or cross-device sync.

Playback uses AVPlayer, AVAudioSession's playback category, background audio, and system remote commands. Positions save every five seconds, on pause, and when the app leaves the foreground. The last recording reopens paused. Interrupted audio can resume when iOS permits it; unplugging headphones pauses playback.

A physical iPhone check is still needed for lock-screen playback, headphone/Bluetooth routing, interruptions, and the Files “Open in” flow. Simulator checks cannot prove these device behaviors.

## Build and checks

The generated Xcode project is included, so XcodeGen is not required to open it. If changing `project.yml`, regenerate with:

```sh
rtk proxy xcodegen generate --spec ios/project.yml
```

From the repository root:

```sh
rtk xcodebuild build -project ios/Earmark.xcodeproj -scheme Earmark -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/earmark-derived CODE_SIGNING_ALLOWED=NO
rtk xcodebuild test -project ios/Earmark.xcodeproj -scheme Earmark -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath /tmp/earmark-derived CODE_SIGNING_ALLOWED=NO
```

Checks cover persistence across reopening, manual-folder preservation, deletion during loading, backup validation, RSS metadata, Archive.org normalization, direct MP3 resolution, local M4A import/playback/resume after removal of the original file, and main interface interactions.
