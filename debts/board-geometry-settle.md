# Geometry cases read rects before the board settles

Decision: none. Found in test/setup-page.ps1 at 0e99075 (PR 58 and PR 60, one-off full-run failures; finding F11). Recorded 2026-11-19 22:34 CST. Line numbers are at 0e99075.

Tiles move with a 0.22 s transition (app.html:263). `Fl-Open` (test/setup-page.ps1:2262) returns once the page opens on Focus and Ultrawide is selected. It does not wait for the board to settle. `Fl-Still` (:2282) is the settle wait. Only five calls use it (:2388, :2398, :3160, :3188, :3218).

The geometry cases read their "before" rects right after `Fl-Open`, with no `Fl-Still`. They are drag-segment (case at :2454), drag-line with Shift (:2492), Go Around (:2525), drag-floor (:2557), and the cases for keys, the Shift+Right guard, split-area and err-save.

They failed as one-offs on full runs of PR 58 and PR 60. Two other cases failed the same way under load: stack-lock "no scene after 30 s", and "page preview == engine: thursday-prep".

Fix: wait for the board to settle inside `Fl-Open`, once, so each case that calls it gets the wait.

stack-lock SlLoad: app.html loadAll fetches once, so one failed fetch leaves no scene; fix page-side, never by retrying in the test.
