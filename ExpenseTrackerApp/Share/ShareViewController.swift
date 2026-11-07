import UIKit
import UniformTypeIdentifiers

/// Appears as "Kharcha" in the iOS share sheet. Saves the shared text (e.g. a
/// bank SMS) to the App Group inbox; the main app shows it for review when opened.
final class ShareViewController: UIViewController {
    private let card = UIView()
    private let titleLabel = UILabel()
    private let detailLabel = UILabel()
    private let doneButton = UIButton(type: .system)

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor.black.withAlphaComponent(0.35)
        buildCard()
        collectText { [weak self] texts in
            DispatchQueue.main.async { self?.finish(with: texts) }
        }
    }

    private func buildCard() {
        card.backgroundColor = .systemBackground
        card.layer.cornerRadius = 20
        card.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(card)

        titleLabel.text = "Saving to Kharcha…"
        titleLabel.font = .preferredFont(forTextStyle: .headline)
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 0

        detailLabel.font = .preferredFont(forTextStyle: .subheadline)
        detailLabel.textColor = .secondaryLabel
        detailLabel.textAlignment = .center
        detailLabel.numberOfLines = 0

        doneButton.setTitle("Done", for: .normal)
        doneButton.titleLabel?.font = .preferredFont(forTextStyle: .headline)
        doneButton.isHidden = true
        doneButton.addTarget(self, action: #selector(close), for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [titleLabel, detailLabel, doneButton])
        stack.axis = .vertical
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)

        NSLayoutConstraint.activate([
            card.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            card.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            card.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.82),
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 22),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -16),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -20)
        ])
    }

    /// Gathers plain text from every shared item.
    private func collectText(_ completion: @escaping ([String]) -> Void) {
        let items = (extensionContext?.inputItems as? [NSExtensionItem]) ?? []
        let group = DispatchGroup()
        let lock = NSLock()
        var texts: [String] = []
        func add(_ s: String?) {
            guard let s = s?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return }
            lock.lock(); if !texts.contains(s) { texts.append(s) }; lock.unlock()
        }

        let textType = UTType.plainText.identifier
        let urlType = UTType.url.identifier
        for item in items {
            add(item.attributedContentText?.string)
            for provider in item.attachments ?? [] {
                if provider.hasItemConformingToTypeIdentifier(textType) {
                    group.enter()
                    provider.loadItem(forTypeIdentifier: textType, options: nil) { value, _ in
                        if let s = value as? String { add(s) }
                        else if let d = value as? Data { add(String(data: d, encoding: .utf8)) }
                        else if let u = value as? URL { add(try? String(contentsOf: u, encoding: .utf8)) }
                        group.leave()
                    }
                } else if provider.hasItemConformingToTypeIdentifier(urlType) {
                    group.enter()
                    provider.loadItem(forTypeIdentifier: urlType, options: nil) { value, _ in
                        if let u = value as? URL, !u.isFileURL { add(u.absoluteString) }
                        group.leave()
                    }
                }
            }
        }
        group.notify(queue: .global()) { completion(texts) }
    }

    private func finish(with texts: [String]) {
        guard !texts.isEmpty else {
            show(title: "Nothing to save", detail: "Share the text of a bank SMS or UPI message.", autoClose: false)
            return
        }
        let saved = SharedInbox.append(texts.joined(separator: "\n\n"))
        if saved {
            show(title: "Saved ✓", detail: "Open Kharcha to review and add it.", autoClose: true)
        } else {
            show(title: "Couldn’t save", detail: "The app group isn’t set up for this build.", autoClose: false)
        }
    }

    private func show(title: String, detail: String, autoClose: Bool) {
        titleLabel.text = title
        detailLabel.text = detail
        doneButton.isHidden = false
        if autoClose {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { [weak self] in self?.close() }
        }
    }

    private var closed = false

    @objc private func close() {
        guard !closed else { return }
        closed = true
        extensionContext?.completeRequest(returningItems: nil)
    }
}
