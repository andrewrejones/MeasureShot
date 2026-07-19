import SwiftUI
import CoreImage

struct AnnotationOverlay: View {
    let annotations: [MSAnnotation]
    let inProgress: MSAnnotation?
    let selectedAnnotationID: UUID?
    let scale: CGFloat
    let calibration: MSCalibration?
    let outputUnit: MSMeasurementUnit
    let regionTitleProvider: (MSAnnotation) -> String

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
            drawPivotAngle(
                annotation,
                color: color,
                lineWidth: lineWidth,
                in: &context
            )

        case .parallelAngle:
            drawAngle(
                annotation,
                color: color,
                lineWidth: lineWidth,
                in: &context
            )

        case .arrow:
            drawArrow(from: start, to: end, color: color, lineWidth: lineWidth, in: &context)

        case .pen:
            drawFreehand(
                annotation,
                closePath: false,
                color: color,
                lineWidth: lineWidth,
                feathered: true,
                in: &context
            )

        case .trace:
            drawFreehand(
                annotation,
                closePath: false,
                color: color,
                lineWidth: lineWidth,
                feathered: false,
                in: &context
            )
            if !selected {
                drawPathPointHandles(annotation, in: &context)
            }

        case .region:
            drawFreehand(
                annotation,
                closePath: true,
                color: color,
                lineWidth: lineWidth,
                feathered: false,
                in: &context
            )
            drawRegionLabel(annotation, in: &context)

        case .rectangle:
            context.stroke(
                Path(annotation.normalizedRect.applying(CGAffineTransform(scaleX: scale, y: scale))),
                with: .color(color),
                lineWidth: lineWidth
            )
            drawRegionLabel(annotation, in: &context)

        case .ellipse:
            let rect = annotation.normalizedRect.applying(CGAffineTransform(scaleX: scale, y: scale))
            context.stroke(Path(ellipseIn: rect), with: .color(color), lineWidth: lineWidth)
            drawRegionLabel(annotation, in: &context)

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

    private func drawPivotAngle(
        _ annotation: MSAnnotation,
        color: Color,
        lineWidth: CGFloat,
        in context: inout GraphicsContext
    ) {
        let pivot = scaled(annotation.start)
        let firstEnd = scaled(annotation.end)

        var path = Path()
        path.move(to: pivot)
        path.addLine(to: firstEnd)

        if let thirdPoint = annotation.thirdPoint {
            path.move(to: pivot)
            path.addLine(to: scaled(thirdPoint))
        }

        context.stroke(path, with: .color(color), lineWidth: lineWidth)

        let pivotDot = CGRect(x: pivot.x - 4, y: pivot.y - 4, width: 8, height: 8)
        context.fill(Path(ellipseIn: pivotDot), with: .color(color))

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
                at: CGPoint(x: pivot.x + 12, y: pivot.y - 18),
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

    private func drawRegionLabel(_ annotation: MSAnnotation, in context: inout GraphicsContext) {
        let labelText = regionTitleProvider(annotation)
        guard !labelText.isEmpty else { return }

        let label = Text(labelText)
            .font(.system(size: max(10, 12 * scale), weight: .semibold, design: .rounded))
            .foregroundColor(.white)

        context.draw(label, at: scaled(annotation.centre), anchor: .center)
    }

    private func drawFreehand(
        _ annotation: MSAnnotation,
        closePath: Bool,
        color: Color,
        lineWidth: CGFloat,
        feathered: Bool,
        in context: inout GraphicsContext
    ) {
        guard let firstPoint = annotation.points.first else { return }

        var path = Path()
        path.move(to: scaled(firstPoint))

        for point in annotation.points.dropFirst() {
            path.addLine(to: scaled(point))
        }

        if closePath {
            path.closeSubpath()
            context.fill(path, with: .color(color.opacity(0.12)))
        }

        if feathered {
            context.stroke(
                path,
                with: .color(color.opacity(0.16)),
                style: StrokeStyle(lineWidth: lineWidth * 2.8, lineCap: .round, lineJoin: .round)
            )
            context.stroke(
                path,
                with: .color(color.opacity(0.24)),
                style: StrokeStyle(lineWidth: lineWidth * 1.8, lineCap: .round, lineJoin: .round)
            )
        }

        context.stroke(
            path,
            with: .color(color),
            style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
        )
    }

    private func drawSelectionHandles(_ annotation: MSAnnotation, in context: inout GraphicsContext) {
        if annotation.type == .pen || annotation.type == .region || annotation.type == .trace {
            guard !annotation.points.isEmpty else { return }

            let rect = annotation.points.reduce(CGRect.null) { partialResult, point in
                partialResult.union(CGRect(origin: scaled(point), size: .zero))
            }.insetBy(dx: -6, dy: -6)

            context.stroke(
                Path(rect),
                with: .color(.accentColor.opacity(0.75)),
                style: StrokeStyle(lineWidth: 1, dash: [5, 4])
            )

            if annotation.type == .region || annotation.type == .trace {
                drawPathPointHandles(annotation, in: &context)
            }
            return
        }

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

    private func drawPathPointHandles(_ annotation: MSAnnotation, in context: inout GraphicsContext) {
        for (index, point) in annotation.points.enumerated() {
            if annotation.type == .region,
               index == annotation.points.count - 1,
               annotation.points.count > 2 {
                continue
            }

            let centre = scaled(point)
            let radius = index == 0 ? 5.5 : 4.5
            let rect = CGRect(
                x: centre.x - radius,
                y: centre.y - radius,
                width: radius * 2,
                height: radius * 2
            )

            context.fill(Path(ellipseIn: rect), with: .color(.white.opacity(0.95)))
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
