import CoreGraphics
import Foundation

public enum CapturePhase: Equatable, Sendable {
    case idle
    case choosingFirstCorner
    case choosingSecondCorner
    case annotating
}

public enum AnnotationTool: String, CaseIterable, Sendable {
    case select
    case rectangle
    case arrow
}

public final class CaptureSession {
    public private(set) var phase: CapturePhase = .idle
    public private(set) var firstCorner: CGPoint?
    public var cursorPoint: CGPoint?
    public private(set) var cropRect: CGRect?
    public private(set) var annotations: [Annotation] = []
    public var selectedAnnotationID: UUID?
    public var tool: AnnotationTool = .rectangle
    public var pendingAnnotationStart: CGPoint?

    private var undoStack: [[Annotation]] = []

    public init() {}

    public func beginSelection() {
        phase = .choosingFirstCorner
        firstCorner = nil
        cursorPoint = nil
        cropRect = nil
        annotations = []
        selectedAnnotationID = nil
        pendingAnnotationStart = nil
        undoStack = []
    }

    @discardableResult
    public func registerSelectionClick(_ point: CGPoint) -> CGRect? {
        switch phase {
        case .choosingFirstCorner:
            firstCorner = point
            cursorPoint = point
            phase = .choosingSecondCorner
            return nil
        case .choosingSecondCorner:
            guard let firstCorner else { return nil }
            let candidate = Geometry.normalizedRect(from: firstCorner, to: point)
            guard Geometry.isUsableSelection(candidate) else {
                self.firstCorner = point
                cursorPoint = point
                return nil
            }
            cropRect = candidate
            phase = .annotating
            cursorPoint = nil
            return candidate
        default:
            return nil
        }
    }

    public func setCropRect(_ rect: CGRect) {
        cropRect = rect
        phase = .annotating
    }

    @discardableResult
    public func addAnnotation(kind: AnnotationKind, start: CGPoint, end: CGPoint) -> Annotation? {
        guard let cropRect else { return nil }
        let localBounds = CGRect(origin: .zero, size: cropRect.size)
        let clampedStart = Geometry.clamp(start, to: localBounds)
        let clampedEnd = Geometry.clamp(end, to: localBounds)
        let annotation = Annotation(kind: kind, start: clampedStart, end: clampedEnd)

        if kind == .rectangle && !Geometry.isUsableSelection(annotation.bounds) {
            return nil
        }
        if kind == .arrow && hypot(clampedEnd.x - clampedStart.x, clampedEnd.y - clampedStart.y) < 4 {
            return nil
        }

        checkpoint()
        annotations.append(annotation)
        selectedAnnotationID = annotation.id
        return annotation
    }

    public func annotation(at point: CGPoint, tolerance: CGFloat = 8) -> Annotation? {
        annotations.reversed().first { $0.hitTest(point, tolerance: tolerance) }
    }

    public func annotation(id: UUID) -> Annotation? {
        annotations.first { $0.id == id }
    }

    public func updateAnnotation(_ annotation: Annotation) {
        guard let index = annotations.firstIndex(where: { $0.id == annotation.id }) else { return }
        annotations[index] = annotation
    }

    public func checkpoint() {
        undoStack.append(annotations)
    }

    public func deleteSelected() {
        guard let selectedAnnotationID,
              annotations.contains(where: { $0.id == selectedAnnotationID }) else { return }
        checkpoint()
        annotations.removeAll { $0.id == selectedAnnotationID }
        self.selectedAnnotationID = nil
    }

    public var canUndo: Bool {
        !undoStack.isEmpty
    }

    public func undo() {
        guard let previous = undoStack.popLast() else { return }
        annotations = previous
        if let selectedAnnotationID,
           !annotations.contains(where: { $0.id == selectedAnnotationID }) {
            self.selectedAnnotationID = nil
        }
    }
}
