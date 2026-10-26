import XCTest

final class EarmarkUITests: XCTestCase {
    @MainActor private func scrollArchive(_ app: XCUIApplication) {
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.8))
            .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.3)))
    }
    private func testApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["EARMARK_UI_TEST_LIBRARY"] = UUID().uuidString
        return app
    }
    @MainActor func testGlobalAndFolderListeningTabsShareStatus() {
        let app = testApp(); app.launch()
        let link = app.textFields["linkField"]
        XCTAssertTrue(link.waitForExistence(timeout: 5))
        link.tap(); link.typeText("https://example.com/status-only.mp3")
        app.buttons["loadLink"].tap()
        scrollArchive(app)
        app.buttons["folderHeader-"].tap()
        let local = app.buttons["Options for status-only"]
        for _ in 0..<3 where !local.isHittable { scrollArchive(app) }
        local.tap(); app.buttons["Mark as listened"].tap()
        XCTAssertTrue(local.waitForNonExistence(timeout: 5))
        app.buttons["status-listened-folder-"].tap()
        XCTAssertTrue(local.waitForExistence(timeout: 5))
        let globalTab = app.buttons["status-listened-global"]
        for _ in 0..<3 where !globalTab.isHittable { scrollArchive(app) }
        globalTab.tap()
        let global = app.buttons["Options for status-only, Unarchived"]
        XCTAssertTrue(global.waitForExistence(timeout: 5))
        global.tap(); app.buttons["Mark as unlistened"].tap()
        XCTAssertTrue(global.waitForNonExistence(timeout: 5))
        app.buttons["status-listening-global"].tap()
        XCTAssertTrue(global.waitForExistence(timeout: 5))
        app.terminate(); app.launch(); scrollArchive(app)
        XCTAssertTrue(global.waitForExistence(timeout: 5))
    }

    @MainActor func testAutomaticSaveDuplicateNoticeAndSleepCountdown() {
        let app = testApp(); app.launch()
        let link = app.textFields["linkField"]
        XCTAssertTrue(link.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["saveArchive"].exists)
        XCTAssertEqual(app.buttons["loadLink"].label, "load")
        XCTAssertEqual(app.buttons["loadLink"].frame.midY, app.buttons["importAudio"].frame.midY, accuracy: 2)
        XCTAssertEqual(app.buttons["loadLink"].frame.midY, app.buttons["saveArchive"].frame.midY, accuracy: 2)
        link.tap(); link.typeText("https://example.com/saved-only.mp3")
        app.buttons["loadLink"].tap()
        app.buttons["loadLink"].tap()
        XCTAssertTrue(app.staticTexts["duplicateNotice"].waitForExistence(timeout: 5))
        app.buttons["sleepTimer"].tap(); app.buttons["15 minutes"].tap()
        XCTAssertTrue(app.staticTexts["sleepCountdown"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["sleepTimer"].label.contains(":"))
        let active = XCTAttachment(screenshot: app.screenshot()); active.name = "Loaded stereo with sleep countdown"; active.lifetime = .keepAlways; add(active)
        app.buttons["sleepTimer"].tap(); app.buttons["Cancel sleep timer"].tap()
        XCTAssertTrue(app.staticTexts["sleepCountdown"].waitForNonExistence(timeout: 5))
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Sleep timer cancelled"; screenshot.lifetime = .keepAlways; add(screenshot)
        app.buttons["sleepTimer"].tap()
        XCTAssertFalse(app.buttons["Cancel sleep timer"].exists)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.2)).tap()
    }

    @MainActor func testArchiveWithoutLoadingAndDeleteUndo() {
        let app = testApp(); app.launch()
        let field = app.textFields["linkField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap(); field.typeText("https://example.com/archive-only.mp3")
        app.buttons["saveArchive"].tap(); app.buttons["archiveLink"].tap()
        XCTAssertEqual(app.staticTexts["nowPlayingTitle"].label, "A little listening time")
        XCTAssertFalse(app.otherElements["loadedLight"].exists)
        scrollArchive(app)
        let row = app.buttons["Options for archive-only, Unarchived"]
        for _ in 0..<3 where !row.isHittable { scrollArchive(app) }
        XCTAssertTrue(row.exists)
        row.tap(); app.buttons["Delete"].tap()
        XCTAssertTrue(row.waitForNonExistence(timeout: 5))
        app.buttons["undoDelete"].tap()
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        app.buttons["Create folder"].tap()
        app.alerts["New folder"].textFields.firstMatch.typeText("Test folder")
        app.alerts["New folder"].buttons["Create"].tap()
        XCTAssertTrue(app.buttons["folderHeader-Test folder"].waitForExistence(timeout: 5))
        app.buttons["folderHeader-Test folder"].swipeLeft()
        app.buttons["deleteFolder-Test folder"].tap()
        app.buttons["undoDelete"].tap()
        XCTAssertTrue(app.buttons["folderHeader-Test folder"].waitForExistence(timeout: 5))
    }

    @MainActor func testStickerPagesDragAndDonePersist() {
        let app = testApp(); app.launch()
        let decorate = app.buttons["decorateStereo"]
        XCTAssertTrue(decorate.waitForExistence(timeout: 5))
        decorate.tap()
        for _ in 0..<3 where app.buttons["stickerSource-Gem_heart_green"].frame.maxY > app.frame.height - 150 { scrollArchive(app) }
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "stickerSource-")).count, 5)
        let source = app.buttons["stickerSource-Gem_heart_green"]
        let target = app.otherElements["stereoPlayer"]
        let destination = target.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.675))
        let dropPoint = destination.screenPoint
        source.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 0.3, thenDragTo: destination, withVelocity: .slow, thenHoldForDuration: 0.2)
        let placed = app.images["Placed heart green sticker"]
        XCTAssertTrue(placed.waitForExistence(timeout: 5))
        XCTAssertEqual(placed.frame.midX, dropPoint.x, accuracy: 18)
        XCTAssertEqual(placed.frame.midY, dropPoint.y, accuracy: 18)
        // Resize and rotate in one movement with the selected sticker's corner handle.
        let center = CGPoint(x: placed.frame.midX, y: placed.frame.midY)
        let origin = app.coordinate(withNormalizedOffset: .zero)
        let handle = origin.withOffset(CGVector(dx: center.x + 25.5, dy: center.y + 25.5))
        let smaller = origin.withOffset(CGVector(dx: center.x + 6, dy: center.y - 6))
        handle.press(forDuration: 0.15, thenDragTo: smaller, withVelocity: .slow, thenHoldForDuration: 0.1)
        let description = placed.value as? String ?? ""
        let size = Double(description.components(separatedBy: ",").first?.replacingOccurrences(of: "Size ", with: "") ?? "") ?? 100
        XCTAssertLessThanOrEqual(size, 12, description)
        XCTAssertFalse(description.contains("rotation 0 degrees"), description)
        let sheet = XCTAttachment(screenshot: app.screenshot()); sheet.name = "Glossy sticker sheet and resized gem"; sheet.lifetime = .keepAlways; add(sheet)
        app.buttons["stickerDone"].tap()
        app.terminate(); app.launch()
        let count = app.otherElements["Stereo decorations"]
        XCTAssertTrue(count.waitForExistence(timeout: 5))
        XCTAssertEqual(count.value as? String, "4 stickers")
        app.buttons["decorateStereo"].tap()
        for _ in 0..<3 where app.buttons["stickerSource-Gem_heart_green"].frame.maxY > app.frame.height - 150 { scrollArchive(app) }
        let row = app.buttons["stickerSource-Gem_diamond_purple"]
        row.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5)).press(forDuration: 0.05, thenDragTo: app.buttons["stickerSource-Gem_heart_green"].coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.5)))
        XCTAssertTrue(app.buttons["stickerSource-Gem_butterfly_silver"].waitForExistence(timeout: 5))
    }

    @MainActor func testDragArchiveEntryIntoFolder() {
        let app = testApp(); app.launch()
        let title = "drag-ui-\(UUID().uuidString)"
        let link = app.textFields["linkField"]
        XCTAssertTrue(link.waitForExistence(timeout: 5))
        link.tap(); link.typeText("https://example.com/\(title).mp3")
        app.buttons["loadLink"].tap()
        XCTAssertTrue(app.staticTexts["error"].waitForExistence(timeout: 15))
        scrollArchive(app)
        app.buttons["Create folder"].tap()
        let field = app.alerts["New folder"].textFields.firstMatch
        field.tap(); field.typeText("Listening")
        app.alerts["New folder"].buttons["Create"].tap()
        app.buttons["Expand Unarchived"].tap()
        let item = app.buttons["Options for \(title)"]
        scrollArchive(app)
        item.press(forDuration: 1, thenDragTo: app.buttons["folderMenu-Listening"], withVelocity: .slow, thenHoldForDuration: 1)
        XCTAssertTrue(app.buttons["folderHeader-Listening"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["folderHeader-Listening"].label, "Listening · 1")
        app.terminate(); app.launch(); scrollArchive(app)
        XCTAssertTrue(app.buttons["folderHeader-Listening"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["folderHeader-Listening"].label, "Listening · 1")
    }
    @MainActor func testArchiveItemMenuRenamesAndLoads() {
        let app = testApp(); app.launch()
        let title = "original"
        let link = app.textFields["linkField"]
        XCTAssertTrue(link.waitForExistence(timeout: 5))
        link.tap(); link.typeText("https://example.com/\(title).mp3")
        app.buttons["loadLink"].tap()
        XCTAssertTrue(app.staticTexts["error"].waitForExistence(timeout: 15))
        scrollArchive(app)
        app.buttons["Expand Unarchived"].tap()
        let item = app.buttons["Options for \(title)"]
        for _ in 0..<3 where !item.isHittable { scrollArchive(app) }
        item.tap()
        XCTAssertFalse(app.buttons["Move"].exists)
        app.buttons["Rename"].tap()
        let field = app.textFields["Episode or audio title"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: title.count) + "Renamed audio")
        app.buttons["Save"].tap()
        let renamed = app.buttons["Options for Renamed audio"]
        XCTAssertTrue(renamed.waitForExistence(timeout: 5))
        renamed.tap(); app.buttons["Mark as listened"].tap()
        app.buttons["status-listened-folder-"].tap()
        renamed.tap()
        XCTAssertTrue(app.buttons["Mark as unlistened"].waitForExistence(timeout: 5))
        app.buttons["Load in player"].tap()
        app.swipeDown(); app.swipeDown()
        XCTAssertEqual(app.staticTexts["nowPlayingTitle"].label, "Renamed audio")
    }
    @MainActor func testResetClearsPlayerAndImportPrecedesError() {
        let app = testApp(); app.launch()
        let link = app.textFields["linkField"]
        XCTAssertTrue(link.waitForExistence(timeout: 5))
        link.tap(); link.typeText("https://example.com/reset-ui-\(UUID().uuidString).mp3")
        app.buttons["loadLink"].tap()
        let error = app.staticTexts["error"]
        XCTAssertTrue(error.waitForExistence(timeout: 15))
        XCTAssertLessThan(app.buttons["importAudio"].frame.maxY, error.frame.minY)
        app.buttons["resetPlayer"].tap()
        XCTAssertFalse(error.exists)
        XCTAssertEqual(app.staticTexts["nowPlayingTitle"].label, "A little listening time")
        XCTAssertFalse(app.buttons["Play"].isEnabled)
        app.terminate(); app.launch()
        XCTAssertTrue(app.staticTexts["nowPlayingTitle"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["nowPlayingTitle"].label, "A little listening time")
    }
    @MainActor func testFolderAndSavedLinkSurviveTermination() throws {
        let app = testApp(); app.launch()
        let url = "https://example.com/ui-test-\(UUID().uuidString).mp3"
        let link = app.textFields["linkField"]
        XCTAssertTrue(link.waitForExistence(timeout: 5))
        link.tap(); link.typeText(url)
        app.buttons["loadLink"].tap()
        XCTAssertTrue(app.staticTexts["error"].waitForExistence(timeout: 15))
        scrollArchive(app)
        let folderName = "Favorites-\(Int(Date().timeIntervalSince1970))"
        app.buttons["Create folder"].tap()
        let field = app.alerts["New folder"].textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap(); field.typeText(folderName)
        XCTAssertEqual(field.value as? String, folderName)
        app.alerts["New folder"].buttons["Create"].tap()
        XCTAssertTrue(app.buttons["folderHeader-\(folderName)"].waitForExistence(timeout: 5))
        app.terminate(); app.launch(); scrollArchive(app)
        XCTAssertTrue(app.buttons["folderHeader-\(folderName)"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Unarchived ·")).firstMatch.exists)
        app.buttons["folderHeader-\(folderName)"].tap()
        XCTAssertTrue(app.buttons["Collapse \(folderName)"].exists)
        XCTAssertFalse(app.alerts["Rename folder"].exists)
        let folderMenu = app.buttons["folderMenu-\(folderName)"]
        for _ in 0..<6 where !folderMenu.isHittable { scrollArchive(app) }
        folderMenu.tap()
        app.buttons["Rename folder"].tap()
        let renamed = "Renamed-\(UUID().uuidString.prefix(6))"
        let renameField = app.alerts["Rename folder"].textFields.firstMatch
        renameField.tap()
        renameField.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: folderName.count) + renamed)
        app.alerts["Rename folder"].buttons["Save"].tap()
        let savedFolder = app.buttons["folderMenu-\(renamed)"]
        XCTAssertTrue(savedFolder.waitForExistence(timeout: 5))
        let cell = app.cells.containing(.button, identifier: "folderMenu-\(renamed)").firstMatch
        cell.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).press(forDuration: 0.1, thenDragTo: cell.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.5)))
        let delete = app.buttons["deleteFolder-\(renamed)"]
        XCTAssertTrue(delete.waitForExistence(timeout: 5))
        delete.tap()
        XCTAssertFalse(savedFolder.exists)
    }
    @MainActor func testThemeSwitchAndCompactPlayer() {
        let app = testApp(); app.launch()
        let theme = app.buttons["themeToggle"]
        XCTAssertTrue(theme.waitForExistence(timeout: 5))
        let before = theme.label
        theme.tap()
        XCTAssertNotEqual(theme.label, before)
        app.buttons["decorateStereo"].tap()
        scrollArchive(app)
        let lightSheet = XCTAttachment(screenshot: app.screenshot()); lightSheet.name = "Sticker sheet alternate theme"; lightSheet.lifetime = .keepAlways; add(lightSheet)
        app.buttons["stickerDone"].tap()
        app.terminate(); app.launch()
        XCTAssertNotEqual(app.buttons["themeToggle"].label, before)
        app.buttons["themeToggle"].tap()
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Earmark compact native player"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
    @MainActor func testImportAudioOpensFilesPicker() {
        let app = testApp(); app.launch()
        let button = app.buttons["importAudio"]
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        button.tap()
        let cancel = app.buttons["Cancel"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 5))
        cancel.tap()
        XCTAssertTrue(app.buttons["importAudio"].exists)
    }

}
