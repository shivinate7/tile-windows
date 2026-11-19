# Item G has no test for a floor-driven fall-through, or for left-right before above-below

Decision: layout free (`layout-free`). Recorded 2026-11-19 13:12 CST. Line numbers are at b1735e7.

PR 56 (item G midpoint fall-through, merged at 4191c69) made a midpoint pair that fails the floor or the overlap check hand over to the next pair. Left and right are tried first. The rule is in the tile.ps1 comment (:241-243). The pair loop is at :315, and the check and revert at :323.

Two gaps:

- Floor reason. The only item G floor case is G5 (test/engine-layouts.ps1:768-769). It has no above-below pair, so it tests the single-side fallback, not a hand-over to above-below. The ten-area case at test/engine-layouts.ps1:1010-1011 has no above-below pair either. A floor-driven fall-through is untested. The floor check itself is in free-area-floor-whole-rect.
- Order. No case has both pairs pass. G1 (test/engine-layouts.ps1:752) and G5 have no above-below pair. G8 (:776) has no left-right pair. G13 (:849) has a left-right pair that passes and an above-below pair that fails. G11 and G12 (:839, :843) are the reverse: left-right fails and above-below passes. So no test pins left-right before above-below when both midpoints pass.

The fall-through cases (G11, G12, G13, and the case at :827) cover only the overlap reason.

Checked by reading the code, not by a run.
