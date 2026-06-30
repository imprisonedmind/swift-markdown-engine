//
//  IframeEmbedOverlay.swift
//  MarkdownEngine
//
//  Live WebKit-backed iframe block overlay.
//

import AppKit
import WebKit

final class IframeEmbedOverlay: NSView {
    static let headerHeight: CGFloat = 34
    override var isFlipped: Bool { true }

    let sourceID: Int
    weak var ownerTextView: NativeTextView?
    var anchorTextLocation: Int

    private let headerView = NSView()
    private let titleField = NSTextField(labelWithString: "")
    private let openButton = ArrowCursorButton()
    private let revealButton = ArrowCursorButton()
    private let deleteButton = ArrowCursorButton()
    private let webView = IframeBodyWebView(frame: .zero)
    private var currentURL: URL?
    private var windowController: IframeEmbedWindowController?

    init(sourceID: Int, ownerTextView: NativeTextView, anchorLocation: Int) {
        self.sourceID = sourceID
        self.ownerTextView = ownerTextView
        self.anchorTextLocation = anchorLocation
        super.init(frame: .zero)

        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.masksToBounds = true
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.separatorColor.cgColor
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor

        headerView.wantsLayer = true
        headerView.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        addSubview(headerView)

        titleField.font = .systemFont(ofSize: 12, weight: .medium)
        titleField.textColor = .secondaryLabelColor
        titleField.lineBreakMode = .byTruncatingMiddle
        headerView.addSubview(titleField)

        configureHeaderButton(revealButton)
        revealButton.image = neutralSymbol("chevron.left.forwardslash.chevron.right", description: "Reveal iframe source")
        revealButton.imagePosition = .imageOnly
        revealButton.toolTip = "Reveal source"
        revealButton.target = self
        revealButton.action = #selector(revealSource)
        headerView.addSubview(revealButton)

        configureHeaderButton(deleteButton)
        deleteButton.image = neutralSymbol("trash", description: "Delete iframe")
        deleteButton.imagePosition = .imageOnly
        deleteButton.toolTip = "Delete iframe"
        deleteButton.target = self
        deleteButton.action = #selector(deleteIframe)
        headerView.addSubview(deleteButton)

        configureHeaderButton(openButton)
        openButton.image = neutralSymbol("arrow.up.forward.square", description: "Open iframe")
        openButton.imagePosition = .imageOnly
        openButton.toolTip = "Open in window"
        openButton.target = self
        openButton.action = #selector(openInWindow)
        headerView.addSubview(openButton)

        webView.allowsBackForwardNavigationGestures = false
        webView.setValue(false, forKey: "drawsBackground")
        webView.ownerTextView = ownerTextView
        webView.navigationDelegate = webView
        addSubview(webView)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func layout() {
        super.layout()
        let headerHeight = Self.headerHeight
        headerView.frame = NSRect(x: 0, y: 0, width: bounds.width, height: headerHeight)
        openButton.frame = NSRect(x: bounds.width - 38, y: 4, width: 30, height: 26)
        revealButton.frame = NSRect(x: bounds.width - 74, y: 4, width: 30, height: 26)
        deleteButton.frame = NSRect(x: bounds.width - 110, y: 4, width: 30, height: 26)
        titleField.frame = NSRect(x: 12, y: 7, width: max(0, bounds.width - 130), height: 20)
        webView.frame = NSRect(x: 0, y: headerHeight, width: bounds.width, height: max(0, bounds.height - headerHeight))
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(NSRect(x: 0, y: 0, width: bounds.width, height: Self.headerHeight), cursor: .arrow)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !isHidden, alphaValue > 0, bounds.contains(point) else {
            return nil
        }
        if point.y <= Self.headerHeight {
            for button in [deleteButton, revealButton, openButton] where button.frame.contains(point) {
                return button
            }
            return self
        }
        let webPoint = convert(point, to: webView)
        return webView.hitTest(webPoint) ?? webView
    }

    func update(url: URL, title: String, anchorLocation: Int) {
        titleField.stringValue = title
        anchorTextLocation = anchorLocation
        if currentURL != url {
            currentURL = url
            iframeInputLog("overlay load sourceID=\(sourceID) url=\(url.absoluteString)")
            webView.load(URLRequest(url: url))
        }
    }

    override func mouseDown(with event: NSEvent) {
        if handleForwardedMouseDown(with: event) {
            return
        }
    }

    func handleForwardedMouseDown(with event: NSEvent) -> Bool {
        let point = convert(event.locationInWindow, from: nil)
        guard point.y <= Self.headerHeight else {
            iframeInputLog("overlay body mouseDown forwarding to webView")
            ownerTextView?.setIframeEmbedInteractionFocus(true)
            window?.makeFirstResponder(webView)
            webView.mouseDown(with: event)
            return true
        }
        if performHeaderButtonClick(at: point) {
            return true
        }
        iframeInputLog("overlay header mouseDown ignored")
        return true
    }

    private func performHeaderButtonClick(at point: NSPoint) -> Bool {
        let buttons: [(ArrowCursorButton, String)] = [
            (deleteButton, "delete"),
            (revealButton, "reveal"),
            (openButton, "open")
        ]
        for (button, name) in buttons where button.frame.contains(point) {
            iframeInputLog("overlay header manual button click name=\(name)")
            button.performClick(nil)
            return true
        }
        return false
    }

    @objc private func revealSource() {
        iframeInputLog("overlay reveal button action")
        guard let textView = ownerTextView else {
            return
        }
        let paragraph = (textView.string as NSString).paragraphRange(for: NSRange(location: anchorTextLocation, length: 0))
        textView.revealedIframeEmbedSourceIDs.insert(sourceID)
        textView.revealedIframeEmbedParagraphLocations.insert(paragraph.location)
        textView.setIframeEmbedInteractionFocus(false)
        removeFromSuperview()
        textView.iframeEmbedOverlays.removeValue(forKey: sourceID)
        textView.window?.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: anchorTextLocation, length: 0))
        if let coordinator = textView.delegate as? NativeTextViewCoordinator {
            coordinator.restyleParagraphs([paragraph], in: textView)
        }
    }

    @objc private func deleteIframe() {
        iframeInputLog("overlay delete button action")
        guard let textView = ownerTextView,
              let storage = textView.textStorage else { return }
        let location = max(0, min(anchorTextLocation, max(0, storage.length - 1)))
        let rawRange = (storage.attribute(.iframeEmbedFullRange, at: location, effectiveRange: nil) as? NSValue)?.rangeValue
            ?? (textView.string as NSString).paragraphRange(for: NSRange(location: location, length: 0))
        guard rawRange.location != NSNotFound,
              NSMaxRange(rawRange) <= storage.length,
              textView.shouldChangeText(in: rawRange, replacementString: "") else { return }
        storage.replaceCharacters(in: rawRange, with: "")
        textView.didChangeText()
    }

    @objc private func openInWindow() {
        iframeInputLog("overlay open button action")
        guard let currentURL else { return }
        if let windowController {
            windowController.showWindow(nil)
            windowController.window?.makeKeyAndOrderFront(nil)
            return
        }
        let controller = IframeEmbedWindowController(url: currentURL, title: titleField.stringValue)
        windowController = controller
        controller.showWindow(nil)
    }

    private func neutralSymbol(_ name: String, description: String) -> NSImage? {
        guard let symbol = NSImage(systemSymbolName: name, accessibilityDescription: description)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 15, weight: .regular)) else {
            return nil
        }
        symbol.isTemplate = true
        return symbol
    }

    private func configureHeaderButton(_ button: NSButton) {
        button.bezelStyle = .accessoryBarAction
        button.isBordered = true
        button.controlSize = .small
        button.setButtonType(.momentaryPushIn)
        button.imageScaling = .scaleProportionallyDown
        button.contentTintColor = .labelColor
        button.focusRingType = .none
    }
}

