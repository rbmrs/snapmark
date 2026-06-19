import CoreGraphics
import XCTest
@testable import SnapmarkCore

final class AnnotationTests: XCTestCase {
    func testArrowHitTestingUsesLineDistance() {
        let arrow = Annotation(
            kind: .arrow,
            start: CGPoint(x: 10, y: 10),
            end: CGPoint(x: 90, y: 10)
        )

        XCTAssertTrue(arrow.hitTest(CGPoint(x: 50, y: 15), tolerance: 6))
        XCTAssertFalse(arrow.hitTest(CGPoint(x: 50, y: 25), tolerance: 6))
    }

    func testRectangleHitTestingTargetsOutline() {
        let rectangle = Annotation(
            kind: .rectangle,
            start: CGPoint(x: 10, y: 10),
            end: CGPoint(x: 90, y: 90)
        )

        XCTAssertTrue(rectangle.hitTest(CGPoint(x: 12, y: 50)))
        XCTAssertFalse(rectangle.hitTest(CGPoint(x: 50, y: 50)))
    }

    func testMovingAnnotationIsClampedToCrop() {
        var rectangle = Annotation(
            kind: .rectangle,
            start: CGPoint(x: 20, y: 20),
            end: CGPoint(x: 60, y: 60)
        )

        rectangle.move(
            by: CGPoint(x: 100, y: -100),
            within: CGRect(x: 0, y: 0, width: 100, height: 100)
        )

        XCTAssertEqual(rectangle.bounds, CGRect(x: 60, y: 0, width: 40, height: 40))
    }

    func testRectangleCornerResizeKeepsOppositeCorner() {
        var rectangle = Annotation(
            kind: .rectangle,
            start: CGPoint(x: 10, y: 10),
            end: CGPoint(x: 50, y: 50)
        )

        rectangle.resize(
            handle: .rectangleCorner(0),
            to: CGPoint(x: 20, y: 25),
            within: CGRect(x: 0, y: 0, width: 100, height: 100)
        )

        XCTAssertEqual(rectangle.bounds, CGRect(x: 20, y: 25, width: 30, height: 25))
    }
}
