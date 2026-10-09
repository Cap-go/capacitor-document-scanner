import CoreImage
import UIKit
import VisionKit

private protocol SimulatorDocumentScannerViewControllerDelegate: AnyObject {
    func simulatorDocumentScannerViewControllerDidCancel(_ controller: SimulatorDocumentScannerViewController)
    func simulatorDocumentScannerViewController(
        _ controller: SimulatorDocumentScannerViewController,
        didFinishWith images: [UIImage]
    )
}

private final class SimulatorDocumentScannerViewController: UIViewController {
    private let sampleImages: [UIImage]
    private weak var delegate: SimulatorDocumentScannerViewControllerDelegate?

    init(sampleImages: [UIImage], delegate: SimulatorDocumentScannerViewControllerDelegate) {
        self.sampleImages = sampleImages
        self.delegate = delegate
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        let titleLabel = UILabel()
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = "Simulator VisionKit Scanner"
        titleLabel.font = .systemFont(ofSize: 28, weight: .bold)
        titleLabel.textAlignment = .center
        titleLabel.accessibilityIdentifier = "simulator-scanner-title"

        let subtitleLabel = UILabel()
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        subtitleLabel.text = "Deterministic native harness for Maestro. Devices still use VisionKit."
        subtitleLabel.font = .systemFont(ofSize: 15, weight: .medium)
        subtitleLabel.textColor = .secondaryLabel
        subtitleLabel.textAlignment = .center
        subtitleLabel.numberOfLines = 0

        let previewImageView = UIImageView(image: sampleImages.first)
        previewImageView.translatesAutoresizingMaskIntoConstraints = false
        previewImageView.contentMode = .scaleAspectFit
        previewImageView.layer.cornerRadius = 20
        previewImageView.layer.masksToBounds = true
        previewImageView.layer.borderWidth = 1
        previewImageView.layer.borderColor = UIColor.separator.cgColor
        previewImageView.backgroundColor = UIColor.secondarySystemBackground

        let summaryLabel = UILabel()
        summaryLabel.translatesAutoresizingMaskIntoConstraints = false
        summaryLabel.text = "\(sampleImages.count) sample page\(sampleImages.count == 1 ? "" : "s") ready"
        summaryLabel.font = .monospacedSystemFont(ofSize: 14, weight: .semibold)
        summaryLabel.textColor = .secondaryLabel
        summaryLabel.textAlignment = .center

        let cancelButton = UIButton(type: .system)
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        cancelButton.setTitle("Cancel Scan", for: .normal)
        cancelButton.accessibilityIdentifier = "simulator-scanner-cancel-button"
        cancelButton.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
        cancelButton.backgroundColor = .secondarySystemBackground
        cancelButton.layer.cornerRadius = 16
        cancelButton.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)

        let useSampleButton = UIButton(type: .system)
        useSampleButton.translatesAutoresizingMaskIntoConstraints = false
        useSampleButton.setTitle("Use Sample Scan", for: .normal)
        useSampleButton.accessibilityIdentifier = "simulator-scanner-use-sample-button"
        useSampleButton.titleLabel?.font = .systemFont(ofSize: 17, weight: .bold)
        useSampleButton.setTitleColor(.white, for: .normal)
        useSampleButton.backgroundColor = .systemBlue
        useSampleButton.layer.cornerRadius = 16
        useSampleButton.addTarget(self, action: #selector(useSampleTapped), for: .touchUpInside)

        let buttonStack = UIStackView(arrangedSubviews: [cancelButton, useSampleButton])
        buttonStack.translatesAutoresizingMaskIntoConstraints = false
        buttonStack.axis = .vertical
        buttonStack.spacing = 12
        buttonStack.distribution = .fillEqually

        view.addSubview(titleLabel)
        view.addSubview(subtitleLabel)
        view.addSubview(previewImageView)
        view.addSubview(summaryLabel)
        view.addSubview(buttonStack)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 32),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            titleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),

            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 12),
            subtitleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            subtitleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),

            previewImageView.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 28),
            previewImageView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            previewImageView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            previewImageView.heightAnchor.constraint(equalTo: previewImageView.widthAnchor, multiplier: 1.35),

            summaryLabel.topAnchor.constraint(equalTo: previewImageView.bottomAnchor, constant: 16),
            summaryLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            summaryLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),

            buttonStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            buttonStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            buttonStack.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -24),
            buttonStack.heightAnchor.constraint(equalToConstant: 116),

            cancelButton.heightAnchor.constraint(equalToConstant: 52),
            useSampleButton.heightAnchor.constraint(equalToConstant: 52)
        ])
    }

    @objc private func cancelTapped() {
        delegate?.simulatorDocumentScannerViewControllerDidCancel(self)
    }

    @objc private func useSampleTapped() {
        delegate?.simulatorDocumentScannerViewController(self, didFinishWith: sampleImages)
    }
}

/**
 Handles presenting the VisionKit document scanner and returning results.
 */
