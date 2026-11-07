import Foundation

/// Keeps a copy of the app's data in the user's private iCloud (iCloud key-value storage),
/// so it follows the Apple ID to other iPhones/iPads and survives reinstalling.
/// The data is zlib-compressed; iCloud key-value storage allows up to 1 MB per app.
final class CloudSync {
    static let shared = CloudSync()

    private let store = NSUbiquitousKeyValueStore.default
    private let key = "expenses-state-v1"
    private let stampKey = "expenses-state-v1-at"
    var onRemoteChange: (() -> Void)?

    /// True when the device is signed in to iCloud (Settings › your name › iCloud).
    var isAvailable: Bool { FileManager.default.ubiquityIdentityToken != nil }

    var lastWrite: Double { store.double(forKey: stampKey) }

    func start() {
        NotificationCenter.default.addObserver(forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
                                               object: store, queue: .main) { [weak self] _ in
            self?.onRemoteChange?()
        }
        store.synchronize()
    }

    /// The JSON saved in iCloud, or nil if there is none yet.
    func read() -> String? {
        guard let data = store.data(forKey: key) else { return nil }
        var raw = data
        if let unpacked = try? (data as NSData).decompressed(using: .zlib) {
            raw = unpacked as Data
        }
        return String(data: raw, encoding: .utf8)
    }

    /// Saves the JSON to iCloud. Returns nil on success, otherwise a message for the user.
    func write(_ json: String) -> String? {
        guard isAvailable else { return "Not signed in to iCloud" }
        guard let raw = json.data(using: .utf8) else { return "Could not encode the data" }
        var data = raw
        if let packed = try? (raw as NSData).compressed(using: .zlib) {
            data = packed as Data
        }
        if data.count > 960_000 {
            return "Too much data for iCloud (\(data.count / 1024) KB of 1 MB)"
        }
        store.set(data, forKey: key)
        store.set(Date().timeIntervalSince1970, forKey: stampKey)
        store.synchronize()
        return nil
    }
}
