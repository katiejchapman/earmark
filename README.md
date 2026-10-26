# earmark

A personal iPhone audio player with a local listening archive and a customizable rhinestone stereo.

Open [ios/Earmark.xcodeproj](ios/Earmark.xcodeproj) in Xcode to build the current app. See [installation and usage](ios/README.md) and [validation notes](ios/VALIDATION.md).

- Load audio links and import local recordings, including M4A and MP4 audio. Loaded items save automatically, with duplicate detection that survives renaming.
- Save links or files to the archive while other audio plays. Organize recordings into folders, undo deletions, track listening/listened status, and resume saved playback positions.
- Set a 5, 15, or 30 minute sleep timer. Choose a light or dark theme; dark is the initial default.
- Decorate the stereo with reusable gems. Swipe through five choices at a time, drag onto the stereo, pinch and rotate during placement, and drag unwanted gems to the trash. The checkmark saves the layout locally.

The app stores its library, imported audio copies, and decorations on the iPhone. Installing an update over the same app preserves this data; deleting the app removes it. Personal device backups are excluded from this repository.

`index.html` and `earmark.html` preserve the original standalone web player. Numbered files in `previews/` preserve the design history; [v17](previews/rhinestone-stereo-v17.html) is the latest interactive design preview, not the native app. No earlier previews have been overwritten.

## Checks

```sh
node --test tests/player.test.cjs
xcodebuild test -project ios/Earmark.xcodeproj -scheme Earmark -destination 'platform=iOS Simulator,name=iPhone 17 Pro' CODE_SIGNING_ALLOWED=NO
```

The generated Xcode project and native artwork are included. No Node dependencies are needed to build the iPhone app.
