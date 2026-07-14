//
//  EditorView.swift
//  MeasureShot
//
//  Created by Andrew Jones on 7/13/26.
//

import SwiftUI

struct EditorView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(spacing: 0) {
            topToolbar
            Divider()

            HSplitView {
                ToolSidebar()
                    .environment(appState)
                    .frame(minWidth: 150, idealWidth: 170, maxWidth: 210)

                EditorCanvas()
                    .environment(appState)
                    .frame(minWidth: 500, maxWidth: .infinity, maxHeight: .infinity)

                InspectorSidebar()
                    .environment(appState)
                    .frame(minWidth: 220, idealWidth: 250, maxWidth: 300)
            }

            Divider()
            statusBar
        }
        .frame(minWidth: 980, minHeight: 680)
    }

    private var topToolbar: some View {
        HStack(spacing: 12) {
            Button {
                appState.startCapture()
            } label: {
                Label("Capture", systemImage: "camera.viewfinder")
            }

            Divider()
                .frame(height: 20)

            Button {
                appState.copyImage()
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }
            .disabled(appState.currentImage == nil)

            Button {
                appState.saveImage()
            } label: {
                Label("Save", systemImage: "square.and.arrow.down")
            }
            .disabled(appState.currentImage == nil)

            Button {
                appState.shareImage()
            } label: {
                Label("Share", systemImage: "square.and.arrow.up")
            }
            .disabled(appState.currentImage == nil)

            Button {
                appState.undo()
            } label: {
                Image(systemName: "arrow.uturn.backward")
            }
            .help("Undo")
            .keyboardShortcut("z", modifiers: [.command])

            Button {
                appState.redo()
            } label: {
                Image(systemName: "arrow.uturn.forward")
            }
            .help("Redo")
            .keyboardShortcut("z", modifiers: [.command, .shift])

            Button(role: .destructive) {
                appState.clearAllAnnotations()
            } label: {
                Label("Clear All", systemImage: "trash")
            }
            .disabled(appState.annotations.isEmpty)

            Divider()
                .frame(height: 20)

            Button {
                appState.zoomOut()
            } label: {
                Image(systemName: "minus.magnifyingglass")
            }
            .help("Zoom Out")
            .disabled(appState.currentImage == nil)

            Button {
                appState.zoomToActualSize()
            } label: {
                Text("100%")
            }
            .help("Actual Size")
            .disabled(appState.currentImage == nil)

            Button {
                appState.zoomIn()
            } label: {
                Image(systemName: "plus.magnifyingglass")
            }
            .help("Zoom In")
            .disabled(appState.currentImage == nil)

            Button {
                appState.zoomToFit()
            } label: {
                Label("Fit", systemImage: "arrow.up.left.and.arrow.down.right")
            }
            .disabled(appState.currentImage == nil)

            Spacer()
        }
        .buttonStyle(.bordered)
        .padding(10)
    }

    private var statusBar: some View {
        HStack {
            Text(appState.statusMessage)
                .foregroundStyle(.secondary)

            Spacer()

            Text("Layer: \(appState.activeLayer.title)")
                .foregroundStyle(.secondary)

            Divider()
                .frame(height: 12)

            Text(appState.isFitToWindow ? "Fit" : "\(Int(appState.zoomScale * 100))%")
                .foregroundStyle(.secondary)

            if let image = appState.currentImage {
                Divider()
                    .frame(height: 12)

                Text("\(Int(image.size.width)) × \(Int(image.size.height)) px")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.caption)
        .padding(.horizontal, 12)
        .frame(height: 28)
    }
}

private struct ToolSidebar: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Tools")
                .font(.headline)
                .padding(.horizontal, 12)
                .padding(.top, 12)

            ScrollView {
                VStack(spacing: 4) {
                    ForEach(MSToolType.allCases) { tool in
                        Button {
                            appState.selectedTool = tool
                            appState.cancelAnnotation()
                            appState.resetAngleCreation()
                            appState.statusMessage = "Selected \(tool.title)"
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: tool.systemImage)
                                    .frame(width: 20)

                                Text(tool.title)

                                Spacer()
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .background(
                            appState.selectedTool == tool
                                ? Color.accentColor.opacity(0.16)
                                : Color.clear
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                    }
                }
                .padding(.horizontal, 8)
            }

            Spacer()
        }
        .background(.thinMaterial)
    }
}

private enum AnnotationEndpoint {
    case start
    case end
    case third
}

