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
- `serve.ps1` keeps serving the live desktop when -From does not resolve, so a dry-run review can read live windows (design review stack-and-lock round 1).

## From PR 2 review round 3 (2026-10-22)

- `app.html` 321/526: a later toast clears `noteUp`, so a recovery note can return on every load until dismissed.
- `serve.ps1` 37: `Get-TileNote` reads `note.txt` with no lock; a dismiss racing a read can drop that one reply.
- `config.ps1` 34: the note file grows by one line per recovery until dismissed.
- `install.ps1` 37: a failed delete of `app.old-<pid>` is never cleaned up by later installs.
- Design round 3 rows 2 to 9 (`docs/design/reviews/app-round3.md`).

## From the triggers lane (2026-10-22)

- Untested: the Win32 signals (idle, mouse, foreground, lock and unlock, the end of a window drag) and the balloon click that arranges. Pure steps are tested; a tick with real signals was smoke-run with no apply.
- `tray.ps1` The offer is a balloon, not a button: a click on it arranges (for 3 min, or until another balloon shows). A click from Action Center is unchecked.
- `tray.ps1` The manual-move guard sees a user's drag or resize (the end of a move). A window moved by keyboard shortcut or snap assist may not register; the mouse-button guard still holds while a button is down.
- `tray.ps1` Focus in gaps has no hours: with a gap and a touched PC after the last meeting, Focus applies once that evening.
- `tray.ps1` Grid follows the Claude count applies only from the tray. The app's Apply and tile.ps1 use the saved grid.
- `tray.ps1` The activity map reads the foreground window every 3 s; a Chrome tab title that changes inside one dwell counts as the same activity.
- `scenes.json` Thursday Prep ships as a manual scene with Thursday 14:30 filled in; set "On a Schedule" on it to run it.
- `config.ps1` An older config.json gains the new starters once (the first read after the update). A scene deleted earlier stays deleted.
- `README.md` `agenda.json` lives in the app folder, so a reinstall removes it until the morning task writes it again.
- `tile.ps1` Zones fill after all pins, in monitor order (portrait, laptop, then ultrawide). A zone on an earlier monitor can take a window a later zone wants.
- `tile.ps1` A window that stays put is held by handle and app for the session. A saved scene holds it by app and exact title, so a window whose title changed rejoins the fill next session.
- `app.html` A swap writes two pins, so the swapped windows stop following their zone's fill order. The offline page has no bay or zones.

## From PR 6 review round 3 (2026-10-22)

- Debt: Draw Zone is hard to find. Add an armed state and a hint that names zones. (bay design round 3, row 1)
- Debt: one act has four names (pin, keep put, stay put, keep where it is). Pick one verb. (bay design round 3, row 2)
- Saving a scene drops Stay Put entries for windows that are closed at save time; when reopened, they rejoin the fill and an automatic apply can move them.
- After Save, a scene with Stay Put entries can still show as edited until refresh.
- Under 240px of board height the list flows below the board; dragging onto it then needs a scroll.
- Bay design round 3 rows 3 to 9.

## From triggers review round 3 (2026-10-22)

- `app.html` Choosing "On a Schedule" pushes the rows below down about 80px. Reviewer B rated it acceptable: the fields belong to that choice.
- `app.html` The folded Extra Triggers line and the rail say "3 on", "2 of 7 scenes" without naming them.
- `app.html` The "On" word shows beside some switches only, far from the toggle, and clips at 1024.
- `app.html` Rail chip names ("Return", "Gap") differ from the switch names.
- `app.html` The amber "triggers move windows" box is heavy and repeats on every scene.
- `app.html` Group labels look alike; the extras do not read as a separate zone.
- `app.html` At 1024 the sticky Save bar covers the last lines of the inspector.
- `tray.ps1` `Read-Num` lets the string "NaN" through; it then throws in `AddMinutes`. Hand edit only.
- `app.html` A saved value over its cap shows uncapped; the tray acts on the cap.
- `tray.ps1` A bad hand-edited value falls back to its default with no warning.
- `app.html` Unverified: focus restore may snap back to an edited field after Tab out.

## From design review stack-and-lock round 3 (2026-11-11)

- `app.html` At 1440 the drag ghost covers the locked drop's "Put Behind" (design review stack-and-lock round 3, finding 3).
- `app.html` At 1024 a resize destination chip clips "Chrome" to "Chrom" (design review stack-and-lock round 3, finding 4).
- `app.html` At 1024 the taken-swap destination chip text runs 7px past its box but stays readable (design review stack-and-lock round 3, finding 5).
- `app.html` A window resize during a drag leaves the dragged tile at its old size, off the board. Rare. Not checked against main (design review stack-and-lock round 3, finding 6).
- `app.html` On tiles under 84px the Stay Put icon is 18px, under the 24px touch size, and its arrow-into-tray glyph reads as a download (design review stack-and-lock round 3).
- `app.html` The pin mark is hidden on a narrow selected stacked tile (design review stack-and-lock round 3).
- `app.html` The +N badge loses its chip outline in forced colours (design review stack-and-lock round 3).

