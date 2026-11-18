# Free-area rects and pins can drop without a missing entry

Decision: layout free (`layout-free`). Recorded 2026-11-18 16:29 CST. Line numbers are at 74f87cb.

In `Resolve-FreeAreas` (tile.ps1:196), an area whose rect fails the checks at tile.ps1:201-204 leaves the area list with no entry in Missing. If that area had a pin, the pin is listed as "not in a free area" (:225).

A second area on a pin that is already taken (:217) stays in the fill as a free slot. Only its pin claim is dropped, and nothing goes to Missing.

A pin on another monitor, or a pin index outside the scene, is labelled "pin not in this scene" (:217-218).
