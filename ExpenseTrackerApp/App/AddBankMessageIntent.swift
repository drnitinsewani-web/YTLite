import AppIntents
import Foundation
import UIKit

/// Shortcuts action "Add Bank Message". Used from a Personal Automation
/// (Shortcuts → Automation → Message) so bank SMS reach the app automatically.
/// Runs in the background: the text is queued in the App Group inbox and the
/// app picks it up the next time it opens.
@available(iOS 16.0, *)
struct AddBankMessageIntent: AppIntent {
    static var title: LocalizedStringResource = "Add Bank Message"
    static var description = IntentDescription("Sends a bank, UPI or card message to Kharcha. It is added the next time you open the app.")
    static var openAppWhenRun: Bool = false

    /// Optional: from Siri there is no message, so the copied text is used.
    @Parameter(title: "Message")
    var message: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Add \(\.$message) to Kharcha")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        var text = (message ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        var fromClipboard = false
        if text.isEmpty {
            let copied: String = await MainActor.run { UIPasteboard.general.string ?? "" }
            text = copied.trimmingCharacters(in: .whitespacesAndNewlines)
            fromClipboard = true
        }
        if text.isEmpty {
            return .result(dialog: "Copy a bank message first (touch and hold it in Messages → Copy), then ask me again.")
        }
        if SharedInbox.appendMessage(text) {
            return .result(dialog: fromClipboard ? "Sent the copied message to Kharcha. It's added when you open the app." : "Saved to Kharcha.")
        }
        return .result(dialog: "Couldn't save the message. Open Kharcha once and try again.")
    }
}

