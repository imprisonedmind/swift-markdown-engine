//
//  MarkdownStyler+Iframes.swift
//  MarkdownEngine
//
//  Live WebKit iframe embeds for raw HTML iframe blocks.
//

import AppKit
import Foundation

struct IframeEmbedDescriptor: Equatable {
    let url: URL
    let title: String?
    let requestedWidth: CGFloat?
    let requestedHeight: CGFloat?

    var displayTitle: String {
        if let title, !title.isEmpty { return title }
        return url.host ?? url.absoluteString
    }
}

extension MarkdownStyler {
    static func styleIframeEmbeds(_ ctx: StylingContext) -> [StyledRange] {
        var attrs: [StyledRange] = []
        let tokens = iframeTokens(in: ctx)
        if !tokens.isEmpty {
            iframeDebugLog("style pass found \(tokens.count) raw iframe token(s)")
        }
        for token in tokens {
            if MarkdownDetection.isInsideCodeBlock(range: token.range, codeTokens: ctx.codeTokens) {
                iframeDebugLog("style skipped iframe inside code range=\(token.range.location):\(token.range.length)")
                continue
            }
            let paragraphRange = ctx.nsText.paragraphRange(for: token.range)
            let sourceID = iframeSourceID(for: token, in: ctx.nsText)
            if ctx.revealedIframeEmbedSourceIDs.contains(sourceID)
                || ctx.revealedIframeEmbedParagraphLocations.contains(paragraphRange.location) {
                iframeInputLog("style iframe reveal source sourceID=\(sourceID) token=\(token.range.location):\(token.range.length) caret=\(ctx.caretLocation) paragraph=\(paragraphRange.location):\(paragraphRange.length)")
                appendSecondaryMarkers(for: token, to: &attrs, theme: ctx.configuration.theme)
                continue
            }
            guard let descriptor = iframeDescriptor(for: token, in: ctx.nsText) else {
                let source = ctx.nsText.substring(with: token.range)
                iframeDebugLog("style failed to parse iframe attributes range=\(token.range.location):\(token.range.length) source=\(source)")
                appendSecondaryMarkers(for: token, to: &attrs, theme: ctx.configuration.theme)
                continue
            }

            let imageEmbedConfig = ctx.configuration.imageEmbed
            let maxWidth: CGFloat = {
                if let tc = ctx.layoutBridge?.firstTextContainer {
                    let w = tc.containerSize.width - tc.lineFragmentPadding * 2
                    if w > 0 && w < imageEmbedConfig.unreasonableMaxWidth { return w }
                }
                return imageEmbedConfig.fallbackMaxWidth
            }()

            let requestedWidth = descriptor.requestedWidth ?? 820
            let requestedHeight = descriptor.requestedHeight ?? 520
            let displayWidth = min(max(requestedWidth, imageEmbedConfig.minimumWidth), maxWidth)
            let displayHeight = max(requestedHeight, 180)
            let totalHeight = IframeEmbedOverlay.headerHeight + displayHeight
            let para = NSMutableParagraphStyle()
            para.minimumLineHeight = totalHeight
            para.maximumLineHeight = totalHeight
            para.paragraphSpacingBefore = imageEmbedConfig.paragraphSpacing
            para.paragraphSpacing = imageEmbedConfig.paragraphSpacing
            para.lineBreakMode = .byClipping
            attrs.append((paragraphRange, [.paragraphStyle: para]))

            let sourceText = ctx.nsText.substring(with: token.range)
            attrs.append((token.range, [
                .foregroundColor: NSColor.clear,
                .font: ctx.latexMarkerFont,
                .kern: -HeadingHelpers.textWidth(sourceText, font: ctx.latexMarkerFont)
            ]))

            let anchorRange = NSRange(location: token.range.location, length: min(1, token.range.length))
            if anchorRange.length > 0 {
                let anchorChar = ctx.nsText.substring(with: anchorRange)
                attrs.append((anchorRange, [
                    .foregroundColor: NSColor.clear,
                    .font: ctx.latexMarkerFont,
                    .kern: displayWidth - HeadingHelpers.textWidth(anchorChar, font: ctx.latexMarkerFont),
                    .iframeEmbedID: sourceID,
                    .iframeEmbedURL: descriptor.url,
                    .iframeEmbedTitle: descriptor.displayTitle,
                    .iframeEmbedWidth: displayWidth,
                    .iframeEmbedHeight: displayHeight,
                    .iframeEmbedTotalHeight: totalHeight,
                    .iframeEmbedFullRange: NSValue(range: paragraphRange)
                ]))
            }
        }
        return attrs
    }

