import AppKit
import SwiftUI
import Observation
import UniformTypeIdentifiers

enum MSCanvasLayer: String, CaseIterable, Identifiable, Sendable {
    case annotations
    case measurements
    case guides

    var id: String { rawValue }

    var title: String {
        switch self {
        case .annotations: return "Annotations"
        case .measurements: return "Measurements"
        case .guides: return "Guides"
        }
    }

    var systemImage: String {
        switch self {
        case .annotations: return "pencil.and.outline"
        case .measurements: return "ruler"
        case .guides: return "line.3.horizontal"
        }
    }
}

private struct ImageDocumentEditState {
    var rotationQuarterTurns: Int
    var freeRotationDegrees: Double
    var isFlippedHorizontally: Bool
    var isFlippedVertically: Bool
    var cropRect: CGRect?
    var brightness: Double
    var contrast: Double
    var exposure: Double

    init(document: ImageDocument) {
        rotationQuarterTurns = document.rotationQuarterTurns
        freeRotationDegrees = document.freeRotationDegrees
        isFlippedHorizontally = document.isFlippedHorizontally
        isFlippedVertically = document.isFlippedVertically
        cropRect = document.cropRect
        brightness = document.brightness
        contrast = document.contrast
        exposure = document.exposure
    }

    func apply(to document: ImageDocument) {
        document.rotationQuarterTurns = rotationQuarterTurns
        document.freeRotationDegrees = freeRotationDegrees
        document.isFlippedHorizontally = isFlippedHorizontally
        document.isFlippedVertically = isFlippedVertically
        document.cropRect = cropRect
        document.brightness = brightness
        document.contrast = contrast
        document.exposure = exposure
    }
}

private struct AppUndoState {
    var annotations: [MSAnnotation]
    var imageDocumentState: ImageDocumentEditState?
}

struct MSScreenshotTabSummary: Identifiable, Hashable {
    let id: UUID
    var title: String
    var isSelected: Bool
}

struct MSAverageColor: Hashable {
    var hex: String
    var rgb: String
}

enum MSSideBySideSlot {
    case left
    case right
}

@Observable
private final class ScreenshotWorkspace: Identifiable {
    let id: UUID
    var document: ImageDocument
    var annotations: [MSAnnotation] = []
    var selectedAnnotationID: UUID?
    var inProgressAnnotation: MSAnnotation?
    var calibration: MSCalibration?
    var cropSelectionRect: CGRect?
    var zoomScale: CGFloat = 1
    var isFitToWindow = true
    var undoStack: [AppUndoState] = []
    var redoStack: [AppUndoState] = []
    var pendingImageAdjustmentUndoState: AppUndoState?
    var lastMoveUndoState: AppUndoState?
    var lastEndpointEditUndoState: AppUndoState?
    var computationResults: [MSComputationResult] = []

    init(document: ImageDocument) {
        self.id = document.id
        self.document = document
    }
}

@MainActor
@Observable
final class AppState {
    private static let annotationColorDefaultsKey = "annotationColor"
    private static let annotationLineWidthDefaultsKey = "annotationLineWidth"
    private static let exportHistoryManifestFilename = "manifest.json"
    private static let exportHistoryTabDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    private struct ExportHistoryRecord: Codable {
        var id: UUID
        var action: MSExportHistoryAction
        var createdAt: Date
        var fileURL: URL?
        var imageFilename: String
        var editableSnapshot: ExportHistoryEditableRecord?
    }

    private struct ExportHistoryEditableRecord: Codable {
        var documentTitle: String
        var sourceImageFilename: String
        var rotationQuarterTurns: Int
        var freeRotationDegrees: Double
        var isFlippedHorizontally: Bool
        var isFlippedVertically: Bool
        var cropRect: CGRect?
        var brightness: Double
        var contrast: Double
        var exposure: Double
        var annotations: [MSAnnotation]
        var calibration: MSCalibration?
        var outputMeasurementUnit: MSMeasurementUnit
        var isAnnotationLayerVisible: Bool
        var isMeasurementLayerVisible: Bool
        var isGuideLayerVisible: Bool
        var computationResults: [MSComputationResult]?
    }

    private var screenshotWorkspaces: [ScreenshotWorkspace] = []
    var selectedScreenshotID: UUID?
    var sideBySideLeftScreenshotID: UUID?
    var sideBySideRightScreenshotID: UUID?

    var screenshotTabs: [MSScreenshotTabSummary] {
        screenshotWorkspaces.map {
            MSScreenshotTabSummary(
                id: $0.id,
                title: $0.document.title,
                isSelected: $0.id == selectedScreenshotID
            )
        }
    }

    var imageDocument: ImageDocument? {
        get { selectedWorkspace?.document }
        set {
            guard let newValue else {
                clearImage()
                return
            }

            if let index = selectedWorkspaceIndex {
                screenshotWorkspaces[index].document = newValue
                selectedScreenshotID = newValue.id
            } else {
                addScreenshotWorkspace(for: newValue)
            }
        }
    }

    var currentImage: NSImage? {
        guard let imageDocument else { return nil }
        return ImageRenderer.render(document: imageDocument)
    }

    var selectedTool: MSToolType = .select
    var statusMessage = "Ready"
    var isCapturing = false
    var zoomScale: CGFloat {
        get { selectedWorkspace?.zoomScale ?? 1 }
        set { selectedWorkspace?.zoomScale = newValue }
    }
    var isFitToWindow: Bool {
        get { selectedWorkspace?.isFitToWindow ?? true }
        set { selectedWorkspace?.isFitToWindow = newValue }
    }

    var isAnnotationLayerVisible = true
    var isMeasurementLayerVisible = true
    var isGuideLayerVisible = true

    var activeLayer: MSCanvasLayer = .annotations
    var exportHistory: [MSExportHistoryItem] = []

    // MARK: - Canvas State

    var annotations: [MSAnnotation] {
        get { selectedWorkspace?.annotations ?? [] }
        set { selectedWorkspace?.annotations = newValue }
    }
    var selectedAnnotationID: UUID? {
        get { selectedWorkspace?.selectedAnnotationID }
        set { selectedWorkspace?.selectedAnnotationID = newValue }
    }
    var inProgressAnnotation: MSAnnotation? {
        get { selectedWorkspace?.inProgressAnnotation }
        set { selectedWorkspace?.inProgressAnnotation = newValue }
    }
    var annotationColor: Color = .black {
        didSet {
            saveAnnotationColor()
        }
    }
    var annotationLineWidth: CGFloat = 2 {
        didSet {
            UserDefaults.standard.set(
                Double(annotationLineWidth),
                forKey: Self.annotationLineWidthDefaultsKey
            )
        }
    }
    var calibration: MSCalibration? {
        get { selectedWorkspace?.calibration }
        set { selectedWorkspace?.calibration = newValue }
    }
    var outputMeasurementUnit: MSMeasurementUnit = .centimetres
    var calibrationKnownLength: Double = 10
    var calibrationUnit: MSMeasurementUnit = .centimetres

    var sampledColor: Color = .clear
    var sampledHex: String = "#000000"
    var sampledRGB: String = "0, 0, 0"
    var latestComparisonResult: String?
    var computationResults: [MSComputationResult] {
        get { selectedWorkspace?.computationResults ?? [] }
        set { selectedWorkspace?.computationResults = newValue }
    }

    var defaultText = "Double-click to edit"
    var defaultFontSize: CGFloat = 18
    var defaultBlurRadius: Double = 12
    var defaultBlurBrushSize: Double = 44
    var showBlurMask = false
    var defaultPenLineWidth: CGFloat = 7
    var cropSelectionRect: CGRect? {
        get { selectedWorkspace?.cropSelectionRect }
        set { selectedWorkspace?.cropSelectionRect = newValue }
    }

    private var angleCreationStage = 0
    private var angleFirstPoint: CGPoint?
    private var angleVertex: CGPoint?
    private var anglePerpendicularEnd: CGPoint?

    private var selectedWorkspaceIndex: Int? {
        guard let selectedScreenshotID else { return nil }
        return screenshotWorkspaces.firstIndex { $0.id == selectedScreenshotID }
    }

    private var selectedWorkspace: ScreenshotWorkspace? {
        guard let selectedWorkspaceIndex else { return nil }
        return screenshotWorkspaces[selectedWorkspaceIndex]
    }

    init() {
        if let savedColor = Self.loadAnnotationColor() {
            annotationColor = savedColor.swiftUIColor
        }

        let savedLineWidth = UserDefaults.standard.double(forKey: Self.annotationLineWidthDefaultsKey)
        if savedLineWidth > 0 {
            annotationLineWidth = CGFloat(savedLineWidth)
        }

        loadExportHistory()
    }

    func startCapture() {
        captureScreenshot { [weak self] image in
            self?.addScreenshot(image: image)
            self?.statusMessage = "Capture complete"
        }
    }

    func prepareSideBySideComparison() {
        if sideBySideLeftScreenshotID == nil || !hasScreenshot(id: sideBySideLeftScreenshotID) {
            sideBySideLeftScreenshotID = selectedScreenshotID
        }

        if sideBySideRightScreenshotID == nil || !hasScreenshot(id: sideBySideRightScreenshotID) {
            sideBySideRightScreenshotID = screenshotWorkspaces.first {
                $0.id != sideBySideLeftScreenshotID
            }?.id
        }

        selectedTool = .sideBySide
        statusMessage = "Side-by-side comparison"
    }

    func selectSideBySideSlot(_ slot: MSSideBySideSlot) {
        switch slot {
        case .left:
            if let sideBySideLeftScreenshotID {
                selectScreenshotTab(id: sideBySideLeftScreenshotID)
            }
        case .right:
            if let sideBySideRightScreenshotID {
                selectScreenshotTab(id: sideBySideRightScreenshotID)
            }
        }
        selectedTool = .sideBySide
    }

    func captureSideBySideImage(for slot: MSSideBySideSlot) {
        captureScreenshot { [weak self] image in
            guard let self else { return }

            let id = self.addScreenshot(image: image, title: self.defaultSideBySideTitle(for: slot))
            self.setSideBySideScreenshot(id: id, for: slot)
            self.selectedTool = .sideBySide
            self.statusMessage = "Added comparison image"
        }
    }

    func insertSideBySideImage(for slot: MSSideBySideSlot) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true

        let completion: (NSApplication.ModalResponse) -> Void = { [weak self, panel] response in
            guard response == .OK,
                  let url = panel.url,
                  let image = NSImage(contentsOf: url) else {
                return
            }

            Task { @MainActor in
                guard let self else { return }

                let id = self.addScreenshot(
                    image: image,
                    title: url.deletingPathExtension().lastPathComponent
                )
                self.setSideBySideScreenshot(id: id, for: slot)
                self.selectedTool = .sideBySide
                self.statusMessage = "Inserted comparison image"
            }
        }

