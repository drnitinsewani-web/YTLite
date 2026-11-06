import Foundation

/// Texts shared into the Share Extension wait here (in the App Group container)
/// until the main app opens and picks them up.
enum SharedInbox {
    private static var fileURL: URL? {
        guard let group = Bundle.main.object(forInfoDictionaryKey: "AppGroupID") as? String,
              let dir = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) else { return nil }
        return dir.appendingPathComponent("shared-inbox.json")
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
