import SwiftUI
import CoreImage

struct ToolSidebar: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Tools")
                .font(.headline)
                .padding(.horizontal, 12)
                .padding(.top, 12)

            ScrollView {
                VStack(spacing: 4) {
                    ForEach(MSToolType.allCases.filter { $0 != .crop }) { tool in
                        Button {
                            appState.selectedTool = tool
                            appState.cancelAnnotation()
                            appState.resetAngleCreation()
                            appState.statusMessage = "Selected \(tool.title)"
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: tool.systemImage)
                                    .frame(width: 20)

                                Text(tool.title)

                                Spacer()
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .background(
                            appState.selectedTool == tool
                                ? Color.accentColor.opacity(0.16)
                                : Color.clear
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                    }
                }
                .padding(.horizontal, 8)
            }

            Spacer()
        }
        .background(.thinMaterial)
    }
}
