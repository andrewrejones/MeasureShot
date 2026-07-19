import SwiftUI

struct SideBySideComparisonView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(spacing: 12) {
            header

            HSplitView {
                comparisonPane(slot: .left)
                    .frame(minWidth: 260, maxWidth: .infinity, maxHeight: .infinity)

                comparisonPane(slot: .right)
                    .frame(minWidth: 260, maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(12)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            appState.prepareSideBySideComparison()
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Label("Side-by-side comparison", systemImage: "rectangle.split.2x1")
                .font(.headline)

            Spacer()

            Button {
                appState.exportSideBySideComparison()
            } label: {
                Label("Export Comparison", systemImage: "square.and.arrow.down")
            }
            .disabled(appState.sideBySideRenderedImage(for: .left) == nil || appState.sideBySideRenderedImage(for: .right) == nil)
        }
    }

    private func comparisonPane(slot: MSSideBySideSlot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(slot == .left ? "Left" : "Right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(appState.sideBySideTitle(for: slot))
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer()

                Button {
                    appState.selectSideBySideSlot(slot)
                } label: {
                    Label("Edit", systemImage: "cursorarrow")
                }
                .disabled(appState.sideBySideRenderedImage(for: slot) == nil)
            }

            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(nsColor: .controlBackgroundColor))

                if let image = appState.sideBySideRenderedImage(for: slot) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .padding(10)
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "photo")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                        Text(slot == .left ? "Add the first image" : "Add the second image")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(appState.selectedScreenshotID == selectedID(for: slot) ? Color.accentColor : Color.secondary.opacity(0.25), lineWidth: appState.selectedScreenshotID == selectedID(for: slot) ? 2 : 1)
            )
            .onTapGesture {
                appState.selectSideBySideSlot(slot)
            }

            Text(appState.sideBySideDetailText(for: slot))
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Button {
                    appState.captureSideBySideImage(for: slot)
                } label: {
                    Label("Capture", systemImage: "camera.viewfinder")
                }

                Button {
                    appState.insertSideBySideImage(for: slot)
                } label: {
                    Label("Insert", systemImage: "photo.badge.plus")
                }
            }
            .controlSize(.small)
        }
        .padding(12)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func selectedID(for slot: MSSideBySideSlot) -> UUID? {
        switch slot {
        case .left:
            return appState.sideBySideLeftScreenshotID
        case .right:
            return appState.sideBySideRightScreenshotID
        }
    }
}
