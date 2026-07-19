//
//  EditorView.swift
//  MeasureShot
//
//  Created by Andrew Jones on 7/13/26.
//

import SwiftUI
import CoreImage

struct EditorView: View {
    @Environment(AppState.self) private var appState
    @State private var editingTabID: UUID?
    @State private var editingTabTitle = ""
    @State private var isShowingExportPreview = false

    var body: some View {
        VStack(spacing: 0) {
            topToolbar
            if !appState.screenshotTabs.isEmpty {
                screenshotTabBar
            }
            Divider()

            HSplitView {
                ToolSidebar()
                    .environment(appState)
                    .frame(minWidth: 150, idealWidth: 170, maxWidth: 210)

                Group {
                    if appState.selectedTool == .sideBySide {
                        SideBySideComparisonView()
                            .environment(appState)
                    } else {
                        EditorCanvas()
                            .environment(appState)
                    }
                }
                .frame(minWidth: 500, maxWidth: .infinity, maxHeight: .infinity)

                InspectorSidebar()
                    .environment(appState)
                    .frame(minWidth: 220, idealWidth: 250, maxWidth: 300)
            }

            Divider()
            statusBar
        }
        .frame(minWidth: 980, minHeight: 680)
        .sheet(isPresented: $isShowingExportPreview) {
            ExportPreviewSheet()
                .environment(appState)
        }
    }

