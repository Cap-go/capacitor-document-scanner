import Capacitor
import Foundation

@objc(DocumentScannerPlugin)
public class DocumentScannerPlugin: CAPPlugin, CAPBridgedPlugin {
    private let pluginVersion: String = "8.3.3"
    public let identifier = "DocumentScannerPlugin"
    public let jsName = "DocumentScanner"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "scanDocument", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "getPluginVersion", returnType: CAPPluginReturnPromise)
    ]

    private var documentScanner: DocScanner?

    @objc func scanDocument(_ call: CAPPluginCall) {
        guard let bridgeViewController = bridge?.viewController else {
            call.reject("Bridge view controller unavailable.")
            return
        }

        documentScanner = DocScanner(
            bridgeViewController,
            successHandler: { [weak self] scannedImages in
                call.resolve([
                    "status": "success",
                    "scannedImages": scannedImages
                ])
                self?.documentScanner = nil
            },
            errorHandler: { [weak self] errorMessage in
                call.reject(errorMessage)
                self?.documentScanner = nil
            },
            cancelHandler: { [weak self] in
                call.resolve([
                    "status": "cancel"
                ])
                self?.documentScanner = nil
            },
            responseType: call.getString("responseType") ?? ResponseType.imageFilePath,
            croppedImageQuality: clampQuality(call.getInt("croppedImageQuality")),
            brightness: clampBrightness(call.getFloat("brightness")),
            contrast: clampContrast(call.getFloat("contrast")),
            maxNumDocuments: validateMaxNumDocuments(call.getInt("maxNumDocuments"))
        )

        documentScanner?.startScan()
    }

    private func clampQuality(_ value: Int?) -> Int {
        let quality = value ?? 100
        return max(0, min(100, quality))
    }

    private func clampBrightness(_ value: Float?) -> Float {
        let brightness = value ?? 0.0
        return max(-255.0, min(255.0, brightness))
    }

    private func clampContrast(_ value: Float?) -> Float {
        let contrast = value ?? 1.0
        return max(0.0, min(10.0, contrast))
    }

    private func validateMaxNumDocuments(_ value: Int?) -> Int? {
        guard let limit = value else {
            return nil
        }
        // Only return limit if it's positive, otherwise return nil (unlimited)
        return limit > 0 ? limit : nil
    }

    @objc func getPluginVersion(_ call: CAPPluginCall) {
        call.resolve(["version": self.pluginVersion])
    }

}
