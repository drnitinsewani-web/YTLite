# Expenses — iOS app (TestFlight)

A native iOS wrapper around the web app in [`../ExpenseTracker`](../ExpenseTracker).
The same code runs inside the app, plus:

- **Share Extension:** "Kharcha" appears in the iOS share sheet. Share a bank SMS (or any text)
  and it waits in an inbox; the next time you open the app it shows up for review.
- **Durable storage:** data is saved in the app's own storage (Application Support), not browser storage.
- **Exports** (CSV and backup) open the iOS share sheet, so you can save them to Files, iCloud or WhatsApp.
- **Excel import works offline** (the SheetJS reader is bundled).
- **Gmail alerts** work the same as in the web app (see `../ExpenseTracker/README.md`).

The Xcode project is generated with [XcodeGen](https://github.com/yonaskolb/XcodeGen) from `project.yml`.
GitHub Actions (`.github/workflows/expenses-ios.yml`) builds it on a macOS runner and uploads it to TestFlight.

## One-time setup

You need a paid Apple Developer Program membership. The default bundle ID is `com.drnitinsewani.expenses`.
To use a different one, add a repository **variable** `IOS_BUNDLE_ID` and use it everywhere below.

### 1. Register the identifiers ([developer.apple.com → Certificates, IDs & Profiles](https://developer.apple.com/account/resources/identifiers/list))
1. **Identifiers → + → App Groups:** `group.com.drnitinsewani.expenses`
2. **Identifiers → + → App IDs → App:** bundle ID `com.drnitinsewani.expenses`, enable **App Groups**,
   then click *Configure* and tick the group above.
3. Repeat for the extension: `com.drnitinsewani.expenses.share`, with **App Groups** set to the same group.

### 2. Create the app record ([App Store Connect → Apps → +](https://appstoreconnect.apple.com/apps))
**New App**, platform iOS, any name (e.g. "Expenses – Nitin"; names must be unique on the App Store),
bundle ID `com.drnitinsewani.expenses`, any SKU (e.g. `expenses1`).

### 3. Create an API key ([App Store Connect → Users and Access → Integrations → App Store Connect API](https://appstoreconnect.apple.com/access/integrations/api))
**Team Keys → +**, access **Admin**. Admin access is needed so the build machine can create the
signing certificate and profiles for you. Download the `.p8` file (it can only be downloaded once)
and note the **Key ID** and the **Issuer ID** shown above the list.

### 4. Add GitHub secrets (repo **Settings → Secrets and variables → Actions → New repository secret**)
| Secret | Value |
|---|---|
| `APP_STORE_CONNECT_KEY` | the full contents of the `.p8` file, including the `-----BEGIN PRIVATE KEY-----` lines |
| `APP_STORE_CONNECT_KEY_ID` | Key ID, e.g. `ABC123DEFG` |
| `APP_STORE_CONNECT_ISSUER_ID` | Issuer ID (a UUID) |
| `APPLE_TEAM_ID` | your Team ID, at [developer.apple.com/account](https://developer.apple.com/account) → Membership details |

### 5. Build
Make sure Actions are enabled for the repository (forks start with them off: **Actions** tab → *enable*).
Then any push that changes `ExpenseTracker/` or `ExpenseTrackerApp/` builds and uploads a new version.
You can also rerun the latest run from the **Actions** tab (*Expenses iOS app (TestFlight)* → *Re-run jobs*).
Once this workflow is on the default branch, you can also start it from the **Run workflow** button.

### 6. Install
After Apple processes the build (5–30 minutes), open App Store Connect → your app → **TestFlight**.
Add yourself under **Internal Testing** (create a group and add your Apple ID), then install the
**TestFlight** app on your iPhone and tap **Install**.

## Using the Share Extension
In Messages, select the SMS text (or long-press → *Copy* and paste anywhere) → **Share** → **Kharcha**.
If you don't see it, scroll the app row to the end → **More** → turn on *Kharcha*.
Open Expenses afterwards: the shared messages appear in the review screen.

## Bank SMS reach the app automatically (Shortcuts automation)
The app adds a Shortcuts action, **Add Bank Message**, that saves a message in the background.
1. Open **Shortcuts → Automation → + (New Automation) → Message**.
2. **Message Contains:** `Rs`. Leave *Sender* empty to catch all banks, or choose your bank's sender.
   Choose **Run Immediately**, turn off *Notify When Run*, then tap **Next**.
3. **New Blank Automation → Add Action**, search **Add Bank Message** (Kharcha) and add it.
4. Tap the **Message** field, choose **Shortcut Input**, then tap it again and pick **Content**
   (so the message text, not the whole message object, is passed). Tap **Done**.
5. Optional: repeat with **Message Contains** `INR` if your bank writes amounts that way.

Every matching SMS is now saved silently. Open Kharcha and the transactions are waiting for review.
To skip the review step, turn on **Settings → Add messages from Shortcuts and Share automatically**.
OTPs and other non-transaction messages are ignored, and duplicates are skipped.

## Moving your data from the home-screen web app
In the web app: **Settings → Back up (JSON)**. In the iOS app: **Settings → Restore from backup** and pick that file.

## Building locally (on a Mac)
```sh
brew install xcodegen
cd ExpenseTrackerApp
./scripts/sync-web.sh
BUNDLE_ID=com.drnitinsewani.expenses TEAM_ID=YOURTEAMID xcodegen generate
open Expenses.xcodeproj
```
Re-run `./scripts/sync-web.sh` after changing the web app.
