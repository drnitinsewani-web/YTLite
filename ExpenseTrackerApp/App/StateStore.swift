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
        snapshotBeforeSaving(newSize: data.count, current: url)
        try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    // MARK: - Automatic backups (on this iPhone, in Application Support)
    // A copy of the data as it was at the start of each day (last 10 days), and an extra copy
    // whenever a save would shrink the data to less than half (last 5) — so a mistake or a bad
    // sync can always be undone from Settings › Data › Automatic backups.

    private static var backupDir: URL? {
        guard let base = fileURL?.deletingLastPathComponent() else { return nil }
        let dir = base.appendingPathComponent("backups", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func snapshotBeforeSaving(newSize: Int, current: URL) {
        let fm = FileManager.default
        guard let dir = backupDir,
              let attrs = try? fm.attributesOfItem(atPath: current.path),
              let oldSize = (attrs[.size] as? NSNumber)?.intValue, oldSize > 200 else { return }
        let day = DateFormatter()
        day.calendar = Calendar(identifier: .gregorian)
        day.locale = Locale(identifier: "en_US_POSIX")
        day.dateFormat = "yyyy-MM-dd"
        let daily = dir.appendingPathComponent("daily-\(day.string(from: Date())).json")
        if !fm.fileExists(atPath: daily.path) {
            try? fm.copyItem(at: current, to: daily)
            prune(prefix: "daily-", keep: 10)
        }
        if oldSize > 20_000 && newSize < oldSize / 2 {
            let stamp = Int(Date().timeIntervalSince1970)
            try? fm.copyItem(at: current, to: dir.appendingPathComponent("before-shrink-\(stamp).json"))
            prune(prefix: "before-shrink-", keep: 5)
        }
    }

    private static func prune(prefix: String, keep: Int) {
        guard let dir = backupDir,
              let names = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else { return }
        let mine = names.filter { $0.hasPrefix(prefix) }.sorted()
        for name in mine.dropLast(keep) { try? FileManager.default.removeItem(at: dir.appendingPathComponent(name)) }
    }

    /// Backups, newest first: file name, when it was saved, and how many entries it holds.
    static func backups() -> [[String: Any]] {
        let fm = FileManager.default
        guard let dir = backupDir, let names = try? fm.contentsOfDirectory(atPath: dir.path) else { return [] }
        var out: [[String: Any]] = []
        for name in names where name.hasSuffix(".json") {
            let url = dir.appendingPathComponent(name)
            let date = ((try? fm.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date) ?? Date.distantPast
            var entries = -1
            if let data = try? Data(contentsOf: url),
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let list = obj["expenses"] as? [Any] { entries = list.count }
            out.append(["name": name, "at": date.timeIntervalSince1970, "entries": entries])
        }
        return out.sorted { (($0["at"] as? Double) ?? 0) > (($1["at"] as? Double) ?? 0) }
    }

    /// A copy of the current data, taken just before a backup is restored over it (last 3 kept).
    static func snapshotBeforeRestore() {
        guard let url = fileURL, let dir = backupDir, FileManager.default.fileExists(atPath: url.path) else { return }
        try? FileManager.default.copyItem(at: url, to: dir.appendingPathComponent("before-restore-\(Int(Date().timeIntervalSince1970)).json"))
        prune(prefix: "before-restore-", keep: 3)
    }

    static func readBackup(_ name: String) -> String? {
        guard !name.contains("/"), let dir = backupDir,
              let data = try? Data(contentsOf: dir.appendingPathComponent(name)) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
