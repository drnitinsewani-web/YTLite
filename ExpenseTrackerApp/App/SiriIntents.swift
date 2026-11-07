import AppIntents
import Foundation
import UIKit

/// "Hey Siri, add expense in Kharcha" — asks how much and what for, then queues it for the app.
@available(iOS 16.0, *)
struct AddExpenseIntent: AppIntent {
    static var title: LocalizedStringResource = "Add Expense"
    static var description = IntentDescription("Adds a cash or other expense to Kharcha.")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Amount", requestValueDialog: "How much?")
    var amount: Double

    @Parameter(title: "What for", requestValueDialog: "What was it for?")
    var note: String

    static var parameterSummary: some ParameterSummary {
        Summary("Add \(\.$amount) for \(\.$note) to Kharcha")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard amount > 0 else { return .result(dialog: "The amount needs to be more than zero.") }
        let entry: [String: Any] = ["amount": amount, "note": note.trimmingCharacters(in: .whitespacesAndNewlines),
                                    "date": KharchaData.today(), "type": "debit"]
        guard let data = try? JSONSerialization.data(withJSONObject: entry),
              let json = String(data: data, encoding: .utf8),
              SharedInbox.append("kharcha:entry:" + json) else {
            return .result(dialog: "Couldn't save it. Open Kharcha once and try again.")
        }
        return .result(dialog: "Added \(KharchaData.money(amount)) for \(note) to Kharcha.")
    }
}

/// "Hey Siri, add this transaction to Kharcha" — the copied bank message plus a spoken comment.
/// If the transaction is already in Kharcha (from a statement, SMS…), the comment is added to it.
@available(iOS 16.0, *)
struct AddTransactionWithCommentIntent: AppIntent {
    static var title: LocalizedStringResource = "Add Transaction with Comment"
    static var description = IntentDescription("Adds the copied bank message to Kharcha with your comment.")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Comment", requestValueDialog: "What's the comment?")
    var comment: String

    @Parameter(title: "Message")
    var message: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Add \(\.$message) to Kharcha with comment \(\.$comment)")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        var text = (message ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty {
            let copied: String = await MainActor.run { UIPasteboard.general.string ?? "" }
            text = copied.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if text.isEmpty {
            return .result(dialog: "Copy the bank message first (touch and hold it in Messages, then Copy), and ask me again.")
        }
        let note = comment.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = try? JSONSerialization.data(withJSONObject: ["text": text, "comment": note]),
              let json = String(data: data, encoding: .utf8),
              SharedInbox.append("kharcha:msg:" + json) else {
            return .result(dialog: "Couldn't save it. Open Kharcha once and try again.")
        }
        return .result(dialog: IntentDialog(stringLiteral: "Done. Saved to Kharcha with the comment \u{201C}\(note)\u{201D}. It's added when you open the app."))
    }
}

/// "Hey Siri, how much have I spent in Kharcha" — this month's spending, top category, entries to review.
@available(iOS 16.0, *)
struct SpendingIntent: AppIntent {
    static var title: LocalizedStringResource = "Spending This Month"
    static var description = IntentDescription("Tells you how much you have spent this month.")
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let s = KharchaData.summary() else {
            return .result(dialog: "Open Kharcha once so I can read your entries.")
        }
        var parts = ["You've spent \(KharchaData.money(s.spent)) so far this month"]
        if let top = s.top { parts[0] += ", most on \(top.name) at \(KharchaData.money(top.amount))" }
        parts[0] += "."
        if s.income > 0 { parts.append("Income: \(KharchaData.money(s.income)).") }
        if s.toReview > 0 { parts.append("\(s.toReview) transaction\(s.toReview == 1 ? "" : "s") waiting for your comment.") }
        return .result(dialog: IntentDialog(stringLiteral: parts.joined(separator: " ")))
    }
}

/// Reads the app's saved data (written by the web view) for Siri answers.
enum KharchaData {
    struct Summary { let spent: Double; let income: Double; let top: (name: String, amount: Double)?; let toReview: Int }

