import SwiftUI

@main
struct EarmarkApp: App {
    @StateObject private var store: LibraryStore
    @StateObject private var player: AudioPlayer
    @StateObject private var studio: StickerStudioStore
    @Environment(\.scenePhase) private var phase
    @AppStorage("darkMode") private var dark = true
    init() {
        let store: LibraryStore
        #if DEBUG
        if let identifier = ProcessInfo.processInfo.environment["EARMARK_UI_TEST_LIBRARY"], UUID(uuidString: identifier) != nil {
            let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            store = LibraryStore(file: root.appendingPathComponent("EarmarkUITests/\(identifier)/library.json"))
            if store.data.entries.isEmpty, ProcessInfo.processInfo.environment["EARMARK_UI_TEST_SCROLL_FIXTURE"] == "1" {
                for index in 0..<20 { _ = try? store.remember("https://example.com/scroll-item-\(index).mp3") }
            }
        } else { store = AudioPlayer.widgetInstance?.store ?? LibraryStore() }
        #else
        store = AudioPlayer.widgetInstance?.store ?? LibraryStore()
        #endif
        let studio = StickerStudioStore(file: store.audioDirectory.deletingLastPathComponent().appendingPathComponent("decorations.json"))
        let player = AudioPlayer.widgetInstance ?? AudioPlayer(store: store)
        if ProcessInfo.processInfo.environment["EARMARK_UI_TEST_LIBRARY"] == nil { AudioPlayer.widgetInstance = player }
        player.widgetDecorations = { [weak studio] in studio?.widgetDecorations ?? .empty }
        _store = StateObject(wrappedValue: store)
        _player = StateObject(wrappedValue: player)
        _studio = StateObject(wrappedValue: studio)
    }
    var body: some Scene {
        WindowGroup {
            ContentView(store: store, player: player, studio: studio)
                .preferredColorScheme(dark ? .dark : .light)
                .task { player.restoreLast(); player.publishWidget() }
                .onChange(of: studio.saved) { _, _ in player.publishWidget() }
                .onChange(of: dark) { _, _ in player.publishWidget() }
                .onChange(of: phase) { _, phase in if phase != .active { player.savePosition() } }
        }
    }
}
