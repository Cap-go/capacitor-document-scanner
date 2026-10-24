import XCTest
@testable import DocumentScannerPlugin

final class DocumentScannerTests: XCTestCase {
    func testResponseTypeValues() {
        XCTAssertEqual(ResponseType.base64, "base64")
        XCTAssertEqual(ResponseType.imageFilePath, "imageFilePath")
    }

    func testVisionKitHackMatchesCompileFlag() {
        #if CAPGO_DOCUMENT_SCANNER_VISIONKIT_HACK
        XCTAssertTrue(VisionKitScanHack.isCompiledIn)
        XCTAssertEqual(
            VisionKitPrivateConstants.inProcessViewControllerClassName,
            "VNDocumentCameraViewController_InProcess"
        )
        XCTAssertEqual(
            VisionKitPrivateConstants.documentCameraCanAddImagesSelector,
            Selector("documentCameraController:canAddImages:")
        )
        #else
        XCTAssertFalse(VisionKitScanHack.isCompiledIn)
        #endif
    }
}
