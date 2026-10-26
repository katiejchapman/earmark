import Foundation
import WidgetKit

@MainActor enum WidgetBridge {
    private static var previous: WidgetSnapshot?
    private static var lastReload = Date.distantPast
    static func publish(_ state: WidgetSnapshot) {
        // Isolated test libraries must never publish test recordings to the widget.
        guard ProcessInfo.processInfo.environment["EARMARK_UI_TEST_LIBRARY"] == nil,
              ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil,
              let file = WidgetSnapshot.file else { return }
        guard let previous = previous else { save(state, file: file, reload: true); return }
        let changed = previous.title != state.title || previous.folder != state.folder || previous.playing != state.playing || previous.loaded != state.loaded || previous.dark != state.dark || previous.sleepDeadline != state.sleepDeadline || abs(previous.duration - state.duration) > 0.5 || previous.decorations != state.decorations || (state.sleepDeadline == nil && abs(previous.sleepRemaining - state.sleepRemaining) > 0.5)
        let seeked = abs(previous.position(at: state.updated) - state.position) > 3
        guard changed || seeked || state.updated.timeIntervalSince(previous.updated) >= 30 else { return }
        save(state, file: file, reload: changed || seeked || state.updated.timeIntervalSince(lastReload) >= 60)
    }
    private static func save(_ state: WidgetSnapshot, file: URL, reload: Bool) {
        do {
            try state.write(to: file); previous = state
            if reload { lastReload = state.updated; WidgetCenter.shared.reloadTimelines(ofKind: WidgetSnapshot.kind) }
        } catch { /* Widget failure must not affect playback or archive writes. */ }
    }
}
