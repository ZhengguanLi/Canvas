import SwiftUI
import XCTest
@testable import ProjectCanvas

final class NoteMarkdownTests: XCTestCase {
    private func roundTrip(_ markdown: String) -> String {
        NoteMarkdown.markdown(from: NoteMarkdown.attributed(from: markdown))
    }

    func testInlineMarkdownRoundTrips() {
        for markdown in ["plain text", "**bold** and *italic*", "use `swift build` now", "[docs](https://example.com) here",
                         "line one\n**line two**", "", "***both***"] {
            XCTAssertEqual(NoteMarkdown.attributed(from: roundTrip(markdown)), NoteMarkdown.attributed(from: markdown), markdown)
        }
    }

    func testLiteralMarkdownCharactersAreEscaped() {
        var text = AttributedString("2 * 3 = 6 and a_b")
        text.inlinePresentationIntent = nil
        let markdown = NoteMarkdown.markdown(from: text)
        XCTAssertEqual(String(NoteMarkdown.attributed(from: markdown).characters), "2 * 3 = 6 and a_b")
    }

    func testEditorFontTraitsBecomeMarkdown() {
        var text = AttributedString("Ship it today")
        let range = text.range(of: "Ship")!
        text[range].font = .body.bold()
        let markdown = NoteMarkdown.markdown(from: text) { font in (font == .body.bold(), false, false) }
        XCTAssertEqual(markdown, "**Ship** it today")
    }

    func testWhitespaceStaysOutsideMarkers() {
        var text = AttributedString("a bold b")
        text[text.range(of: " bold ")!].inlinePresentationIntent = .stronglyEmphasized
        XCTAssertEqual(NoteMarkdown.markdown(from: text), "a **bold** b")
    }
}
