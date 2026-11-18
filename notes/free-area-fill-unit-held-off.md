# Free areas turn off fill unit and held entries

Decision: layout free (`layout-free`). Recorded 2026-11-18 16:29 CST. Line numbers are at 74f87cb.

Under free areas, `fill.unit` is off. `Unit` is set only when there are no free areas (tile.ps1:808). Held entries (`fill.held`) are dropped too: `$hs` is built only when there are no free areas (:799). The plan's L3 section (docs/plans/layout-free-build.md) says neither.

The plan's L3 section lists three arguments for `Get-CollapsedAreas`. The code takes a fourth, `$size`, for the 400 x 300 floor (tile.ps1:238).

Checked by reading the code, not by a run.
