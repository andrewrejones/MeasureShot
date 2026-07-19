import SwiftUI


enum MSAnnotationType: String, Codable, CaseIterable, Sendable {
    case measurement
    case calibration
    case angle
    case parallelAngle
    case line
    case arrow
    case rectangle
    case ellipse
    case pen
    case region
    case trace
    case text
    case blur
}

enum MSMeasurementUnit: String, Codable, CaseIterable, Identifiable, Sendable {
    case pixels = "px"
    case millimetres = "mm"
    case centimetres = "cm"
    case metres = "m"
    case inches = "in"
    case feet = "ft"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pixels: return "Pixels"
        case .millimetres: return "Millimetres"
        case .centimetres: return "Centimetres"
        case .metres: return "Metres"
        case .inches: return "Inches"
        case .feet: return "Feet"
        }
    }

    var millimetresPerUnit: Double? {
        switch self {
        case .pixels:
            return nil
        case .millimetres:
            return 1
        case .centimetres:
            return 10
        case .metres:
            return 1_000
        case .inches:
            return 25.4
        case .feet:
            return 304.8
        }
    }
}

struct MSCalibration: Codable, Sendable, Hashable {
    var pixelLength: Double
    var knownLength: Double
    var unit: MSMeasurementUnit

    var millimetresPerPixel: Double? {
        guard pixelLength > 0,
              knownLength > 0,
              let millimetresPerUnit = unit.millimetresPerUnit else {
            return nil
        }

        return knownLength * millimetresPerUnit / pixelLength
    }

    func convertedLength(forPixels pixels: Double, to outputUnit: MSMeasurementUnit) -> Double? {
        if outputUnit == .pixels {
            return pixels
        }

        guard let millimetresPerPixel,
              let millimetresPerOutputUnit = outputUnit.millimetresPerUnit else {
            return nil
        }

        return pixels * millimetresPerPixel / millimetresPerOutputUnit
    }

    func convertedArea(forSquarePixels squarePixels: Double, to outputUnit: MSMeasurementUnit) -> Double? {
        if outputUnit == .pixels {
            return squarePixels
        }

        guard let millimetresPerPixel,
              let millimetresPerOutputUnit = outputUnit.millimetresPerUnit else {
            return nil
        }

        let outputUnitsPerPixel = millimetresPerPixel / millimetresPerOutputUnit
        return squarePixels * outputUnitsPerPixel * outputUnitsPerPixel
    }
}

struct MSStrokeStyle: Codable, Sendable, Hashable {
    var color: ColorData = .systemRed
    var lineWidth: CGFloat = 2
    var opacity: Double = 1.0
}

struct ColorData: Codable, Hashable, Sendable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double

    static let systemRed = ColorData(
        red: 1,
        green: 0.23,
        blue: 0.19,
        alpha: 1
    )

    var swiftUIColor: Color {
        Color(
            red: red,
            green: green,
            blue: blue,
            opacity: alpha
        )
    }
}

struct MSAnnotation: Identifiable, Codable, Sendable {
    let id: UUID
    var type: MSAnnotationType
    var start: CGPoint
    var end: CGPoint
    
    var thirdPoint: CGPoint?
    var fourthPoint: CGPoint?
    var title: String?
    var stroke: MSStrokeStyle = MSStrokeStyle()
    var text: String = ""
    var fontSize: CGFloat = 18
    var measuredValue: Double?
    var measurementUnit: MSMeasurementUnit = .pixels
    var referenceAngleDegrees: Double = 90
    var blurRadius: Double = 12
    var blurBrushSize: Double = 44
    var points: [CGPoint] = []

    init(
        type: MSAnnotationType,
        start: CGPoint,
        end: CGPoint
    ) {
        self.id = UUID()
        self.type = type
        self.start = start
        self.end = end
        self.thirdPoint = nil
        self.fourthPoint = nil
    }

    var width: CGFloat {
        abs(end.x - start.x)
    }

    var height: CGFloat {
        abs(end.y - start.y)
    }

    var centre: CGPoint {
        if type == .region, !points.isEmpty {
            return CGPoint(x: regionBounds.midX, y: regionBounds.midY)
        }

        return CGPoint(
            x: (start.x + end.x) / 2,
            y: (start.y + end.y) / 2
        )
    }

    var regionBounds: CGRect {
        guard !points.isEmpty else { return normalizedRect }

        return points.reduce(CGRect.null) { partialResult, point in
            partialResult.union(CGRect(origin: point, size: .zero))
        }
    }

