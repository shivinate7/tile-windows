# The 400 x 300 floor checks each neighbour's whole rect

Decision: layout free (`layout-free`). Recorded 2026-11-18 16:29 CST. Line numbers are at 74f87cb.

`Get-CollapsedAreas` (tile.ps1:238) runs the floor check after a midpoint share (`Test-Floor`, tile.ps1:289, called at :317). It checks each neighbour's whole rect after the share, not only the part the share adds. So any neighbour under 400 x 300 after the share blocks the midpoint, even one that was already small. The whole space then goes to a single side (:321-327), where the floor is not checked.

Checked by reading the code, not by a run. Test G5 (test/engine-layouts.ps1:758-759) pins one such case: the midpoint share would leave the left window 300 px wide, so the left side takes the whole space.

Decide with owner question M (key M, midpoint share, in docs/plans/layout-free-build.md) whether the midpoint should win in that case.
