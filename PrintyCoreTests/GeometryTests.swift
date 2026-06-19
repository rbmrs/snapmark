import CoreGraphics
import XCTest
@testable import PrintyCore

final class GeometryTests: XCTestCase {
    func testNormalizedRectAcceptsReversedCorners() {
        let rect = Geometry.normalizedRect(
            from: CGPoint(x: 90, y: 75),
            to: CGPoint(x: 10, y: 15)
        )

        XCTAssertEqual(rect, CGRect(x: 10, y: 15, width: 80, height: 60))
    }

    func testSmallSelectionsAreRejected() {
        XCTAssertFalse(Geometry.isUsableSelection(CGRect(x: 0, y: 0, width: 3, height: 20)))
        XCTAssertFalse(Geometry.isUsableSelection(CGRect(x: 0, y: 0, width: 20, height: 3)))
        XCTAssertTrue(Geometry.isUsableSelection(CGRect(x: 0, y: 0, width: 4, height: 4)))
    }

    func testPixelCropRectConvertsBottomLeftPointsToTopLeftPixels() {
        let rect = Geometry.pixelCropRect(
            pointRect: CGRect(x: 10, y: 20, width: 30, height: 40),
            imageSize: CGSize(width: 200, height: 200),
            displayPointSize: CGSize(width: 100, height: 100)
        )

        XCTAssertEqual(rect, CGRect(x: 20, y: 80, width: 60, height: 80))
    }

    func testPixelCropRectSupportsDifferentAxisScales() {
        let rect = Geometry.pixelCropRect(
            pointRect: CGRect(x: 25, y: 25, width: 50, height: 50),
            imageSize: CGSize(width: 200, height: 300),
            displayPointSize: CGSize(width: 100, height: 100)
        )

        XCTAssertEqual(rect, CGRect(x: 50, y: 75, width: 100, height: 150))
    }

    func testToolbarIsPlacedAboveSelectionWhenThereIsRoom() {
        let frame = Geometry.floatingToolbarFrame(
            selection: CGRect(x: 200, y: 200, width: 300, height: 200),
            container: CGRect(x: 0, y: 0, width: 1000, height: 800),
            size: CGSize(width: 400, height: 50)
        )

        XCTAssertEqual(frame, CGRect(x: 150, y: 410, width: 400, height: 50))
    }

    func testToolbarMovesBelowSelectionNearTopEdge() {
        let frame = Geometry.floatingToolbarFrame(
            selection: CGRect(x: 200, y: 650, width: 300, height: 130),
            container: CGRect(x: 0, y: 0, width: 1000, height: 800),
            size: CGSize(width: 400, height: 50)
        )

        XCTAssertEqual(frame, CGRect(x: 150, y: 590, width: 400, height: 50))
    }

    func testToolbarIsClampedToDisplaySides() {
        let frame = Geometry.floatingToolbarFrame(
            selection: CGRect(x: 5, y: 200, width: 100, height: 100),
            container: CGRect(x: 0, y: 0, width: 500, height: 500),
            size: CGSize(width: 300, height: 50)
        )

        XCTAssertEqual(frame.minX, 10)
    }
}