        if let window = NSApplication.shared.keyWindow ?? NSApplication.shared.mainWindow {
            panel.beginSheetModal(for: window, completionHandler: completion)
        } else {
            panel.begin(completionHandler: completion)
        }
    }

    func sideBySideTitle(for slot: MSSideBySideSlot) -> String {
        guard let workspace = sideBySideWorkspace(for: slot) else {
            return slot == .left ? "Left Image" : "Right Image"
        }

        return workspace.document.title
    }

    func sideBySideRenderedImage(for slot: MSSideBySideSlot) -> NSImage? {
        guard let workspace = sideBySideWorkspace(for: slot) else { return nil }
        return renderedImage(for: workspace, showAnnotations: true, showMeasurements: true)
    }

    func sideBySideDetailText(for slot: MSSideBySideSlot) -> String {
        guard let workspace = sideBySideWorkspace(for: slot) else {
            return "No image loaded"
        }

        let measuredRegions = workspace.annotations.filter { $0.isMeasuredRegion }.count
        let measurements = workspace.annotations.filter {
            $0.type == .measurement || $0.type == .calibration || $0.type == .angle || $0.type == .parallelAngle
        }.count

        return "\(measuredRegions) regions, \(measurements) measurements"
    }

    func exportSideBySideComparison() {
        guard let image = renderSideBySideComparisonImage() else {
            statusMessage = "Add two images to export a comparison"
            return
        }

        saveExportImage(
            image,
            filename: "MeasureShot Side by Side.png",
            includeEditableSnapshot: false
        )
    }

    private func captureScreenshot(onSuccess: @escaping (NSImage) -> Void) {
        guard !isCapturing else { return }

        isCapturing = true
        statusMessage = "Select a region to capture"

        CaptureManager.shared.startRegionCapture { [weak self] result in
            guard let self else { return }

            self.isCapturing = false

            switch result {
            case .success(let image):
                onSuccess(image)
                self.showEditor()

            case .failure(let error):
                if case CaptureManager.CaptureError.cancelled = error {
                    self.statusMessage = "Capture cancelled"
                } else {
                    self.statusMessage = error.localizedDescription
                }
                self.showEditor()
            }
        }
    }

    func clearImage() {
        guard let index = selectedWorkspaceIndex else { return }

        screenshotWorkspaces.remove(at: index)
        self.selectedScreenshotID = screenshotWorkspaces.indices.contains(index)
            ? screenshotWorkspaces[index].id
            : screenshotWorkspaces.last?.id
        resetTransientImageEditState()
        sampledColor = .clear
        sampledHex = "#000000"
        sampledRGB = "0, 0, 0"
        statusMessage = "Closed screenshot"
    }

    func addScreenshot(image: NSImage) {
        let nextNumber = screenshotWorkspaces.count + 1
        _ = addScreenshot(image: image, title: "Screenshot \(nextNumber)")
    }

    @discardableResult
    private func addScreenshot(image: NSImage, title: String) -> UUID {
        let document = ImageDocument(image: image, title: title)
        addScreenshotWorkspace(for: document)
        resetCanvasStateForNewDocument()
        return document.id
    }

    func insertImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true

        let completion: (NSApplication.ModalResponse) -> Void = { [weak self, panel] response in
            guard response == .OK,
                  let url = panel.url,
                  let image = NSImage(contentsOf: url) else {
                return
            }

            Task { @MainActor in
                self?.insertImage(image, title: url.deletingPathExtension().lastPathComponent)
            }
        }

        if let window = NSApplication.shared.keyWindow ?? NSApplication.shared.mainWindow {
            panel.beginSheetModal(for: window, completionHandler: completion)
        } else {
            panel.begin(completionHandler: completion)
        }
    }

    private func insertImage(_ image: NSImage, title: String) {
        let document = ImageDocument(image: image, title: title)
        addScreenshotWorkspace(for: document)
        resetCanvasStateForNewDocument()
        statusMessage = "Inserted image"
        showEditor()
    }

    func createBlankTab() {
        let nextNumber = screenshotWorkspaces.count + 1
        let size = CGSize(width: 1600, height: 1000)
        let image = NSImage(size: size)

        image.lockFocus()
        NSColor.white.setFill()
        NSRect(origin: .zero, size: size).fill()
        image.unlockFocus()

        let document = ImageDocument(image: image, title: "Blank \(nextNumber)")
        addScreenshotWorkspace(for: document)
        resetCanvasStateForNewDocument()
        statusMessage = "Created blank tab"
        showEditor()
    }

    func selectScreenshotTab(id: UUID) {
        guard screenshotWorkspaces.contains(where: { $0.id == id }) else { return }
        selectedScreenshotID = id
        resetTransientImageEditState()
        selectedTool = .select
        statusMessage = selectedWorkspace?.document.title ?? "Selected screenshot"
    }

    func closeScreenshotTab(id: UUID) {
        guard let index = screenshotWorkspaces.firstIndex(where: { $0.id == id }) else { return }
        screenshotWorkspaces.remove(at: index)

        if selectedScreenshotID == id {
            selectedScreenshotID = screenshotWorkspaces.indices.contains(index)
                ? screenshotWorkspaces[index].id
                : screenshotWorkspaces.last?.id
        }

        resetTransientImageEditState()
        statusMessage = screenshotWorkspaces.isEmpty ? "No screenshots open" : "Closed screenshot"
    }

    func renameScreenshotTab(id: UUID, title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let index = screenshotWorkspaces.firstIndex(where: { $0.id == id }) else {
            return
        }

        screenshotWorkspaces[index].document.title = title
        statusMessage = "Renamed tab"
    }

    private func addScreenshotWorkspace(for document: ImageDocument) {
        let workspace = ScreenshotWorkspace(document: document)
        screenshotWorkspaces.append(workspace)
        selectedScreenshotID = workspace.id
    }

    private func hasScreenshot(id: UUID?) -> Bool {
        guard let id else { return false }
        return screenshotWorkspaces.contains { $0.id == id }
    }

    private func setSideBySideScreenshot(id: UUID, for slot: MSSideBySideSlot) {
        switch slot {
        case .left:
            sideBySideLeftScreenshotID = id
        case .right:
            sideBySideRightScreenshotID = id
        }
        selectedScreenshotID = id
    }

    private func sideBySideWorkspace(for slot: MSSideBySideSlot) -> ScreenshotWorkspace? {
        let id = slot == .left ? sideBySideLeftScreenshotID : sideBySideRightScreenshotID
        guard let id else { return nil }
        return screenshotWorkspaces.first { $0.id == id }
    }

    private func defaultSideBySideTitle(for slot: MSSideBySideSlot) -> String {
        switch slot {
        case .left:
            return "Comparison Left"
        case .right:
            return "Comparison Right"
        }
    }

    private func renderedImage(
        for workspace: ScreenshotWorkspace,
        showAnnotations: Bool,
        showMeasurements: Bool
    ) -> NSImage? {
        let image = ImageRenderer.render(document: workspace.document)
        return ExportRenderer.render(
            image: image,
            annotations: workspace.annotations,
            calibration: workspace.calibration,
            outputUnit: outputMeasurementUnit,
            showAnnotations: showAnnotations,
            showMeasurements: showMeasurements
        )
    }

    func rotateImageClockwise() {
        guard let imageDocument,
              let imageSize = currentImage?.size else {
            statusMessage = "No image to rotate"
            return
        }

        recordUndoState()
        imageDocument.rotateClockwise()
        transformAnnotations { rotatedClockwise($0, in: imageSize) }
        resetTransientImageEditState()
        refreshCalibrationFromAnnotations()
        isFitToWindow = true
        statusMessage = "Rotated 90° clockwise"
    }

    func flipImageHorizontally() {
        guard let imageDocument,
              let imageSize = currentImage?.size else {
            statusMessage = "No image to flip"
            return
        }

        recordUndoState()
        imageDocument.flipHorizontally()
        transformAnnotations { flippedHorizontally($0, in: imageSize) }
        resetTransientImageEditState()
        refreshCalibrationFromAnnotations()
        statusMessage = "Flipped horizontally"
    }

    func flipImageVertically() {
        guard let imageDocument,
              let imageSize = currentImage?.size else {
            statusMessage = "No image to flip"
            return
        }

        recordUndoState()
        imageDocument.flipVertically()
        transformAnnotations { flippedVertically($0, in: imageSize) }
        resetTransientImageEditState()
        refreshCalibrationFromAnnotations()
        statusMessage = "Flipped vertically"
    }

    func setFreeRotationDegrees(_ degrees: Double) {
        guard let imageDocument,
              let imageSize = currentImage?.size else {
            statusMessage = "No image to rotate"
            return
        }

        let delta = degrees - imageDocument.freeRotationDegrees
        guard abs(delta) >= 0.0001 else { return }

        recordUndoState()
        imageDocument.freeRotationDegrees = degrees
        transformAnnotations { rotated($0, in: imageSize, clockwiseDegrees: delta) }
        resetTransientImageEditState()
        refreshCalibrationFromAnnotations()
        isFitToWindow = true
        statusMessage = String(format: "Rotated %.0f°", degrees)
    }

    func resetImageRotation() {
        guard let imageDocument,
              let imageSize = currentImage?.size else {
            statusMessage = "No image to reset"
            return
        }

        let totalRotation = imageDocument.totalRotationDegrees
        guard abs(totalRotation.truncatingRemainder(dividingBy: 360)) >= 0.0001 else { return }

        recordUndoState()
        imageDocument.rotationQuarterTurns = 0
        imageDocument.freeRotationDegrees = 0
        transformAnnotations { rotated($0, in: imageSize, clockwiseDegrees: -totalRotation) }
        resetTransientImageEditState()
        refreshCalibrationFromAnnotations()
        isFitToWindow = true
        statusMessage = "Reset rotation"
    }

    func selectCropTool() {
        guard let currentImage else {
            statusMessage = "No image to crop"
            return
        }

        selectedTool = .crop
        cancelAnnotation()
        resetAngleCreation()
        cropSelectionRect = CGRect(origin: .zero, size: currentImage.size)
        statusMessage = "Drag crop edges, corners, or draw a new crop box"
    }

    func updateCropSelection(_ rect: CGRect, imageSize: CGSize) {
        cropSelectionRect = clampedCropRect(rect, imageSize: imageSize)
    }

    func applyCropSelection(imageSize: CGSize) {
        guard let imageDocument,
              let cropSelectionRect else {
            return
        }

        let cropRect = clampedCropRect(cropSelectionRect, imageSize: imageSize)
        guard cropRect.width >= 4, cropRect.height >= 4 else {
            self.cropSelectionRect = CGRect(origin: .zero, size: imageSize)
            statusMessage = "Crop area is too small"
            return
        }

        recordUndoState()
        let existingCrop = imageDocument.cropRect ?? CGRect(origin: .zero, size: imageSize)
        imageDocument.cropRect = CGRect(
            x: existingCrop.minX + cropRect.minX,
            y: existingCrop.minY + cropRect.minY,
            width: cropRect.width,
            height: cropRect.height
        )

        transformAnnotations { point in
            CGPoint(x: point.x - cropRect.minX, y: point.y - cropRect.minY)
        }
        selectedAnnotationID = nil
        self.cropSelectionRect = nil
        resetTransientImageEditState()
        refreshCalibrationFromAnnotations()
        isFitToWindow = true
        statusMessage = "Cropped image"
    }

    func resetImageCrop() {
        guard let imageDocument,
              let cropRect = imageDocument.cropRect else {
            statusMessage = "No crop to reset"
            return
        }

        recordUndoState()
        imageDocument.cropRect = nil
        transformAnnotations { point in
            CGPoint(x: point.x + cropRect.minX, y: point.y + cropRect.minY)
        }
        selectedAnnotationID = nil
        cropSelectionRect = nil
        resetTransientImageEditState()
        refreshCalibrationFromAnnotations()
        isFitToWindow = true
        statusMessage = "Reset crop"
    }

    func beginImageAdjustmentEdit() {
        guard let selectedWorkspace,
              selectedWorkspace.pendingImageAdjustmentUndoState == nil else { return }
        selectedWorkspace.pendingImageAdjustmentUndoState = currentUndoState()
    }

    func finishImageAdjustmentEdit() {
        guard let selectedWorkspace,
              let pendingImageAdjustmentUndoState = selectedWorkspace.pendingImageAdjustmentUndoState else { return }
        selectedWorkspace.undoStack.append(pendingImageAdjustmentUndoState)
        selectedWorkspace.redoStack.removeAll()
        selectedWorkspace.pendingImageAdjustmentUndoState = nil
    }

    func setImageBrightness(_ brightness: Double) {
        guard let imageDocument else { return }
        imageDocument.brightness = brightness
        statusMessage = String(format: "Brightness %.2f", brightness)
    }

    func setImageContrast(_ contrast: Double) {
        guard let imageDocument else { return }
        imageDocument.contrast = contrast
        statusMessage = String(format: "Contrast %.2f", contrast)
    }

    func setImageExposure(_ exposure: Double) {
        guard let imageDocument else { return }
        imageDocument.exposure = exposure
        statusMessage = String(format: "Exposure %+.1f", exposure)
    }

    func resetImageAdjustments() {
        guard let imageDocument,
              imageDocument.brightness != 0 || imageDocument.contrast != 1 || imageDocument.exposure != 0 else {
            statusMessage = "No image adjustments to reset"
            return
        }

        recordUndoState()
        imageDocument.brightness = 0
        imageDocument.contrast = 1
        imageDocument.exposure = 0
        statusMessage = "Reset image adjustments"
    }

    // MARK: - Annotation Management

    var selectedAnnotation: MSAnnotation? {
        guard let selectedAnnotationID else { return nil }
        return annotations.first { $0.id == selectedAnnotationID }
    }

    func annotationType(for tool: MSToolType) -> MSAnnotationType? {
        switch tool {
        case .arrow:
            return .arrow
        case .rectangle:
            return .rectangle
        case .ellipse:
            return .ellipse
        case .pen:
            return .pen
        case .region:
            return .region
        case .measure:
            return .measurement
        case .calibrate:
            return .calibration
        case .angle:
            return .angle
        case .parallelAngle:
            return .parallelAngle
        case .text:
            return .text
        case .blur:
            return .blur
        case .select, .crop, .colourPicker, .sideBySide:
            return nil
        }
    }

    func canDrawWithSelectedTool() -> Bool {
        switch selectedTool {
        case .measure, .calibrate, .angle, .parallelAngle, .arrow, .rectangle, .ellipse, .pen, .region, .blur:
            return true
        case .select, .text, .crop, .colourPicker, .sideBySide:
            return false
        }
    }

    func beginAnnotation(type: MSAnnotationType, at point: CGPoint) {
        if type == .angle {
            if angleCreationStage == 0 {
                angleFirstPoint = point
                angleVertex = point
                anglePerpendicularEnd = nil
                angleCreationStage = 1

                var annotation = MSAnnotation(type: .angle, start: point, end: point)
                annotation.stroke.color = colorData(from: annotationColor)
                annotation.stroke.lineWidth = annotationLineWidth
                inProgressAnnotation = annotation
                statusMessage = "Draw the first angle arm"
                return
            }

            if angleCreationStage == 2 {
                statusMessage = "Draw the second angle arm from the pivot"
                return
            }
        }

        if type == .parallelAngle {
            if angleCreationStage == 0 {
                angleFirstPoint = point
                angleVertex = nil
                anglePerpendicularEnd = nil
                angleCreationStage = 1

                var annotation = MSAnnotation(type: .parallelAngle, start: point, end: point)
                annotation.stroke.color = colorData(from: annotationColor)
                annotation.stroke.lineWidth = annotationLineWidth
                inProgressAnnotation = annotation
                statusMessage = "Draw the baseline"
                return
            }

            if angleCreationStage == 2 {
                statusMessage = "Draw the measured line from the end of the 90° arm"
                return
            }
        }

        if type == .text {
            recordUndoState()
            var annotation = MSAnnotation(type: .text, start: point, end: point)
            annotation.text = defaultText
            annotation.fontSize = defaultFontSize
            annotation.stroke.color = colorData(from: annotationColor)
            annotations.append(annotation)
            selectedAnnotationID = annotation.id
            statusMessage = "Added text"
            return
        }

        if type == .blur {
            var annotation = MSAnnotation(type: .blur, start: point, end: point)
            annotation.blurRadius = defaultBlurRadius
            annotation.blurBrushSize = defaultBlurBrushSize
            annotation.points = [point]
            annotation.stroke.color = colorData(from: annotationColor)
            inProgressAnnotation = annotation
            statusMessage = "Painting blur"
            return
        }

        if type == .pen {
            var annotation = MSAnnotation(type: .pen, start: point, end: point)
            annotation.points = [point]
            annotation.stroke.color = colorData(from: annotationColor)
            annotation.stroke.lineWidth = max(annotationLineWidth, defaultPenLineWidth)
            inProgressAnnotation = annotation
            statusMessage = "Drawing"
            return
        }

        if type == .region {
            var annotation = MSAnnotation(type: .region, start: point, end: point)
            annotation.points = [point]
            annotation.stroke.color = colorData(from: annotationColor)
            annotation.stroke.lineWidth = annotationLineWidth
            inProgressAnnotation = annotation
            statusMessage = "Tracing region"
            return
        }

        var annotation = MSAnnotation(type: type, start: point, end: point)
        annotation.stroke.color = colorData(from: annotationColor)
        annotation.stroke.lineWidth = annotationLineWidth
        inProgressAnnotation = annotation
    }

    func updateAnnotation(to point: CGPoint) {
        guard var annotation = inProgressAnnotation else { return }

        if annotation.type == .angle {
            if angleCreationStage == 1 {
                annotation.end = point
            } else if angleCreationStage == 2 {
                annotation.thirdPoint = point
            }
        } else if annotation.type == .parallelAngle {
            if angleCreationStage == 1 {
                annotation.end = point
            } else if angleCreationStage == 2 {
                annotation.fourthPoint = point
            }
        } else if annotation.type == .blur {
            annotation.end = point

            if let lastPoint = annotation.points.last {
                let distance = hypot(point.x - lastPoint.x, point.y - lastPoint.y)
                if distance >= max(2, annotation.blurBrushSize * 0.12) {
                    annotation.points.append(point)
                }
            } else {
                annotation.points = [point]
            }
        } else if annotation.type == .pen || annotation.type == .region {
            annotation.end = point

            if let lastPoint = annotation.points.last {
                let distance = hypot(point.x - lastPoint.x, point.y - lastPoint.y)
                if distance >= max(1.5, annotation.stroke.lineWidth * 0.35) {
                    annotation.points.append(point)
                }
            } else {
                annotation.points = [point]
            }
        } else {
            annotation.end = point
        }

        inProgressAnnotation = annotation
    }

    func finishAnnotation() {
        guard var annotation = inProgressAnnotation else { return }

        if annotation.type == .blur {
            guard !annotation.points.isEmpty else {
                inProgressAnnotation = nil
                return
            }

            if annotation.points.count == 1 {
                annotation.points.append(annotation.points[0])
            }

            recordUndoState()
            annotations.append(annotation)
            selectedAnnotationID = annotation.id
            inProgressAnnotation = nil
            statusMessage = "Added blur stroke"
            return
        }

        if annotation.type == .pen || annotation.type == .region {
            guard !annotation.points.isEmpty else {
                inProgressAnnotation = nil
                return
            }

            if annotation.points.count == 1 {
                annotation.points.append(annotation.points[0])
            }

            recordUndoState()
            annotations.append(annotation)
            selectedAnnotationID = annotation.id
            inProgressAnnotation = nil
            statusMessage = annotation.type == .region ? "Added measured region" : "Added pen stroke"
            return
        }

        if annotation.type == .angle {
            if angleCreationStage == 1 {
                guard annotation.length >= 2 else {
                    resetAngleCreation()
                    statusMessage = "Angle cancelled"
                    return
                }

                angleVertex = annotation.start
                annotation.thirdPoint = annotation.start
                inProgressAnnotation = annotation
                angleCreationStage = 2
                statusMessage = "Now drag the second angle arm from the pivot"
                return
            }

            if angleCreationStage == 2 {
                guard let thirdPoint = annotation.thirdPoint,
                      hypot(
                          thirdPoint.x - annotation.start.x,
                          thirdPoint.y - annotation.start.y
                      ) >= 2 else {
                    statusMessage = "Draw the second angle arm"
                    return
                }

                recordUndoState()
                annotations.append(annotation)
                selectedAnnotationID = annotation.id
                resetAngleCreation()
                selectedTool = .select
                statusMessage = "Added angle"
                return
            }
        }

        if annotation.type == .parallelAngle {
            if angleCreationStage == 1 {
                guard annotation.length >= 2 else {
                    resetAngleCreation()
                    statusMessage = "Parallel angle cancelled"
                    return
                }

                angleVertex = annotation.end
                let perpendicularLength = max(annotation.length * 0.6, 40)

                guard let perpendicularEnd = annotation.perpendicularPoint(
                    length: perpendicularLength
                ) else {
                    resetAngleCreation()
                    return
                }

                anglePerpendicularEnd = perpendicularEnd
                annotation.thirdPoint = perpendicularEnd
                annotation.fourthPoint = perpendicularEnd
                inProgressAnnotation = annotation
                angleCreationStage = 2
                statusMessage = "Now drag from the end of the 90° arm to define the measured line"
                return
            }

            if angleCreationStage == 2 {
                guard let thirdPoint = annotation.thirdPoint,
                      let fourthPoint = annotation.fourthPoint,
                      hypot(
                          fourthPoint.x - thirdPoint.x,
                          fourthPoint.y - thirdPoint.y
                      ) >= 2 else {
                    statusMessage = "Draw the measured line"
                    return
                }

                recordUndoState()
                annotations.append(annotation)
                selectedAnnotationID = annotation.id
                resetAngleCreation()
                selectedTool = .select
                statusMessage = "Added parallel angle"
                return
            }
        }

        guard annotation.length >= 2 else {
            inProgressAnnotation = nil
            return
        }

        if annotation.type == .calibration {
            annotation.measuredValue = calibrationKnownLength
            annotation.measurementUnit = calibrationUnit
        }

        recordUndoState()
        annotations.append(annotation)
        selectedAnnotationID = annotation.id
        inProgressAnnotation = nil

        if annotation.type == .calibration {
            applyCalibration(from: annotation)
        } else {
            statusMessage = "Added \(annotation.type.rawValue)"
        }
    }

    func cancelAnnotation() {
        inProgressAnnotation = nil
    }

    func resetAngleCreation() {
        angleCreationStage = 0
        angleFirstPoint = nil
        angleVertex = nil
        anglePerpendicularEnd = nil
        inProgressAnnotation = nil
    }

    func updateSampledColor(_ color: NSColor) {
        let rgb = color.usingColorSpace(.deviceRGB) ?? color
        sampledColor = Color(rgb)
        sampledHex = String(
            format: "#%02X%02X%02X",
            Int(rgb.redComponent * 255),
            Int(rgb.greenComponent * 255),
            Int(rgb.blueComponent * 255)
        )
        sampledRGB = String(
            format: "%d, %d, %d",
            Int(rgb.redComponent * 255),
            Int(rgb.greenComponent * 255),
            Int(rgb.blueComponent * 255)
        )
        copySampledHex()
    }

    func copySampledHex() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(sampledHex, forType: .string)
        statusMessage = "Copied \(sampledHex)"
    }

    func averageColor(for annotation: MSAnnotation) -> MSAverageColor? {
        guard annotation.isMeasuredRegion,
              let image = currentImage,
              let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else {
            return nil
        }

        let bounds = annotation.regionBounds.intersection(CGRect(origin: .zero, size: image.size))
        guard !bounds.isNull, bounds.width > 0, bounds.height > 0 else { return nil }

        let sampleTarget = 10_000.0
        let sampleStep = max(1, Int(sqrt((bounds.width * bounds.height) / sampleTarget)))
        var redTotal = 0.0
        var greenTotal = 0.0
        var blueTotal = 0.0
        var sampleCount = 0.0

        var y = Int(bounds.minY)
        while y < Int(bounds.maxY) {
            var x = Int(bounds.minX)
            while x < Int(bounds.maxX) {
                let point = CGPoint(x: CGFloat(x) + 0.5, y: CGFloat(y) + 0.5)

                if region(annotation, contains: point),
                   let color = bitmapColor(at: point, imageSize: image.size, bitmap: bitmap) {
                    redTotal += color.redComponent
                    greenTotal += color.greenComponent
                    blueTotal += color.blueComponent
                    sampleCount += 1
                }

                x += sampleStep
            }
            y += sampleStep
        }

        guard sampleCount > 0 else { return nil }

        let red = Int((redTotal / sampleCount * 255).rounded())
        let green = Int((greenTotal / sampleCount * 255).rounded())
        let blue = Int((blueTotal / sampleCount * 255).rounded())

        return MSAverageColor(
            hex: String(format: "#%02X%02X%02X", red, green, blue),
            rgb: "\(red), \(green), \(blue)"
        )
    }

    func deleteSelectedAnnotation() {
        guard let selectedAnnotationID else { return }

        deleteAnnotation(id: selectedAnnotationID)
    }

    func deleteAnnotation(id: UUID) {
        let deletingCalibration = annotations.first(where: {
            $0.id == id
        })?.type == .calibration

        recordUndoState()
        annotations.removeAll { $0.id == id }
        if selectedAnnotationID == id {
            selectedAnnotationID = nil
        }

        if deletingCalibration {
            calibration = nil
            statusMessage = "Deleted calibration"
        } else {
            statusMessage = "Deleted annotation"
        }
    }

    func selectAnnotation(id: UUID?) {
        selectedAnnotationID = id
    }

    func applyCalibrationFromSelection() {
        guard let selectedAnnotation,
              selectedAnnotation.type == .calibration else {
            statusMessage = "Select a calibration line first"
            return
        }

        applyCalibration(from: selectedAnnotation)
    }

    func clearCalibration() {
        calibration = nil
        statusMessage = "Calibration cleared"
    }

    func updateSelectedCalibrationValue() {
        guard let selectedAnnotationID,
              let index = annotations.firstIndex(where: { $0.id == selectedAnnotationID }),
              annotations[index].type == .calibration else {
            return
        }

        recordUndoState()
        annotations[index].measuredValue = calibrationKnownLength
        annotations[index].measurementUnit = calibrationUnit
        applyCalibration(from: annotations[index])
    }

    func measurementText(for annotation: MSAnnotation) -> String {
        annotation.displayValue(
            calibration: calibration,
            outputUnit: outputMeasurementUnit
        )
    }

    func measuredRegions() -> [MSAnnotation] {
        annotations.filter { $0.isMeasuredRegion }
    }

    func measuredItems() -> [MSAnnotation] {
        annotations.filter {
            $0.isMeasuredRegion
                || $0.type == .measurement
                || $0.type == .calibration
                || $0.type == .angle
                || $0.type == .parallelAngle
        }
    }

    func measuredItemTitle(for annotation: MSAnnotation) -> String {
        if annotation.isMeasuredRegion {
            return regionTitle(for: annotation)
        }

        if let title = annotation.title,
           !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return title
        }

        return defaultMeasuredItemTitle(for: annotation)
    }

    func compactMeasuredItemTitle(for annotation: MSAnnotation) -> String {
        if annotation.isMeasuredRegion {
            return compactRegionTitle(for: annotation)
        }

        guard let selectedWorkspace else { return "" }
        return compactMeasurementTitle(for: annotation, in: selectedWorkspace)
    }

    func inspectorMeasuredItemTitle(for annotation: MSAnnotation) -> String {
        let compactTitle = compactMeasuredItemTitle(for: annotation)
        let fullTitle = measuredItemTitle(for: annotation)
        return compactTitle.isEmpty ? fullTitle : "\(compactTitle): \(fullTitle)"
    }

    func updateMeasuredItemTitle(id: UUID, title: String) {
        guard let index = annotations.firstIndex(where: { $0.id == id }) else { return }

        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        annotations[index].title = trimmed.isEmpty ? nil : title
        statusMessage = "Renamed measurement"
    }

    private func defaultMeasuredItemTitle(for annotation: MSAnnotation) -> String {
        let matchingAnnotations = annotations.filter { $0.type == annotation.type }
        let index = matchingAnnotations.firstIndex { $0.id == annotation.id } ?? 0

        switch annotation.type {
        case .measurement:
            return "Measurement \(index + 1)"
        case .calibration:
            return "Calibration \(index + 1)"
        case .angle:
            return "Angle \(index + 1)"
        case .parallelAngle:
            return "Parallel Angle \(index + 1)"
        default:
            return "Measurement \(index + 1)"
        }
    }

    func regionTitle(for annotation: MSAnnotation) -> String {
        if let title = annotation.title,
           !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return title
        }

        return defaultRegionTitle(for: annotation)
    }

    func compactRegionTitle(for annotation: MSAnnotation) -> String {
        guard annotation.isMeasuredRegion else { return "" }

        let matchingRegions = measuredRegions().filter { $0.type == annotation.type }
        let index = matchingRegions.firstIndex { $0.id == annotation.id } ?? 0

        switch annotation.type {
        case .rectangle:
            return "R\(index + 1)"
        case .ellipse:
            return "E\(index + 1)"
        case .region:
            return "ROI\(index + 1)"
        default:
            return "M\(index + 1)"
        }
    }

    func inspectorRegionTitle(for annotation: MSAnnotation) -> String {
        let compactTitle = compactRegionTitle(for: annotation)
        let fullTitle = regionTitle(for: annotation)
        return compactTitle.isEmpty ? fullTitle : "\(compactTitle): \(fullTitle)"
    }

    private func defaultRegionTitle(for annotation: MSAnnotation) -> String {
        guard annotation.isMeasuredRegion else { return "" }

        let matchingRegions = measuredRegions().filter { $0.type == annotation.type }
        let index = matchingRegions.firstIndex { $0.id == annotation.id } ?? 0

        switch annotation.type {
        case .rectangle:
            return "Rectangle \(index + 1)"
        case .ellipse:
            return "Ellipse \(index + 1)"
        case .region:
            return "Region \(index + 1)"
        default:
            return "Shape \(index + 1)"
        }
    }

    func computationVariables() -> [MSComputationVariable] {
        if selectedTool == .sideBySide {
            let leftVariables = sideBySideWorkspace(for: .left).map {
                computationVariables(for: $0, expressionPrefix: "Left", displayPrefix: "Left")
            } ?? []
            let rightVariables = sideBySideWorkspace(for: .right).map {
                computationVariables(for: $0, expressionPrefix: "Right", displayPrefix: "Right")
            } ?? []
            return leftVariables + rightVariables
        }

        guard let selectedWorkspace else { return [] }
        return computationVariables(for: selectedWorkspace, expressionPrefix: nil, displayPrefix: nil)
    }

    func addComputationResult(name: String, expression: String, value: Double) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let result = MSComputationResult(
            name: trimmedName.isEmpty ? "Computation \(computationResults.count + 1)" : trimmedName,
            expression: expression,
            value: value,
            formattedValue: String(format: "%.4f", value)
        )
        computationResults.insert(result, at: 0)
        latestComparisonResult = nil
        statusMessage = "Saved computation"
    }

    func deleteComputationResult(id: UUID) {
        computationResults.removeAll { $0.id == id }
        statusMessage = "Deleted computation"
    }

    func clearComputationResults() {
        computationResults.removeAll()
        latestComparisonResult = nil
        statusMessage = "Cleared computations"
    }

    private func computationVariables(
        for workspace: ScreenshotWorkspace,
        expressionPrefix: String?,
        displayPrefix: String?
    ) -> [MSComputationVariable] {
        workspace.annotations.flatMap { annotation in
            computationVariables(
                for: annotation,
                in: workspace,
                expressionPrefix: expressionPrefix,
                displayPrefix: displayPrefix
            )
        }
    }

    private func computationVariables(
        for annotation: MSAnnotation,
        in workspace: ScreenshotWorkspace,
        expressionPrefix: String?,
        displayPrefix: String?
    ) -> [MSComputationVariable] {
        if annotation.isMeasuredRegion {
            let shortTitle = compactRegionTitle(for: annotation, in: workspace)
            var variables = [
                computationVariable(shortTitle: shortTitle, expressionPrefix: expressionPrefix, displayPrefix: displayPrefix, metric: "area", title: "Area", value: convertedArea(annotation.regionAreaSquarePixels, calibration: workspace.calibration), unit: areaUnitSuffix(calibration: workspace.calibration)),
                computationVariable(shortTitle: shortTitle, expressionPrefix: expressionPrefix, displayPrefix: displayPrefix, metric: "perimeter", title: "Perimeter", value: convertedLength(annotation.regionPerimeterPixels, calibration: workspace.calibration), unit: lengthUnitSuffix(calibration: workspace.calibration)),
                computationVariable(shortTitle: shortTitle, expressionPrefix: expressionPrefix, displayPrefix: displayPrefix, metric: "width", title: "Width", value: convertedLength(Double(annotation.width), calibration: workspace.calibration), unit: lengthUnitSuffix(calibration: workspace.calibration)),
                computationVariable(shortTitle: shortTitle, expressionPrefix: expressionPrefix, displayPrefix: displayPrefix, metric: "height", title: "Height", value: convertedLength(Double(annotation.height), calibration: workspace.calibration), unit: lengthUnitSuffix(calibration: workspace.calibration))
            ]

            if annotation.type == .ellipse {
                variables.append(contentsOf: [
                    computationVariable(shortTitle: shortTitle, expressionPrefix: expressionPrefix, displayPrefix: displayPrefix, metric: "radiusX", title: "Radius X", value: convertedLength(Double(annotation.width / 2), calibration: workspace.calibration), unit: lengthUnitSuffix(calibration: workspace.calibration)),
                    computationVariable(shortTitle: shortTitle, expressionPrefix: expressionPrefix, displayPrefix: displayPrefix, metric: "radiusY", title: "Radius Y", value: convertedLength(Double(annotation.height / 2), calibration: workspace.calibration), unit: lengthUnitSuffix(calibration: workspace.calibration)),
                    computationVariable(shortTitle: shortTitle, expressionPrefix: expressionPrefix, displayPrefix: displayPrefix, metric: "diameterX", title: "Diameter X", value: convertedLength(Double(annotation.width), calibration: workspace.calibration), unit: lengthUnitSuffix(calibration: workspace.calibration)),
                    computationVariable(shortTitle: shortTitle, expressionPrefix: expressionPrefix, displayPrefix: displayPrefix, metric: "diameterY", title: "Diameter Y", value: convertedLength(Double(annotation.height), calibration: workspace.calibration), unit: lengthUnitSuffix(calibration: workspace.calibration))
                ])
            }

            return variables
        }

        if annotation.type == .measurement || annotation.type == .calibration {
            let shortTitle = compactMeasurementTitle(for: annotation, in: workspace)
            return [
                computationVariable(shortTitle: shortTitle, expressionPrefix: expressionPrefix, displayPrefix: displayPrefix, metric: "length", title: "Length", value: convertedLength(Double(annotation.length), calibration: workspace.calibration), unit: lengthUnitSuffix(calibration: workspace.calibration))
            ]
        }

        if annotation.type == .angle || annotation.type == .parallelAngle {
            let shortTitle = compactMeasurementTitle(for: annotation, in: workspace)
            return [
                computationVariable(shortTitle: shortTitle, expressionPrefix: expressionPrefix, displayPrefix: displayPrefix, metric: "degrees", title: "Degrees", value: annotation.angleDeviationFromReference, unit: "deg")
            ]
        }

        return []
    }

    private func computationVariable(
        shortTitle: String,
        expressionPrefix: String?,
        displayPrefix: String?,
        metric: String,
        title: String,
        value: Double,
        unit: String
    ) -> MSComputationVariable {
        let sourceID = [expressionPrefix, shortTitle].compactMap { $0 }.joined(separator: ".")
        let sourceTitle = [displayPrefix, shortTitle].compactMap { $0 }.joined(separator: " ")
        return MSComputationVariable(
            id: "\(sourceID).\(metric)",
            sourceID: sourceID,
            sourceTitle: sourceTitle,
            metricID: metric,
            metricTitle: title,
            value: value,
            unit: unit
        )
    }

    private func compactRegionTitle(for annotation: MSAnnotation, in workspace: ScreenshotWorkspace) -> String {
        guard annotation.isMeasuredRegion else { return "" }

        let matchingRegions = workspace.annotations.filter { $0.isMeasuredRegion && $0.type == annotation.type }
        let index = matchingRegions.firstIndex { $0.id == annotation.id } ?? 0

        switch annotation.type {
        case .rectangle:
            return "R\(index + 1)"
        case .ellipse:
            return "E\(index + 1)"
        case .region:
            return "ROI\(index + 1)"
        default:
            return "M\(index + 1)"
        }
    }

    private func compactMeasurementTitle(for annotation: MSAnnotation, in workspace: ScreenshotWorkspace) -> String {
        let matchingAnnotations = workspace.annotations.filter { $0.type == annotation.type }
        let index = matchingAnnotations.firstIndex { $0.id == annotation.id } ?? 0

        switch annotation.type {
        case .measurement:
            return "M\(index + 1)"
        case .calibration:
            return "C\(index + 1)"
        case .angle:
            return "A\(index + 1)"
        case .parallelAngle:
            return "PA\(index + 1)"
        default:
            return "V\(index + 1)"
        }
    }

    private func convertedLength(_ pixels: Double, calibration: MSCalibration?) -> Double {
        if let calibration,
           let converted = calibration.convertedLength(forPixels: pixels, to: outputMeasurementUnit) {
            return converted
        }

        return pixels
    }

    private func convertedArea(_ squarePixels: Double, calibration: MSCalibration?) -> Double {
        if let calibration,
           let converted = calibration.convertedArea(forSquarePixels: squarePixels, to: outputMeasurementUnit) {
            return converted
        }

        return squarePixels
    }

    private func lengthUnitSuffix(calibration: MSCalibration?) -> String {
        if calibration != nil || outputMeasurementUnit == .pixels {
            return outputMeasurementUnit.rawValue
        }

        return "px"
    }

    private func areaUnitSuffix(calibration: MSCalibration?) -> String {
        "\(lengthUnitSuffix(calibration: calibration))^2"
    }

    func updateRegionTitle(id: UUID, title: String) {
        guard let index = annotations.firstIndex(where: { $0.id == id }),
              annotations[index].isMeasuredRegion else {
            return
        }

        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        annotations[index].title = trimmed.isEmpty ? nil : title
        statusMessage = "Renamed region"
    }

    private func applyCalibration(from annotation: MSAnnotation) {
        guard annotation.type == .calibration,
              let knownLength = annotation.measuredValue,
              knownLength > 0,
              annotation.measurementUnit != .pixels else {
            statusMessage = "Enter a valid calibration distance"
            return
        }

        calibration = MSCalibration(
            pixelLength: Double(annotation.length),
            knownLength: knownLength,
            unit: annotation.measurementUnit
        )
        calibrationKnownLength = knownLength
        calibrationUnit = annotation.measurementUnit
        outputMeasurementUnit = annotation.measurementUnit
        statusMessage = String(
            format: "Calibrated %.1f px = %.2f %@",
            Double(annotation.length),
            knownLength,
            annotation.measurementUnit.rawValue
        )
    }

    func clearAllAnnotations() {
        guard !annotations.isEmpty else { return }
        recordUndoState()
        annotations.removeAll()
        selectedAnnotationID = nil
        inProgressAnnotation = nil
        calibration = nil
        statusMessage = "Cleared all annotations"
    }

    func undo() {
        guard let selectedWorkspace,
              let previous = selectedWorkspace.undoStack.popLast() else { return }
        selectedWorkspace.redoStack.append(currentUndoState())
        restore(previous)
        statusMessage = "Undo"
    }

    func redo() {
        guard let selectedWorkspace,
              let next = selectedWorkspace.redoStack.popLast() else { return }
        selectedWorkspace.undoStack.append(currentUndoState())
        restore(next)
        statusMessage = "Redo"
    }

    func applyCurrentStyleToSelection() {
        guard let selectedAnnotationID,
              let index = annotations.firstIndex(where: { $0.id == selectedAnnotationID }) else {
            return
        }

        recordUndoState()
        annotations[index].stroke.color = colorData(from: annotationColor)
        annotations[index].stroke.lineWidth = annotationLineWidth
        statusMessage = "Updated annotation style"
    }

    func setAnnotationColor(_ color: Color) {
        annotationColor = color
        applyCurrentStyleToSelection()
    }

    func setAnnotationLineWidth(_ lineWidth: CGFloat) {
        annotationLineWidth = lineWidth
        applyCurrentStyleToSelection()
    }

    func updateSelectedText(_ text: String) {
        guard let id = selectedAnnotationID,
              let index = annotations.firstIndex(where: { $0.id == id }),
              annotations[index].type == .text else { return }

        recordUndoState()
        annotations[index].text = text
    }

    func updateSelectedFontSize(_ size: CGFloat) {
        guard let id = selectedAnnotationID,
              let index = annotations.firstIndex(where: { $0.id == id }),
              annotations[index].type == .text else { return }

        recordUndoState()
        annotations[index].fontSize = size
    }

    func updateSelectedBlurRadius(_ radius: Double) {
        guard let id = selectedAnnotationID,
              let index = annotations.firstIndex(where: { $0.id == id }),
              annotations[index].type == .blur else { return }

        recordUndoState()
        annotations[index].blurRadius = radius
    }

    func updateSelectedBlurBrushSize(_ size: Double) {
        guard let id = selectedAnnotationID,
              let index = annotations.firstIndex(where: { $0.id == id }),
              annotations[index].type == .blur else { return }

        recordUndoState()
        annotations[index].blurBrushSize = size
    }

    private func recordUndoState() {
        guard let selectedWorkspace else { return }
        selectedWorkspace.undoStack.append(currentUndoState())
        selectedWorkspace.redoStack.removeAll()
    }

    private func currentUndoState() -> AppUndoState {
        AppUndoState(
            annotations: annotations,
            imageDocumentState: imageDocument.map(ImageDocumentEditState.init)
        )
    }

    private func restore(_ state: AppUndoState) {
        annotations = state.annotations
        if let imageDocument,
           let imageDocumentState = state.imageDocumentState {
            imageDocumentState.apply(to: imageDocument)
        }
        selectedAnnotationID = nil
        inProgressAnnotation = nil
        cropSelectionRect = nil
        refreshCalibrationFromAnnotations()
        isFitToWindow = true
    }

    private func resetCanvasStateForNewDocument() {
        annotations.removeAll()
        selectedAnnotationID = nil
        inProgressAnnotation = nil
        angleCreationStage = 0
        angleFirstPoint = nil
        angleVertex = nil
        anglePerpendicularEnd = nil
        cropSelectionRect = nil
        selectedWorkspace?.undoStack.removeAll()
        selectedWorkspace?.redoStack.removeAll()
        selectedWorkspace?.pendingImageAdjustmentUndoState = nil
        selectedWorkspace?.lastMoveUndoState = nil
        selectedWorkspace?.lastEndpointEditUndoState = nil
        calibration = nil
        computationResults.removeAll()
        latestComparisonResult = nil
        outputMeasurementUnit = .centimetres
        zoomScale = 1
        isFitToWindow = true
        selectedTool = .select
    }

    private func resetTransientImageEditState() {
        resetAngleCreation()
        selectedWorkspace?.lastMoveUndoState = nil
        selectedWorkspace?.lastEndpointEditUndoState = nil
    }

    private func transformAnnotations(_ transformPoint: (CGPoint) -> CGPoint) {
        annotations = annotations.map { transformed($0, transformPoint: transformPoint) }
        inProgressAnnotation = inProgressAnnotation.map { transformed($0, transformPoint: transformPoint) }
    }

    private func transformed(
        _ annotation: MSAnnotation,
        transformPoint: (CGPoint) -> CGPoint
    ) -> MSAnnotation {
        var transformed = annotation
        transformed.start = transformPoint(annotation.start)
        transformed.end = transformPoint(annotation.end)
        transformed.thirdPoint = annotation.thirdPoint.map(transformPoint)
        transformed.fourthPoint = annotation.fourthPoint.map(transformPoint)
        transformed.points = annotation.points.map(transformPoint)
        return transformed
    }

    private func clampedCropRect(_ rect: CGRect, imageSize: CGSize) -> CGRect {
        let bounds = CGRect(origin: .zero, size: imageSize)
        let standardized = rect.standardized.intersection(bounds)

        guard !standardized.isNull else {
            return CGRect(origin: .zero, size: imageSize)
        }

        return standardized
    }

    private func rotatedClockwise(_ point: CGPoint, in imageSize: CGSize) -> CGPoint {
        rotated(point, in: imageSize, clockwiseDegrees: 90)
    }

    private func flippedHorizontally(_ point: CGPoint, in imageSize: CGSize) -> CGPoint {
        CGPoint(x: imageSize.width - point.x, y: point.y)
    }

    private func flippedVertically(_ point: CGPoint, in imageSize: CGSize) -> CGPoint {
        CGPoint(x: point.x, y: imageSize.height - point.y)
    }

    private func rotated(
        _ point: CGPoint,
        in imageSize: CGSize,
        clockwiseDegrees: Double
    ) -> CGPoint {
        let radians = clockwiseDegrees * .pi / 180
        let cosine = cos(radians)
        let sine = sin(radians)
        let outputSize = rotatedBoundingSize(for: imageSize, degrees: clockwiseDegrees)
        let centeredX = point.x - imageSize.width / 2
        let centeredY = point.y - imageSize.height / 2

        return CGPoint(
            x: centeredX * cosine + centeredY * sine + outputSize.width / 2,
            y: -centeredX * sine + centeredY * cosine + outputSize.height / 2
        )
    }

    private func rotatedBoundingSize(for size: CGSize, degrees: Double) -> CGSize {
        let radians = degrees * .pi / 180
        let cosine = abs(cos(radians))
        let sine = abs(sin(radians))

        return CGSize(
            width: max(1, size.width * cosine + size.height * sine),
            height: max(1, size.width * sine + size.height * cosine)
        )
    }

    private func colorData(from color: Color) -> ColorData {
        let nsColor = NSColor(color)
        let converted = nsColor.usingColorSpace(.deviceRGB) ?? nsColor
        return ColorData(
            red: converted.redComponent,
            green: converted.greenComponent,
            blue: converted.blueComponent,
            alpha: converted.alphaComponent
        )
    }

    private func bitmapColor(
        at point: CGPoint,
        imageSize: CGSize,
        bitmap: NSBitmapImageRep
    ) -> NSColor? {
        let normalizedX = min(max(point.x / max(imageSize.width, 1), 0), 1)
        let normalizedY = min(max(point.y / max(imageSize.height, 1), 0), 1)
        let pixelX = min(max(Int(normalizedX * CGFloat(bitmap.pixelsWide)), 0), bitmap.pixelsWide - 1)
        let pixelYFromTop = min(max(Int(normalizedY * CGFloat(bitmap.pixelsHigh)), 0), bitmap.pixelsHigh - 1)
        let pixelY = bitmap.pixelsHigh - 1 - pixelYFromTop

        return bitmap.colorAt(x: pixelX, y: pixelY)?.usingColorSpace(.deviceRGB)
    }

    private func region(_ annotation: MSAnnotation, contains point: CGPoint) -> Bool {
        switch annotation.type {
        case .rectangle:
            return annotation.normalizedRect.contains(point)
        case .ellipse:
            let rect = annotation.normalizedRect
            guard rect.width > 0, rect.height > 0 else { return false }
            let normalizedX = (point.x - rect.midX) / (rect.width / 2)
            let normalizedY = (point.y - rect.midY) / (rect.height / 2)
            return normalizedX * normalizedX + normalizedY * normalizedY <= 1
        case .region:
            return polygon(annotation.points, contains: point)
        default:
            return false
        }
    }

    private func polygon(_ points: [CGPoint], contains point: CGPoint) -> Bool {
        guard points.count >= 3 else { return false }

        var isInside = false
        var previousIndex = points.count - 1

        for currentIndex in points.indices {
            let current = points[currentIndex]
            let previous = points[previousIndex]
            let crossesY = (current.y > point.y) != (previous.y > point.y)

            if crossesY {
                let intersectionX = (previous.x - current.x) * (point.y - current.y) / (previous.y - current.y) + current.x
                if point.x < intersectionX {
                    isInside.toggle()
                }
            }

            previousIndex = currentIndex
        }

        return isInside
    }

    private func saveAnnotationColor() {
        let colorData = colorData(from: annotationColor)
        guard let encoded = try? JSONEncoder().encode(colorData) else { return }
        UserDefaults.standard.set(encoded, forKey: Self.annotationColorDefaultsKey)
    }

    private static func loadAnnotationColor() -> ColorData? {
        guard let data = UserDefaults.standard.data(forKey: annotationColorDefaultsKey) else {
            return nil
        }

        return try? JSONDecoder().decode(ColorData.self, from: data)
    }

    func moveSelectedAnnotation(by delta: CGSize) {
        guard let selectedWorkspace,
              let selectedAnnotationID,
              let index = annotations.firstIndex(where: { $0.id == selectedAnnotationID }) else {
            return
        }
        if selectedWorkspace.lastMoveUndoState == nil {
            selectedWorkspace.lastMoveUndoState = currentUndoState()
        }
        annotations[index].start.x += delta.width
        annotations[index].start.y += delta.height
        annotations[index].end.x += delta.width
        annotations[index].end.y += delta.height
        if (annotations[index].type == .angle || annotations[index].type == .parallelAngle),
           annotations[index].thirdPoint != nil {
            annotations[index].thirdPoint!.x += delta.width
            annotations[index].thirdPoint!.y += delta.height
        }
        if (annotations[index].type == .angle || annotations[index].type == .parallelAngle),
           annotations[index].fourthPoint != nil {
            annotations[index].fourthPoint!.x += delta.width
            annotations[index].fourthPoint!.y += delta.height
        }
        if annotations[index].type == .blur {
            annotations[index].points = annotations[index].points.map {
                CGPoint(x: $0.x + delta.width, y: $0.y + delta.height)
            }
        }
        if annotations[index].type == .pen || annotations[index].type == .region {
            annotations[index].points = annotations[index].points.map {
                CGPoint(x: $0.x + delta.width, y: $0.y + delta.height)
            }
        }
    }

    func finishMovingSelectedAnnotation() {
        guard let selectedWorkspace,
              let lastMoveUndoState = selectedWorkspace.lastMoveUndoState else { return }
        selectedWorkspace.undoStack.append(lastMoveUndoState)
        selectedWorkspace.redoStack.removeAll()
        selectedWorkspace.lastMoveUndoState = nil
    }

    func updateSelectedAnnotationEndpoint(isStart: Bool, to point: CGPoint) {
        guard let selectedWorkspace,
              let selectedAnnotationID,
              let index = annotations.firstIndex(where: { $0.id == selectedAnnotationID }) else {
            return
        }

        if selectedWorkspace.lastEndpointEditUndoState == nil {
            selectedWorkspace.lastEndpointEditUndoState = currentUndoState()
        }

        if isStart {
            annotations[index].start = point
        } else {
            annotations[index].end = point
        }

        if annotations[index].type == .calibration {
            applyCalibration(from: annotations[index])
        }
    }

    func updateSelectedAngleThirdPoint(to point: CGPoint) {
        guard let selectedWorkspace,
              let selectedAnnotationID,
              let index = annotations.firstIndex(where: { $0.id == selectedAnnotationID }) else {
            return
        }

        guard annotations[index].type == .angle || annotations[index].type == .parallelAngle else {
            return
        }

        if selectedWorkspace.lastEndpointEditUndoState == nil {
            selectedWorkspace.lastEndpointEditUndoState = currentUndoState()
        }

        annotations[index].thirdPoint = point
    }

    func updateSelectedAngleFourthPoint(to point: CGPoint) {
        guard let selectedWorkspace,
              let selectedAnnotationID,
              let index = annotations.firstIndex(where: { $0.id == selectedAnnotationID }),
              annotations[index].type == .angle || annotations[index].type == .parallelAngle else {
            return
        }

        if selectedWorkspace.lastEndpointEditUndoState == nil {
            selectedWorkspace.lastEndpointEditUndoState = currentUndoState()
        }

        annotations[index].fourthPoint = point
    }

    func finishEditingSelectedAnnotationEndpoint() {
        guard let selectedWorkspace,
              let lastEndpointEditUndoState = selectedWorkspace.lastEndpointEditUndoState else { return }

        selectedWorkspace.undoStack.append(lastEndpointEditUndoState)
        selectedWorkspace.redoStack.removeAll()
        selectedWorkspace.lastEndpointEditUndoState = nil

        if let selectedAnnotation {
            if selectedAnnotation.type == .calibration {
                applyCalibration(from: selectedAnnotation)
            }
            statusMessage = "Updated \(selectedAnnotation.type.rawValue)"
        }
    }

    func showEditor() {
        NSApplication.shared.activate(ignoringOtherApps: true)

        for window in NSApplication.shared.windows where window.canBecomeMain {
            window.makeKeyAndOrderFront(nil)
        }
    }

    func copyImage() {
        guard let currentImage,
              let rendered = ExportRenderer.render(
                image: currentImage,
                annotations: annotations,
                calibration: calibration,
                outputUnit: outputMeasurementUnit,
                showAnnotations: isAnnotationLayerVisible,
                showMeasurements: isMeasurementLayerVisible
              ) else {
            statusMessage = "Nothing to copy"
            return
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([rendered])
        recordExportHistory(action: .copied, image: rendered, editableSnapshot: currentEditableHistorySnapshot())
        statusMessage = "Copied annotated image"
    }

    func saveImage() {
        guard let currentImage,
              let rendered = ExportRenderer.render(
                image: currentImage,
                annotations: annotations,
                calibration: calibration,
                outputUnit: outputMeasurementUnit,
                showAnnotations: isAnnotationLayerVisible,
                showMeasurements: isMeasurementLayerVisible
              ),
              let tiff = rendered.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else {
            statusMessage = "Nothing to save"
            return
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "MeasureShot Export.png"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try png.write(to: url)
            recordExportHistory(
                action: .saved,
                image: rendered,
                fileURL: url,
                editableSnapshot: currentEditableHistorySnapshot()
            )
            statusMessage = "Image saved"
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func shareImage() {
        guard let currentImage,
              let rendered = ExportRenderer.render(
                image: currentImage,
                annotations: annotations,
                calibration: calibration,
                outputUnit: outputMeasurementUnit,
                showAnnotations: isAnnotationLayerVisible,
                showMeasurements: isMeasurementLayerVisible
              ) else {
            statusMessage = "Nothing to share"
            return
        }

        guard let window = NSApplication.shared.keyWindow,
              let contentView = window.contentView else {
            statusMessage = "Unable to share"
            return
        }

        NSSharingServicePicker(items: [rendered]).show(
            relativeTo: contentView.bounds,
            of: contentView,
            preferredEdge: .minY
        )
        recordExportHistory(action: .shared, image: rendered, editableSnapshot: currentEditableHistorySnapshot())
    }

    func export(option: MSExportOption) {
        switch option {
        case .standard:
            saveImage()
        case .plain:
            saveExportImage(renderPlainExportImage(), filename: "MeasureShot Plain.png")
        case .allOverlays:
            saveExportImage(
                renderExportImage(showAnnotations: true, showMeasurements: true),
                filename: "MeasureShot All Overlays.png"
            )
        case .legendOverlay:
            saveExportImage(renderLegendOverlayExportImage(), filename: "MeasureShot Legend Overlay.png")
        case .sidebarLegend:
            saveExportImage(renderSidebarLegendExportImage(), filename: "MeasureShot Sidebar Legend.png")
        case .annotationsCSV:
            saveAnnotationsCSV()
        }
    }

    func exportPreviewImage(for option: MSExportOption) -> NSImage? {
        switch option {
        case .standard:
            return renderExportImage(
                showAnnotations: isAnnotationLayerVisible,
                showMeasurements: isMeasurementLayerVisible
            )
        case .plain:
            return renderPlainExportImage()
        case .allOverlays:
            return renderExportImage(showAnnotations: true, showMeasurements: true)
        case .legendOverlay:
            return renderLegendOverlayExportImage()
        case .sidebarLegend:
            return renderSidebarLegendExportImage()
        case .annotationsCSV:
            return nil
        }
    }

    func copyExportHistoryItem(id: UUID) {
        guard let item = exportHistory.first(where: { $0.id == id }) else { return }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([item.image])
        statusMessage = "Copied export from history"
    }

    func openExportHistoryItem(id: UUID) {
        guard let item = exportHistory.first(where: { $0.id == id }) else { return }

        if let editableSnapshot = item.editableSnapshot {
            let document = ImageDocument(
                image: editableSnapshot.document.originalImage,
                title: editableSnapshot.document.title
            )
            document.rotationQuarterTurns = editableSnapshot.document.rotationQuarterTurns
            document.freeRotationDegrees = editableSnapshot.document.freeRotationDegrees
            document.isFlippedHorizontally = editableSnapshot.document.isFlippedHorizontally
            document.isFlippedVertically = editableSnapshot.document.isFlippedVertically
            document.cropRect = editableSnapshot.document.cropRect
            document.brightness = editableSnapshot.document.brightness
            document.contrast = editableSnapshot.document.contrast
            document.exposure = editableSnapshot.document.exposure

            addScreenshotWorkspace(for: document)
            annotations = editableSnapshot.annotations
            calibration = editableSnapshot.calibration
            outputMeasurementUnit = editableSnapshot.outputMeasurementUnit
            isAnnotationLayerVisible = editableSnapshot.isAnnotationLayerVisible
            isMeasurementLayerVisible = editableSnapshot.isMeasurementLayerVisible
            isGuideLayerVisible = editableSnapshot.isGuideLayerVisible
            computationResults = editableSnapshot.computationResults
            resetTransientImageEditState()
            statusMessage = "Opened editable export from history"
        } else {
            let document = ImageDocument(
                image: item.image,
                title: "History \(Self.exportHistoryTabDateFormatter.string(from: item.createdAt))"
            )
            addScreenshotWorkspace(for: document)
            resetCanvasStateForNewDocument()
            statusMessage = "Opened flattened export from history"
        }
        showEditor()
    }

    func clearExportHistory() {
        guard !exportHistory.isEmpty else { return }

        for item in exportHistory {
            if let imageFileURL = item.imageFileURL {
                try? FileManager.default.removeItem(at: imageFileURL)
            }
            removeEditableHistorySourceImage(for: item)
        }

        exportHistory.removeAll()
        saveExportHistoryManifest()
        statusMessage = "Cleared export history"
    }

    private func recordExportHistory(
        action: MSExportHistoryAction,
        image: NSImage,
        fileURL: URL? = nil,
        editableSnapshot: MSExportHistoryEditableSnapshot? = nil
    ) {
        let id = UUID()
        let imageFileURL = persistExportHistoryImage(id: id, image: image)
        let editableSnapshot = persistEditableHistorySnapshot(
            editableSnapshot,
            id: id
        )

        exportHistory.insert(
            MSExportHistoryItem(
                id: id,
                action: action,
                image: image,
                createdAt: Date(),
                fileURL: fileURL,
                imageFileURL: imageFileURL,
                editableSnapshot: editableSnapshot
            ),
            at: 0
        )
        saveExportHistoryManifest()
        pruneExportHistory()
    }

    private func renderPlainExportImage() -> NSImage? {
        currentImage
    }

    private func renderSideBySideComparisonImage() -> NSImage? {
        guard let left = sideBySideRenderedImage(for: .left),
              let right = sideBySideRenderedImage(for: .right) else {
            return nil
        }

        let padding: CGFloat = 32
        let labelHeight: CGFloat = 40
        let targetPaneHeight = max(left.size.height, right.size.height)
        let leftScale = targetPaneHeight / max(left.size.height, 1)
        let rightScale = targetPaneHeight / max(right.size.height, 1)
        let leftSize = CGSize(width: left.size.width * leftScale, height: targetPaneHeight)
        let rightSize = CGSize(width: right.size.width * rightScale, height: targetPaneHeight)
        let outputSize = CGSize(
            width: leftSize.width + rightSize.width + padding * 3,
            height: targetPaneHeight + labelHeight + padding * 2
        )
        let output = NSImage(size: outputSize)

        output.lockFocus()
        defer { output.unlockFocus() }

        NSColor.white.setFill()
        NSRect(origin: .zero, size: outputSize).fill()

        drawSideBySideLabel(sideBySideTitle(for: .left), at: CGPoint(x: padding, y: outputSize.height - padding - 24))
        drawSideBySideLabel(sideBySideTitle(for: .right), at: CGPoint(x: padding * 2 + leftSize.width, y: outputSize.height - padding - 24))

        left.draw(
            in: NSRect(x: padding, y: padding, width: leftSize.width, height: leftSize.height),
            from: NSRect(origin: .zero, size: left.size),
            operation: .copy,
            fraction: 1
        )
        right.draw(
            in: NSRect(x: padding * 2 + leftSize.width, y: padding, width: rightSize.width, height: rightSize.height),
            from: NSRect(origin: .zero, size: right.size),
            operation: .copy,
            fraction: 1
        )

        NSColor.separatorColor.setStroke()
        let divider = NSBezierPath()
        let dividerX = padding * 1.5 + leftSize.width
        divider.move(to: CGPoint(x: dividerX, y: padding))
        divider.line(to: CGPoint(x: dividerX, y: outputSize.height - padding))
        divider.lineWidth = 2
        divider.stroke()

        return output
    }

    private func drawSideBySideLabel(_ label: String, at point: CGPoint) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 22, weight: .semibold),
            .foregroundColor: NSColor.labelColor
        ]
        NSAttributedString(string: label, attributes: attributes).draw(at: point)
    }

    private func renderExportImage(showAnnotations: Bool, showMeasurements: Bool) -> NSImage? {
        guard let currentImage else { return nil }

        return ExportRenderer.render(
            image: currentImage,
            annotations: annotations,
            calibration: calibration,
            outputUnit: outputMeasurementUnit,
            showAnnotations: showAnnotations,
            showMeasurements: showMeasurements
        )
    }

    private func renderLegendOverlayExportImage() -> NSImage? {
        guard let currentImage else { return nil }

        return ExportRenderer.renderLegendOverlay(
            image: currentImage,
            annotations: annotations,
            calibration: calibration,
            outputUnit: outputMeasurementUnit,
            computationLines: currentComputationExportLines()
        )
    }

    private func renderSidebarLegendExportImage() -> NSImage? {
        guard let currentImage else { return nil }

        return ExportRenderer.renderSidebarLegend(
            image: currentImage,
            annotations: annotations,
            calibration: calibration,
            outputUnit: outputMeasurementUnit,
            computationLines: currentComputationExportLines()
        )
    }

    private func saveExportImage(
        _ image: NSImage?,
        filename: String,
        includeEditableSnapshot: Bool = true
    ) {
        guard let image,
              let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else {
            statusMessage = "Nothing to export"
            return
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = filename

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try png.write(to: url)
            recordExportHistory(
                action: .saved,
                image: image,
                fileURL: url,
                editableSnapshot: includeEditableSnapshot ? currentEditableHistorySnapshot() : nil
            )
            statusMessage = "Export saved"
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func saveAnnotationsCSV() {
        guard !annotations.isEmpty else {
            statusMessage = "No annotations to export"
            return
        }

        let csv = ExportRenderer.annotationCSV(
            annotations: annotations,
            calibration: calibration,
            outputUnit: outputMeasurementUnit,
            computationLines: currentComputationExportLines()
        )

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "MeasureShot Annotations.csv"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try csv.write(to: url, atomically: true, encoding: .utf8)
            statusMessage = "Annotations CSV saved"
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func exportHistoryItems(
        for range: MSExportHistoryRange,
        selectedDate: Date
    ) -> [MSExportHistoryItem] {
        let calendar = Calendar.current
        let now = Date()

        switch range {
        case .today:
            return exportHistory.filter {
                calendar.isDate($0.createdAt, inSameDayAs: now)
            }
        case .yesterday:
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: now) else { return [] }
            return exportHistory.filter {
                calendar.isDate($0.createdAt, inSameDayAs: yesterday)
            }
        case .lastWeek:
            let startDate = calendar.date(byAdding: .day, value: -7, to: now) ?? now
            return exportHistory.filter { $0.createdAt >= startDate }
        case .lastMonth:
            let startDate = calendar.date(byAdding: .day, value: -30, to: now) ?? now
            return exportHistory.filter { $0.createdAt >= startDate }
        case .customDay:
            return exportHistory.filter {
                calendar.isDate($0.createdAt, inSameDayAs: selectedDate)
            }
        }
    }

    private func pruneExportHistory() {
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? .distantPast
        let keptItems = Array(exportHistory.filter { $0.createdAt >= cutoffDate }.prefix(300))
        let keptIDs = Set(keptItems.map(\.id))
        let removedItems = exportHistory.filter { !keptIDs.contains($0.id) }
        exportHistory = keptItems

        for item in removedItems {
            if let imageFileURL = item.imageFileURL {
                try? FileManager.default.removeItem(at: imageFileURL)
            }
            removeEditableHistorySourceImage(for: item)
        }

        saveExportHistoryManifest()
    }

    private func loadExportHistory() {
        guard let data = try? Data(contentsOf: exportHistoryManifestURL),
              let records = try? JSONDecoder().decode([ExportHistoryRecord].self, from: data) else {
            return
        }

        exportHistory = records.compactMap { record in
            let imageURL = exportHistoryDirectory.appendingPathComponent(record.imageFilename)
            guard let image = NSImage(contentsOf: imageURL) else { return nil }

            return MSExportHistoryItem(
                id: record.id,
                action: record.action,
                image: image,
                createdAt: record.createdAt,
                fileURL: record.fileURL,
                imageFileURL: imageURL,
                editableSnapshot: editableSnapshot(from: record.editableSnapshot)
            )
        }
        .sorted { $0.createdAt > $1.createdAt }

        pruneExportHistory()
    }

    private func saveExportHistoryManifest() {
        let records = exportHistory.compactMap { item -> ExportHistoryRecord? in
            guard let imageFileURL = item.imageFileURL else { return nil }
            return ExportHistoryRecord(
                id: item.id,
                action: item.action,
                createdAt: item.createdAt,
                fileURL: item.fileURL,
                imageFilename: imageFileURL.lastPathComponent,
                editableSnapshot: editableRecord(from: item.editableSnapshot, id: item.id)
            )
        }

        do {
            try FileManager.default.createDirectory(
                at: exportHistoryDirectory,
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(records)
            try data.write(to: exportHistoryManifestURL, options: .atomic)
        } catch {
            statusMessage = "Unable to save history"
        }
    }

    private func persistExportHistoryImage(id: UUID, image: NSImage) -> URL? {
        persistHistoryImage(image, filename: "\(id.uuidString).png")
    }

    private func persistEditableHistorySnapshot(
        _ snapshot: MSExportHistoryEditableSnapshot?,
        id: UUID
    ) -> MSExportHistoryEditableSnapshot? {
        guard let snapshot else { return nil }
        guard persistHistoryImage(
            snapshot.document.originalImage,
            filename: sourceImageFilename(for: id)
        ) != nil else {
            return nil
        }

        return snapshot
    }

    private func persistHistoryImage(_ image: NSImage, filename: String) -> URL? {
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else {
            return nil
        }

        do {
            try FileManager.default.createDirectory(
                at: exportHistoryDirectory,
                withIntermediateDirectories: true
            )
            let url = exportHistoryDirectory.appendingPathComponent(filename)
            try png.write(to: url, options: .atomic)
            return url
        } catch {
            statusMessage = "Unable to save history image"
            return nil
        }
    }

    private func currentEditableHistorySnapshot() -> MSExportHistoryEditableSnapshot? {
        guard let imageDocument else { return nil }

        let documentSnapshot = MSImageDocumentSnapshot(
            title: imageDocument.title,
            originalImage: imageDocument.originalImage,
            rotationQuarterTurns: imageDocument.rotationQuarterTurns,
            freeRotationDegrees: imageDocument.freeRotationDegrees,
            isFlippedHorizontally: imageDocument.isFlippedHorizontally,
            isFlippedVertically: imageDocument.isFlippedVertically,
            cropRect: imageDocument.cropRect,
            brightness: imageDocument.brightness,
            contrast: imageDocument.contrast,
            exposure: imageDocument.exposure
        )

        return MSExportHistoryEditableSnapshot(
            document: documentSnapshot,
            annotations: annotations,
            calibration: calibration,
            outputMeasurementUnit: outputMeasurementUnit,
            isAnnotationLayerVisible: isAnnotationLayerVisible,
            isMeasurementLayerVisible: isMeasurementLayerVisible,
            isGuideLayerVisible: isGuideLayerVisible,
            computationResults: computationResults
        )
    }

    private func currentComputationExportLines() -> [String] {
        let savedLines = computationResults.map(\.exportLine)
        guard let latestComparisonResult,
              !latestComparisonResult.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return savedLines
        }

        return savedLines + [latestComparisonResult]
    }

    private func editableRecord(
        from snapshot: MSExportHistoryEditableSnapshot?,
        id: UUID
    ) -> ExportHistoryEditableRecord? {
        guard let snapshot else { return nil }

        return ExportHistoryEditableRecord(
            documentTitle: snapshot.document.title,
            sourceImageFilename: sourceImageFilename(for: id),
            rotationQuarterTurns: snapshot.document.rotationQuarterTurns,
            freeRotationDegrees: snapshot.document.freeRotationDegrees,
            isFlippedHorizontally: snapshot.document.isFlippedHorizontally,
            isFlippedVertically: snapshot.document.isFlippedVertically,
            cropRect: snapshot.document.cropRect,
            brightness: snapshot.document.brightness,
            contrast: snapshot.document.contrast,
            exposure: snapshot.document.exposure,
            annotations: snapshot.annotations,
            calibration: snapshot.calibration,
            outputMeasurementUnit: snapshot.outputMeasurementUnit,
            isAnnotationLayerVisible: snapshot.isAnnotationLayerVisible,
            isMeasurementLayerVisible: snapshot.isMeasurementLayerVisible,
            isGuideLayerVisible: snapshot.isGuideLayerVisible,
            computationResults: snapshot.computationResults
        )
    }

    private func editableSnapshot(
        from record: ExportHistoryEditableRecord?
    ) -> MSExportHistoryEditableSnapshot? {
        guard let record else { return nil }

        let sourceImageURL = exportHistoryDirectory.appendingPathComponent(record.sourceImageFilename)
        guard let sourceImage = NSImage(contentsOf: sourceImageURL) else { return nil }

        let documentSnapshot = MSImageDocumentSnapshot(
            title: record.documentTitle,
            originalImage: sourceImage,
            rotationQuarterTurns: record.rotationQuarterTurns,
            freeRotationDegrees: record.freeRotationDegrees,
            isFlippedHorizontally: record.isFlippedHorizontally,
            isFlippedVertically: record.isFlippedVertically,
            cropRect: record.cropRect,
            brightness: record.brightness,
            contrast: record.contrast,
            exposure: record.exposure
        )

        return MSExportHistoryEditableSnapshot(
            document: documentSnapshot,
            annotations: record.annotations,
            calibration: record.calibration,
            outputMeasurementUnit: record.outputMeasurementUnit,
            isAnnotationLayerVisible: record.isAnnotationLayerVisible,
            isMeasurementLayerVisible: record.isMeasurementLayerVisible,
            isGuideLayerVisible: record.isGuideLayerVisible,
            computationResults: record.computationResults ?? []
        )
    }

    private func removeEditableHistorySourceImage(for item: MSExportHistoryItem) {
        guard item.editableSnapshot != nil else { return }
        let url = exportHistoryDirectory.appendingPathComponent(sourceImageFilename(for: item.id))
        try? FileManager.default.removeItem(at: url)
    }

    private func sourceImageFilename(for id: UUID) -> String {
        "\(id.uuidString)-source.png"
    }

    private var exportHistoryDirectory: URL {
        let baseURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory

        return baseURL
            .appendingPathComponent("MeasureShot", isDirectory: true)
            .appendingPathComponent("ExportHistory", isDirectory: true)
    }

    private var exportHistoryManifestURL: URL {
        exportHistoryDirectory.appendingPathComponent(Self.exportHistoryManifestFilename)
    }

    func zoomIn() {
        isFitToWindow = false
        zoomScale = min(zoomScale * 1.25, 8)
    }

    func zoomOut() {
        isFitToWindow = false
        zoomScale = max(zoomScale / 1.25, 0.1)
    }

    func zoomToActualSize() {
        isFitToWindow = false
        zoomScale = 1
    }

    func zoomToFit() {
        isFitToWindow = true
    }

    func isLayerVisible(_ layer: MSCanvasLayer) -> Bool {
        switch layer {
        case .annotations: return isAnnotationLayerVisible
        case .measurements: return isMeasurementLayerVisible
        case .guides: return isGuideLayerVisible
        }
    }

    func setLayer(_ layer: MSCanvasLayer, visible: Bool) {
        switch layer {
        case .annotations:
            isAnnotationLayerVisible = visible
        case .measurements:
            isMeasurementLayerVisible = visible
        case .guides:
            isGuideLayerVisible = visible
        }
    }

    func selectLayer(_ layer: MSCanvasLayer) {
        activeLayer = layer
        statusMessage = "Active layer: \(layer.title)"
    }

    func toggleAnnotationLayer() {
        setLayer(.annotations, visible: !isAnnotationLayerVisible)
    }

    func toggleMeasurementLayer() {
        setLayer(.measurements, visible: !isMeasurementLayerVisible)
    }

    func toggleGuideLayer() {
        setLayer(.guides, visible: !isGuideLayerVisible)
    }
    private func refreshCalibrationFromAnnotations() {
        guard let calibrationAnnotation = annotations.last(where: {
            $0.type == .calibration && $0.measuredValue != nil
        }) else {
            calibration = nil
            return
        }

        applyCalibration(from: calibrationAnnotation)
    }
}
