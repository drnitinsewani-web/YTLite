import Foundation

/// Texts shared into the Share Extension wait here (in the App Group container)
/// until the main app opens and picks them up.
enum SharedInbox {
    private static var container: URL? {
        guard let group = Bundle.main.object(forInfoDictionaryKey: "AppGroupID") as? String else { return nil }
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)
    }

    private static var fileURL: URL? {
        container?.appendingPathComponent("shared-inbox.json")
    }

    /// Statement files (CSV / XLS / XLSX / PDF) shared into the extension.
    private static var filesDir: URL? {
        container?.appendingPathComponent("shared-files", isDirectory: true)
    }

    static func appendFile(from source: URL, name: String) -> Bool {
        guard let dir = filesDir else { return false }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let safeName = name.replacingOccurrences(of: "/", with: "-")
        let dest = dir.appendingPathComponent(UUID().uuidString + "__" + safeName)
        do {
            try FileManager.default.copyItem(at: source, to: dest)
            return true
        } catch {
            return false
        }
    }

    static func takeFiles() -> [(name: String, data: Data)] {
        guard let dir = filesDir,
              let urls = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return [] }
        var out: [(name: String, data: Data)] = []
        for url in urls.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            if let data = try? Data(contentsOf: url) {
                let stored = url.lastPathComponent
                let original = stored.components(separatedBy: "__").dropFirst().joined(separator: "__")
                out.append((name: original.isEmpty ? stored : original, data: data))
            }
            try? FileManager.default.removeItem(at: url)
        }
        return out
    }

    private static func read(_ url: URL) -> [String] {
        guard let data = try? Data(contentsOf: url),
              let items = try? JSONSerialization.jsonObject(with: data) as? [String] else { return [] }
        return items
    }

    /// Returns false if the App Group is not available (e.g. misconfigured signing).
    @discardableResult
    static func append(_ text: String) -> Bool {
        guard let url = fileURL else { return false }
        var ok = false
        var error: NSError?
        NSFileCoordinator().coordinate(writingItemAt: url, options: [], error: &error) { target in
            var items = read(target)
            items.append(text)
            if let data = try? JSONSerialization.data(withJSONObject: items) {
                ok = (try? data.write(to: target, options: .atomic)) != nil
            }
        }
        return ok && error == nil
    }

    static func takeAll() -> [String] {
        guard let url = fileURL else { return [] }
        var items: [String] = []
        var error: NSError?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forDeleting, error: &error) { target in
            items = read(target)
            try? FileManager.default.removeItem(at: target)
        }
        return items
    }
}
