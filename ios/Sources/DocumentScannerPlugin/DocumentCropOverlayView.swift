import UIKit

final class DocumentCropOverlayView: UIView {
    var quad: DocumentQuad = DocumentQuad.defaultInset(for: CGSize(width: 1, height: 1)) {
        didSet { setNeedsDisplay() }
    }

    /// Region where the image is drawn (aspect fit inside the overlay bounds).
    var interactionRect: CGRect = .zero {
        didSet { setNeedsDisplay() }
    }

    var onQuadChanged: ((DocumentQuad) -> Void)?

    private var activeCorner: Int?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isUserInteractionEnabled = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else {
            return
        }

        let points = cornerPointsInView()
        context.setStrokeColor(UIColor.systemGreen.cgColor)
        context.setLineWidth(3)
        context.move(to: points[0])
        for index in 1 ..< points.count {
            context.addLine(to: points[index])
        }
        context.closePath()
        context.strokePath()

        for point in points {
            let handleRect = CGRect(x: point.x - 14, y: point.y - 14, width: 28, height: 28)
            context.setFillColor(UIColor.systemGreen.cgColor)
            context.fillEllipse(in: handleRect)
        }
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else {
            return
        }
        let location = touch.location(in: self)
        activeCorner = nearestCornerIndex(to: location)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first, let activeCorner else {
            return
        }
        let location = touch.location(in: self)
        let rect = activeInteractionRect()
        let normalized = CGPoint(
            x: min(1, max(0, (location.x - rect.minX) / max(rect.width, 1))),
            y: min(1, max(0, (location.y - rect.minY) / max(rect.height, 1)))
        )
        updateCorner(index: activeCorner, to: normalized)
        onQuadChanged?(quad)
        setNeedsDisplay()
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        activeCorner = nil
    }

    private func activeInteractionRect() -> CGRect {
        if interactionRect.width > 0 && interactionRect.height > 0 {
            return interactionRect
        }
        return bounds
    }

    private func cornerPointsInView() -> [CGPoint] {
        let rect = activeInteractionRect()
        let quad = quad.clamped()
        return [
            CGPoint(x: rect.minX + quad.topLeft.x * rect.width, y: rect.minY + quad.topLeft.y * rect.height),
            CGPoint(x: rect.minX + quad.topRight.x * rect.width, y: rect.minY + quad.topRight.y * rect.height),
            CGPoint(x: rect.minX + quad.bottomRight.x * rect.width, y: rect.minY + quad.bottomRight.y * rect.height),
            CGPoint(x: rect.minX + quad.bottomLeft.x * rect.width, y: rect.minY + quad.bottomLeft.y * rect.height)
        ]
    }

    private func nearestCornerIndex(to point: CGPoint) -> Int {
        let points = cornerPointsInView()
        var bestIndex = 0
        var bestDistance = CGFloat.greatestFiniteMagnitude
        for (index, corner) in points.enumerated() {
            let distance = hypot(corner.x - point.x, corner.y - point.y)
            if distance < bestDistance {
                bestDistance = distance
                bestIndex = index
            }
        }
        return bestIndex
    }

    private func updateCorner(index: Int, to point: CGPoint) {
        switch index {
        case 0: quad.topLeft = point
        case 1: quad.topRight = point
        case 2: quad.bottomRight = point
        default: quad.bottomLeft = point
        }
    }
}
