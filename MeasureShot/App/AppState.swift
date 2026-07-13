import AppKit
import Observation
import UniformTypeIdentifiers

@MainActor
@Observable
final class AppState {
    var currentImage: NSImage?
    var selectedTool: MSToolType = .select
    var statusMessage = "Ready"
    var isCapturing = false

    func startCapture() {
        guard !isCapturing else { return }

        isCapturing = true
        statusMessage = "Select a region to capture"

        CaptureManager.shared.startRegionCapture { [weak self] result in
            guard let self else { return }

            self.isCapturing = false

            switch result {
            case .success(let image):
                self.currentImage = image
                self.selectedTool = .select
                self.statusMessage = "Capture complete"
                self.showEditor()

            case .failure(let error):
                if case CaptureManager.CaptureError.cancelled = error {
                    self.statusMessage = "Capture cancelled"
                } else {
                    self.statusMessage = error.localizedDescription
                }
                self.showEditor()
            }
        }
    }

    func showEditor() {
        NSApplication.shared.activate(ignoringOtherApps: true)

        for window in NSApplication.shared.windows where window.canBecomeMain {
            window.makeKeyAndOrderFront(nil)
        }
    }

    func copyImage() {
        guard let currentImage else {
            statusMessage = "Nothing to copy"
            return
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([currentImage])
        statusMessage = "Copied to clipboard"
    }

    func saveImage() {
        guard let currentImage,
              let tiffData = currentImage.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            statusMessage = "Nothing to save"
            return
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "MeasureShot.png"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try pngData.write(to: url, options: .atomic)
            statusMessage = "Saved \(url.lastPathComponent)"
        } catch {
            statusMessage = "Save failed: \(error.localizedDescription)"
        }
    }

    func shareImage() {
        guard let currentImage else {
            statusMessage = "Nothing to share"
            return
        }

        guard let window = NSApplication.shared.keyWindow,
              let contentView = window.contentView else {
            statusMessage = "Unable to open share menu"
            return
        }

        let picker = NSSharingServicePicker(items: [currentImage])
        picker.show(
            relativeTo: contentView.bounds,
            of: contentView,
            preferredEdge: .minY
        )
    }
}
