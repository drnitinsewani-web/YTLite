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
