import UIKit
import XCTest
@testable import DocumentScannerPlugin

final class DocumentPerspectiveCorrectorTests: XCTestCase {
    func testPerspectiveCorrectionProducesImage() {
        let size = CGSize(width: 200, height: 300)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            UIColor.black.setFill()
            context.fill(CGRect(x: 40, y: 60, width: 120, height: 180))
        }

        let quad = DocumentQuad(
            topLeft: CGPoint(x: 0.2, y: 0.2),
            topRight: CGPoint(x: 0.8, y: 0.2),
            bottomRight: CGPoint(x: 0.8, y: 0.8),
            bottomLeft: CGPoint(x: 0.2, y: 0.8)
        )

        let corrected = DocumentPerspectiveCorrector.correctedImage(from: image, quad: quad)
        XCTAssertNotNil(corrected)
        XCTAssertGreaterThan(corrected?.size.width ?? 0, 0)
        XCTAssertGreaterThan(corrected?.size.height ?? 0, 0)
    }
}
