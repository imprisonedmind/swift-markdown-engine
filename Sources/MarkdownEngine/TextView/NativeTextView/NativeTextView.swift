//
//  NativeTextView.swift
//  MarkdownEngine
//
//  Created by Luca Chen on 18.02.26.
//
//  AppKit `NSTextView` subclass used by the markdown editor. Stored state
//  lives here; behavior is split across `NativeTextView+<Feature>.swift`
//  files in this folder (frame & overscroll, caret workarounds, click remap,
//  paste handling, drag-select boost, task checkbox, spelling policy).
//
//  Bottom-overscroll math lives in `BottomOverscrollPolicy.swift`.
//  Pasteboard image inspection lives in `PasteboardImageReader.swift`.
//

import AppKit
import UniformTypeIdentifiers

final class NativeTextView: NSTextView {
    // MARK: Frame & overscroll state
    var baseContentHeight: CGFloat = 0
    var activeBottomOverscroll: CGFloat = 0
    var isApplyingManagedFrameSize = false
    /// Set on switch/resize to force full-layout height measurement until the cascade settles.
    var pendingFullLayoutMeasure = false
    /// Coalesces wide-table overlay updates to once per runloop (resize fires many per frame).
    var pendingWideTableOverlayUpdate = false
    var suppressAutoRevealOnce: Bool = false

    // MARK: Configuration
    var configuration: MarkdownEditorConfiguration = .default {
        didSet {
            overscrollPercent = configuration.overscroll.percent
            maxOverscrollPoints = configuration.overscroll.maxPoints
            minOverscrollPoints = configuration.overscroll.minPoints
        }
    }
    var overscrollPercent: CGFloat = MarkdownEditorConfiguration.default.overscroll.percent
    var maxOverscrollPoints: CGFloat = MarkdownEditorConfiguration.default.overscroll.maxPoints
    var minOverscrollPoints: CGFloat = MarkdownEditorConfiguration.default.overscroll.minPoints

    // MARK: Editor wiring
    var onPasteImage: ((NSPasteboard) -> String?)?
    weak var layoutBridge: LayoutBridge?
    var baseFont: NSFont = NSFont.systemFont(ofSize: NSFont.systemFontSize)

    // MARK: Caret-workaround state
    var caretIndicatorObservation: NSKeyValueObservation?
    weak var observedCaretIndicator: NSView?
    var isApplyingCaretShift: Bool = false

    // MARK: Drag-select state
    var dragStartMouseScreenLoc: NSPoint?

    // MARK: Placeholder state
    /// Click-through ghost-text label shown while the document is empty;
    /// managed by `NativeTextView+Placeholder.swift`.
    weak var placeholderView: PlaceholderLabelView?

    // MARK: Cursor exclusion
    /// Embedder-supplied predicate that suppresses the I-beam cursor in edit mode.
    /// Called on every mouse-move with the event location in window coordinates.
    /// Return `true` to show the arrow cursor instead of the edit-mode I-beam.
    var isCursorExcluded: ((CGPoint) -> Bool)?

    // MARK: Wide-table overlay state
    /// Live NSScrollView per wide table; keyed by source-ID hash.
    var wideTableOverlays: [Int: WideTableOverlay] = [:]
    var iframeEmbedOverlays: [Int: IframeEmbedOverlay] = [:]
    var iframeEmbedHasInteractionFocus = false
    var iframeEmbedFocusMouseMonitor: Any?
    var iframeEmbedIsRedirectingMouseDown = false
    var revealedIframeEmbedSourceIDs = Set<Int>()
    var revealedIframeEmbedParagraphLocations = Set<Int>()
    /// Persisted horizontal scroll offset per wide table; survives restyles.
    var tableHorizontalScrollOffsets: [Int: CGFloat] = [:]

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        // Forward appearance changes to the embedder's highlighter via its registered notification.
        if let name = configuration.services.syntaxHighlighter.appearanceDidChangeNotification {
            NotificationCenter.default.post(name: name, object: self)
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        for overlay in iframeEmbedOverlays.values where overlay.superview === self {
            let overlayPoint = overlay.convert(point, from: self)
            if let hitView = overlay.hitTest(overlayPoint) {
                return hitView
            }
        }
        return super.hitTest(point)
    }

