import AppKit
import Carbon.HIToolbox
import SnapmarkCore

@MainActor
final class OverlayView: NSView {
    let capturedImage: CGImage
    let session = CaptureSession()
    weak var coordinator: CaptureCoordinator?
    var acceptsSelectionInput = true {
        didSet { needsDisplay = true }
    }

    private var trackingAreaReference: NSTrackingArea?
    private var dragAnnotationID: UUID?
    private var dragHandle: AnnotationHandle?
    private var dragStart: CGPoint?
    private var dragOriginal: Annotation?
    private var dragCheckpointed = false
    private var hoveredToolbarAction: ToolbarAction?

    private enum ToolbarAction: CaseIterable {
        case select
        case rectangle
        case arrow

        var symbolName: String {
            switch self {
            case .select: "hand.point.up.left"
            case .rectangle: "rectangle"
            case .arrow: "arrow.up.right"
            }
        }
    }

    init(image: CGImage, coordinator: CaptureCoordinator) {
        capturedImage = image
        self.coordinator = coordinator
        super.init(frame: .zero)
        session.beginSelection()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool { true }

    // The overlay activates the app when it appears. Without this, macOS swallows
    // the first click just to make the window key, so the user would have to click
    // once to focus and again to set the first corner.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingAreaReference {
            removeTrackingArea(trackingAreaReference)
        }
        let tracking = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseMoved, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(tracking)
        trackingAreaReference = tracking
    }

    override func draw(_ dirtyRect: NSRect) {
        NSImage(cgImage: capturedImage, size: bounds.size).draw(in: bounds)

        switch session.phase {
        case .choosingFirstCorner:
            NSColor.black.withAlphaComponent(0.5).setFill()
            bounds.fill()
            drawSelectionInstructions("Click the first corner")
        case .choosingSecondCorner:
            drawSelectionPreview()
            drawSelectionInstructions("Click the opposite corner")
        case .annotating:
            drawAnnotationEditor()
        case .idle:
            break
        }

        if !acceptsSelectionInput && session.phase != .annotating {
            NSColor.black.withAlphaComponent(0.2).setFill()
            bounds.fill()
            drawSelectionInstructions("Complete the selection on the other display")
        }
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: session.tool == .select ? .arrow : .crosshair)
    }

    override func mouseMoved(with event: NSEvent) {
        session.cursorPoint = convert(event.locationInWindow, from: nil)
        hoveredToolbarAction = session.phase == .annotating
            ? toolbarAction(at: session.cursorPoint ?? .zero)
            : nil
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)

        switch session.phase {
        case .choosingFirstCorner:
            guard acceptsSelectionInput else { return }
            session.registerSelectionClick(point)
            coordinator?.didChooseFirstCorner(in: self)
            needsDisplay = true
        case .choosingSecondCorner:
            guard acceptsSelectionInput else { return }
            if session.registerSelectionClick(point) != nil {
                coordinator?.didConfirmCrop(in: self)
            }
            needsDisplay = true
        case .annotating:
            handleAnnotationMouseDown(at: point)
        case .idle:
            break
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard session.phase == .annotating,
              let cropRect = session.cropRect,
              let id = dragAnnotationID,
              let original = dragOriginal,
              let dragStart else { return }

        if !dragCheckpointed {
            session.checkpoint()
            dragCheckpointed = true
        }

        let screenPoint = convert(event.locationInWindow, from: nil)
        let localPoint = Geometry.clamp(
            CGPoint(x: screenPoint.x - cropRect.minX, y: screenPoint.y - cropRect.minY),
            to: CGRect(origin: .zero, size: cropRect.size)
        )
        var updated = original
        if let dragHandle {
            updated.resize(
                handle: dragHandle,
                to: localPoint,
                within: CGRect(origin: .zero, size: cropRect.size)
            )
        } else {
            updated.move(
                by: CGPoint(x: localPoint.x - dragStart.x, y: localPoint.y - dragStart.y),
                within: CGRect(origin: .zero, size: cropRect.size)
            )
        }
        if updated.id == id {
            session.updateAnnotation(updated)
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        dragAnnotationID = nil
        dragHandle = nil
        dragStart = nil
        dragOriginal = nil
        dragCheckpointed = false
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == UInt16(kVK_Escape) {
            if session.pendingAnnotationStart != nil {
                session.pendingAnnotationStart = nil
                needsDisplay = true
            } else {
                coordinator?.cancel()
            }
            return
        }
        if event.keyCode == UInt16(kVK_Return) || event.keyCode == UInt16(kVK_ANSI_KeypadEnter) {
            if session.phase == .annotating {
                coordinator?.copyAndFinish(from: self)
            }
            return
        }
        if event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers?.lowercased() == "z" {
            session.undo()
            needsDisplay = true
            return
        }
        if event.keyCode == UInt16(kVK_Delete) || event.keyCode == UInt16(kVK_ForwardDelete) {
            session.deleteSelected()
            needsDisplay = true
            return
        }

        switch event.charactersIgnoringModifiers?.lowercased() {
        case "v": setTool(.select)
        case "r": setTool(.rectangle)
        case "a": setTool(.arrow)
        default: super.keyDown(with: event)
        }
    }

    private func handleAnnotationMouseDown(at screenPoint: CGPoint) {
        if let action = toolbarAction(at: screenPoint) {
            perform(action)
            return
        }
        guard let cropRect = session.cropRect, cropRect.contains(screenPoint) else { return }
        let localPoint = CGPoint(x: screenPoint.x - cropRect.minX, y: screenPoint.y - cropRect.minY)

        switch session.tool {
        case .rectangle, .arrow:
            if let start = session.pendingAnnotationStart {
                let kind: AnnotationKind = session.tool == .rectangle ? .rectangle : .arrow
                _ = session.addAnnotation(kind: kind, start: start, end: localPoint)
                session.pendingAnnotationStart = nil
            } else {
                session.pendingAnnotationStart = localPoint
                session.selectedAnnotationID = nil
            }
        case .select:
            beginSelectionOrDrag(at: localPoint)
        }
        needsDisplay = true
    }

    private func beginSelectionOrDrag(at point: CGPoint) {
        let selected = session.selectedAnnotationID.flatMap { session.annotation(id: $0) }
        if let selected, let handle = selected.handle(at: point) {
            prepareDrag(annotation: selected, handle: handle, at: point)
            return
        }

        let hit = session.annotations.reversed().first { annotation in
            annotation.hitTest(point) || (annotation.kind == .rectangle && annotation.bounds.contains(point))
        }
        session.selectedAnnotationID = hit?.id
        if let hit {
            prepareDrag(annotation: hit, handle: nil, at: point)
        }
    }

    private func prepareDrag(annotation: Annotation, handle: AnnotationHandle?, at point: CGPoint) {
        dragAnnotationID = annotation.id
        dragHandle = handle
        dragStart = point
        dragOriginal = annotation
        dragCheckpointed = false
    }

    private func setTool(_ tool: AnnotationTool) {
        session.tool = tool
        session.pendingAnnotationStart = nil
        window?.invalidateCursorRects(for: self)
        needsDisplay = true
    }

    private func perform(_ action: ToolbarAction) {
        switch action {
        case .select: setTool(.select)
        case .rectangle: setTool(.rectangle)
        case .arrow: setTool(.arrow)
        }
    }

    private func drawSelectionPreview() {
        guard let first = session.firstCorner, let cursor = session.cursorPoint else { return }
        let rect = Geometry.normalizedRect(from: first, to: cursor)
        drawDimmedOutside(rect)

        NSColor.white.setStroke()
        let path = NSBezierPath(rect: rect)
        path.lineWidth = 1
        path.setLineDash([6, 4], count: 2, phase: 0)
        path.stroke()

        NSColor.systemRed.setFill()
        NSBezierPath(ovalIn: CGRect(x: first.x - 4, y: first.y - 4, width: 8, height: 8)).fill()
    }

    private func drawAnnotationEditor() {
        guard let cropRect = session.cropRect else { return }
        drawDimmedOutside(cropRect)

        NSColor.white.withAlphaComponent(0.9).setStroke()
        let cropBorder = NSBezierPath(rect: cropRect)
        cropBorder.lineWidth = 1
        cropBorder.stroke()

        for annotation in session.annotations {
            draw(annotation, selected: annotation.id == session.selectedAnnotationID, cropOrigin: cropRect.origin)
        }

        if let start = session.pendingAnnotationStart, let cursor = session.cursorPoint {
            let localCursor = Geometry.clamp(
                CGPoint(x: cursor.x - cropRect.minX, y: cursor.y - cropRect.minY),
                to: CGRect(origin: .zero, size: cropRect.size)
            )
            let kind: AnnotationKind = session.tool == .rectangle ? .rectangle : .arrow
            draw(
                Annotation(kind: kind, start: start, end: localCursor),
                selected: false,
                cropOrigin: cropRect.origin,
                alpha: 0.65
            )
        }

        drawToolbar()
    }

    private func draw(_ annotation: Annotation, selected: Bool, cropOrigin: CGPoint, alpha: CGFloat = 1) {
        let start = CGPoint(x: annotation.start.x + cropOrigin.x, y: annotation.start.y + cropOrigin.y)
        let end = CGPoint(x: annotation.end.x + cropOrigin.x, y: annotation.end.y + cropOrigin.y)
        NSColor.systemRed.withAlphaComponent(alpha).setStroke()
        NSColor.systemRed.withAlphaComponent(alpha).setFill()

        switch annotation.kind {
        case .rectangle:
            let rect = Geometry.normalizedRect(from: start, to: end)
            let path = NSBezierPath(rect: rect)
            path.lineWidth = ImageExporter.strokeWidth
            path.lineJoinStyle = .round
            path.stroke()
        case .arrow:
            let path = NSBezierPath()
            path.move(to: start)
            path.line(to: end)
            path.lineWidth = ImageExporter.strokeWidth
            path.lineCapStyle = .round
            path.stroke()

            let angle = atan2(end.y - start.y, end.x - start.x)
            let spread = CGFloat.pi / 6
            let first = CGPoint(
                x: end.x - ImageExporter.arrowheadLength * cos(angle - spread),
                y: end.y - ImageExporter.arrowheadLength * sin(angle - spread)
            )
            let second = CGPoint(
                x: end.x - ImageExporter.arrowheadLength * cos(angle + spread),
                y: end.y - ImageExporter.arrowheadLength * sin(angle + spread)
            )
            let head = NSBezierPath()
            head.move(to: end)
            head.line(to: first)
            head.move(to: end)
            head.line(to: second)
            head.lineWidth = ImageExporter.strokeWidth
            head.lineCapStyle = .round
            head.stroke()
        }

        if selected {
            NSColor.white.setFill()
            NSColor.systemRed.setStroke()
            for (_, handle) in annotation.handles {
                let point = CGPoint(x: handle.x + cropOrigin.x, y: handle.y + cropOrigin.y)
                let handleRect = CGRect(x: point.x - 4, y: point.y - 4, width: 8, height: 8)
                let handlePath = NSBezierPath(ovalIn: handleRect)
                handlePath.fill()
                handlePath.lineWidth = 2
                handlePath.stroke()
            }
        }
    }

    private func drawDimmedOutside(_ rect: CGRect) {
        NSColor.black.withAlphaComponent(0.5).setFill()
        CGRect(x: bounds.minX, y: bounds.minY, width: bounds.width, height: max(0, rect.minY - bounds.minY)).fill()
        CGRect(x: bounds.minX, y: rect.maxY, width: bounds.width, height: max(0, bounds.maxY - rect.maxY)).fill()
        CGRect(x: bounds.minX, y: rect.minY, width: max(0, rect.minX - bounds.minX), height: rect.height).fill()
        CGRect(x: rect.maxX, y: rect.minY, width: max(0, bounds.maxX - rect.maxX), height: rect.height).fill()
    }

    private func drawSelectionInstructions(_ text: String) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 16, weight: .semibold),
            .foregroundColor: NSColor.white
        ]
        let size = text.size(withAttributes: attributes)
        let frame = CGRect(
            x: bounds.midX - size.width / 2 - 16,
            y: bounds.maxY - 70,
            width: size.width + 32,
            height: size.height + 16
        )
        NSColor.black.withAlphaComponent(0.78).setFill()
        NSBezierPath(roundedRect: frame, xRadius: 9, yRadius: 9).fill()
        text.draw(
            at: CGPoint(x: frame.minX + 16, y: frame.minY + 8),
            withAttributes: attributes
        )
    }

    private var toolbarButtonFrames: [(ToolbarAction, CGRect)] {
        let buttonSize: CGFloat = 38
        let spacing: CGFloat = 4
        let toolbarSize = CGSize(
            width: CGFloat(ToolbarAction.allCases.count) * buttonSize
                + CGFloat(ToolbarAction.allCases.count - 1) * spacing
                + 12,
            height: buttonSize + 12
        )
        let selection = session.cropRect ?? bounds
        let toolbarFrame = Geometry.floatingToolbarFrame(
            selection: selection,
            container: bounds,
            size: toolbarSize
        )
        let originX = toolbarFrame.minX + 6
        let originY = toolbarFrame.minY + 6
        var x = originX
        return ToolbarAction.allCases.map { action in
            defer { x += buttonSize + spacing }
            return (action, CGRect(x: x, y: originY, width: buttonSize, height: buttonSize))
        }
    }

    private func drawToolbar() {
        let frames = toolbarButtonFrames
        guard let first = frames.first?.1, let last = frames.last?.1 else { return }
        let background = CGRect(
            x: first.minX - 8,
            y: first.minY - 8,
            width: last.maxX - first.minX + 16,
            height: first.height + 16
        )
        NSColor.black.withAlphaComponent(0.84).setFill()
        NSBezierPath(roundedRect: background, xRadius: 10, yRadius: 10).fill()

        for (action, frame) in frames {
            let isActive =
                (action == .select && session.tool == .select) ||
                (action == .rectangle && session.tool == .rectangle) ||
                (action == .arrow && session.tool == .arrow)
            if isActive {
                NSColor.controlAccentColor.setFill()
                NSBezierPath(roundedRect: frame, xRadius: 8, yRadius: 8).fill()
            } else if hoveredToolbarAction == action {
                NSColor.white.withAlphaComponent(0.14).setFill()
                NSBezierPath(roundedRect: frame, xRadius: 8, yRadius: 8).fill()
            }

            let symbolConfiguration = NSImage.SymbolConfiguration(
                pointSize: 17,
                weight: .semibold
            ).applying(
                NSImage.SymbolConfiguration(paletteColors: [.white])
            )
            guard let image = NSImage(
                systemSymbolName: action.symbolName,
                accessibilityDescription: nil
            )?.withSymbolConfiguration(symbolConfiguration) else { continue }
            let imageSize = image.size
            image.draw(
                in: CGRect(
                    x: frame.midX - imageSize.width / 2,
                    y: frame.midY - imageSize.height / 2,
                    width: imageSize.width,
                    height: imageSize.height
                )
            )
        }
    }

    private func toolbarAction(at point: CGPoint) -> ToolbarAction? {
        toolbarButtonFrames.first { $0.1.contains(point) }?.0
    }

}
