import XCTest
@testable import DocumentScannerPlugin

final class DocumentScannerTests: XCTestCase {
    func testResponseTypeValues() {
        XCTAssertEqual(ResponseType.base64, "base64")
        XCTAssertEqual(ResponseType.imageFilePath, "imageFilePath")
    }

    func testVisionKitPrivateConstantsAreStatic() {
        XCTAssertEqual(
            VisionKitPrivateConstants.inProcessViewControllerClassName,
            "VNDocumentCameraViewController_InProcess"
        )
        XCTAssertEqual(
            VisionKitPrivateConstants.documentCameraCanAddImagesSelector,
            Selector("documentCameraController:canAddImages:")
        )
    }
}
