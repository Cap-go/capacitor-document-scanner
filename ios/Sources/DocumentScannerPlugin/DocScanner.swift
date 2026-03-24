import UIKit
import VisionKit

/// Global storage for maxNumDocuments limit (used by swizzled method)
private var documentScanLimit: Int?

private func debugGeometryString(for point: CGPoint) -> String {
    NSCoder.string(for: point)
}

private func debugGeometryString(for rect: CGRect) -> String {
    NSCoder.string(for: rect)
}

private func docScannerDebugLog(_ message: @autoclosure () -> String) {
#if DEBUG
    NSLog("[DocScanner] %@", message())
#endif
}

private final class WeakDocumentCameraController {
    weak var value: VNDocumentCameraViewController?
}
private final class WeakScannerCounterLabel {
    weak var value: ScannerCounterBadgeLabel?
}
private final class WeakScannerInteractionBlockerView {
    weak var value: ScannerInteractionBlockerView?
}
private final class SuppressedCounterLabelState {
    weak var label: UILabel?
    let originalAlpha: CGFloat

    init(label: UILabel) {
        self.label = label
        self.originalAlpha = label.alpha
    }
}
private final class LockedCaptureControlState {
    weak var control: UIControl?
    let wasEnabled: Bool
    let wasUserInteractionEnabled: Bool
    let originalAlpha: CGFloat

    init(control: UIControl) {
        self.control = control
        self.wasEnabled = control.isEnabled
        self.wasUserInteractionEnabled = control.isUserInteractionEnabled
        self.originalAlpha = control.alpha
    }
}
private final class LockedBarButtonItemState {
    weak var item: UIBarButtonItem?
    let wasEnabled: Bool

    init(item: UIBarButtonItem) {
        self.item = item
        self.wasEnabled = item.isEnabled
    }
}
private final class ScannerInteractionBlockerView: UIView {
    var blockingRects: [CGRect] = []
    var passthroughRects: [CGRect] = []

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        let isBlocked = blockingRects.contains(where: { $0.contains(point) })
        let isPassthrough = passthroughRects.contains(where: { $0.contains(point) })

#if DEBUG
        if point.y >= bounds.height * 0.5 {
            let recipientDescription = debugHitTestRecipientDescription(at: point, with: event) ?? "nil"
            NSLog(
                "[DocScanner] blocker point=%@ blocked=%@ passthrough=%@ recipient=%@ blockingRects=%@ passthroughRects=%@",
                debugGeometryString(for: point),
                isBlocked.description,
                isPassthrough.description,
                recipientDescription,
                blockingRects.map { debugGeometryString(for: $0) }.joined(separator: ", "),
                passthroughRects.map { debugGeometryString(for: $0) }.joined(separator: ", ")
            )
        }
#endif

        guard isBlocked else {
            return false
        }

        return !isPassthrough
    }

#if DEBUG
    private func debugHitTestRecipientDescription(at point: CGPoint, with event: UIEvent?) -> String? {
        guard let superview else {
            return nil
        }

        let wasHidden = isHidden
        isHidden = true
        let recipient = superview.hitTest(point, with: event)
        isHidden = wasHidden

        guard let recipient else {
            return nil
        }

        let className = NSStringFromClass(type(of: recipient))
        let frameDescription = debugGeometryString(for: recipient.convert(recipient.bounds, to: superview))
        return "\(className) \(frameDescription)"
    }
#endif
}
private final class ScannerCounterBadgeLabel: UILabel {
    private let textInsets = UIEdgeInsets(top: 6, left: 12, bottom: 6, right: 12)

    override var intrinsicContentSize: CGSize {
        let size = super.intrinsicContentSize
        return CGSize(
            width: size.width + textInsets.left + textInsets.right,
            height: max(28, size.height + textInsets.top + textInsets.bottom)
        )
    }

