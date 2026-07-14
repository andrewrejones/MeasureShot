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

@MainActor
@Observable
final class AppState {
    var currentImage: NSImage?
    var selectedTool: MSToolType = .select
    var statusMessage = "Ready"
    var isCapturing = false
    var zoomScale: CGFloat = 1
    var isFitToWindow = true

    var isAnnotationLayerVisible = true
    var isMeasurementLayerVisible = true
    var isGuideLayerVisible = true

    var activeLayer: MSCanvasLayer = .annotations

    // MARK: - Canvas State

    var annotations: [MSAnnotation] = []
    var selectedAnnotationID: UUID?
    var inProgressAnnotation: MSAnnotation?
    var annotationColor: Color = .red
    var annotationLineWidth: CGFloat = 2
    var calibration: MSCalibration?
    var outputMeasurementUnit: MSMeasurementUnit = .millimetres
    var calibrationKnownLength: Double = 10
    var calibrationUnit: MSMeasurementUnit = .millimetres

    var sampledColor: Color = .clear
    var sampledHex: String = "#000000"
    var sampledRGB: String = "0, 0, 0"

    var defaultText = "Double-click to edit"
    var defaultFontSize: CGFloat = 18
    var defaultBlurRadius: Double = 12
    var defaultBlurBrushSize: Double = 44
    var showBlurMask = false

    private var angleCreationStage = 0
    private var angleFirstPoint: CGPoint?
    private var angleVertex: CGPoint?
    private var anglePerpendicularEnd: CGPoint?

    private var undoStack: [[MSAnnotation]] = []
    private var redoStack: [[MSAnnotation]] = []

    func startCapture() {
        guard !isCapturing else { return }

        isCapturing = true
        statusMessage = "Select a region to capture"

        CaptureManager.shared.startRegionCapture { [weak self] result in
            guard let self else { return }

            self.isCapturing = false

            switch result {
            case .success(let image):
                self.currentImage = image
                self.annotations.removeAll()
                self.selectedAnnotationID = nil
                self.inProgressAnnotation = nil
                self.undoStack.removeAll()
                self.redoStack.removeAll()
                self.calibration = nil
                self.outputMeasurementUnit = .millimetres
                self.zoomScale = 1
                self.isFitToWindow = true
                self.selectedTool = .select
                self.statusMessage = "Capture complete"
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
        case .measure:
            return .measurement
        case .calibrate:
            return .calibration
        case .angle:
            return .angle
        case .text:
            return .text
        case .blur:
            return .blur
        case .select, .colourPicker:
            return nil
        }
    }

    func canDrawWithSelectedTool() -> Bool {
        switch selectedTool {
        case .measure, .calibrate, .angle, .arrow, .rectangle, .ellipse, .blur:
            return true
        case .select, .text, .colourPicker:
            return false
        }
    }

    func beginAnnotation(type: MSAnnotationType, at point: CGPoint) {
        if type == .angle {
            if angleCreationStage == 0 {
                angleFirstPoint = point
                angleVertex = nil
                anglePerpendicularEnd = nil
                angleCreationStage = 1

                var annotation = MSAnnotation(type: .angle, start: point, end: point)
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

        if annotation.type == .angle {
            if angleCreationStage == 1 {
                guard annotation.length >= 2 else {
                    resetAngleCreation()
                    statusMessage = "Angle cancelled"
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
                statusMessage = "Added three-line angle"
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
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(sampledHex, forType: .string)
        statusMessage = "Copied \(sampledHex)"
    }

    func deleteSelectedAnnotation() {
        guard let selectedAnnotationID else { return }

        let deletingCalibration = annotations.first(where: {
            $0.id == selectedAnnotationID
        })?.type == .calibration

        recordUndoState()
        annotations.removeAll { $0.id == selectedAnnotationID }
        self.selectedAnnotationID = nil

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
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(annotations)
        annotations = previous
        selectedAnnotationID = nil
        inProgressAnnotation = nil
        refreshCalibrationFromAnnotations()
        statusMessage = "Undo"
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(annotations)
        annotations = next
        selectedAnnotationID = nil
        inProgressAnnotation = nil
        refreshCalibrationFromAnnotations()
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
        undoStack.append(annotations)
        redoStack.removeAll()
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

    private var lastMoveUndoState: [MSAnnotation]?
    private var lastEndpointEditUndoState: [MSAnnotation]?
    func moveSelectedAnnotation(by delta: CGSize) {
        guard let selectedAnnotationID,
              let index = annotations.firstIndex(where: { $0.id == selectedAnnotationID }) else {
            return
        }
        if lastMoveUndoState == nil {
            lastMoveUndoState = annotations
        }
        annotations[index].start.x += delta.width
        annotations[index].start.y += delta.height
        annotations[index].end.x += delta.width
        annotations[index].end.y += delta.height
        if annotations[index].type == .angle,
           annotations[index].thirdPoint != nil {
            annotations[index].thirdPoint!.x += delta.width
            annotations[index].thirdPoint!.y += delta.height
        }
        if annotations[index].type == .angle,
           annotations[index].fourthPoint != nil {
            annotations[index].fourthPoint!.x += delta.width
            annotations[index].fourthPoint!.y += delta.height
        }
        if annotations[index].type == .blur {
            annotations[index].points = annotations[index].points.map {
                CGPoint(x: $0.x + delta.width, y: $0.y + delta.height)
            }
        }
    }

    func finishMovingSelectedAnnotation() {
        guard let lastMoveUndoState else { return }
        undoStack.append(lastMoveUndoState)
        redoStack.removeAll()
        self.lastMoveUndoState = nil
    }

    func updateSelectedAnnotationEndpoint(isStart: Bool, to point: CGPoint) {
        guard let selectedAnnotationID,
              let index = annotations.firstIndex(where: { $0.id == selectedAnnotationID }) else {
            return
        }

        if lastEndpointEditUndoState == nil {
            lastEndpointEditUndoState = annotations
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
        guard let selectedAnnotationID,
              let index = annotations.firstIndex(where: { $0.id == selectedAnnotationID }) else {
            return
        }

        guard annotations[index].type == .angle else {
            return
        }

        if lastEndpointEditUndoState == nil {
            lastEndpointEditUndoState = annotations
        }

        annotations[index].thirdPoint = point
    }

    func updateSelectedAngleFourthPoint(to point: CGPoint) {
        guard let selectedAnnotationID,
              let index = annotations.firstIndex(where: { $0.id == selectedAnnotationID }),
              annotations[index].type == .angle else {
            return
        }

        if lastEndpointEditUndoState == nil {
            lastEndpointEditUndoState = annotations
        }

        annotations[index].fourthPoint = point
    }

    func finishEditingSelectedAnnotationEndpoint() {
        guard let lastEndpointEditUndoState else { return }

        undoStack.append(lastEndpointEditUndoState)
        redoStack.removeAll()
        self.lastEndpointEditUndoState = nil

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
