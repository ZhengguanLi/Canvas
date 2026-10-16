import AppKit
import XCTest
@testable import ProjectCanvas

final class ClipboardLimitTests: XCTestCase {
    @MainActor func testIndependentLimitsPersistAndKeepNewestWhenReduced() throws {
        let name = "ClipboardLimitTests.\(UUID().uuidString)"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { preferences.removePersistentDomain(forName: name) }
        let history = ClipboardHistory(preferences: preferences)
        XCTAssertEqual(history.textLimit, 50)
        XCTAssertEqual(history.imageLimit, 50)
        history.setLimits(text: 100, images: 50)
        for index in 0..<110 { history.receiveText("Item \(index)") }
        XCTAssertEqual(history.texts.count, 100)
        history.setLimits(text: 25, images: 0)
        XCTAssertEqual(history.texts.count, 25)
        XCTAssertEqual(history.texts.first?.text, "Item 109")
        XCTAssertEqual(history.texts.last?.text, "Item 85")
        let reopened = ClipboardHistory(preferences: preferences)
        XCTAssertEqual(reopened.textLimit, 25)
        XCTAssertEqual(reopened.imageLimit, 0)
        XCTAssertTrue(reopened.texts.isEmpty)
        history.setLimits(text: 0)
        for index in 110..<350 { history.receiveText("Item \(index)") }
        XCTAssertEqual(history.texts.count, 265)
        XCTAssertEqual(history.imageLimit, 0)
        history.setLimits(text: 50)
        XCTAssertEqual(history.texts.count, 50)
        XCTAssertEqual(history.imageLimit, 0)
    }

    @MainActor func testImageLimitTrimsOldestWithoutRemovingText() throws {
        let name = "ClipboardImageLimitTests.\(UUID().uuidString)"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { preferences.removePersistentDomain(forName: name) }
        let history = ClipboardHistory(preferences: preferences)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 4, pixelsHigh: 4,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let pixels = try XCTUnwrap(bitmap.bitmapData)
        pixels.initialize(repeating: 255, count: bitmap.bytesPerRow * 4)
        let thumbnail = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        for number in 1...30 {
            history.receiveImage(ClipboardHistory.PreparedImage(data: Data([UInt8(number)]), thumbnail: thumbnail), type: .png)
        }
        history.receiveText("Keep this")
        history.setLimits(images: 25)
        XCTAssertEqual(history.images.count, 25)
        XCTAssertEqual(history.images.first?.data, Data([30]))
        XCTAssertEqual(history.images.last?.data, Data([6]))
        XCTAssertEqual(history.texts.first?.text, "Keep this")
    }

    @MainActor func testLegacyLimitsRoundUpToPresetsWithoutUnexpectedlyReducingRetention() throws {
        let name = "ClipboardLegacyLimits.\(UUID().uuidString)"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { preferences.removePersistentDomain(forName: name) }
        preferences.set(37, forKey: ClipboardHistory.textLimitKey)
        preferences.set(200, forKey: ClipboardHistory.imageLimitKey)
        let history = ClipboardHistory(preferences: preferences)
        XCTAssertEqual(history.textLimit, 50)
        XCTAssertEqual(history.imageLimit, 0)
    }

}
