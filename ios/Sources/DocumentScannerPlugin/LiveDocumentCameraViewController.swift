import AVFoundation
import UIKit
import Vision

protocol LiveDocumentCameraViewControllerDelegate: AnyObject {
    func liveDocumentCameraDidCancel(_ controller: LiveDocumentCameraViewController)
    func liveDocumentCamera(
        _ controller: LiveDocumentCameraViewController,
        didCapture image: UIImage,
        detectedQuad: DocumentQuad
    )
    func liveDocumentCamera(_ controller: LiveDocumentCameraViewController, didFail message: String)
}

final class LiveDocumentCameraViewController: UIViewController {
    weak var delegate: LiveDocumentCameraViewControllerDelegate?

    private let captureSession = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let sessionQueue = DispatchQueue(label: "app.capgo.document-scanner.camera")
    private let previewLayer = AVCaptureVideoPreviewLayer()
    private let quadOverlay = CAShapeLayer()
    private var latestDetectedQuad: DocumentQuad?
    private var isCapturing = false

    private let captureButton = UIButton(type: .system)

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        title = "Scan Document"

        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .cancel,
            target: self,
            action: #selector(cancelTapped)
        )

        previewLayer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(previewLayer)

        quadOverlay.strokeColor = UIColor.systemGreen.cgColor
        quadOverlay.fillColor = UIColor.clear.cgColor
        quadOverlay.lineWidth = 3
        view.layer.addSublayer(quadOverlay)

        captureButton.translatesAutoresizingMaskIntoConstraints = false
        captureButton.backgroundColor = .white
        captureButton.layer.cornerRadius = 36
        captureButton.layer.borderWidth = 4
        captureButton.layer.borderColor = UIColor.systemBlue.cgColor
        captureButton.accessibilityIdentifier = "managed-scanner-capture-button"
        captureButton.addTarget(self, action: #selector(captureTapped), for: .touchUpInside)
        view.addSubview(captureButton)

        NSLayoutConstraint.activate([
            captureButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            captureButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -24),
            captureButton.widthAnchor.constraint(equalToConstant: 72),
            captureButton.heightAnchor.constraint(equalToConstant: 72)
        ])
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer.frame = view.bounds
        quadOverlay.frame = view.bounds
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        requestCameraAccessAndStart()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        sessionQueue.async {
            if self.captureSession.isRunning {
                self.captureSession.stopRunning()
            }
        }
    }

    @objc private func cancelTapped() {
        delegate?.liveDocumentCameraDidCancel(self)
    }

    @objc private func captureTapped() {
        guard !isCapturing else {
            return
        }
        isCapturing = true
        let settings = AVCapturePhotoSettings()
        photoOutput.capturePhoto(with: settings, delegate: self)
    }

    private func requestCameraAccessAndStart() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    guard let self else {
                        return
                    }
                    if granted {
                        self.configureSession()
                    } else {
                        self.delegate?.liveDocumentCamera(self, didFail: "Camera permission denied.")
                    }
                }
            }
        default:
            delegate?.liveDocumentCamera(self, didFail: "Camera permission denied.")
        }
    }

    private func configureSession() {
        sessionQueue.async {
            self.captureSession.beginConfiguration()
            self.captureSession.sessionPreset = .photo

            guard
                let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                let input = try? AVCaptureDeviceInput(device: camera),
                self.captureSession.canAddInput(input)
            else {
                DispatchQueue.main.async {
                    self.delegate?.liveDocumentCamera(self, didFail: "Unable to access the camera.")
                }
                self.captureSession.commitConfiguration()
                return
            }

            self.captureSession.addInput(input)

            if self.captureSession.canAddOutput(self.photoOutput) {
                self.captureSession.addOutput(self.photoOutput)
            }

            self.videoOutput.setSampleBufferDelegate(self, queue: self.sessionQueue)
            self.videoOutput.alwaysDiscardsLateVideoFrames = true
            if self.captureSession.canAddOutput(self.videoOutput) {
                self.captureSession.addOutput(self.videoOutput)
            }

            self.captureSession.commitConfiguration()
            self.previewLayer.session = self.captureSession
            self.captureSession.startRunning()
        }
    }

    private func updateOverlay(with quad: DocumentQuad?) {
        guard let quad else {
            quadOverlay.path = nil
            return
        }

        let size = view.bounds.size
        let path = UIBezierPath()
        let points = [
            CGPoint(x: quad.topLeft.x * size.width, y: quad.topLeft.y * size.height),
            CGPoint(x: quad.topRight.x * size.width, y: quad.topRight.y * size.height),
            CGPoint(x: quad.bottomRight.x * size.width, y: quad.bottomRight.y * size.height),
            CGPoint(x: quad.bottomLeft.x * size.width, y: quad.bottomLeft.y * size.height)
        ]
        path.move(to: points[0])
        for index in 1 ..< points.count {
            path.addLine(to: points[index])
        }
        path.close()
        quadOverlay.path = path.cgPath
    }
}

extension LiveDocumentCameraViewController: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        isCapturing = false
        if let error {
            DispatchQueue.main.async {
                self.delegate?.liveDocumentCamera(self, didFail: error.localizedDescription)
            }
            return
        }

        guard let data = photo.fileDataRepresentation(), let image = UIImage(data: data) else {
            DispatchQueue.main.async {
                self.delegate?.liveDocumentCamera(self, didFail: "Unable to capture photo.")
            }
            return
        }

        let detected = DocumentQuadDetector.detect(in: image)
            ?? latestDetectedQuad
            ?? DocumentQuad.defaultInset(for: image.size)

        DispatchQueue.main.async {
            self.delegate?.liveDocumentCamera(self, didCapture: image, detectedQuad: detected)
        }
    }
}

extension LiveDocumentCameraViewController: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }

        let request = VNDetectRectanglesRequest { [weak self] request, _ in
            guard
                let self,
                let observation = request.results?.first as? VNRectangleObservation
            else {
                return
            }

            let quad = DocumentQuad.fromVisionNormalizedPoints(
                topLeft: observation.topLeft,
                topRight: observation.topRight,
                bottomRight: observation.bottomRight,
                bottomLeft: observation.bottomLeft
            )
            self.latestDetectedQuad = quad
            DispatchQueue.main.async {
                self.updateOverlay(with: quad)
            }
        }
        request.maximumObservations = 1
        request.minimumConfidence = 0.5

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .right, options: [:])
        try? handler.perform([request])
    }
}
