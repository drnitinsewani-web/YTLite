# Expense Tracker (phone web app)

A small, offline-first expense tracker you can install on your phone's home screen.
It has no server and no account: all data stays in your phone's browser storage.

## Features
- Quick add for expenses **and income**: amount, category, date, payment method (Cash/Card/UPI/Bank/Other), note
- **Bank statement import** (CSV, XLS, XLSX) with automatic debit/credit detection and categorisation
- Tap any expense to edit or delete it
- Month-by-month view with daily grouping and search
- Monthly budget with a progress bar (turns amber at 80%, red when over)
- Summary: total, daily average, transaction count, change vs last month,
  spending by category, and a 6-month bar chart
- Custom categories (with emoji), multiple currencies
- Export to CSV, back up and restore as JSON
- Works offline (service worker), light and dark mode

## Importing bank statements
1. In net banking, download the account or credit-card statement as **CSV or Excel**
   (PDF can't be read reliably, so choose the Excel/CSV option).
2. Tap **📥** on the Expenses screen, or **Settings → Import bank statement**, and pick the file.
3. The app finds the date, description and debit/credit (or single amount) columns
   on its own; formats like HDFC, SBI, ICICI and Axis, credit-card statements and US banks work.
   If something looks off, open **Columns & format** to fix the column mapping or date order.
4. Review the preview: withdrawals become expenses, deposits become income, and each
   row has a category picked from merchant keywords (Swiggy → Food, DMart → Groceries,
   Uber → Transport, BESCOM/Airtel → Bills, salary, interest, refunds…).
   Use the **Uncategorised** filter to fix the rest.
5. Tap **Import**.

**It learns:** when you change a category, the merchant is remembered (see
*Settings → Learned rules*) and other rows from the same merchant are updated too.
**No double counting:** credit-card bill payments and transfers between your own accounts
go to *Transfer*, which isn't counted in spending or income, and rows you already
imported are flagged and unticked when you import the same statement again.

Excel files need an internet connection the first time (the reader library loads from
cdnjs); CSV import works fully offline.

## Adding from bank SMS
- **iPhone:** long-press the bank SMS → **Copy**, open the app, tap **💬**, paste
  (or tap *Paste from clipboard*) and tap **Read messages**. You can paste several messages at once.
  iOS does not let home-screen web apps appear in the Share sheet, so copy → paste is the quickest route.
- **Android:** after installing the app, choose **Share → Expenses** on a message and it opens ready to save.

The reader picks out the amount (ignoring "Avl Bal"), debit or credit, date, the payee or payer and the bank,
then categorises it like a statement row. OTPs, "will be debited" autopay notices, failed and declined
transactions and payment requests are ignored. Pasting the same SMS twice is detected, and when the same
transaction later arrives in a statement import it is flagged as a *possible duplicate* and left unticked.

## Gmail: bank alert emails
The app can look through your Gmail for bank, UPI and card alert emails (debits and credits) and
add them through the same review screen as SMS.

It uses a tiny **Google Apps Script** that runs inside your own Google account, so there is no
server in between and no Google Cloud setup:
1. **Settings → Email (Gmail) → Copy setup script.** The script already contains a private key
   that only your app knows.
2. On [script.google.com](https://script.google.com) (signed in to the Gmail that receives bank alerts):
   **New project**, replace the contents with the script.
3. **Deploy → New deployment → Web app.** Execute as **Me**, Who has access **Anyone**. Deploy and allow
   Gmail access (Google shows an "unverified app" warning for personal scripts: *Advanced → Go to project*).
4. Copy the **Web app URL** into the app's *Gmail bridge address* box.

The app checks automatically when opened (at most hourly), or tap **Check email now**. The first check
covers the last 45 days. Each email is only offered once, and anything already added from SMS or a
statement is flagged as a possible duplicate. The script answers only requests carrying your key, and
returns just the alert sentence around each amount, nothing else from your mailbox.
To disconnect, clear the address in the app and delete the deployment in Apps Script.

## Put it on your phone
The app is static files, so any static host will work. With GitHub Pages:

1. In the repo, open **Settings → Pages**, choose "Deploy from a branch" and select this branch, folder `/ (root)`.
2. Open `https://<your-user>.github.io/<repo>/ExpenseTracker/` on your phone.
3. **iPhone (Safari):** Share → *Add to Home Screen*.
   **Android (Chrome):** ⋮ menu → *Install app* / *Add to Home screen*.

To try it locally: `cd ExpenseTracker && python3 -m http.server 8000`, then open
`http://<your-computer-ip>:8000` from a phone on the same Wi-Fi.

## Your data
Expenses are saved in `localStorage` on the device. Clearing the browser's site data,
or uninstalling the app, deletes them. Use **Settings → Back up (JSON)** regularly
and **Restore from backup** to move to a new phone.
