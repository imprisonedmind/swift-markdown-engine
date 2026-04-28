//
//  MarkdownEngineDecouplingTests.swift
//  MarkdownEngineTests
//
//  Smoke tests guarding the engine's decoupling boundary. Each test
//  exercises a protocol-default-implementation path so we catch
//  regressions where engine code accidentally re-introduces a
//  dependency on a concrete app type or singleton.
//

import Testing
import Foundation
import AppKit
@testable import MarkdownEngine

@Suite("Markdown engine decoupling")
struct MarkdownEngineDecouplingTests {

    // MARK: NoOp services stay inert

    @Test func noOpResolverReturnsNil() {
        let resolver = NoOpWikiLinkResolver()
        #expect(resolver.resolve(displayName: "Anything", range: NSRange(location: 0, length: 8)) == nil)
    }

    @Test func noOpImageProviderReturnsNil() {
        let provider = NoOpEmbeddedImageProvider()
        let request = EmbeddedImageRequest(name: "nope")
        #expect(provider.image(for: request) == nil)
    }

    @Test func noOpLatexRendererReturnsNil() {
        let renderer = NoOpLatexRenderer()
        let result = renderer.render(latex: "x^2", fontSize: 14, theme: .default)
        #expect(result == nil)
    }

    @Test func plainTextSyntaxHighlighterReturnsNoHighlighting() {
        let highlighter = PlainTextSyntaxHighlighter()
        #expect(highlighter.highlight(code: "let x = 1", language: "swift") == nil)
        #expect(highlighter.appearanceDidChangeNotification == nil)
    }

    // MARK: WikiLinkService roundtrip

    @Test func wikiLinkRoundtripsThroughDisplayAndStorage() {
        let storage = "Before [[Apple|11111111-2222-3333-4444-555555555555]] after"
        let display = WikiLinkService.makeDisplayState(from: storage)
        #expect(display.display == "Before [[Apple]] after")
        #expect(display.metadata.count == 1)
        let firstID = display.metadata.values.first?.id
        #expect(firstID == "11111111-2222-3333-4444-555555555555")
    }

    @Test func wikiLinkServiceLeavesPlainTextUntouched() {
        let storage = "no links here"
        let display = WikiLinkService.makeDisplayState(from: storage)
        #expect(display.display == storage)
        #expect(display.metadata.isEmpty)
    }

    // MARK: Tokenizer remains pure

    @Test func tokenizerParsesBoldEmphasisAndCode() {
        let tokens = MarkdownTokenizer.parseTokens(in: "**bold** *italic* `code`")
        let kinds = tokens.map(\.kind)
        #expect(kinds.contains(.bold))
        #expect(kinds.contains(.italic))
        #expect(kinds.contains(.inlineCode))
    }

    // MARK: Default services container is fully wired with no-ops

    @Test func defaultServicesAreAllNoOps() {
        let services = MarkdownEditorServices.default
        #expect(services.wikiLinks is NoOpWikiLinkResolver)
        #expect(services.images is NoOpEmbeddedImageProvider)
        #expect(services.syntaxHighlighter is PlainTextSyntaxHighlighter)
        #expect(services.latex is NoOpLatexRenderer)
    }

    @Test func defaultBusHasNoNotificationNames() {
        let bus = MarkdownEditorBus.default
        #expect(bus.applyBoldRequest == nil)
        #expect(bus.applyItalicRequest == nil)
        #expect(bus.applyHeadingRequest == nil)
        #expect(bus.selectionBoldDidChange == nil)
        #expect(bus.selectionItalicDidChange == nil)
        #expect(bus.findScrollToRange == nil)
        #expect(bus.findClearHighlights == nil)
    }

    // MARK: Styler runs end-to-end with defaults

    @Test func stylerProducesAttributesWithDefaultServices() {
        let text = "# Heading\n\n**bold** and `code`"
        let ranges = MarkdownStyler.styleAttributes(
            text: text,
            fontName: NSFont.systemFont(ofSize: 14).fontName,
            fontSize: 14,
            caretLocation: 0,
            activeTokenIndices: [],
            configuration: .default
        )
        #expect(!ranges.isEmpty)
    }
}
