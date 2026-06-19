import AppKit
import CoreGraphics
import Foundation

public enum ImageExporterError: Error, Equatable {
    case invalidCrop
    case unableToCrop
    case unableToCreateContext
    case unableToCreateImage
    case unableToEncodePNG
}

public enum ImageExporter {
    public static let strokeWidth: CGFloat = 4
    public static let arrowheadLength: CGFloat = 14

    public static func render(
        sourceImage: CGImage,
        displayPointSize: CGSize,
        cropRect: CGRect,
        annotations: [Annotation]
    ) throws -> CGImage {
        let pixelRect = Geometry.pixelCropRect(
            pointRect: cropRect,
            imageSize: CGSize(width: sourceImage.width, height: sourceImage.height),
            displayPointSize: displayPointSize
        )
        guard pixelRect.width > 0, pixelRect.height > 0 else {
            throw ImageExporterError.invalidCrop
        }
        guard let cropped = sourceImage.cropping(to: pixelRect) else {
            throw ImageExporterError.unableToCrop
        }

        let width = cropped.width
        let height = cropped.height
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw ImageExporterError.unableToCreateContext
        }

        context.interpolationQuality = .none
        context.draw(cropped, in: CGRect(x: 0, y: 0, width: width, height: height))

        let scaleX = CGFloat(width) / cropRect.width
        let scaleY = CGFloat(height) / cropRect.height
        context.setStrokeColor(NSColor.systemRed.cgColor)
        context.setFillColor(NSColor.systemRed.cgColor)
        context.setLineWidth(strokeWidth * min(scaleX, scaleY))
        context.setLineCap(.round)
        context.setLineJoin(.round)

        for annotation in annotations {
            draw(annotation, in: context, scaleX: scaleX, scaleY: scaleY)
        }

        guard let output = context.makeImage() else {
            throw ImageExporterError.unableToCreateImage
        }
        return output
    }

    public static func pngData(from image: CGImage) throws -> Data {
        let representation = NSBitmapImageRep(cgImage: image)
        guard let data = representation.representation(using: .png, properties: [:]) else {
            throw ImageExporterError.unableToEncodePNG
        }
        return data
    }

    public static func writeToPasteboard(_ image: CGImage) throws {
        let data = try pngData(from: image)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setData(data, forType: .png)
        pasteboard.writeObjects([NSImage(cgImage: image, size: .zero)])
    }

    private static func draw(
        _ annotation: Annotation,
        in context: CGContext,
        scaleX: CGFloat,
        scaleY: CGFloat
    ) {
        func pixelPoint(_ point: CGPoint) -> CGPoint {
            CGPoint(x: point.x * scaleX, y: point.y * scaleY)
        }

        switch annotation.kind {
        case .rectangle:
            let rect = annotation.bounds
            let pixelRect = CGRect(
                x: rect.minX * scaleX,
                y: rect.minY * scaleY,
                width: rect.width * scaleX,
                height: rect.height * scaleY
            )
            context.stroke(pixelRect)
        case .arrow:
            let start = pixelPoint(annotation.start)
            let end = pixelPoint(annotation.end)
            context.beginPath()
            context.move(to: start)
            context.addLine(to: end)
            context.strokePath()

            let angle = atan2(end.y - start.y, end.x - start.x)
            let head = arrowheadLength * min(scaleX, scaleY)
            let spread = CGFloat.pi / 6
            let first = CGPoint(
                x: end.x - head * cos(angle - spread),
                y: end.y - head * sin(angle - spread)
            )
            let second = CGPoint(
                x: end.x - head * cos(angle + spread),
                y: end.y - head * sin(angle + spread)
            )
            context.beginPath()
            context.move(to: end)
            context.addLine(to: first)
            context.move(to: end)
            context.addLine(to: second)
            context.strokePath()
        }
    }
}
