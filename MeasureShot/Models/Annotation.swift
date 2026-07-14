import SwiftUI


enum MSAnnotationType: String, Codable, CaseIterable, Sendable {
    case measurement
    case calibration
    case angle
    case line
    case arrow
    case rectangle
    case ellipse
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
    var stroke: MSStrokeStyle = MSStrokeStyle()
    var text: String = ""
    var measuredValue: Double?
    var measurementUnit: MSMeasurementUnit = .pixels
    var referenceAngleDegrees: Double = 90

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
    }

    var width: CGFloat {
        abs(end.x - start.x)
    }

    var height: CGFloat {
        abs(end.y - start.y)
    }

    var centre: CGPoint {
        CGPoint(
            x: (start.x + end.x) / 2,
            y: (start.y + end.y) / 2
        )
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

        if type == .angle {
            return String(
                format: "%.1f°  (%+.1f° from %.0f°)",
                angleDegrees,
                angleDeviationFromReference,
                referenceAngleDegrees
            )
        }

        return ""
    }

    var angleDegrees: Double {
        guard let thirdPoint else {
            let radians = atan2(end.y - start.y, end.x - start.x)
            var degrees = Double(radians * 180 / .pi)

            while degrees < 0 { degrees += 360 }
            while degrees >= 360 { degrees -= 360 }

            return degrees
        }

        let baseline = CGPoint(
            x: start.x - end.x,
            y: start.y - end.y
        )
        let measuredArm = CGPoint(
            x: thirdPoint.x - end.x,
            y: thirdPoint.y - end.y
        )

        let baselineLength = hypot(baseline.x, baseline.y)
        let measuredLength = hypot(measuredArm.x, measuredArm.y)

        guard baselineLength > 0, measuredLength > 0 else { return 0 }

        let dot = baseline.x * measuredArm.x + baseline.y * measuredArm.y
        let cosine = min(1, max(-1, dot / (baselineLength * measuredLength)))

        return acos(cosine) * 180 / .pi
    }

    var angleDeviationFromReference: Double {
        angleDegrees - referenceAngleDegrees
    }

    var perpendicularReferencePoint: CGPoint? {
        guard let thirdPoint else { return nil }

        let baselineVector = CGPoint(
            x: start.x - end.x,
            y: start.y - end.y
        )
        let baselineLength = hypot(baselineVector.x, baselineVector.y)

        guard baselineLength > 0 else { return nil }

        let armLength = max(
            hypot(thirdPoint.x - end.x, thirdPoint.y - end.y),
            baselineLength * 0.5
        )
        let unit = CGPoint(
            x: baselineVector.x / baselineLength,
            y: baselineVector.y / baselineLength
        )
        let radians = referenceAngleDegrees * .pi / 180
        let rotated = CGPoint(
            x: unit.x * cos(radians) - unit.y * sin(radians),
            y: unit.x * sin(radians) + unit.y * cos(radians)
        )

        return CGPoint(
            x: end.x + rotated.x * armLength,
            y: end.y + rotated.y * armLength
        )
    }
}
