import Capacitor
import Foundation

@available(iOS 13.0, *)
@objc(DocumentScannerPlugin)
public class DocumentScannerPlugin: CAPPlugin, CAPBridgedPlugin {
    private let pluginVersion: String = "7.2.2"
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
            croppedImageQuality: clampQuality(call.getInt("croppedImageQuality"))
        )

        documentScanner?.startScan()
    }

    private func clampQuality(_ value: Int?) -> Int {
        let quality = value ?? 100
        return max(0, min(100, quality))
    }

    @objc func getPluginVersion(_ call: CAPPluginCall) {
        call.resolve(["version": self.pluginVersion])
    }

}
