import SwiftUI
import CoreImage

private let exportHistoryDateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .none
    formatter.timeStyle = .short
    return formatter
}()

private let annotationColourPresets: [(title: String, color: Color)] = [
    ("Black", .black),
    ("White", .white),
    ("Red", .red),
    ("Highlighter Green", Color(red: 0.25, green: 1.0, blue: 0.25)),
    ("Highlighter Yellow", Color(red: 1.0, green: 0.92, blue: 0.05)),
    ("Blue", .blue)
]

struct InspectorSidebar: View {
    @Environment(AppState.self) private var appState
    @AppStorage("inspector.imageSectionExpanded") private var isImageSectionExpanded = true
    @AppStorage("inspector.appearanceSectionExpanded") private var isAppearanceSectionExpanded = true
    @AppStorage("inspector.layersSectionExpanded") private var isLayersSectionExpanded = true
    @State private var comparisonFirstID: UUID?
    @State private var comparisonSecondID: UUID?
    @State private var comparisonResult: String?

    private var shouldShowMeasurementPanel: Bool {
        appState.selectedTool == .calibrate
            || appState.selectedTool == .measure
            || appState.selectedAnnotation?.type == .calibration
            || appState.selectedAnnotation?.type == .measurement
    }

    private var shouldShowCalibrationControls: Bool {
        appState.selectedTool == .calibrate
            || appState.selectedAnnotation?.type == .calibration
    }

    private var shouldShowColourPickerPanel: Bool {
        appState.selectedTool == .colourPicker
    }

    private var shouldShowTextPanel: Bool {
        appState.selectedTool == .text
            || appState.selectedAnnotation?.type == .text
    }

    private var shouldShowBlurPanel: Bool {
        appState.selectedTool == .blur
            || appState.selectedAnnotation?.type == .blur
    }

    private var measuredRegions: [MSAnnotation] {
        appState.measuredRegions()
    }

