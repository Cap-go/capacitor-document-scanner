import UIKit

protocol DocumentPageReviewViewControllerDelegate: AnyObject {
    func documentPageReviewDidCancel(_ controller: DocumentPageReviewViewController)
    func documentPageReviewDidRetake(_ controller: DocumentPageReviewViewController)
    func documentPageReview(
        _ controller: DocumentPageReviewViewController,
        didChoose action: DocumentPostCaptureAction
    )
}

final class DocumentPageReviewViewController: UIViewController {
    weak var delegate: DocumentPageReviewViewControllerDelegate?

    private let previewImage: UIImage
    private let pageNumber: Int
    private let totalAccepted: Int
    private let allowsContinueScanning: Bool

    init(previewImage: UIImage, pageNumber: Int, totalAccepted: Int, allowsContinueScanning: Bool) {
        self.previewImage = previewImage
        self.pageNumber = pageNumber
        self.totalAccepted = totalAccepted
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
        title = "Review Page \(pageNumber)"

        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .cancel,
            target: self,
            action: #selector(cancelTapped)
        )

        let imageView = UIImageView(image: previewImage)
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFit
        imageView.layer.cornerRadius = 12
        imageView.layer.masksToBounds = true

        let summaryLabel = UILabel()
        summaryLabel.translatesAutoresizingMaskIntoConstraints = false
        summaryLabel.textAlignment = .center
        summaryLabel.numberOfLines = 0
        summaryLabel.font = .systemFont(ofSize: 16, weight: .medium)
        summaryLabel.textColor = .secondaryLabel
        summaryLabel.text = "\(totalAccepted) page\(totalAccepted == 1 ? "" : "s") in this session"

        let retakeButton = makeButton(title: "Retake", color: .secondarySystemBackground, titleColor: .label)
        retakeButton.addTarget(self, action: #selector(retakeTapped), for: .touchUpInside)

        let continueButton = makeButton(title: "Continue Scan", color: .systemBlue, titleColor: .white)
        continueButton.addTarget(self, action: #selector(continueTapped), for: .touchUpInside)
        continueButton.isHidden = !allowsContinueScanning

        let doneButton = makeButton(title: "Done Scanning", color: .systemGreen, titleColor: .white)
        doneButton.addTarget(self, action: #selector(doneTapped), for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [retakeButton, continueButton, doneButton])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 10

        view.addSubview(imageView)
        view.addSubview(summaryLabel)
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            imageView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            imageView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            imageView.heightAnchor.constraint(equalTo: view.heightAnchor, multiplier: 0.5),

            summaryLabel.topAnchor.constraint(equalTo: imageView.bottomAnchor, constant: 12),
            summaryLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            summaryLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),

            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            stack.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16)
        ])
    }

    private func makeButton(title: String, color: UIColor, titleColor: UIColor) -> UIButton {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setTitle(title, for: .normal)
        button.setTitleColor(titleColor, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
        button.backgroundColor = color
        button.layer.cornerRadius = 12
        button.heightAnchor.constraint(equalToConstant: 48).isActive = true
        return button
    }

    @objc private func cancelTapped() {
        delegate?.documentPageReviewDidCancel(self)
    }

    @objc private func retakeTapped() {
        delegate?.documentPageReviewDidRetake(self)
    }

    @objc private func continueTapped() {
        delegate?.documentPageReview(self, didChoose: .continueScanning)
    }

    @objc private func doneTapped() {
        delegate?.documentPageReview(self, didChoose: .finishScanning)
    }
}
