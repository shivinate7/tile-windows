# Notes

Low findings. Each becomes a debt only after a real incident.

- `app.html` The "moves are off while Apply runs" part of the busy check cannot go red alone: the key handler and `edit()` both stop it.
- `app.html` `/scene`, `/apply` and `/preview` fetches have no timeout. A hung server keeps the page busy; Stop server still works.
- `app.html` A pin made by dragging matches the window's full title when its app has several windows. A title that changes (a browser tab) stops matching; the inspector's "Title contains" field widens it.
- `app.html` Loads Sora, DM Mono and Bricolage Grotesque from Google Fonts. Offline it falls back to Segoe UI.
- `tile.ps1` A scene reads the windows once, so a live run picks pins by pre-move positions. main's `-Default` re-read them per pass. Dry runs are the same (checked).
- `tile.ps1` With fewer than three monitors, each role takes its own screen (widest first) and a missing role is skipped with a warning. main's `-Default` stopped at a missing portrait. Not covered by a fixture.
- `serve.ps1` Port probe then rebind can race another process; `Start()` then throws a clear error.
- Untested: Apply moving a real window; the tray icon and its menu; a schedule or monitor change firing end to end; `irm | iex` from GitHub (the piped path is tested from a local source).
- `tray.ps1` Teams call detection reads the microphone privacy store (`LastUsedTimeStop` = 0 for a Teams exe or the MSTeams package). Misses: microphone access off for desktop apps, a call joined muted from the start in some builds, Teams in a browser. The window-title fallback runs only when the store cannot be read, and matches only `Meeting with … | Microsoft Teams` or `Call | Microsoft Teams`: it misses other call window titles and any non-English Teams. A start or end needs two readings 3 s apart, so a scene lags a call by up to 6 s.
- `config.ps1` Writers share one named mutex per home with a 10 s wait. A writer that waits longer goes ahead without it.
- `tray.ps1` The installer asks a running tray to quit and waits 5 s. A tray stuck longer is not stopped, and its old files are replaced under it.
- `config.ps1` The unique temp name cannot go red alone: the write lock already keeps two writers apart. It guards a writer that skips the lock.
- `config.ps1` The re-check under the lock before a file moves to `.bad` guards a race between two readers. No test can time that race, so it has no red proof.
- `install.ps1` `TILE_TEST_SWAP_FAIL` is a test seam: it throws between the two renames of the swap, so the rollback can be tested.

## From PR 2 review round 3 (2026-10-22)

- Debt: "Stop Server" in the app footer stops with no ask. Add an ask that names the act. (design round 3, row 1)
- `app.html` 321/526: a later toast clears `noteUp`, so a recovery note can return on every load until dismissed.
- `serve.ps1` 37: `Get-TileNote` reads `note.txt` with no lock; a dismiss racing a read can drop that one reply.
- `config.ps1` 34: the note file grows by one line per recovery until dismissed.
- `install.ps1` 37: a failed delete of `app.old-<pid>` is never cleaned up by later installs.
- Design round 3 rows 2 to 9 (`design/reviews/app-round3.md`).
