import CoreGraphics

/// Four corners in normalized image coordinates (0...1), origin top-left.
struct DocumentQuad: Equatable {
    var topLeft: CGPoint
    var topRight: CGPoint
    var bottomRight: CGPoint
    var bottomLeft: CGPoint

    static func defaultInset(for size: CGSize, insetRatio: CGFloat = 0.08) -> DocumentQuad {
        let insetX = insetRatio
        let insetY = insetRatio * (size.width / max(size.height, 1))
        return DocumentQuad(
            topLeft: CGPoint(x: insetX, y: insetY),
            topRight: CGPoint(x: 1 - insetX, y: insetY),
            bottomRight: CGPoint(x: 1 - insetX, y: 1 - insetY),
            bottomLeft: CGPoint(x: insetX, y: 1 - insetY)
        )
    }

    func pointsInPixels(imageSize: CGSize) -> (CGPoint, CGPoint, CGPoint, CGPoint) {
        (
            CGPoint(x: topLeft.x * imageSize.width, y: topLeft.y * imageSize.height),
            CGPoint(x: topRight.x * imageSize.width, y: topRight.y * imageSize.height),
            CGPoint(x: bottomRight.x * imageSize.width, y: bottomRight.y * imageSize.height),
            CGPoint(x: bottomLeft.x * imageSize.width, y: bottomLeft.y * imageSize.height)
        )
    }

    func clamped() -> DocumentQuad {
        DocumentQuad(
            topLeft: clamp(topLeft),
            topRight: clamp(topRight),
            bottomRight: clamp(bottomRight),
            bottomLeft: clamp(bottomLeft)
        )
    }

    private func clamp(_ point: CGPoint) -> CGPoint {
        CGPoint(x: min(1, max(0, point.x)), y: min(1, max(0, point.y)))
    }

    /// Vision rectangle observations use a bottom-left origin; UIKit uses top-left.
    static func fromVisionNormalizedPoints(
        topLeft: CGPoint,
        topRight: CGPoint,
        bottomRight: CGPoint,
        bottomLeft: CGPoint
    ) -> DocumentQuad {
        func flip(_ point: CGPoint) -> CGPoint {
            CGPoint(x: point.x, y: 1 - point.y)
        }

        return DocumentQuad(
            topLeft: flip(topLeft),
            topRight: flip(topRight),
            bottomRight: flip(bottomRight),
            bottomLeft: flip(bottomLeft)
        )
    }
}
