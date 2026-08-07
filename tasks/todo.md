# Timeline missing block for running timer

Bug: a timer ran ~30 minutes with no block on the timeline; stopping and
restarting it made the whole session appear at once.

Cause: the open (in-progress) block only renders when the event log has an
open `start` event AND the locally synced entry is marked running. Any
divergence between those sources hides the whole session, while a `stop`
event always produces a visible closed block. The running entry's
`timer_started_at` from Harvest is authoritative but unused.

## Plan
- [x] Reproduce the builder behavior against the real event log
- [x] Render the running entry's block from the entry itself, with
      `timer_started_at` as fallback when the event log lacks an open start
- [x] Skip appending exact-duplicate timer events (app relaunch writes a
      second identical start via recordExternalTimerChange)
- [x] Roll `selectedDay` forward at midnight when it was pointing at "today"
- [x] Update and extend tests, run the suite

## Review
- `TimelineBuilder.blocks` now takes `running: [RunningTimer]`
  (entryId, projectId, startedAt) instead of `runningEntryIds: Set<Int64>`.
  A running entry always yields a block: event-log open start when present,
  otherwise `timer_started_at`. Dangling open starts for non-running entries
  are still dropped.
- `EventLog.append` ignores events identical to one already logged.
- `AppState` tick task advances `selectedDay` across midnight so a
  long-running menu bar app doesn't keep showing yesterday.
- All tests pass (see summary).
