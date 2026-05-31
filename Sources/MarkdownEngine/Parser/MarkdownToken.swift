//
//  MarkdownToken.swift
//  MarkdownEngine
//
//  Created by Luca Chen on 18.02.26.
//

// Defines the basic Markdown building blocks the editor works with (bold,
// links, code, LaTeX, etc.), plus shared text attributes.
import AppKit
import Foundation

extension NSAttributedString.Key {
    public static let wikiLinkID = NSAttributedString.Key("NodeLinkID")
    public static let taskCheckbox = NSAttributedString.Key("TaskCheckbox")
}

enum MarkdownTokenKind {
    case italic
    case boldItalic
    case bold
    case link
    case wikiLink
    case heading
    /// One line of a blockquote. `markerRanges[0]` is the `>`/`>>`… run
    /// (hidden when inactive); `contentRange` is the quoted text. The
    /// nesting level is the count of `>` in the marker.
    case blockquote
    case codeBlock
    case inlineCode
    case blockLatex
    case inlineLatex
    case imageEmbed
    case imageLink
    case strikethrough
    case table
    /// A CommonMark backslash escape (`\*`, `` \` ``, `\\`, …). The marker
    /// is the backslash (hidden when inactive); the content is the single
    /// escaped, now-literal punctuation character.
    case backslashEscape
}

struct MarkdownToken {
    let kind: MarkdownTokenKind
    let range: NSRange
    let contentRange: NSRange
    let markerRanges: [NSRange]
}

extension MarkdownToken {
    func standaloneParagraphRange(in text: NSString) -> NSRange? {
        let paragraphRange = text.paragraphRange(for: range)
        let paragraphText = text.substring(with: paragraphRange) as NSString
        let tokenRelativeRange = NSRange(
            location: range.location - paragraphRange.location,
            length: range.length
        )
        let mutableParagraph = paragraphText.mutableCopy() as! NSMutableString
        mutableParagraph.replaceCharacters(in: tokenRelativeRange, with: "")
        return mutableParagraph.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? paragraphRange : nil
    }

    func containsSelectionOrStandaloneParagraph(_ selectionLocation: Int, in text: NSString) -> Bool {
        let start = range.location
        let end = NSMaxRange(range) - 1
        if selectionLocation >= start && selectionLocation <= end {
            return true
        }

        guard let paragraphRange = standaloneParagraphRange(in: text) else {
            return false
        }
        let paragraphEnd = NSMaxRange(paragraphRange)
        // Keep the source revealed when the caret sits at the very end of the
        // document right after the image — but NOT when that paragraph ends in a
        // newline, i.e. the caret jumped to a fresh line below (the user pressed
        // Enter). Otherwise the syntax stays revealed until the next keystroke.
        let endsWithNewline = paragraphEnd > paragraphRange.location
            && (text.character(at: paragraphEnd - 1) == 0x0A || text.character(at: paragraphEnd - 1) == 0x0D)
        let isAtLastParagraphEnd = selectionLocation == text.length
            && paragraphEnd == text.length && !endsWithNewline
        return (selectionLocation >= paragraphRange.location && selectionLocation < paragraphEnd)
            || isAtLastParagraphEnd
    }
}