    private var topToolbar: some View {
        VStack(spacing: 4) {
            HStack(spacing: 10) {
                Button {
                    appState.startCapture()
                } label: {
                    ToolbarIconLabel("Capture", systemImage: "camera.viewfinder")
                }

                Button {
                    appState.insertImage()
                } label: {
                    ToolbarIconLabel("Insert", systemImage: "photo.badge.plus")
                }

                Button {
                    appState.createBlankTab()
                } label: {
                    ToolbarIconLabel("New Tab", systemImage: "plus.rectangle.on.rectangle")
                }

                Button(role: .destructive) {
                    appState.clearImage()
                } label: {
                    ToolbarIconLabel("Clear", systemImage: "xmark.rectangle")
                }
                .disabled(appState.imageDocument == nil)

                Divider()
                    .frame(height: 20)

                Button {
                    appState.copyImage()
                } label: {
                    ToolbarIconLabel("Copy", systemImage: "doc.on.doc")
                }
                .disabled(appState.imageDocument == nil)

                Button {
                    appState.saveImage()
                } label: {
                    ToolbarIconLabel("Save", systemImage: "square.and.arrow.down")
                }
                .disabled(appState.imageDocument == nil)

                Button {
                    appState.shareImage()
                } label: {
                    ToolbarIconLabel("Share", systemImage: "square.and.arrow.up")
                }
                .disabled(appState.imageDocument == nil)

                Menu {
                    Button {
                        isShowingExportPreview = true
                    } label: {
                        Label("Preview Export...", systemImage: "eye")
                    }

                    Divider()

                    ForEach(MSExportOption.allCases) { option in
                        Button {
                            appState.export(option: option)
                        } label: {
                            Label(option.title, systemImage: option.systemImage)
                        }
                    }
                } label: {
                    ToolbarIconLabel("Export", systemImage: "square.and.arrow.down.on.square")
                }
                .disabled(appState.imageDocument == nil)

                Divider()
                    .frame(height: 20)

                Button {
                    appState.undo()
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                }
                .help("Undo")
                .keyboardShortcut("z", modifiers: [.command])

                Button {
                    appState.redo()
                } label: {
                    Image(systemName: "arrow.uturn.forward")
                }
                .help("Redo")
                .keyboardShortcut("z", modifiers: [.command, .shift])

                Button(role: .destructive) {
                    appState.clearAllAnnotations()
                } label: {
                    ToolbarIconLabel("Clear All", systemImage: "trash")
                }
                .disabled(appState.annotations.isEmpty)

                Divider()
                    .frame(height: 20)

                Button {
                    appState.zoomOut()
                } label: {
                    Image(systemName: "minus.magnifyingglass")
                }
                .help("Zoom Out")
                .disabled(appState.imageDocument == nil)

                Button {
                    appState.zoomToActualSize()
                } label: {
                    Text("100%")
                }
                .help("Actual Size")
                .disabled(appState.imageDocument == nil)

                Button {
                    appState.zoomIn()
                } label: {
                    Image(systemName: "plus.magnifyingglass")
                }
                .help("Zoom In")
                .disabled(appState.imageDocument == nil)

                Button {
                    appState.zoomToFit()
                } label: {
                    ToolbarIconLabel("Fit", systemImage: "arrow.up.left.and.arrow.down.right")
                }
                .disabled(appState.imageDocument == nil)

                Spacer()
            }

            HStack(spacing: 10) {
                Button {
                    appState.rotateImageClockwise()
                } label: {
                    ToolbarIconLabel("Rotate", systemImage: "rotate.right")
                }
                .help("Rotate 90° Clockwise")
                .disabled(appState.imageDocument == nil)

                Button {
                    appState.resetImageRotation()
                } label: {
                    ToolbarIconLabel("Reset", systemImage: "rotate.3d")
                }
                .help("Reset Rotation")
                .disabled(appState.imageDocument == nil)

                Stepper(value: rotationDegreesBinding, in: -180...180, step: 1) {
                    HStack(spacing: 4) {
                        Image(systemName: "angle")

                        TextField("Degrees", value: rotationDegreesBinding, format: .number.precision(.fractionLength(0)))
                            .frame(width: 44)
                            .multilineTextAlignment(.trailing)

                        Text("°")
                    }
                }
                .frame(width: 132)
                .disabled(appState.imageDocument == nil)

                Button {
                    appState.flipImageHorizontally()
                } label: {
                    ToolbarIconLabel("Flip H", systemImage: "arrow.left.and.right")
                }
                .help("Flip Horizontally")
                .disabled(appState.imageDocument == nil)

                Button {
                    appState.flipImageVertically()
                } label: {
                    ToolbarIconLabel("Flip V", systemImage: "arrow.up.and.down")
                }
                .help("Flip Vertically")
                .disabled(appState.imageDocument == nil)

                Divider()
                    .frame(height: 20)

                Button {
                    appState.selectCropTool()
                } label: {
                    ToolbarIconLabel("Crop", systemImage: "crop")
                }
                .help("Crop Image")
                .disabled(appState.imageDocument == nil)

                Button {
                    appState.resetImageCrop()
                } label: {
                    ToolbarIconLabel("Uncrop", systemImage: "crop.rotate")
                }
                .help("Reset Crop")
                .disabled(appState.imageDocument?.cropRect == nil)

                Spacer()
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    private var rotationDegreesBinding: Binding<Double> {
        Binding(
            get: { appState.imageDocument?.freeRotationDegrees ?? 0 },
            set: { appState.setFreeRotationDegrees($0) }
        )
    }

    private var screenshotTabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(appState.screenshotTabs) { tab in
                    HStack(spacing: 6) {
                        HStack(spacing: 6) {
                            Button {
                                appState.selectScreenshotTab(id: tab.id)
                            } label: {
                                Image(systemName: "photo")
                            }
                            .buttonStyle(.plain)

                            if editingTabID == tab.id {
                                TextField(
                                    "Tab name",
                                    text: $editingTabTitle
                                )
                                .textFieldStyle(.plain)
                                .frame(width: 110)
                                .onSubmit {
                                    commitTabRename(id: tab.id)
                                }
                            } else {
                                Button {
                                    appState.selectScreenshotTab(id: tab.id)
                                } label: {
                                    Text(tab.title)
                                        .lineLimit(1)
                                        .frame(width: 110, alignment: .leading)
                                }
                                .buttonStyle(.plain)
                            }

                            Button {
                                if editingTabID == tab.id {
                                    commitTabRename(id: tab.id)
                                } else {
                                    editingTabID = tab.id
                                    editingTabTitle = tab.title
                                    appState.selectScreenshotTab(id: tab.id)
                                }
                            } label: {
                                Image(systemName: editingTabID == tab.id ? "checkmark" : "pencil")
                                    .font(.system(size: 10, weight: .semibold))
                                    .frame(width: 16, height: 16)
                            }
                            .buttonStyle(.plain)
                            .help(editingTabID == tab.id ? "Done Renaming" : "Rename Tab")
                        }
                        .padding(.leading, 8)
                        .padding(.vertical, 5)

                        Button {
                            appState.closeScreenshotTab(id: tab.id)
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 10, weight: .semibold))
                                .frame(width: 16, height: 16)
                        }
                        .buttonStyle(.plain)
                        .help("Close Screenshot")
                    }
                    .padding(.trailing, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 7)
                            .fill(tab.isSelected ? Color.accentColor.opacity(0.18) : Color(nsColor: .controlBackgroundColor))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 7)
                            .stroke(tab.isSelected ? Color.accentColor.opacity(0.45) : Color.secondary.opacity(0.2))
                    )
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
        .background(.thinMaterial)
    }

    private func commitTabRename(id: UUID) {
        appState.renameScreenshotTab(id: id, title: editingTabTitle)
        editingTabID = nil
        editingTabTitle = ""
    }

    private var statusBar: some View {
        HStack {
            Text(appState.statusMessage)
                .foregroundStyle(.secondary)

            Spacer()

            Text("Layer: \(appState.activeLayer.title)")
                .foregroundStyle(.secondary)

            Divider()
                .frame(height: 12)

            Text(appState.isFitToWindow ? "Fit" : "\(Int(appState.zoomScale * 100))%")
                .foregroundStyle(.secondary)

            if let imageDocument = appState.imageDocument {
                let image = ImageRenderer.render(document: imageDocument)

                Divider()
                    .frame(height: 12)

                Text("\(Int(image.size.width)) × \(Int(image.size.height)) px")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.caption)
        .padding(.horizontal, 12)
        .frame(height: 28)
    }
}

