import SwiftUI
import CoreImage

struct AnnotationOverlay: View {
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

extension Path {
    init(_ rect: CGRect) {
        self.init()
        addRect(rect)
    }
}
