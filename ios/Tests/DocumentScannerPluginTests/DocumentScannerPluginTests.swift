import XCTest
@testable import DocumentScannerPlugin

final class DocumentScannerTests: XCTestCase {
    func testResponseTypeValues() {
        XCTAssertEqual(ResponseType.base64, "base64")
        XCTAssertEqual(ResponseType.imageFilePath, "imageFilePath")
    }

    func testVisionKitSwizzleMatchesCompileFlag() {
        #if CAPGO_DOCUMENT_SCANNER_VISIONKIT_SWIZZLE
        XCTAssertTrue(VisionKitScanSwizzle.isCompiledIn)
        XCTAssertEqual(
            VisionKitPrivateConstants.inProcessViewControllerClassName,
            "VNDocumentCameraViewController_InProcess"
        )
        XCTAssertEqual(
            VisionKitPrivateConstants.documentCameraCanAddImagesSelector,
            Selector("documentCameraController:canAddImages:")
        )
        #else
        XCTAssertFalse(VisionKitScanSwizzle.isCompiledIn)
        #endif
    }
}