    func iframeEmbedHitTarget(for event: NSEvent) -> NSView? {
        for overlay in iframeEmbedOverlays.values {
            let overlayPoint = overlay.convert(event.locationInWindow, from: nil)
            guard overlay.bounds.contains(overlayPoint) else { continue }
            return overlay.hitTest(overlayPoint) ?? overlay
        }
        return nil
    }

    func setIframeEmbedInteractionFocus(_ hasFocus: Bool) {
        guard iframeEmbedHasInteractionFocus != hasFocus else {
            if hasFocus {
                installIframeEmbedFocusMouseMonitorIfNeeded()
            }
            return
        }
        iframeEmbedHasInteractionFocus = hasFocus
        if hasFocus {
            installIframeEmbedFocusMouseMonitorIfNeeded()
        } else {
            removeIframeEmbedFocusMouseMonitor()
        }
    }

    private func installIframeEmbedFocusMouseMonitorIfNeeded() {
        guard iframeEmbedFocusMouseMonitor == nil else { return }
        iframeEmbedFocusMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] event in
            guard let self,
                  self.iframeEmbedHasInteractionFocus,
                  event.window === self.window else {
                return event
            }
            if self.iframeEmbedHitTarget(for: event) == nil {
                let point = event.locationInWindow
                iframeInputLog("iframe focus monitor clearing outside click point=\(Int(point.x)),\(Int(point.y))")
                self.setIframeEmbedInteractionFocus(false)
                if self.isEditorWindowPoint(point) {
                    self.window?.makeFirstResponder(self)
                }
            }
            return event
        }
    }

    private func isEditorWindowPoint(_ point: NSPoint) -> Bool {
        if bounds.contains(convert(point, from: nil)) {
            return true
        }
        guard let superview else { return false }
        return superview.bounds.contains(superview.convert(point, from: nil))
    }

    private func removeIframeEmbedFocusMouseMonitor() {
        guard let monitor = iframeEmbedFocusMouseMonitor else { return }
        NSEvent.removeMonitor(monitor)
        iframeEmbedFocusMouseMonitor = nil
    }

    func clearRevealedIframeEmbedsOutsideCaret(in text: NSString, caretLocation: Int) -> [NSRange] {
        guard !revealedIframeEmbedParagraphLocations.isEmpty else { return [] }
        let safeCaret = min(max(caretLocation, 0), text.length)
        let caretParagraph = text.paragraphRange(for: NSRange(location: safeCaret, length: 0))
        var clearedParagraphs: [NSRange] = []

        for paragraphLocation in revealedIframeEmbedParagraphLocations where paragraphLocation != caretParagraph.location {
            let paragraph = text.paragraphRange(for: NSRange(location: min(paragraphLocation, max(0, text.length - 1)), length: 0))
            clearedParagraphs.append(paragraph)
        }

        guard !clearedParagraphs.isEmpty else { return [] }
        let remainingLocations = revealedIframeEmbedParagraphLocations.filter { $0 == caretParagraph.location }
        revealedIframeEmbedParagraphLocations = remainingLocations
        revealedIframeEmbedSourceIDs.removeAll()
        return clearedParagraphs
    }

    // setMarkedText skips textDidChange, so restyle the marked paragraph to apply markdown attrs.
    override func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        super.setMarkedText(string, selectedRange: selectedRange, replacementRange: replacementRange)
        guard hasMarkedText(),
              let coord = delegate as? NativeTextViewCoordinator else { return }
        let marked = markedRange()
        guard marked.location != NSNotFound, marked.length > 0 else { return }
        let nsText = self.string as NSString
        let paragraph = nsText.paragraphRange(for: marked)
        coord.restyleParagraphs([paragraph], in: self)
    }

    deinit {
        caretIndicatorObservation?.invalidate()
        removeIframeEmbedFocusMouseMonitor()
    }
}
