import Foundation

/// Keeps the app's data (one JSON document) in Application Support, which iOS
/// backs up and never clears, unlike web storage.
enum StateStore {
    private static var fileURL: URL? {
        guard let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("expenses-state.json")
    }

    static func load() -> String? {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func save(_ json: String) {
        guard let url = fileURL, let data = json.data(using: .utf8) else { return }
        try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}
