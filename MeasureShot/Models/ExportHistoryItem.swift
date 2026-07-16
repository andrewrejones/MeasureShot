import AppKit
import Foundation

enum MSExportHistoryAction: String, Sendable {
    case copied
    case saved
    case shared

    var title: String {
        switch self {
        case .copied: return "Copied"
        case .saved: return "Saved"
        case .shared: return "Shared"
        }
    }

    var systemImage: String {
        switch self {
        case .copied: return "doc.on.doc"
        case .saved: return "square.and.arrow.down"
        case .shared: return "square.and.arrow.up"
        }
    }
}

struct MSExportHistoryItem: Identifiable {
    let id = UUID()
    let action: MSExportHistoryAction
    let image: NSImage
    let createdAt: Date
    let fileURL: URL?

    var dimensionsText: String {
        "\(Int(image.size.width)) × \(Int(image.size.height)) px"
    }
}
