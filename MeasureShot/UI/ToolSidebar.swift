import SwiftUI

private let sidebarHistoryDateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .short
    return formatter
}()

struct ToolSidebar: View {
    @Environment(AppState.self) private var appState
    @AppStorage("sidebar.historyBrowserExpanded") private var isHistoryBrowserExpanded = false
    @State private var exportHistoryRange: MSExportHistoryRange = .today
    @State private var exportHistoryDate = Date()

    private var filteredHistoryItems: [MSExportHistoryItem] {
        appState.exportHistoryItems(
            for: exportHistoryRange,
            selectedDate: exportHistoryDate
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Tools")
                .font(.headline)
                .padding(.horizontal, 12)
                .padding(.top, 12)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    toolList

                    if !appState.exportHistory.isEmpty {
                        Divider()
                        historyBrowser
                    }
                }
                .padding(.horizontal, 8)
            }

            Spacer()
        }
        .background(.thinMaterial)
    }

    private var toolList: some View {
        VStack(spacing: 4) {
            ForEach(MSToolType.allCases.filter { $0 != .crop }) { tool in
                Button {
                    appState.cancelAnnotation()
                    appState.resetAngleCreation()
                    if tool == .sideBySide {
                        appState.prepareSideBySideComparison()
                    } else {
                        appState.selectedTool = tool
                        appState.statusMessage = "Selected \(tool.title)"
                    }
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
    }

    private var historyBrowser: some View {
        DisclosureGroup(isExpanded: $isHistoryBrowserExpanded) {
            VStack(alignment: .leading, spacing: 10) {
                Picker("Range", selection: $exportHistoryRange) {
                    ForEach(MSExportHistoryRange.allCases) { range in
                        Text(range.title).tag(range)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()

                if exportHistoryRange == .customDay {
                    DatePicker(
                        "Date",
                        selection: $exportHistoryDate,
                        displayedComponents: [.date]
                    )
                    .datePickerStyle(.compact)
                    .labelsHidden()
                }

                if filteredHistoryItems.isEmpty {
                    Text("No exports in this range.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 4)
                } else {
                    VStack(spacing: 8) {
                        ForEach(filteredHistoryItems) { item in
                            historyRow(item)
                        }
                    }
                }
            }
            .padding(.top, 8)
        } label: {
            HStack {
                Label("History", systemImage: "clock.arrow.circlepath")
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Spacer()

                Text("\(appState.exportHistory.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func historyRow(_ item: MSExportHistoryItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                appState.openExportHistoryItem(id: item.id)
            } label: {
                Image(nsImage: item.image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
                    .frame(height: 78)
                    .background(Color(nsColor: .windowBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                    .overlay(
                        RoundedRectangle(cornerRadius: 5)
                            .stroke(.secondary.opacity(0.28))
                    )
            }
            .buttonStyle(.plain)
            .help("Open this export in a new tab")

            HStack(spacing: 6) {
                Image(systemName: item.action.systemImage)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.action.title)
                        .fontWeight(.medium)
                    Text(sidebarHistoryDateFormatter.string(from: item.createdAt))
                        .foregroundStyle(.secondary)
                    Text(item.dimensionsText)
                        .foregroundStyle(.secondary)
                }
                .lineLimit(1)
                .truncationMode(.middle)

                Spacer(minLength: 0)

                Button {
                    appState.copyExportHistoryItem(id: item.id)
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .help("Copy this export")
            }
            .font(.caption)
        }
        .padding(6)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: 7))
    }
}
