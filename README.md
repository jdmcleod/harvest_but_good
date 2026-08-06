# Harvest Timer

A native macOS menu bar replacement for the Harvest timer app, built for duration-based tracking. Every start and stop made through this app is logged locally with a timestamp and shown on a day timeline — the thing Harvest itself can't tell you.

## Requirements

- macOS 14+
- Swift toolchain (Command Line Tools are enough; Xcode not required)
- A Harvest Personal Access Token

## Build and install

```sh
Scripts/build-app.sh
cp -R dist/HarvestTimer.app /Applications/
open /Applications/HarvestTimer.app
```

The app lives in the menu bar (no Dock icon) and shows today's total hours next to a timer icon.

## Connect to Harvest

The app walks you through this on first launch:

1. It opens https://id.getharvest.com/developers for you. Sign in and click **Create new personal access token**; name it `HarvestTimer`.
2. Copy the token and the numeric **Account ID** shown in the *Choose Account* section on that page.
3. Paste both into the app and click **Validate**, then **Save & Start**.

Both values are stored in the macOS Keychain. Revoke the token anytime from the same Harvest page.

## How it works

- **Favorites** are cards; one click starts (or restarts) a timer for that project + task. Hover for the remove button, use **Add** to pick from your assigned projects.
- The **left pane** lists the selected day's entries with inline note editing, a start/stop button, and a count of how many times each entry was started from this app.
- The **right pane** is a 7 AM – 7 PM timeline. Blocks are start→stop intervals recorded by this app, color-coded by project. Timers started or stopped elsewhere (web, phone) appear in the entry list but produce no blocks — Harvest's API doesn't expose those timestamps.
- The app syncs with Harvest every 30 seconds.

Local data (favorites and the start/stop event log) lives in `~/Library/Application Support/HarvestTimer/`.

## Development

```sh
swift build                        # compile
swift run HarvestTimerTestRunner   # run the test suite
swift run HarvestTimer             # run the app without bundling
```

Tests use a plain assert-based runner because neither XCTest nor Swift Testing ships with the Command Line Tools.
