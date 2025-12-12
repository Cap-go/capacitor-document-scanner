import UIKit
import VisionKit

/**
 Handles presenting the VisionKit document scanner and returning results.
 */
@available(iOS 13.0, *)
class DocScanner: NSObject, VNDocumentCameraViewControllerDelegate {
    private weak var viewController: UIViewController?
    private var successHandler: ([String]) -> Void
    private var errorHandler: (String) -> Void
    private var cancelHandler: () -> Void
    private var responseType: String
    private var croppedImageQuality: Int
    private var brightness: Float
    private var contrast: Float

    init(
        _ viewController: UIViewController? = nil,
        successHandler: @escaping ([String]) -> Void = { _ in },
        errorHandler: @escaping (String) -> Void = { _ in },
        cancelHandler: @escaping () -> Void = {},
        responseType: String = ResponseType.imageFilePath,
        croppedImageQuality: Int = 100,
        brightness: Float = 0.0,
        contrast: Float = 1.0
    ) {
        self.viewController = viewController
        self.successHandler = successHandler
        self.errorHandler = errorHandler
        self.cancelHandler = cancelHandler
        self.responseType = responseType
        self.croppedImageQuality = croppedImageQuality
        self.brightness = brightness
        self.contrast = contrast
    }

    override convenience init() {
        self.init(nil)
    }

    func startScan() {
        guard VNDocumentCameraViewController.isSupported else {
            errorHandler("Document scanning is not supported on this device.")
            return
        }

        DispatchQueue.main.async {
            let documentCameraViewController = VNDocumentCameraViewController()
            documentCameraViewController.delegate = self
            self.viewController?.present(documentCameraViewController, animated: true)
        }
    }

    func startScan(
        _ viewController: UIViewController? = nil,
        successHandler: @escaping ([String]) -> Void = { _ in },
        errorHandler: @escaping (String) -> Void = { _ in },
        cancelHandler: @escaping () -> Void = {},
        responseType: String? = ResponseType.imageFilePath,
        croppedImageQuality: Int? = 100,
        brightness: Float? = 0.0,
        contrast: Float? = 1.0
    ) {
        self.viewController = viewController
        self.successHandler = successHandler
        self.errorHandler = errorHandler
        self.cancelHandler = cancelHandler
        self.responseType = responseType ?? ResponseType.imageFilePath
        self.croppedImageQuality = croppedImageQuality ?? 100
        self.brightness = brightness ?? 0.0
        self.contrast = contrast ?? 1.0

        startScan()
    }

    func documentCameraViewController(
        _ controller: VNDocumentCameraViewController,
        didFinishWith scan: VNDocumentCameraScan
    ) {
        var results: [String] = []

        for pageNumber in 0 ..< scan.pageCount {
            var processedImage = scan.imageOfPage(at: pageNumber)

            // Apply brightness and contrast adjustments if needed
            if brightness != 0.0 || contrast != 1.0 {
                processedImage = applyBrightnessContrast(to: processedImage, brightness: brightness, contrast: contrast)
            }

            guard
                let scannedImageData = processedImage
                    .jpegData(compressionQuality: CGFloat(croppedImageQuality) / CGFloat(100))
            else {
                goBackToPreviousView(controller)
                errorHandler("Unable to get scanned document in jpeg format.")
                return
            }

            switch responseType {
            case ResponseType.base64:
                results.append(scannedImageData.base64EncodedString())
            case ResponseType.imageFilePath:
                do {
                    let imagePath = FileUtil().createImageFile(pageNumber)
                    try scannedImageData.write(to: imagePath)
                    results.append(imagePath.absoluteString)
                } catch {
                    goBackToPreviousView(controller)
                    errorHandler("Unable to save scanned image: \(error.localizedDescription)")
                    return
                }
            default:
                errorHandler(
                    "responseType must be \(ResponseType.base64) or \(ResponseType.imageFilePath)"
                )
                return
            }
        }

        goBackToPreviousView(controller)
        successHandler(results)
    }

    func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
        goBackToPreviousView(controller)
        cancelHandler()
    }

    func documentCameraViewController(
        _ controller: VNDocumentCameraViewController,
        didFailWithError error: Error
    ) {
        goBackToPreviousView(controller)
        errorHandler(error.localizedDescription)
    }

    private func goBackToPreviousView(_ controller: VNDocumentCameraViewController) {
        DispatchQueue.main.async {
            controller.dismiss(animated: true)
        }
    }

    /**
     Applies brightness and contrast adjustments to a UIImage using CIFilter.
     - Parameter image: The source image
     - Parameter brightness: Brightness adjustment (-255 to 255, 0 = no change)
     - Parameter contrast: Contrast adjustment (0.0 to 10.0, 1.0 = no change)
     - Returns: A new UIImage with adjustments applied
     */
    private func applyBrightnessContrast(to image: UIImage, brightness: Float, contrast: Float) -> UIImage {
        guard let ciImage = CIImage(image: image) else {
            return image
        }

        // Normalize brightness from (-255, 255) to (-1, 1) for CIColorControls
        let normalizedBrightness = brightness / 255.0

        let filter = CIFilter(name: "CIColorControls")
        filter?.setValue(ciImage, forKey: kCIInputImageKey)
        filter?.setValue(normalizedBrightness, forKey: kCIInputBrightnessKey)
        filter?.setValue(contrast, forKey: kCIInputContrastKey)

        guard let outputImage = filter?.outputImage else {
            return image
        }

        let context = CIContext()
        guard let cgImage = context.createCGImage(outputImage, from: outputImage.extent) else {
            return image
        }

        return UIImage(cgImage: cgImage, scale: image.scale, orientation: image.imageOrientation)
    }
}
