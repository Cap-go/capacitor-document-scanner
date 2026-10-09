import UIKit

protocol ManagedDocumentScanFlowViewControllerDelegate: AnyObject {
    func managedDocumentScanFlowDidCancel(_ controller: ManagedDocumentScanFlowViewController)
    func managedDocumentScanFlow(
        _ controller: ManagedDocumentScanFlowViewController,
        didFinishWith images: [UIImage]
    )
    func managedDocumentScanFlow(_ controller: ManagedDocumentScanFlowViewController, didFail message: String)
}

struct ManagedDocumentScanConfiguration {
    let letUserAdjustCrop: Bool
    let reviewCapturedDocument: Bool
    let maxNumDocuments: Int?
}

final class ManagedDocumentScanFlowViewController: UINavigationController {
    weak var flowDelegate: ManagedDocumentScanFlowViewControllerDelegate?

    private let configuration: ManagedDocumentScanConfiguration
    private var acceptedImages: [UIImage] = []
    private var pendingImage: UIImage?
    private var pendingQuad: DocumentQuad?

    init(configuration: ManagedDocumentScanConfiguration) {
        self.configuration = configuration
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationBar.prefersLargeTitles = false
        showCamera()
    }

    private func showCamera() {
        if DocumentScanSessionPolicy.hasReachedPageLimit(
            acceptedCount: acceptedImages.count,
            maxNumDocuments: configuration.maxNumDocuments
        ) {
            flowDelegate?.managedDocumentScanFlow(self, didFinishWith: acceptedImages)
            return
        }

        let camera = LiveDocumentCameraViewController()
        camera.delegate = self
        setViewControllers([camera], animated: false)
    }

    private func allowsContinueAfterNextAppend() -> Bool {
        DocumentScanSessionPolicy.allowsContinueScanning(
            acceptedCount: acceptedImages.count + 1,
            maxNumDocuments: configuration.maxNumDocuments
        )
    }

    private func handleCapturedImage(_ image: UIImage, quad: DocumentQuad) {
        pendingImage = image
        pendingQuad = quad

        if DocumentScanSessionPolicy.shouldShowCropEditor(letUserAdjustCrop: configuration.letUserAdjustCrop) {
            let cropController = DocumentCropEditorViewController(
                sourceImage: image,
                initialQuad: quad,
                allowsContinueScanning: allowsContinueAfterNextAppend()
            )
            cropController.delegate = self
            pushViewController(cropController, animated: true)
            return
        }

        let corrected = DocumentPerspectiveCorrector.correctedImage(from: image, quad: quad) ?? image
        routeAfterCorrection(corrected, action: nil)
    }

    private func routeAfterCorrection(_ image: UIImage, action: DocumentPostCaptureAction?) {
        pendingImage = image
        let nextCount = acceptedImages.count + 1
        let needsReview = DocumentScanSessionPolicy.shouldShowReviewScreen(
            reviewCapturedDocument: configuration.reviewCapturedDocument,
            acceptedCountAfterAppend: nextCount,
            maxNumDocuments: configuration.maxNumDocuments
        )

        if needsReview {
            let review = DocumentPageReviewViewController(
                previewImage: image,
                pageNumber: nextCount,
                totalAccepted: nextCount,
                allowsContinueScanning: allowsContinueAfterNextAppend()
            )
            review.delegate = self
            pushViewController(review, animated: true)
            return
        }

        let resolvedAction = action ?? .continueScanning
        applyPostCaptureAction(resolvedAction, image: image)
    }

    private func applyPostCaptureAction(_ action: DocumentPostCaptureAction, image: UIImage) {
        acceptedImages.append(image)
        pendingImage = nil
        pendingQuad = nil

        switch action {
        case .continueScanning:
            if DocumentScanSessionPolicy.hasReachedPageLimit(
                acceptedCount: acceptedImages.count,
                maxNumDocuments: configuration.maxNumDocuments
            ) {
                flowDelegate?.managedDocumentScanFlow(self, didFinishWith: acceptedImages)
            } else {
                showCamera()
            }
        case .finishScanning:
            flowDelegate?.managedDocumentScanFlow(self, didFinishWith: acceptedImages)
        }
    }
}

extension ManagedDocumentScanFlowViewController: LiveDocumentCameraViewControllerDelegate {
    func liveDocumentCameraDidCancel(_ controller: LiveDocumentCameraViewController) {
        if acceptedImages.isEmpty {
            flowDelegate?.managedDocumentScanFlowDidCancel(self)
        } else {
            flowDelegate?.managedDocumentScanFlow(self, didFinishWith: acceptedImages)
        }
    }

    func liveDocumentCamera(
        _ controller: LiveDocumentCameraViewController,
        didCapture image: UIImage,
        detectedQuad: DocumentQuad
    ) {
        handleCapturedImage(image, quad: detectedQuad)
    }

    func liveDocumentCamera(_ controller: LiveDocumentCameraViewController, didFail message: String) {
        flowDelegate?.managedDocumentScanFlow(self, didFail: message)
    }
}

extension ManagedDocumentScanFlowViewController: DocumentCropEditorViewControllerDelegate {
    func documentCropEditorDidCancel(_ controller: DocumentCropEditorViewController) {
        flowDelegate?.managedDocumentScanFlowDidCancel(self)
    }

    func documentCropEditorDidRetake(_ controller: DocumentCropEditorViewController) {
        pendingImage = nil
        pendingQuad = nil
        showCamera()
    }

    func documentCropEditor(
        _ controller: DocumentCropEditorViewController,
        didFinishWith image: UIImage,
        action: DocumentPostCaptureAction
    ) {
        let needsReview = DocumentScanSessionPolicy.shouldShowReviewScreen(
            reviewCapturedDocument: configuration.reviewCapturedDocument,
            acceptedCountAfterAppend: acceptedImages.count + 1,
            maxNumDocuments: configuration.maxNumDocuments
        )

        if needsReview {
            pendingImage = image
            routeAfterCorrection(image, action: action)
            return
        }

        applyPostCaptureAction(action, image: image)
    }
}

extension ManagedDocumentScanFlowViewController: DocumentPageReviewViewControllerDelegate {
    func documentPageReviewDidCancel(_ controller: DocumentPageReviewViewController) {
        if acceptedImages.isEmpty {
            flowDelegate?.managedDocumentScanFlowDidCancel(self)
        } else {
            flowDelegate?.managedDocumentScanFlow(self, didFinishWith: acceptedImages)
        }
    }

    func documentPageReviewDidRetake(_ controller: DocumentPageReviewViewController) {
        pendingImage = nil
        pendingQuad = nil
        showCamera()
    }

    func documentPageReview(
        _ controller: DocumentPageReviewViewController,
        didChoose action: DocumentPostCaptureAction
    ) {
        guard let image = pendingImage else {
            showCamera()
            return
        }
        applyPostCaptureAction(action, image: image)
    }
}
