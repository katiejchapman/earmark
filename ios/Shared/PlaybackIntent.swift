import AppIntents
import WidgetKit

struct StereoPlaybackIntent: AudioPlaybackIntent {
    static var title: LocalizedStringResource = "Control earmark playback"
    static var openAppWhenRun: Bool = false
    @Parameter(title: "Action") var action: String
    init() { action = "toggle" }
    init(action: String) { self.action = action }
    @MainActor func perform() async throws -> some IntentResult {
        #if EARMARK_APP
        let player: AudioPlayer
        if let existing = AudioPlayer.widgetInstance { player = existing }
        else {
            let store = LibraryStore()
            let studio = StickerStudioStore(file: store.audioDirectory.deletingLastPathComponent().appendingPathComponent("decorations.json"))
            player = AudioPlayer(store: store)
            player.widgetDecorations = { studio.widgetDecorations }
            AudioPlayer.widgetInstance = player
        }
        player.handleWidgetAction(action)
        // Allow a cold restore to establish its audio item before finishing the intent.
        for _ in 0..<100 where player.loading { try await Task.sleep(for: .milliseconds(100)) }
        player.publishWidget()
        #endif
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetSnapshot.kind)
        return .result()
    }
}
