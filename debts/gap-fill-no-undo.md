# Gap fill moves windows with no notice and no Undo

Decision: undo from an automated act's notification (`run-undo`). Found at d15a42c. Recorded 2026-11-23 13:15 CST. Line numbers are at d15a42c.

When a tiled window on a Free Layout monitor closes or hides, `Step-GapFill` (tray.ps1:468) reads the gap watch's events, and `Invoke-GapFill` (tray.ps1:679) runs tile.ps1 -GapFill. That run moves the other windows into the gap. The code comment says it shows no toast and keeps no run record (tray.ps1:678), so Undo never offers it. Its only trace is one log line, "Gap-fill: N window(s) away. Moved M." (tray.ps1:687). The gap fill's moves are not in the last run's record, so Undo of that run does not put them back.

Harm: windows move with no notice, and the owner has no Undo for the move.

Likelihood: unmeasured. It runs whenever a tiled window goes away on a Free Layout monitor.

Recovery: none in the code. The owner moves the windows back by hand.

Fix: show a run toast with Undo for a gap fill that moved windows, and keep the moved windows' places in the run record. Write a red case first: a gap fill that moves one window, then check that a toast with Undo shows and that Undo puts the window back.
