import AppIntents
import Foundation

/// Shortcuts action "Add Bank Message". Used from a Personal Automation
/// (Shortcuts → Automation → Message) so bank SMS reach the app automatically.
/// Runs in the background: the text is queued in the App Group inbox and the
/// app picks it up the next time it opens.
@available(iOS 16.0, *)
struct AddBankMessageIntent: AppIntent {
    static var title: LocalizedStringResource = "Add Bank Message"
    static var description = IntentDescription("Sends a bank, UPI or card message to Kharcha. It is added the next time you open the app.")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Message")
    var message: String

    static var parameterSummary: some ParameterSummary {
        Summary("Add \(\.$message) to Kharcha")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let text = message.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty {
            return .result(dialog: "There was no message text to add.")
        }
        if SharedInbox.append(text) {
            return .result(dialog: "Saved to Kharcha.")
        }
        return .result(dialog: "Couldn't save the message. Open Kharcha once and try again.")
    }
}

@available(iOS 16.0, *)
struct KharchaShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: AddBankMessageIntent(),
                    phrases: ["Add bank message to \(.applicationName)"])
    }
}
