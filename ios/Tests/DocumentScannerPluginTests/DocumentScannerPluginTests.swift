import XCTest
@testable import DocumentScannerPlugin

final class DocumentScannerTests: XCTestCase {
    func testResponseTypeValues() {
        XCTAssertEqual(ResponseType.base64, "base64")
        XCTAssertEqual(ResponseType.imageFilePath, "imageFilePath")
    }

    func testClampedPageCountWithoutLimit() {
        XCTAssertEqual(DocScanner.clampedPageCount(total: 5, limit: nil), 5)
    }

    func testClampedPageCountWithLimit() {
        XCTAssertEqual(DocScanner.clampedPageCount(total: 10, limit: 3), 3)
        XCTAssertEqual(DocScanner.clampedPageCount(total: 2, limit: 5), 2)
        XCTAssertEqual(DocScanner.clampedPageCount(total: 0, limit: 1), 0)
    }
}
