import Foundation
import Testing
@testable import MarkdownEngine

@Suite("Iframe source identity")
struct IframeSourceIDTests {
    @Test("source ID is stable when text is inserted above iframe")
    func sourceIDStableAfterInsertionAboveIframe() {
        let iframe = #"<iframe src="https://example.com" width="820" height="520"></iframe>"#
        let before = "Intro\n\n\(iframe)\n"
        let after = "Intro\nInserted text\n\n\(iframe)\n"

        #expect(sourceID(for: iframe, in: before) == sourceID(for: iframe, in: after))
    }

    @Test("source ID changes when iframe source changes")
    func sourceIDChangesWhenIframeSourceChanges() {
        let first = #"<iframe src="https://example.com/one" width="820" height="520"></iframe>"#
        let second = #"<iframe src="https://example.com/two" width="820" height="520"></iframe>"#

        #expect(sourceID(for: first, in: first) != sourceID(for: second, in: second))
    }

    @Test("duplicate identical iframes get distinct source IDs")
    func duplicateIdenticalIframesGetDistinctSourceIDs() {
        let iframe = #"<iframe src="https://example.com" width="820" height="520"></iframe>"#
        let text = "\(iframe)\n\n\(iframe)"
        let nsText = text as NSString
        let firstRange = nsText.range(of: iframe)
        let secondSearchRange = NSRange(location: NSMaxRange(firstRange), length: nsText.length - NSMaxRange(firstRange))
        let secondRange = nsText.range(of: iframe, options: [], range: secondSearchRange)

        let firstID = MarkdownStyler.iframeSourceID(for: token(range: firstRange), in: nsText)
        let secondID = MarkdownStyler.iframeSourceID(for: token(range: secondRange), in: nsText)

        #expect(firstID != secondID)
    }

    private func sourceID(for iframe: String, in text: String) -> Int {
        let nsText = text as NSString
        let range = nsText.range(of: iframe)
        return MarkdownStyler.iframeSourceID(for: token(range: range), in: nsText)
    }

    private func token(range: NSRange) -> MarkdownToken {
        MarkdownToken(
            kind: .iframeEmbed,
            range: range,
            contentRange: range,
            markerRanges: []
        )
    }
}
