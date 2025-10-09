import XCTest
@testable import DocumentScannerPlugin

final class DocumentScannerTests: XCTestCase {
    func testResponseTypeValues() {
        XCTAssertEqual(ResponseType.base64, "base64")
        XCTAssertEqual(ResponseType.imageFilePath, "imageFilePath")
    }
}
