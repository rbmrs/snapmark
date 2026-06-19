import CoreGraphics
import Foundation

public enum AnnotationKind: String, Codable, Sendable {
    case rectangle
    case arrow
}

public enum AnnotationHandle: Equatable, Sendable {
    case rectangleCorner(Int)
    case arrowStart
    case arrowEnd
}

public struct Annotation: Identifiable, Equatable, Sendable {
    public let id: UUID
    public var kind: AnnotationKind
    public var start: CGPoint
    public var end: CGPoint

    public init(id: UUID = UUID(), kind: AnnotationKind, start: CGPoint, end: CGPoint) {
        self.id = id
        self.kind = kind
        self.start = start
        self.end = end
    }

    public var bounds: CGRect {
        Geometry.normalizedRect(from: start, to: end)
    }

    public var handles: [(AnnotationHandle, CGPoint)] {
        switch kind {
        case .rectangle:
            let rect = bounds
            return [
                (.rectangleCorner(0), CGPoint(x: rect.minX, y: rect.minY)),
                (.rectangleCorner(1), CGPoint(x: rect.maxX, y: rect.minY)),
                (.rectangleCorner(2), CGPoint(x: rect.maxX, y: rect.maxY)),
                (.rectangleCorner(3), CGPoint(x: rect.minX, y: rect.maxY))
            ]
        case .arrow:
            return [(.arrowStart, start), (.arrowEnd, end)]
        }
    }

    public func handle(at point: CGPoint, tolerance: CGFloat = 8) -> AnnotationHandle? {
        handles.first { _, handlePoint in
            hypot(point.x - handlePoint.x, point.y - handlePoint.y) <= tolerance
        }?.0
    }

    public func hitTest(_ point: CGPoint, tolerance: CGFloat = 8) -> Bool {
        switch kind {
        case .rectangle:
            let rect = bounds
            let outer = rect.insetBy(dx: -tolerance, dy: -tolerance)
            let inner = rect.insetBy(dx: tolerance, dy: tolerance)
            return outer.contains(point) && (!inner.contains(point) || inner.width <= 0 || inner.height <= 0)
        case .arrow:
            return Geometry.distance(from: point, toSegmentFrom: start, to: end) <= tolerance
        }
    }

    public mutating func move(by delta: CGPoint, within bounds: CGRect) {
        let currentBounds = self.bounds
        var adjusted = delta
        if currentBounds.minX + adjusted.x < bounds.minX {
            adjusted.x = bounds.minX - currentBounds.minX
        }
        if currentBounds.maxX + adjusted.x > bounds.maxX {
            adjusted.x = bounds.maxX - currentBounds.maxX
        }
        if currentBounds.minY + adjusted.y < bounds.minY {
            adjusted.y = bounds.minY - currentBounds.minY
        }
        if currentBounds.maxY + adjusted.y > bounds.maxY {
            adjusted.y = bounds.maxY - currentBounds.maxY
        }
        start.x += adjusted.x
        start.y += adjusted.y
        end.x += adjusted.x
        end.y += adjusted.y
    }

    public mutating func resize(handle: AnnotationHandle, to point: CGPoint, within bounds: CGRect) {
        let clamped = Geometry.clamp(point, to: bounds)
        switch (kind, handle) {
        case (.arrow, .arrowStart):
            start = clamped
        case (.arrow, .arrowEnd):
            end = clamped
        case (.rectangle, .rectangleCorner(let index)):
            let rect = self.bounds
            let opposite: CGPoint
            switch index {
            case 0: opposite = CGPoint(x: rect.maxX, y: rect.maxY)
            case 1: opposite = CGPoint(x: rect.minX, y: rect.maxY)
            case 2: opposite = CGPoint(x: rect.minX, y: rect.minY)
            default: opposite = CGPoint(x: rect.maxX, y: rect.minY)
            }
            start = opposite
            end = clamped
        default:
            break
        }
    }
}