private struct EditorCanvas: View {
    @Environment(AppState.self) private var appState

    @State private var lastDragPoint: CGPoint?
    @State private var draggedEndpoint: AnnotationEndpoint?
    @FocusState private var isCanvasFocused: Bool

    var body: some View {
        Group {
            if let image = appState.currentImage {
                GeometryReader { geometry in
                    ScrollView([.horizontal, .vertical]) {
                        let fittedScale = min(
                            max(0.01, (geometry.size.width - 48) / max(image.size.width, 1)),
                            max(0.01, (geometry.size.height - 48) / max(image.size.height, 1))
                        )

                        let effectiveScale = appState.isFitToWindow
                            ? fittedScale
                            : appState.zoomScale

                        ZStack {
                            Image(nsImage: image)
                                .resizable()
                                .interpolation(.high)
                                .frame(
                                    width: image.size.width * effectiveScale,
                                    height: image.size.height * effectiveScale
                                )

                            if appState.isGuideLayerVisible {
                                Color.clear
                            }

                            if appState.isMeasurementLayerVisible {
                                AnnotationOverlay(
                                    annotations: appState.annotations.filter {
                                        $0.type == .measurement || $0.type == .calibration || $0.type == .angle
                                    },
                                    inProgress: measurementPreview,
                                    selectedAnnotationID: appState.selectedAnnotationID,
                                    scale: effectiveScale,
                                    calibration: appState.calibration,
                                    outputUnit: appState.outputMeasurementUnit
                                )
                            }

                            if appState.isAnnotationLayerVisible {
                                AnnotationOverlay(
                                    annotations: appState.annotations.filter {
                                        $0.type == .arrow || $0.type == .line || $0.type == .rectangle || $0.type == .ellipse
                                    },
                                    inProgress: annotationPreview,
                                    selectedAnnotationID: appState.selectedAnnotationID,
                                    scale: effectiveScale,
                                    calibration: appState.calibration,
                                    outputUnit: appState.outputMeasurementUnit
                                )
                            }
                        }
                        .frame(
                            width: image.size.width * effectiveScale,
                            height: image.size.height * effectiveScale
                        )
                        .contentShape(Rectangle())
                        .focusable()
                        .focused($isCanvasFocused)
                        .onDeleteCommand {
                            appState.deleteSelectedAnnotation()
                        }
                        .gesture(canvasGesture(scale: effectiveScale, imageSize: image.size))
                        .onTapGesture {
                            isCanvasFocused = true
                        }
                        .padding(24)
                        .frame(
                            minWidth: geometry.size.width,
                            minHeight: geometry.size.height,
                            alignment: .center
                        )
                    }
                    .simultaneousGesture(
                        MagnifyGesture()
                            .onChanged { value in
                                appState.isFitToWindow = false
                                appState.zoomScale = min(
                                    max(appState.zoomScale * value.magnification, 0.1),
                                    8
                                )
                            }
                    )
                }
            } else {
                ContentUnavailableView(
                    "No Capture",
                    systemImage: "camera.viewfinder",
                    description: Text("Click Capture or press ⌘⌥⇧4 to take a screenshot.")
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var annotationPreview: MSAnnotation? {
        guard let annotation = appState.inProgressAnnotation else { return nil }
        switch annotation.type {
        case .arrow, .line, .rectangle, .ellipse:
            return annotation
        default:
            return nil
        }
    }

    private var measurementPreview: MSAnnotation? {
        guard let annotation = appState.inProgressAnnotation else { return nil }
        switch annotation.type {
        case .measurement, .calibration, .angle:
            return annotation
        default:
            return nil
        }
    }

    private func canvasGesture(scale: CGFloat, imageSize: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                isCanvasFocused = true
                let imagePoint = clampedImagePoint(value.location, scale: scale, imageSize: imageSize)

                if appState.selectedTool == .colourPicker {
                    return
                }

                if appState.selectedTool == .select {
                    if lastDragPoint == nil {
                        if let endpoint = endpointHitTest(imagePoint, scale: scale) {
                            draggedEndpoint = endpoint
                            lastDragPoint = imagePoint
                            return
                        }

                        appState.selectAnnotation(id: hitTest(imagePoint))
                        lastDragPoint = imagePoint
                        return
                    }

                    if let draggedEndpoint {
                        switch draggedEndpoint {
                        case .start:
                            appState.updateSelectedAnnotationEndpoint(isStart: true, to: imagePoint)
                        case .end:
                            appState.updateSelectedAnnotationEndpoint(isStart: false, to: imagePoint)
                        case .third:
                            appState.updateSelectedAngleThirdPoint(to: imagePoint)
                        }
                        self.lastDragPoint = imagePoint
                        return
                    }

                    guard appState.selectedAnnotationID != nil,
                          let lastDragPoint else { return }

                    let delta = CGSize(
                        width: imagePoint.x - lastDragPoint.x,
                        height: imagePoint.y - lastDragPoint.y
                    )
                    appState.moveSelectedAnnotation(by: delta)
                    self.lastDragPoint = imagePoint
                    return
                }

                guard let annotationType = appState.annotationType(for: appState.selectedTool) else {
                    return
                }

                if appState.inProgressAnnotation == nil {
                    appState.beginAnnotation(type: annotationType, at: imagePoint)
                }

                appState.updateAnnotation(to: imagePoint)
            }
            .onEnded { value in
                defer {
                    lastDragPoint = nil
                    draggedEndpoint = nil
                }

                if appState.selectedTool == .colourPicker {
                    let imagePoint = clampedImagePoint(
                        value.location,
                        scale: scale,
                        imageSize: imageSize
                    )
                    sampleColour(at: imagePoint)
                    return
                }

                if appState.selectedTool == .select {
                    if draggedEndpoint != nil {
                        appState.finishEditingSelectedAnnotationEndpoint()
                    } else {
                        appState.finishMovingSelectedAnnotation()
                    }
                    return
                }

                guard appState.canDrawWithSelectedTool() else { return }
                let imagePoint = clampedImagePoint(value.location, scale: scale, imageSize: imageSize)
                appState.updateAnnotation(to: imagePoint)
                appState.finishAnnotation()
            }
    }

    private func endpointHitTest(_ point: CGPoint, scale: CGFloat) -> AnnotationEndpoint? {
        guard let annotation = appState.selectedAnnotation else { return nil }
        let tolerance = max(8, 10 / max(scale, 0.01))

        if hypot(point.x - annotation.start.x, point.y - annotation.start.y) <= tolerance {
            return .start
        }

        if hypot(point.x - annotation.end.x, point.y - annotation.end.y) <= tolerance {
            return .end
        }

        if let thirdPoint = annotation.thirdPoint,
           hypot(point.x - thirdPoint.x, point.y - thirdPoint.y) <= tolerance {
            return .third
        }

        return nil
    }

    private func clampedImagePoint(_ point: CGPoint, scale: CGFloat, imageSize: CGSize) -> CGPoint {
        CGPoint(
            x: min(max(point.x / scale, 0), imageSize.width),
            y: min(max(point.y / scale, 0), imageSize.height)
        )
    }

    private func hitTest(_ point: CGPoint) -> UUID? {
        for annotation in appState.annotations.reversed() {
            switch annotation.type {
            case .rectangle, .ellipse:
                if annotation.normalizedRect.insetBy(dx: -8, dy: -8).contains(point) {
                    return annotation.id
                }

            case .arrow, .line, .measurement, .calibration:
                if distanceFromPoint(point, toSegmentFrom: annotation.start, to: annotation.end) <= 8 {
                    return annotation.id
                }

            case .angle:
                let baselineHit = distanceFromPoint(
                    point,
                    toSegmentFrom: annotation.start,
                    to: annotation.end
                ) <= 8

                let measuredHit: Bool
                if let thirdPoint = annotation.thirdPoint {
                    measuredHit = distanceFromPoint(
                        point,
                        toSegmentFrom: annotation.end,
                        to: thirdPoint
                    ) <= 8
                } else {
                    measuredHit = false
                }

                if baselineHit || measuredHit {
                    return annotation.id
                }

            case .text, .blur:
                if annotation.normalizedRect.insetBy(dx: -8, dy: -8).contains(point) {
                    return annotation.id
                }
            }
        }

        return nil
    }

    private func sampleColour(at point: CGPoint) {
        guard let image = appState.currentImage,
              let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else {
            return
        }

        let x = min(max(Int(point.x.rounded()), 0), bitmap.pixelsWide - 1)
        let yFromTop = min(max(Int(point.y.rounded()), 0), bitmap.pixelsHigh - 1)
        let y = bitmap.pixelsHigh - 1 - yFromTop

        guard let colour = bitmap.colorAt(x: x, y: y) else { return }
        appState.updateSampledColor(colour)
    }

    private func distanceFromPoint(_ point: CGPoint, toSegmentFrom start: CGPoint, to end: CGPoint) -> CGFloat {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let lengthSquared = dx * dx + dy * dy

        guard lengthSquared > 0 else {
            return hypot(point.x - start.x, point.y - start.y)
        }

        let t = min(
            1,
            max(0, ((point.x - start.x) * dx + (point.y - start.y) * dy) / lengthSquared)
        )
        let projection = CGPoint(x: start.x + t * dx, y: start.y + t * dy)
        return hypot(point.x - projection.x, point.y - projection.y)
    }
}

private struct AnnotationOverlay: View {
    let annotations: [MSAnnotation]
    let inProgress: MSAnnotation?
    let selectedAnnotationID: UUID?
    let scale: CGFloat
    let calibration: MSCalibration?
    let outputUnit: MSMeasurementUnit

    var body: some View {
        Canvas { context, _ in
            for annotation in annotations {
                draw(
                    annotation,
                    selected: annotation.id == selectedAnnotationID,
                    in: &context
                )
            }

            if let inProgress {
                draw(inProgress, selected: false, in: &context)
            }
        }
        .allowsHitTesting(false)
    }

    private func draw(
        _ annotation: MSAnnotation,
        selected: Bool,
        in context: inout GraphicsContext
    ) {
        let start = scaled(annotation.start)
        let end = scaled(annotation.end)
        let color = annotation.stroke.color.swiftUIColor.opacity(annotation.stroke.opacity)
        let lineWidth = max(1, annotation.stroke.lineWidth * scale)

        switch annotation.type {
        case .line, .measurement, .calibration:
            var path = Path()
            path.move(to: start)
            path.addLine(to: end)
            context.stroke(path, with: .color(color), lineWidth: lineWidth)

            if annotation.type == .measurement || annotation.type == .calibration {
                drawMeasurementLabel(annotation, in: &context)
            }

        case .angle:
            drawAngle(
                annotation,
                color: color,
                lineWidth: lineWidth,
                in: &context
            )

        case .arrow:
            drawArrow(from: start, to: end, color: color, lineWidth: lineWidth, in: &context)

        case .rectangle:
            context.stroke(
                Path(annotation.normalizedRect.applying(CGAffineTransform(scaleX: scale, y: scale))),
                with: .color(color),
                lineWidth: lineWidth
            )

        case .ellipse:
            let rect = annotation.normalizedRect.applying(CGAffineTransform(scaleX: scale, y: scale))
            context.stroke(Path(ellipseIn: rect), with: .color(color), lineWidth: lineWidth)

        case .text, .blur:
            break
        }

        if selected {
            drawSelectionHandles(annotation, in: &context)
        }
    }

    private func drawAngle(
        _ annotation: MSAnnotation,
        color: Color,
        lineWidth: CGFloat,
        in context: inout GraphicsContext
    ) {
        let start = scaled(annotation.start)
        let vertex = scaled(annotation.end)

        var baseline = Path()
        baseline.move(to: start)
        baseline.addLine(to: vertex)
        context.stroke(baseline, with: .color(color), lineWidth: lineWidth)

        if let thirdPoint = annotation.thirdPoint {
            let measuredEnd = scaled(thirdPoint)
            var measuredArm = Path()
            measuredArm.move(to: vertex)
            measuredArm.addLine(to: measuredEnd)
            context.stroke(measuredArm, with: .color(color), lineWidth: lineWidth)
        }

        if let referencePoint = annotation.perpendicularReferencePoint {
            var reference = Path()
            reference.move(to: vertex)
            reference.addLine(to: scaled(referencePoint))
            context.stroke(
                reference,
                with: .color(color.opacity(0.65)),
                style: StrokeStyle(
                    lineWidth: max(1, lineWidth * 0.75),
                    dash: [6 * scale, 4 * scale]
                )
            )
        }

        if annotation.thirdPoint != nil {
            let label = Text(
                annotation.displayValue(
                    calibration: calibration,
                    outputUnit: outputUnit
                )
            )
            .font(.system(size: max(11, 12 * scale), weight: .semibold, design: .rounded))
            .foregroundColor(.white)

            context.draw(
                label,
                at: CGPoint(x: vertex.x + 12, y: vertex.y - 18),
                anchor: .leading
            )
        }
    }

    private func drawArrow(
        from start: CGPoint,
        to end: CGPoint,
        color: Color,
        lineWidth: CGFloat,
        in context: inout GraphicsContext
    ) {
        var path = Path()
        path.move(to: start)
        path.addLine(to: end)

        let angle = atan2(end.y - start.y, end.x - start.x)
        let headLength = max(10, 12 * scale)
        let first = CGPoint(
            x: end.x - cos(angle - .pi / 6) * headLength,
            y: end.y - sin(angle - .pi / 6) * headLength
        )
        let second = CGPoint(
            x: end.x - cos(angle + .pi / 6) * headLength,
            y: end.y - sin(angle + .pi / 6) * headLength
        )

        path.move(to: first)
        path.addLine(to: end)
        path.addLine(to: second)
        context.stroke(path, with: .color(color), lineWidth: lineWidth)
    }

    private func drawMeasurementLabel(_ annotation: MSAnnotation, in context: inout GraphicsContext) {
        let midpoint = CGPoint(
            x: (annotation.start.x + annotation.end.x) * 0.5 * scale,
            y: (annotation.start.y + annotation.end.y) * 0.5 * scale
        )

        let labelText = annotation.displayValue(
            calibration: calibration,
            outputUnit: outputUnit
        )

        let label = Text(labelText)
            .font(.system(size: max(11, 12 * scale), weight: .semibold, design: .rounded))
            .foregroundColor(.white)

        context.draw(label, at: CGPoint(x: midpoint.x, y: midpoint.y - 12))
    }

    private func drawSelectionHandles(_ annotation: MSAnnotation, in context: inout GraphicsContext) {
        var points = [scaled(annotation.start), scaled(annotation.end)]

        if let thirdPoint = annotation.thirdPoint {
            points.append(scaled(thirdPoint))
        }

        for point in points {
            let rect = CGRect(x: point.x - 5, y: point.y - 5, width: 10, height: 10)
            context.fill(Path(ellipseIn: rect), with: .color(.white))
            context.stroke(Path(ellipseIn: rect), with: .color(.accentColor), lineWidth: 2)
        }
    }

    private func scaled(_ point: CGPoint) -> CGPoint {
        CGPoint(x: point.x * scale, y: point.y * scale)
    }
}

private extension Path {
    init(_ rect: CGRect) {
        self.init()
        addRect(rect)
    }
}

private struct InspectorSidebar: View {
    @Environment(AppState.self) private var appState

    private var shouldShowMeasurementPanel: Bool {
        appState.selectedTool == .calibrate
            || appState.selectedTool == .measure
            || appState.selectedAnnotation?.type == .calibration
            || appState.selectedAnnotation?.type == .measurement
    }

    private var shouldShowCalibrationControls: Bool {
        appState.selectedTool == .calibrate
            || appState.selectedAnnotation?.type == .calibration
    }

    private var shouldShowColourPickerPanel: Bool {
        appState.selectedTool == .colourPicker
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Inspector")
                    .font(.headline)

                activeToolSection
                instructionsSection
                appearanceSection

                if shouldShowColourPickerPanel {
                    colourPickerSection
                }

                if shouldShowMeasurementPanel {
                    measurementSection
                }

                layersSection
            }
            .padding(12)
        }
        .background(.thinMaterial)
    }

    private var colourPickerSection: some View {
        GroupBox("Sampled Colour") {
            VStack(alignment: .leading, spacing: 10) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(appState.sampledColor)
                    .frame(height: 42)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(.secondary.opacity(0.4))
                    )

                HStack {
                    Text("HEX")
                    Spacer()
                    Text(appState.sampledHex)
                        .font(.system(.body, design: .monospaced))
                }

                HStack {
                    Text("RGB")
                    Spacer()
                    Text(appState.sampledRGB)
                        .font(.system(.body, design: .monospaced))
                }

                Text("Click anywhere on the image to copy the HEX value.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var activeToolSection: some View {
        GroupBox("Active Tool") {
            HStack {
                Image(systemName: appState.selectedTool.systemImage)
                Text(appState.selectedTool.title)
                Spacer()
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var instructionsSection: some View {
        GroupBox("How to Use") {
            Text(toolInstructions)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var appearanceSection: some View {
        GroupBox("Appearance") {
            VStack(alignment: .leading, spacing: 12) {
                ColorPicker(
                    "Colour",
                    selection: Binding(
                        get: { appState.annotationColor },
                        set: { newColor in
                            appState.annotationColor = newColor
                            appState.applyCurrentStyleToSelection()
                        }
                    )
                )

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Line Width")
                        Spacer()
                        Text("\(appState.annotationLineWidth, specifier: "%.1f") pt")
                            .foregroundStyle(.secondary)
                    }

                    Slider(
                        value: Binding(
                            get: { Double(appState.annotationLineWidth) },
                            set: { newValue in
                                appState.annotationLineWidth = CGFloat(newValue)
                                appState.applyCurrentStyleToSelection()
                            }
                        ),
                        in: 1...12,
                        step: 0.5
                    )
                }

                if appState.selectedAnnotationID != nil {
                    Button("Apply to Selected") {
                        appState.applyCurrentStyleToSelection()
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var measurementSection: some View {
        GroupBox("Measurement") {
            VStack(alignment: .leading, spacing: 10) {
                outputUnitPicker

                if shouldShowCalibrationControls {
                    Divider()
                    calibrationControls
                }

                calibrationStatus
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var outputUnitPicker: some View {
        Picker(
            "Output Unit",
            selection: Binding(
                get: { appState.outputMeasurementUnit },
                set: { appState.outputMeasurementUnit = $0 }
            )
        ) {
            ForEach(MSMeasurementUnit.allCases) { unit in
                Text(unit.title).tag(unit)
            }
        }
    }

    private var calibrationControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Known Length")
                Spacer()

                TextField(
                    "Length",
                    value: Binding(
                        get: { appState.calibrationKnownLength },
                        set: { appState.calibrationKnownLength = $0 }
                    ),
                    format: .number
                )
                .frame(width: 80)
            }

            Picker(
                "Calibration Unit",
                selection: Binding(
                    get: { appState.calibrationUnit },
                    set: { appState.calibrationUnit = $0 }
                )
            ) {
                ForEach(MSMeasurementUnit.allCases.filter { $0 != .pixels }) { unit in
                    Text(unit.title).tag(unit)
                }
            }

            HStack {
                Button("Apply Calibration") {
                    appState.updateSelectedCalibrationValue()
                }
                .disabled(appState.selectedAnnotation?.type != .calibration)

                Button("Clear") {
                    appState.clearCalibration()
                }
                .disabled(appState.calibration == nil)
            }
        }
    }

    @ViewBuilder
    private var calibrationStatus: some View {
        if let calibration = appState.calibration,
           let millimetresPerPixel = calibration.millimetresPerPixel {
            Text(String(format: "Scale: %.5f mm/px", millimetresPerPixel))
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            Text("Draw a calibration line, select it, then enter the known distance.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var layersSection: some View {
        GroupBox("Layers") {
            VStack(spacing: 8) {
                ForEach(MSCanvasLayer.allCases) { layer in
                    layerRow(layer)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var toolInstructions: String {
        switch appState.selectedTool {
        case .select:
            return "Click an object to select it. Drag the object to move it, or drag either endpoint handle to reshape it."
        case .measure:
            return "Drag from one point to another. The pixel distance updates live while you draw."
        case .calibrate:
            return "Draw over a known distance, then enter its real-world length and unit."
        case .angle:
            return "Drag the baseline from its first point to the vertex. Release, then drag from the vertex to define the measured arm. The 90° reference and deviation update live."
        case .arrow:
            return "Drag from the arrow tail to its tip."
        case .rectangle:
            return "Drag diagonally to draw a rectangle."
        case .ellipse:
            return "Drag diagonally to draw an ellipse."
        case .text:
            return "Click the image where you want to place text."
        case .blur:
            return "Drag across the area you want to obscure."
        case .colourPicker:
            return "Move over the image and click to copy the sampled colour value."
        }
    }

    private func layerRow(_ layer: MSCanvasLayer) -> some View {
        HStack(spacing: 8) {
            Button {
                appState.setLayer(layer, visible: !appState.isLayerVisible(layer))
            } label: {
                Image(systemName: appState.isLayerVisible(layer) ? "eye" : "eye.slash")
                    .frame(width: 18)
            }
            .buttonStyle(.plain)
            .help(appState.isLayerVisible(layer) ? "Hide \(layer.title)" : "Show \(layer.title)")

            Button {
                appState.selectLayer(layer)
            } label: {
                HStack {
                    Image(systemName: layer.systemImage)
                    Text(layer.title)
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if appState.activeLayer == layer {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.tint)
            }
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 4)
        .background(
            appState.activeLayer == layer
                ? Color.accentColor.opacity(0.12)
                : Color.clear
        )
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

#Preview {
    EditorView()
        .environment(AppState())
}
