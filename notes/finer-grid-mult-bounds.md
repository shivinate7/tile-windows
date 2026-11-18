# Finer grid: mult has no upper bound

Decision: layout free (`layout-free`). Recorded 2026-11-18 13:07 CST.

`Get-CellPair` (on branch `finer-grid`, PR 46 (finer grid)) rejects only values below 1. It has no upper bound. Checked by reading `Pass`, not by a run.

- `mult` [16,1] on a 24-column grid at 1365 px: the base width is 57 and the sub-width rounds up to 4. Cell 15 ends at `EdgeX` 60 and cell 16 starts at 57, so cell 15 is -3 px wide.
- `mult` [1000,1]: the sub-width rounds to 0, so every cell has zero width.
- `mult` [1e9,1]: the column count is 2.4e10, which overflows Int32 and throws.
- A `mult` with `c` missing: the column count becomes 0, the engine sizes the grid itself, and a window lands past the area's right edge.

None of these is page input today. L2 should cap `mult`.
