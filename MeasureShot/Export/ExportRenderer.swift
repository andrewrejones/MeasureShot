import AppKit
import CoreImage

@MainActor
enum ExportRenderer {
    static func render(
        image: NSImage,
        annotations: [MSAnnotation],
        calibration: MSCalibration?,
        outputUnit: MSMeasurementUnit,
        showAnnotations: Bool,
        showMeasurements: Bool
    ) -> NSImage? {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return nil }

        let output = NSImage(size: size)
        output.lockFocus()
        defer { output.unlockFocus() }

        image.draw(
            in: NSRect(origin: .zero, size: size),
            from: NSRect(origin: .zero, size: image.size),
            operation: .copy,
            fraction: 1
        )

        drawBlurRegions(
            from: image,
            annotations: annotations.filter { $0.type == .blur },
            imageSize: size,
            enabled: showAnnotations
        )

        guard let context = NSGraphicsContext.current?.cgContext else {
            return output
        }

        context.saveGState()
        context.translateBy(x: 0, y: size.height)
        context.scaleBy(x: 1, y: -1)

        let measuredRegions = annotations.filter { $0.isMeasuredRegion }

        for annotation in annotations where shouldRender(
            annotation,
            showAnnotations: showAnnotations,
            showMeasurements: showMeasurements
        ) {
            draw(
                annotation,
                regionTitle: regionTitle(for: annotation, measuredRegions: measuredRegions),
                calibration: calibration,
                outputUnit: outputUnit,
                imageHeight: size.height,
                in: context
            )
        }