private struct ExportPreviewSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var selectedOption: MSExportOption = .standard

    private var previewOptions: [MSExportOption] {
        MSExportOption.allCases.filter { $0 != .annotationsCSV }
    }

    private var previewImage: NSImage? {
        appState.exportPreviewImage(for: selectedOption)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Picker("Export Type", selection: $selectedOption) {
                    ForEach(previewOptions) { option in
                        Label(option.title, systemImage: option.systemImage)
                            .tag(option)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 240)

                Spacer()

                Button("Cancel") {
                    dismiss()
                }

                Button {
                    appState.export(option: selectedOption)
                } label: {
                    Label("Save", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.borderedProminent)
            }

            if let previewImage {
                ScrollView([.horizontal, .vertical]) {
                    Image(nsImage: previewImage)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .frame(maxWidth: 760, maxHeight: 520)
                        .padding(16)
                }
                .frame(width: 820, height: 560)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                ContentUnavailableView(
                    "No Preview",
                    systemImage: "eye.slash",
                    description: Text("This export type does not produce an image preview.")
                )
                .frame(width: 820, height: 560)
            }
        }
        .padding(18)
        .frame(width: 860)
    }
}

private struct ToolbarIconLabel: View {
    let title: String
    let systemImage: String

    init(_ title: String, systemImage: String) {
        self.title = title
        self.systemImage = systemImage
    }

    var body: some View {
        VStack(spacing: 2) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .medium))
                .frame(height: 16)

            Text(title)
                .font(.caption2)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(width: 54, height: 38)
        .contentShape(Rectangle())
    }
}

#Preview {
    EditorView()
        .environment(AppState())
}
