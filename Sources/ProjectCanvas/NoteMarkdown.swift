import Foundation
import SwiftUI

/// Notes are stored as inline Markdown and edited as rich text. Bold, italics, code and links
/// round-trip; they may come from Markdown intents or from fonts set by the rich text editor.
enum NoteMarkdown {
    struct Traits: Equatable {
        var bold = false, italic = false, code = false
        var link: URL?
        var isPlain: Bool { !bold && !italic && !code && link == nil }
    }

    static func attributed(from markdown: String) -> AttributedString {
        (try? AttributedString(markdown: markdown, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(markdown)
    }

    /// `fontTraits` resolves a run's SwiftUI font (bold, italic, monospaced); it needs a view environment.
    static func markdown(from text: AttributedString,
                         fontTraits: (Font) -> (bold: Bool, italic: Bool, mono: Bool) = { _ in (false, false, false) }) -> String {
        var segments: [(String, Traits)] = []
        for run in text.runs {
            var traits = Traits(link: run.link)
            if let intent = run.inlinePresentationIntent {
                traits.bold = intent.contains(.stronglyEmphasized)
                traits.italic = intent.contains(.emphasized)
                traits.code = intent.contains(.code)
            }
            if let font = run.font {
                let resolved = fontTraits(font)
                traits.bold = traits.bold || resolved.bold
                traits.italic = traits.italic || resolved.italic
                traits.code = traits.code || resolved.mono
            }
            let string = String(text[run.range].characters)
            // Runs can split on attributes we do not serialise; merge neighbours with equal traits.
            if let last = segments.last, last.1 == traits { segments[segments.count - 1].0 += string }
            else { segments.append((string, traits)) }
        }
        return segments.map { wrap($0.0, $0.1) }.joined()
    }

    /// Markers cannot span line breaks or hug whitespace, so each line is wrapped separately
    /// and surrounding whitespace stays outside the markers.
    private static func wrap(_ text: String, _ traits: Traits) -> String {
        guard !traits.isPlain else { return escape(text) }
        return text.split(separator: "\n", omittingEmptySubsequences: false).map { line -> String in
            let leading = line.prefix { $0.isWhitespace }
            let trailing = String(line.reversed().prefix { $0.isWhitespace }.reversed())
            let core = line.dropFirst(leading.count).dropLast(trailing.count)
            guard !core.isEmpty else { return String(line) }
            var body = traits.code ? "`" + String(core).replacingOccurrences(of: "`", with: "") + "`" : escape(String(core))
            if traits.italic && !traits.code { body = "*" + body + "*" }
            if traits.bold { body = "**" + body + "**" }
            if let link = traits.link { body = "[" + body + "](" + link.absoluteString + ")" }
            return String(leading) + body + trailing
        }.joined(separator: "\n")
    }

    private static func escape(_ text: String) -> String {
        var result = ""
        for character in text {
            if "\\`*_[]".contains(character) { result.append("\\") }
            result.append(character)
        }
        return result
    }
}
