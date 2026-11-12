# Undo from a run's notification

Kind: build
Plan: docs/design/mockups/run-undo-notes.md#notification (windows)

**Question.** When a scheduled or triggered run moves windows, should its notification offer Undo, and how?

**Ruling (owner, 2026-11-12 15:06 CST).** Yes. A run that moves windows shows a modern Windows notification with an Undo button, in place of the tray balloon. The button runs a per-user `tilewindows://undo` link, which tells the tray to put the windows back. The notification stays in the notification centre.

**Date.** 2026-11-12

**Why.** The owner wants to reverse an unwanted run from the notification itself. A tray balloon cannot hold a button.

**Open.** What Undo restores, how long it is offered, and what a stale Undo does: set by the design notes (run-undo) and the build.

**Check.** None yet. The run-undo lane adds one.
