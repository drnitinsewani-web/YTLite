# Expense Tracker (phone web app)

A small, offline-first expense tracker you can install on your phone's home screen.
It has no server and no account: all data stays in your phone's browser storage.

## Features
- Quick add: amount, category, date, payment method (Cash/Card/UPI/Bank/Other), note
- Tap any expense to edit or delete it
- Month-by-month view with daily grouping and search
- Monthly budget with a progress bar (turns amber at 80%, red when over)
- Summary: total, daily average, transaction count, change vs last month,
  spending by category, and a 6-month bar chart
- Custom categories (with emoji), multiple currencies
- Export to CSV, back up and restore as JSON
- Works offline (service worker), light and dark mode

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