    static func today() -> String {
        let f = DateFormatter(); f.calendar = Calendar(identifier: .gregorian); f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }

    static var currency: String {
        guard let json = StateStore.load(), let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let settings = obj["settings"] as? [String: Any], let c = settings["currency"] as? String else { return "INR" }
        return c
    }

    static func money(_ v: Double) -> String {
        let f = NumberFormatter(); f.numberStyle = .currency; f.currencyCode = currency
        f.locale = Locale(identifier: currency == "INR" ? "en_IN" : Locale.current.identifier)
        f.maximumFractionDigits = v.rounded() == v ? 0 : 2
        return f.string(from: NSNumber(value: v)) ?? String(format: "%.0f", v)
    }

    static func summary() -> Summary? {
        guard let json = StateStore.load(), let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let expenses = obj["expenses"] as? [[String: Any]] else { return nil }
        let excluded = Set(((obj["categories"] as? [[String: Any]]) ?? [])
            .filter { ($0["exclude"] as? Bool) == true }.compactMap { $0["name"] as? String })
            .union(["Transfer", "Investment", "Loan"])
        let month = String(today().prefix(7))
        let num: (Any?) -> Double = { v in (v as? Double) ?? Double("\(v ?? 0)") ?? 0 }
        // as in the app: money back linked to a payment (refundOf) is not income, and the payment
        // counts only what didn't come back; transfers Kharcha marked (autoXfer) never count
        var debitIds = Set<String>()
        for e in expenses where (e["type"] as? String) == "debit" { if let id = e["id"] as? String { debitIds.insert(id) } }
        var refunded: [String: Double] = [:]
        for e in expenses where (e["type"] as? String) == "credit" {
            if let to = e["refundOf"] as? String, debitIds.contains(to) { refunded[to, default: 0] += num(e["amount"]) }
        }
        var spent = 0.0, income = 0.0, byCat: [String: Double] = [:], toReview = 0
        for e in expenses {
            if (e["unread"] as? Bool) == true { toReview += 1 }
            guard let d = e["date"] as? String, d.hasPrefix(month) else { continue }
            let cat = (e["category"] as? String) ?? "Other"
            if excluded.contains(cat) || e["autoXfer"] != nil { continue }
            if (e["type"] as? String) == "credit" {
                if let to = e["refundOf"] as? String, debitIds.contains(to) { continue }
                income += num(e["amount"])
            } else {
                let amt = max(0, num(e["amount"]) - refunded[(e["id"] as? String) ?? "", default: 0])
                spent += amt; byCat[cat, default: 0] += amt
            }
        }
        let top = byCat.max { $0.value < $1.value }.map { (name: $0.key, amount: $0.value) }
        return Summary(spent: spent, income: income, top: top, toReview: toReview)
    }
}

@available(iOS 16.0, *)
struct KharchaShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: AddBankMessageIntent(),
                    phrases: ["Add bank message to \(.applicationName)",
                              "Send bank message to \(.applicationName)",
                              "Send copied message to \(.applicationName)",
                              "Add copied message to \(.applicationName)"])
        AppShortcut(intent: AddTransactionWithCommentIntent(),
                    phrases: ["Add this transaction to \(.applicationName)",
                              "Add this to \(.applicationName)",
                              "Add copied transaction to \(.applicationName)",
                              "Add transaction with comment to \(.applicationName)",
                              "Is transaction ko \(.applicationName) mein add karo"])
        AppShortcut(intent: AddExpenseIntent(),
                    phrases: ["Add expense in \(.applicationName)",
                              "Add expense to \(.applicationName)",
                              "Log spending in \(.applicationName)"])
        AppShortcut(intent: SpendingIntent(),
                    phrases: ["How much have I spent in \(.applicationName)",
                              "\(.applicationName) spending this month",
                              "Check my spending in \(.applicationName)"])
    }
}
