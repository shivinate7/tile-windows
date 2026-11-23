# Undo from an automated act's notification

Kind: build
Plan: docs/design/mockups/run-undo-notes.md#notification (windows)

**Question.** When the app acts on its own and changes what the owner sees or has, should that act's notification offer Undo, and how? First asked for a scheduled or triggered scene run that moves windows. Widened 2026-11-23 to every automated act.

**Ruling (owner, 2026-11-23 13:07 CST).** The owner's words: "ensure for any automated process it's known in this repo that an undo toast/notif is also to be built". Every automated process the app adds that changes what the user sees or has (moves or resizes windows, changes a scene, config or saved layout) ships with a notification that offers Undo, built in the same change.

**Ruling (owner, 2026-11-12 15:06 CST), scene runs.** Yes. A run that moves windows shows a modern Windows notification with an Undo button, in place of the tray balloon. The button runs a per-user `tilewindows://undo` link, which tells the tray to put the windows back. The notification stays in the notification centre.

**Settled (coordinator, 2026-11-12 15:16 CST).** Undo restores the moved windows' places and the scene the run changed (not a scene it left as it was). Undo is offered until the next run or a tray restart, with no timer. Undo counts as the owner's own move. A tray-menu Apply Scene gets the same toast and Undo. No Apply Again. A stale Undo says so: a later run replaced it, or the tray restarted since.

**Coordinator picks (2026-11-12 16:07 CST).** App names come from the shared map (`scenes.json` appNames). The notification is a toast when the Start shortcut with the AppUserModelID exists, and each run repairs that id (PR 118). With no Start shortcut, it is the tray balloon. The 2026-11-23 ruling overrides the balloon part: a balloon run has no Undo (audit row 1, debt `balloon-fallback-no-undo`).

**Popup Undo (owner, 15:42 CST 2026-11-19, pick A).** A `tilewindows://` link the app cannot use shows a popup saying so, never a silent exit. The log shows every Undo, whatever its outcome.

**Cause.** Windows passes the toast link as `tilewindows://undo/?run=<id>` (slash before `?`), which the link pattern must accept.

**Check.** `test/run-undo.ps1` (the run toast, Undo's places and guards, the protocol keys); `test/run.ps1` runs it.

**Confirmed live (2026-11-20 10:31 CST).** The tray, installed at 10:08 CST from commit 62a2c63 through WMI with PR 60 (popup Undo link fix), applied a one-off Thursday Prep schedule. The coordinator set that schedule on the owner's ask. It moved 7 windows. The owner pressed the toast's Undo, and the log reads "Put back 6 of 7 windows" (Calendar, moved since, stayed). config.json was restored byte for byte after the test.

**Why.** The owner wants to reverse an unwanted run from the notification itself. A tray balloon cannot hold a button. The 2026-11-23 ruling asks the same of every automated act.

**Date.** 2026-11-12. Widened 2026-11-23.

**Audit (2026-11-23, main at d15a42c; rows 1 and 2 at 9b60ed8, PR 118).** Each act the app takes on its own, and whether it has an Undo notification. A debt is filed for each act that changes something and lacks one. Acts that change nothing, or that the owner must accept, get no debt.

| # | Act | Code | Changes | Undo notification | Debt |
|---|---|---|---|---|---|
| 1 | Scene applies: schedule, monitor change, call start and end, desk, window, activity, size, gaps, noext, grid, and the offer's click | `Apply-Scene` (tray.ps1), from the tray tick | windows, scene | Yes for the run toast. Each run repairs the Start shortcut's app id first (PR 118). No for the balloon: when no Start shortcut exists (the log says Undo is not offered), or when the toast throws (the log does not say so) | `balloon-fallback-no-undo` |
| 2 | Gap fill on a Free Layout monitor, when a tiled window goes away | `Step-GapFill`, `Invoke-GapFill` (tray.ps1) | windows | Yes when it moves windows (PR 118): a toast with Undo, and its moves join the current run's record or start their own. No for the balloon: when no Start shortcut exists or the toast throws (the log says Undo is not offered) | `balloon-fallback-no-undo` |
| 3 | Autosave on each board edit, no Save click | `layoutEdited`, `saveLayout` (app.html) | saved layout | Not needed: it saves the user's own edits, and the header Undo covers them | none |
| 4 | Setup added when the page reads the snapshot (load and Refresh) | `Add-SnapshotSetup` (serve.ps1), `Register-TileSetup` (config.ps1) | config: monitors, setups | No | `plug-in-adds-setup-no-undo` |
| 5 | Setup switch turned off on a config read | `Update-TileSetupSwitch` (config.ps1) | config: a scene's trigger | No: a note only | `setup-switch-off-no-undo` |
| 6 | Config that does not parse moved aside, starter scenes back | `Get-TileConfigText`, `Set-TileBad` (config.ps1) | config: scenes | No: a note only | `config-bad-file-no-undo` |
| 7 | Config upgrade adds starter scenes and fields | `Update-TileConfig` (config.ps1) | config: scenes | No: silent | `config-upgrade-no-undo` |
| 8 | Offer before a meeting | `Offer-Scene` (tray.ps1) | nothing until clicked | Not needed: moves nothing, and the owner accepts it by a click. The click is row 1 | none |
| 9 | Agenda reads (call, size, offer, gaps) | tray tick reads agenda.json | nothing | Not needed: reads only. Its applies are row 1 | none |
| 10 | Morning task writes agenda.json (the README prompt) | not app code | agenda.json only | Not needed: no window, scene, config or layout changes | none |
| 11 | Forget a setup, cascade that switches a trigger off | `Forget-Known` (serve.ps1) | config | Not needed: the owner's own act. Its note is shown | none |
| 12 | First run, no config.json | `Get-TileConfigText` | config: starter scenes | Not needed: nothing was there to put back | none |
| 13 | install.ps1 | install.ps1 | app folder, shortcuts, link | Not needed: run by hand. Nothing in the app runs it | none |

Row 3: autosave saves the user's own edits, and the header Undo covers them. Basis: item 8 of the monitor setups record (`monitor-setups`, owner 2026-11-17 11:38 CST): "Undo is the way back" (coordinator pick, 2026-11-23 13:19 CST, process-only).

**Open.**
- Built in PR 118: a run whose toast had fallen back to a balloon gets its Start shortcut's app id repaired, so its toast with Undo shows. A gap fill that moves windows gets a toast with Undo. Its moves join the current run's record, or start their own.
- Not built: a run or gap fill with no Start shortcut, or whose toast throws, still shows a balloon with no Undo (debt `balloon-fallback-no-undo`).
- Open owner review: the Tile Windows Choices page
