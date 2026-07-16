import SwiftUI
import CoreImage

struct BlurOverlay: View {
    let image: NSImage
    let annotations: [MSAnnotation]
    let inProgress: MSAnnotation?
    let scale: CGFloat
    let showMask: Bool

    var body: some View {
        ZStack {
            ForEach(allBlurAnnotations) { annotation in
                blurStrokeView(annotation)
            }
        }
        .frame(
            width: image.size.width * scale,
            height: image.size.height * scale
        )
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func blurStrokeView(_ annotation: MSAnnotation) -> some View {
        let displayedWidth = image.size.width * scale
        let displayedHeight = image.size.height * scale

        if !annotation.points.isEmpty {
            ZStack {
                if let blurred = makeBlurredImage(radius: annotation.blurRadius) {
                    Image(nsImage: blurred)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: displayedWidth, height: displayedHeight)
                        .mask {
                            blurMask(for: annotation)
                        }
                }

                if showMask {
                    Color.red.opacity(0.35)
                        .frame(width: displayedWidth, height: displayedHeight)
                        .mask {
                            blurMask(for: annotation)
                        }
                }
            }
            .frame(width: displayedWidth, height: displayedHeight)
        }
    }

    @ViewBuilder
    private func blurMask(for annotation: MSAnnotation) -> some View {
        if annotation.points.isEmpty {
            Color.clear
        } else {
            Canvas { context, _ in
                let diameter = max(2, annotation.blurBrushSize * scale)
                let radius = diameter / 2
                let points = interpolatedBrushPoints(
                    annotation.points,
                    maximumSpacing: max(1, annotation.blurBrushSize * 0.15)
                )

                for point in points {
                    let centre = CGPoint(
                        x: point.x * scale,
                        y: point.y * scale
                    )
                    let rect = CGRect(
                        x: centre.x - radius,
                        y: centre.y - radius,
                        width: diameter,
                        height: diameter
                    )
                    context.fill(
                        Path(ellipseIn: rect),
                        with: .color(.white)
                    )
                }
            }
            .frame(
                width: image.size.width * scale,
                height: image.size.height * scale
            )
        }
    }

    private func makeBlurredImage(radius: Double) -> NSImage? {
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let cgInput = bitmap.cgImage,
              let filter = CIFilter(name: "CIGaussianBlur") else {
            return nil
        }

        let input = CIImage(cgImage: cgInput)
        filter.setValue(input, forKey: kCIInputImageKey)
        filter.setValue(max(8, radius * 1.5), forKey: kCIInputRadiusKey)

        guard let output = filter.outputImage?.cropped(to: input.extent) else {
            return nil
        }

        let ciContext = CIContext(options: nil)
        guard let cgOutput = ciContext.createCGImage(output, from: input.extent) else {
            return nil
        }

        return NSImage(cgImage: cgOutput, size: image.size)
    }

    private func interpolatedBrushPoints(
        _ points: [CGPoint],
        maximumSpacing: Double
    ) -> [CGPoint] {
        guard let first = points.first else { return [] }
        guard points.count > 1 else { return [first] }

        var result = [first]

        for (start, end) in zip(points, points.dropFirst()) {
            let distance = hypot(end.x - start.x, end.y - start.y)
            let steps = max(1, Int(ceil(distance / maximumSpacing)))

            for step in 1...steps {
                let progress = CGFloat(step) / CGFloat(steps)
                result.append(
                    CGPoint(
                        x: start.x + (end.x - start.x) * progress,
                        y: start.y + (end.y - start.y) * progress
                    )
                )
            }
        }

        return result
    }

    private var allBlurAnnotations: [MSAnnotation] {
        if let inProgress {
            return annotations + [inProgress]
        }
        return annotations
    }
}
