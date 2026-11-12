# Run Undo: design notes

Mockup: `run-undo.html`, beside this file. Task: owner, 2026-11-12 14:30 CST. Coordinator pick,
14:59 CST: a modern Windows toast with an Undo action, launched through a per-user
`tilewindows://undo` protocol, in place of the tray balloon for runs that moved windows.

Deep links: `#s=<state>`, plus `t=light|dark` and `hide=<option,...>`; `labels=0` hides the
Today and New labels. With no `t`, the page follows the system theme. `#s=all` shows every state.
States: `today`, `run`, `run-open`, `kinds`, `undone-quiet`, `undone-popup`, `undone-remove`,
`partial-skip`, `partial-refuse`, `stale-later`, `stale-gone`, `later-notimer`, `later-cap`.
Option keys for `hide`: `quiet`, `popup`, `remove`, `skip`, `refuse`, `notimer`, `cap`, `grid`,
`menu`, `openbtn`. Each option has a switch on the page that hides it.

Size: `layout.py devices` gives no device list for this repo, so the toast is drawn at 100 %
display scale. Windows sets the size: a 364 px wide pop-up and a 380 px notification centre.
Windows owns the toast's colours, frame, corners and shadow, and it follows the Windows light or
dark theme. The app sets only the text, the buttons, the launch target and the app name and icon in
the header. The `--win-*` values approximate Windows 11; the page shell uses the tokens from
`app.html`.

Focus ids for the waiting page: `today-balloon`, `run-toast`, `open-btn`, `kind-grid`,
`kind-menu`, `undone-quiet`, `undone-popup`, `undone-remove`, `partial-skip`, `partial-refuse`,
`stale-later`, `stale-gone`, `later-notimer`, `later-cap`.

## What a run is, and what Undo restores

A run is one call of `Apply-Scene` (tray.ps1) from a trigger: `Step-Tray` returns the scene, the
`why` string and the kind. `tile.ps1 -Scene` returns `placed`: per window, the rect it moved to
and the rect it came `from`. `Add-TileLog` (config.ps1) then writes the scene as `active` in
state.json.

Undo restores two things:
- **Window places.** Each window with `note = moved` goes back to its `from` rect. A window that
  was minimised before the run is skipped, since it has no rect to go back to. This is the same
  filter as `app.html` `applyScene` (`p.from.x > -20000`).
- **The scene on screen.** `active` goes back to the scene before the run. Without this, Place
  New Windows or Put This Scene Back When I Return would re-apply the undone scene.

Undo reuses the board's restore path (decision `undo-moves-windows`, Undo moves the real windows
back): `tile.ps1 -Place` with the `from` rects, as `placeBack` in `app.html` sends to `/apply`.
It is not a second copy of the restore.

## Choices

1. **A toast per run that moved a window, in place of the balloon.** Title: "<Scene> applied".
   Body: the run's `why` string with its first letter in capitals, then "Moved N windows." with
   a true plural. One button, Undo. A click on the body opens Tile Windows (`Open-App`).
   Today: `Note` shows "<Scene> applied <why>. Moved N window(s)." as a balloon with no button.
   Gain: the reason and the count read at a glance, and Undo is one press away. Lose: nothing a
   reader sees today. Pick: yes. The why strings keep one home: `New-Cand` and its call sites.
   The log line in state.json stays as today.
2. **Runs that moved nothing, failures and the meeting offer keep the balloon.** A run with
   `n = 0`, a "failed" note, `$TileNote` and `Offer-Scene` are as today. Gain: the brief's scope;
   nothing to undo gets no Undo. Lose: two notice styles. Pick: yes. A later lane can turn the offer
   into a toast with an Arrange Windows button (not drawn).
3. **Every trigger kind gets the same toast** (`#s=kinds`): schedule, gap, meeting offer
   clicked, back at the desk (lock or idle), new window, activity, call start and end, monitors
   changed, external monitors gone. Pick: yes.
4. **Grid line** (option `grid`). When `Get-ClaudeMode` picked a grid, add a second body line:
   "Dense grid: 5 Claude windows." Gain: says why the layout looks denser. Lose: a longer toast.
   Pick: yes.
