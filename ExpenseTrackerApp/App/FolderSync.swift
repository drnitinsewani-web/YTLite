import Foundation

/// A folder the user picked (e.g. in iCloud Drive) that Kharcha watches for statements.
/// Access survives restarts through a bookmark; files already handled are remembered by
/// name + size + modification date, so a statement is imported once (and again only if replaced).
final class FolderSync {
    static let shared = FolderSync()

    /// `note`: why the file wasn't read (it comes with no data and is shown in the folder's log);
    /// `retry`: it may be readable next time.
    struct NewFile { let name: String; let data: Data; let key: String; var note: String? = nil; var retry = false }

    private let bookmarkKey = "statementFolderBookmark"
    private let seenKey = "statementFolderSeen"
    private let defaults = UserDefaults.standard
    static let extensions: Set<String> = ["csv", "tsv", "txt", "xls", "xlsx", "ods", "pdf"]
    static let maxFileSize = 25_000_000
    /// About this much is handed to the web app per check (it holds several copies while importing).
    static let batchSize = 12_000_000

    var isSet: Bool { defaults.data(forKey: bookmarkKey) != nil }
    var folderName: String? { resolve()?.lastPathComponent }

    /// Saves access to a folder returned by the document picker.
    @discardableResult
    func setFolder(_ url: URL) -> Bool {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) else { return false }
        defaults.set(data, forKey: bookmarkKey)
        defaults.removeObject(forKey: seenKey)   // a new folder: look at everything in it once
        return true
    }

    /// When Kharcha learns to read a new kind of file, every file in the folder is looked at again
    /// once (statements already imported are recognised as duplicates and skipped).
    func setParserVersion(_ v: Int) {
        let key = "statementFolderParser"
        if defaults.integer(forKey: key) != v {
            defaults.removeObject(forKey: seenKey)
            defaults.set(v, forKey: key)
        }
    }

    /// Forget which files were imported, so the next check imports everything in the folder again.
    func forgetSeen() { defaults.removeObject(forKey: seenKey) }

    /// Look at these files again on the next check (e.g. PDFs that needed a DeepSeek key, once one is added).
    func forget(_ keys: [String]) {
        let drop = Set(keys)
        let list = (defaults.stringArray(forKey: seenKey) ?? []).filter { !drop.contains($0) }
        defaults.set(list, forKey: seenKey)
    }

    func clear() {
        defaults.removeObject(forKey: bookmarkKey)
        defaults.removeObject(forKey: seenKey)
    }

    private func resolve() -> URL? {
        guard let data = defaults.data(forKey: bookmarkKey) else { return nil }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &stale) else { return nil }
        if stale, let fresh = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
            defaults.set(fresh, forKey: bookmarkKey)
        }
        return url
    }

    private var seen: Set<String> { Set(defaults.stringArray(forKey: seenKey) ?? []) }

    func markSeen(_ keys: [String]) {
        guard !keys.isEmpty else { return }
        var list = defaults.stringArray(forKey: seenKey) ?? []
        list.append(contentsOf: keys.filter { !list.contains($0) })
        defaults.set(Array(list.suffix(3000)), forKey: seenKey)
    }

    /// Statements in the folder not handled yet, about `batchSize` bytes of them: `more` counts the ones
    /// left for the next check. Files still in iCloud are asked to download and counted in `pending`
    /// (check again shortly). `error` is set if the folder can't be read. `skip`: files not to read now.
    func newFiles(skipping skip: Set<String> = []) -> (files: [NewFile], pending: Int, more: Int, error: String?) {
        guard let folder = resolve() else { return ([], 0, 0, isSet ? "Kharcha lost access to the folder. Choose it again." : nil) }
        let scoped = folder.startAccessingSecurityScopedResource()
        defer { if scoped { folder.stopAccessingSecurityScopedResource() } }

        var files: [NewFile] = [], pending = 0, more = 0, total = 0, failure: String?
        let seen = self.seen
        let fm = FileManager.default
        let keys: [URLResourceKey] = [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey,
                                      .ubiquitousItemDownloadingStatusKey, .isUbiquitousItemKey]
        var coordError: NSError?
        NSFileCoordinator().coordinate(readingItemAt: folder, options: [], error: &coordError) { dir in
            guard let entries = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: keys, options: []) else {
                failure = "Couldn't open the folder."
                return
            }
            for url in entries {
                var name = url.lastPathComponent
                // older iOS: a file not downloaded yet shows as ".Name.pdf.icloud"
                if name.hasPrefix("."), name.hasSuffix(".icloud") {
                    name = String(name.dropFirst().dropLast(7))
                    if Self.extensions.contains((name as NSString).pathExtension.lowercased()) {
                        try? fm.startDownloadingUbiquitousItem(at: dir.appendingPathComponent(name))
                        pending += 1
                    }
                    continue
                }
                if name.hasPrefix(".") { continue }
                guard Self.extensions.contains(url.pathExtension.lowercased()) else { continue }
                let values = try? url.resourceValues(forKeys: Set(keys))
                if values?.isDirectory == true { continue }
                if values?.isUbiquitousItem == true,
                   let status = values?.ubiquitousItemDownloadingStatus, status != .current {
                    try? fm.startDownloadingUbiquitousItem(at: url)
                    pending += 1
                    continue
                }
                let stamp = Int(values?.contentModificationDate?.timeIntervalSince1970 ?? 0)
                let size = values?.fileSize ?? 0
                let key = "\(name)|\(size)|\(stamp)"
                if seen.contains(key) || skip.contains(key) { continue }
                let tooBig = "too big to read from the folder (25 MB or more): open it with 📥 Import"
                if size >= Self.maxFileSize {
                    files.append(NewFile(name: name, data: Data(), key: key, note: tooBig))
                    continue
                }
                if total > 0 && total + size > Self.batchSize {
                    more += 1
                    continue
                }
                var data: Data?
                var readError: NSError?
                NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &readError) { fileURL in
                    data = try? Data(contentsOf: fileURL)
                }
                guard let read = data else {
                    files.append(NewFile(name: name, data: Data(), key: key, note: "couldn’t open this file", retry: true))
                    continue
                }
                if read.isEmpty { continue }   // still being saved: looked at again next time
                if read.count >= Self.maxFileSize {
                    files.append(NewFile(name: name, data: Data(), key: key, note: tooBig))
                    continue
                }
                files.append(NewFile(name: name, data: read, key: key))
                total += read.count
            }
        }
        if let coordError = coordError, failure == nil { failure = coordError.localizedDescription }
        return (files, pending, more, failure)
    }
}
