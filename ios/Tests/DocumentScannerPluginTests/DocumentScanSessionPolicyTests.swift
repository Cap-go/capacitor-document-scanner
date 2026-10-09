import XCTest
@testable import DocumentScannerPlugin

final class DocumentScanSessionPolicyTests: XCTestCase {
    func testUsesVisionKitOnlyWhenNoManagedOptions() {
        XCTAssertTrue(
            DocumentScanSessionPolicy.usesVisionKitOnly(
                letUserAdjustCrop: false,
                reviewCapturedDocument: false,
                maxNumDocuments: nil
            )
        )
    }

    func testUsesManagedFlowWhenCropEnabled() {
        XCTAssertFalse(
            DocumentScanSessionPolicy.usesVisionKitOnly(
                letUserAdjustCrop: true,
                reviewCapturedDocument: false,
                maxNumDocuments: nil
            )
        )
    }

    func testUsesManagedFlowWhenReviewEnabled() {
        XCTAssertFalse(
            DocumentScanSessionPolicy.usesVisionKitOnly(
                letUserAdjustCrop: false,
                reviewCapturedDocument: true,
                maxNumDocuments: nil
            )
        )
    }

    func testUsesManagedFlowWhenPageLimitSet() {
        XCTAssertFalse(
            DocumentScanSessionPolicy.usesVisionKitOnly(
                letUserAdjustCrop: false,
                reviewCapturedDocument: false,
                maxNumDocuments: 2
            )
        )
    }

    func testEffectivePageLimitClampsToSystemMaximum() {
        XCTAssertEqual(DocumentScanSessionPolicy.effectivePageLimit(maxNumDocuments: 100), 24)
        XCTAssertEqual(DocumentScanSessionPolicy.effectivePageLimit(maxNumDocuments: 3), 3)
        XCTAssertEqual(DocumentScanSessionPolicy.effectivePageLimit(maxNumDocuments: nil), 24)
    }

    func testReviewShownAtConfiguredLimit() {
        XCTAssertTrue(
            DocumentScanSessionPolicy.shouldShowReviewScreen(
                reviewCapturedDocument: false,
                acceptedCountAfterAppend: 2,
                maxNumDocuments: 2
            )
        )
    }

    func testContinueScanningBlockedAtLimit() {
        XCTAssertFalse(
            DocumentScanSessionPolicy.allowsContinueScanning(acceptedCount: 2, maxNumDocuments: 2)
        )
        XCTAssertTrue(
            DocumentScanSessionPolicy.allowsContinueScanning(acceptedCount: 1, maxNumDocuments: 2)
        )
    }
}
