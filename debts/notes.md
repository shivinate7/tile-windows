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
