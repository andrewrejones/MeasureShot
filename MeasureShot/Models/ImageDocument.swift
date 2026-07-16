//
//  ImageDocument.swift
//  MeasureShot
//
//  Created by Andrew Jones on 7/16/26.
//

import AppKit
import Observation

@MainActor
@Observable
final class ImageDocument: Identifiable {
    let id = UUID()

    var title: String

    /// Untouched source image. Image edits should always be derived from this.
    let originalImage: NSImage

    /// Number of clockwise quarter-turns: 0, 1, 2 or 3.
    var rotationQuarterTurns = 0

    /// Additional clockwise rotation in degrees.
    var freeRotationDegrees: Double = 0

    var isFlippedHorizontally = false
    var isFlippedVertically = false

    /// Crop rectangle in original-image coordinates.
    /// Nil means the full image is used.
    var cropRect: CGRect?

    /// Reserved for the next image-adjustment phase.
    var brightness: Double = 0
    var contrast: Double = 1
    var exposure: Double = 0

    init(
        image: NSImage,
        title: String = "Untitled"
    ) {
        self.originalImage = image
        self.title = title
    }

    var normalizedRotationQuarterTurns: Int {
        ((rotationQuarterTurns % 4) + 4) % 4
    }

    func rotateClockwise() {
        rotationQuarterTurns = normalizedRotationQuarterTurns + 1
    }

    func rotateAnticlockwise() {
        rotationQuarterTurns = normalizedRotationQuarterTurns - 1
    }

    func flipHorizontally() {
        isFlippedHorizontally.toggle()
    }

    func flipVertically() {
        isFlippedVertically.toggle()
    }

    var totalRotationDegrees: Double {
        Double(normalizedRotationQuarterTurns) * 90 + freeRotationDegrees
    }

    func resetImageTransforms() {
        rotationQuarterTurns = 0
        freeRotationDegrees = 0
        isFlippedHorizontally = false
        isFlippedVertically = false
        cropRect = nil
        brightness = 0
        contrast = 1
        exposure = 0
    }
}
