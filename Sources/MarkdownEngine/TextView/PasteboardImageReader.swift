//
//  PasteboardImageReader.swift
//  Nodes
//
//  Pasteboard inspection helpers used to detect and extract images
//  from paste / drop events into the editor.
//

import AppKit
import UniformTypeIdentifiers

public enum PasteboardImageReader {
    public static func canPasteImage(from pasteboard: NSPasteboard) -> Bool {
        imageFileURL(from: pasteboard) != nil || imageData(from: pasteboard) != nil
    }

    public static func imageFileURL(from pasteboard: NSPasteboard) -> URL? {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true
        ]
        guard let objects = pasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL] else {
            return nil
        }

        return objects.first(where: { url in
            guard let type = UTType(filenameExtension: url.pathExtension) else { return false }
            return type.conforms(to: .image)
        })
    }

    public static func imageData(from pasteboard: NSPasteboard) -> Data? {
        if let pngData = pasteboard.data(forType: .png), !pngData.isEmpty {
            return pngData
        }

        if let tiffData = pasteboard.data(forType: .tiff),
           let bitmapRep = NSBitmapImageRep(data: tiffData),
           let pngData = bitmapRep.representation(using: .png, properties: [:]) {
            return pngData
        }

        if let images = pasteboard.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage],
           let image = images.first,
           let pngData = pngData(from: image) {
            return pngData
        }

        for type in pasteboard.types ?? [] where type != .png && type != .tiff {
            guard let data = pasteboard.data(forType: type),
                  !data.isEmpty,
                  let image = NSImage(data: data),
                  let pngData = pngData(from: image) else {
                continue
            }
            return pngData
        }

        guard let image = NSImage(pasteboard: pasteboard) else {
            return nil
        }
        return pngData(from: image)
    }

    private static func pngData(from image: NSImage) -> Data? {
        if let tiffData = image.tiffRepresentation,
           let bitmapRep = NSBitmapImageRep(data: tiffData),
           let pngData = bitmapRep.representation(using: .png, properties: [:]) {
            return pngData
        }

        var proposedRect = NSRect(origin: .zero, size: image.size)
        guard let cgImage = image.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil) else {
            return nil
        }
        let bitmapRep = NSBitmapImageRep(cgImage: cgImage)
        return bitmapRep.representation(using: .png, properties: [:])
    }
}
