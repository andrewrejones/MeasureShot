import AppKit
import Foundation

enum MSExportHistoryAction: String, Codable, Sendable {
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

enum MSExportHistoryRange: String, CaseIterable, Identifiable, Sendable {
    case today
    case yesterday
    case lastWeek
    case lastMonth
    case customDay

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: return "Today"
        case .yesterday: return "Yesterday"
        case .lastWeek: return "Last Week"
        case .lastMonth: return "Last Month"
        case .customDay: return "Date"
        }
    }
}

enum MSExportOption: String, CaseIterable, Identifiable, Sendable {
    case standard
    case plain
    case allOverlays
    case legendOverlay
    case sidebarLegend
    case annotationsCSV

    var id: String { rawValue }

    var title: String {
        switch self {
        case .standard: return "Standard PNG"
        case .plain: return "Plain PNG"
        case .allOverlays: return "All Overlays PNG"
        case .legendOverlay: return "Legend Overlay PNG"
        case .sidebarLegend: return "Sidebar Legend PNG"
        case .annotationsCSV: return "Annotations CSV"
        }
    }

    var systemImage: String {
        switch self {
        case .standard: return "photo"
        case .plain: return "photo"
        case .allOverlays: return "square.3.layers.3d"
        case .legendOverlay: return "list.bullet.rectangle"
        case .sidebarLegend: return "sidebar.right"
        case .annotationsCSV: return "tablecells"
        }
    }
}

struct MSImageDocumentSnapshot {
    let title: String
    let originalImage: NSImage
    let rotationQuarterTurns: Int
    let freeRotationDegrees: Double
    let isFlippedHorizontally: Bool
    let isFlippedVertically: Bool
    let cropRect: CGRect?
    let brightness: Double
    let contrast: Double
    let exposure: Double
}

struct MSExportHistoryEditableSnapshot {
    let document: MSImageDocumentSnapshot
    let annotations: [MSAnnotation]
    let calibration: MSCalibration?
    let outputMeasurementUnit: MSMeasurementUnit
    let isAnnotationLayerVisible: Bool
    let isMeasurementLayerVisible: Bool
    let isGuideLayerVisible: Bool
    let computationResults: [MSComputationResult]
}

struct MSExportHistoryItem: Identifiable {
    let id: UUID
    let action: MSExportHistoryAction
    let image: NSImage
    let createdAt: Date
    let fileURL: URL?
    let imageFileURL: URL?
    let editableSnapshot: MSExportHistoryEditableSnapshot?

    init(
        id: UUID = UUID(),
        action: MSExportHistoryAction,
        image: NSImage,
        createdAt: Date,
        fileURL: URL? = nil,
        imageFileURL: URL? = nil,
        editableSnapshot: MSExportHistoryEditableSnapshot? = nil
    ) {
        self.id = id
        self.action = action
        self.image = image
        self.createdAt = createdAt
        self.fileURL = fileURL
        self.imageFileURL = imageFileURL
        self.editableSnapshot = editableSnapshot
    }

    var dimensionsText: String {
        "\(Int(image.size.width)) × \(Int(image.size.height)) px"
    }
}
