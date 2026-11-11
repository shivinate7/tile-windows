# Stack and lock design review, round 2

Commit seen: 60febd5, the head of PR 11 (the stack-and-lock pull request). Render: partial, Edge CLI, with no drag driver, so the drag, inspector and resize states were not rendered. Reviewer: design reviewer on Opus. Clashes with the design records: F1 to F3 below.

## Pass or fail by state

| State | Result | Note |
|---|---|---|
| Board at rest | FAIL ×4 | F2 |
| Stacked tile at rest, +N and edge | PASS ×4 | |
| Drag | unknown | not rendered |
| Inspector | unknown | not rendered |
| Resize | unknown | not rendered |

The ×4 counts take round 1's four columns: 1440 and 1024, light and dark. Not confirmed in the review input.

## Findings

| # | Severity | Finding |
|---|---|---|
| F1 | Medium | At 1024 the Put Behind and Locked chips drop to icon only. The ruling says they read "Behind" and "Locked". |
| F2 | Low | The hint copy reads "keep put", against design pick 15 (board hint). |
| F3 | Medium | The nosp class (app.html:660) hides Stay Put on every selected tile under 66px, against design pick 8 (stack badge). The same class also hides it on a stacked tile under 80px tall. |

## Round 1 rows at 60febd5

| Round 1 row | Status |
|---|---|
| 1, stack edge | Closed in normal colours. Forced colours: unverified. |
| 2, labels clip at 1024×768 | Unverified. |
| 3, locked chip copy | Closed. |
| 4, Stay Put on a selected stacked tile at 1024×768 | Unverified. |
| 5, Behind This Window below the inspector's scroll area at 1440 | Unverified. |
| 6, Stay Put on a locked tile | Closed. |
| 7, hint wraps at 1440 | Closed. |
