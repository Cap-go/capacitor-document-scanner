// swiftlint:disable file_length type_body_length identifier_name
import Foundation
import UIKit
import VisionKit

#if CAPGO_DOCUMENT_SCANNER_VISIONKIT_SWIZZLE
import ObjectiveC.runtime

enum VisionKitPrivateConstants {
    static let inProcessViewControllerClassName = "VNDocumentCameraViewController_InProcess"
    static let documentCameraCanAddImagesSelector = Selector("documentCameraController:canAddImages:")
    static let gestureRecognizerTargetsKey = "_targets"
    static let gestureTargetIvarName = "_target"
    static let gestureActionIvarName = "_action"
    static let thumbnailContainerViewClassFragment = "ICDocCamThumbnailContainerView"
}

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

final class VisionKitScanSwizzle: NSObject {
    static let isCompiledIn = true
    private static var swizzled = false

    static func prepare(limit: Int?, presentPreviewAfterCapture: Bool) {
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

    static func reset() {
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

        // appstore-2.5.2-allow: resolve VisionKit in-process document camera class for page-limit swizzle
        guard let inProcessClass = NSClassFromString(VisionKitPrivateConstants.inProcessViewControllerClassName) else {
            return
        }

        let originalSelector = VisionKitPrivateConstants.documentCameraCanAddImagesSelector
        let swizzledSelector = #selector(VisionKitScanSwizzle.swizzled_documentCameraController(_:canAddImages:))

        guard
            // appstore-2.5.2-allow: read private canAddImages implementation before swizzle
            let originalMethod = class_getInstanceMethod(inProcessClass, originalSelector),
            let swizzledMethod = class_getInstanceMethod(VisionKitScanSwizzle.self, swizzledSelector)
        else {
            return
        }

        swizzled = true
        // appstore-2.5.2-allow: install swizzled canAddImages handler on in-process VisionKit class
        let didAddMethod = class_addMethod(
            inProcessClass,
            swizzledSelector,
            method_getImplementation(swizzledMethod),
            method_getTypeEncoding(swizzledMethod)
        )

        if didAddMethod,
           let installedSwizzledMethod = class_getInstanceMethod(inProcessClass, swizzledSelector) {
            // appstore-2.5.2-allow: exchange canAddImages implementations for scan limit enforcement
            method_exchangeImplementations(originalMethod, installedSwizzledMethod)
            return
        }

        // appstore-2.5.2-allow: exchange canAddImages implementations for scan limit enforcement
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
            VisionKitScanSwizzle.requestPreviewPresentationIfNeeded(
                forceNewCycle: true,
                customizeForCompletion: reachedConfiguredLimit
            )
        }

        if reachedConfiguredLimit {
            if !previewWasRequested {
                VisionKitScanSwizzle.requestPreviewPresentationIfNeeded(
                    forceNewCycle: true,
                    customizeForCompletion: true
                )
            }
            VisionKitScanSwizzle.suppressLimitModalIfNeeded()
            return false
        }

        return originalAllowsMoreImages
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
            if let previewView = findFirstView(
                namedLike: [VisionKitPrivateConstants.thumbnailContainerViewClassFragment],
                in: rootView
            ) {
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
            // appstore-2.5.2-allow: read UIKit gesture recognizer target list to trigger preview navigation
            guard let internalTargets = gestureRecognizer.value(
                forKey: VisionKitPrivateConstants.gestureRecognizerTargetsKey
            ) as? [NSObject] else {
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
        guard let targetClass: AnyClass = object_getClass(internalTarget) else {
            return nil
        }

        // appstore-2.5.2-allow: read UIKit gesture target/action ivars to forward preview taps
        guard
            let targetIvar = class_getInstanceVariable(
                targetClass,
                VisionKitPrivateConstants.gestureTargetIvarName
            ),
            let actionIvar = class_getInstanceVariable(
                targetClass,
                VisionKitPrivateConstants.gestureActionIvarName
            ),
            // appstore-2.5.2-allow: read gesture target object from UIKit internal target entry
            let target = object_getIvar(internalTarget, targetIvar) as AnyObject?
        else {
            return nil
        }

        // appstore-2.5.2-allow: read gesture action selector offset from UIKit internal target entry
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

    static func attach(controller: VNDocumentCameraViewController) {
        activeDocumentCameraController.value = controller
    }

}

#else

enum VisionKitScanSwizzle {
    static let isCompiledIn = false

    static func prepare(limit: Int?, presentPreviewAfterCapture: Bool) {
        guard limit != nil || presentPreviewAfterCapture else {
            return
        }

        guard !didLogDisabledSwizzle else {
            return
        }

        didLogDisabledSwizzle = true
        NSLog(
            "[DocumentScanner] Private VisionKit page-limit swizzle is not compiled in. " +
                "maxNumDocuments only trims pages after Save. " +
                "Set plugins.DocumentScanner.iosVisionKitSwizzle to true and run cap sync to compile it."
        )
    }

    static func reset() {}

    static func attach(controller: VNDocumentCameraViewController) {}

    private static var didLogDisabledSwizzle = false
}

#endif