    var normalizedRect: CGRect {
        CGRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(end.x - start.x),
            height: abs(end.y - start.y)
        )
    }

    var length: CGFloat {
        hypot(end.x - start.x, end.y - start.y)
    }

    var isMeasuredRegion: Bool {
        type == .rectangle || type == .ellipse || type == .region
    }

    var regionPerimeterPixels: Double {
        switch type {
        case .rectangle:
            return Double(2 * (width + height))
        case .ellipse:
            let a = Double(width / 2)
            let b = Double(height / 2)
            guard a > 0, b > 0 else { return 0 }
            let h = pow(a - b, 2) / pow(a + b, 2)
            return .pi * (a + b) * (1 + (3 * h) / (10 + sqrt(4 - 3 * h)))
        case .region:
            return Double(closedPolylineLength(points))
        default:
            return Double(length)
        }
    }

    var regionAreaSquarePixels: Double {
        switch type {
        case .rectangle:
            return Double(width * height)
        case .ellipse:
            return Double.pi * Double(width / 2) * Double(height / 2)
        case .region:
            return abs(shoelaceArea(points))
        default:
            return 0
        }
    }

    func regionMeasurementText(
        calibration: MSCalibration?,
        outputUnit: MSMeasurementUnit
    ) -> String {
        guard isMeasuredRegion else { return "" }

        let unit = calibratedUnit(calibration: calibration, outputUnit: outputUnit)
        let widthText = formattedLength(
            Double(width),
            calibration: calibration,
            outputUnit: outputUnit
        )
        let heightText = formattedLength(
            Double(height),
            calibration: calibration,
            outputUnit: outputUnit
        )
        let perimeterText = formattedLength(
            regionPerimeterPixels,
            calibration: calibration,
            outputUnit: outputUnit
        )
        let areaText = formattedArea(
            regionAreaSquarePixels,
            calibration: calibration,
            outputUnit: outputUnit
        )

        switch type {
        case .rectangle:
            return "W \(widthText)  H \(heightText)\nA \(areaText)  P \(perimeterText)"
        case .ellipse:
            let radiusX = formattedLength(
                Double(width / 2),
                calibration: calibration,
                outputUnit: outputUnit
            )
            let radiusY = formattedLength(
                Double(height / 2),
                calibration: calibration,
                outputUnit: outputUnit
            )
            return "D \(widthText) x \(heightText)\nR \(radiusX) x \(radiusY)\nA \(areaText)  P \(perimeterText)"
        case .region:
            return "A \(areaText)\nP \(perimeterText)"
        default:
            return unit
        }
    }

    func regionMeasurementLines(
        calibration: MSCalibration?,
        outputUnit: MSMeasurementUnit
    ) -> [String] {
        guard isMeasuredRegion else { return [] }

        let widthText = formattedLength(
            Double(width),
            calibration: calibration,
            outputUnit: outputUnit
        )
        let heightText = formattedLength(
            Double(height),
            calibration: calibration,
            outputUnit: outputUnit
        )
        let perimeterText = formattedLength(
            regionPerimeterPixels,
            calibration: calibration,
            outputUnit: outputUnit
        )
        let areaText = formattedArea(
            regionAreaSquarePixels,
            calibration: calibration,
            outputUnit: outputUnit
        )

        switch type {
        case .rectangle:
            return [
                "Width: \(widthText)",
                "Height: \(heightText)",
                "Area: \(areaText)",
                "Perimeter: \(perimeterText)"
            ]
        case .ellipse:
            let radiusX = formattedLength(
                Double(width / 2),
                calibration: calibration,
                outputUnit: outputUnit
            )
            let radiusY = formattedLength(
                Double(height / 2),
                calibration: calibration,
                outputUnit: outputUnit
            )
            return [
                "Diameter: \(widthText) x \(heightText)",
                "Radius: \(radiusX) x \(radiusY)",
                "Area: \(areaText)",
                "Perimeter: \(perimeterText)"
            ]
        case .region:
            return [
                "Area: \(areaText)",
                "Perimeter: \(perimeterText)"
            ]
        default:
            return []
        }
    }

    func displayValue(
        calibration: MSCalibration?,
        outputUnit: MSMeasurementUnit
    ) -> String {
        if type == .measurement {
            if let calibration,
               let converted = calibration.convertedLength(
                  forPixels: Double(length),
                  to: outputUnit
               ) {
                return String(format: "%.2f %@", converted, outputUnit.rawValue)
            }

            return String(format: "%.1f px", Double(length))
        }

        if type == .calibration {
            if let measuredValue {
                return String(format: "%.2f %@", measuredValue, measurementUnit.rawValue)
            }

            return String(format: "%.1f px", Double(length))
        }

        if type == .angle || type == .parallelAngle {
            return String(
                format: type == .angle ? "%.1f°" : "%+.1f° from baseline",
                angleDeviationFromReference
            )
        }

        return ""
    }

    private func formattedLength(
        _ pixels: Double,
        calibration: MSCalibration?,
        outputUnit: MSMeasurementUnit
    ) -> String {
        if let calibration,
           let converted = calibration.convertedLength(forPixels: pixels, to: outputUnit) {
            return String(format: "%.2f %@", converted, outputUnit.rawValue)
        }

        return String(format: "%.1f px", pixels)
    }

    private func formattedArea(
        _ squarePixels: Double,
        calibration: MSCalibration?,
        outputUnit: MSMeasurementUnit
    ) -> String {
        if let calibration,
           let converted = calibration.convertedArea(forSquarePixels: squarePixels, to: outputUnit) {
            return String(format: "%.2f %@²", converted, outputUnit.rawValue)
        }

        return String(format: "%.1f px²", squarePixels)
    }

    private func calibratedUnit(
        calibration: MSCalibration?,
        outputUnit: MSMeasurementUnit
    ) -> String {
        calibration == nil ? "px" : outputUnit.rawValue
    }

    private func closedPolylineLength(_ points: [CGPoint]) -> CGFloat {
        guard points.count > 1 else { return 0 }

        var total: CGFloat = 0
        for index in 1..<points.count {
            total += hypot(points[index].x - points[index - 1].x, points[index].y - points[index - 1].y)
        }

        if let first = points.first, let last = points.last {
            total += hypot(first.x - last.x, first.y - last.y)
        }

        return total
    }

    private func shoelaceArea(_ points: [CGPoint]) -> Double {
        guard points.count > 2 else { return 0 }

        var sum = 0.0
        for index in points.indices {
            let nextIndex = points.index(after: index) == points.endIndex ? points.startIndex : points.index(after: index)
            sum += Double(points[index].x * points[nextIndex].y - points[nextIndex].x * points[index].y)
        }

        return sum / 2
    }

    var angleDegrees: Double {
        guard let thirdPoint else {
            return 0
        }

        let baseline = CGPoint(
            x: end.x - start.x,
            y: end.y - start.y
        )
        let measuredLine: CGPoint
        if type == .parallelAngle, let fourthPoint {
            measuredLine = CGPoint(
                x: fourthPoint.x - thirdPoint.x,
                y: fourthPoint.y - thirdPoint.y
            )
        } else {
            measuredLine = CGPoint(
                x: thirdPoint.x - start.x,
                y: thirdPoint.y - start.y
            )
        }

        let baselineLength = hypot(baseline.x, baseline.y)
        let measuredLength = hypot(measuredLine.x, measuredLine.y)

        guard baselineLength > 0, measuredLength > 0 else { return 0 }

        let dot = baseline.x * measuredLine.x + baseline.y * measuredLine.y
        let cosine = min(1, max(-1, dot / (baselineLength * measuredLength)))
        let unsigned = acos(cosine) * 180 / .pi
        let cross = baseline.x * measuredLine.y - baseline.y * measuredLine.x

        return cross < 0 ? -unsigned : unsigned
    }

    var angleDeviationFromReference: Double {
        angleDegrees
    }

    var perpendicularReferencePoint: CGPoint? {
        thirdPoint
    }

    func perpendicularPoint(length: CGFloat) -> CGPoint? {
        let baseline = CGPoint(
            x: end.x - start.x,
            y: end.y - start.y
        )
        let baselineLength = hypot(baseline.x, baseline.y)

        guard baselineLength > 0 else { return nil }

        let unit = CGPoint(
            x: baseline.x / baselineLength,
            y: baseline.y / baselineLength
        )
        let radians = referenceAngleDegrees * .pi / 180
        let rotated = CGPoint(
            x: unit.x * cos(radians) - unit.y * sin(radians),
            y: unit.x * sin(radians) + unit.y * cos(radians)
        )

        return CGPoint(
            x: end.x + rotated.x * length,
            y: end.y + rotated.y * length
        )
    }
}