private final class ArrowCursorButton: NSButton {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        iframeInputLog("overlay button mouseDown tooltip=\(toolTip ?? "nil")")
        super.mouseDown(with: event)
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .arrow)
    }
}

private final class IframeBodyWebView: WKWebView, WKNavigationDelegate {
    override var acceptsFirstResponder: Bool { true }
    weak var ownerTextView: NativeTextView?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        iframeInputLog("webView didMoveToWindow hasWindow=\(window != nil)")
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        iframeInputLog("webView didStart url=\(webView.url?.absoluteString ?? "nil")")
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        iframeInputLog("webView didCommit url=\(webView.url?.absoluteString ?? "nil")")
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        iframeInputLog("webView didFinish url=\(webView.url?.absoluteString ?? "nil") title=\(webView.title ?? "nil")")
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        iframeInputLog("webView didFail url=\(webView.url?.absoluteString ?? "nil") error=\(error.localizedDescription)")
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        iframeInputLog("webView didFailProvisional url=\(webView.url?.absoluteString ?? "nil") error=\(error.localizedDescription)")
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        iframeInputLog("webView process terminated url=\(webView.url?.absoluteString ?? "nil")")
    }

    override func mouseDown(with event: NSEvent) {
        if redirectMouseDownToOwnerIfOutsideBounds(event) {
            return
        }
        iframeInputLog("webView mouseDown makeFirstResponder")
        ownerTextView?.setIframeEmbedInteractionFocus(true)
        window?.makeFirstResponder(self)
        super.mouseDown(with: event)
    }

    override func rightMouseDown(with event: NSEvent) {
        iframeInputLog("webView rightMouseDown makeFirstResponder")
        ownerTextView?.setIframeEmbedInteractionFocus(true)
        window?.makeFirstResponder(self)
        super.rightMouseDown(with: event)
    }

    override func otherMouseDown(with event: NSEvent) {
        iframeInputLog("webView otherMouseDown makeFirstResponder")
        ownerTextView?.setIframeEmbedInteractionFocus(true)
        window?.makeFirstResponder(self)
        super.otherMouseDown(with: event)
    }

    private func redirectMouseDownToOwnerIfOutsideBounds(_ event: NSEvent) -> Bool {
        let point = convert(event.locationInWindow, from: nil)
        guard !bounds.contains(point), let ownerTextView else {
            return false
        }
        iframeInputLog("webView mouseDown outside bounds redirecting to textView point=\(Int(point.x)),\(Int(point.y)) bounds=\(Int(bounds.width))x\(Int(bounds.height))")
        ownerTextView.setIframeEmbedInteractionFocus(false)
        ownerTextView.window?.makeFirstResponder(ownerTextView)
        ownerTextView.iframeEmbedIsRedirectingMouseDown = true
        defer { ownerTextView.iframeEmbedIsRedirectingMouseDown = false }
        ownerTextView.mouseDown(with: event)
        return true
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        iframeInputLog("webView performKeyEquivalent key=\(event.charactersIgnoringModifiers ?? "nil") chars=\(event.characters ?? "nil") modifiers=\(event.modifierFlags.rawValue)")
        let handled = super.performKeyEquivalent(with: event)
        iframeInputLog("webView performKeyEquivalent handled=\(handled)")
        return handled
    }

}

