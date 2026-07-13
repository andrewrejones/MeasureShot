import AppKit
import ScreenCaptureKit

@MainActor
final class CaptureManager: NSObject {
    static let shared = CaptureManager()

    enum CaptureError: LocalizedError {
        case cancelled
        case noScreen
        case displayUnavailable
        case invalidSelection

        var errorDescription: String? {
            switch self {
            case .cancelled: return "Capture cancelled"
            case .noScreen: return "No display available"
            case .displayUnavailable: return "Unable to capture this display"
            case .invalidSelection: return "Selection is too small"
            }
        }
    }

    private var completion: ((Result<NSImage, Error>) -> Void)?
    private var overlayWindow: CaptureOverlayWindow?
    private var hiddenWindows: [NSWindow] = []

    func startRegionCapture(completion: @escaping (Result<NSImage, Error>) -> Void) {
        guard overlayWindow == nil else { return }

        self.completion = completion
        hideMeasureShotWindows()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.showSelectionOverlay()
        }
    }

    private func hideMeasureShotWindows() {
        hiddenWindows = NSApplication.shared.windows.filter {
            $0.isVisible && !($0 is CaptureOverlayWindow)
        }
        hiddenWindows.forEach { $0.orderOut(nil) }
    }

    private func restoreMeasureShotWindows() {
        hiddenWindows.forEach { $0.orderFront(nil) }
        hiddenWindows.removeAll()
    }

    private func showSelectionOverlay() {
        let mouseLocation = NSEvent.mouseLocation

        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) })
                ?? NSScreen.main
                ?? NSScreen.screens.first else {
            finish(.failure(CaptureError.noScreen))
            return
        }

        let selectionView = CaptureSelectionView(
            frame: NSRect(origin: .zero, size: screen.frame.size)
        )

        selectionView.onCancel = { [weak self] in
            self?.finish(.failure(CaptureError.cancelled))
        }

        selectionView.onSelection = { [weak self] selectionRect in
            self?.capture(selectionRect: selectionRect, on: screen)
        }

        let window = CaptureOverlayWindow(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false,
            screen: screen
        )

        window.level = .screenSaver
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.contentView = selectionView
        window.makeKeyAndOrderFront(nil)

        NSApplication.shared.activate(ignoringOtherApps: true)
        overlayWindow = window
    }

    private func capture(selectionRect: CGRect, on screen: NSScreen) {
        guard selectionRect.width >= 2, selectionRect.height >= 2 else {
            finish(.failure(CaptureError.invalidSelection))
            return
        }

        dismissOverlay()

        Task {
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(
                    false,
                    onScreenWindowsOnly: true
                )

                let screenNumberKey = NSDeviceDescriptionKey("NSScreenNumber")
                let screenDisplayID = (screen.deviceDescription[screenNumberKey] as? NSNumber)?.uint32Value

                guard let screenDisplayID,
                      let display = content.displays.first(where: { $0.displayID == screenDisplayID }) else {
                    finish(.failure(CaptureError.displayUnavailable))
                    return
                }

                let filter = SCContentFilter(display: display, excludingWindows: [])
                let configuration = SCStreamConfiguration()
                configuration.sourceRect = selectionRect
                configuration.width = max(
                    1,
                    Int(selectionRect.width * screen.backingScaleFactor)
                )
                configuration.height = max(
                    1,
                    Int(selectionRect.height * screen.backingScaleFactor)
                )
                configuration.showsCursor = false

                let cgImage = try await SCScreenshotManager.captureImage(
                    contentFilter: filter,
                    configuration: configuration
                )

                let image = NSImage(
                    cgImage: cgImage,
                    size: NSSize(
                        width: cgImage.width,
                        height: cgImage.height
                    )
                )

                finish(.success(image))
            } catch {
                finish(.failure(error))
            }
        }
    }

    private func dismissOverlay() {
        guard let overlayWindow else { return }

        overlayWindow.contentView = nil
        overlayWindow.orderOut(nil)
        overlayWindow.close()
        self.overlayWindow = nil
    }

    private func finish(_ result: Result<NSImage, Error>) {
        dismissOverlay()
        restoreMeasureShotWindows()

        let callback = completion
        completion = nil
        callback?(result)
    }
}

final class CaptureOverlayWindow: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class CaptureSelectionView: NSView {
    var onSelection: ((CGRect) -> Void)?
    var onCancel: (() -> Void)?

    private var dragStart: CGPoint?
    private var dragCurrent: CGPoint?

    override var acceptsFirstResponder: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onCancel?()
        } else {
            super.keyDown(with: event)
        }
    }

    override func mouseDown(with event: NSEvent) {
        dragStart = convert(event.locationInWindow, from: nil)
        dragCurrent = dragStart
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        dragCurrent = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard let dragStart else { return }

        dragCurrent = convert(event.locationInWindow, from: nil)

        let localRect = normalizedRect(
            from: dragStart,
            to: dragCurrent ?? dragStart
        )

        let sourceRect = CGRect(
            x: localRect.minX,
            y: bounds.height - localRect.maxY,
            width: localRect.width,
            height: localRect.height
        )

        window?.ignoresMouseEvents = true
        onSelection?(sourceRect)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        NSColor.black.withAlphaComponent(0.35).setFill()
        bounds.fill()

        guard let dragStart, let dragCurrent else { return }

        let selection = normalizedRect(from: dragStart, to: dragCurrent)

        NSGraphicsContext.current?.saveGraphicsState()
        NSGraphicsContext.current?.compositingOperation = .copy
        NSColor.clear.setFill()
        selection.fill()
        NSGraphicsContext.current?.restoreGraphicsState()

        NSColor.white.setStroke()
        let border = NSBezierPath(rect: selection)
        border.lineWidth = 1
        border.stroke()

        let label = "\(Int(selection.width)) × \(Int(selection.height))"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.white,
            .backgroundColor: NSColor.black.withAlphaComponent(0.65)
        ]
        let text = NSAttributedString(
            string: "  \(label)  ",
            attributes: attributes
        )
        text.draw(
            at: CGPoint(
                x: selection.minX,
                y: max(0, selection.minY - 22)
            )
        )
    }

    private func normalizedRect(from first: CGPoint, to second: CGPoint) -> CGRect {
        CGRect(
            x: min(first.x, second.x),
            y: min(first.y, second.y),
            width: abs(second.x - first.x),
            height: abs(second.y - first.y)
        )
    }
}
