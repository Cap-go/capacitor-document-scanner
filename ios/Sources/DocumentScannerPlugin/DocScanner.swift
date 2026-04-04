// swiftlint:disable file_length type_body_length identifier_name type_name function_body_length
import CoreImage
import ObjectiveC.runtime
import UIKit
import VisionKit

private final class WeakDocumentCameraController {
    weak var value: VNDocumentCameraViewController?
}

private let activeDocumentCameraController = WeakDocumentCameraController()
private var documentScanLimit: Int?
private var documentScanShouldPresentPreviewAfterCapture = false
private var documentScanLastPreviewedAcceptedCount = 0
private var documentScanPreviewPresentationRequested = false
private var documentScanPreviewPresentationGeneration = 0
private var documentScanShouldCustomizePreviewNavigation = false
private var documentScanPreviewNavigationCustomized = false
private var documentScanModalSuppressionGeneration = 0

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

        DocScanner.configureVisionKitHackState(
            limit: maxNumDocuments,
            presentPreviewAfterCapture: reviewCapturedDocument || letUserAdjustCrop
        )

        DispatchQueue.main.async {
            let documentCameraViewController = VNDocumentCameraViewController()
            documentCameraViewController.delegate = self
            activeDocumentCameraController.value = documentCameraViewController
            viewController.present(documentCameraViewController, animated: true)
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

    private static func configureVisionKitHackState(limit: Int?, presentPreviewAfterCapture: Bool) {
        documentScanLimit = limit
        documentScanShouldPresentPreviewAfterCapture = presentPreviewAfterCapture
        documentScanLastPreviewedAcceptedCount = 0
        documentScanPreviewPresentationRequested = false
        documentScanPreviewPresentationGeneration += 1
        documentScanShouldCustomizePreviewNavigation = false
        documentScanPreviewNavigationCustomized = false
        documentScanModalSuppressionGeneration += 1

        guard limit != nil || presentPreviewAfterCapture else {
            return
        }

        setupSwizzling()
    }

    private static func resetVisionKitHackState() {
        documentScanLimit = nil
        documentScanShouldPresentPreviewAfterCapture = false
        documentScanLastPreviewedAcceptedCount = 0
        documentScanPreviewPresentationRequested = false
        documentScanPreviewPresentationGeneration += 1
        documentScanShouldCustomizePreviewNavigation = false
        documentScanPreviewNavigationCustomized = false
        documentScanModalSuppressionGeneration += 1
        activeDocumentCameraController.value = nil
    }

    private static func setupSwizzling() {
        guard !swizzled else {
            return
        }

        guard let inProcessClass = NSClassFromString("VNDocumentCameraViewController_InProcess") else {
            return
        }

        let originalSelector = NSSelectorFromString("documentCameraController:canAddImages:")
        let swizzledSelector = #selector(DocScanner.swizzled_documentCameraController(_:canAddImages:))

        guard
            let originalMethod = class_getInstanceMethod(inProcessClass, originalSelector),
            let swizzledMethod = class_getInstanceMethod(DocScanner.self, swizzledSelector)
        else {
            return
        }

        swizzled = true
        let didAddMethod = class_addMethod(
            inProcessClass,
            swizzledSelector,
            method_getImplementation(swizzledMethod),
            method_getTypeEncoding(swizzledMethod)
        )

        if didAddMethod,
           let installedSwizzledMethod = class_getInstanceMethod(inProcessClass, swizzledSelector) {
            method_exchangeImplementations(originalMethod, installedSwizzledMethod)
            return
        }

        method_exchangeImplementations(originalMethod, swizzledMethod)
    }

    @objc dynamic func swizzled_documentCameraController(_ controller: AnyObject, canAddImages count: UInt64) -> Bool {
        let originalAllowsMoreImages = swizzled_documentCameraController(controller, canAddImages: count)
        let acceptedCount = max(0, Int(count) - 1)
        let reachedConfiguredLimit = documentScanLimit.map { Int(count) > $0 } ?? false
        var previewWasRequested = false

        if documentScanShouldPresentPreviewAfterCapture,
           acceptedCount > 0,
           acceptedCount > documentScanLastPreviewedAcceptedCount {
            documentScanLastPreviewedAcceptedCount = acceptedCount
            previewWasRequested = true
            DocScanner.requestPreviewPresentationIfNeeded(
                forceNewCycle: true,
                customizeForCompletion: reachedConfiguredLimit
            )
        }

        if reachedConfiguredLimit {
            if !previewWasRequested {
                DocScanner.requestPreviewPresentationIfNeeded(
                    forceNewCycle: true,
                    customizeForCompletion: true
                )
            }
            DocScanner.suppressLimitModalIfNeeded()
            return false
        }

        return originalAllowsMoreImages
    }

    private var shouldUseSimulatorHarness: Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        return false
        #endif
    }

    private static func resolvedView(for controller: UIViewController) -> UIView? {
        controller.viewIfLoaded ?? controller.view
    }

    private static func requestPreviewPresentationIfNeeded(forceNewCycle: Bool, customizeForCompletion: Bool) {
        DispatchQueue.main.async {
            guard let documentCameraViewController = activeDocumentCameraController.value else {
                return
            }

            if forceNewCycle {
                documentScanPreviewPresentationRequested = false
                documentScanPreviewNavigationCustomized = false
            }

            documentScanShouldCustomizePreviewNavigation =
                documentScanShouldCustomizePreviewNavigation || customizeForCompletion

            guard !documentScanPreviewPresentationRequested else {
                if documentScanShouldCustomizePreviewNavigation {
                    _ = customizePreviewNavigationIfNeeded(around: documentCameraViewController)
                }
                return
            }

            documentScanPreviewPresentationRequested = true
            let generation = documentScanPreviewPresentationGeneration + 1
            documentScanPreviewPresentationGeneration = generation
            attemptPreviewPresentation(generation: generation, remainingAttempts: 12)
        }
    }

    private static func attemptPreviewPresentation(generation: Int, remainingAttempts: Int) {
        DispatchQueue.main.async {
            guard
                generation == documentScanPreviewPresentationGeneration,
                let documentCameraViewController = activeDocumentCameraController.value
            else {
                return
            }

            if findVisiblePreviewOrEditorController(around: documentCameraViewController) != nil {
                if documentScanShouldCustomizePreviewNavigation {
                    _ = customizePreviewNavigationIfNeeded(around: documentCameraViewController)
                }
                return
            }

            guard let rootView = resolvedView(for: documentCameraViewController) else {
                return
            }

            let previewWasTriggered: Bool
            if let previewView = findFirstView(namedLike: ["ICDocCamThumbnailContainerView"], in: rootView) {
                previewWasTriggered = triggerInteraction(around: previewView, in: rootView)
            } else {
                let previewPoint = CGPoint(
                    x: previewHotspotFrame(in: rootView).midX,
                    y: previewHotspotFrame(in: rootView).midY
                )
                previewWasTriggered = triggerInteraction(at: previewPoint, in: rootView)
            }

            if !previewWasTriggered && remainingAttempts <= 0 {
                documentScanPreviewPresentationRequested = false
                return
            }

            guard remainingAttempts > 0 else {
                return
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                attemptPreviewPresentation(generation: generation, remainingAttempts: remainingAttempts - 1)
            }
        }
    }

    @discardableResult
    private static func customizePreviewNavigationIfNeeded(around scannerController: UIViewController) -> Bool {
        guard documentScanShouldCustomizePreviewNavigation else {
            return false
        }

        guard let previewController = findVisiblePreviewOrEditorController(around: scannerController) else {
            return false
        }

        guard !documentScanPreviewNavigationCustomized else {
            return true
        }

        let completionButton = findCompletionButton(in: scannerController)
        let completionTitle = completionButton?.title ?? "Done"
        let completionStyle = completionButton?.style == .plain ? UIBarButtonItem.Style.plain : .done

        previewController.navigationItem.hidesBackButton = true
        previewController.navigationItem.setHidesBackButton(true, animated: false)
        previewController.navigationItem.leftItemsSupplementBackButton = false

        if let completionAction = completionButton?.action {
            previewController.navigationItem.leftBarButtonItem = UIBarButtonItem(
                title: completionTitle,
                style: completionStyle,
                target: completionButton?.target,
                action: completionAction
            )
        }

        documentScanPreviewNavigationCustomized = true
        return true
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
                guard let invocation = gestureRecognizerInvocation(from: internalTarget) else {
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
        guard
            let targetClass: AnyClass = object_getClass(internalTarget),
            let targetIvar = class_getInstanceVariable(targetClass, "_target"),
            let actionIvar = class_getInstanceVariable(targetClass, "_action"),
            let target = object_getIvar(internalTarget, targetIvar) as AnyObject?
        else {
            return nil
        }

        let actionOffset = ivar_getOffset(actionIvar)
        let actionPointer = Unmanaged.passUnretained(internalTarget).toOpaque().advanced(by: actionOffset)
        let selector = actionPointer.load(as: Selector.self)

        guard let responder = target as? NSObject,
              responder.responds(to: selector) else {
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
            if let matchingSubview = findFirstView(namedLike: classNameFragments, in: subview, rootView: rootView) {
                return matchingSubview
            }
        }

        return nil
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

        let normalizedTitle = normalizeActionText(barButtonItem.title)
        return normalizedTitle == "done" || normalizedTitle == "save" || normalizedTitle == "done scanning"
    }

    private static func normalizeActionText(_ text: String?) -> String {
        text?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased() ?? ""
    }

    private static func previewHotspotFrame(in rootView: UIView) -> CGRect {
        CGRect(
            x: 0,
            y: rootView.bounds.height * 0.56,
            width: rootView.bounds.width * 0.42,
            height: rootView.bounds.height * 0.44
        )
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

    private static func shouldSuppressModal(_ viewController: UIViewController, scannerRoot: UIViewController) -> Bool {
        guard viewController !== scannerRoot else {
            return false
        }

        if viewController is UIAlertController {
            return true
        }

        let className = NSStringFromClass(type(of: viewController)).lowercased()
        return className.contains("alert") || className.contains("sheet") || className.contains("prompt")
    }

    private func finishScan(with images: [UIImage]) {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let limitedImages = self.limit(images: images)
                let results = try limitedImages.enumerated().map { index, image in
                    let adjustedImage = self.applyBrightnessContrastIfNeeded(to: image)
                    guard
                        let imageData = adjustedImage.jpegData(
                            compressionQuality: CGFloat(self.croppedImageQuality) / 100.0
                        )
                    else {
                        throw RuntimeError.message("Unable to get scanned document in jpeg format.")
                    }

                    switch self.responseType {
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

    private func limit(images: [UIImage]) -> [UIImage] {
        guard let maxNumDocuments else {
            return images
        }
        return Array(images.prefix(maxNumDocuments))
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
        let images = (0 ..< scan.pageCount).map(scan.imageOfPage(at:))
        DocScanner.resetVisionKitHackState()
        dismiss(controller) {
            self.finishScan(with: images)
        }
    }

    func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
        DocScanner.resetVisionKitHackState()
        dismiss(controller) {
            self.cancelHandler()
        }
    }

    func documentCameraViewController(
        _ controller: VNDocumentCameraViewController,
        didFailWithError error: Error
    ) {
        DocScanner.resetVisionKitHackState()
        dismiss(controller) {
            self.errorHandler(error.localizedDescription)
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
