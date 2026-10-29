# earmark

A personal iPhone audio player with a local listening archive and a customizable rhinestone stereo.

Open [ios/earmark.xcodeproj](ios/earmark.xcodeproj) in Xcode to build the current app. See [installation and usage](ios/README.md) and [validation notes](ios/VALIDATION.md).

- Choose link or file in the inline source toggle, then load or save. Import local recordings, including M4A and MP4 audio. Loaded items save automatically, with duplicate detection that survives renaming.
- Save links or files to the archive while other audio plays. New unfiled audio appears in inbox. Organize recordings into folders, undo deletions, track listening/listened status, and resume saved playback positions. Listening rows show a compact progress bar and percentage beside the filename once the audio duration is known.
- Set a 5, 15, or 30 minute sleep timer. Choose a light or dark theme; dark is the initial default.
- Decorate the stereo with reusable gems. Swipe through five choices at a time, drag onto the stereo, pinch and rotate during placement, and drag unwanted gems to the trash. The checkmark saves the layout locally.

The app stores its library, imported audio copies, and decorations on the iPhone. Installing an update over the same app preserves this data; deleting the app removes it. Personal device backups are excluded from this repository.

`index.html` and `earmark.html` preserve the original standalone web player. Numbered files in `previews/` preserve the design history; [inline-source v4](previews/controls-and-sources-v4.html) is the latest interactive design preview, not the native app. No earlier previews have been overwritten. The separate [mini stereo widget mockup](previews/mini-stereo-widget-v3.html) shows small and medium concepts in both themes; these historical HTML concepts are preserved. The app now includes a native small/medium mini stereo widget: open earmark once after installing, then search earmark in the Home Screen’s Add Widget gallery. Playback and skip buttons use background audio intents; the sleep picker opens the app. iOS manages refresh timing.

## Checks

```sh
node --test tests/player.test.cjs
xcodebuild test -project ios/earmark.xcodeproj -scheme Earmark -destination 'platform=iOS Simulator,name=iPhone 17 Pro' CODE_SIGNING_ALLOWED=NO
```

The generated Xcode project and native artwork are included. No Node dependencies are needed to build the iPhone app.