    override func drawText(in rect: CGRect) {
        super.drawText(in: rect.inset(by: textInsets))
    }
}
private let activeDocumentCameraController = WeakDocumentCameraController()
private let activeDocumentCameraCounterLabel = WeakScannerCounterLabel()
private let activeDocumentCameraInteractionBlocker = WeakScannerInteractionBlockerView()
private var activeLockedCaptureControls: [LockedCaptureControlState] = []
private var activeLockedCaptureBarButtonItems: [LockedBarButtonItemState] = []
private var activeSuppressedNativeCounterLabels: [SuppressedCounterLabelState] = []
private var documentScanFinishRequested = false
private var documentScanModalSuppressionGeneration = 0
private var documentScanCounterDisplayGeneration = 0
private var documentScanCurrentCount = 0
private var documentScanTotalCount: Int?
private var documentScanAutoCaptureDisabled = false
private var documentScanAutoCaptureAttemptCount = 0
private var documentScanPreviewPresentationRequested = false
private var documentScanPreviewPresentationGeneration = 0
private var documentScanPreviewNavigationCustomized = false

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
        let canAddImages = swizzled_documentCameraController(controller, canAddImages: count)

        if let limit = documentScanLimit {
            DocScanner.scheduleCounterDisplayUpdate(rawCount: Int(count), totalCount: limit)
        }

        // Once the limit is reached, keep the scanner interactive and immediately
        // push VisionKit into preview instead of trying to fight its auto-capture mode.
        if let limit = documentScanLimit, count >= UInt64(limit + 1) {
            DocScanner.requestPreviewPresentationIfNeeded()
            return canAddImages
        }

        return canAddImages
    }

    func startScan() {
        guard VNDocumentCameraViewController.isSupported else {
            errorHandler("Document scanning is not supported on this device.")
            return
        }

        docScannerDebugLog(
            "startScan limit=\(maxNumDocuments.map(String.init) ?? "nil") responseType=\(responseType) quality=\(croppedImageQuality) brightness=\(brightness) contrast=\(contrast)"
        )

        // Set the global limit and setup swizzling if we have a limit
        if let limit = maxNumDocuments, limit > 0 {
            documentScanLimit = limit
            documentScanFinishRequested = false
            documentScanModalSuppressionGeneration += 1
            documentScanCounterDisplayGeneration += 1
            documentScanCurrentCount = 0
            documentScanTotalCount = limit
            activeDocumentCameraCounterLabel.value = nil
            activeDocumentCameraInteractionBlocker.value = nil
            activeLockedCaptureControls = []
            activeLockedCaptureBarButtonItems = []
            activeSuppressedNativeCounterLabels = []
            documentScanAutoCaptureDisabled = false
            documentScanAutoCaptureAttemptCount = 0
            documentScanPreviewPresentationRequested = false
            documentScanPreviewPresentationGeneration += 1
            documentScanPreviewNavigationCustomized = false
            DocScanner.setupSwizzling()
        } else {
            documentScanLimit = nil
            documentScanFinishRequested = false
            documentScanModalSuppressionGeneration += 1
            documentScanCounterDisplayGeneration += 1
            documentScanCurrentCount = 0
            documentScanTotalCount = nil
            activeDocumentCameraCounterLabel.value = nil
            activeDocumentCameraInteractionBlocker.value = nil
            activeLockedCaptureControls = []
            activeLockedCaptureBarButtonItems = []
            activeSuppressedNativeCounterLabels = []
            documentScanAutoCaptureDisabled = false
            documentScanAutoCaptureAttemptCount = 0
            documentScanPreviewPresentationRequested = false
            documentScanPreviewPresentationGeneration += 1
            documentScanPreviewNavigationCustomized = false
        }

        DispatchQueue.main.async {
            let documentCameraViewController = VNDocumentCameraViewController()
            documentCameraViewController.delegate = self
            activeDocumentCameraController.value = documentCameraViewController
            docScannerDebugLog("presenting VNDocumentCameraViewController limit=\(documentScanLimit.map(String.init) ?? "nil")")
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
        docScannerDebugLog(
            "didFinishWith pageCount=\(scan.pageCount) pageLimit=\(pageLimit) limit=\(maxNumDocuments.map(String.init) ?? "nil")"
        )

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

        // Clear the global limit before dismissing to avoid race conditions
        documentScanLimit = nil
        documentScanFinishRequested = false
        documentScanModalSuppressionGeneration += 1
        documentScanCounterDisplayGeneration += 1
        documentScanCurrentCount = 0
        documentScanTotalCount = nil
        documentScanAutoCaptureDisabled = false
        documentScanAutoCaptureAttemptCount = 0
        documentScanPreviewPresentationRequested = false
        documentScanPreviewPresentationGeneration += 1
        documentScanPreviewNavigationCustomized = false
        activeDocumentCameraCounterLabel.value = nil
        DocScanner.removeCaptureInteractionBlockerIfNeeded()
        DocScanner.restoreSuppressedNativeCounterLabelsIfNeeded()
        DocScanner.restoreLockedCaptureInteractionsIfNeeded()
        activeDocumentCameraController.value = nil
        goBackToPreviousView(controller)
        successHandler(results)
    }

    func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
        docScannerDebugLog("didCancel currentCount=\(documentScanCurrentCount) total=\(documentScanTotalCount.map(String.init) ?? "nil")")
        // Clear the global limit before dismissing to avoid race conditions
        documentScanLimit = nil
        documentScanFinishRequested = false
        documentScanModalSuppressionGeneration += 1
        documentScanCounterDisplayGeneration += 1
        documentScanCurrentCount = 0
        documentScanTotalCount = nil
        documentScanAutoCaptureDisabled = false
        documentScanAutoCaptureAttemptCount = 0
        documentScanPreviewPresentationRequested = false
        documentScanPreviewPresentationGeneration += 1
        documentScanPreviewNavigationCustomized = false
        activeDocumentCameraCounterLabel.value = nil
        DocScanner.removeCaptureInteractionBlockerIfNeeded()
        DocScanner.restoreSuppressedNativeCounterLabelsIfNeeded()
        DocScanner.restoreLockedCaptureInteractionsIfNeeded()
        activeDocumentCameraController.value = nil
        goBackToPreviousView(controller)
        cancelHandler()
    }

    func documentCameraViewController(
        _ controller: VNDocumentCameraViewController,
        didFailWithError error: Error
    ) {
        docScannerDebugLog(
            "didFailWithError error=\(error.localizedDescription) currentCount=\(documentScanCurrentCount) total=\(documentScanTotalCount.map(String.init) ?? "nil")"
        )
        // Clear the global limit before dismissing to avoid race conditions
        documentScanLimit = nil
        documentScanFinishRequested = false
        documentScanModalSuppressionGeneration += 1
        documentScanCounterDisplayGeneration += 1
        documentScanCurrentCount = 0
        documentScanTotalCount = nil
        documentScanAutoCaptureDisabled = false
        documentScanAutoCaptureAttemptCount = 0
        documentScanPreviewPresentationRequested = false
        documentScanPreviewPresentationGeneration += 1
        documentScanPreviewNavigationCustomized = false
        activeDocumentCameraCounterLabel.value = nil
        DocScanner.removeCaptureInteractionBlockerIfNeeded()
        DocScanner.restoreSuppressedNativeCounterLabelsIfNeeded()
        DocScanner.restoreLockedCaptureInteractionsIfNeeded()
        activeDocumentCameraController.value = nil
        goBackToPreviousView(controller)
        errorHandler(error.localizedDescription)
    }

    private static func requestScanCompletionIfNeeded() -> Bool {
        guard !documentScanFinishRequested,
              let documentCameraViewController = activeDocumentCameraController.value
        else {
            docScannerDebugLog("requestScanCompletion skipped alreadyRequested=\(documentScanFinishRequested) hasController=\(activeDocumentCameraController.value != nil)")
            return false
        }

        docScannerDebugLog("requestScanCompletion started")
        documentScanFinishRequested = true
        let didTriggerCompletion: Bool

        if Thread.isMainThread {
            didTriggerCompletion = triggerScanCompletion(on: documentCameraViewController)
        } else {
            var triggeredCompletion = false
            DispatchQueue.main.sync {
                triggeredCompletion = triggerScanCompletion(on: documentCameraViewController)
            }
            didTriggerCompletion = triggeredCompletion
        }

        if !didTriggerCompletion {
            documentScanFinishRequested = false
        }

        docScannerDebugLog("requestScanCompletion result=\(didTriggerCompletion)")

        return didTriggerCompletion
    }

    private static func scheduleCounterDisplayUpdate(rawCount: Int, totalCount: Int) {
        guard documentScanLimit != nil, totalCount > 0 else {
            return
        }

        documentScanCurrentCount = max(0, min(rawCount - 1, totalCount))
        documentScanTotalCount = totalCount

        let generation = documentScanCounterDisplayGeneration + 1
        documentScanCounterDisplayGeneration = generation
        updateCounterDisplay(generation: generation)
    }

    private static func updateCounterDisplay(generation: Int) {
        DispatchQueue.main.async {
            guard generation == documentScanCounterDisplayGeneration,
                  documentScanLimit != nil,
                  let documentCameraViewController = activeDocumentCameraController.value,
                  let totalCount = documentScanTotalCount,
                  let rootView = resolvedView(for: documentCameraViewController)
            else {
                return
            }

            if documentScanCurrentCount <= 0 {
                activeDocumentCameraCounterLabel.value?.isHidden = true
                removeCaptureInteractionBlockerIfNeeded()
                restoreSuppressedNativeCounterLabelsIfNeeded()
                restoreLockedCaptureInteractionsIfNeeded()
            } else if shouldShowCounterBadge(in: documentCameraViewController) {
                let displayText = "\(documentScanCurrentCount)/\(totalCount)"
                applyCounterDisplayText(displayText, in: rootView)
                updateCaptureInteractionState(
                    in: documentCameraViewController,
                    isLocked: documentScanCurrentCount >= totalCount
                )
            } else {
                activeDocumentCameraCounterLabel.value?.isHidden = true
                removeCaptureInteractionBlockerIfNeeded()
                restoreSuppressedNativeCounterLabelsIfNeeded()
                restoreLockedCaptureInteractionsIfNeeded()
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                updateCounterDisplay(generation: generation)
            }
        }
    }

    private static func applyCounterDisplayText(_ displayText: String, in rootView: UIView) -> Bool {
        let counterLabel = ensureCounterLabel(in: rootView)
        counterLabel.isHidden = false
        counterLabel.text = displayText
        suppressNativeCounterLabels(in: rootView)
        return true
    }

    private static func ensureCounterLabel(in rootView: UIView) -> ScannerCounterBadgeLabel {
        if let existingCounterLabel = activeDocumentCameraCounterLabel.value {
            return existingCounterLabel
        }

        let counterLabel = ScannerCounterBadgeLabel()
        counterLabel.translatesAutoresizingMaskIntoConstraints = false
        counterLabel.backgroundColor = UIColor.black.withAlphaComponent(0.82)
        counterLabel.textColor = .white
        counterLabel.font = .monospacedDigitSystemFont(ofSize: 15, weight: .semibold)
        counterLabel.textAlignment = .center
        counterLabel.adjustsFontSizeToFitWidth = true
        counterLabel.minimumScaleFactor = 0.7
        counterLabel.layer.cornerRadius = 14
        counterLabel.clipsToBounds = true
        counterLabel.isUserInteractionEnabled = false

        rootView.addSubview(counterLabel)
        NSLayoutConstraint.activate([
            counterLabel.centerXAnchor.constraint(equalTo: rootView.centerXAnchor),
            counterLabel.topAnchor.constraint(equalTo: rootView.safeAreaLayoutGuide.topAnchor, constant: 10),
            counterLabel.widthAnchor.constraint(lessThanOrEqualTo: rootView.widthAnchor, multiplier: 0.45)
        ])

        activeDocumentCameraCounterLabel.value = counterLabel
        return counterLabel
    }

    private static func suppressNativeCounterLabels(in rootView: UIView) {
        var candidates: [UILabel] = []
        collectCounterCandidates(in: rootView, candidates: &candidates)

        let candidateIdentifiers = Set(candidates.map { ObjectIdentifier($0) })

        for state in activeSuppressedNativeCounterLabels {
            guard let label = state.label else {
                continue
            }

            if !candidateIdentifiers.contains(ObjectIdentifier(label)) {
                label.alpha = state.originalAlpha
            }
        }

        activeSuppressedNativeCounterLabels = activeSuppressedNativeCounterLabels.filter { state in
            guard let label = state.label else {
                return false
            }

            return candidateIdentifiers.contains(ObjectIdentifier(label))
        }

        for candidate in candidates {
            if !isTrackingSuppressedCounterLabel(candidate) {
                activeSuppressedNativeCounterLabels.append(SuppressedCounterLabelState(label: candidate))
            }

            candidate.alpha = 0
        }
    }

    private static func collectCounterCandidates(in view: UIView, candidates: inout [UILabel]) {
        if view.isHidden {
            return
        }

        if let label = view as? UILabel,
           label.alpha <= 0.01,
           !isTrackingSuppressedCounterLabel(label) {
            return
        }

        if !(view is UILabel), view.alpha <= 0.01 {
            return
        }

        if let label = view as? UILabel,
           isCounterCandidate(label) {
            candidates.append(label)
        }

        for subview in view.subviews {
            collectCounterCandidates(in: subview, candidates: &candidates)
        }
    }

    private static func isCounterCandidate(_ label: UILabel) -> Bool {
        if label === activeDocumentCameraCounterLabel.value {
            return false
        }

        if let rootView = activeDocumentCameraController.value?.view,
           !isTopCounterRegionCandidate(label, in: rootView) {
            return false
        }

        return isCounterText(label.text)
    }

    private static func isCounterText(_ text: String?) -> Bool {
        guard let trimmedText = text?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmedText.isEmpty
        else {
            return false
        }

        return trimmedText.allSatisfy { $0.isNumber || $0 == "/" }
    }

    private static func isTopCounterRegionCandidate(_ view: UIView, in rootView: UIView) -> Bool {
        let frame = view.convert(view.bounds, to: rootView)
        let topLimit = rootView.safeAreaInsets.top + 96
        return frame.minY >= rootView.safeAreaInsets.top - 8 && frame.maxY <= topLimit
    }

    private static func updateCaptureInteractionState(
        in scannerController: VNDocumentCameraViewController,
        isLocked: Bool
    ) {
        guard let rootView = resolvedView(for: scannerController) else {
            removeCaptureInteractionBlockerIfNeeded()
            restoreLockedCaptureInteractionsIfNeeded()
            return
        }

        let hasVisibleShutter = hasVisibleShutterSurface(in: rootView)

        guard isLocked,
              hasVisibleShutter
        else {
            removeCaptureInteractionBlockerIfNeeded()
            restoreLockedCaptureInteractionsIfNeeded()
            return
        }

        requestPreviewPresentationIfNeeded()
        showCaptureInteractionBlocker(in: rootView)
    }

    private static func requestPreviewPresentationIfNeeded() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async {
                requestPreviewPresentationIfNeeded()
            }
            return
        }

        guard !documentScanPreviewPresentationRequested,
              let documentCameraViewController = activeDocumentCameraController.value
        else {
            if let documentCameraViewController = activeDocumentCameraController.value,
               !hasLiveCaptureVisible(around: documentCameraViewController) {
                customizePreviewNavigationIfNeeded(around: documentCameraViewController)
            }
            return
        }

        documentScanPreviewPresentationRequested = true
        let generation = documentScanPreviewPresentationGeneration + 1
        documentScanPreviewPresentationGeneration = generation
        attemptPreviewPresentation(
            generation: generation,
            remainingAttempts: 8
        )
    }

    private static func attemptPreviewPresentation(generation: Int, remainingAttempts: Int) {
        DispatchQueue.main.async {
            guard generation == documentScanPreviewPresentationGeneration,
                  let documentCameraViewController = activeDocumentCameraController.value
            else {
                return
            }

            if !hasLiveCaptureVisible(around: documentCameraViewController),
               customizePreviewNavigationIfNeeded(around: documentCameraViewController) {
                return
            }

            guard let rootView = resolvedView(for: documentCameraViewController) else {
                return
            }
            let didTriggerPreview: Bool

            if let previewView = findFirstView(namedLike: ["ICDocCamThumbnailContainerView"], in: rootView) {
                didTriggerPreview = triggerInteraction(around: previewView, in: rootView)
            } else {
                let previewFrame = previewHotspotFrame(in: rootView)
                let previewPoint = CGPoint(x: previewFrame.midX, y: previewFrame.midY)
                didTriggerPreview = triggerInteraction(at: previewPoint, in: rootView)
            }

            if didTriggerPreview {
                docScannerDebugLog("preview presentation triggered at limit")
            }

            guard remainingAttempts > 0 else {
                return
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                attemptPreviewPresentation(
                    generation: generation,
                    remainingAttempts: remainingAttempts - 1
                )
            }
        }
    }

    @discardableResult
    private static func customizePreviewNavigationIfNeeded(around scannerController: UIViewController) -> Bool {
        guard !hasLiveCaptureVisible(around: scannerController) else {
            return false
        }

        guard let previewController = findVisiblePreviewOrEditorController(around: scannerController) else {
            return false
        }

        guard !documentScanPreviewNavigationCustomized else {
            return true
        }

        let completionButton = findCompletionButton(in: scannerController)
        let completionTitle = completionButton?.title ?? "Validate"
        let completionStyle = completionButton?.style == .plain ? UIBarButtonItem.Style.plain : .done
        let completionTarget = completionButton?.target
        let completionAction = completionButton?.action

        previewController.navigationItem.hidesBackButton = true
        previewController.navigationItem.setHidesBackButton(true, animated: false)
        previewController.navigationItem.leftItemsSupplementBackButton = false

        if let completionAction {
            previewController.navigationItem.leftBarButtonItem = UIBarButtonItem(
                title: completionTitle,
                style: completionStyle,
                target: completionTarget,
                action: completionAction
            )
        }

        documentScanPreviewNavigationCustomized = true
        docScannerDebugLog(
            "preview navigation customized controller=\(NSStringFromClass(type(of: previewController))) title=\(completionTitle)"
        )
        return true
    }

    private static func requestAutomaticCaptureStopIfNeeded() {
        guard !documentScanAutoCaptureDisabled,
              let documentCameraViewController = activeDocumentCameraController.value
        else {
            return
        }

        documentScanAutoCaptureAttemptCount += 1
        let attemptNumber = documentScanAutoCaptureAttemptCount
        let searchRootView = automaticCaptureSearchRootView(for: documentCameraViewController)
        let didDisableAutoCapture: Bool

        if Thread.isMainThread {
            didDisableAutoCapture = disableAutomaticCaptureIfPossible(
                in: searchRootView,
                attemptNumber: attemptNumber
            )
        } else {
            var disabledAutoCapture = false
            DispatchQueue.main.sync {
                disabledAutoCapture = disableAutomaticCaptureIfPossible(
                    in: searchRootView,
                    attemptNumber: attemptNumber
                )
            }
            didDisableAutoCapture = disabledAutoCapture
        }

        if didDisableAutoCapture {
            documentScanAutoCaptureDisabled = true
        }
    }

    private static func disableAutomaticCaptureIfPossible(in rootView: UIView, attemptNumber: Int) -> Bool {
        let segmentedControl = findAutoCaptureSegmentedControl(in: rootView)
        let targetView = findAutoCaptureTargetView(
            in: rootView,
            preferredKeywords: ["off", "manual"]
        )
        let modeFrame = findAutoCaptureModeFrame(in: rootView)
        let toggleControl = findAutoCaptureToggleControl(in: rootView)

#if DEBUG
        if shouldLogAutoCaptureAttempt(attemptNumber) {
            NSLog(
                "[DocScanner] auto attempt=%ld root=%@ segmented=%@ target=%@ modeFrame=%@ toggle=%@",
                attemptNumber,
                describeView(rootView, in: rootView),
                describeAutoCaptureSegmentedControl(segmentedControl, in: rootView),
                describeAutoCaptureView(targetView, in: rootView),
                modeFrame.map { debugGeometryString(for: $0) } ?? "nil",
                describeAutoCaptureControl(toggleControl, in: rootView)
            )
        }
#endif

        if let segmentedControl,
           let targetIndex = preferredAutoCaptureDisabledSegmentIndex(in: segmentedControl) {
            if segmentedControl.selectedSegmentIndex != targetIndex {
                segmentedControl.selectedSegmentIndex = targetIndex
                segmentedControl.sendActions(for: .valueChanged)
            }
#if DEBUG
            NSLog(
                "[DocScanner] auto capture disabled via %@ segment=%ld",
                NSStringFromClass(type(of: segmentedControl)),
                targetIndex
            )
#endif
            return true
        }

        if let targetView, triggerInteraction(around: targetView, in: rootView) {
#if DEBUG
            NSLog(
                "[DocScanner] auto capture target triggered via %@ texts=%@",
                NSStringFromClass(type(of: targetView)),
                normalizedVisibleTexts(in: targetView).joined(separator: ", ")
            )
#endif
            return true
        }

        if let modeFrame,
           triggerInteraction(at: CGPoint(x: modeFrame.maxX - modeFrame.width * 0.18, y: modeFrame.midY), in: rootView) {
#if DEBUG
            NSLog(
                "[DocScanner] auto capture right-side tap triggered frame=%@",
                debugGeometryString(for: modeFrame)
            )
#endif
            return true
        }

        if let control = toggleControl {
            triggerBestPrimaryAction(for: control)
#if DEBUG
            NSLog(
                "[DocScanner] auto capture toggle triggered via %@ descriptors=%@",
                NSStringFromClass(type(of: control)),
                normalizedActionDescriptors(for: control).joined(separator: ", ")
            )
#endif
            return true
        }

#if DEBUG
        if shouldLogAutoCaptureAttempt(attemptNumber) {
            NSLog("[DocScanner] auto attempt=%ld no candidate matched", attemptNumber)
        }
#endif
        return false
    }

    private static func shouldLogAutoCaptureAttempt(_ attemptNumber: Int) -> Bool {
        attemptNumber <= 3 || attemptNumber % 25 == 0
    }

    private static func describeAutoCaptureSegmentedControl(
        _ control: UISegmentedControl?,
        in rootView: UIView
    ) -> String {
        guard let control else {
            return "nil"
        }

        let frame = control.convert(control.bounds, to: rootView)
        let titles = (0 ..< control.numberOfSegments).map { index in
            control.titleForSegment(at: index) ?? ""
        }
        return "\(NSStringFromClass(type(of: control))) frame=\(debugGeometryString(for: frame)) selected=\(control.selectedSegmentIndex) titles=\(titles.joined(separator: "|"))"
    }

    private static func describeAutoCaptureView(_ view: UIView?, in rootView: UIView) -> String {
        guard let view else {
            return "nil"
        }

        let frame = view.convert(view.bounds, to: rootView)
        let texts = normalizedVisibleTexts(in: view).joined(separator: ", ")
        return "\(NSStringFromClass(type(of: view))) frame=\(debugGeometryString(for: frame)) texts=\(texts)"
    }

    private static func describeAutoCaptureControl(_ control: UIControl?, in rootView: UIView) -> String {
        guard let control else {
            return "nil"
        }

        let frame = control.convert(control.bounds, to: rootView)
        let descriptors = normalizedActionDescriptors(for: control).joined(separator: ", ")
        return "\(NSStringFromClass(type(of: control))) frame=\(debugGeometryString(for: frame)) descriptors=\(descriptors)"
    }

    private static func describeView(_ view: UIView, in rootView: UIView) -> String {
        let frame = view.convert(view.bounds, to: rootView)
        return "\(NSStringFromClass(type(of: view))) frame=\(debugGeometryString(for: frame))"
    }

    private static func automaticCaptureSearchRootView(for controller: UIViewController) -> UIView {
        if let navigationController = controller.navigationController,
           let navigationView = resolvedView(for: navigationController) {
            return navigationView
        }

        if let superview = controller.view.superview {
            return superview
        }

        if let window = controller.view.window {
            return window
        }

        return resolvedView(for: controller) ?? UIView(frame: .zero)
    }

    private static func triggerInteraction(around view: UIView, in rootView: UIView) -> Bool {
        var currentView: UIView? = view

        while let candidate = currentView {
            if triggerInteraction(on: candidate) {
                return true
            }
            currentView = candidate.superview
        }

        let targetPoint = view.convert(CGPoint(x: view.bounds.midX, y: view.bounds.midY), to: rootView)
        return triggerInteraction(at: targetPoint, in: rootView)
    }

    private static func triggerInteraction(at point: CGPoint, in rootView: UIView) -> Bool {
        guard let hitView = rootView.hitTest(point, with: nil) else {
            return false
        }

        var currentView: UIView? = hitView

        while let candidate = currentView {
            if triggerInteraction(on: candidate) {
                return true
            }
            currentView = candidate.superview
        }

        return false
    }

    private static func triggerInteraction(on view: UIView) -> Bool {
        if let control = view as? UIControl {
            triggerBestPrimaryAction(for: control)
            return true
        }

        return triggerGestureRecognizers(on: view)
    }

    private static func triggerGestureRecognizers(on view: UIView) -> Bool {
        guard let gestureRecognizers = view.gestureRecognizers, !gestureRecognizers.isEmpty else {
            return false
        }

        for gestureRecognizer in gestureRecognizers where gestureRecognizer.isEnabled {
            guard let internalTargets = gestureRecognizer.value(forKey: "_targets") as? [NSObject] else {
                continue
            }

            for internalTarget in internalTargets {
                guard let invocation = gestureRecognizerInvocation(from: internalTarget)
                else {
                    continue
                }

                UIApplication.shared.sendAction(
                    invocation.selector,
                    to: invocation.target,
                    from: gestureRecognizer,
                    for: nil
                )
                return true
            }
        }

        return false
    }

    private static func gestureRecognizerInvocation(from internalTarget: NSObject) -> (target: AnyObject, selector: Selector)? {
        guard let targetClass: AnyClass = object_getClass(internalTarget),
              let targetIvar = class_getInstanceVariable(targetClass, "_target"),
              let actionIvar = class_getInstanceVariable(targetClass, "_action"),
              let target = object_getIvar(internalTarget, targetIvar) as AnyObject?
        else {
            return nil
        }

        let actionOffset = ivar_getOffset(actionIvar)
        let actionPointer = Unmanaged.passUnretained(internalTarget).toOpaque().advanced(by: actionOffset)
        let selector = actionPointer.load(as: Selector.self)

        guard let responder = target as? NSObjectProtocol,
              responder.responds?(to: selector) == true
        else {
            return nil
        }

        return (target, selector)
    }

    private static func triggerBestPrimaryAction(for control: UIControl) {
        let supportedEvents: [UIControl.Event] = [.primaryActionTriggered, .touchUpInside, .valueChanged]

        for event in supportedEvents {
            for target in control.allTargets {
                if let actions = control.actions(forTarget: target, forControlEvent: event),
                   !actions.isEmpty {
                    control.sendActions(for: event)
                    return
                }
            }
        }

        control.sendActions(for: .touchUpInside)
    }

    private static func showCaptureInteractionBlocker(in rootView: UIView) {
        let isNewBlocker = activeDocumentCameraInteractionBlocker.value == nil
        let blockerView = ensureCaptureInteractionBlocker(in: rootView)
        let nextFrame = rootView.bounds
        let nextBlockingRects = interactionBlockingRects(in: rootView)
        let nextPassthroughRects = interactionPassthroughRects(in: rootView)
        let needsGeometryUpdate = blockerView.frame != nextFrame
            || blockerView.blockingRects != nextBlockingRects
            || blockerView.passthroughRects != nextPassthroughRects

        if needsGeometryUpdate {
            blockerView.frame = nextFrame
            blockerView.blockingRects = nextBlockingRects
            blockerView.passthroughRects = nextPassthroughRects
        }
#if DEBUG
        if needsGeometryUpdate || isNewBlocker {
            NSLog(
                "[DocScanner] blocker configured frame=%@ blockingRects=%@ passthroughRects=%@",
                debugGeometryString(for: blockerView.frame),
                blockerView.blockingRects.map { debugGeometryString(for: $0) }.joined(separator: ", "),
                blockerView.passthroughRects.map { debugGeometryString(for: $0) }.joined(separator: ", ")
            )
        }
#endif
        if isNewBlocker {
            rootView.bringSubviewToFront(blockerView)
        }

        if let counterLabel = activeDocumentCameraCounterLabel.value,
           counterLabel.superview === rootView {
            rootView.bringSubviewToFront(counterLabel)
        }
    }

    private static func ensureCaptureInteractionBlocker(in rootView: UIView) -> ScannerInteractionBlockerView {
        if let existingBlocker = activeDocumentCameraInteractionBlocker.value {
            return existingBlocker
        }

        let blockerView = ScannerInteractionBlockerView(frame: rootView.bounds)
        blockerView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        blockerView.backgroundColor = .clear
        blockerView.isUserInteractionEnabled = true
        blockerView.accessibilityIdentifier = "CapgoDocumentScannerInteractionBlocker"

        rootView.addSubview(blockerView)
        activeDocumentCameraInteractionBlocker.value = blockerView
        return blockerView
    }

    private static func removeCaptureInteractionBlockerIfNeeded() {
        activeDocumentCameraInteractionBlocker.value?.removeFromSuperview()
        activeDocumentCameraInteractionBlocker.value = nil
    }

    private static func interactionBlockingRects(in rootView: UIView) -> [CGRect] {
        [rootView.bounds]
    }

    private static func interactionPassthroughRects(in rootView: UIView) -> [CGRect] {
        var rects: [CGRect] = []
        rects.append(contentsOf: framesForViews(namedLike: ["ICDocCamThumbnailContainerView"], in: rootView))
        rects.append(contentsOf: topBarFramesForPassthrough(in: rootView))

        if rects.isEmpty {
            rects.append(defaultTopBarPassthroughRect(in: rootView))
            rects.append(previewHotspotFrame(in: rootView))
        } else {
            if !rects.contains(where: { $0.intersects(previewHotspotFrame(in: rootView)) }) {
                rects.append(previewHotspotFrame(in: rootView))
            }
            if !rects.contains(where: { $0.intersects(defaultTopBarPassthroughRect(in: rootView)) }) {
                rects.append(defaultTopBarPassthroughRect(in: rootView))
            }
        }

        return rects.map { $0.insetBy(dx: -12, dy: -12) }
    }

    private static func topBarFramesForPassthrough(in rootView: UIView) -> [CGRect] {
        let allowedTopBand = defaultTopBarPassthroughRect(in: rootView)

        return framesForViews(namedLike: ["_UIFloatingBarContainerView"], in: rootView).compactMap { frame in
            let clippedFrame = frame.intersection(allowedTopBand)
            guard !clippedFrame.isNull, !clippedFrame.isEmpty else {
                return nil
            }

            return clippedFrame
        }
    }

    private static func framesForViews(namedLike classNameFragments: [String], in rootView: UIView) -> [CGRect] {
        var frames: [CGRect] = []
        collectFramesForViews(namedLike: classNameFragments, in: rootView, rootView: rootView, frames: &frames)
        return frames
    }

    private static func findFirstView(namedLike classNameFragments: [String], in rootView: UIView) -> UIView? {
        findFirstView(namedLike: classNameFragments, in: rootView, rootView: rootView)
    }

    private static func findFirstView(
        namedLike classNameFragments: [String],
        in view: UIView,
        rootView: UIView
    ) -> UIView? {
        guard !view.isHidden, view.alpha > 0.01 else {
            return nil
        }

        let className = NSStringFromClass(type(of: view))
        if classNameFragments.contains(where: { className.contains($0) }) {
            return view
        }

        for subview in view.subviews {
            if let matchingSubview = findFirstView(
                namedLike: classNameFragments,
                in: subview,
                rootView: rootView
            ) {
                return matchingSubview
            }
        }

        return nil
    }

    private static func collectFramesForViews(
        namedLike classNameFragments: [String],
        in view: UIView,
        rootView: UIView,
        frames: inout [CGRect]
    ) {
        guard !view.isHidden else {
            return
        }

        let className = NSStringFromClass(type(of: view))
        if classNameFragments.contains(where: { className.contains($0) }) {
            frames.append(view.convert(view.bounds, to: rootView))
        }

        for subview in view.subviews {
            collectFramesForViews(namedLike: classNameFragments, in: subview, rootView: rootView, frames: &frames)
        }
    }

    private static func defaultTopBarPassthroughRect(in rootView: UIView) -> CGRect {
        CGRect(
            x: 0,
            y: 0,
            width: rootView.bounds.width,
            height: rootView.safeAreaInsets.top + 60
        )
    }

    private static func findAutoCaptureSegmentedControl(in rootView: UIView) -> UISegmentedControl? {
        var candidates: [UISegmentedControl] = []
        collectAutoCaptureSegmentedControls(in: rootView, rootView: rootView, candidates: &candidates)

        return candidates.min { lhs, rhs in
            let lhsFrame = lhs.convert(lhs.bounds, to: rootView)
            let rhsFrame = rhs.convert(rhs.bounds, to: rootView)
            let lhsDistance = abs(lhsFrame.midX - rootView.bounds.midX)
            let rhsDistance = abs(rhsFrame.midX - rootView.bounds.midX)

            if lhsDistance == rhsDistance {
                return lhsFrame.minY < rhsFrame.minY
            }

            return lhsDistance < rhsDistance
        }
    }

    private static func collectAutoCaptureSegmentedControls(
        in view: UIView,
        rootView: UIView,
        candidates: inout [UISegmentedControl]
    ) {
        guard !view.isHidden, view.alpha > 0.01 else {
            return
        }

        if let segmentedControl = view as? UISegmentedControl {
            let frame = segmentedControl.convert(segmentedControl.bounds, to: rootView)
            if isAutoCaptureModeFrame(frame, in: rootView),
               preferredAutoCaptureDisabledSegmentIndex(in: segmentedControl) != nil {
                candidates.append(segmentedControl)
            }
        }

        for subview in view.subviews {
            collectAutoCaptureSegmentedControls(in: subview, rootView: rootView, candidates: &candidates)
        }
    }

    private static func preferredAutoCaptureDisabledSegmentIndex(in control: UISegmentedControl) -> Int? {
        guard control.numberOfSegments > 0 else {
            return nil
        }

        let titles = (0 ..< control.numberOfSegments).map { index in
            normalizeActionText(control.titleForSegment(at: index)) ?? ""
        }

        if control.selectedSegmentIndex >= 0,
           control.selectedSegmentIndex < titles.count {
            let selectedTitle = titles[control.selectedSegmentIndex]
            if selectedTitle.contains("off") || selectedTitle.contains("manual") {
                return control.selectedSegmentIndex
            }
        }

        if let offIndex = titles.firstIndex(where: { $0.contains("off") || $0.contains("manual") }) {
            return offIndex
        }

        if let nonAutoIndex = titles.firstIndex(where: { !$0.isEmpty && !$0.contains("auto") }) {
            return nonAutoIndex
        }

        return nil
    }

    private static func findAutoCaptureToggleControl(in rootView: UIView) -> UIControl? {
        var candidates: [UIControl] = []
        collectAutoCaptureToggleControls(in: rootView, rootView: rootView, candidates: &candidates)

        return candidates.min { lhs, rhs in
            let lhsFrame = lhs.convert(lhs.bounds, to: rootView)
            let rhsFrame = rhs.convert(rhs.bounds, to: rootView)
            let lhsScore = autoCaptureTogglePriority(for: lhs, frame: lhsFrame, in: rootView)
            let rhsScore = autoCaptureTogglePriority(for: rhs, frame: rhsFrame, in: rootView)
            return lhsScore < rhsScore
        }
    }

    private static func findAutoCaptureTargetView(
        in rootView: UIView,
        preferredKeywords: [String]
    ) -> UIView? {
        var candidates: [UIView] = []
        collectAutoCaptureTargetViews(
            in: rootView,
            rootView: rootView,
            preferredKeywords: preferredKeywords,
            candidates: &candidates
        )

        return candidates.min { lhs, rhs in
            let lhsFrame = lhs.convert(lhs.bounds, to: rootView)
            let rhsFrame = rhs.convert(rhs.bounds, to: rootView)
            let lhsTexts = normalizedVisibleTexts(in: lhs)
            let rhsTexts = normalizedVisibleTexts(in: rhs)
            let lhsScore = autoCaptureTargetPriority(
                forTexts: lhsTexts,
                frame: lhsFrame,
                preferredKeywords: preferredKeywords,
                in: rootView
            )
            let rhsScore = autoCaptureTargetPriority(
                forTexts: rhsTexts,
                frame: rhsFrame,
                preferredKeywords: preferredKeywords,
                in: rootView
            )
            return lhsScore < rhsScore
        }
    }

    private static func collectAutoCaptureTargetViews(
        in view: UIView,
        rootView: UIView,
        preferredKeywords: [String],
        candidates: inout [UIView]
    ) {
        guard !view.isHidden, view.alpha > 0.01 else {
            return
        }

        let frame = view.convert(view.bounds, to: rootView)
        let texts = normalizedVisibleTexts(in: view)

        if isAutoCaptureModeFrame(frame, in: rootView),
           texts.contains(where: { text in preferredKeywords.contains(where: text.contains) }) {
            candidates.append(view)
        }

        for subview in view.subviews {
            collectAutoCaptureTargetViews(
                in: subview,
                rootView: rootView,
                preferredKeywords: preferredKeywords,
                candidates: &candidates
            )
        }
    }

    private static func findAutoCaptureModeFrame(in rootView: UIView) -> CGRect? {
        var frames: [CGRect] = []
        collectAutoCaptureModeFrames(in: rootView, rootView: rootView, frames: &frames)

        return frames.min { lhs, rhs in
            let lhsDistance = abs(lhs.midX - rootView.bounds.midX)
            let rhsDistance = abs(rhs.midX - rootView.bounds.midX)

            if lhsDistance == rhsDistance {
                return lhs.minY < rhs.minY
            }

            return lhsDistance < rhsDistance
        }
    }

    private static func collectAutoCaptureModeFrames(
        in view: UIView,
        rootView: UIView,
        frames: inout [CGRect]
    ) {
        guard !view.isHidden, view.alpha > 0.01 else {
            return
        }

        let frame = view.convert(view.bounds, to: rootView)
        let texts = normalizedVisibleTexts(in: view)

        if isAutoCaptureModeFrame(frame, in: rootView),
           texts.contains(where: { $0.contains("auto") }),
           texts.contains(where: { $0.contains("off") || $0.contains("manual") }) {
            frames.append(frame)
        }

        for subview in view.subviews {
            collectAutoCaptureModeFrames(in: subview, rootView: rootView, frames: &frames)
        }
    }

    private static func collectAutoCaptureToggleControls(
        in view: UIView,
        rootView: UIView,
        candidates: inout [UIControl]
    ) {
        guard !view.isHidden, view.alpha > 0.01 else {
            return
        }

        if let control = view as? UIControl {
            let frame = control.convert(control.bounds, to: rootView)
            if isAutoCaptureToggleControl(control, frame: frame, in: rootView) {
                candidates.append(control)
            }
        }

        for subview in view.subviews {
            collectAutoCaptureToggleControls(in: subview, rootView: rootView, candidates: &candidates)
        }
    }

    private static func autoCaptureTogglePriority(for control: UIControl, frame: CGRect, in rootView: UIView) -> CGFloat {
        let descriptors = normalizedActionDescriptors(for: control)
        let preferenceBoost: CGFloat

        if descriptors.contains(where: { $0.contains("off") || $0.contains("manual") }) {
            preferenceBoost = 0
        } else if descriptors.contains(where: { $0.contains("auto") || $0.contains("automatic") }) {
            preferenceBoost = 1000
        } else {
            preferenceBoost = 2000
        }

        return preferenceBoost + abs(frame.midX - rootView.bounds.midX) + frame.minY
    }

    private static func autoCaptureTargetPriority(
        forTexts texts: [String],
        frame: CGRect,
        preferredKeywords: [String],
        in rootView: UIView
    ) -> CGFloat {
        let preferenceBoost: CGFloat

        if texts.contains(where: { text in preferredKeywords.contains(where: text.contains) }) {
            preferenceBoost = 0
        } else if texts.contains(where: { $0.contains("auto") }) {
            preferenceBoost = 1000
        } else {
            preferenceBoost = 2000
        }

        return preferenceBoost
            + abs(frame.midX - rootView.bounds.midX)
            + frame.minY
            + abs(frame.width - 60) * 0.1
            + abs(frame.height - 32) * 0.1
    }

    private static func isAutoCaptureToggleControl(
        _ control: UIControl,
        frame: CGRect,
        in rootView: UIView
    ) -> Bool {
        guard isAutoCaptureModeFrame(frame, in: rootView) else {
            return false
        }

        let descriptors = normalizedActionDescriptors(for: control)
        guard descriptors.contains(where: {
            $0.contains("auto") || $0.contains("automatic") || $0.contains("off") || $0.contains("manual")
        }) else {
            return false
        }

        let excludedKeywords = [
            "flash", "torch", "filter", "preview", "thumbnail",
            "done", "save", "cancel", "close", "back"
        ]

        return !descriptors.contains { descriptor in
            excludedKeywords.contains { keyword in descriptor.contains(keyword) }
        }
    }

    private static func isAutoCaptureModeFrame(_ frame: CGRect, in rootView: UIView) -> Bool {
        guard frame.width > 1,
              frame.height > 1,
              rootView.bounds.intersects(frame)
        else {
            return false
        }

        let topLimit = rootView.safeAreaInsets.top + 120
        let isCentered = abs(frame.midX - rootView.bounds.midX) <= rootView.bounds.width * 0.35
        let isLargeEnough = frame.width >= 80 && frame.height >= 28

        return frame.maxY <= topLimit && isCentered && isLargeEnough
    }

    private static func lockCaptureControls(in rootView: UIView) {
        var candidates: [UIControl] = []
        collectCaptureControlCandidates(in: rootView, rootView: rootView, candidates: &candidates)

        for control in candidates {
            guard !isTrackingLockedControl(control) else {
                control.isEnabled = false
                control.isUserInteractionEnabled = false
                control.alpha = min(control.alpha, 0.35)
                continue
            }

            activeLockedCaptureControls.append(LockedCaptureControlState(control: control))
            control.isEnabled = false
            control.isUserInteractionEnabled = false
            control.alpha = min(control.alpha, 0.35)
        }
    }

    private static func collectCaptureControlCandidates(
        in view: UIView,
        rootView: UIView,
        candidates: inout [UIControl]
    ) {
        guard !view.isHidden, view.alpha > 0.01 else {
            return
        }

        if let control = view as? UIControl,
           isCaptureControlCandidate(control, in: rootView) {
            candidates.append(control)
        }

        for subview in view.subviews {
            collectCaptureControlCandidates(in: subview, rootView: rootView, candidates: &candidates)
        }
    }

    private static func isCaptureControlCandidate(_ control: UIControl, in rootView: UIView) -> Bool {
        if control === activeDocumentCameraCounterLabel.value {
            return false
        }

        let frame = control.convert(control.bounds, to: rootView)
        guard frame.width > 1,
              frame.height > 1,
              rootView.bounds.intersects(frame)
        else {
            return false
        }

        if isPreviewInteractionFrame(frame, in: rootView),
           !isShutterLikeFrame(frame, in: rootView) {
            return false
        }

        if isPreservedActionControl(control) {
            return false
        }

        let rootHeight = rootView.bounds.height
        let isTopCaptureAction = isTopCaptureActionControl(control, frame: frame, in: rootView)
        let isBottomActionBand = frame.minY >= rootHeight * 0.56
        let isBottomCenterControl = isBottomActionBand && isShutterLikeFrame(frame, in: rootView)
        let isBottomTrailingControl = isBottomActionBand
            && frame.midX >= rootView.bounds.width * 0.68
            && isSmallActionIcon(frame)
            && isLockableActionControl(control)

        return isTopCaptureAction || isBottomCenterControl || isBottomTrailingControl
    }

    private static func hasVisibleShutterSurface(in rootView: UIView) -> Bool {
        var viewsToVisit: [UIView] = [rootView]

        while !viewsToVisit.isEmpty {
            let currentView = viewsToVisit.removeFirst()
            guard !currentView.isHidden, currentView.alpha > 0.01 else {
                continue
            }

            let frame = currentView.convert(currentView.bounds, to: rootView)
            if isShutterLikeFrame(frame, in: rootView) {
                return true
            }

            viewsToVisit.append(contentsOf: currentView.subviews)
        }

        return false
    }

    private static func isShutterLikeFrame(_ frame: CGRect, in rootView: UIView) -> Bool {
        guard frame.width > 1,
              frame.height > 1,
              rootView.bounds.intersects(frame)
        else {
            return false
        }

        let rootWidth = rootView.bounds.width
        let rootHeight = rootView.bounds.height
        let minSide = min(frame.width, frame.height)
        let maxSide = max(frame.width, frame.height)
        let isBottomBand = frame.minY >= rootHeight * 0.56
        let isCentered = abs(frame.midX - rootWidth / 2) <= rootWidth * 0.2
        let isLargePrimaryControl = minSide >= 56
            && maxSide <= 150
            && maxSide / max(minSide, 1) <= 1.35

        return isBottomBand && isCentered && isLargePrimaryControl
    }

    private static func isPreviewInteractionFrame(_ frame: CGRect, in rootView: UIView) -> Bool {
        frame.intersects(previewHotspotFrame(in: rootView))
    }

    private static func previewHotspotFrame(in rootView: UIView) -> CGRect {
        CGRect(
            x: 0,
            y: rootView.bounds.height * 0.56,
            width: rootView.bounds.width * 0.42,
            height: rootView.bounds.height * 0.44
        )
    }

    private static func isSmallActionIcon(_ frame: CGRect) -> Bool {
        let minSide = min(frame.width, frame.height)
        let maxSide = max(frame.width, frame.height)
        return minSide >= 28 && maxSide <= 72 && maxSide / max(minSide, 1) <= 1.35
    }

    private static func isPreservedActionControl(_ control: UIControl) -> Bool {
        let descriptors = normalizedActionDescriptors(for: control)
        let preservedKeywords = [
            "done", "save", "validate", "valider", "cancel", "close", "back",
            "preview", "thumbnail", "thumbnails", "pages", "gallery"
        ]

        return descriptors.contains { descriptor in
            preservedKeywords.contains { descriptor.contains($0) }
        }
    }

    private static func isLockableActionControl(_ control: UIControl) -> Bool {
        let descriptors = normalizedActionDescriptors(for: control)
        let lockableKeywords = [
            "flash", "torch", "filter", "capture", "shutter", "scan", "camera", "retake"
        ]

        return descriptors.contains { descriptor in
            lockableKeywords.contains { descriptor.contains($0) }
        }
    }

    private static func isTopCaptureActionControl(
        _ control: UIControl,
        frame: CGRect,
        in rootView: UIView
    ) -> Bool {
        let topActionLimit = rootView.safeAreaInsets.top + 96
        guard frame.maxY <= topActionLimit,
              isSmallActionIcon(frame)
        else {
            return false
        }

        return isLockableActionControl(control)
    }

    private static func normalizedActionText(for control: UIControl) -> String? {
        normalizedActionDescriptors(for: control).first
    }

    private static func normalizedActionDescriptors(for control: UIControl) -> [String] {
        var descriptors: [String] = []

        if let button = control as? UIButton {
            let buttonTitles = [
                button.title(for: .normal),
                button.title(for: .selected),
                button.title(for: .disabled)
            ]
            descriptors.append(contentsOf: buttonTitles.compactMap(normalizeActionText))
        }

        let accessibilityValues = [
            control.accessibilityLabel,
            control.accessibilityIdentifier,
            control.accessibilityValue
        ]
        descriptors.append(contentsOf: accessibilityValues.compactMap(normalizeActionText))
        descriptors.append(contentsOf: normalizedVisibleTexts(in: control))

        for target in control.allTargets {
            descriptors.append(normalizeActionText(String(describing: type(of: target))) ?? "")
            let supportedEvents: [UIControl.Event] = [.touchUpInside, .primaryActionTriggered, .valueChanged]

            for event in supportedEvents {
                let actions = control.actions(forTarget: target, forControlEvent: event) ?? []
                descriptors.append(contentsOf: actions.compactMap(normalizeActionText))
            }
        }

        return Array(Set(descriptors.filter { !$0.isEmpty }))
    }

    private static func normalizedVisibleTexts(in view: UIView) -> [String] {
        var texts: [String] = []
        collectNormalizedVisibleTexts(in: view, texts: &texts, depthRemaining: 3)
        return texts
    }

    private static func collectNormalizedVisibleTexts(
        in view: UIView,
        texts: inout [String],
        depthRemaining: Int
    ) {
        guard depthRemaining >= 0,
              !view.isHidden,
              view.alpha > 0.01
        else {
            return
        }

        if let label = view as? UILabel,
           let text = normalizeActionText(label.text) {
            texts.append(text)
        }

        if let button = view as? UIButton {
            let buttonTitles = [
                button.title(for: .normal),
                button.title(for: .selected),
                button.title(for: .disabled)
            ]
            texts.append(contentsOf: buttonTitles.compactMap(normalizeActionText))
        }

        if let segmentedControl = view as? UISegmentedControl {
            for index in 0 ..< segmentedControl.numberOfSegments {
                texts.append(normalizeActionText(segmentedControl.titleForSegment(at: index)) ?? "")
            }
        }

        guard depthRemaining > 0 else {
            return
        }

        for subview in view.subviews {
            collectNormalizedVisibleTexts(in: subview, texts: &texts, depthRemaining: depthRemaining - 1)
        }
    }

    private static func normalizeActionText(_ text: String?) -> String? {
        guard let text = text?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(),
              !text.isEmpty
        else {
            return nil
        }

        return text
    }

    private static func isTrackingLockedControl(_ control: UIControl) -> Bool {
        activeLockedCaptureControls.contains { $0.control === control }
    }

    private static func isTrackingSuppressedCounterLabel(_ label: UILabel) -> Bool {
        activeSuppressedNativeCounterLabels.contains { $0.label === label }
    }

    private static func lockCaptureBarButtonItems(around rootViewController: UIViewController) {
        var controllersToVisit: [UIViewController] = [rootViewController]
        var visitedControllers = Set<ObjectIdentifier>()

        while !controllersToVisit.isEmpty {
            let currentController = controllersToVisit.removeFirst()
            let identifier = ObjectIdentifier(currentController)

            guard visitedControllers.insert(identifier).inserted else {
                continue
            }

            let rightBarButtonItems = currentController.navigationItem.rightBarButtonItems ?? []
            for barButtonItem in rightBarButtonItems where shouldLockBarButtonItem(barButtonItem) {
                lockBarButtonItem(barButtonItem)
            }

            if let rightBarButtonItem = currentController.navigationItem.rightBarButtonItem,
               shouldLockBarButtonItem(rightBarButtonItem) {
                lockBarButtonItem(rightBarButtonItem)
            }

            if let navigationController = currentController as? UINavigationController {
                controllersToVisit.append(contentsOf: navigationController.viewControllers)
            }

            controllersToVisit.append(contentsOf: currentController.children)
        }
    }

    private static func shouldLockBarButtonItem(_ barButtonItem: UIBarButtonItem) -> Bool {
        guard !isCompletionButton(barButtonItem) else {
            return false
        }

        let normalizedTitle = normalizeActionText(barButtonItem.title)
        return normalizedTitle != "cancel"
            && normalizedTitle != "close"
            && normalizedTitle != "back"
    }

    private static func lockBarButtonItem(_ barButtonItem: UIBarButtonItem) {
        guard !isTrackingLockedBarButtonItem(barButtonItem) else {
            barButtonItem.isEnabled = false
            return
        }

        activeLockedCaptureBarButtonItems.append(LockedBarButtonItemState(item: barButtonItem))
        barButtonItem.isEnabled = false
    }

    private static func isTrackingLockedBarButtonItem(_ barButtonItem: UIBarButtonItem) -> Bool {
        activeLockedCaptureBarButtonItems.contains { $0.item === barButtonItem }
    }

    private static func restoreLockedCaptureInteractionsIfNeeded() {
        for state in activeLockedCaptureControls {
            guard let control = state.control else {
                continue
            }

            control.isEnabled = state.wasEnabled
            control.isUserInteractionEnabled = state.wasUserInteractionEnabled
            control.alpha = state.originalAlpha
        }

        activeLockedCaptureControls = []

        for state in activeLockedCaptureBarButtonItems {
            state.item?.isEnabled = state.wasEnabled
        }

        activeLockedCaptureBarButtonItems = []
    }

    private static func restorePreviewInteractionsIfNeeded(in rootView: UIView) {
        activeLockedCaptureControls.removeAll { state in
            guard let control = state.control else {
                return true
            }

            let frame = control.convert(control.bounds, to: rootView)
            guard isPreviewInteractionFrame(frame, in: rootView),
                  !isShutterLikeFrame(frame, in: rootView)
            else {
                return false
            }

            control.isEnabled = state.wasEnabled
            control.isUserInteractionEnabled = state.wasUserInteractionEnabled
            control.alpha = state.originalAlpha
            return true
        }
    }

    private static func restoreSuppressedNativeCounterLabelsIfNeeded() {
        for state in activeSuppressedNativeCounterLabels {
            guard let label = state.label else {
                continue
            }

            label.alpha = state.originalAlpha
        }

        activeSuppressedNativeCounterLabels = []
    }

    private static func shouldShowCounterBadge(in scannerController: VNDocumentCameraViewController) -> Bool {
        guard let rootView = resolvedView(for: scannerController) else {
            return false
        }

        return hasVisibleShutterSurface(in: rootView)
    }

    private static func resolvedView(for controller: UIViewController) -> UIView? {
        controller.viewIfLoaded ?? controller.view
    }

    private static func hasLiveCaptureVisible(around scannerController: UIViewController) -> Bool {
        guard let rootView = resolvedView(for: scannerController) else {
            return false
        }

        return hasVisibleShutterSurface(in: rootView)
    }

    private static func containsVisiblePreviewOrEditorController(around scannerController: UIViewController) -> Bool {
        findVisiblePreviewOrEditorController(around: scannerController) != nil
    }

    private static func findVisiblePreviewOrEditorController(around scannerController: UIViewController) -> UIViewController? {
        var controllersToVisit: [UIViewController] = []
        var visitedControllers = Set<ObjectIdentifier>()

        if let navigationController = scannerController.navigationController {
            if let topViewController = navigationController.topViewController,
               topViewController !== scannerController,
               topViewController.isViewLoaded,
               topViewController.view.window != nil {
                return topViewController
            }
            controllersToVisit.append(navigationController)
        }

        controllersToVisit.append(contentsOf: scannerController.children)

        if let presentedViewController = scannerController.presentedViewController {
            controllersToVisit.append(presentedViewController)
        }

        while !controllersToVisit.isEmpty {
            let currentController = controllersToVisit.removeFirst()
            let identifier = ObjectIdentifier(currentController)

            guard visitedControllers.insert(identifier).inserted else {
                continue
            }

            if currentController !== scannerController,
               currentController.isViewLoaded,
               currentController.view.window != nil,
               looksLikePreviewOrEditorController(currentController) {
                return currentController
            }

            if let navigationController = currentController as? UINavigationController {
                if let topViewController = navigationController.topViewController,
                   topViewController !== scannerController,
                   topViewController.isViewLoaded,
                   topViewController.view.window != nil {
                    return topViewController
                }
                controllersToVisit.append(contentsOf: navigationController.viewControllers)
            }

            controllersToVisit.append(contentsOf: currentController.children)

            if let presentedViewController = currentController.presentedViewController {
                controllersToVisit.append(presentedViewController)
            }
        }

        return nil
    }

    private static func looksLikePreviewOrEditorController(_ viewController: UIViewController) -> Bool {
        let className = NSStringFromClass(type(of: viewController)).lowercased()
        let previewKeywords = ["preview", "review", "edit", "editor", "filter", "rotate", "crop"]
        return previewKeywords.contains { className.contains($0) }
    }

    private static func suppressLimitModalIfNeeded() {
        let generation = documentScanModalSuppressionGeneration + 1
        documentScanModalSuppressionGeneration = generation
        suppressLimitModalIfNeeded(generation: generation, remainingAttempts: 12)
    }

    private static func suppressLimitModalIfNeeded(generation: Int, remainingAttempts: Int) {
        DispatchQueue.main.async {
            guard generation == documentScanModalSuppressionGeneration else {
                return
            }

            dismissVisibleLimitModalIfNeeded()

            guard remainingAttempts > 0 else {
                return
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                suppressLimitModalIfNeeded(generation: generation, remainingAttempts: remainingAttempts - 1)
            }
        }
    }

    private static func dismissVisibleLimitModalIfNeeded() {
        guard let documentCameraViewController = activeDocumentCameraController.value else {
            return
        }

        let modalsToDismiss = findPresentedModals(around: documentCameraViewController)
        for modal in modalsToDismiss {
            modal.view.alpha = 0
            modal.view.isHidden = true
            modal.dismiss(animated: false)
        }
    }

    private static func findPresentedModals(around rootViewController: UIViewController) -> [UIViewController] {
        var results: [UIViewController] = []
        var controllersToVisit: [UIViewController] = [rootViewController]
        var visitedControllers = Set<ObjectIdentifier>()
        var seenResults = Set<ObjectIdentifier>()

        while !controllersToVisit.isEmpty {
            let currentController = controllersToVisit.removeFirst()
            let identifier = ObjectIdentifier(currentController)

            guard visitedControllers.insert(identifier).inserted else {
                continue
            }

            if let presentedViewController = currentController.presentedViewController,
               shouldSuppressModal(presentedViewController, scannerRoot: rootViewController),
               seenResults.insert(ObjectIdentifier(presentedViewController)).inserted {
                results.append(presentedViewController)
            }

            if let navigationController = currentController as? UINavigationController {
                controllersToVisit.append(contentsOf: navigationController.viewControllers)
            }

            controllersToVisit.append(contentsOf: currentController.children)
        }

        if let windowScene = rootViewController.view.window?.windowScene {
            for window in windowScene.windows {
                guard let windowRootViewController = window.rootViewController else {
                    continue
                }

                if let modal = topPresentedViewController(from: windowRootViewController),
                   shouldSuppressModal(modal, scannerRoot: rootViewController),
                   seenResults.insert(ObjectIdentifier(modal)).inserted {
                    results.append(modal)
                }
            }
        }

        return results
    }

    private static func topPresentedViewController(from rootViewController: UIViewController) -> UIViewController? {
        var currentViewController: UIViewController? = rootViewController
        var lastPresentedViewController: UIViewController?

        while let presentedViewController = currentViewController?.presentedViewController {
            lastPresentedViewController = presentedViewController
            currentViewController = presentedViewController
        }

        return lastPresentedViewController
    }

    private static func shouldSuppressModal(
        _ viewController: UIViewController,
        scannerRoot: UIViewController
    ) -> Bool {
        guard viewController !== scannerRoot else {
            return false
        }

        if viewController is UIAlertController {
            return true
        }

        let className = NSStringFromClass(type(of: viewController)).lowercased()
        return className.contains("alert")
            || className.contains("sheet")
            || className.contains("prompt")
    }

    private static func triggerScanCompletion(on rootViewController: UIViewController) -> Bool {
        guard let completionButton = findCompletionButton(in: rootViewController),
              let action = completionButton.action
        else {
            return false
        }

        UIApplication.shared.sendAction(action, to: completionButton.target, from: completionButton, for: nil)
        return true
    }

    private static func findCompletionButton(in rootViewController: UIViewController) -> UIBarButtonItem? {
        var controllersToVisit: [UIViewController] = [rootViewController]
        var visitedControllers = Set<ObjectIdentifier>()
        var fallbackButton: UIBarButtonItem?

        while !controllersToVisit.isEmpty {
            let currentController = controllersToVisit.removeFirst()
            let identifier = ObjectIdentifier(currentController)

            guard visitedControllers.insert(identifier).inserted else {
                continue
            }

            let rightBarButtonItems = currentController.navigationItem.rightBarButtonItems ?? []
            for barButtonItem in rightBarButtonItems where barButtonItem.isEnabled && barButtonItem.action != nil {
                if isCompletionButton(barButtonItem) {
                    return barButtonItem
                }
                fallbackButton = fallbackButton ?? barButtonItem
            }

            if let rightBarButtonItem = currentController.navigationItem.rightBarButtonItem,
               rightBarButtonItem.isEnabled,
               rightBarButtonItem.action != nil {
                if isCompletionButton(rightBarButtonItem) {
                    return rightBarButtonItem
                }
                fallbackButton = fallbackButton ?? rightBarButtonItem
            }

            if let navigationController = currentController as? UINavigationController {
                controllersToVisit.append(contentsOf: navigationController.viewControllers)
            }

            controllersToVisit.append(contentsOf: currentController.children)

            if let parentController = currentController.parent {
                controllersToVisit.append(parentController)
            }

            if let presentedViewController = currentController.presentedViewController {
                controllersToVisit.append(presentedViewController)
            }
        }

        return fallbackButton
    }

    private static func isCompletionButton(_ barButtonItem: UIBarButtonItem) -> Bool {
        if barButtonItem.style == .done {
            return true
        }

        let normalizedTitle = barButtonItem.title?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        return normalizedTitle == "done" || normalizedTitle == "save"
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