        context.restoreGState()
        return output
    }

    static func renderLegendOverlay(
        image: NSImage,
        annotations: [MSAnnotation],
        calibration: MSCalibration?,
        outputUnit: MSMeasurementUnit,
        computationLines: [String] = []
    ) -> NSImage? {
        guard let output = render(
            image: image,
            annotations: annotations,
            calibration: calibration,
            outputUnit: outputUnit,
            showAnnotations: true,
            showMeasurements: true
        ) else {
            return nil
        }

        let lines = annotationLegendLines(
            annotations: annotations,
            calibration: calibration,
            outputUnit: outputUnit
        )
        guard !lines.isEmpty || !computationLines.isEmpty else { return output }

        output.lockFocus()
        drawLegend(
            lines,
            computationLines: computationLines,
            in: NSRect(
                x: 18,
                y: 18,
                width: min(520, output.size.width - 36),
                height: output.size.height - 36
            )
        )
        output.unlockFocus()
        return output
    }

    static func renderSidebarLegend(
        image: NSImage,
        annotations: [MSAnnotation],
        calibration: MSCalibration?,
        outputUnit: MSMeasurementUnit,
        computationLines: [String] = []
    ) -> NSImage? {
        guard let renderedImage = render(
            image: image,
            annotations: annotations,
            calibration: calibration,
            outputUnit: outputUnit,
            showAnnotations: true,
            showMeasurements: true
        ) else {
            return nil
        }

        let lines = annotationLegendLines(
            annotations: annotations,
            calibration: calibration,
            outputUnit: outputUnit
        )
        let sidebarWidth = max(420, min(620, renderedImage.size.width * 0.38))
        let output = NSImage(size: CGSize(width: renderedImage.size.width + sidebarWidth, height: renderedImage.size.height))

        output.lockFocus()
        NSColor.white.setFill()
        NSRect(origin: .zero, size: output.size).fill()
        renderedImage.draw(at: .zero, from: NSRect(origin: .zero, size: renderedImage.size), operation: .copy, fraction: 1)

        let sidebarRect = NSRect(
            x: renderedImage.size.width,
            y: 0,
            width: sidebarWidth,
            height: renderedImage.size.height
        )
        NSColor.white.setFill()
        sidebarRect.fill()
        drawLegend(
            lines,
            computationLines: computationLines,
            in: sidebarRect.insetBy(dx: 20, dy: 20),
            drawBackground: true,
            darkText: true
        )
        output.unlockFocus()

        return output
    }

    static func annotationCSV(
        annotations: [MSAnnotation],
        calibration: MSCalibration?,
        outputUnit: MSMeasurementUnit,
        computationLines: [String] = []
    ) -> String {
        let measuredRegions = annotations.filter { $0.isMeasuredRegion }
        let rows = annotations.enumerated().map { index, annotation in
            let name = legendTitle(for: annotation, annotationIndex: index, measuredRegions: measuredRegions)
            return [
                name,
                annotation.type.rawValue,
                annotation.displayValue(calibration: calibration, outputUnit: outputUnit),
                String(format: "%.2f", annotation.start.x),
                String(format: "%.2f", annotation.start.y),
                String(format: "%.2f", annotation.end.x),
                String(format: "%.2f", annotation.end.y),
                annotation.regionMeasurementLines(calibration: calibration, outputUnit: outputUnit).joined(separator: " | ")
            ].map(csvEscape).joined(separator: ",")
        }

        let computationRows = computationLines.map {
            [
                "Computation",
                "calculation",
                $0,
                "",
                "",
                "",
                "",
                ""
            ].map(csvEscape).joined(separator: ",")
        }

        return (["Name,Type,Value,Start X,Start Y,End X,End Y,Details"] + rows + computationRows).joined(separator: "\n")
    }

    private static func shouldRender(
        _ annotation: MSAnnotation,
        showAnnotations: Bool,
        showMeasurements: Bool
    ) -> Bool {
        switch annotation.type {
        case .measurement, .calibration, .angle, .parallelAngle:
            return showMeasurements

        case .line, .arrow, .rectangle, .ellipse, .pen, .region, .text:
            return showAnnotations

        case .blur:
            return false
        }
    }

    private static func annotationLegendLines(
        annotations: [MSAnnotation],
        calibration: MSCalibration?,
        outputUnit: MSMeasurementUnit
    ) -> [String] {
        let measuredRegions = annotations.filter { $0.isMeasuredRegion }
        return annotations.enumerated().map { index, annotation in
            let name = legendTitle(for: annotation, annotationIndex: index, measuredRegions: measuredRegions)
            let value = annotation.displayValue(calibration: calibration, outputUnit: outputUnit)
            let regionDetails = annotation.regionMeasurementLines(
                calibration: calibration,
                outputUnit: outputUnit
            )

            if !regionDetails.isEmpty {
                return ([name] + regionDetails).joined(separator: "\n")
            }

            if !value.isEmpty {
                return "\(name)\n\(value)"
            }

            return "\(name)\n\(annotation.type.rawValue)"
        }
    }

    private static func legendTitle(
        for annotation: MSAnnotation,
        annotationIndex: Int,
        measuredRegions: [MSAnnotation]
    ) -> String {
        if annotation.isMeasuredRegion {
            let compactTitle = regionTitle(for: annotation, measuredRegions: measuredRegions)
            let fullTitle = annotation.title?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                ? annotation.title!
                : fullRegionTitle(for: annotation, measuredRegions: measuredRegions)
            return "\(compactTitle): \(fullTitle)"
        }

        return annotation.title?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? annotation.title!
            : defaultTitle(for: annotation, index: annotationIndex)
    }

    private static func defaultTitle(for annotation: MSAnnotation, index: Int) -> String {
        let base: String
        switch annotation.type {
        case .measurement: base = "Measurement"
        case .calibration: base = "Calibration"
        case .angle: base = "Angle"
        case .parallelAngle: base = "Parallel Angle"
        case .line: base = "Line"
        case .arrow: base = "Arrow"
        case .rectangle: base = "Rectangle"
        case .ellipse: base = "Ellipse"
        case .pen: base = "Pen"
        case .region: base = "Region"
        case .text: base = "Text"
        case .blur: base = "Blur"
        }

        return "\(base) \(index + 1)"
    }

    private static func drawLegend(
        _ lines: [String],
        computationLines: [String] = [],
        in rect: NSRect,
        drawBackground: Bool = true,
        darkText: Bool = false
    ) {
        guard rect.width > 0, rect.height > 0 else { return }

        if drawBackground {
            (darkText ? NSColor.white.withAlphaComponent(0.88) : NSColor.black.withAlphaComponent(0.66)).setFill()
            NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8).fill()
        }

        let textColor = darkText ? NSColor.labelColor : NSColor.white
        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 24, weight: .semibold),
            .foregroundColor: textColor
        ]
        let sectionAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 18, weight: .semibold),
            .foregroundColor: textColor
        ]
        let bodyAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 18),
            .foregroundColor: textColor
        ]

        var y = rect.maxY - 44
        NSAttributedString(string: "Annotations", attributes: titleAttributes)
            .draw(at: CGPoint(x: rect.minX + 18, y: y))
        y -= 44

        for line in lines {
            guard y > rect.minY + 16 else { break }
            let attributed = NSAttributedString(string: line, attributes: bodyAttributes)
            let textRect = NSRect(x: rect.minX + 18, y: rect.minY, width: rect.width - 36, height: 10_000)
            let measuredHeight = ceil(
                attributed.boundingRect(
                    with: textRect.size,
                    options: [.usesLineFragmentOrigin]
                ).height
            )
            let rowHeight = max(34, measuredHeight + 14)
            guard y - rowHeight > rect.minY + 16 else { break }

            attributed.draw(
                with: NSRect(x: rect.minX + 18, y: y - rowHeight + 8, width: rect.width - 36, height: rowHeight),
                options: [.usesLineFragmentOrigin]
            )
            y -= rowHeight + 8
        }

        if !computationLines.isEmpty, y > rect.minY + 70 {
            y -= 8
            NSAttributedString(string: "Computations", attributes: sectionAttributes)
                .draw(at: CGPoint(x: rect.minX + 18, y: y - 20))
            y -= 42

            for line in computationLines {
                guard y > rect.minY + 16 else { break }
                let attributed = NSAttributedString(string: line, attributes: bodyAttributes)
                let textRect = NSRect(x: rect.minX + 18, y: rect.minY, width: rect.width - 36, height: 10_000)
                let measuredHeight = ceil(
                    attributed.boundingRect(
                        with: textRect.size,
                        options: [.usesLineFragmentOrigin]
                    ).height
                )
                let rowHeight = max(34, measuredHeight + 14)
                guard y - rowHeight > rect.minY + 16 else { break }

                attributed.draw(
                    with: NSRect(x: rect.minX + 18, y: y - rowHeight + 8, width: rect.width - 36, height: rowHeight),
                    options: [.usesLineFragmentOrigin]
                )
                y -= rowHeight + 8
            }
        }
    }

    private static func csvEscape(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") {
            return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
        }

        return value
    }

    private static func draw(
        _ annotation: MSAnnotation,
        regionTitle: String,
        calibration: MSCalibration?,
        outputUnit: MSMeasurementUnit,
        imageHeight: CGFloat,
        in context: CGContext
    ) {
        let colour = annotation.stroke.color

        context.saveGState()
        context.setStrokeColor(
            red: colour.red,
            green: colour.green,
            blue: colour.blue,
            alpha: colour.alpha * annotation.stroke.opacity
        )
        context.setFillColor(
            red: colour.red,
            green: colour.green,
            blue: colour.blue,
            alpha: colour.alpha * annotation.stroke.opacity
        )
        context.setLineWidth(max(1, annotation.stroke.lineWidth))
        context.setLineCap(.round)
        context.setLineJoin(.round)

        switch annotation.type {
        case .line:
            drawLine(from: annotation.start, to: annotation.end, in: context)

        case .measurement, .calibration:
            drawLine(from: annotation.start, to: annotation.end, in: context)

            let label = annotation.displayValue(
                calibration: calibration,
                outputUnit: outputUnit
            )
            let midpoint = CGPoint(
                x: (annotation.start.x + annotation.end.x) / 2,
                y: (annotation.start.y + annotation.end.y) / 2 - 12
            )
            drawLabel(label, at: midpoint, imageHeight: imageHeight, in: context)

        case .arrow:
            drawArrow(annotation, in: context)

        case .pen:
            drawFreehand(annotation, closePath: false, feathered: true, in: context)

        case .region:
            drawFreehand(annotation, closePath: true, feathered: false, in: context)
            drawLabel(
                regionTitle,
                at: annotation.centre,
                imageHeight: imageHeight,
                in: context
            )

        case .rectangle:
            context.stroke(annotation.normalizedRect)
            drawLabel(
                regionTitle,
                at: annotation.centre,
                imageHeight: imageHeight,
                in: context
            )

        case .ellipse:
            context.strokeEllipse(in: annotation.normalizedRect)
            drawLabel(
                regionTitle,
                at: annotation.centre,
                imageHeight: imageHeight,
                in: context
            )

        case .angle:
            drawPivotAngle(
                annotation,
                calibration: calibration,
                outputUnit: outputUnit,
                imageHeight: imageHeight,
                in: context
            )

        case .parallelAngle:
            drawAngle(
                annotation,
                calibration: calibration,
                outputUnit: outputUnit,
                imageHeight: imageHeight,
                in: context
            )

        case .text:
            drawText(
                annotation,
                imageHeight: imageHeight,
                in: context
            )

        case .blur:
            break
        }
        context.restoreGState()
    }

    private static func drawText(
        _ annotation: MSAnnotation,
        imageHeight: CGFloat,
        in context: CGContext
    ) {
        context.saveGState()
        context.translateBy(x: 0, y: imageHeight)
        context.scaleBy(x: 1, y: -1)

        let colour = annotation.stroke.color
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: annotation.fontSize),
            .foregroundColor: NSColor(
                red: colour.red,
                green: colour.green,
                blue: colour.blue,
                alpha: colour.alpha * annotation.stroke.opacity
            )
        ]

        let attributedString = NSAttributedString(
            string: annotation.text,
            attributes: attributes
        )

        attributedString.draw(
            at: CGPoint(
                x: annotation.start.x,
                y: imageHeight - annotation.start.y - annotation.fontSize
            )
        )

        context.restoreGState()
    }

    private static func drawBlurRegions(
        from image: NSImage,
        annotations: [MSAnnotation],
        imageSize: CGSize,
        enabled: Bool
    ) {
        guard enabled,
              !annotations.isEmpty,
              let tiffData = image.tiffRepresentation,
              let ciImage = CIImage(data: tiffData) else {
            return
        }

        let ciContext = CIContext(options: nil)

        for annotation in annotations {
            guard !annotation.points.isEmpty else { continue }

            guard let filter = CIFilter(name: "CIGaussianBlur") else { continue }
            filter.setValue(ciImage, forKey: kCIInputImageKey)
            filter.setValue(annotation.blurRadius, forKey: kCIInputRadiusKey)

            guard let outputImage = filter.outputImage?.cropped(to: ciImage.extent),
                  let cgImage = ciContext.createCGImage(outputImage, from: ciImage.extent) else {
                continue
            }

            let blurredImage = NSImage(cgImage: cgImage, size: imageSize)

            let maskImage = NSImage(size: imageSize)
            maskImage.lockFocus()
            NSColor.white.setFill()

            let diameter = annotation.blurBrushSize
            let radius = diameter / 2

            for point in annotation.points {
                let appKitPoint = CGPoint(
                    x: point.x,
                    y: imageSize.height - point.y
                )

                NSBezierPath(
                    ovalIn: NSRect(
                        x: appKitPoint.x - radius,
                        y: appKitPoint.y - radius,
                        width: diameter,
                        height: diameter
                    )
                ).fill()
            }

            maskImage.unlockFocus()

            NSGraphicsContext.saveGraphicsState()
            maskImage.draw(
                in: NSRect(origin: .zero, size: imageSize),
                from: NSRect(origin: .zero, size: imageSize),
                operation: .destinationIn,
                fraction: 1
            )

            blurredImage.draw(
                in: NSRect(origin: .zero, size: imageSize),
                from: NSRect(origin: .zero, size: imageSize),
                operation: .sourceOver,
                fraction: 1
            )
            NSGraphicsContext.restoreGraphicsState()
        }
    }


    private static func drawLine(
        from start: CGPoint,
        to end: CGPoint,
        in context: CGContext
    ) {
        context.beginPath()
        context.move(to: start)
        context.addLine(to: end)
        context.strokePath()
    }

    private static func drawArrow(
        _ annotation: MSAnnotation,
        in context: CGContext
    ) {
        let start = annotation.start
        let end = annotation.end
        let angle = atan2(end.y - start.y, end.x - start.x)
        let headLength = max(10, annotation.stroke.lineWidth * 6)

        let first = CGPoint(
            x: end.x - cos(angle - .pi / 6) * headLength,
            y: end.y - sin(angle - .pi / 6) * headLength
        )
        let second = CGPoint(
            x: end.x - cos(angle + .pi / 6) * headLength,
            y: end.y - sin(angle + .pi / 6) * headLength
        )

        context.beginPath()
        context.move(to: start)
        context.addLine(to: end)
        context.move(to: first)
        context.addLine(to: end)
        context.addLine(to: second)
        context.strokePath()
    }

    private static func drawFreehand(
        _ annotation: MSAnnotation,
        closePath: Bool,
        feathered: Bool,
        in context: CGContext
    ) {
        guard let firstPoint = annotation.points.first else { return }

        context.beginPath()
        context.move(to: firstPoint)

        for point in annotation.points.dropFirst() {
            context.addLine(to: point)
        }

        if closePath {
            context.closePath()
        }

        if feathered {
            context.saveGState()
            let colour = annotation.stroke.color
            context.setStrokeColor(
                red: colour.red,
                green: colour.green,
                blue: colour.blue,
                alpha: colour.alpha * annotation.stroke.opacity * 0.16
            )
            context.setLineWidth(max(1, annotation.stroke.lineWidth * 2.8))
            context.strokePath()
            context.restoreGState()

            context.beginPath()
            context.move(to: firstPoint)
            for point in annotation.points.dropFirst() {
                context.addLine(to: point)
            }
        }

        context.strokePath()
    }

    private static func drawPivotAngle(
        _ annotation: MSAnnotation,
        calibration: MSCalibration?,
        outputUnit: MSMeasurementUnit,
        imageHeight: CGFloat,
        in context: CGContext
    ) {
        drawLine(from: annotation.start, to: annotation.end, in: context)

        if let thirdPoint = annotation.thirdPoint {
            drawLine(from: annotation.start, to: thirdPoint, in: context)

            let label = annotation.displayValue(
                calibration: calibration,
                outputUnit: outputUnit
            )

            drawLabel(
                label,
                at: CGPoint(
                    x: annotation.start.x + 12,
                    y: annotation.start.y - 18
                ),
                imageHeight: imageHeight,
                in: context
            )
        }
    }

    private static func drawAngle(
        _ annotation: MSAnnotation,
        calibration: MSCalibration?,
        outputUnit: MSMeasurementUnit,
        imageHeight: CGFloat,
        in context: CGContext
    ) {
        drawLine(from: annotation.start, to: annotation.end, in: context)

        if let thirdPoint = annotation.thirdPoint {
            context.saveGState()
            context.setLineDash(phase: 0, lengths: [6, 4])
            drawLine(from: annotation.end, to: thirdPoint, in: context)
            context.restoreGState()
        }

        if let thirdPoint = annotation.thirdPoint,
           let fourthPoint = annotation.fourthPoint {
            drawLine(from: thirdPoint, to: fourthPoint, in: context)

            let label = annotation.displayValue(
                calibration: calibration,
                outputUnit: outputUnit
            )

            drawLabel(
                label,
                at: CGPoint(
                    x: thirdPoint.x + 12,
                    y: thirdPoint.y - 18
                ),
                imageHeight: imageHeight,
                in: context
            )
        }
    }

    private static func drawLabel(
        _ text: String,
        at point: CGPoint,
        imageHeight: CGFloat,
        in context: CGContext
    ) {
        context.saveGState()
        context.translateBy(x: 0, y: imageHeight)
        context.scaleBy(x: 1, y: -1)

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 14, weight: .semibold),
            .foregroundColor: NSColor.white,
            .backgroundColor: NSColor.black.withAlphaComponent(0.65)
        ]

        let attributedString = NSAttributedString(
            string: "  \(text)  ",
            attributes: attributes
        )

        attributedString.draw(
            at: CGPoint(
                x: point.x,
                y: imageHeight - point.y
            )
        )

        context.restoreGState()
    }

    private static func regionTitle(
        for annotation: MSAnnotation,
        measuredRegions: [MSAnnotation]
    ) -> String {
        guard annotation.isMeasuredRegion else { return "" }

        let matchingRegions = measuredRegions.filter { $0.type == annotation.type }
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

    private static func fullRegionTitle(
        for annotation: MSAnnotation,
        measuredRegions: [MSAnnotation]
    ) -> String {
        guard annotation.isMeasuredRegion else { return "" }

        let matchingRegions = measuredRegions.filter { $0.type == annotation.type }
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
}
