# A neighbour that already overlaps gets no share

Decision: layout free (`layout-free`). Recorded 2026-11-18 16:29 CST. Line numbers are at 74f87cb.

`Test-NoOverlap` (tile.ps1:292-299) checks the neighbours after a share. It fails when a neighbour overlaps any other live area, whether the overlap was already there or the share made it. The share is then undone, and the next side is tried (:317, :325).

No test pins a gap that stays because every side would overlap. The one gap case, the pinwheel centre (test/engine-layouts.ps1:755-756), stays because no side qualifies. Every side's neighbour sticks out past the centre's edge.
