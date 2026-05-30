//
//  MarkdownAST.swift
//  MarkdownEngine
//
//  Phase 2.5 foundation: the semantic document AST. Combines the block-structure
//  pass (BlockParser) with the inline pass (InlineParser) into one tree of
//  `BlockNode`s, each inline-bearing block carrying its parsed inline children
//  in absolute document coordinates. The AST-native styler (next increments)
//  walks this tree instead of consuming flat tokens.
//

import Foundation

/// One item line of a list. `marker` is the `-`/`*`/`+` or `1.`/`1)` run;
/// `checkbox` is the `[ ]`/`[x]` bracket range for a GFM task item (else nil).
/// `indent` is the leading-whitespace column count (a nesting hint that the
/// styler indents by; Phase B turns it into a real container tree).
struct ListItem: Equatable {
    let range: NSRange          // the item's full line (incl. trailing newline)
    let marker: NSRange
    let ordered: Bool
    let number: Int?            // ordered start value, e.g. `5.` → 5
    let checkbox: NSRange?
    let checked: Bool
    let indent: Int
    let contentRange: NSRange   // text after the marker (and checkbox)
    let inlines: [InlineNode]
}

/// A top-level block in the document AST.
indirect enum BlockNode: Equatable {
    case paragraph(range: NSRange, inlines: [InlineNode])
    case heading(level: Int, range: NSRange, markers: [NSRange], inlines: [InlineNode])
    case blockquote(range: NSRange, inlines: [InlineNode])
    case list(range: NSRange, items: [ListItem])
    case codeBlock(range: NSRange)
    case blockLatex(range: NSRange)
    case table(range: NSRange)
    case thematicBreak(range: NSRange)
    case blank(range: NSRange)
}

enum DocumentAST {

    private static let hash: unichar = 0x23
    private static let space: unichar = 0x20
    private static let tab: unichar = 0x09

    /// Build the document AST: block structure with inline children parsed.
    static func parse(_ text: String) -> [BlockNode] {
        let ns = text as NSString
        return BlockParser.parse(text).map { node(for: $0, ns: ns) }
    }

    private static func node(for block: Block, ns: NSString) -> BlockNode {
        switch block.kind {
        case .paragraph:
            return .paragraph(range: block.range, inlines: InlineParser.parse(ns, range: block.range))
        case .heading:
            return heading(block.range, ns)
        case .blockquote:
            return .blockquote(range: block.range, inlines: InlineParser.parse(ns, range: block.range))
        case .list:
            return list(block.range, ns)
        case .fencedCode:
            return .codeBlock(range: block.range)
        case .blockLatex:
            return .blockLatex(range: block.range)
        case .table:
            return .table(range: block.range)
        case .thematicBreak:
            return .thematicBreak(range: block.range)
        case .blank:
            return .blank(range: block.range)
        }
    }

    /// ATX heading: optional indent, `#`×level, space(s), then inline content.
    private static func heading(_ range: NSRange, _ ns: NSString) -> BlockNode {
        let end = NSMaxRange(range)
        var i = range.location
        while i < end, ns.character(at: i) == space || ns.character(at: i) == tab { i += 1 }
        let hashStart = i
        var level = 0
        while i < end, ns.character(at: i) == hash { level += 1; i += 1 }
        let markers = [NSRange(location: hashStart, length: level)]

        var contentStart = i
        while contentStart < end, ns.character(at: contentStart) == space { contentStart += 1 }
        var contentEnd = end
        while contentEnd > contentStart, isLineBreak(ns.character(at: contentEnd - 1)) { contentEnd -= 1 }
        let contentRange = NSRange(location: contentStart, length: contentEnd - contentStart)

        return .heading(level: level, range: range, markers: markers,
                        inlines: InlineParser.parse(ns, range: contentRange))
    }

    /// Split a list block into one `ListItem` per physical line (Phase A is
    /// line-based; Phase B groups continuation lines + nested blocks per item).
    private static func list(_ range: NSRange, _ ns: NSString) -> BlockNode {
        var items: [ListItem] = []
        var cursor = range.location
        let end = NSMaxRange(range)
        while cursor < end {
            let line = ns.lineRange(for: NSRange(location: cursor, length: 0))
            items.append(listItem(line, ns))
            cursor = NSMaxRange(line)
        }
        return .list(range: range, items: items)
    }

    /// Parse one list-item line: indent, marker (`-`/`*`/`+` or `N.`/`N)`),
    /// optional `[ ]`/`[x]` task checkbox, then the inline content.
    private static func listItem(_ lineRange: NSRange, _ ns: NSString) -> ListItem {
        let end = NSMaxRange(lineRange)
        var i = lineRange.location
        var indent = 0
        while i < end, ns.character(at: i) == space || ns.character(at: i) == tab { i += 1; indent += 1 }
        let markerStart = i
        var ordered = false
        var number: Int?
        let c = i < end ? ns.character(at: i) : 0
        if c == 0x2D || c == 0x2A || c == 0x2B {        // - * +
            i += 1
        } else {                                        // N. / N)
            var value = 0
            var digits = 0
            while i < end, ns.character(at: i) >= 0x30, ns.character(at: i) <= 0x39, digits < 9 {
                value = value * 10 + Int(ns.character(at: i) - 0x30); i += 1; digits += 1
            }
            ordered = true
            number = value
            if i < end { i += 1 }                       // the `.` or `)`
        }
        let marker = NSRange(location: markerStart, length: i - markerStart)
        if i < end, ns.character(at: i) == space || ns.character(at: i) == tab { i += 1 }
        var checkbox: NSRange?
        var checked = false
        if i + 2 < end, ns.character(at: i) == 0x5B, ns.character(at: i + 2) == 0x5D {   // [ x ]
            let mid = ns.character(at: i + 1)
            if mid == space || mid == 0x78 || mid == 0x58 {     // space / x / X
                checkbox = NSRange(location: i, length: 3)
                checked = (mid == 0x78 || mid == 0x58)
                i += 3
                if i < end, ns.character(at: i) == space || ns.character(at: i) == tab { i += 1 }
            }
        }
        var contentEnd = end
        while contentEnd > i, isLineBreak(ns.character(at: contentEnd - 1)) { contentEnd -= 1 }
        let content = NSRange(location: i, length: max(0, contentEnd - i))
        return ListItem(range: lineRange, marker: marker, ordered: ordered, number: number,
                        checkbox: checkbox, checked: checked, indent: indent,
                        contentRange: content, inlines: InlineParser.parse(ns, range: content))
    }

    private static func isLineBreak(_ c: unichar) -> Bool { c == 0x0A || c == 0x0D }
}
