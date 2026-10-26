import XCTest
import AVFoundation
import UIKit
@testable import Earmark

final class LibraryTests: XCTestCase {
    private func temporaryFile() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("library.json") }

    func testWidgetSnapshotRoundTripAndPositionProjection() throws {
        let now = Date(timeIntervalSince1970: 1000), file = temporaryFile()
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        var state = WidgetSnapshot(title: "A saved recording", folder: "Favorites", position: 80, duration: 100,
            playing: true, loaded: true, dark: true, updated: now, sleepDeadline: now.addingTimeInterval(900))
        try state.write(to: file)
        XCTAssertEqual(try JSONDecoder().decode(WidgetSnapshot.self, from: Data(contentsOf: file)), state)
        XCTAssertEqual(state.position(at: now.addingTimeInterval(10)), 90)
        XCTAssertEqual(state.position(at: now.addingTimeInterval(300)), 100)
        XCTAssertEqual(state.position(at: now.addingTimeInterval(-5)), 80)
        state.playing = false
        XCTAssertEqual(state.position(at: now.addingTimeInterval(10)), 80)
        XCTAssertFalse(WidgetSnapshot.empty.loaded)
    }

    @MainActor func testWidgetActionsRestoreSkipAndResetWithoutRemovingArchive() async throws {
        let file = temporaryFile(), directory = file.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let original = directory.appendingPathComponent("widget.caf")
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 8000, channels: 1))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 8000 * 40))
        buffer.frameLength = buffer.frameCapacity
        for i in 0..<Int(buffer.frameLength) { buffer.floatChannelData![0][i] = 0 }
        do { let output = try AVAudioFile(forWriting: original, settings: format.settings); try output.write(from: buffer) }
        let store = LibraryStore(file: directory.appendingPathComponent("App/library.json"))
        let entry = try store.importAudio(original); store.select(entry.id); store.setPosition(20, for: entry.id)
        let player = AudioPlayer(store: store)
        player.handleWidgetAction("back")
        for _ in 0..<100 where player.loading || abs(player.position - 5) > 0.3 { try await Task.sleep(for: .milliseconds(100)) }
        XCTAssertNil(player.message); XCTAssertEqual(player.currentID, entry.id)
        XCTAssertEqual(player.position, 5, accuracy: 0.3)
        player.handleWidgetAction("forward")
        XCTAssertEqual(player.position, 20, accuracy: 0.3)
        try await Task.sleep(for: .milliseconds(150))
        player.handleWidgetAction("toggle")
        try await Task.sleep(for: .milliseconds(300)); player.pause()
        XCTAssertGreaterThanOrEqual(store.entry(entry.id)?.position ?? 0, 19.9)
        player.handleWidgetAction("reset")
        XCTAssertNil(player.currentID); XCTAssertNil(store.data.lastID)
        XCTAssertEqual(store.data.entries.count, 1)
        XCTAssertGreaterThanOrEqual(store.entry(entry.id)?.position ?? 0, 19.9)
    }

    func testWidgetStickersKeepSavedDesignAndOmitProtectedOverlaps() {
        for small in [true, false] {
            let size = CGSize(width: small ? 178 : 360, height: 178)
            let layout = WidgetStereoLayout(size: size, small: small)
            let safe = WidgetGem(id: UUID(), asset: "Gem_moon_blue", x: 0.25, y: layout.decoration.midY / size.height, size: 18, rotation: 17)
            var onScreen = safe; onScreen.id = UUID(); onScreen.y = layout.lcd.midY / size.height
            var offEdge = safe; offEdge.id = UUID(); offEdge.x = 0
            var overlap = safe; overlap.id = UUID()
            var tooLarge = safe; tooLarge.id = UUID(); tooLarge.x = 0.7; tooLarge.size = 120
            let saved = WidgetDecorations(width: 362, height: 365, gems: [safe, onScreen, offEdge, overlap, tooLarge])
            let visible = saved.visible(in: size, obstacles: layout.protectedRects)
            XCTAssertEqual(visible.map(\.id), [safe.id])
            XCTAssertEqual(visible.first?.asset, safe.asset)
            XCTAssertEqual(visible.first?.rotation, safe.rotation)
            XCTAssertLessThan(visible.first?.size ?? 100, safe.size)
            XCTAssertEqual(saved.gems.count, 5) // Filtering never edits the saved app layout.
        }
        var state = WidgetSnapshot.empty
        let now = Date(); state.updated = now; state.position = 20; state.duration = 200; state.playing = true
        state.sleepDeadline = now.addingTimeInterval(5)
        XCTAssertEqual(state.position(at: now.addingTimeInterval(100)), 25, accuracy: 0.01)
    }

    @MainActor func testArchiveProgressPersistsAndOldLibrariesRemainReadable() throws {
        let file = temporaryFile(); let store = LibraryStore(file: file)
        let entry = try store.remember("https://example.com/progress.mp3")
        XCTAssertEqual(entry.progressFraction, 0)
        store.setPosition(80, for: entry.id)
        XCTAssertNil(store.entry(entry.id)?.progressFraction)
        store.setDuration(200, for: entry.id)
        let reopened = LibraryStore(file: file)
        XCTAssertEqual(reopened.entry(entry.id)?.duration, 200)
        XCTAssertEqual(reopened.entry(entry.id)?.progressFraction ?? -1, 0.4, accuracy: 0.001)
        reopened.setPosition(300, for: entry.id)
        XCTAssertEqual(reopened.entry(entry.id)?.progressFraction, 1)
        reopened.setDuration(-1, for: entry.id)
        XCTAssertEqual(reopened.entry(entry.id)?.duration, 200)
        var legacy = try JSONDecoder().decode(LibraryData.self, from: reopened.exportData())
        legacy.entries[0].duration = nil
        try reopened.restore(JSONEncoder().encode(legacy))
        XCTAssertEqual(reopened.entry(entry.id)?.position, 300)
        XCTAssertNil(reopened.entry(entry.id)?.duration)
        legacy.entries[0].duration = -20
        XCTAssertThrowsError(try reopened.restore(JSONEncoder().encode(legacy)))
    }

    @MainActor func testSelectionPersistsBeforeAudioResolution() throws {
        let file = temporaryFile(); let store = LibraryStore(file: file)
        let first = try store.remember("https://example.com/old.mp3")
        let current = try store.remember("https://example.com/new.mp3")
        store.select(first.id); store.setPosition(189, for: current.id)
        let player = AudioPlayer(store: store)
        player.load(try XCTUnwrap(store.entry(current.id)))
        let reopened = LibraryStore(file: file)
        XCTAssertEqual(reopened.data.lastID, current.id)
        XCTAssertEqual(reopened.entry(current.id)?.position, 189)
        XCTAssertEqual(reopened.data.entries.count, 2)
        player.reset()
    }

    @MainActor func testStickersRejectProtectedSurfacesAndEachOtherIncludingRotation() throws {
        let file = temporaryFile()
        let studio = StickerStudioStore(file: file); studio.begin()
        studio.draft = []
        let stereo = CGRect(x: 20, y: 40, width: 320, height: 400)
        let screen = CGRect(x: 40, y: 70, width: 280, height: 100)
        let controls = CGRect(x: 80, y: 240, width: 200, height: 50)
        studio.updateLayout(stereo: stereo, obstacles: [screen, controls])
        let safe = PlacedGem(asset: GemChoice.all[0].id, x: 0.5, y: 0.8, size: 28)
        XCTAssertTrue(studio.place(safe))
        var overlap = safe; overlap.id = UUID()
        XCTAssertFalse(studio.place(overlap))
        var blocked = safe; blocked.id = UUID(); blocked.y = 0.15
        XCTAssertFalse(studio.place(blocked)) // Screen.
        blocked.y = 0.55
        XCTAssertFalse(studio.place(blocked)) // Playback controls.
        blocked.y = 0.42; blocked.size = 70; blocked.rotation = 45
        XCTAssertFalse(studio.place(blocked)) // Rotated corner touches protected area.
        blocked.x = 0.01; blocked.y = 0.9; blocked.size = 28
        XCTAssertFalse(studio.place(blocked)) // Outside stereo.
        studio.adjust(safe.id, scale: 5, rotation: 45)
        XCTAssertEqual(studio.draft.first?.size, 28) // Invalid resize leaves original intact.
        studio.add(GemChoice.all[1])
        XCTAssertEqual(studio.draft.count, 2)
        XCTAssertTrue(studio.draft.allSatisfy { studio.canPlace($0) })
        studio.finish()
        XCTAssertEqual(StickerStudioStore(file: file).saved.count, 2)
    }

    @MainActor func testGemMotionStopsAtEdgesSlidesAndCannotTunnel() throws {
        let studio = StickerStudioStore(file: temporaryFile()); studio.begin(); studio.draft = []
        studio.updateLayout(stereo: CGRect(x: 0, y: 0, width: 320, height: 400),
                            obstacles: [CGRect(x: 140, y: 60, width: 2, height: 260)])
        let start = PlacedGem(asset: GemChoice.all[0].id, x: 0.25, y: 0.4, size: 20)
        XCTAssertTrue(studio.place(start))
        var target = start; target.x = 0.9; target.y = 0.6
        let stopped = studio.limitedMotion(from: start, to: target)
        XCTAssertEqual(stopped.x * 320, 126, accuracy: 1)
        XCTAssertEqual(stopped.y, 0.6, accuracy: 0.002)
        XCTAssertTrue(studio.canPlace(stopped))
        XCTAssertTrue(studio.place(stopped))
        target = stopped; target.x = 0.2
        let reversed = studio.limitedMotion(from: stopped, to: target)
        XCTAssertEqual(reversed.x, 0.2, accuracy: 0.002)
        // The other gem is also a solid limit.
        var other = start; other.id = UUID(); other.x = 0.2; other.y = 0.8
        XCTAssertTrue(studio.place(other))
        target = reversed; target.y = 0.95
        let againstGem = studio.limitedMotion(from: reversed, to: target)
        XCTAssertLessThan(againstGem.y, 0.75)
        XCTAssertTrue(studio.canPlace(againstGem))
        var larger = stopped; larger.size = 120; larger.rotation = 45
        let resized = studio.limitedMotion(from: stopped, to: larger)
        XCTAssertTrue(studio.canPlace(resized))
        XCTAssertLessThan(resized.size, 120)
        studio.place(resized); studio.finish()
    }

    @MainActor func testFileSelectionWaitsForActionAndRetainsOriginalName() throws {
        let file = temporaryFile(), store = LibraryStore(file: file)
        let playing = try store.remember("https://example.com/current.mp3"); store.select(playing.id)
        let source = file.deletingLastPathComponent().appendingPathComponent("chosen.m4a")
        try Data([1, 3, 5, 7]).write(to: source)
        let selected = try AudioSelection.stage([source]); defer { AudioSelection.remove(selected) }
        XCTAssertEqual(selected.first?.lastPathComponent, "chosen.m4a")
        try FileManager.default.removeItem(at: source)
        XCTAssertEqual(store.data.entries.count, 1)
        XCTAssertEqual(store.data.lastID, playing.id)
        let saved = try store.importAudio(XCTUnwrap(selected.first))
        XCTAssertEqual(store.data.entries.count, 2)
        XCTAssertEqual(store.data.lastID, playing.id) // Save does not replace the player.
        store.rename(saved.id, title: "Renamed", show: "")
        XCTAssertEqual(try store.importAudio(XCTUnwrap(selected.first)).id, saved.id)
        XCTAssertEqual(store.data.entries.count, 2)
        AudioSelection.remove(selected)
        XCTAssertFalse(FileManager.default.fileExists(atPath: try XCTUnwrap(selected.first).path))
        XCTAssertNotNil(store.playbackURL(for: saved))
    }

    @MainActor func testDeleteUndoKeepsLocalAudioAndInterveningProgress() throws {
        let file = temporaryFile(); let store = LibraryStore(file: file)
        let entry = try store.remember("https://example.com/keep.mp3")
        store.move(entry.id, to: store.addFolder("Favorites"))
        store.deleteFolder("Favorites")
        XCTAssertNil(store.entry(entry.id)?.folder)
        store.setPosition(42, for: entry.id)
        let newer = try store.remember("https://example.com/new.mp3")
        store.undoDelete()
        XCTAssertEqual(store.entry(entry.id)?.folder, "Favorites")
        XCTAssertEqual(store.entry(entry.id)?.position, 42)
        XCTAssertNotNil(store.entry(newer.id))
        let incoming = file.deletingLastPathComponent().appendingPathComponent("undo.m4a")
        try Data([1, 2, 3]).write(to: incoming)
        let local = try store.importAudio(incoming)
        store.delete(local.id)
        XCTAssertTrue(store.canUndoDelete)
        XCTAssertNil(store.entry(local.id))
        store.undoDelete()
        XCTAssertEqual(store.entry(local.id), local)
        XCTAssertTrue(FileManager.default.fileExists(atPath: try XCTUnwrap(store.playbackURL(for: local)).path))
        XCTAssertFalse(store.canUndoDelete)
    }

    @MainActor func testUndoDoesNotDuplicateReaddedRecording() throws {
        let store = LibraryStore(file: temporaryFile())
        let old = try store.remember("https://example.com/same.mp3")
        store.delete(old.id)
        let new = try store.remember("https://example.com/same.mp3")
        store.undoDelete()
        XCTAssertEqual(store.data.entries.map(\.id), [new.id])
    }

    @MainActor func testRenamedURLAndFileReportAlreadySavedWithoutDuplicates() throws {
        let file = temporaryFile(); let store = LibraryStore(file: file)
        let original = try store.remember("https://example.com/original-name.mp3")
        store.move(original.id, to: store.addFolder("Favorites"))
        store.rename(original.id, title: "My title", show: "")
        store.setPosition(42, for: original.id)
        let again = try store.remember("https://EXAMPLE.com:443/original-name.mp3#time")
        XCTAssertEqual(again.id, original.id)
        XCTAssertEqual(again.title, "My title")
        XCTAssertEqual(again.folder, "Favorites")
        XCTAssertEqual(again.position, 42)
        XCTAssertEqual(store.duplicateNotice, "File already saved.")
        XCTAssertEqual(store.data.entries.count, 1)
        let directory = file.deletingLastPathComponent()
        let incoming = directory.appendingPathComponent("original.m4a")
        try Data([1, 4, 9, 16]).write(to: incoming)
        let local = try store.importAudio(incoming)
        store.rename(local.id, title: "Renamed local file", show: "")
        let reopened = LibraryStore(file: file)
        let repeated = try reopened.importAudio(incoming)
        XCTAssertEqual(repeated.id, local.id)
        XCTAssertEqual(repeated.title, "Renamed local file")
        XCTAssertEqual(reopened.duplicateNotice, "File already saved.")
        XCTAssertEqual(reopened.data.entries.count, 2)
        _ = try reopened.remember("https://other.example.com/original-name.mp3")
        XCTAssertNil(reopened.duplicateNotice)
        XCTAssertEqual(reopened.data.entries.count, 3)
    }

    @MainActor func testSourceGemCanBePinchedAndRotatedBeforeDrop() throws {
        let file = temporaryFile().deletingLastPathComponent().appendingPathComponent("decorations.json")
        let studio = StickerStudioStore(file: file); studio.begin()
        let view = StickerTouchView(frame: CGRect(x: 0, y: 0, width: 320, height: 600))
        view.studio = studio
        view.frames = ["stereo": CGRect(x: 0, y: 0, width: 320, height: 400)]
        view.beginSourceSession(GemChoice.all[0], at: CGPoint(x: 120, y: 500))
        view.beginPinch(); view.scaleActiveGesture(1.8)
        view.beginRotation(); view.rotateActiveGesture(.pi / 6)
        XCTAssertEqual(studio.draft.count, 3) // The source is not consumed before placement.
        view.moveActiveGesture(to: CGPoint(x: 160, y: 210)); view.endActiveGesture()
        XCTAssertEqual(studio.draft.count, 4)
        XCTAssertEqual(studio.draft.last?.size ?? 0, 35 * pow(1.8, 1.35), accuracy: 0.1)
        XCTAssertEqual(studio.draft.last?.rotation ?? 0, 30, accuracy: 0.1)
        studio.finish()
        XCTAssertEqual(StickerStudioStore(file: file).saved.last?.size ?? 0, 35 * pow(1.8, 1.35), accuracy: 0.1)
        XCTAssertEqual(GemChoice.all.count, 48)
    }

    @MainActor func testPinchCanShrinkGemToEightPointsAndPersist() throws {
        let file = temporaryFile().deletingLastPathComponent().appendingPathComponent("decorations.json")
        let studio = StickerStudioStore(file: file); studio.begin()
        let view = StickerTouchView(frame: CGRect(x: 0, y: 0, width: 320, height: 600))
        view.studio = studio; view.frames = ["stereo": CGRect(x: 0, y: 0, width: 320, height: 400)]
        view.beginSourceSession(GemChoice.all[0], at: CGPoint(x: 150, y: 500))
        view.beginPinch(); view.scaleActiveGesture(0.1)
        view.beginRotation(); view.rotateActiveGesture(.pi / 2)
        view.moveActiveGesture(to: CGPoint(x: 160, y: 210)); view.endActiveGesture()
        studio.finish()
        let saved = StickerStudioStore(file: file).saved.last
        XCTAssertEqual(saved?.size, 8)
        XCTAssertEqual(saved?.rotation, 90)
    }

    @MainActor func testStickerLayoutTransformPersistenceAndFiveItemPages() throws {
        let file = temporaryFile().deletingLastPathComponent().appendingPathComponent("decorations.json")
        let studio = StickerStudioStore(file: file)
        XCTAssertEqual(GemChoice.all.count, 48)
        XCTAssertEqual(studio.choices.count, 5)
        XCTAssertEqual(Set(studio.choices.map(\.shape)).count, 5)
        XCTAssertEqual(Set(GemChoice.all.map(\.id)).count, 48)
        XCTAssertTrue(GemChoice.all.allSatisfy { UIImage(named: $0.id) != nil })
        let firstPage = studio.choices.map(\.id)
        studio.changePage(1)
        XCTAssertNotEqual(studio.choices.map(\.id), firstPage)
        XCTAssertLessThanOrEqual(studio.choices.count, 5)
        studio.begin()
        var gem = PlacedGem(asset: GemChoice.all[0].id, x: 0, y: 1, size: 67, rotation: 43)
        gem.constrain(to: CGSize(width: 320, height: 440))
        let radians = gem.rotation * .pi / 180
        let extent = gem.size / 2 * (abs(cos(radians)) + abs(sin(radians)))
        XCTAssertGreaterThanOrEqual(gem.x * 320 - extent, 3.9)
        XCTAssertLessThanOrEqual(gem.y * 440 + extent, 436.1)
        studio.place(gem); studio.finish()
        XCTAssertFalse(studio.editing)
        let reopened = StickerStudioStore(file: file)
        XCTAssertEqual(reopened.saved.count, 4)
        XCTAssertEqual(reopened.saved.last?.rotation, 43)
        XCTAssertEqual(reopened.saved.last?.size, 67)
        reopened.begin(); reopened.remove(gem.id); reopened.finish()
        XCTAssertEqual(StickerStudioStore(file: file).saved.count, 3)
        // The sheet's supply does not shrink when a gem is placed or removed.
        XCTAssertEqual(GemChoice.all.count, 48)
    }

    @MainActor func testSleepCountdownWaitsWhilePaused() async throws {
        let player = AudioPlayer(store: LibraryStore(file: temporaryFile()))
        player.setSleepTimer(seconds: 3)
        try await Task.sleep(for: .milliseconds(1150))
        XCTAssertEqual(player.sleepRemaining, 3, accuracy: 0.01)
        XCTAssertTrue(player.sleepActive)
        XCTAssertNil(player.sleepDeadline)
        XCTAssertFalse(player.playing)
        player.cancelSleepTimer()
    }

    @MainActor func testLargeSeekCanReturnAndSleepPausesPlayback() async throws {
        let library = temporaryFile()
        let directory = library.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let original = directory.appendingPathComponent("long.caf")
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 8000, channels: 1))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 8000))
        buffer.frameLength = buffer.frameCapacity
        for index in 0..<8000 { buffer.floatChannelData![0][index] = 0 }
        do {
            let file = try AVAudioFile(forWriting: original, settings: format.settings)
            for _ in 0..<180 { try file.write(from: buffer) }
        }
        let store = LibraryStore(file: library)
        let entry = try store.importAudio(original)
        store.setPosition(12, for: entry.id)
        let player = AudioPlayer(store: store)
        player.load(try XCTUnwrap(store.entry(entry.id)))
        for _ in 0..<100 where player.loading { try await Task.sleep(for: .milliseconds(100)) }
        XCTAssertNil(player.message)
        XCTAssertEqual(player.position, 12, accuracy: 0.2)
        player.seek(100)
        // The new target is durable even before AVPlayer completes seeking.
        XCTAssertEqual(LibraryStore(file: library).entry(entry.id)?.position, 100)
        XCTAssertEqual(store.entry(entry.id)?.scrubReturnPosition ?? -1, 12, accuracy: 0.2)
        try await Task.sleep(for: .milliseconds(300))
        player.seek(175)
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(store.entry(entry.id)?.scrubReturnPosition ?? -1, 12, accuracy: 0.2)
        player.returnToSavedPosition()
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(player.position, 12, accuracy: 0.2)
        XCTAssertNil(store.entry(entry.id)?.scrubReturnPosition)
        player.skip(15)
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertNil(store.entry(entry.id)?.scrubReturnPosition)
        player.seek(120)
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertNotNil(player.visibleScrubReturnPosition)
        player.expireScrubReturnIfNeeded(now: Date().addingTimeInterval(31))
        XCTAssertNil(player.visibleScrubReturnPosition)
        XCTAssertNil(store.entry(entry.id)?.scrubReturnPosition)
        player.play()
        for _ in 0..<50 where !player.playing { try await Task.sleep(for: .milliseconds(100)) }
        XCTAssertTrue(player.playing)
        _ = try store.remember("https://example.com/queued-while-playing.mp3")
        XCTAssertEqual(player.currentID, entry.id)
        XCTAssertTrue(player.playing)
        player.setSleepTimer(seconds: 3)
        try await Task.sleep(for: .milliseconds(500))
        player.pause()
        let remainingWhilePaused = player.sleepRemaining
        XCTAssertGreaterThan(remainingWhilePaused, 2)
        XCTAssertLessThan(remainingWhilePaused, 3)
        XCTAssertNil(player.sleepDeadline)
        try await Task.sleep(for: .milliseconds(600))
        XCTAssertEqual(player.sleepRemaining, remainingWhilePaused, accuracy: 0.05)
        player.play()
        for _ in 0..<50 where !player.playing { try await Task.sleep(for: .milliseconds(100)) }
        XCTAssertNotNil(player.sleepDeadline)
        player.setSleepTimer(seconds: 0.1)
        try await Task.sleep(for: .milliseconds(400))
        XCTAssertFalse(player.playing)
        XCTAssertNil(player.sleepDeadline)
        XCTAssertGreaterThan(store.entry(entry.id)?.position ?? 0, 26)
        player.reset()
    }

    @MainActor func testPausedSleepTimerReplacementAndCancellation() async throws {
        let player = AudioPlayer(store: LibraryStore(file: temporaryFile()))
        player.setSleepTimer(seconds: 0.1)
        XCTAssertTrue(player.sleepActive); XCTAssertNil(player.sleepDeadline)
        player.setSleepTimer(seconds: 5)
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(player.sleepRemaining, 5, accuracy: 0.01)
        player.cancelSleepTimer()
        XCTAssertFalse(player.sleepActive); XCTAssertNil(player.sleepDeadline)
        player.setSleepTimer(seconds: 0.1)
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertTrue(player.sleepActive)
        XCTAssertFalse(player.playing)
        player.setSleepTimer(seconds: 60)
        player.reset()
        XCTAssertFalse(player.sleepActive); XCTAssertNil(player.sleepDeadline)
    }

    @MainActor func testScrubReturnPositionPersistsWithoutChangingProgress() throws {
        let file = temporaryFile(); let store = LibraryStore(file: file)
        let entry = try store.remember("https://example.com/bookmark.mp3")
        store.setPosition(600, for: entry.id)
        store.setScrubReturnPosition(120, for: entry.id)
        let reopened = LibraryStore(file: file)
        XCTAssertEqual(reopened.entry(entry.id)?.position, 600)
        XCTAssertEqual(reopened.entry(entry.id)?.scrubReturnPosition, 120)
        reopened.setScrubReturnPosition(nil, for: entry.id)
        XCTAssertNil(LibraryStore(file: file).entry(entry.id)?.scrubReturnPosition)
    }

    @MainActor func testListenedStatusPersistsAndOldBackupsStillOpen() throws {
        let file = temporaryFile(); let store = LibraryStore(file: file)
        let entry = try store.remember("https://example.com/listened.mp3")
        XCTAssertNotEqual(entry.listened, true)
        store.setListened(true, for: entry.id)
        let reopened = LibraryStore(file: file)
        XCTAssertEqual(reopened.entry(entry.id)?.listened, true)
        reopened.setListened(false, for: entry.id)
        XCTAssertEqual(LibraryStore(file: file).entry(entry.id)?.listened, false)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: store.exportData()) as? [String: Any])
        var entries = try XCTUnwrap(json["entries"] as? [[String: Any]])
        entries[0].removeValue(forKey: "listened"); json["entries"] = entries
        try reopened.restore(JSONSerialization.data(withJSONObject: json))
        XCTAssertNotEqual(reopened.entry(entry.id)?.listened, true)
    }

    @MainActor func testFolderRenamePersistsContentsAndDeleteReturnsThemToArchive() throws {
        let file = temporaryFile(); let store = LibraryStore(file: file)
        let entry = try store.remember("https://example.com/folder-rename.mp3")
        let metadata = ResolvedAudio(source: entry.url, title: "Episode", show: "Show")
        store.apply(metadata, to: entry.id)
        store.setPosition(42, for: entry.id)
        XCTAssertEqual(store.renameFolder("Show", to: " Favorites "), "Favorites")
        store.apply(metadata, to: entry.id)
        XCTAssertEqual(store.entry(entry.id)?.folder, "Favorites")
        store.addFolder("Other")
        XCTAssertNil(store.renameFolder("Favorites", to: "OTHER"))
        XCTAssertNil(store.renameFolder("Favorites", to: " "))
        let reopened = LibraryStore(file: file)
        XCTAssertEqual(reopened.entry(entry.id)?.folder, "Favorites")
        XCTAssertEqual(reopened.entry(entry.id)?.position, 42)
        reopened.deleteFolder("Favorites")
        reopened.apply(metadata, to: entry.id)
        XCTAssertNil(reopened.entry(entry.id)?.folder)
        XCTAssertEqual(reopened.entry(entry.id)?.title, "Episode")
        XCTAssertEqual(reopened.data.entries.count, 1)
    }

    @MainActor func testResetCancelsLoadAndClearsSelectionWithoutDeletingLibrary() async throws {
        let file = temporaryFile()
        let store = LibraryStore(file: file)
        let entry = try store.remember("https://example.com/reset.mp3")
        store.move(entry.id, to: store.addFolder("Favorites"))
        store.setPosition(87, for: entry.id)
        store.select(entry.id)
        let player = AudioPlayer(store: store)
        player.load(store.entry(entry.id)!)
        player.message = "Old playback error"
        player.reset()
        await Task.yield()
        player.restoreLast()
        XCTAssertNil(player.currentID)
        XCTAssertNil(player.message)
        XCTAssertFalse(player.loading)
        XCTAssertFalse(player.playing)
        XCTAssertEqual(player.position, 0)
        XCTAssertEqual(player.duration, 0)
        let reopened = LibraryStore(file: file)
        XCTAssertNil(reopened.data.lastID)
        XCTAssertEqual(reopened.entry(entry.id)?.position, 87)
        XCTAssertEqual(reopened.entry(entry.id)?.folder, "Favorites")
    }

    @MainActor func testLibrarySurvivesRelaunchWithFoldersNamesAndPositions() throws {
        let file = temporaryFile()
        let store = LibraryStore(file: file)
        let entry = try store.remember("https://example.com/episode.mp3")
        let folder = store.addFolder("Favorites")
        store.move(entry.id, to: folder)
        store.rename(entry.id, title: "Episode One", show: "My Show")
        store.setPosition(142.5, for: entry.id)
        store.select(entry.id)
        let reopened = LibraryStore(file: file)
        XCTAssertEqual(reopened.entry(entry.id)?.title, "Episode One")
        XCTAssertEqual(reopened.entry(entry.id)?.show, "My Show")
        XCTAssertEqual(reopened.entry(entry.id)?.position, 142.5)
        XCTAssertEqual(reopened.entry(entry.id)?.folder, "Favorites")
        XCTAssertEqual(reopened.data.lastID, entry.id)
        XCTAssertNil(reopened.storageError)
    }

    @MainActor func testAutomaticFoldersRespectManualEditsAndDeletedFolders() throws {
        let store = LibraryStore(file: temporaryFile())
        let entry = try store.remember("https://example.com/episode.mp3")
        let result = ResolvedAudio(source: entry.url, title: "Automatic title", show: "Show")
        store.apply(result, to: entry.id)
        XCTAssertEqual(store.entry(entry.id)?.folder, "Show")
        store.rename(entry.id, title: "My title", show: "My show")
        store.apply(result, to: entry.id)
        XCTAssertEqual(store.entry(entry.id)?.title, "My title")
        store.deleteFolder("My show")
        store.apply(result, to: entry.id)
        XCTAssertNil(store.entry(entry.id)?.folder)
    }

    @MainActor func testDedupeDeleteAndFailedLoadPersistence() throws {
        let file = temporaryFile(); let store = LibraryStore(file: file)
        let first = try store.remember("https://example.com/episode")
        XCTAssertEqual(try store.remember(first.url.absoluteString).id, first.id)
        XCTAssertEqual(LibraryStore(file: file).data.entries.count, 1)
        store.select(first.id); store.delete(first.id)
        let reopened = LibraryStore(file: file)
        XCTAssertTrue(reopened.data.entries.isEmpty)
        XCTAssertNil(reopened.data.lastID)
        store.apply(ResolvedAudio(source: first.url, title: "Late response", show: "Show"), to: first.id)
        XCTAssertTrue(store.data.entries.isEmpty)
        XCTAssertTrue(store.data.folders.isEmpty)
    }

    @MainActor func testLinkAliasesShareOneRecordingAndKeepFolderAndPosition() throws {
        let store = LibraryStore(file: temporaryFile())
        let direct = try store.remember("https://example.com/episode.mp3")
        store.move(direct.id, to: store.addFolder("Favorites"))
        store.setPosition(87, for: direct.id)
        store.rename(direct.id, title: "My episode", show: "My show")
        XCTAssertEqual(try store.remember("https://EXAMPLE.com:443/episode.mp3#t=20").id, direct.id)
        let page = try store.remember("https://example.com/episode-page")
        let resolved = store.apply(ResolvedAudio(source: direct.url, title: "Fetched title", show: "Fetched show"), to: page.id)
        XCTAssertEqual(resolved?.id, direct.id)
        XCTAssertEqual(resolved?.position, 87)
        XCTAssertEqual(resolved?.folder, "Favorites")
        XCTAssertEqual(resolved?.title, "My episode")
        XCTAssertEqual(try store.remember(page.url.absoluteString).id, direct.id)
        XCTAssertEqual(store.data.entries.count, 1)
        let restored = LibraryStore(file: temporaryFile())
        try restored.restore(store.exportData())
        XCTAssertEqual(try restored.remember(page.url.absoluteString).id, direct.id)
        // Distinct query parameters can identify distinct audio; do not strip them.
        let one = try store.remember("https://example.com/audio?id=1")
        XCTAssertNotEqual(try store.remember("https://example.com/audio?id=2").id, one.id)
    }

    @MainActor func testRepeatedFileImportUsesContentAndPreservesArchiveEntry() throws {
        let file = temporaryFile()
        let directory = file.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let original = directory.appendingPathComponent("one.m4a")
        let renamed = directory.appendingPathComponent("renamed.m4a")
        try Data([1, 2, 3, 4]).write(to: original)
        try FileManager.default.copyItem(at: original, to: renamed)
        let store = LibraryStore(file: file)
        let first = try store.importAudio(original)
        store.move(first.id, to: store.addFolder("Favorites"))
        store.setPosition(23, for: first.id)
        // Simulate an older saved library that predates content hashes.
        var legacy = try JSONDecoder().decode(LibraryData.self, from: store.exportData())
        legacy.entries[0].contentHash = nil
        try store.restore(JSONEncoder().encode(legacy))
        let reopened = LibraryStore(file: file)
        let again = try reopened.importAudio(renamed)
        XCTAssertEqual(again.id, first.id)
        XCTAssertEqual(again.folder, "Favorites")
        XCTAssertEqual(again.position, 23)
        XCTAssertEqual(reopened.data.entries.count, 1)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: reopened.audioDirectory.path).count, 1)
        // Same filename with different bytes must still be importable.
        try Data([5, 6, 7]).write(to: renamed)
        XCTAssertNotEqual(try reopened.importAudio(renamed).id, first.id)
        XCTAssertEqual(reopened.data.entries.count, 2)
    }

    @MainActor func testBackupAndCorruptFilePreservation() throws {
        let file = temporaryFile()
        let store = LibraryStore(file: file)
        _ = try store.remember("https://example.com/test.mp3")
        let backup = try store.exportData()
        let broken = Data("not json".utf8)
        try broken.write(to: file)
        let reopened = LibraryStore(file: file)
        XCTAssertNotNil(reopened.storageError)
        _ = try reopened.remember("https://example.com/other.mp3")
        XCTAssertEqual(try Data(contentsOf: file), broken)
        XCTAssertThrowsError(try reopened.restore(broken))
        try reopened.restore(backup)
        XCTAssertNil(reopened.storageError)
        XCTAssertEqual(reopened.data.entries.count, 1)
        XCTAssertEqual(reopened.data.entries[0].url.absoluteString, "https://example.com/test.mp3")
    }

    func testRSSMetadata() throws {
        let xml = """
        <rss><channel><title>Example Show</title><item><title><![CDATA[Episode & One]]></title><link>https://example.com/episode</link><enclosure url="https://cdn.example.com/one.mp3" type="audio/mpeg"/></item></channel></rss>
        """
        let feed = try XCTUnwrap(RSSReader.read(Data(xml.utf8), base: URL(string: "https://example.com/feed")!))
        XCTAssertEqual(feed.show, "Example Show")
        XCTAssertEqual(feed.episodes.first?.title, "Episode & One")
        XCTAssertEqual(feed.episodes.first?.show, "Example Show")
        XCTAssertEqual(feed.episodes.first?.source.absoluteString, "https://cdn.example.com/one.mp3")
    }
    func testArchiveNormalizationPreservesExactRecording() {
        let url = URL(string: "https://ia601608.us.archive.org/19/items/book/part%20two.mp3")!
        XCTAssertEqual(AudioResolver.archiveDownload(url)?.absoluteString, "https://archive.org/download/book/part%20two.mp3")
    }
    func testExampleMP3ResolvesWithoutNetworkMetadata() async throws {
        let url = URL(string: "https://d3ctxlq1ktw2nl.cloudfront.net/staging/2021-7-19/213635671-32000-2-0b2c7ddfc1a111e3.mp3")!
        let audio = try await AudioResolver().resolve(url)
        XCTAssertEqual(audio.source, url)
        XCTAssertTrue(audio.show.isEmpty)
    }
    @MainActor func testImportedM4APersistsIndependentlyOfOriginal() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let original = directory.appendingPathComponent("My recording.m4a")
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 44100 * 4))
        buffer.frameLength = buffer.frameCapacity
        for i in 0..<Int(buffer.frameLength) { buffer.floatChannelData![0][i] = Float(sin(Double(i) * 2 * .pi * 440 / 44100)) * 0.01 }
        do {
            let audioFile = try AVAudioFile(forWriting: original, settings: [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 44100, AVNumberOfChannelsKey: 1, AVEncoderBitRateKey: 64000])
            try audioFile.write(from: buffer)
        }
        let libraryURL = directory.appendingPathComponent("App/library.json")
        let store = LibraryStore(file: libraryURL)
        let entry = try store.importAudio(original)
        store.setPosition(1.25, for: entry.id)
        let folder = store.addFolder("Voice notes"); store.move(entry.id, to: folder)
        store.select(entry.id)
        try FileManager.default.removeItem(at: original)
        let reopened = LibraryStore(file: libraryURL)
        let restored = try XCTUnwrap(reopened.entry(entry.id))
        XCTAssertEqual(restored.title, "My recording")
        XCTAssertEqual(restored.folder, "Voice notes")
        XCTAssertTrue(FileManager.default.fileExists(atPath: try XCTUnwrap(reopened.playbackURL(for: restored)).path))
        let player = AudioPlayer(store: reopened)
        player.restoreLast()
        XCTAssertEqual(player.currentID, restored.id)
        for _ in 0..<100 where player.loading { try await Task.sleep(nanoseconds: 100_000_000) }
        XCTAssertFalse(player.loading)
        XCTAssertNil(player.message)
        XCTAssertGreaterThan(player.duration, 3.9)
        XCTAssertGreaterThan(reopened.entry(entry.id)?.duration ?? 0, 3.9)
        XCTAssertEqual(reopened.entry(entry.id)?.progressFraction ?? -1, 1.25 / player.duration, accuracy: 0.02)
        XCTAssertEqual(player.position, 1.25, accuracy: 0.15)
        player.play()
        try await Task.sleep(nanoseconds: 1_500_000_000)
        player.pause()
        XCTAssertGreaterThan(player.position, 1.25)
        XCTAssertGreaterThan(reopened.entry(entry.id)?.position ?? 0, 1.25)
        player.stop()
        let backup = try reopened.exportData()
        try reopened.restore(backup)
        XCTAssertEqual(reopened.entry(entry.id)?.localFilename, entry.localFilename)
        reopened.delete(entry.id)
        XCTAssertNil(reopened.entry(entry.id))
        reopened.undoDelete()
        XCTAssertNotNil(reopened.entry(entry.id))
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.audioDirectory.appendingPathComponent(entry.localFilename!).path))
    }

    @MainActor func testImportedMP4PlaysFromItsSavedCopy() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let source = directory.appendingPathComponent("source.m4a")
        let original = directory.appendingPathComponent("Local audio.mp4")
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 44100))
        buffer.frameLength = buffer.frameCapacity
        for i in 0..<Int(buffer.frameLength) { buffer.floatChannelData![0][i] = 0 }
        do {
            let file = try AVAudioFile(forWriting: source, settings: [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 44100, AVNumberOfChannelsKey: 1])
            try file.write(from: buffer)
        }
        let export = try XCTUnwrap(AVAssetExportSession(asset: AVURLAsset(url: source), presetName: AVAssetExportPresetPassthrough))
        export.outputURL = original; export.outputFileType = .mp4
        await export.export()
        XCTAssertEqual(export.status, .completed, export.error?.localizedDescription ?? "MP4 export failed")
        let library = directory.appendingPathComponent("App/library.json")
        let store = LibraryStore(file: library)
        let entry = try store.importAudio(original)
        XCTAssertNil(entry.folder)
        XCTAssertEqual(try store.importAudio(original).id, entry.id)
        try FileManager.default.removeItem(at: original)
        let reopened = LibraryStore(file: library)
        let player = AudioPlayer(store: reopened)
        player.load(try XCTUnwrap(reopened.entry(entry.id)))
        for _ in 0..<100 where player.loading { try await Task.sleep(for: .milliseconds(100)) }
        XCTAssertNil(player.message)
        XCTAssertGreaterThan(player.duration, 0.9)
        player.reset()
    }

}
