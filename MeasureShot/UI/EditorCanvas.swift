import SwiftUI
import CoreImage

enum AnnotationEndpoint {
    case start
    case end
    case third
    case fourth
}

enum CropDragTarget {
    case new
    case topLeft
    case top
    case topRight
    case left
    case right
    case bottomLeft
    case bottom
    case bottomRight
}

struct CropOverlay: View {
    let rect: CGRect
    let imageSize: CGSize
    let scale: CGFloat

    var body: some View {
        let scaledRect = CGRect(
            x: rect.minX * scale,
            y: rect.minY * scale,
            width: rect.width * scale,
            height: rect.height * scale
        )
        let scaledSize = CGSize(
            width: imageSize.width * scale,
            height: imageSize.height * scale
        )

        ZStack(alignment: .topLeading) {
            Path { path in
                path.addRect(CGRect(origin: .zero, size: scaledSize))
                path.addRect(scaledRect)
            }
            .fill(.black.opacity(0.38), style: FillStyle(eoFill: true))

            Rectangle()
                .stroke(.white, style: StrokeStyle(lineWidth: 2, dash: [7, 4]))
                .background(Rectangle().stroke(.black.opacity(0.55), lineWidth: 1))
                .frame(width: scaledRect.width, height: scaledRect.height)
                .position(x: scaledRect.midX, y: scaledRect.midY)

            ForEach(Array(handlePoints(for: scaledRect).enumerated()), id: \.offset) { _, point in
                Circle()
                    .fill(.white)
                    .overlay(Circle().stroke(.black.opacity(0.7), lineWidth: 1))
                    .frame(width: 10, height: 10)
                    .position(point)
            }
        }
        .frame(width: scaledSize.width, height: scaledSize.height)
        .allowsHitTesting(false)
    }

    private func handlePoints(for rect: CGRect) -> [CGPoint] {
        [
            CGPoint(x: rect.minX, y: rect.minY),
            CGPoint(x: rect.midX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.minY),
            CGPoint(x: rect.minX, y: rect.midY),
            CGPoint(x: rect.maxX, y: rect.midY),
            CGPoint(x: rect.minX, y: rect.maxY),
            CGPoint(x: rect.midX, y: rect.maxY),
            CGPoint(x: rect.maxX, y: rect.maxY)
        ]
    }
}

struct EditorCanvas: View {
    @Environment(AppState.self) private var appState

    @State private var lastDragPoint: CGPoint?
    @State private var draggedEndpoint: AnnotationEndpoint?
    @State private var colourPickerLocation: CGPoint?
    @State private var colourPickerPreview: NSColor?
    @State private var blurBrushLocation: CGPoint?
    @State private var cropDragTarget: CropDragTarget?
    @State private var cropDragStartPoint: CGPoint?
    @State private var cropDragStartRect: CGRect?
    @FocusState private var isCanvasFocused: Bool

    var body: some View {
        Group {
            if let imageDocument = appState.imageDocument {
                let image = ImageRenderer.render(document: imageDocument)

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

                            if appState.selectedTool == .crop,
                               let cropSelectionRect = appState.cropSelectionRect {
                                CropOverlay(
                                    rect: cropSelectionRect,
                                    imageSize: image.size,
                                    scale: effectiveScale
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

                if appState.selectedTool == .crop {
                    updateCropDrag(to: imagePoint, imageSize: imageSize, scale: scale)
                    return
                }

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
                    cropDragTarget = nil
                    cropDragStartPoint = nil
                    cropDragStartRect = nil
                }

                if appState.selectedTool == .crop {
                    appState.applyCropSelection(imageSize: imageSize)
                    return
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

    private func updateCropDrag(to point: CGPoint, imageSize: CGSize, scale: CGFloat) {
        let currentRect = appState.cropSelectionRect ?? CGRect(origin: .zero, size: imageSize)

        if cropDragTarget == nil {
            cropDragTarget = cropHitTarget(at: point, in: currentRect, scale: scale)
            cropDragStartPoint = point
            cropDragStartRect = currentRect
        }

        guard let cropDragTarget,
              let cropDragStartPoint,
              let cropDragStartRect else {
            return
        }

        let nextRect: CGRect
        if cropDragTarget == .new {
            nextRect = CGRect(
                x: cropDragStartPoint.x,
                y: cropDragStartPoint.y,
                width: point.x - cropDragStartPoint.x,
                height: point.y - cropDragStartPoint.y
            )
        } else {
            nextRect = resizedCropRect(
                cropDragStartRect,
                target: cropDragTarget,
                to: point
            )
        }

        appState.updateCropSelection(nextRect, imageSize: imageSize)
    }

    private func cropHitTarget(at point: CGPoint, in rect: CGRect, scale: CGFloat) -> CropDragTarget {
        let tolerance = max(8, 10 / max(scale, 0.01))
        let expanded = rect.insetBy(dx: -tolerance, dy: -tolerance)
        guard expanded.contains(point) else { return .new }

        let nearLeft = abs(point.x - rect.minX) <= tolerance
        let nearRight = abs(point.x - rect.maxX) <= tolerance
        let nearTop = abs(point.y - rect.minY) <= tolerance
        let nearBottom = abs(point.y - rect.maxY) <= tolerance

        switch (nearLeft, nearRight, nearTop, nearBottom) {
        case (true, false, true, false): return .topLeft
        case (false, true, true, false): return .topRight
        case (true, false, false, true): return .bottomLeft
        case (false, true, false, true): return .bottomRight
        case (true, false, false, false): return .left
        case (false, true, false, false): return .right
        case (false, false, true, false): return .top
        case (false, false, false, true): return .bottom
        default: return .new
        }
    }

    private func resizedCropRect(
        _ rect: CGRect,
        target: CropDragTarget,
        to point: CGPoint
    ) -> CGRect {
        var minX = rect.minX
        var maxX = rect.maxX
        var minY = rect.minY
        var maxY = rect.maxY

        switch target {
        case .new:
            break
        case .topLeft:
            minX = point.x
            minY = point.y
        case .top:
            minY = point.y
        case .topRight:
            maxX = point.x
            minY = point.y
        case .left:
            minX = point.x
        case .right:
            maxX = point.x
        case .bottomLeft:
            minX = point.x
            maxY = point.y
        case .bottom:
            maxY = point.y
        case .bottomRight:
            maxX = point.x
            maxY = point.y
        }

        return CGRect(
            x: minX,
            y: minY,
            width: maxX - minX,
            height: maxY - minY
        )
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
        guard let imageDocument = appState.imageDocument else {
            return nil
        }

        let image = ImageRenderer.render(document: imageDocument)

        guard let tiff = image.tiffRepresentation,
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
