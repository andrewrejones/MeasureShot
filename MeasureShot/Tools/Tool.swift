
import Foundation

enum MSToolType: String, CaseIterable, Identifiable, Sendable {
    case select
    case measure
    case calibrate
    case angle
    case parallelAngle
    case arrow
    case rectangle
    case ellipse
    case region
    case trace
    case pen
    case text
    case blur
    case crop
    case colourPicker
    case sideBySide

    var id: String { rawValue }

    var title: String {
        switch self {
        case .select: "Select"
        case .measure: "Measure"
        case .calibrate: "Calibrate"
        case .angle: "Angle"
        case .parallelAngle: "Parallel Angle"
        case .arrow: "Arrow"
        case .rectangle: "Rectangle"
        case .ellipse: "Ellipse"
        case .region: "Region"
        case .trace: "Trace"
        case .pen: "Pen"
        case .text: "Text"
        case .blur: "Blur"
        case .crop: "Crop"
        case .colourPicker: "Colour Picker"
        case .sideBySide: "Compare"
        }
    }

    var systemImage: String {
        switch self {
        case .select: "cursorarrow"
        case .measure: "ruler"
        case .calibrate: "scope"
        case .angle: "angle"
        case .parallelAngle: "angle"
        case .arrow: "arrow.up.right"
        case .rectangle: "rectangle"
        case .ellipse: "circle"
        case .region: "lasso"
        case .trace: "waveform.path.ecg"
        case .pen: "pencil.tip"
        case .text: "textformat"
        case .blur: "drop"
        case .crop: "crop"
        case .colourPicker: "eyedropper"
        case .sideBySide: "rectangle.split.2x1"
        }
    }
}
