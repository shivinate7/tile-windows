# The gap run's live move runs in no test

Decision: layout free (`layout-free`). Found in tile.ps1 at commit e0e3be2 (PR 54, the gap-fill run). Recorded 2026-11-19 11:38 CST. Line numbers are at e0e3be2.

The live branch of the gap run is `if ($GapFill)` (tile.ps1:860). Without `-DryRun`, it calls `Move-Win` for each window it moves (tile.ps1:875). No test reaches that call. The real engine runs with `-GapFill` in these tests only as follows:
- with `-From`, which is always a dry run (test/engine-layouts.ps1:874, :944, :971);
- with `-DryRun` (test/safe-moves.ps1:270);
- refused by the live-move guard (test/safe-moves.ps1:265, :267, :269; test/triggers.ps1:535-537).

No test sets TILE_TEST_ALLOW_LIVE=1 on a live `-GapFill` run. The `-Lib` seam cannot reach the branch. Tests swap `Move-Win` for a fake through `-Lib` (tile.ps1:28), but `-Lib` returns at tile.ps1:377, above the gap block.

The tray runs this branch for real. `Invoke-GapFill` passes `-DryRun` to tile.ps1 only under `-NoApply` (tray.ps1:661). The tray writes no run-undo record for a gap run (tray.ps1:655).

Harm: a defect in the live move ships unseen.

Likelihood: unmeasured. A gap run acts only on a monitor whose grid has free areas (tray.ps1:447). `app.html` has no Free Layout, and no starter scene holds a free area. Today only a hand-edited scene can reach the branch.

Recovery: none in the code. The tray writes no run-undo record for a gap run (tray.ps1:655).

Fix: add a case that runs the live branch with `Move-Win` replaced by a fake, and checks the handles and rects it is called with. The `-Lib` return sits above the branch, so the case needs the branch above tile.ps1:377 or another seam. Write the case red first.
