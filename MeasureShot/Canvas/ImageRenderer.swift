//
//  ImageRenderer.swift
//  MeasureShot
//
//  Created by Andrew Jones on 7/16/26.
//

import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins

/// Responsible for producing the image displayed in the editor.
/// Image edits are derived from the document's original image.
enum ImageRenderer {

    private static let ciContext = CIContext(options: nil)

    static func render(document: ImageDocument) -> NSImage {
        let inputImage = document.originalImage
        let inputSize = inputImage.size
        let rotationDegrees = document.totalRotationDegrees
        let hasRotation = !rotationDegrees.isAlmostZero
        let hasFlip = document.isFlippedHorizontally || document.isFlippedVertically

        let transformedImage: NSImage
        if hasRotation || hasFlip {
            let outputSize = rotatedBoundingSize(for: inputSize, degrees: rotationDegrees)
            transformedImage = NSImage(size: outputSize)

            transformedImage.lockFocus()
            NSGraphicsContext.current?.imageInterpolation = .high

            let transform = NSAffineTransform()
            transform.translateX(by: outputSize.width / 2, yBy: outputSize.height / 2)
            transform.rotate(byDegrees: -rotationDegrees)
            transform.scaleX(
                by: document.isFlippedHorizontally ? -1 : 1,
                yBy: document.isFlippedVertically ? -1 : 1
            )
            transform.translateX(by: -inputSize.width / 2, yBy: -inputSize.height / 2)
            transform.concat()

            inputImage.draw(
                in: NSRect(origin: .zero, size: inputSize),
                from: NSRect(origin: .zero, size: inputSize),
                operation: .copy,
                fraction: 1
            )
            transformedImage.unlockFocus()
        } else {
            transformedImage = inputImage
        }

        let croppedImage: NSImage
        if let cropRect = document.cropRect {
            croppedImage = cropped(transformedImage, to: cropRect)
        } else {
            croppedImage = transformedImage
        }

        return adjusted(croppedImage, document: document)
    }

    private static func adjusted(_ image: NSImage, document: ImageDocument) -> NSImage {
        guard document.brightness != 0 || document.contrast != 1 || document.exposure != 0,
              let ciImage = ciImage(from: image) else {
            return image
        }

        let exposureFilter = CIFilter.exposureAdjust()
        exposureFilter.inputImage = ciImage
        exposureFilter.ev = Float(document.exposure)

        let colorFilter = CIFilter.colorControls()
        colorFilter.inputImage = exposureFilter.outputImage
        colorFilter.brightness = Float(document.brightness)
        colorFilter.contrast = Float(document.contrast)

        guard let outputImage = colorFilter.outputImage,
              let cgImage = ciContext.createCGImage(outputImage, from: outputImage.extent) else {
            return image
        }

        return NSImage(cgImage: cgImage, size: image.size)
    }

    private static func ciImage(from image: NSImage) -> CIImage? {
        if let tiffRepresentation = image.tiffRepresentation {
            return CIImage(data: tiffRepresentation)
        }

        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }

        return CIImage(cgImage: cgImage)
    }

    private static func cropped(_ image: NSImage, to cropRect: CGRect) -> NSImage {
        let bounds = CGRect(origin: .zero, size: image.size)
        let clampedRect = cropRect.standardized.intersection(bounds)

        guard !clampedRect.isNull,
              clampedRect.width > 0,
              clampedRect.height > 0 else {
            return image
        }

        let outputImage = NSImage(size: clampedRect.size)
        outputImage.lockFocus()
        defer { outputImage.unlockFocus() }

        NSGraphicsContext.current?.imageInterpolation = .high

        let sourceRect = NSRect(
            x: clampedRect.minX,
            y: image.size.height - clampedRect.maxY,
            width: clampedRect.width,
            height: clampedRect.height
        )

        image.draw(
            in: NSRect(origin: .zero, size: clampedRect.size),
            from: sourceRect,
            operation: .copy,
            fraction: 1
        )

        return outputImage
    }

    private static func rotatedBoundingSize(for size: CGSize, degrees: Double) -> CGSize {
        let radians = degrees * .pi / 180
        let cosine = abs(cos(radians))
        let sine = abs(sin(radians))

        return CGSize(
            width: max(1, size.width * cosine + size.height * sine),
            height: max(1, size.width * sine + size.height * cosine)
        )
    }
}

private extension Double {
    var isAlmostZero: Bool {
        abs(self.truncatingRemainder(dividingBy: 360)) < 0.0001
    }
}
