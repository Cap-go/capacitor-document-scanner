import Foundation

/**
 Utilities for creating and managing scanned image files.
 */
class FileUtil {
    func createImageFile(_ pageNumber: Int) -> URL {
        let documentsDirectory = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        )[0]

        return documentsDirectory.appendingPathComponent(
            "DOCUMENT_SCAN_\(pageNumber)_\(currentTimestamp()).jpg"
        )
    }

    func getBase64Image(imageFilePath: String) throws -> String {
        let imageUrl = try imageURL(imageFilePath)
        guard let imageData = try? Data(contentsOf: imageUrl) else {
            throw RuntimeError.message("Unable to get image from file")
        }
        return imageData.base64EncodedString()
    }

    func deleteImage(imageFilePath: String) throws {
        try FileManager.default.removeItem(at: imageURL(imageFilePath))
    }

    private func imageURL(_ imageFilePath: String) throws -> URL {
        guard let imageUrl = URL(string: imageFilePath) else {
            throw RuntimeError.message("Unable to get image from file")
        }
        return imageUrl
    }

    private func currentTimestamp() -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd_HHmmss"
        return dateFormatter.string(from: Date())
    }
}
