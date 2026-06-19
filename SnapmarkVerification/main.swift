import AppKit
import CoreGraphics
import SnapmarkCore

func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fatalError("Verification failed: \(message)")
    }
}

let normalized = Geometry.normalizedRect(
    from: CGPoint(x: 90, y: 70),
    to: CGPoint(x: 10, y: 20)
)
require(normalized == CGRect(x: 10, y: 20, width: 80, height: 50), "rectangle normalization")

let toolbarAbove = Geometry.floatingToolbarFrame(
    selection: CGRect(x: 200, y: 200, width: 300, height: 200),
    container: CGRect(x: 0, y: 0, width: 1000, height: 800),
    size: CGSize(width: 400, height: 50)
)
require(toolbarAbove == CGRect(x: 150, y: 410, width: 400, height: 50), "toolbar above selection")

let toolbarBelow = Geometry.floatingToolbarFrame(
    selection: CGRect(x: 200, y: 650, width: 300, height: 130),
    container: CGRect(x: 0, y: 0, width: 1000, height: 800),
    size: CGSize(width: 400, height: 50)
)
require(toolbarBelow == CGRect(x: 150, y: 590, width: 400, height: 50), "toolbar below selection")

let session = CaptureSession()
session.beginSelection()
require(session.registerSelectionClick(CGPoint(x: 80, y: 80)) == nil, "first selection click")
require(
    session.registerSelectionClick(CGPoint(x: 20, y: 30)) == CGRect(x: 20, y: 30, width: 60, height: 50),
    "second selection click"
)
require(
    session.addAnnotation(
        kind: .arrow,
        start: CGPoint(x: 5, y: 5),
        end: CGPoint(x: 50, y: 40)
    ) != nil,
    "annotation creation"
)
session.deleteSelected()
require(session.annotations.isEmpty, "annotation deletion")
session.undo()
require(session.annotations.count == 1, "annotation undo")

guard let context = CGContext(
    data: nil,
    width: 200,
    height: 100,
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: CGColorSpaceCreateDeviceRGB(),
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else {
    fatalError("Verification failed: source context")
}
context.setFillColor(NSColor.white.cgColor)
context.fill(CGRect(x: 0, y: 0, width: 200, height: 100))
guard let source = context.makeImage() else {
    fatalError("Verification failed: source image")
}

let output = try ImageExporter.render(
    sourceImage: source,
    displayPointSize: CGSize(width: 100, height: 50),
    cropRect: CGRect(x: 10, y: 5, width: 30, height: 20),
    annotations: session.annotations
)
require(output.width == 60 && output.height == 40, "Retina export dimensions")
let pngData = try ImageExporter.pngData(from: output)
require(!pngData.isEmpty, "PNG encoding")

print("Snapmark verification passed")
