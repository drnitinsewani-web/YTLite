import UIKit
import WebKit
import UniformTypeIdentifiers

/// Hosts the bundled web app (www/) and bridges it to native features:
/// durable storage, file export through the share sheet, and texts received
/// from the Share Extension.
final class WebViewController: UIViewController, WKScriptMessageHandler, WKUIDelegate, WKNavigationDelegate, UIDocumentPickerDelegate {
    static let scheme = "expenses"
    private var webView: WKWebView!
    private var jsReady = false
    private var folderChecking = false
    private var folderRetries = 0
    /// Files the web app couldn't import this time (e.g. DeepSeek offline): tried again once the app is
    /// opened again or the folder is checked from Settings, not on the follow-up checks before that.
    private var folderLater = Set<String>()

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
        NotificationCenter.default.addObserver(self, selector: #selector(reduceTransparencyChanged),
                                               name: UIAccessibility.reduceTransparencyStatusDidChangeNotification, object: nil)
        CloudSync.shared.onRemoteChange = { [weak self] in self?.sendCloudData() }
        CloudSync.shared.start()
    }

    /// Hands the iCloud copy to the web app, which merges it with the data on this device.
    private func sendCloudData() {
        guard jsReady else { return }
        let cloud = CloudSync.shared
        let json = cloud.read().map { jsString($0) } ?? "null"
        webView.evaluateJavaScript("window.expensesCloudData && window.expensesCloudData(\(json), \(cloud.isAvailable), \(cloud.lastWrite))")
    }

    private func load() {
        jsReady = false
        webView.load(URLRequest(url: URL(string: "\(Self.scheme)://localhost/index.html")!))
    }

    /// Injects the saved data before the page's own scripts run: null when nothing is saved yet (a new
    /// install), text the page can't read when the file is there but couldn't be read.
    private func installStateScript(on controller: WKUserContentController) {
        controller.removeAllUserScripts()
        let saved = StateStore.load().map { jsString($0) } ?? (StateStore.hasFile ? jsString("unreadable") : "null")
        // Reduce Transparency (Settings › Accessibility) isn't a CSS media feature in WKWebView: the page is told,
        // and draws solid surfaces instead of glass (class a11y-solid)
        let solid = UIAccessibility.isReduceTransparencyEnabled
        let source = "window.__EXPENSES_NATIVE__ = true; window.__EXPENSES_NATIVE_STATE__ = \(saved); window.__EXPENSES_SOLID__ = \(solid);"
        controller.addUserScript(WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: true))
    }

    @objc private func reduceTransparencyChanged() {
        webView.evaluateJavaScript("document.documentElement.classList.toggle('a11y-solid', \(UIAccessibility.isReduceTransparencyEnabled))")
    }

    @objc private func appDidBecomeActive() {
        deliverSharedTexts()
        sendCloudData()
        folderRetries = 0
        folderLater.removeAll()
        checkFolder()
    }

    // MARK: - Statement folder (e.g. in iCloud Drive)

    private func sendFolderInfo(status: String? = nil) {
        guard jsReady else { return }
        let sync = FolderSync.shared
        let name = sync.isSet ? jsString(sync.folderName ?? "Folder") : "null"
        let msg = status.map { jsString($0) } ?? "null"
        webView.evaluateJavaScript("window.expensesFolderInfo && window.expensesFolderInfo(\(name), \(msg))")
    }

    private func pickFolder() {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [UTType.folder])
        picker.delegate = self
        picker.allowsMultipleSelection = false
        topPresenter().present(picker, animated: true)
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else { return }
        if FolderSync.shared.setFolder(url) {
            sendFolderInfo(status: "Folder chosen. Looking for statements…")
            folderRetries = 0
            folderLater.removeAll()
            checkFolder()
        } else {
            sendFolderInfo(status: "Couldn't get access to that folder. Try another one.")
        }
    }

    /// Reads new statements in the background and hands them to the web app, which imports
    /// them without asking (duplicates are skipped there). Files still downloading from
    /// iCloud are looked at again shortly. A few at a time: once the web app has imported
    /// them it asks for the rest ("folderMore").
    private func checkFolder() {
        guard jsReady, FolderSync.shared.isSet, !folderChecking else { return }
        folderChecking = true
        let skip = folderLater
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let result = FolderSync.shared.newFiles(skipping: skip)
            let payload: [[String: String]] = result.files.map { file -> [String: String] in
                var item: [String: String] = ["name": file.name, "key": file.key, "b64": file.data.base64EncodedString()]
                if let note = file.note { item["note"] = note }
                if file.retry { item["retry"] = "1" }
                return item
            }
            let json = (try? JSONSerialization.data(withJSONObject: payload)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.folderChecking = false
                let err = result.error.map { self.jsString($0) } ?? "null"
                self.webView.evaluateJavaScript("window.expensesFolderFiles && window.expensesFolderFiles(\(json), \(result.pending), \(err), \(result.more))")
                if result.pending > 0 && self.folderRetries < 6 {
                    self.folderRetries += 1
                    DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in self?.checkFolder() }
                }
            }
        }
    }

    /// Asks the page first: it says no while one of its sheets is open or its saved data couldn't be
    /// read, and everything stays in the inbox until it sends "inboxOpen".
    private func deliverSharedTexts() {
        guard jsReady else { return }
        webView.evaluateJavaScript("window.expensesCanReceive ? window.expensesCanReceive() : true") { [weak self] result, _ in
            guard let self = self, self.jsReady, (result as? Bool) ?? true else { return }
            self.sendInbox()
        }
    }

    private func sendInbox() {
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
            if let v = body["parser"] as? Int { FolderSync.shared.setParserVersion(v) }
            jsReady = true
            deliverSharedTexts()
            sendCloudData()
            sendFolderInfo()
            folderRetries = 0
            checkFolder()
        case "inboxOpen":
            deliverSharedTexts()
        case "backups":
            let list = (try? JSONSerialization.data(withJSONObject: StateStore.backups())).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
            webView.evaluateJavaScript("window.expensesBackups && window.expensesBackups(\(list))")
        case "backupRead":
            let name = (body["name"] as? String) ?? ""
            // read it first: the copy of the current data made next can push the oldest restore point out
            let backup = StateStore.readBackup(name)
            if backup != nil { StateStore.snapshotBeforeRestore() }
            let text = backup.map { jsString($0) } ?? "null"
            webView.evaluateJavaScript("window.expensesBackupData && window.expensesBackupData(\(jsString(name)), \(text))")
        case "folderPick":
            pickFolder()
        case "folderRescan":
            FolderSync.shared.forgetSeen()
            folderRetries = 0
            folderLater.removeAll()
            checkFolder()
        case "folderCheck":
            folderRetries = 0
            folderLater.removeAll()
            checkFolder()
        case "folderMore":
            checkFolder()
        case "folderForget":
            FolderSync.shared.forget((body["keys"] as? [String]) ?? [])
            folderRetries = 0
            checkFolder()
        case "folderLater":
            folderLater.formUnion((body["keys"] as? [String]) ?? [])
        case "folderClear":
            FolderSync.shared.clear()
            sendFolderInfo()
        case "folderDone":
            FolderSync.shared.markSeen((body["keys"] as? [String]) ?? [])
        case "cloudPull":
            sendCloudData()
        case "cloudPush":
            let error = (body["data"] as? String).flatMap { CloudSync.shared.write($0) }
            let arg = error.map { jsString($0) } ?? "null"
            webView.evaluateJavaScript("window.expensesCloudPushed && window.expensesCloudPushed(\(arg), \(CloudSync.shared.lastWrite))")
        case "ai":
            callDeepSeek(id: (body["id"] as? String) ?? "", key: (body["key"] as? String) ?? "", payload: (body["body"] as? String) ?? "{}")
        case "export":
            let name = (body["name"] as? String) ?? "export.txt"
            let text = (body["text"] as? String) ?? ""
            export(name: name, text: text)
        default:
            break
        }
    }

    // DeepSeek request made natively so the web page isn't limited by browser cross-site rules.
    private func callDeepSeek(id: String, key: String, payload: String) {
        guard let url = URL(string: "https://api.deepseek.com/chat/completions") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 180
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.httpBody = payload.data(using: .utf8)
        URLSession.shared.dataTask(with: req) { [weak self] data, response, error in
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let text = data.flatMap { String(data: $0, encoding: .utf8) } ?? (error?.localizedDescription ?? "")
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.webView.evaluateJavaScript("window.expensesAiDone && window.expensesAiDone(\(self.jsString(id)), \(status), \(self.jsString(text)))")
            }
        }.resume()
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

    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (String?) -> Void) {
        let alert = UIAlertController(title: nil, message: prompt, preferredStyle: .alert)
        alert.addTextField { field in
            field.text = defaultText
            field.clearButtonMode = .whileEditing
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in completionHandler(nil) })
        alert.addAction(UIAlertAction(title: "OK", style: .default) { [weak alert] _ in
            completionHandler(alert?.textFields?.first?.text ?? "")
        })
        present(alert, orElse: { completionHandler(nil) })
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
