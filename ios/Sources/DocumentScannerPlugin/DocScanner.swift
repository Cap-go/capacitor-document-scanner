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

    init(
        _ viewController: UIViewController? = nil,
        successHandler: @escaping ([String]) -> Void = { _ in },
        errorHandler: @escaping (String) -> Void = { _ in },
        cancelHandler: @escaping () -> Void = {},
        responseType: String = ResponseType.imageFilePath,
        croppedImageQuality: Int = 100
    ) {
        self.viewController = viewController
        self.successHandler = successHandler
        self.errorHandler = errorHandler
        self.cancelHandler = cancelHandler
        self.responseType = responseType
        self.croppedImageQuality = croppedImageQuality
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
        croppedImageQuality: Int? = 100
    ) {
        self.viewController = viewController
        self.successHandler = successHandler
        self.errorHandler = errorHandler
        self.cancelHandler = cancelHandler
        self.responseType = responseType ?? ResponseType.imageFilePath
        self.croppedImageQuality = croppedImageQuality ?? 100

        startScan()
    }

    func documentCameraViewController(
        _ controller: VNDocumentCameraViewController,
        didFinishWith scan: VNDocumentCameraScan
    ) {
        var results: [String] = []

        for pageNumber in 0 ..< scan.pageCount {
            guard
                let scannedImageData = scan.imageOfPage(at: pageNumber)
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
}