5. **Tray menu runs** (option `menu`). Apply Scene from the tray menu ("from the tray") is a hand
   apply, so it is outside the brief. It has no Undo anywhere today. Gain: the same Undo for every
   tray apply. Lose: a toast after a hand act. Pick: yes. `Owner grant: yes`.
6. **Open button** (option `openbtn`). A second button, Open Tile Windows. Gain: easy to find.
   Lose: it repeats the body click, and a narrow toast splits Undo's width. Pick: no.
7. **One toast at a time.** Every run toast has the same tag and group, so a new run replaces the
   old toast on screen and in the centre. Only the newest run can be undone. Gain: no stale Undo
   buttons pile up. Lose: the centre does not list earlier runs. The board's recent log still
   does. Pick: yes.
8. **After Undo, the answer shows in the same toast** (house rule `ux-answer-at-press`). The
   title becomes "<Scene> undone" and the body "Put back N windows.", the words of `placeBack`.
   - Quiet Update (option `quiet`): the toast updates with no pop-up and no sound; the windows
     moving back are the answer. A partial or failed Undo still pops up. Pick: yes.
   - Follow-Up Toast (option `popup`): the update pops up again. Gain: always confirms. Lose:
     noise after a plain success.
   - Remove the Toast (option `remove`): nothing is said. Lose: a partial result goes unsaid.
9. **A window you moved since the run.** "Moved since" means its rect is more than 4 px from the
   rect the run put it in.
   - Skip Moved Windows (option `skip`): put back the rest, and say "Put back 5 of 6 windows.
     You moved Outlook since, so it stays." Pick: yes. Your own move wins.
   - All or Nothing (option `refuse`): move nothing, and offer Undo Anyway. Gain: the old layout
     comes back whole or not at all. Lose: one more press in the common case.
   A window that has closed is skipped and counted the same way ("Outlook closed").
10. **A later run.** The tag in choice 7 replaces the old toast, so this shows only if you click an
    old toast in the short moment before it is replaced. The launch URI carries the run id
    (`tilewindows://undo?run=<id>`), and the agent compares it with the newest run. The toast says
    so and offers Undo <newer scene>. Pick: yes.
11. **The tray agent restarted or quit.** The agent keeps the undo record in memory only. At start
    and at Quit it removes its toasts from the centre, so no dead Undo is left. If a click still
    comes (a race), the toast says "Tile Windows restarted since, so it lost the old places." and
    offers Open Tile Windows (house rule `ux-no-dead-end`). Pick: yes.
12. **How long Undo is offered.** `Owner grant: yes`.
    - Until the Next Run (option `notimer`): until a later run replaces it, or the agent
      restarts or quits. No timer. Choice 9 protects windows you moved since. Pick: yes.
    - One-Hour Cap (option `cap`): the toast also expires one hour after the run
      (`ExpirationTime`) and leaves the centre. Gain: no Undo from long ago. Lose: a run while you
      were away for over an hour cannot be undone.
13. **Undo counts as your own move.** After Undo the agent sets the manual-move time
    (`[TileInput]::MoveEndTicks`), since a move made by code does not fire the move-end hook.
    Step-Tray then cancels waiting one-shots and holds runs for 10 s, so nothing redoes the run.
    Writing the previous scene as `active` already starts the 15 minute activity grace, through
    `manualApplyAt` in `Step-Tray`. Gain: Undo sticks. Lose: an Undo also cancels a run that was
    waiting for an unrelated reason. Pick: yes. `Owner grant: yes`, because it changes a guard's
    input.
14. **Do Not Disturb.** Windows holds the pop-up and puts the toast straight into the centre. Undo
    there works the same. Nothing to build.

## For the builder (outside the design folder)

- The toast header shows "Tile Windows" and its icon only if the app has an AppUserModelID. The
  Start menu shortcut that `install.ps1` writes must carry it. Without one, Windows names the
  process, likely Windows PowerShell. `uninstall.ps1` removes it.
- `install.ps1` registers `tilewindows://` under HKCU\Software\Classes; `uninstall.ps1` removes
  it. The handler starts PowerShell hidden and passes the URI to the running agent, as the Open
  event does today. On this machine a registry write from the Bash tool goes to the app package's
  private copy, so test the protocol from a real terminal.
- `Note` clears `$script:offer`. The toast path must clear it too, or a late click on the offer
  balloon arranges windows.
- The Today drawing of the balloon is not measured on this PC; its header text may differ.
