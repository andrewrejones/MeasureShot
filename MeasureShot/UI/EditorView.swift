//
//  EditorView.swift
//  MeasureShot
//
//  Created by Andrew Jones on 7/13/26.
//

import SwiftUI

struct EditorView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(spacing: 0) {
            toolbar

            Divider()

            Group {
                if let image = appState.currentImage {
                    GeometryReader { geometry in
                        Image(nsImage: image)
                            .resizable()
                            .interpolation(.high)
                            .aspectRatio(contentMode: .fit)
                            .frame(
                                width: max(0, geometry.size.width - 48),
                                height: max(0, geometry.size.height - 48)
                            )
                            .frame(
                                maxWidth: .infinity,
                                maxHeight: .infinity,
                                alignment: .center
                            )
                            .padding(24)
                    }
                } else {
                    ContentUnavailableView(
                        "No Capture",
                        systemImage: "camera.viewfinder",
                        description: Text("Click Capture or press ⌘⌥⇧4 to take a screenshot.")
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            HStack {
                Text(appState.statusMessage)
                    .foregroundStyle(.secondary)

                Spacer()

                if let image = appState.currentImage {
                    Text("\(Int(image.size.width)) × \(Int(image.size.height)) px")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.caption)
            .padding(.horizontal, 12)
            .frame(height: 28)
        }
        .frame(minWidth: 900, minHeight: 620)
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            Button {
                appState.startCapture()
            } label: {
                Label("Capture", systemImage: "camera.viewfinder")
            }

            Divider()
                .frame(height: 20)

            Button {
                appState.copyImage()
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }
            .disabled(appState.currentImage == nil)

            Button {
                appState.saveImage()
            } label: {
                Label("Save", systemImage: "square.and.arrow.down")
            }
            .disabled(appState.currentImage == nil)

            Button {
                appState.shareImage()
            } label: {
                Label("Share", systemImage: "square.and.arrow.up")
            }
            .disabled(appState.currentImage == nil)

            Spacer()
        }
        .buttonStyle(.bordered)
        .padding(10)
    }
}

#Preview {
    EditorView()
        .environment(AppState())
}
