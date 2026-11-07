import UIKit
import WebKit

/// Hosts the bundled web app (www/) and bridges it to native features:
/// durable storage, file export through the share sheet, and texts received
/// from the Share Extension.
final class WebViewController: UIViewController, WKScriptMessageHandler, WKUIDelegate, WKNavigationDelegate {
    static let scheme = "expenses"
    private var webView: WKWebView!
    private var jsReady = false

    override func loadView() {
        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(BundleSchemeHandler(), forURLScheme: Self.scheme)
        config.userContentController.add(WeakMessageHandler(self), name: "expenses")
        installStateScript(on: config.userContentController)

        webView = WKWebView(frame: .zero, configuration: config)
        webView.uiDelegate = self
        webView.navigationDelegate = self
        webView.isOpaque = false
        webView.backgroundColor = UIColor(named: "LaunchBackground")
        webView.scrollView.backgroundColor = UIColor(named: "LaunchBackground")
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        if #available(iOS 16.4, *) { webView.isInspectable = true }
        view = webView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        load()
        NotificationCenter.default.addObserver(self, selector: #selector(appDidBecomeActive),
                                               name: UIApplication.didBecomeActiveNotification, object: nil)
    }

    private func load() {
        jsReady = false
        webView.load(URLRequest(url: URL(string: "\(Self.scheme)://localhost/index.html")!))
    }

    /// Injects the saved data before the page's own scripts run.
    private func installStateScript(on controller: WKUserContentController) {
        controller.removeAllUserScripts()
        let saved = StateStore.load() ?? "null"
        let source = "window.__EXPENSES_NATIVE__ = true; window.__EXPENSES_NATIVE_STATE__ = \(jsString(saved));"
        controller.addUserScript(WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: true))
    }

    @objc private func appDidBecomeActive() { deliverSharedTexts() }

    private func deliverSharedTexts() {
        guard jsReady else { return }
        // Statement files shared from Mail / Files / WhatsApp open the import screen
        for file in SharedInbox.takeFiles() {
            let js = "window.expensesReceiveFile && window.expensesReceiveFile(\(jsString(file.name)), \(jsString(file.data.base64EncodedString())))"
            webView.evaluateJavaScript(js)
        }
        let texts = SharedInbox.takeAll()
        guard !texts.isEmpty else { return }
        let joined = texts.joined(separator: "\n\n")
        webView.evaluateJavaScript("window.expensesReceiveShared && window.expensesReceiveShared(\(jsString(joined)))")
    }

    // MARK: - Messages from JavaScript

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
        switch type {
        case "save":
            if let data = body["data"] as? String { StateStore.save(data) }
        case "ready":
            jsReady = true
            deliverSharedTexts()
        case "export":
            let name = (body["name"] as? String) ?? "export.txt"
            let text = (body["text"] as? String) ?? ""
            export(name: name, text: text)
        default:
            break
        }
    }

    private func export(name: String, text: String) {
        let safeName = name.replacingOccurrences(of: "/", with: "-")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(safeName)
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            return
        }
        let sheet = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        sheet.popoverPresentationController?.sourceView = view
        sheet.popoverPresentationController?.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1)
        topPresenter().present(sheet, animated: true)
    }

    // MARK: - Navigation

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if let url = navigationAction.request.url,
           let scheme = url.scheme?.lowercased(),
           ["http", "https", "mailto", "tel"].contains(scheme),
           navigationAction.targetFrame?.isMainFrame ?? true {
            UIApplication.shared.open(url)
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        installStateScript(on: webView.configuration.userContentController)
        load()
    }

    // MARK: - alert() / confirm() support

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler() })
        present(alert, orElse: completionHandler)
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in completionHandler(false) })
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler(true) })
        present(alert, orElse: { completionHandler(false) })
    }

    private func present(_ alert: UIAlertController, orElse fallback: @escaping () -> Void) {
        let presenter = topPresenter()
        if presenter is UIAlertController { fallback(); return }
        presenter.present(alert, animated: true)
    }

    private func topPresenter() -> UIViewController {
        var top: UIViewController = self
        while let next = top.presentedViewController { top = next }
        return top
    }

    /// Encodes a Swift string as a JavaScript string literal.
    private func jsString(_ s: String) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: [s]),
              let json = String(data: data, encoding: .utf8) else { return "\"\"" }
        return String(json.dropFirst().dropLast())
    }
}

/// Avoids a retain cycle between WKUserContentController and the view controller.
private final class WeakMessageHandler: NSObject, WKScriptMessageHandler {
    weak var target: WKScriptMessageHandler?
    init(_ target: WKScriptMessageHandler) { self.target = target }
    func userContentController(_ c: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(c, didReceive: message)
    }
}
