# Stack and lock design review, round 1

Commit seen: 107a0c6, the head of PR 11 (the stack-and-lock pull request). Screens: the board and inspector for stack, lock and resize, on a dry-run server, headless Chromium, at 1440 and 1024, light and dark. Reviewer: design reviewer on Opus. Clashes with the design records: not checked here.

## Pass or fail by state

| State | 1440 light | 1440 dark | 1024 light | 1024 dark |
|---|---|---|---|---|
| Over a Taken Cell | PASS | PASS | FAIL | FAIL |
| Over a Locked Tile | FAIL | FAIL | FAIL | FAIL |
| Over a Spanned Block | PASS | PASS | PASS | PASS |
| Stacked Tile With +N | FAIL | FAIL | FAIL | FAIL |
| Inspector With Behind This Window | FAIL | FAIL | PASS | PASS |
| Resize Mid-Drag | PASS | PASS | PASS | PASS |
| Board at Rest With Padlocks | PASS | PASS | PASS | PASS |

## Findings

| # | Severity | Finding |
|---|---|---|
| 1 | Medium | The stack edge does not match design pick 9 (stack edge). The front tile loses its top and right border, and the back window shows no edge. It is near invisible at 1024 and gone in forced colors. |
| 2 | Medium | Labels clip at 1024×768, where cells are 57px. The design notes assumed 78px cells. Clipped labels: "Behinc", "Behin", "Loc". At 1024×900, "Put Behind" clips by 1px (Low). |
| 3 | Low | The locked chip read "Locked, so it stays". Design pick 6 (drag over a locked tile) says "Locked, so no Swap". Fixed in commit 039e85c. |
| 4 | Medium | At 1024×768, Stay Put on a selected stacked tile (design pick 8, stack badge) moves up 24px and wraps to two lines. The tile edge clips it, and it covers the app tag and padlock. |
| 5 | Medium | At 1440×900, Behind This Window starts below the inspector's scroll area. Design pick 10 says the list shows with no scroll at 1440. Proposed fix: scroll the inspector to the Window section when a stacked tile is selected. |
| 6 | Low | Stay Put stays enabled on a locked tile and only posts a status line. This goes against rule `ux-control-earns-place` (a control must earn its place). |
| 7 | Note | The hint wraps to two lines at 1440. The mockup shows one line. |

Row 3 is fixed in commit 039e85c. Status of rows 1, 2 and 4 to 7 at 039e85c: unknown, not re-reviewed.
