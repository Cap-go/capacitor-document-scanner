import Foundation

enum DocumentScanSessionPolicy {
    static let visionKitSystemMaximum = 24

    /// Uses stock VisionKit when no per-page crop, review, or custom page cap is required.
    static func usesVisionKitOnly(
        letUserAdjustCrop: Bool,
        reviewCapturedDocument: Bool,
        maxNumDocuments: Int?
    ) -> Bool {
        !letUserAdjustCrop && !reviewCapturedDocument && maxNumDocuments == nil
    }

    static func effectivePageLimit(maxNumDocuments: Int?) -> Int {
        guard let maxNumDocuments else {
            return visionKitSystemMaximum
        }
        return min(visionKitSystemMaximum, max(1, maxNumDocuments))
    }

    static func hasReachedPageLimit(acceptedCount: Int, maxNumDocuments: Int?) -> Bool {
        acceptedCount >= effectivePageLimit(maxNumDocuments: maxNumDocuments)
    }

    /// After accepting one more page, will the session be at the configured cap?
    static func willReachPageLimitAfterNextPage(acceptedCount: Int, maxNumDocuments: Int?) -> Bool {
        hasReachedPageLimit(acceptedCount: acceptedCount + 1, maxNumDocuments: maxNumDocuments)
    }

    static func shouldShowCropEditor(letUserAdjustCrop: Bool) -> Bool {
        letUserAdjustCrop
    }

    static func shouldShowReviewScreen(
        reviewCapturedDocument: Bool,
        acceptedCountAfterAppend: Int,
        maxNumDocuments: Int?
    ) -> Bool {
        reviewCapturedDocument || hasReachedPageLimit(acceptedCount: acceptedCountAfterAppend, maxNumDocuments: maxNumDocuments)
    }

    static func allowsContinueScanning(acceptedCount: Int, maxNumDocuments: Int?) -> Bool {
        !hasReachedPageLimit(acceptedCount: acceptedCount, maxNumDocuments: maxNumDocuments)
    }
}
