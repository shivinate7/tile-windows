# Undo from a run's notification

Kind: build
Plan: docs/design/mockups/run-undo-notes.md#notification (windows)

**Question.** When a scheduled or triggered run moves windows, should its notification offer Undo, and how?

**Ruling (owner, 2026-11-12 15:06 CST).** Yes. A run that moves windows shows a modern Windows notification with an Undo button, in place of the tray balloon. The button runs a per-user `tilewindows://undo` link, which tells the tray to put the windows back. The notification stays in the notification centre.

**Date.** 2026-11-12

**Why.** The owner wants to reverse an unwanted run from the notification itself. A tray balloon cannot hold a button.

**Open.** Settled by the coordinator, 2026-11-12 15:16 CST: Undo restores the moved windows' places and the scene the run changed (not a scene it left as it was). Undo is offered until the next run or a tray restart, with no timer. Undo counts as the owner's own move. A tray-menu Apply Scene gets the same toast and Undo. No Apply Again. A stale Undo says so: a later run replaced it, or the tray restarted since.

**Coordinator picks (2026-11-12 16:07 CST).** App names come from the shared map (`scenes.json` appNames). The notification is a toast only when the Start shortcut with the AppUserModelID exists; otherwise it is the tray balloon.

**Check.** `test/run-undo.ps1` (the run toast, Undo's places and guards, the protocol keys); `test/run.ps1` runs it.

Open owner review: the Tile Windows Choices page