class DocScanner: NSObject {
    private weak var viewController: UIViewController?
    private var successHandler: ([String]) -> Void
    private var errorHandler: (String) -> Void
    private var cancelHandler: () -> Void
    private var responseType: String
    private var croppedImageQuality: Int
    private var brightness: Float
    private var contrast: Float
    private var maxNumDocuments: Int?
    private var letUserAdjustCrop: Bool
    private var reviewCapturedDocument: Bool
    private let ciContext = CIContext()

    init(
        _ viewController: UIViewController? = nil,
        successHandler: @escaping ([String]) -> Void = { _ in },
        errorHandler: @escaping (String) -> Void = { _ in },
        cancelHandler: @escaping () -> Void = {},
        responseType: String = ResponseType.imageFilePath,
        croppedImageQuality: Int = 100,
        brightness: Float = 0.0,
        contrast: Float = 1.0,
        maxNumDocuments: Int? = nil,
        letUserAdjustCrop: Bool = true,
        reviewCapturedDocument: Bool = false
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
        self.letUserAdjustCrop = letUserAdjustCrop
        self.reviewCapturedDocument = reviewCapturedDocument
    }

    override convenience init() {
        self.init(nil)
    }

    func startScan() {
        guard let viewController else {
            errorHandler("Bridge view controller unavailable.")
            return
        }

        if shouldUseSimulatorHarness {
            let simulatorController = SimulatorDocumentScannerViewController(
                sampleImages: makeSimulatorSampleImages(),
                delegate: self
            )
            simulatorController.modalPresentationStyle = .fullScreen
            DispatchQueue.main.async {
                viewController.present(simulatorController, animated: true)
            }
            return
        }

        guard VNDocumentCameraViewController.isSupported else {
            errorHandler("VisionKit document scanning is not supported on this device.")
            return
        }

        DispatchQueue.main.async {
            if DocumentScanSessionPolicy.usesVisionKitOnly(
                letUserAdjustCrop: self.letUserAdjustCrop,
                reviewCapturedDocument: self.reviewCapturedDocument,
                maxNumDocuments: self.maxNumDocuments
            ) {
                let documentCameraViewController = VNDocumentCameraViewController()
                documentCameraViewController.delegate = self
                viewController.present(documentCameraViewController, animated: true)
                return
            }

            let configuration = ManagedDocumentScanConfiguration(
                letUserAdjustCrop: self.letUserAdjustCrop,
                reviewCapturedDocument: self.reviewCapturedDocument,
                maxNumDocuments: self.maxNumDocuments
            )
            let managedFlow = ManagedDocumentScanFlowViewController(configuration: configuration)
            managedFlow.flowDelegate = self
            viewController.present(managedFlow, animated: true)
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
        maxNumDocuments: Int? = nil,
        letUserAdjustCrop: Bool = true,
        reviewCapturedDocument: Bool = false
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
        self.letUserAdjustCrop = letUserAdjustCrop
        self.reviewCapturedDocument = reviewCapturedDocument

        startScan()
    }

    /// Clamps VisionKit batch results to a configured limit (managed flow enforces limits during capture).
    static func clampedPageCount(total: Int, limit: Int?) -> Int {
        guard let limit else {
            return total
        }

        return max(0, min(total, limit))
    }

    private var shouldUseSimulatorHarness: Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        return false
        #endif
    }

    private func finishScan(with scan: VNDocumentCameraScan) {
        processImages(pageCount: DocScanner.clampedPageCount(total: scan.pageCount, limit: maxNumDocuments)) { index in
            scan.imageOfPage(at: index)
        }
    }

    private func finishScan(with images: [UIImage]) {
        processImages(pageCount: DocScanner.clampedPageCount(total: images.count, limit: maxNumDocuments)) { index in
            images[index]
        }
    }

