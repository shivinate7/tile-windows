# Bay and zones design review, round 2

Commit seen: 64e73fb. Screens in shotsE (main, list full, zone, zone draw, list drag-over, swap drag-over). No clashes with the design records; all FIX.

| # | By | Finding |
|---|---|---|
| 1 | A, B | "N more below" hint painted over the last clipped row; list cuts mid-row; at 1024 only about 2 rows show |
| 2 | A, B | List titles truncated with no way to read the full title |
| 3 | B | Swap drag: large ghost covers the target and neighbours; target outline thin; "Swap with" pill half-covers a tag; displaced window's destination not shown |
| 4 | B | List drag-over: ghost covers chips; no insertion position shown |
| 5 | A | List drag-over thickens the border and shifts rows by 1px; summary text swaps |
| 6 | A, B | "No free cell" pill states a problem with no next step; jargon; style differs from "Minimized" |
| 7 | B | Moving a window out is only explained in text; list below the fold at 1440; no idle drop affordance or "Stay Put" action on a selected tile |
| 8 | B | Draw Zone button sits below the fold in the inspector; draw preview does not show what the zone will take |
| 9 | B | Finished zone shows no edit or remove affordance on the board |
| 10 | A | Dark: an emptied cell is nearly the board colour |
| 11 | A | "Claude · 3 of 4" unexplained; zone help clipped in the inspector; draw cancel not evident |
| 12 | B | Three stacked strips (hint, Keyboard, warning) between board and list |
