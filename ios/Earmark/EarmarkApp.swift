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
        } else { store = LibraryStore() }
        #else
        store = LibraryStore()
        #endif
        _store = StateObject(wrappedValue: store)
        _player = StateObject(wrappedValue: AudioPlayer(store: store))
        _studio = StateObject(wrappedValue: StickerStudioStore(file: store.audioDirectory.deletingLastPathComponent().appendingPathComponent("decorations.json")))
    }
    var body: some Scene {
        WindowGroup {
            ContentView(store: store, player: player, studio: studio)
                .preferredColorScheme(dark ? .dark : .light)
                .task { player.restoreLast() }
                .onChange(of: phase) { _, phase in if phase != .active { player.savePosition() } }
        }
    }
}
