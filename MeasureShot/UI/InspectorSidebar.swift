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

private struct ComputationMetricChoice: Identifiable, Hashable {
    let id: String
    let title: String
}

struct InspectorSidebar: View {
    @Environment(AppState.self) private var appState
    @AppStorage("inspector.imageSectionExpanded") private var isImageSectionExpanded = true
    @AppStorage("inspector.appearanceSectionExpanded") private var isAppearanceSectionExpanded = true
    @AppStorage("inspector.layersSectionExpanded") private var isLayersSectionExpanded = true
    @AppStorage("inspector.equationBuilderExpanded") private var isEquationBuilderExpanded = true
    @AppStorage("inspector.exportHistoryExpanded") private var isExportHistoryExpanded = false
    @State private var comparisonFirstID: UUID?
    @State private var comparisonSecondID: UUID?
    @State private var comparisonResult: String?
    @State private var computationName = "Custom computation"
    @State private var computationExpression = ""
    @State private var selectedValueOneSourceID: String?
    @State private var selectedValueOneMetricID = "area"
    @State private var selectedValueTwoSourceID: String?
    @State private var selectedValueTwoMetricID = "area"

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

    private var measuredItems: [MSAnnotation] {
        appState.measuredItems()
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

                if appState.isTraceInProgress {
                    traceControlsSection
                }

                if !measuredItems.isEmpty {
                    measuredItemsSection
                }

                if measuredRegions.count >= 2 {
                    regionComparisonSection
                }

                if !appState.computationVariables().isEmpty {
                    computationBuilderSection
                }

                if shouldShowTextPanel {
                    textSection
                }

                if shouldShowBlurPanel {
                    blurSection
                }

                if shouldShowColourPickerPanel {
                    colourPickerSection
                }

                if appState.imageDocument != nil {
                    imageAdjustmentsSection
                }

                appearanceSection

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
                        .textSelection(.enabled)

                    Button {
                        appState.copySampledHex()
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .buttonStyle(.borderless)
                    .help("Copy HEX")
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

    private var traceControlsSection: some View {
        GroupBox("Trace") {
            HStack(spacing: 8) {
                Button {
                    appState.finishTrace()
                } label: {
                    Label("Finish Trace", systemImage: "checkmark")
                }

                Button(role: .cancel) {
                    appState.cancelTrace()
                } label: {
                    Label("Cancel", systemImage: "xmark")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var measuredItemsSection: some View {
        GroupBox("Measured Items") {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(measuredItems.enumerated()), id: \.element.id) { _, annotation in
                    measuredItemRow(annotation)

                    if annotation.id != measuredItems.last?.id {
                        Divider()
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func measuredItemRow(_ annotation: MSAnnotation) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("\(appState.compactMeasuredItemTitle(for: annotation)):")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 42, alignment: .leading)

                TextField(
                    "Measurement name",
                    text: Binding(
                        get: { appState.measuredItemTitle(for: annotation) },
                        set: { appState.updateMeasuredItemTitle(id: annotation.id, title: $0) }
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
                .help("Select \(appState.measuredItemTitle(for: annotation))")

                Button(role: .destructive) {
                    appState.deleteAnnotation(id: annotation.id)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help("Delete \(appState.measuredItemTitle(for: annotation))")
            }

            if annotation.isMeasuredRegion {
                ForEach(
                    annotation.regionMeasurementLines(
                        calibration: appState.calibration,
                        outputUnit: appState.outputMeasurementUnit
                    ),
                    id: \.self
                ) { line in
                    measuredItemDetail(line)
                }

                if let averageColor = appState.averageColor(for: annotation) {
                    Divider()

                    measuredItemDetail("Average HEX: \(averageColor.hex)")
                        .textSelection(.enabled)

                    measuredItemDetail("Average RGB: \(averageColor.rgb)")
                        .textSelection(.enabled)
                }
            } else {
                measuredItemDetail(appState.measurementText(for: annotation))
            }
        }
    }

    private func measuredItemDetail(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var exportHistorySection: some View {
        DisclosureGroup(isExpanded: $isExportHistoryExpanded) {
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
            .padding(.top, 8)
        } label: {
            HStack {
                Label("Export History", systemImage: "clock.arrow.circlepath")
                Spacer()
                Text("\(appState.exportHistory.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
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
        GroupBox("Quick Computations") {
            VStack(alignment: .leading, spacing: 10) {
                Picker("First", selection: comparisonFirstBinding) {
                    ForEach(measuredRegions) { annotation in
                        Text(appState.inspectorRegionTitle(for: annotation)).tag(Optional(annotation.id))
                    }
                }

                Picker("Second", selection: comparisonSecondBinding) {
                    ForEach(measuredRegions) { annotation in
                        Text(appState.inspectorRegionTitle(for: annotation)).tag(Optional(annotation.id))
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

    private var computationVariables: [MSComputationVariable] {
        appState.computationVariables()
    }

    private var computationBuilderSection: some View {
        DisclosureGroup(isExpanded: $isEquationBuilderExpanded) {
            VStack(alignment: .leading, spacing: 10) {
                TextField("Result name", text: $computationName)
                    .textFieldStyle(.roundedBorder)

                computationValuePicker(
                    title: "Value 1",
                    sourceID: $selectedValueOneSourceID,
                    metricID: $selectedValueOneMetricID
                )

                computationValuePicker(
                    title: "Value 2",
                    sourceID: $selectedValueTwoSourceID,
                    metricID: $selectedValueTwoMetricID
                )

                TextField("Equation", text: $computationExpression, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .lineLimit(2...4)

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 6) {
                    ForEach(["+", "-", "×", "÷", "(", ")", "0.5", "100"], id: \.self) { token in
                        Button(token) {
                            appendComputationToken(token)
                        }
                        .buttonStyle(.bordered)
                    }
                }

                computationPreview

                HStack {
                    Button("Save Result") {
                        saveCurrentComputation()
                    }
                    .disabled(currentComputationValue == nil)

                    Button("Clear") {
                        computationExpression = ""
                    }
                    .disabled(computationExpression.isEmpty)
                }

                if !appState.computationResults.isEmpty {
                    Divider()

                    HStack {
                        Text("Saved")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Clear All") {
                            appState.clearComputationResults()
                        }
                        .font(.caption)
                    }

                    ForEach(appState.computationResults) { result in
                        HStack(alignment: .top, spacing: 8) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(result.name): \(result.formattedValue)")
                                    .font(.caption.weight(.semibold))
                                Text(result.expression)
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }

                            Spacer()

                            Button(role: .destructive) {
                                appState.deleteComputationResult(id: result.id)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 8)
            .onAppear {
                ensureComputationValueSelections()
            }
            .onChange(of: computationVariables.map(\.id)) {
                ensureComputationValueSelections()
            }
        } label: {
            Label("Equation Builder", systemImage: "function")
        }
    }

    private func computationValuePicker(
        title: String,
        sourceID: Binding<String?>,
        metricID: Binding<String>
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Picker("Source", selection: sourceID) {
                ForEach(computationSourceChoices) { source in
                    Text(source.title).tag(Optional(source.id))
                }
            }

            Picker("Measurement", selection: metricID) {
                ForEach(computationMetricChoices(for: sourceID.wrappedValue)) { metric in
                    Text(metric.title).tag(metric.id)
                }
            }

            Button("Insert \(title)") {
                insertComputationValue(sourceID: sourceID.wrappedValue, metricID: metricID.wrappedValue)
            }
            .disabled(computationVariableID(sourceID: sourceID.wrappedValue, metricID: metricID.wrappedValue) == nil)
        }
    }

    @ViewBuilder
    private var computationPreview: some View {
        if computationExpression.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Text("Choose values and operators to build a calculation.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } else if let currentComputationValue {
            Text(String(format: "Live result: %.4f", currentComputationValue))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
                .textSelection(.enabled)
        } else if let error = currentComputationError {
            Text(error)
                .font(.caption)
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var currentComputationValue: Double? {
        try? MSFormulaEvaluator.evaluate(
            expression: computationExpression,
            variables: computationVariableValues
        )
    }

    private var currentComputationError: String? {
        do {
            _ = try MSFormulaEvaluator.evaluate(
                expression: computationExpression,
                variables: computationVariableValues
            )
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    private var computationVariableValues: [String: Double] {
        Dictionary(uniqueKeysWithValues: computationVariables.map { ($0.id, $0.value) })
    }

    private var computationSourceChoices: [ComputationMetricChoice] {
        var seen = Set<String>()
        return computationVariables.compactMap { variable in
            guard !seen.contains(variable.sourceID) else { return nil }
            seen.insert(variable.sourceID)
            return ComputationMetricChoice(id: variable.sourceID, title: variable.sourceTitle)
        }
    }

    private func ensureComputationValueSelections() {
        let sourceIDs = computationSourceChoices.map(\.id)
        guard !sourceIDs.isEmpty else {
            selectedValueOneSourceID = nil
            selectedValueTwoSourceID = nil
            return
        }

        if selectedValueOneSourceID == nil || !sourceIDs.contains(selectedValueOneSourceID!) {
            selectedValueOneSourceID = sourceIDs[0]
        }

        if selectedValueTwoSourceID == nil || !sourceIDs.contains(selectedValueTwoSourceID!) {
            selectedValueTwoSourceID = sourceIDs.count > 1 ? sourceIDs[1] : sourceIDs[0]
        }

        selectedValueOneMetricID = validMetricID(selectedValueOneMetricID, for: selectedValueOneSourceID)
        selectedValueTwoMetricID = validMetricID(selectedValueTwoMetricID, for: selectedValueTwoSourceID)
    }

    private func computationMetricChoices(for sourceID: String?) -> [ComputationMetricChoice] {
        guard let sourceID else { return [] }

        return computationVariables
            .filter { $0.sourceID == sourceID }
            .map { variable in
                ComputationMetricChoice(id: variable.metricID, title: "\(variable.metricTitle) (\(variable.unit))")
            }
    }

    private func validMetricID(_ metricID: String, for sourceID: String?) -> String {
        let choices = computationMetricChoices(for: sourceID)
        if choices.contains(where: { $0.id == metricID }) {
            return metricID
        }

        return choices.first?.id ?? "area"
    }

    private func insertComputationValue(sourceID: String?, metricID: String) {
        guard let variableID = computationVariableID(sourceID: sourceID, metricID: metricID) else { return }
        appendComputationToken(variableID)
    }

    private func computationVariableID(sourceID: String?, metricID: String) -> String? {
        guard let sourceID else { return nil }
        let validMetricID = validMetricID(metricID, for: sourceID)
        return computationVariables.first {
            $0.sourceID == sourceID && $0.metricID == validMetricID
        }?.id
    }

    private func appendComputationToken(_ token: String) {
        if computationExpression.isEmpty {
            computationExpression = token
        } else {
            computationExpression += " \(token)"
        }
    }

    private func saveCurrentComputation() {
        guard let value = currentComputationValue else { return }
        appState.addComputationResult(
            name: computationName,
            expression: computationExpression,
            value: value
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
            return "Drag diagonally to draw a rectangle. Hold Shift while dragging to make a perfect square."
        case .ellipse:
            return "Drag diagonally to draw an ellipse. Hold Shift while dragging to make a perfect circle."
        case .pen:
            return "Drag to draw a quick freehand annotation."
        case .region:
            return "Drag around an object to trace a closed measured region. MeasureShot shows its area and perimeter."
        case .trace:
            return "Click along an edge to add snapped trace points. Click near the start to close it into a measured region, or use Finish Trace to keep it open."
        case .text:
            return "Click the image where you want to place text."
        case .blur:
            return "Drag over the image to paint blur in real time. Adjust brush size and strength in the inspector."
        case .crop:
            return "Drag a crop edge or corner to resize it, or drag elsewhere on the image to draw a new crop box. Release to crop."
        case .colourPicker:
            return "Move over the image and click to copy the sampled colour value."
        case .sideBySide:
            return "Compare two screenshot tabs side by side. Select a pane to make that image active for editing and measurements."
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
