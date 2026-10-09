import UIKit

protocol DocumentCropEditorViewControllerDelegate: AnyObject {
    func documentCropEditorDidCancel(_ controller: DocumentCropEditorViewController)
    func documentCropEditorDidRetake(_ controller: DocumentCropEditorViewController)
    func documentCropEditor(
        _ controller: DocumentCropEditorViewController,
        didFinishWith image: UIImage,
        action: DocumentPostCaptureAction
    )
}

enum DocumentPostCaptureAction {
    case continueScanning
    case finishScanning
}

final class DocumentCropEditorViewController: UIViewController {
    weak var delegate: DocumentCropEditorViewControllerDelegate?

    private let sourceImage: UIImage
    private var quad: DocumentQuad
    private let allowsContinueScanning: Bool

    private let imageView = UIImageView()
    private let overlayView = DocumentCropOverlayView()
    private let retakeButton = UIButton(type: .system)
    private let continueButton = UIButton(type: .system)
    private let doneButton = UIButton(type: .system)

    init(sourceImage: UIImage, initialQuad: DocumentQuad, allowsContinueScanning: Bool) {
        self.sourceImage = sourceImage
        self.quad = initialQuad
        self.allowsContinueScanning = allowsContinueScanning
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        title = "Adjust Crop"

        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .cancel,
            target: self,
            action: #selector(cancelTapped)
        )

        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFit
        imageView.image = sourceImage

        overlayView.translatesAutoresizingMaskIntoConstraints = false
        overlayView.quad = quad
        overlayView.onQuadChanged = { [weak self] updatedQuad in
            self?.quad = updatedQuad
        }

        configureActionButton(retakeButton, title: "Retake", background: .secondarySystemBackground, titleColor: .label)
        retakeButton.addTarget(self, action: #selector(retakeTapped), for: .touchUpInside)

        configureActionButton(continueButton, title: "Continue Scan", background: .systemBlue, titleColor: .white)
        continueButton.addTarget(self, action: #selector(continueTapped), for: .touchUpInside)
        continueButton.isHidden = !allowsContinueScanning

        configureActionButton(doneButton, title: "Done Scanning", background: .systemGreen, titleColor: .white)
        doneButton.addTarget(self, action: #selector(doneTapped), for: .touchUpInside)

        let buttonStack = UIStackView(arrangedSubviews: [retakeButton, continueButton, doneButton])
        buttonStack.translatesAutoresizingMaskIntoConstraints = false
        buttonStack.axis = .vertical
        buttonStack.spacing = 10

        view.addSubview(imageView)
        view.addSubview(overlayView)
        view.addSubview(buttonStack)

        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            imageView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            imageView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            imageView.bottomAnchor.constraint(equalTo: buttonStack.topAnchor, constant: -16),

            overlayView.topAnchor.constraint(equalTo: imageView.topAnchor),
            overlayView.leadingAnchor.constraint(equalTo: imageView.leadingAnchor),
            overlayView.trailingAnchor.constraint(equalTo: imageView.trailingAnchor),
            overlayView.bottomAnchor.constraint(equalTo: imageView.bottomAnchor),

            buttonStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            buttonStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            buttonStack.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12)
        ])
    }

    private func configureActionButton(_ button: UIButton, title: String, background: UIColor, titleColor: UIColor) {
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setTitle(title, for: .normal)
        button.setTitleColor(titleColor, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
        button.backgroundColor = background
        button.layer.cornerRadius = 12
        button.heightAnchor.constraint(equalToConstant: 48).isActive = true
    }

    @objc private func cancelTapped() {
        delegate?.documentCropEditorDidCancel(self)
    }

    @objc private func retakeTapped() {
        delegate?.documentCropEditorDidRetake(self)
    }

    @objc private func continueTapped() {
        finish(action: .continueScanning)
    }

    @objc private func doneTapped() {
        finish(action: .finishScanning)
    }

    private func finish(action: DocumentPostCaptureAction) {
        let corrected = DocumentPerspectiveCorrector.correctedImage(from: sourceImage, quad: quad) ?? sourceImage
        delegate?.documentCropEditor(self, didFinishWith: corrected, action: action)
    }
}
