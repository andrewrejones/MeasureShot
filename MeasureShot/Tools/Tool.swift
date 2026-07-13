
import Foundation

enum MSToolType: String, CaseIterable, Identifiable, Sendable {
    case select
    case measure
    case calibrate
    case angle
    case arrow
    case rectangle
    case ellipse
    case text
    case blur
    case colourPicker

    var id: String { rawValue }

    var title: String {
        switch self {
        case .select: "Select"
        case .measure: "Measure"
        case .calibrate: "Calibrate"
        case .angle: "Angle"
        case .arrow: "Arrow"
        case .rectangle: "Rectangle"
        case .ellipse: "Ellipse"
        case .text: "Text"
        case .blur: "Blur"
        case .colourPicker: "Colour Picker"
        }
    }

    var systemImage: String {
        switch self {
        case .select: "cursorarrow"
        case .measure: "ruler"
        case .calibrate: "scope"
        case .angle: "angle"
        case .arrow: "arrow.up.right"
        case .rectangle: "rectangle"
        case .ellipse: "circle"
        case .text: "textformat"
        case .blur: "drop"
        case .colourPicker: "eyedropper"
        }
    }
}
