import UIKit
import VisionKit

/// Global storage for maxNumDocuments limit (used by swizzled method)
private var documentScanLimit: Int?

/**
 Handles presenting the VisionKit document scanner and returning results.
 */
class DocScanner: NSObject, VNDocumentCameraViewControllerDelegate {
    private weak var viewController: UIViewController?
    private var successHandler: ([String]) -> Void
    private var errorHandler: (String) -> Void
    private var cancelHandler: () -> Void
    private var responseType: String
    private var croppedImageQuality: Int
    private var brightness: Float
    private var contrast: Float
    private var maxNumDocuments: Int?

    private static var swizzled = false

    init(
        _ viewController: UIViewController? = nil,
        successHandler: @escaping ([String]) -> Void = { _ in },
        errorHandler: @escaping (String) -> Void = { _ in },
        cancelHandler: @escaping () -> Void = {},
        responseType: String = ResponseType.imageFilePath,
        croppedImageQuality: Int = 100,
        brightness: Float = 0.0,
        contrast: Float = 1.0,
        maxNumDocuments: Int? = nil
    ) {
        self.viewController = viewController
        self.successHandler = successHandler
        self.errorHandler = errorHandler
        self.cancelHandler = cancelHandler
        self.responseType = responseType
        self.croppedImageQuality = croppedImageQuality
        self.brightness = brightness
        self.contrast = contrast
        self.maxNumDocuments = maxNumDocuments
    }

    override convenience init() {
        self.init(nil)
    }

    /// Swizzle the internal canAddImages method to enforce document limits
    private static func setupSwizzling() {
        guard !swizzled else { return }
        swizzled = true

        // Find the internal VNDocumentCameraViewController_InProcess class
        guard let inProcessClass = NSClassFromString("VNDocumentCameraViewController_InProcess") else {
            return
        }

        // Selector for the internal delegate method: documentCameraController:canAddImages:
        let originalSelector = NSSelectorFromString("documentCameraController:canAddImages:")
        let swizzledSelector = #selector(DocScanner.swizzled_documentCameraController(_:canAddImages:))

        guard let originalMethod = class_getInstanceMethod(inProcessClass, originalSelector),
              let swizzledMethod = class_getInstanceMethod(DocScanner.self, swizzledSelector) else {
            return
        }

        // Add the swizzled method to the target class
        let didAdd = class_addMethod(
            inProcessClass,
            swizzledSelector,
            method_getImplementation(swizzledMethod),
            method_getTypeEncoding(swizzledMethod)
        )

        if didAdd {
            guard let newSwizzledMethod = class_getInstanceMethod(inProcessClass, swizzledSelector) else {
                return
            }
            method_exchangeImplementations(originalMethod, newSwizzledMethod)
        } else {
            method_exchangeImplementations(originalMethod, swizzledMethod)
        }
    }

    /// Swizzled implementation that enforces document limits
    @objc dynamic func swizzled_documentCameraController(_ controller: AnyObject, canAddImages count: UInt64) -> Bool {
        // Check if we have a limit set
        if let limit = documentScanLimit, count >= UInt64(limit) {
            return false
        }
        // Call the original implementation (swizzled, so this calls original)
        return swizzled_documentCameraController(controller, canAddImages: count)
    }

    func startScan() {
        guard VNDocumentCameraViewController.isSupported else {
            errorHandler("Document scanning is not supported on this device.")
            return
        }

        // Set the global limit and setup swizzling if we have a limit
        if let limit = maxNumDocuments, limit > 0 {
            documentScanLimit = limit
            DocScanner.setupSwizzling()
        } else {
            documentScanLimit = nil
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
        contrast: Float? = 1.0,
        maxNumDocuments: Int? = nil
    ) {
        self.viewController = viewController
        self.successHandler = successHandler
        self.errorHandler = errorHandler
        self.cancelHandler = cancelHandler
        self.responseType = responseType ?? ResponseType.imageFilePath
        self.croppedImageQuality = croppedImageQuality ?? 100
        self.brightness = brightness ?? 0.0
        self.contrast = contrast ?? 1.0
        self.maxNumDocuments = maxNumDocuments

        startScan()
    }

    func documentCameraViewController(
        _ controller: VNDocumentCameraViewController,
        didFinishWith scan: VNDocumentCameraScan
    ) {
        var results: [String] = []

        // Limit pages to maxNumDocuments if specified
        let pageLimit = maxNumDocuments != nil ? min(scan.pageCount, maxNumDocuments!) : scan.pageCount

        for pageNumber in 0 ..< pageLimit {
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
        // Clear the global limit after scan completes
        documentScanLimit = nil
        successHandler(results)
    }

    func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
        goBackToPreviousView(controller)
        // Clear the global limit after scan is cancelled
        documentScanLimit = nil
        cancelHandler()
    }

    func documentCameraViewController(
        _ controller: VNDocumentCameraViewController,
        didFailWithError error: Error
    ) {
        goBackToPreviousView(controller)
        // Clear the global limit after scan fails
        documentScanLimit = nil
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
