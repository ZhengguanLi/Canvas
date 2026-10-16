import XCTest
@testable import ProjectCanvas

final class LocalizationTests: XCTestCase {
    func testLanguagePreferencePersistsAndInvalidValueFallsBack() {
        let name = "LocalizationTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let controller = LanguageController(preferences: defaults, preferredLanguages: { ["zh-Hans-CN"] })
        XCTAssertEqual(controller.selection, .english)
        XCTAssertEqual(controller.resolvedLanguage, .english)
        controller.selection = .simplifiedChinese
        XCTAssertEqual(LanguageController(preferences: defaults).selection, .simplifiedChinese)
        defaults.set("invalid", forKey: LanguageController.preferenceKey)
        XCTAssertEqual(LanguageController(preferences: defaults).selection, .english)
    }

    func testSystemLanguageResolutionAndFallback() {
        XCTAssertEqual(AppLanguage.resolve(preferredLanguages: ["zh-Hans-CN"]), .simplifiedChinese)
        XCTAssertEqual(AppLanguage.resolve(preferredLanguages: ["en-GB"]), .english)
        XCTAssertEqual(AppLanguage.resolve(preferredLanguages: ["fr-FR"]), .english)
        XCTAssertEqual(AppLanguage.resolve(preferredLanguages: []), .english)
    }

    func testLanguageChangeNotifiesDesktopRefresh() {
        let name = "LocalizationNotifications.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let controller = LanguageController(preferences: defaults)
        let notification = expectation(forNotification: .projectCanvasLanguageChanged, object: nil)
        controller.selection = .simplifiedChinese
        wait(for: [notification], timeout: 1)
        XCTAssertEqual(controller.locale.identifier, "zh-Hans")
    }

    func testDictionaryAndUserContentFallback() {
        XCTAssertEqual(L10n.tr("取消", language: .english), "Cancel")
        XCTAssertEqual(L10n.tr("取消", language: .simplifiedChinese), "取消")
        XCTAssertEqual(L10n.tr("My personal project", language: .english), "My personal project")
        XCTAssertFalse(L10n.english.isEmpty)
        XCTAssertTrue(L10n.english.values.allSatisfy { !$0.isEmpty })
    }
    func testEveryApplicationTranslationKeyHasEnglishCopy() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let directory = root.appendingPathComponent("Sources/ProjectCanvas")
        let matcher = try NSRegularExpression(pattern: #"L10n\.(?:tr|format)\("((?:[^"\\]|\\.)*)""#)
        for file in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) where file.pathExtension == "swift" && file.lastPathComponent != "Localization.swift" {
            let source = try String(contentsOf: file)
            let nsSource = source as NSString
            for match in matcher.matches(in: source, range: NSRange(location: 0, length: nsSource.length)) {
                let escaped = nsSource.substring(with: match.range(at: 1))
                let key = escaped.replacingOccurrences(of: #"\n"#, with: "\n")
                XCTAssertNotNil(L10n.english[key], "Missing English copy in \(file.lastPathComponent): \(key)")
            }
        }
    }

}
