//
//  HighlighterSwiftBridge.swift
//  MarkdownEngineCodeBlocks
//
//  Ready-made SyntaxHighlighter conformance backed by HighlighterSwift.
//

import AppKit
import Foundation
import Highlighter
import MarkdownEngine

extension Notification.Name {
    /// Posted by ``HighlighterSwiftBridge`` after the macOS appearance flips and themes are re-applied; the engine subscribes via ``SyntaxHighlighter/appearanceDidChangeNotification`` to invalidate cached attributes.
    public static let markdownEngineHighlighterDidChangeAppearance =
        Notification.Name("MarkdownEngineHighlighterDidChangeAppearance")
}

/// Drop-in ``SyntaxHighlighter`` backed by HighlighterSwift.
///
/// Defaults match the Nodes app's look: opaque light/dark code-block
/// backgrounds and an `SF Mono → Menlo → system monospace` font chain.
/// Override the init params if you'd rather adopt HighlighterSwift's
/// CSS-theme-driven background/font directly.
///
/// When `autoSwitchAppearance` is `true`, the bridge observes
/// `AppleInterfaceThemeChangedNotification` and swaps `lightTheme` /
/// `darkTheme` accordingly, posting
/// ``Notification/Name/markdownEngineHighlighterDidChangeAppearance`` so
/// the engine can re-render code blocks.
public final class HighlighterSwiftBridge: SyntaxHighlighter, @unchecked Sendable {
    private let highlighter: Highlighter?
    private let lightTheme: String
    private let darkTheme: String
    private let autoSwitchAppearance: Bool
    private let lightBackground: NSColor
    private let darkBackground: NSColor
    private let preferredFontNames: [String]
    private var currentTheme: String = ""

    /// - Parameters:
    ///   - lightTheme: HighlighterSwift theme name applied in light mode.
    ///   - darkTheme: HighlighterSwift theme name applied in dark mode.
    ///   - autoSwitchAppearance: When `true`, observes the system appearance
    ///     and swaps themes automatically. Set to `false` to pin to `lightTheme`.
    ///   - lightBackground: Code-block background in light mode. Pass `nil`
    ///     to use HighlighterSwift's CSS-theme background instead.
    ///   - darkBackground: Code-block background in dark mode. Pass `nil`
    ///     to use HighlighterSwift's CSS-theme background instead.
    ///   - preferredFontNames: PostScript font names tried in order before
    ///     falling back to the system monospace font.
    public init(
        lightTheme: String = "atom-one-light",
        darkTheme: String = "atom-one-dark",
        autoSwitchAppearance: Bool = true,
        lightBackground: NSColor? = NSColor(calibratedWhite: 0.95, alpha: 1.0),
        darkBackground: NSColor? = NSColor(calibratedWhite: 0.13, alpha: 1.0),
        preferredFontNames: [String] = ["SF Mono", "Menlo"]
    ) {
        self.highlighter = Highlighter()
        self.lightTheme = lightTheme
        self.darkTheme = darkTheme
        self.autoSwitchAppearance = autoSwitchAppearance
        self.lightBackground = lightBackground ?? .clear
        self.darkBackground = darkBackground ?? .clear
        self.preferredFontNames = preferredFontNames
        applyAppearanceTheme()

        if autoSwitchAppearance {
            DistributedNotificationCenter.default.addObserver(
                forName: NSNotification.Name("AppleInterfaceThemeChangedNotification"),
                object: nil,
                queue: .main
            ) { [weak self] _ in
                guard let self else { return }
                self.applyAppearanceTheme()
                NotificationCenter.default.post(
                    name: .markdownEngineHighlighterDidChangeAppearance,
                    object: nil
                )
            }
        }
    }

    private func applyAppearanceTheme() {
        guard let highlighter else { return }
        let theme = isDarkAppearance() ? darkTheme : lightTheme
        if currentTheme != theme {
            currentTheme = theme
            highlighter.setTheme(theme)
        }
    }

    private func isDarkAppearance() -> Bool {
        guard autoSwitchAppearance else { return false }
        let appearance = NSApp.keyWindow?.effectiveAppearance ?? NSApp.effectiveAppearance
        return appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }

    // MARK: - SyntaxHighlighter

    public var appearanceDidChangeNotification: Notification.Name? {
        autoSwitchAppearance ? .markdownEngineHighlighterDidChangeAppearance : nil
    }

    public func codeFont(size: CGFloat) -> NSFont {
        for name in preferredFontNames {
            if let font = NSFont(name: name, size: size) {
                return font
            }
        }
        return .monospacedSystemFont(ofSize: size, weight: .regular)
    }

    public func backgroundColor() -> NSColor {
        isDarkAppearance() ? darkBackground : lightBackground
    }

    public func highlight(code: String, language: String?) -> NSAttributedString? {
        applyAppearanceTheme()
        guard let highlighter else { return nil }
        let normalized = language?.lowercased().trimmingCharacters(in: .whitespaces)
        if let lang = normalized, !lang.isEmpty {
            return highlighter.highlight(code, as: lang)
        }
        return highlighter.highlight(code, as: nil)
    }
}
