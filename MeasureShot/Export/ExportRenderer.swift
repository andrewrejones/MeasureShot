import AppKit

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

        guard let context = NSGraphicsContext.current?.cgContext else {
            return output
        }

        context.saveGState()
        context.translateBy(x: 0, y: size.height)
        context.scaleBy(x: 1, y: -1)

        for annotation in annotations where shouldRender(
            annotation,
            showAnnotations: showAnnotations,
            showMeasurements: showMeasurements
        ) {
            draw(
                annotation,
                calibration: calibration,
                outputUnit: outputUnit,
                imageHeight: size.height,
                in: context
            )
        }

        context.restoreGState()
        return output
    }

    private static func shouldRender(
        _ annotation: MSAnnotation,
        showAnnotations: Bool,
        showMeasurements: Bool
    ) -> Bool {
        switch annotation.type {
        case .measurement, .calibration, .angle:
            return showMeasurements

        case .line, .arrow, .rectangle, .ellipse, .text, .blur:
            return showAnnotations
        }
    }

    private static func draw(
        _ annotation: MSAnnotation,
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

        case .rectangle:
            context.stroke(annotation.normalizedRect)

        case .ellipse:
            context.strokeEllipse(in: annotation.normalizedRect)

        case .angle:
            drawAngle(
                annotation,
                calibration: calibration,
                outputUnit: outputUnit,
                imageHeight: imageHeight,
                in: context
            )

        case .text, .blur:
            break
        }

        context.restoreGState()
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

    private static func drawAngle(
        _ annotation: MSAnnotation,
        calibration: MSCalibration?,
        outputUnit: MSMeasurementUnit,
        imageHeight: CGFloat,
        in context: CGContext
    ) {
        drawLine(from: annotation.start, to: annotation.end, in: context)

        if let thirdPoint = annotation.thirdPoint {
            drawLine(from: annotation.end, to: thirdPoint, in: context)
        }

        if let referencePoint = annotation.perpendicularReferencePoint {
            context.saveGState()
            context.setLineDash(phase: 0, lengths: [6, 4])
            drawLine(from: annotation.end, to: referencePoint, in: context)
            context.restoreGState()
        }

        let label = annotation.displayValue(
            calibration: calibration,
            outputUnit: outputUnit
        )
        drawLabel(
            label,
            at: CGPoint(x: annotation.end.x + 12, y: annotation.end.y - 18),
            imageHeight: imageHeight,
            in: context
        )
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
}
