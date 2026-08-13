# Agent Instructions

- Do not create todo or plan files (e.g. `tasks/todo.md`). Track work in the conversation instead.
- Run tests with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`. The
  `swift` on `PATH` is Command Line Tools, which has no `Testing` module.

## Commands

```sh
swift build                                      # debug build
DEVELOPER_DIR=… swift test                       # whole suite (see above)
DEVELOPER_DIR=… swift test --filter AppState     # one suite, by its @Test name
Scripts/build-app.sh                             # release build + signed .app in dist/
Scripts/create-signing-cert.sh                   # once per machine; see README
```

There is no linter. The app is a menu bar agent (`LSUIElement`), so running it means
building the bundle and `open dist/HarvestButGood.app` — `swift run` gives you no UI worth
looking at.

## Layout

Three targets in one SwiftPM package (`Package.swift`, Swift 5 language mode):

- `HarvestTimerCore` — everything: models, API, storage, and the SwiftUI views under `Views/`.
- `HarvestTimer` — the executable. `HarvestTimerApp.swift` is an `AppDelegate` that builds the
  status item and window by hand, not a SwiftUI `App`. It owns the one `AppState`.
- `HarvestTimerCoreTests` — swift-testing, not XCTest.

Views are small and stay in `Views/`.

## Architecture

**`AppState`** (`@MainActor @Observable`) is the single store. Views read it from the
environment and call its methods; nothing else touches Harvest or the disk. It has two
inits: the production one reads the Keychain and builds a real `HarvestAPI`, the test one
takes a `HarvestClient` and a storage directory and leaves the Keychain alone. Neither
starts the timers — `start()` does, and tests drive `sync()`/`afkTick()` themselves.

**`HarvestClient`** is the protocol covering every call the app makes. `HarvestAPI`
implements it against api.harvestapp.com; tests use `FakeHarvest` (in-memory, mimics
Harvest's rule that starting a timer stops the running one) or `StubHarvestServer` (a
`URLProtocol` so real requests go through URL loading and headers/query/body are the ones
that would hit the wire).

**`EventLog`** is the point of the app. Harvest's API stores a day's *total*, not a
history, so start/stop timestamps exist only here — append-only JSON lines, one file per
day, under `~/Library/Application Support/HarvestTimer/` (alongside `FavoritesStore`).
`TimelineBuilder` turns those events into the timeline blocks the day view draws. Entries
started elsewhere (web, phone) have no local events, so they show in the list but draw no
blocks; `AppState.recordExternalTimerChange` writes events when a sync reveals a change
made off-app.

**`Day`** wraps Harvest's `yyyy-MM-dd` with a fixed POSIX/Gregorian formatter. Prefer it
over `Date` or bare strings for anything a day is booked against. **`EntryBook`** owns
entries filed by day and how a lookup or update lands.

Credentials (token + numeric account id) live in the macOS Keychain via `Keychain.shared`.

Small decision-only pieces are split out so they can be tested without a UI or a network:
`TimeMove`, `AFKDetector`, `ProjectSearch`, `DayScale`, `WeekCalendar`, `Formatting`,
`NotesField`.

Use Object-Oriented principles rather than creating God-classes.

## Tests

One `@Test("Name")` function per area, with cases inside it via the `test("case") { }`
helper in `TestHarness.swift`, and assertions via `expect(_:_:)` rather than `#expect`
directly — failures then name the case they came from and point at the calling line. Hang
timestamps off the shared `base` date; use `day("2025-08-06")` for fixed dates. `#expect`
carries on after a failure, so the rest of a suite still reports.

## Comments
Comments explain *why* a thing is the way it is, not what the code does; Limit to 80 characters unless there's a really good justification.