    private var textSection: some View {
        GroupBox("Text") {
            VStack(alignment: .leading, spacing: 10) {
                TextField(
                    "Text",
                    text: Binding(
                        get: {
                            appState.selectedAnnotation?.type == .text
                                ? appState.selectedAnnotation?.text ?? appState.defaultText
                                : appState.defaultText
                        },
                        set: { newValue in
                            appState.defaultText = newValue
                            if appState.selectedAnnotation?.type == .text {
                                appState.updateSelectedText(newValue)
                            }
                        }
                    )
                )

                HStack {
                    Text("Font Size")
                    Spacer()
                    Text("\(Int(appState.selectedAnnotation?.type == .text ? appState.selectedAnnotation?.fontSize ?? appState.defaultFontSize : appState.defaultFontSize)) pt")
                        .foregroundStyle(.secondary)
                }

                Slider(
                    value: Binding(
                        get: {
                            Double(
                                appState.selectedAnnotation?.type == .text
                                    ? appState.selectedAnnotation?.fontSize ?? appState.defaultFontSize
                                    : appState.defaultFontSize
                            )
                        },
                        set: { newValue in
                            appState.defaultFontSize = CGFloat(newValue)
                            if appState.selectedAnnotation?.type == .text {
                                appState.updateSelectedFontSize(CGFloat(newValue))
                            }
                        }
                    ),
                    in: 8...72,
                    step: 1
                )

                Text("Click the image to place text, then edit it here.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var blurSection: some View {
        GroupBox("Blur") {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Strength")
                    Spacer()
                    Text("\(Int(appState.selectedAnnotation?.type == .blur ? appState.selectedAnnotation?.blurRadius ?? appState.defaultBlurRadius : appState.defaultBlurRadius))")
                        .foregroundStyle(.secondary)
                }

                Slider(
                    value: Binding(
                        get: {
                            appState.selectedAnnotation?.type == .blur
                                ? appState.selectedAnnotation?.blurRadius ?? appState.defaultBlurRadius
                                : appState.defaultBlurRadius
                        },
                        set: { newValue in
                            appState.defaultBlurRadius = newValue
                            if appState.selectedAnnotation?.type == .blur {
                                appState.updateSelectedBlurRadius(newValue)
                            }
                        }
                    ),
                    in: 4...80,
                    step: 1
                )

                HStack {
                    Text("Brush Size")
                    Spacer()
                    Text("\(Int(appState.selectedAnnotation?.type == .blur ? appState.selectedAnnotation?.blurBrushSize ?? appState.defaultBlurBrushSize : appState.defaultBlurBrushSize)) px")
                        .foregroundStyle(.secondary)
                }

                Slider(
                    value: Binding(
                        get: {
                            appState.selectedAnnotation?.type == .blur
                                ? appState.selectedAnnotation?.blurBrushSize ?? appState.defaultBlurBrushSize
                                : appState.defaultBlurBrushSize
                        },
                        set: { newValue in
                            appState.defaultBlurBrushSize = newValue
                            if appState.selectedAnnotation?.type == .blur {
                                appState.updateSelectedBlurBrushSize(newValue)
                            }
                        }
                    ),
                    in: 10...160,
                    step: 2
                )

                Toggle(
                    "Show Painted Mask",
                    isOn: Binding(
                        get: { appState.showBlurMask },
                        set: { appState.showBlurMask = $0 }
                    )
                )

                Text("Drag across the area to blur. Use Select to move or resize it later.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Inspector")
                    .font(.headline)

                activeToolSection
                instructionsSection

                if !measuredRegions.isEmpty {
                    measuredRegionsSection
                }

                if measuredRegions.count >= 2 {
                    regionComparisonSection
                }

                if appState.imageDocument != nil {
                    imageAdjustmentsSection
                }

                appearanceSection

                if shouldShowTextPanel {
                    textSection
                }

                if shouldShowBlurPanel {
                    blurSection
                }

                if shouldShowColourPickerPanel {
                    colourPickerSection
                }

                if shouldShowMeasurementPanel {
                    measurementSection
                }

                layersSection

                if !appState.exportHistory.isEmpty {
                    exportHistorySection
                }
            }
            .padding(12)
        }
        .background(.thinMaterial)
    }

    private var colourPickerSection: some View {
        GroupBox("Sampled Colour") {
            VStack(alignment: .leading, spacing: 10) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(appState.sampledColor)
                    .frame(height: 42)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(.secondary.opacity(0.4))
                    )

                HStack {
                    Text("HEX")
                    Spacer()
                    Text(appState.sampledHex)
                        .font(.system(.body, design: .monospaced))
                }

                HStack {
                    Text("RGB")
                    Spacer()
                    Text(appState.sampledRGB)
                        .font(.system(.body, design: .monospaced))
                }

                Text("Click anywhere on the image to copy the HEX value.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var activeToolSection: some View {
        GroupBox("Active Tool") {
            HStack {
                Image(systemName: appState.selectedTool.systemImage)
                Text(appState.selectedTool.title)
                Spacer()
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var measuredRegionsSection: some View {
        GroupBox("Measured Regions") {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(measuredRegions.enumerated()), id: \.element.id) { _, annotation in
                    regionMeasurementRow(annotation)

                    if annotation.id != measuredRegions.last?.id {
                        Divider()
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func regionMeasurementRow(_ annotation: MSAnnotation) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                TextField(
                    "Region name",
                    text: Binding(
                        get: { appState.regionTitle(for: annotation) },
                        set: { appState.updateRegionTitle(id: annotation.id, title: $0) }
                    )
                )
                .textFieldStyle(.roundedBorder)
                .font(.subheadline)

                Spacer()

                Button {
                    appState.selectAnnotation(id: annotation.id)
                    appState.selectedTool = .select
                } label: {
                    Image(systemName: appState.selectedAnnotationID == annotation.id ? "checkmark.circle.fill" : "scope")
                }
                .buttonStyle(.borderless)
                .help("Select \(appState.regionTitle(for: annotation))")

                Button(role: .destructive) {
                    appState.deleteAnnotation(id: annotation.id)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help("Delete \(appState.regionTitle(for: annotation))")
            }

            ForEach(
                annotation.regionMeasurementLines(
                    calibration: appState.calibration,
                    outputUnit: appState.outputMeasurementUnit
                ),
                id: \.self
            ) { line in
                Text(line)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let averageColor = appState.averageColor(for: annotation) {
                Divider()

                Text("Average HEX: \(averageColor.hex)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)

                Text("Average RGB: \(averageColor.rgb)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
    }

    private var exportHistorySection: some View {
        GroupBox("Export History") {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Recent Exports")
                        .font(.subheadline)
                    Spacer()
                    Button("Clear") {
                        appState.clearExportHistory()
                    }
                    .buttonStyle(.link)
                }

                ForEach(appState.exportHistory.prefix(6)) { item in
                    exportHistoryRow(item)

                    if item.id != appState.exportHistory.prefix(6).last?.id {
                        Divider()
                    }
                }

            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func exportHistoryRow(_ item: MSExportHistoryItem) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(nsImage: item.image)
                .resizable()
                .scaledToFit()
                .frame(width: 56, height: 42)
                .background(Color(nsColor: .windowBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(.secondary.opacity(0.3))
                )

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Image(systemName: item.action.systemImage)
                    Text(item.action.title)
                        .fontWeight(.medium)
                    Spacer()
                }

                Text(exportHistoryDateFormatter.string(from: item.createdAt))
                    .foregroundStyle(.secondary)

                Text(item.dimensionsText)
                    .foregroundStyle(.secondary)

                if let fileURL = item.fileURL {
                    Text(fileURL.lastPathComponent)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .font(.caption)

            Button {
                appState.copyExportHistoryItem(id: item.id)
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .buttonStyle(.borderless)
            .help("Copy this export")
        }
    }

    private var instructionsSection: some View {
        GroupBox("How to Use") {
            Text(toolInstructions)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var imageAdjustmentsSection: some View {
        DisclosureGroup(isExpanded: $isImageSectionExpanded) {
            VStack(alignment: .leading, spacing: 12) {
                adjustmentSlider(
                    title: "Brightness",
                    value: Binding(
                        get: { appState.imageDocument?.brightness ?? 0 },
                        set: { appState.setImageBrightness($0) }
                    ),
                    range: -1...1,
                    step: 0.01,
                    label: String(format: "%.2f", appState.imageDocument?.brightness ?? 0)
                )

                adjustmentSlider(
                    title: "Contrast",
                    value: Binding(
                        get: { appState.imageDocument?.contrast ?? 1 },
                        set: { appState.setImageContrast($0) }
                    ),
                    range: 0.25...3,
                    step: 0.01,
                    label: String(format: "%.2f", appState.imageDocument?.contrast ?? 1)
                )

                adjustmentSlider(
                    title: "Exposure",
                    value: Binding(
                        get: { appState.imageDocument?.exposure ?? 0 },
                        set: { appState.setImageExposure($0) }
                    ),
                    range: -3...3,
                    step: 0.1,
                    label: String(format: "%+.1f EV", appState.imageDocument?.exposure ?? 0)
                )

                Button("Reset Image Adjustments") {
                    appState.resetImageAdjustments()
                }
                .disabled(
                    appState.imageDocument?.brightness == 0
                        && appState.imageDocument?.contrast == 1
                        && appState.imageDocument?.exposure == 0
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 8)
        } label: {
            Label("Image", systemImage: "photo")
        }
    }

    private func adjustmentSlider(
        title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double,
        label: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                Spacer()
                Text(label)
                    .foregroundStyle(.secondary)
            }

            Slider(
                value: value,
                in: range,
                step: step,
                onEditingChanged: { isEditing in
                    if isEditing {
                        appState.beginImageAdjustmentEdit()
                    } else {
                        appState.finishImageAdjustmentEdit()
                    }
                }
            )
        }
    }

    private var appearanceSection: some View {
        DisclosureGroup(isExpanded: $isAppearanceSectionExpanded) {
            VStack(alignment: .leading, spacing: 12) {
                ColorPicker(
                    "Custom Colour",
                    selection: Binding(
                        get: { appState.annotationColor },
                        set: { newColor in
                            appState.setAnnotationColor(newColor)
                        }
                    )
                )

                VStack(alignment: .leading, spacing: 6) {
                    Text("Presets")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 8) {
                        ForEach(annotationColourPresets.indices, id: \.self) { index in
                            let preset = annotationColourPresets[index]

                            Button {
                                appState.setAnnotationColor(preset.color)
                            } label: {
                                Circle()
                                    .fill(preset.color)
                                    .frame(width: 22, height: 22)
                                    .overlay(
                                        Circle()
                                            .stroke(.secondary.opacity(0.45), lineWidth: 1)
                                    )
                            }
                            .buttonStyle(.plain)
                            .help(preset.title)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Line Width")
                        Spacer()
                        Text("\(appState.annotationLineWidth, specifier: "%.1f") pt")
                            .foregroundStyle(.secondary)
                    }

                    Slider(
                        value: Binding(
                            get: { Double(appState.annotationLineWidth) },
                            set: { newValue in
                                appState.setAnnotationLineWidth(CGFloat(newValue))
                            }
                        ),
                        in: 1...12,
                        step: 0.5
                    )
                }

                if appState.selectedAnnotationID != nil {
                    Button("Apply to Selected") {
                        appState.applyCurrentStyleToSelection()
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 8)
        } label: {
            HStack {
                Label("Appearance", systemImage: "paintpalette")
                Spacer()
                Circle()
                    .fill(appState.annotationColor)
                    .frame(width: 14, height: 14)
                    .overlay(Circle().stroke(.secondary.opacity(0.45), lineWidth: 1))
                Text("\(appState.annotationLineWidth, specifier: "%.1f") pt")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var measurementSection: some View {
        GroupBox("Measurement") {
            VStack(alignment: .leading, spacing: 10) {
                outputUnitPicker

                if shouldShowCalibrationControls {
                    Divider()
                    calibrationControls
                }

                calibrationStatus
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var regionComparisonSection: some View {
        GroupBox("Compare Regions") {
            VStack(alignment: .leading, spacing: 10) {
                Picker("First", selection: comparisonFirstBinding) {
                    ForEach(measuredRegions) { annotation in
                        Text(appState.regionTitle(for: annotation)).tag(Optional(annotation.id))
                    }
                }

                Picker("Second", selection: comparisonSecondBinding) {
                    ForEach(measuredRegions) { annotation in
                        Text(appState.regionTitle(for: annotation)).tag(Optional(annotation.id))
                    }
                }

                Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 8) {
                    GridRow {
                        Button("Area Ratio") {
                            compareRegions(metric: .area, operation: .ratio)
                        }
                        Button("Area %") {
                            compareRegions(metric: .area, operation: .percentage)
                        }
                    }

                    GridRow {
                        Button("Area Difference") {
                            compareRegions(metric: .area, operation: .difference)
                        }
                        Button("Area Product") {
                            compareRegions(metric: .area, operation: .product)
                        }
                    }

                    GridRow {
                        Button("Perimeter Ratio") {
                            compareRegions(metric: .perimeter, operation: .ratio)
                        }
                        Button("Perimeter %") {
                            compareRegions(metric: .perimeter, operation: .percentage)
                        }
                    }
                }
                .buttonStyle(.bordered)

                if let comparisonResult {
                    Text(comparisonResult)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .onAppear {
                ensureComparisonSelection()
            }
            .onChange(of: measuredRegions.map(\.id)) {
                ensureComparisonSelection()
            }
        }
    }

    private var comparisonFirstBinding: Binding<UUID?> {
        Binding(
            get: { comparisonFirstID ?? measuredRegions.first?.id },
            set: { comparisonFirstID = $0 }
        )
    }

    private var comparisonSecondBinding: Binding<UUID?> {
        Binding(
            get: {
                comparisonSecondID
                    ?? measuredRegions.first { $0.id != (comparisonFirstID ?? measuredRegions.first?.id) }?.id
            },
            set: { comparisonSecondID = $0 }
        )
    }

    private var outputUnitPicker: some View {
        Picker(
            "Output Unit",
            selection: Binding(
                get: { appState.outputMeasurementUnit },
                set: { appState.outputMeasurementUnit = $0 }
            )
        ) {
            ForEach(MSMeasurementUnit.allCases) { unit in
                Text(unit.title).tag(unit)
            }
        }
    }

    private var calibrationControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Known Length")
                Spacer()

                TextField(
                    "Length",
                    value: Binding(
                        get: { appState.calibrationKnownLength },
                        set: { appState.calibrationKnownLength = $0 }
                    ),
                    format: .number
                )
                .frame(width: 80)
            }

            Picker(
                "Calibration Unit",
                selection: Binding(
                    get: { appState.calibrationUnit },
                    set: { appState.calibrationUnit = $0 }
                )
            ) {
                ForEach(MSMeasurementUnit.allCases.filter { $0 != .pixels }) { unit in
                    Text(unit.title).tag(unit)
                }
            }

            HStack {
                Button("Apply Calibration") {
                    appState.updateSelectedCalibrationValue()
                }
                .disabled(appState.selectedAnnotation?.type != .calibration)

                Button("Clear") {
                    appState.clearCalibration()
                }
                .disabled(appState.calibration == nil)
            }
        }
    }

    @ViewBuilder
    private var calibrationStatus: some View {
        if let calibration = appState.calibration,
           let millimetresPerPixel = calibration.millimetresPerPixel {
            Text(String(format: "Scale: %.5f mm/px", millimetresPerPixel))
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            Text("Draw a calibration line, select it, then enter the known distance.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private enum RegionComparisonMetric {
        case area
        case perimeter
    }

    private enum RegionComparisonOperation {
        case ratio
        case difference
        case product
        case percentage
    }

    private func ensureComparisonSelection() {
        let ids = measuredRegions.map(\.id)
        guard ids.count >= 2 else {
            comparisonFirstID = nil
            comparisonSecondID = nil
            comparisonResult = nil
            appState.latestComparisonResult = nil
            return
        }

        if comparisonFirstID == nil || !ids.contains(comparisonFirstID!) {
            comparisonFirstID = ids[0]
        }

        if comparisonSecondID == nil || comparisonSecondID == comparisonFirstID || !ids.contains(comparisonSecondID!) {
            comparisonSecondID = ids.first { $0 != comparisonFirstID }
        }
    }

    private func compareRegions(
        metric: RegionComparisonMetric,
        operation: RegionComparisonOperation
    ) {
        ensureComparisonSelection()

        guard let firstID = comparisonFirstID,
              let secondID = comparisonSecondID,
              let first = measuredRegions.first(where: { $0.id == firstID }),
              let second = measuredRegions.first(where: { $0.id == secondID }) else {
            comparisonResult = "Choose two regions to compare."
            appState.latestComparisonResult = comparisonResult
            return
        }

        let firstValue = comparisonValue(for: first, metric: metric)
        let secondValue = comparisonValue(for: second, metric: metric)
        let metricTitle = metric == .area ? "Area" : "Perimeter"

        switch operation {
        case .ratio:
            guard secondValue != 0 else {
                comparisonResult = "\(metricTitle) ratio unavailable: second value is zero."
                appState.latestComparisonResult = comparisonResult
                return
            }
            comparisonResult = String(
                format: "%@ ratio: %.3f : 1. %@",
                metricTitle,
                firstValue / secondValue,
                percentageComparisonText(firstValue: firstValue, secondValue: secondValue)
            )
        case .difference:
            comparisonResult = String(
                format: "%@ difference: %@",
                metricTitle,
                formattedComparisonValue(abs(firstValue - secondValue), metric: metric)
            )
        case .product:
            comparisonResult = String(format: "%@ product: %.3f", metricTitle, firstValue * secondValue)
        case .percentage:
            guard secondValue != 0 else {
                comparisonResult = "\(metricTitle) percentage unavailable: second value is zero."
                appState.latestComparisonResult = comparisonResult
                return
            }
            comparisonResult = "\(metricTitle): \(percentageComparisonText(firstValue: firstValue, secondValue: secondValue))"
        }

        appState.latestComparisonResult = comparisonResult
    }

    private func percentageComparisonText(firstValue: Double, secondValue: Double) -> String {
        guard secondValue != 0 else { return "Second value is zero." }

        let percentChange = ((firstValue - secondValue) / secondValue) * 100
        if abs(percentChange) < 0.05 {
            return "First is about the same as second."
        }

        let direction = percentChange > 0 ? "bigger" : "smaller"
        return String(format: "First is %.1f%% %@ than second.", abs(percentChange), direction)
    }

    private func comparisonValue(
        for annotation: MSAnnotation,
        metric: RegionComparisonMetric
    ) -> Double {
        switch metric {
        case .area:
            if let calibration = appState.calibration,
               let converted = calibration.convertedArea(
                forSquarePixels: annotation.regionAreaSquarePixels,
                to: appState.outputMeasurementUnit
               ) {
                return converted
            }
            return annotation.regionAreaSquarePixels
        case .perimeter:
            if let calibration = appState.calibration,
               let converted = calibration.convertedLength(
                forPixels: annotation.regionPerimeterPixels,
                to: appState.outputMeasurementUnit
               ) {
                return converted
            }
            return annotation.regionPerimeterPixels
        }
    }

    private func formattedComparisonValue(
        _ value: Double,
        metric: RegionComparisonMetric
    ) -> String {
        let unit = appState.calibration == nil ? "px" : appState.outputMeasurementUnit.rawValue
        switch metric {
        case .area:
            return String(format: "%.2f %@²", value, unit)
        case .perimeter:
            return String(format: "%.2f %@", value, unit)
        }
    }

    private var layersSection: some View {
        DisclosureGroup(isExpanded: $isLayersSectionExpanded) {
            VStack(spacing: 8) {
                ForEach(MSCanvasLayer.allCases) { layer in
                    layerRow(layer)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 8)
        } label: {
            Label("Layers", systemImage: "square.3.layers.3d")
        }
    }

    private var toolInstructions: String {
        switch appState.selectedTool {
        case .select:
            return "Click an object to select it. Drag the object to move it, or drag either endpoint handle to reshape it."
        case .measure:
            return "Drag from one point to another. The pixel distance updates live while you draw."
        case .calibrate:
            return "Draw over a known distance, then enter its real-world length and unit."
        case .angle:
            return "Drag from the pivot to the end of the first line. Then drag from the same pivot to the end of the second line to show the angle between them."
        case .parallelAngle:
            return "Drag the baseline. MeasureShot creates a 90° arm automatically. Then drag a separate line from the end of that arm to measure its signed angular difference from the original baseline."
        case .arrow:
            return "Drag from the arrow tail to its tip."
        case .rectangle:
            return "Drag diagonally to draw a rectangle."
        case .ellipse:
            return "Drag diagonally to draw an ellipse. Hold Shift while dragging to make a perfect circle."
        case .pen:
            return "Drag to draw a quick freehand annotation."
        case .region:
            return "Drag around an object to trace a closed measured region. MeasureShot shows its area and perimeter."
        case .text:
            return "Click the image where you want to place text."
        case .blur:
            return "Drag over the image to paint blur in real time. Adjust brush size and strength in the inspector."
        case .crop:
            return "Drag a crop edge or corner to resize it, or drag elsewhere on the image to draw a new crop box. Release to crop."
        case .colourPicker:
            return "Move over the image and click to copy the sampled colour value."
        }
    }

    private func layerRow(_ layer: MSCanvasLayer) -> some View {
        HStack(spacing: 8) {
            Button {
                appState.setLayer(layer, visible: !appState.isLayerVisible(layer))
            } label: {
                Image(systemName: appState.isLayerVisible(layer) ? "eye" : "eye.slash")
                    .frame(width: 18)
            }
            .buttonStyle(.plain)
            .help(appState.isLayerVisible(layer) ? "Hide \(layer.title)" : "Show \(layer.title)")

            Button {
                appState.selectLayer(layer)
            } label: {
                HStack {
                    Image(systemName: layer.systemImage)
                    Text(layer.title)
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if appState.activeLayer == layer {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.tint)
            }
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 4)
        .background(
            appState.activeLayer == layer
                ? Color.accentColor.opacity(0.12)
                : Color.clear
        )
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}