## From PR 13 code review round 3 (2026-11-11)

- `test/stack-lock.ps1` The flash-strip check reads `elementFromPoint`, so it pins the hit-test mechanism, not the geometry. A CSS-only fix could turn it red while the behaviour is right. A geometric overlap check would fix it. (code review round 3, PR 13, board-feedback)
- `app.html` `ctlUnderPeek` tests the button's own rect, not its 3px `::after` reach. During the 1.5s flash, the margin above the lock does not route the press. (code review round 3, PR 13, board-feedback)
- `test/run.ps1` lines 57-60 (`-Place -DryRun matches all windows`) read the live desktop twice. Any window that opens, closes or changes its title between the reads fails it. Seen once, 22 of 23. Promote it to a debt on a second sighting. (code review round 3, PR 13, board-feedback)

## From PR 13 design review round 2 (2026-11-11)

- `app.html` At 1024, on a selected narrow stacked tile, the badge (15.8px), Stay Put (14px) and the grip (14px) sit side by side, under the 24px target size (accessibility rule `ux-a11y-floor`). It is accepted, because the inspector has the same actions at full size (Keep Where It Is, Bring to Front, the Width and Height steppers). (PR 13 design review round 2)
- `app.html` At 1440 a selected stacked tile under 101px tall shows one title line ("Refactor…"), where the mockup shows two. The inspector shows the full title. (PR 13 design review round 2)
- `app.html` At 1024 the peek strip cuts a back app's name longer than about six letters ("Chro…"). (PR 13 design review round 2)
- `app.html` Already on main: at 1024, on a selected narrow tile that is not stacked, the Stay Put icon covers the title's second line. (PR 13 design review round 2)
- `app.html` The strip and the Named Badge both name the back app at 1440, against the one-label rule (`ux-label-once`). The owner ruled both in at 16:31 CST. An open option is to show only "+N" on the badge while the strip is visible. (PR 13 design review round 2)

## From PR 14 code review round 2 (2026-11-12)

- `app.html` (~1441-1445) Off then On within an in-flight preview runs On first, so the final state ignores the last click. A hung or failed preview leaves the switch inert or pinning from a stale answer. (code review round 2, PR 14, fill-keep)

## From PR 14 hold review (2026-11-12)

- `app.html` `newestPrev`: a failed board preview can leave stale previews, and the next fill-off may read them. (hold review, PR 14)
- `app.html` At 1024, an old resize grip can cover a tile title's second line. (hold review, PR 14)
- Test sweep: a stale test run folder in `%TEMP%` stops the sweep. Pointing TEMP at a fresh folder works around it. (hold review, PR 14)
- Open owner question: a held window of an app with several open windows whose title changed finds no match, as a pin would not. (hold review, PR 14)
- sameWin compares by id alone when a Windows That Stay Put entry has one; if that window closes and a same-app, same-title window opens, pinning the new one no longer clears the stale entry (app.html sameWin).
- Held entries with no id (a reloaded saved scene) that share a title all resolve to the first window with that title; pinning it drops every such hold (app.html heldWin, heldOff).
- The longer fill-off hint wraps at 1440 and 1024, and "Windows That Stay Put" breaks across two lines.

## From PR 16 reviews (2026-11-12)

- `config.ps1` (`Get-TileConfigText`) A first-run config.json gets a copy of appNames that nothing reads. Edit the map in `scenes.json`.
- No test covers the `/appnames` route or the board's fetch of it. If it breaks, the board silently shows raw process names.
- `tray.ps1` The TileShortcut `Add-Type` runs before the `-Lib` and mutex checks, so each Undo click's launcher compiles C# first. Cost unmeasured.
- `Invoke-RunUndo` checks `endedBy` before `done`, so a record both undone and ended says "this Undo has ended" instead of "Already undone."
- With no Start shortcut carrying the app ID, `Apply-Scene` returns before ending the older Undo record, so the older Undo stays clickable. The moved-since check keeps windows safe.
- Undo moves windows one `-Place` call at a time, a stopgap for a test fake. Once the fake is fixed, go back to one batched call.
- The board opened as a plain file (`file://`) cannot read `/appnames` and shows capitalised process names.
