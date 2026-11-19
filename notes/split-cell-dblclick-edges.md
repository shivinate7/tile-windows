# Double-click split has four edge cases the code does not handle

Decision: layout free (`layout-free`). Recorded 2026-11-19 13:12 CST. Line numbers are at b1735e7.

A double-click splits the selected tile. The dblclick handler is at app.html:2138. A capture on each press saves the selection as it stood before that press (app.html:2137). The handler splits when the tile under the second click is the selection saved at the first press (selAtPress[0]).

The edge cases the code does not handle:

- A double-click that starts on one tile and ends on another splits the second tile, when the second tile was selected before the pair.
- A drag on the second press may still split. Neither the capture (:2137) nor the handler (:2138) checks movement.
- Ctrl or Shift held on the presses. Ctrl takes the pick path (app.html:2023) and Shift takes the zone path (app.html:2028). Each returns before the drag path starts. The handler (:2138) reads no modifier key, so a split can still follow.
- No touch or pen case. No code reads pointerType. The only trigger is the dblclick event.

The three double-click tests (test/setup-page.ps1:1956, :1980, :2002) cover a double-click on a selected tile, on an unselected tile, and on a selected locked tile. None covers the four cases above.

Checked by reading the code, not by a run.
