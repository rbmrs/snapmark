import AppKit
import CoreGraphics
import XCTest
@testable import PrintyCore

final class ImageExporterTests: XCTestCase {
    func testExportKeepsNativeRetinaDimensions() throws {
        let source = try makeImage(width: 200, height: 100, color: .white)
        let output = try ImageExporter.render(
            sourceImage: source,
            displayPointSize: CGSize(width: 100, height: 50),
            cropRect: CGRect(x: 10, y: 5, width: 30, height: 20),
            annotations: []
        )

        XCTAssertEqual(output.width, 60)
        XCTAssertEqual(output.height, 40)
    }

    func testExportCompositesRedAnnotation() throws {
        let source = try makeImage(width: 100, height: 100, color: .white)
        let annotation = Annotation(
            kind: .rectangle,
            start: CGPoint(x: 10, y: 10),
            end: CGPoint(x: 40, y: 40)
        )
        let output = try ImageExporter.render(
            sourceImage: source,
            displayPointSize: CGSize(width: 100, height: 100),
            cropRect: CGRect(x: 0, y: 0, width: 50, height: 50),
            annotations: [annotation]
        )

        let data = try XCTUnwrap(output.dataProvider?.data as Data?)
        XCTAssertTrue(data.containsRedDominantPixel)
        XCTAssertFalse(try ImageExporter.pngData(from: output).isEmpty)
    }

    private func makeImage(width: Int, height: Int, color: NSColor) throws -> CGImage {
        let context = try XCTUnwrap(
            CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        )
        context.setFillColor(color.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return try XCTUnwrap(context.makeImage())
    }
}

private extension Data {
    var containsRedDominantPixel: Bool {
        guard count >= 4 else { return false }
        return stride(from: 0, to: count - 3, by: 4).contains { index in
            self[index] > 180 && self[index + 1] < 120 && self[index + 2] < 120
        }
    }
}
