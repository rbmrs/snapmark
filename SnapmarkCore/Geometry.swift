import CoreGraphics
import Foundation

public enum Geometry {
    public static let minimumSelectionSize: CGFloat = 4

    public static func normalizedRect(from first: CGPoint, to second: CGPoint) -> CGRect {
        CGRect(
            x: min(first.x, second.x),
            y: min(first.y, second.y),
            width: abs(second.x - first.x),
            height: abs(second.y - first.y)
        )
    }

    public static func isUsableSelection(_ rect: CGRect) -> Bool {
        rect.width >= minimumSelectionSize && rect.height >= minimumSelectionSize
    }

    public static func clamp(_ point: CGPoint, to rect: CGRect) -> CGPoint {
        CGPoint(
            x: min(max(point.x, rect.minX), rect.maxX),
            y: min(max(point.y, rect.minY), rect.maxY)
        )
    }

    public static func distance(from point: CGPoint, toSegmentFrom start: CGPoint, to end: CGPoint) -> CGFloat {
        let segment = CGPoint(x: end.x - start.x, y: end.y - start.y)
        let lengthSquared = segment.x * segment.x + segment.y * segment.y
        guard lengthSquared > 0 else {
            return hypot(point.x - start.x, point.y - start.y)
        }

        let relative = CGPoint(x: point.x - start.x, y: point.y - start.y)
        let projection = (relative.x * segment.x + relative.y * segment.y) / lengthSquared
        let t = min(max(projection, 0), 1)
        let closest = CGPoint(x: start.x + t * segment.x, y: start.y + t * segment.y)
        return hypot(point.x - closest.x, point.y - closest.y)
    }

    public static func pixelCropRect(
        pointRect: CGRect,
        imageSize: CGSize,
        displayPointSize: CGSize
    ) -> CGRect {
        guard displayPointSize.width > 0, displayPointSize.height > 0 else { return .zero }

        let scaleX = imageSize.width / displayPointSize.width
        let scaleY = imageSize.height / displayPointSize.height
        let x = floor(pointRect.minX * scaleX)
        let y = floor((displayPointSize.height - pointRect.maxY) * scaleY)
        let maxX = ceil(pointRect.maxX * scaleX)
        let maxY = ceil((displayPointSize.height - pointRect.minY) * scaleY)

        return CGRect(
            x: max(0, x),
            y: max(0, y),
            width: min(imageSize.width, maxX) - max(0, x),
            height: min(imageSize.height, maxY) - max(0, y)
        ).integral
    }

    public static func floatingToolbarFrame(
        selection: CGRect,
        container: CGRect,
        size: CGSize,
        gap: CGFloat = 10,
        margin: CGFloat = 10
    ) -> CGRect {
        let minimumX = container.minX + margin
        let maximumX = container.maxX - margin - size.width
        let centeredX = selection.midX - size.width / 2
        let x = min(max(centeredX, minimumX), max(minimumX, maximumX))

        let aboveY = selection.maxY + gap
        let belowY = selection.minY - gap - size.height
        let fitsAbove = aboveY + size.height <= container.maxY - margin
        let fitsBelow = belowY >= container.minY + margin

        let y: CGFloat
        if fitsAbove {
            y = aboveY
        } else if fitsBelow {
            y = belowY
        } else {
            let spaceAbove = container.maxY - selection.maxY
            let spaceBelow = selection.minY - container.minY
            if spaceAbove >= spaceBelow {
                y = min(
                    max(aboveY, container.minY + margin),
                    container.maxY - margin - size.height
                )
            } else {
                y = min(
                    max(belowY, container.minY + margin),
                    container.maxY - margin - size.height
                )
            }
        }

        return CGRect(origin: CGPoint(x: x, y: y), size: size)
    }
}
