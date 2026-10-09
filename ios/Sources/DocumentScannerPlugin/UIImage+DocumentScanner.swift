import UIKit

extension UIImage {
    func normalizedUpOrientation() -> UIImage {
        guard imageOrientation != .up else {
            return self
        }

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = scale
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }
}

extension UIImageView {
    func aspectFitImageRect() -> CGRect {
        guard let image else {
            return bounds
        }

        let viewSize = bounds.size
        guard viewSize.width > 0, viewSize.height > 0 else {
            return .zero
        }

        let imageRatio = image.size.width / max(image.size.height, 1)
        let viewRatio = viewSize.width / viewSize.height

        if imageRatio > viewRatio {
            let height = viewSize.width / imageRatio
            let originY = (viewSize.height - height) / 2
            return CGRect(x: 0, y: originY, width: viewSize.width, height: height)
        }

        let width = viewSize.height * imageRatio
        let originX = (viewSize.width - width) / 2
        return CGRect(x: originX, y: 0, width: width, height: viewSize.height)
    }
}
