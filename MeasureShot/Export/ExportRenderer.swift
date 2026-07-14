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

        case .line, .arrow, .rectangle, .ellipse, .text:
            return showAnnotations

        case .blur:
            return false
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
}
