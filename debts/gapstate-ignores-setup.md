# New-GapState reads the wrong grid

Decision: layout free (`layout-free`). Found in tray.ps1 at commit ee47541 (PR 43, the gap-watch pull request). Recorded 2026-11-18 12:35 CST. Line numbers are at ee47541.

`New-GapState` (tray.ps1:473-477) builds one grid table per monitor. It reads the scene's own `grids`, then every `layouts` entry's grids. Where two sources give the same monitor, the later one wins (tray.ps1:475). It ignores the setup key and the grid mode the run used.

Harm: the L5a gap-fill run could gate on a grid the run did not use, so it would fill or skip a gap against the wrong grid.

Likelihood: unmeasured. It needs two `layouts` entries with a grid for the same monitor id.

Recovery: none in the code yet.

Fix in L5a: take the grid from the run's setup key and grid mode, not from a merge of every entry.
