//
//  EditorView.swift
//  MeasureShot
//
//  Created by Andrew Jones on 7/13/26.
//

import SwiftUI
import CoreImage

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
    case fourth
}

private struct EditorCanvas: View {
    @Environment(AppState.self) private var appState

    @State private var lastDragPoint: CGPoint?
    @State private var draggedEndpoint: AnnotationEndpoint?
    @State private var colourPickerLocation: CGPoint?
    @State private var colourPickerPreview: NSColor?
    @State private var blurBrushLocation: CGPoint?
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

                            if appState.isAnnotationLayerVisible {
                                BlurOverlay(
                                    image: image,
                                    annotations: appState.annotations.filter { $0.type == .blur },
                                    inProgress: blurPreview,
                                    scale: effectiveScale,
                                    showMask: appState.showBlurMask
                                )
                            }

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
                                        $0.type == .arrow
                                            || $0.type == .line
                                            || $0.type == .rectangle
                                            || $0.type == .ellipse
                                            || $0.type == .text
                                            || $0.type == .blur
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
                        .onContinuousHover { phase in
                            if appState.selectedTool == .blur {
                                switch phase {
                                case .active(let location):
                                    blurBrushLocation = location
                                case .ended:
                                    blurBrushLocation = nil
                                }
                                colourPickerLocation = nil
                                colourPickerPreview = nil
                                return
                            }

                            blurBrushLocation = nil

                            guard appState.selectedTool == .colourPicker else {
                                colourPickerLocation = nil
                                colourPickerPreview = nil
                                return
                            }

                            switch phase {
                            case .active(let location):
                                colourPickerLocation = location
                                colourPickerPreview = colourAtCanvasPoint(
                                    location,
                                    scale: effectiveScale,
                                    imageSize: image.size
                                )
                            case .ended:
                                colourPickerLocation = nil
                                colourPickerPreview = nil
                            }
                        }
                        .overlay {
                            if appState.selectedTool == .colourPicker,
                               let location = colourPickerLocation,
                               let preview = colourPickerPreview {
                                ZStack {
                                    Circle()
                                        .fill(Color(preview).opacity(0.35))

                                    Circle()
                                        .stroke(.white, lineWidth: 2)

                                    Circle()
                                        .stroke(.black.opacity(0.65), lineWidth: 1)
                                        .padding(2)

                                    Image(systemName: "plus")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(.white)
                                        .shadow(radius: 1)
                                }
                                .frame(width: 24, height: 24)
                                .position(location)
                                .allowsHitTesting(false)
                            }

                            if appState.selectedTool == .blur,
                               let location = blurBrushLocation {
                                Circle()
                                    .stroke(.white, lineWidth: 2)
                                    .background(
                                        Circle()
                                            .stroke(.black.opacity(0.7), lineWidth: 1)
                                            .padding(2)
                                    )
                                    .frame(
                                        width: appState.defaultBlurBrushSize * effectiveScale,
                                        height: appState.defaultBlurBrushSize * effectiveScale
                                    )
                                    .position(location)
                                    .allowsHitTesting(false)
                            }
                        }
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
        case .arrow, .line, .rectangle, .ellipse, .blur:
            return annotation
        default:
            return nil
        }
    }

    private var blurPreview: MSAnnotation? {
        guard let annotation = appState.inProgressAnnotation,
              annotation.type == .blur else {
            return nil
        }
        return annotation
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

                if appState.selectedTool == .blur {
                    blurBrushLocation = value.location
                }

                if appState.selectedTool == .colourPicker {
                    return
                }

                if appState.selectedTool == .text {
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
                        case .fourth:
                            appState.updateSelectedAngleFourthPoint(to: imagePoint)
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
                    if appState.selectedTool == .blur {
                        blurBrushLocation = value.location
                    }
                }

                if appState.selectedTool == .colourPicker {
                    sampleColour(
                        atCanvasPoint: value.location,
                        scale: scale,
                        imageSize: imageSize
                    )
                    return
                }

                if appState.selectedTool == .text {
                    let imagePoint = clampedImagePoint(
                        value.location,
                        scale: scale,
                        imageSize: imageSize
                    )
                    appState.beginAnnotation(type: .text, at: imagePoint)
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

        if let fourthPoint = annotation.fourthPoint,
           hypot(point.x - fourthPoint.x, point.y - fourthPoint.y) <= tolerance {
            return .fourth
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

                let perpendicularHit: Bool
                if let thirdPoint = annotation.thirdPoint {
                    perpendicularHit = distanceFromPoint(
                        point,
                        toSegmentFrom: annotation.end,
                        to: thirdPoint
                    ) <= 8
                } else {
                    perpendicularHit = false
                }

                let measuredHit: Bool
                if let thirdPoint = annotation.thirdPoint,
                   let fourthPoint = annotation.fourthPoint {
                    measuredHit = distanceFromPoint(
                        point,
                        toSegmentFrom: thirdPoint,
                        to: fourthPoint
                    ) <= 8
                } else {
                    measuredHit = false
                }

                if baselineHit || perpendicularHit || measuredHit {
                    return annotation.id
                }

            case .text:
                if textBounds(for: annotation).insetBy(dx: -8, dy: -8).contains(point) {
                    return annotation.id
                }

            case .blur:
                let tolerance = CGFloat(annotation.blurBrushSize / 2 + 8)
                if annotation.points.contains(where: {
                    hypot(point.x - $0.x, point.y - $0.y) <= tolerance
                }) {
                    return annotation.id
                }
            }
        }

        return nil
    }

    private func textBounds(for annotation: MSAnnotation) -> CGRect {
        let width = max(
            60,
            CGFloat(annotation.text.count) * annotation.fontSize * 0.58
        )
        let height = max(24, annotation.fontSize * 1.4)

        return CGRect(
            x: annotation.start.x,
            y: annotation.start.y - height,
            width: width,
            height: height
        )
    }
    private func colourAtCanvasPoint(
        _ point: CGPoint,
        scale: CGFloat,
        imageSize: CGSize
    ) -> NSColor? {
        guard let image = appState.currentImage,
              let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else {
            return nil
        }

        let displayedWidth = max(imageSize.width * scale, 1)
        let displayedHeight = max(imageSize.height * scale, 1)

        let normalizedX = min(max(point.x / displayedWidth, 0), 1)
        let normalizedY = min(max(point.y / displayedHeight, 0), 1)

        let pixelX = min(
            max(Int(normalizedX * CGFloat(bitmap.pixelsWide)), 0),
            bitmap.pixelsWide - 1
        )
        let pixelYFromTop = min(
            max(Int(normalizedY * CGFloat(bitmap.pixelsHigh)), 0),
            bitmap.pixelsHigh - 1
        )
        let pixelY = bitmap.pixelsHigh - 1 - pixelYFromTop

        return bitmap.colorAt(x: pixelX, y: pixelY)
    }

    private func hexString(for colour: NSColor) -> String {
        let rgb = colour.usingColorSpace(.deviceRGB) ?? colour
        return String(
            format: "#%02X%02X%02X",
            Int(rgb.redComponent * 255),
            Int(rgb.greenComponent * 255),
            Int(rgb.blueComponent * 255)
        )
    }

    private func sampleColour(
        atCanvasPoint point: CGPoint,
        scale: CGFloat,
        imageSize: CGSize
    ) {
        guard let colour = colourAtCanvasPoint(
            point,
            scale: scale,
            imageSize: imageSize
        ) else {
            return
        }

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


private struct BlurOverlay: View {
    let image: NSImage
    let annotations: [MSAnnotation]
    let inProgress: MSAnnotation?
    let scale: CGFloat
    let showMask: Bool

    var body: some View {
        ZStack {
            ForEach(allBlurAnnotations) { annotation in
                blurStrokeView(annotation)
            }
        }
        .frame(
            width: image.size.width * scale,
            height: image.size.height * scale
        )
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func blurStrokeView(_ annotation: MSAnnotation) -> some View {
        let displayedWidth = image.size.width * scale
        let displayedHeight = image.size.height * scale

        if !annotation.points.isEmpty {
            ZStack {
                if let blurred = makeBlurredImage(radius: annotation.blurRadius) {
                    Image(nsImage: blurred)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: displayedWidth, height: displayedHeight)
                        .mask {
                            blurMask(for: annotation)
                        }
                }

                if showMask {
                    Color.red.opacity(0.35)
                        .frame(width: displayedWidth, height: displayedHeight)
                        .mask {
                            blurMask(for: annotation)
                        }
                }
            }
            .frame(width: displayedWidth, height: displayedHeight)
        }
    }

    @ViewBuilder
    private func blurMask(for annotation: MSAnnotation) -> some View {
        if annotation.points.isEmpty {
            Color.clear
        } else {
            Canvas { context, _ in
                let diameter = max(2, annotation.blurBrushSize * scale)
                let radius = diameter / 2
                let points = interpolatedBrushPoints(
                    annotation.points,
                    maximumSpacing: max(1, annotation.blurBrushSize * 0.15)
                )

                for point in points {
                    let centre = CGPoint(
                        x: point.x * scale,
                        y: point.y * scale
                    )
                    let rect = CGRect(
                        x: centre.x - radius,
                        y: centre.y - radius,
                        width: diameter,
                        height: diameter
                    )
                    context.fill(
                        Path(ellipseIn: rect),
                        with: .color(.white)
                    )
                }
            }
            .frame(
                width: image.size.width * scale,
                height: image.size.height * scale
            )
        }
    }

    private func makeBlurredImage(radius: Double) -> NSImage? {
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let cgInput = bitmap.cgImage,
              let filter = CIFilter(name: "CIGaussianBlur") else {
            return nil
        }

        let input = CIImage(cgImage: cgInput)
        filter.setValue(input, forKey: kCIInputImageKey)
        filter.setValue(max(8, radius * 1.5), forKey: kCIInputRadiusKey)

        guard let output = filter.outputImage?.cropped(to: input.extent) else {
            return nil
        }

        let ciContext = CIContext(options: nil)
        guard let cgOutput = ciContext.createCGImage(output, from: input.extent) else {
            return nil
        }

        return NSImage(cgImage: cgOutput, size: image.size)
    }

    private func interpolatedBrushPoints(
        _ points: [CGPoint],
        maximumSpacing: Double
    ) -> [CGPoint] {
        guard let first = points.first else { return [] }
        guard points.count > 1 else { return [first] }

        var result = [first]

        for (start, end) in zip(points, points.dropFirst()) {
            let distance = hypot(end.x - start.x, end.y - start.y)
            let steps = max(1, Int(ceil(distance / maximumSpacing)))

            for step in 1...steps {
                let progress = CGFloat(step) / CGFloat(steps)
                result.append(
                    CGPoint(
                        x: start.x + (end.x - start.x) * progress,
                        y: start.y + (end.y - start.y) * progress
                    )
                )
            }
        }

        return result
    }

    private var allBlurAnnotations: [MSAnnotation] {
        if let inProgress {
            return annotations + [inProgress]
        }
        return annotations
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

        case .text:
            let label = Text(annotation.text)
                .font(.system(size: max(8, annotation.fontSize * scale)))
                .foregroundColor(color)

            context.draw(
                label,
                at: scaled(annotation.start),
                anchor: .bottomLeading
            )

        case .blur:
            if selected {
                let diameter = annotation.blurBrushSize * scale
                let radius = diameter / 2

                for point in annotation.points {
                    let centre = scaled(point)
                    let rect = CGRect(
                        x: centre.x - radius,
                        y: centre.y - radius,
                        width: diameter,
                        height: diameter
                    )
                    context.stroke(
                        Path(ellipseIn: rect),
                        with: .color(.accentColor.opacity(0.7)),
                        lineWidth: 1
                    )
                }
            }
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
        let baselineStart = scaled(annotation.start)
        let baselineEnd = scaled(annotation.end)

        var baseline = Path()
        baseline.move(to: baselineStart)
        baseline.addLine(to: baselineEnd)
        context.stroke(baseline, with: .color(color), lineWidth: lineWidth)

        if let thirdPoint = annotation.thirdPoint {
            let perpendicularEnd = scaled(thirdPoint)
            var perpendicular = Path()
            perpendicular.move(to: baselineEnd)
            perpendicular.addLine(to: perpendicularEnd)
            context.stroke(
                perpendicular,
                with: .color(color.opacity(0.75)),
                style: StrokeStyle(
                    lineWidth: max(1, lineWidth * 0.8),
                    dash: [6 * scale, 4 * scale]
                )
            )
        }

        if let thirdPoint = annotation.thirdPoint,
           let fourthPoint = annotation.fourthPoint {
            let measuredStart = scaled(thirdPoint)
            let measuredEnd = scaled(fourthPoint)
            var measured = Path()
            measured.move(to: measuredStart)
            measured.addLine(to: measuredEnd)
            context.stroke(measured, with: .color(color), lineWidth: lineWidth)

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
                at: CGPoint(x: measuredStart.x + 12, y: measuredStart.y - 18),
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

        if let fourthPoint = annotation.fourthPoint {
            points.append(scaled(fourthPoint))
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

    private var shouldShowTextPanel: Bool {
        appState.selectedTool == .text
            || appState.selectedAnnotation?.type == .text
    }

    private var shouldShowBlurPanel: Bool {
        appState.selectedTool == .blur
            || appState.selectedAnnotation?.type == .blur
    }

    private var textSection: some View {
        GroupBox("Text") {
            VStack(alignment: .leading, spacing: 10) {
                TextField(
                    "Text",
                    text: Binding(
                        get: {
                            appState.selectedAnnotation?.type == .text
                                ? appState.selectedAnnotation?.text ?? appState.defaultText
                                : appState.defaultText
                        },
                        set: { newValue in
                            appState.defaultText = newValue
                            if appState.selectedAnnotation?.type == .text {
                                appState.updateSelectedText(newValue)
                            }
                        }
                    )
                )

                HStack {
                    Text("Font Size")
                    Spacer()
                    Text("\(Int(appState.selectedAnnotation?.type == .text ? appState.selectedAnnotation?.fontSize ?? appState.defaultFontSize : appState.defaultFontSize)) pt")
                        .foregroundStyle(.secondary)
                }

                Slider(
                    value: Binding(
                        get: {
                            Double(
                                appState.selectedAnnotation?.type == .text
                                    ? appState.selectedAnnotation?.fontSize ?? appState.defaultFontSize
                                    : appState.defaultFontSize
                            )
                        },
                        set: { newValue in
                            appState.defaultFontSize = CGFloat(newValue)
                            if appState.selectedAnnotation?.type == .text {
                                appState.updateSelectedFontSize(CGFloat(newValue))
                            }
                        }
                    ),
                    in: 8...72,
                    step: 1
                )

                Text("Click the image to place text, then edit it here.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var blurSection: some View {
        GroupBox("Blur") {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Strength")
                    Spacer()
                    Text("\(Int(appState.selectedAnnotation?.type == .blur ? appState.selectedAnnotation?.blurRadius ?? appState.defaultBlurRadius : appState.defaultBlurRadius))")
                        .foregroundStyle(.secondary)
                }

                Slider(
                    value: Binding(
                        get: {
                            appState.selectedAnnotation?.type == .blur
                                ? appState.selectedAnnotation?.blurRadius ?? appState.defaultBlurRadius
                                : appState.defaultBlurRadius
                        },
                        set: { newValue in
                            appState.defaultBlurRadius = newValue
                            if appState.selectedAnnotation?.type == .blur {
                                appState.updateSelectedBlurRadius(newValue)
                            }
                        }
                    ),
                    in: 4...80,
                    step: 1
                )

                HStack {
                    Text("Brush Size")
                    Spacer()
                    Text("\(Int(appState.selectedAnnotation?.type == .blur ? appState.selectedAnnotation?.blurBrushSize ?? appState.defaultBlurBrushSize : appState.defaultBlurBrushSize)) px")
                        .foregroundStyle(.secondary)
                }

                Slider(
                    value: Binding(
                        get: {
                            appState.selectedAnnotation?.type == .blur
                                ? appState.selectedAnnotation?.blurBrushSize ?? appState.defaultBlurBrushSize
                                : appState.defaultBlurBrushSize
                        },
                        set: { newValue in
                            appState.defaultBlurBrushSize = newValue
                            if appState.selectedAnnotation?.type == .blur {
                                appState.updateSelectedBlurBrushSize(newValue)
                            }
                        }
                    ),
                    in: 10...160,
                    step: 2
                )

                Toggle(
                    "Show Painted Mask",
                    isOn: Binding(
                        get: { appState.showBlurMask },
                        set: { appState.showBlurMask = $0 }
                    )
                )

                Text("Drag across the area to blur. Use Select to move or resize it later.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Inspector")
                    .font(.headline)

                activeToolSection
                instructionsSection
                appearanceSection

                if shouldShowTextPanel {
                    textSection
                }

                if shouldShowBlurPanel {
                    blurSection
                }

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
            return "Drag the baseline. MeasureShot creates a 90° arm automatically. Then drag a third line from the end of that arm; the displayed value is its signed angular difference from the original baseline."
        case .arrow:
            return "Drag from the arrow tail to its tip."
        case .rectangle:
            return "Drag diagonally to draw a rectangle."
        case .ellipse:
            return "Drag diagonally to draw an ellipse."
        case .text:
            return "Click the image where you want to place text."
        case .blur:
            return "Drag over the image to paint blur in real time. Adjust brush size and strength in the inspector."
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

