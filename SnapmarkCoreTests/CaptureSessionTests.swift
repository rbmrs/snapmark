import CoreGraphics
import XCTest
@testable import SnapmarkCore

final class CaptureSessionTests: XCTestCase {
    func testTwoClickSelectionTransitionsToAnnotating() {
        let session = CaptureSession()
        session.beginSelection()

        XCTAssertNil(session.registerSelectionClick(CGPoint(x: 80, y: 70)))
        XCTAssertEqual(session.phase, .choosingSecondCorner)

        let crop = session.registerSelectionClick(CGPoint(x: 20, y: 10))
        XCTAssertEqual(crop, CGRect(x: 20, y: 10, width: 60, height: 60))
        XCTAssertEqual(session.phase, .annotating)
    }

    func testInvalidSecondCornerRestartsFromThatPoint() {
        let session = CaptureSession()
        session.beginSelection()
        session.registerSelectionClick(CGPoint(x: 10, y: 10))

        XCTAssertNil(session.registerSelectionClick(CGPoint(x: 12, y: 12)))
        XCTAssertEqual(session.firstCorner, CGPoint(x: 12, y: 12))
        XCTAssertEqual(session.phase, .choosingSecondCorner)
    }

    func testAddDeleteAndUndo() {
        let session = CaptureSession()
        session.setCropRect(CGRect(x: 0, y: 0, width: 100, height: 100))
        let annotation = session.addAnnotation(
            kind: .rectangle,
            start: CGPoint(x: 10, y: 10),
            end: CGPoint(x: 40, y: 40)
        )

        XCTAssertEqual(session.annotations.count, 1)
        XCTAssertEqual(session.selectedAnnotationID, annotation?.id)

        session.deleteSelected()
        XCTAssertTrue(session.annotations.isEmpty)

        session.undo()
        XCTAssertEqual(session.annotations.count, 1)

        session.undo()
        XCTAssertTrue(session.annotations.isEmpty)
    }

    func testAnnotationsAreClampedToCropCoordinates() {
        let session = CaptureSession()
        session.setCropRect(CGRect(x: 20, y: 20, width: 100, height: 80))
        let annotation = session.addAnnotation(
            kind: .arrow,
            start: CGPoint(x: -20, y: 40),
            end: CGPoint(x: 140, y: 100)
        )

        XCTAssertEqual(annotation?.start, CGPoint(x: 0, y: 40))
        XCTAssertEqual(annotation?.end, CGPoint(x: 100, y: 80))
    }
}
