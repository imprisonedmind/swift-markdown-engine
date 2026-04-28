//
//  NativeTextViewSelectionTypes.swift
//  Nodes
//
//  Public selection / replacement value types exposed by NativeTextViewWrapper.
//

import Foundation

public struct NodeLinkSelection: Sendable {
    public let displayRange: NSRange
    public let storageRange: NSRange?
    public let placeholder: String

    public init(displayRange: NSRange, storageRange: NSRange?, placeholder: String) {
        self.displayRange = displayRange
        self.storageRange = storageRange
        self.placeholder = placeholder
    }
}

public enum InlineSelectionKind: Sendable {
    case nodeLink
    case imageEmbed
}

public struct InlineSelectionState: Sendable {
    public let kind: InlineSelectionKind
    public let selection: NodeLinkSelection

    public init(kind: InlineSelectionKind, selection: NodeLinkSelection) {
        self.kind = kind
        self.selection = selection
    }
}

public struct InlineReplacementRequest: Sendable {
    public let id: UUID
    public let nodeId: String
    public let selection: NodeLinkSelection
    public let storageFragment: String
    public let isImageEmbedMode: Bool

    public init(
        id: UUID = UUID(),
        nodeId: String,
        selection: NodeLinkSelection,
        storageFragment: String,
        isImageEmbedMode: Bool
    ) {
        self.id = id
        self.nodeId = nodeId
        self.selection = selection
        self.storageFragment = storageFragment
        self.isImageEmbedMode = isImageEmbedMode
    }
}