    private func processImages(pageCount: Int, imageProvider: @escaping (Int) -> UIImage) {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let results = try self.makeResults(pageCount: pageCount, imageProvider: imageProvider)
                DispatchQueue.main.async {
                    self.successHandler(results)
                }
            } catch RuntimeError.message(let message) {
                DispatchQueue.main.async {
                    self.errorHandler(message)
                }
            } catch {
                DispatchQueue.main.async {
                    self.errorHandler("Unable to save scanned image: \(error.localizedDescription)")
                }
            }
        }
    }

    private func makeResults(pageCount: Int, imageProvider: @escaping (Int) -> UIImage) throws -> [String] {
        var results: [String] = []
        results.reserveCapacity(pageCount)

        for index in 0 ..< pageCount {
            let result = try autoreleasepool {
                try self.process(image: imageProvider(index), at: index)
            }
            results.append(result)
        }

        return results
    }

    private func process(image: UIImage, at index: Int) throws -> String {
        let adjustedImage = applyBrightnessContrastIfNeeded(to: image)
        guard
            let imageData = adjustedImage.jpegData(
                compressionQuality: CGFloat(croppedImageQuality) / 100.0
            )
        else {
            throw RuntimeError.message("Unable to get scanned document in jpeg format.")
        }

        switch responseType {
        case ResponseType.base64:
            return imageData.base64EncodedString()
        case ResponseType.imageFilePath:
            let imagePath = FileUtil().createImageFile(index)
            try imageData.write(to: imagePath)
            return imagePath.absoluteString
        default:
            throw RuntimeError.message(
                "responseType must be \(ResponseType.base64) or \(ResponseType.imageFilePath)"
            )
        }
    }

    private func applyBrightnessContrastIfNeeded(to image: UIImage) -> UIImage {
        guard brightness != 0.0 || contrast != 1.0 else {
            return image
        }

        guard let ciImage = CIImage(image: image) else {
            return image
        }

        let filter = CIFilter(name: "CIColorControls")
        filter?.setValue(ciImage, forKey: kCIInputImageKey)
        filter?.setValue(brightness / 255.0, forKey: kCIInputBrightnessKey)
        filter?.setValue(contrast, forKey: kCIInputContrastKey)

        guard let outputImage = filter?.outputImage,
              let cgImage = ciContext.createCGImage(outputImage, from: outputImage.extent)
        else {
            return image
        }

        return UIImage(cgImage: cgImage, scale: image.scale, orientation: .up)
    }

    private func dismiss(_ controller: UIViewController, completion: @escaping () -> Void) {
        DispatchQueue.main.async {
            controller.dismiss(animated: true, completion: completion)
        }
    }

    private func makeSimulatorSampleImages() -> [UIImage] {
        let sampleCount = maxNumDocuments.map { max(1, min($0, 2)) } ?? 2
        return (1 ... sampleCount).map(makeSimulatorSampleImage(pageNumber:))
    }

    private func makeSimulatorSampleImage(pageNumber: Int) -> UIImage {
        let size = CGSize(width: 1240, height: 1754)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            let bounds = CGRect(origin: .zero, size: size)
            UIColor(red: 0.92, green: 0.95, blue: 1.0, alpha: 1).setFill()
            context.fill(bounds)

            let paperRect = bounds.insetBy(dx: 90, dy: 110)
            let paperPath = UIBezierPath(roundedRect: paperRect, cornerRadius: 28)
            UIColor.white.setFill()
            paperPath.fill()

            UIColor.black.withAlphaComponent(0.08).setStroke()
            paperPath.lineWidth = 3
            paperPath.stroke()

            let header = "MAESTRO TEST DOCUMENT \(pageNumber)"
            let headerAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 46, weight: .bold),
                .foregroundColor: UIColor.black
            ]
            header.draw(at: CGPoint(x: paperRect.minX + 70, y: paperRect.minY + 80), withAttributes: headerAttributes)

            let subheader = reviewCapturedDocument
                ? "VisionKit device path, simulator review harness"
                : "VisionKit device path, simulator deterministic harness"
            let subheaderAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 28, weight: .medium),
                .foregroundColor: UIColor.darkGray
            ]
            subheader.draw(
                at: CGPoint(x: paperRect.minX + 70, y: paperRect.minY + 150),
                withAttributes: subheaderAttributes
            )

            UIColor.systemBlue.setStroke()
            for index in 0 ..< 18 {
                let lineY = paperRect.minY + 260 + CGFloat(index * 62)
                let lineRect = CGRect(x: paperRect.minX + 70, y: lineY, width: paperRect.width - 140, height: 6)
                let linePath = UIBezierPath(roundedRect: lineRect, cornerRadius: 3)
                linePath.lineWidth = 1
                linePath.stroke()
            }
        }
    }
}

extension DocScanner: VNDocumentCameraViewControllerDelegate {
    func documentCameraViewController(
        _ controller: VNDocumentCameraViewController,
        didFinishWith scan: VNDocumentCameraScan
    ) {
        dismiss(controller) {
            self.finishScan(with: scan)
        }
    }

    func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
        dismiss(controller) {
            self.cancelHandler()
        }
    }

    func documentCameraViewController(
        _ controller: VNDocumentCameraViewController,
        didFailWithError error: Error
    ) {
        dismiss(controller) {
            self.errorHandler(error.localizedDescription)
        }
    }
}

extension DocScanner: ManagedDocumentScanFlowViewControllerDelegate {
    func managedDocumentScanFlowDidCancel(_ controller: ManagedDocumentScanFlowViewController) {
        dismiss(controller) {
            self.cancelHandler()
        }
    }

    func managedDocumentScanFlow(
        _ controller: ManagedDocumentScanFlowViewController,
        didFinishWith images: [UIImage]
    ) {
        dismiss(controller) {
            self.finishScan(with: images)
        }
    }

    func managedDocumentScanFlow(_ controller: ManagedDocumentScanFlowViewController, didFail message: String) {
        dismiss(controller) {
            self.errorHandler(message)
        }
    }
}

extension DocScanner: SimulatorDocumentScannerViewControllerDelegate {
    fileprivate func simulatorDocumentScannerViewControllerDidCancel(_ controller: SimulatorDocumentScannerViewController) {
        dismiss(controller) {
            self.cancelHandler()
        }
    }

    fileprivate func simulatorDocumentScannerViewController(
        _ controller: SimulatorDocumentScannerViewController,
        didFinishWith images: [UIImage]
    ) {
        dismiss(controller) {
            self.finishScan(with: images)
        }
    }
}