    private static func iframeTokens(in ctx: StylingContext) -> [MarkdownToken] {
        var result = ctx.tokens.filter { $0.kind == .iframeEmbed }
        var seen = Set<String>(result.map { "\($0.range.location):\($0.range.length)" })

        let source = String(ctx.nsText)
        let pattern = #"<iframe\b[\s\S]*?</iframe>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return result
        }
        let matches = regex.matches(in: source, range: NSRange(location: 0, length: ctx.nsText.length))
        if !matches.isEmpty {
            iframeDebugLog("raw scan matched \(matches.count) iframe tag(s)")
        }
        for match in matches {
            let range = match.range
            let key = "\(range.location):\(range.length)"
            guard seen.insert(key).inserted else { continue }
            let matched = ctx.nsText.substring(with: range)
            let lower = matched.lowercased() as NSString
            let open = lower.range(of: "<iframe")
            let close = lower.range(of: "</iframe>")
            let markers = [open, close]
                .filter { $0.location != NSNotFound && $0.length > 0 }
                .map { NSRange(location: range.location + $0.location, length: $0.length) }
            result.append(MarkdownToken(
                kind: .iframeEmbed,
                range: range,
                contentRange: range,
                markerRanges: markers
            ))
        }
        return deduplicatedIframeTokens(result, in: ctx.nsText)
    }

    private static func deduplicatedIframeTokens(_ tokens: [MarkdownToken], in text: NSString) -> [MarkdownToken] {
        var deduplicated: [MarkdownToken] = []
        for token in tokens.sorted(by: { lhs, rhs in
            if lhs.range.location == rhs.range.location {
                return lhs.range.length < rhs.range.length
            }
            return lhs.range.location < rhs.range.location
        }) {
            guard token.range.location != NSNotFound,
                  token.range.location >= 0,
                  NSMaxRange(token.range) <= text.length else {
                continue
            }

            let tokenParagraph = text.paragraphRange(for: token.range)
            if let existingIndex = deduplicated.firstIndex(where: { existing in
                NSIntersectionRange(existing.range, token.range).length > 0
                    || NSEqualRanges(text.paragraphRange(for: existing.range), tokenParagraph)
            }) {
                let existing = deduplicated[existingIndex]
                if token.range.length < existing.range.length {
                    deduplicated[existingIndex] = token
                }
                continue
            }

            deduplicated.append(token)
        }
        return deduplicated.sorted { $0.range.location < $1.range.location }
    }

    private static func iframeDescriptor(for token: MarkdownToken, in text: NSString) -> IframeEmbedDescriptor? {
        let source = text.substring(with: token.range)
        let attrs = parseHTMLAttributes(source)
        guard let rawURLText = (attrs["src"] ?? attrs["url"])?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawURLText.isEmpty else {
            return nil
        }
        let urlText = rawURLText.contains("://") ? rawURLText : "https://\(rawURLText)"
        guard let url = URL(string: urlText),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return nil
        }
        let requestedWidth = attrs["width"].flatMap { Double($0) }.map { CGFloat($0) }
        let requestedHeight = attrs["height"].flatMap { Double($0) }.map { CGFloat($0) }
        return IframeEmbedDescriptor(
            url: url,
            title: attrs["title"],
            requestedWidth: requestedWidth,
            requestedHeight: requestedHeight
        )
    }

    private static func parseHTMLAttributes(_ source: String) -> [String: String] {
        let pattern = #"([A-Za-z_:][-A-Za-z0-9_:.]*)\s*=\s*(?:"([^"]*)"|'([^']*)'|“([^”]*)”|‘([^’]*)’)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else { return [:] }
        let ns = source as NSString
        let matches = regex.matches(in: source, range: NSRange(location: 0, length: ns.length))
        var result: [String: String] = [:]
        for match in matches where match.numberOfRanges == 6 {
            let key = ns.substring(with: match.range(at: 1)).lowercased()
            let valueRange = (2..<match.numberOfRanges)
                .map { match.range(at: $0) }
                .first { $0.location != NSNotFound } ?? NSRange(location: NSNotFound, length: 0)
            guard valueRange.location != NSNotFound else { continue }
            let value = ns.substring(with: valueRange)
            result[key] = value
        }
        iframeDebugLog("parsed iframe attrs keys=[\(result.keys.sorted().joined(separator: ","))]")
        return result
    }

    static func iframeSourceID(for token: MarkdownToken, in text: NSString) -> Int {
        guard token.range.location != NSNotFound,
              token.range.location >= 0,
              NSMaxRange(token.range) <= text.length else {
            return "\(token.range.location):\(token.range.length)".hashValue
        }
        let source = text.substring(with: token.range)
        let occurrenceIndex = iframeOccurrenceIndex(forSource: source, before: token.range.location, in: text)
        return "\(source)|\(occurrenceIndex)".hashValue
    }

    private static func iframeOccurrenceIndex(forSource source: String, before location: Int, in text: NSString) -> Int {
        guard location > 0 else { return 0 }
        let prefix = text.substring(with: NSRange(location: 0, length: min(location, text.length))) as NSString
        var count = 0
        var searchLocation = 0
        while searchLocation < prefix.length {
            let remaining = NSRange(location: searchLocation, length: prefix.length - searchLocation)
            let found = prefix.range(of: source, options: [], range: remaining)
            guard found.location != NSNotFound else { break }
            count += 1
            searchLocation = NSMaxRange(found)
        }
        return count
    }

}

private func iframeDebugLog(_ message: String) {
    _ = message
}
