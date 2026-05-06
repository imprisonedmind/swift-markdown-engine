//
//  MarkdownStyler+Code.swift
//  MarkdownEngine
//
//  Fenced code blocks and inline code spans.
//

import AppKit
import Foundation

extension MarkdownStyler {

    // MARK: Fenced Code Blocks

    static func styleCodeBlocks(_ ctx: StylingContext) -> [StyledRange] {
        var attrs: [StyledRange] = []
        for (idx, token) in ctx.tokens.enumerated() where token.kind == .codeBlock {
            let codeContent = ctx.nsText.substring(with: token.contentRange)
            let isActive = ctx.activeTokenIndices.contains(idx)
            let language = MarkdownTokenizer.extractLanguage(from: token, in: ctx.text)
            attrs.append((token.range, [
                .font: ctx.codeFont,
                .backgroundColor: ctx.codeBackgroundColor,
                .paragraphStyle: ctx.codeParagraphStyle
            ]))

            if !codeContent.isEmpty,
               let highlighted = ctx.services.syntaxHighlighter.highlight(code: codeContent, language: language) {
                highlighted.enumerateAttributes(in: NSRange(location: 0, length: highlighted.length)) { highlightAttrs, range, _ in
                    guard let foregroundColor = highlightAttrs[.foregroundColor] else { return }
                    let absoluteRange = NSRange(location: token.contentRange.location + range.location, length: range.length)
                    attrs.append((absoluteRange, [.foregroundColor: foregroundColor]))
                }
            }
            let markerAttributes: [NSAttributedString.Key: Any] = isActive
                ? [.foregroundColor: ctx.configuration.theme.mutedText, .font: ctx.codeFont]
                : [.foregroundColor: NSColor.clear, .font: ctx.hiddenMarkerFont]
            token.markerRanges.forEach { attrs.append(($0, markerAttributes)) }
        }
        return attrs
    }

    // MARK: Inline Code

    static func styleInlineCode(_ ctx: StylingContext) -> [StyledRange] {
        var attrs: [StyledRange] = []
        for (idx, token) in ctx.tokens.enumerated() where token.kind == .inlineCode {
            attrs.append((token.contentRange, [
                .font: ctx.codeFont,
                .backgroundColor: ctx.codeBackgroundColor
            ]))
            // When the caret is inside the inline code, surface the backticks
            // at full size so the user can see what they're editing. When
            // it isn't, fall back to the dimmed near-zero-size form that
            // hides the syntax noise.
            let isActive = ctx.activeTokenIndices.contains(idx)
            let markerAttributes: [NSAttributedString.Key: Any]
            if isActive {
                markerAttributes = [
                    .foregroundColor: ctx.configuration.theme.mutedText,
                    .font: ctx.codeFont
                ]
            } else {
                markerAttributes = [
                    .foregroundColor: ctx.configuration.theme.mutedText
                        .withAlphaComponent(ctx.configuration.markers.inlineCodeMarkerAlpha),
                    .font: ctx.inlineMarkerFont
                ]
            }
            token.markerRanges.forEach { attrs.append(($0, markerAttributes)) }
        }
        return attrs
    }
}
