import CoreImage
import UIKit

enum DocumentPerspectiveCorrector {
    static func correctedImage(from image: UIImage, quad: DocumentQuad, context: CIContext = CIContext()) -> UIImage? {
        let uprightImage = image.normalizedUpOrientation()
        guard let cgImage = uprightImage.cgImage else {
            return nil
        }

        let imageSize = CGSize(width: cgImage.width, height: cgImage.height)
        let (topLeft, topRight, bottomRight, bottomLeft) = quad.clamped().pointsInPixels(imageSize: imageSize)
        let ciImage = CIImage(cgImage: cgImage)

        guard let filter = CIFilter(name: "CIPerspectiveCorrection") else {
            return nil
        }

        filter.setValue(ciImage, forKey: kCIInputImageKey)
        filter.setValue(CIVector(cgPoint: topLeft), forKey: "inputTopLeft")
        filter.setValue(CIVector(cgPoint: topRight), forKey: "inputTopRight")
        filter.setValue(CIVector(cgPoint: bottomRight), forKey: "inputBottomRight")
        filter.setValue(CIVector(cgPoint: bottomLeft), forKey: "inputBottomLeft")

        guard let outputImage = filter.outputImage,
              let outputCGImage = context.createCGImage(outputImage, from: outputImage.extent)
        else {
            return nil
        }

        return UIImage(cgImage: outputCGImage, scale: uprightImage.scale, orientation: .up)
    }
}