private final class IframeEmbedWindow: NSWindow {
    override func makeFirstResponder(_ responder: NSResponder?) -> Bool {
        let result = super.makeFirstResponder(responder)
        iframeInputLog("iframeWindow makeFirstResponder responder=\(String(describing: responder)) result=\(result)")
        return result
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if isCommandW(event) {
            close()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func keyDown(with event: NSEvent) {
        if isCommandW(event) {
            close()
            return
        }
        super.keyDown(with: event)
    }

    private func isCommandW(_ event: NSEvent) -> Bool {
        event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.command)
            && event.charactersIgnoringModifiers?.lowercased() == "w"
    }
}

func iframeInputLog(_ message: String) {
    NSLog("[MarkdownEngine][iframe-input] %@", message)
    let line = "[MarkdownEngine][iframe-input] \(message)\n"
    guard let data = line.data(using: .utf8) else { return }
    let url = URL(fileURLWithPath: "/tmp/notepond-dev.log")
    if FileManager.default.fileExists(atPath: url.path) {
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        }
    } else {
        try? data.write(to: url, options: .atomic)
    }
}

private final class IframeEmbedWindowController: NSWindowController, NSWindowDelegate {
    private let url: URL
    private let webView = WKWebView(frame: .zero)

    init(url: URL, title: String) {
        self.url = url
        let frame = Self.defaultWindowFrame(scale: 0.8)
        let window = IframeEmbedWindow(
            contentRect: frame,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = title.isEmpty ? (url.host ?? "Iframe") : title
        window.minSize = NSSize(width: 780, height: 520)
        super.init(window: window)
        window.delegate = self
        webView.autoresizingMask = [.width, .height]
        webView.frame = window.contentView?.bounds ?? .zero
        window.contentView = webView
        webView.load(URLRequest(url: url))
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    private static func defaultWindowFrame(scale: CGFloat) -> NSRect {
        guard let visibleFrame = NSScreen.main?.visibleFrame else {
            return NSRect(x: 0, y: 0, width: 1152, height: 720)
        }

        let rootWidth = min(visibleFrame.width, max(1120, visibleFrame.width * 0.92))
        let rootHeight = min(visibleFrame.height, max(720, visibleFrame.height * 0.9))
        let width = min(visibleFrame.width, rootWidth * scale)
        let height = min(visibleFrame.height, rootHeight * scale)
        let x = visibleFrame.midX - width / 2
        let y = visibleFrame.midY - height / 2
        return NSRect(x: x, y: y, width: width, height: height)
    }
}
