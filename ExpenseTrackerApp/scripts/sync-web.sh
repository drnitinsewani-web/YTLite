#!/bin/sh
# Copy the web app into ExpenseTrackerApp/www so it is bundled inside the iOS app.
set -e
cd "$(dirname "$0")/.."
rm -rf www
mkdir -p www/vendor
cp ../ExpenseTracker/index.html ../ExpenseTracker/icon.svg ../ExpenseTracker/manifest.webmanifest www/
cp ../ExpenseTracker/vendor/xlsx.full.min.js www/vendor/
echo "web app copied to $(pwd)/www"
