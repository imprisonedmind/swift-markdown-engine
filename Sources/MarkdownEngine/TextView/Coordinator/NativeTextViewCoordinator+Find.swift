//
//  NativeTextViewCoordinator+Find.swift
//  MarkdownEngine
//
//  Find-in-document highlighting. The host app posts the bus notifications
//  registered in `MarkdownEditorBus.findScrollToRange` /
//  `findClearHighlights` to drive the highlight overlay; this extension
//  renders the highlights into the underlying NSTextStorage and scrolls the
//  current match into view.
//

import AppKit

extension NativeTextViewCoordinator {
    @objc func handleFindScrollToRange(_ notification: Notification) {
        guard let tv = textView,
              let info = notification.userInfo,
              let range = info["range"] as? NSRange,
              let currentIndex = info["currentIndex"] as? Int,
              let allRanges = info["allRanges"] as? [NSRange] else { return }

        let storage = tv.textStorage
        let fullRange = NSRange(location: 0, length: (tv.string as NSString).length)

        // Clear previous highlights
        storage?.removeAttribute(.backgroundColor, range: fullRange)

        // Highlight all matches; the focused match gets a stronger color.
        let theme = configuration.theme
        let matchAlpha = configuration.markers.findMatchHighlightAlpha
        let highlightColor = theme.findMatchHighlight.withAlphaComponent(matchAlpha)
        let currentHighlightColor = theme.findCurrentMatchHighlight

        for (i, matchRange) in allRanges.enumerated() {
            guard matchRange.location + matchRange.length <= fullRange.length else { continue }
            let color = (i == currentIndex) ? currentHighlightColor : highlightColor
            storage?.addAttribute(.backgroundColor, value: color, range: matchRange)
        }

        // Scroll to current match
        if range.location + range.length <= fullRange.length {
            tv.scrollRangeToVisible(range)
        }
    }

    @objc func handleFindClearHighlights(_ notification: Notification) {
        guard let tv = textView else { return }
        let fullRange = NSRange(location: 0, length: (tv.string as NSString).length)
        tv.textStorage?.removeAttribute(.backgroundColor, range: fullRange)
    }
}
