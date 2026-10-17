import AppKit
import CoreTransferable
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

/// Content explicitly placed on a canvas is saved with that group.
enum CanvasClipboardContent: Codable, Equatable {
    case text(String)
    case image(data: Data, type: String, preview: Data)

    var title: String {
        switch self {
        case .text(let text): String(text.prefix(80))
        case .image: L10n.tr("图片")
        }
    }

    var previewImage: CGImage? {
        guard case .image(_, _, let preview) = self,
              !preview.isEmpty else { return nil }
        return CanvasPreviewCache.shared.image(for: preview)
    }

    var byteCount: Int {
        switch self {
        case .text(let text): text.utf8.count
        case .image(let data, _, let preview): data.count + preview.count
        }
    }

    var isValid: Bool {
        switch self {
        case .text(let text): !text.isEmpty && text.utf8.count <= ClipboardHistory.maximumTextBytes
        case .image(let data, let type, let preview):
            data.count <= ClipboardHistory.maximumImageBytes && preview.count <= 1024 * 1024 &&
                ["public.png", "public.tiff"].contains(type) && Self.validImage(data, expectedType: type) && Self.validImage(preview)
        }
    }

    private static func validImage(_ data: Data, expectedType: String? = nil) -> Bool {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else { return false }
        return (expectedType == nil || (CGImageSourceGetType(source) as String?) == expectedType) &&
            width > 0 && height > 0 && width <= 32_000_000 / height
    }

    @MainActor @discardableResult func copy(to pasteboard: NSPasteboard = .general) -> Bool {
        pasteboard.clearContents()
        switch self {
        case .text(let text): return pasteboard.setString(text, forType: .string)
        case .image(let data, let type, _): return pasteboard.setData(data, forType: NSPasteboard.PasteboardType(type))
        }
    }
}

extension UTType {
    static let projectCanvasClipboard = UTType(exportedAs: "local.projectcanvas.clipboard-item")
}

/// Only transfers a history reference during dragging; persistence happens on drop.
struct ClipboardCanvasTransfer: Codable, Transferable {
    enum Kind: String, Codable { case text, image }
    let id: UUID
    let kind: Kind
    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .projectCanvasClipboard)
    }
}

struct CanvasClipboardTile: View {
    let content: CanvasClipboardContent
    @AppStorage(ClipboardAppearance.textSizeKey) private var textSize = 14.0

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(L10n.tr(content.isText ? "文字" : "图片"), systemImage: content.isText ? "text.alignleft" : "photo")
                .font(.caption2).foregroundStyle(.secondary)
            switch content {
            case .text(let text):
                Text(String(text.prefix(1000))).font(.system(size: ClipboardAppearance(textSize: textSize).textSize))
                    .lineLimit(3).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            case .image:
                if let image = content.previewImage {
                    Image(decorative: image, scale: 1).resizable().scaledToFit().frame(width: 192, height: 62)
                }
            }
        }.padding(9).frame(width: 210, height: 100)
            .accessibilityLabel(content.title)
    }
}

extension CanvasClipboardContent {
    var isText: Bool { if case .text = self { return true }; return false }
}

/// Thread-safe cache with bounded decoded-memory cost. Large imported previews are downsampled.
final class CanvasPreviewCache {
    static let shared = CanvasPreviewCache()
    private let cache = NSCache<NSData, CGImage>()

    init() {
        cache.totalCostLimit = 32 * 1024 * 1024
        cache.countLimit = 256
    }

    func image(for data: Data) -> CGImage? {
        let key = data as NSData
        if let image = cache.object(forKey: key) { return image }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 512,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else { return nil }
        cache.setObject(image, forKey: key, cost: image.bytesPerRow * image.height + data.count)
        return image
    }
}
