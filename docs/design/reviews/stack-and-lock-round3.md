# Stack and lock design review, round 3

Commit seen: 7050ab9, the head of the stack-and-lock branch when fetched. Render: all 32 driver shots. Reviewer: design reviewer on Opus. Clashes with the design records: not given in the review input.

## Pass or fail by state

| State | Result | Note |
|---|---|---|
| Board at rest, taken-behind and spanned | PASS everywhere | |
| Taken-swap | PASS everywhere | At 1024 the destination chip text runs 7px past its box (finding 5). |
| Locked | FAIL at 1440, PASS at 1024 | Finding 3. |
| Stacked with inspector | PASS at 1440, FAIL at 1024 | Finding 1. |
| Resize | FAIL everywhere | Finding 2. At 1024 also finding 4. |
| Stacked in forced colours | PASS at 1440, FAIL at 1024 | Finding 1. |
| Window resized mid-drag | FAIL | Finding 6. |

## Findings

| # | Severity | Finding |
|---|---|---|
| 1 | Medium, likely | On a narrow selected stacked tile, the Stay Put icon overlaps the lock by 6px, and the grip and badge by 1 to 2px. |
| 2 | Low, likely | The resize label reads "1 window move". |
| 3 | Low, likely | At 1440 the drag ghost covers the locked drop's "Put Behind". |
| 4 | Low | At 1024 a resize destination chip clips "Chrome" to "Chrom". |
| 5 | Low | At 1024 the taken-swap destination chip text runs 7px past its box, but stays readable. |
| 6 | Low, rare | A window resize during a drag leaves the dragged tile at its old size, off the board. Not checked against main. |

Findings 1 and 2 get a small fix after round 3. Findings 3 to 6 become notes in `debts/notes.md`.

## Notes, not numbered

- On tiles under 84px the Stay Put icon is 18px, under the 24px touch size. Its arrow-into-tray glyph reads as a download.
- The pin mark is hidden on a narrow selected stacked tile.
- The +N badge loses its chip outline in forced colours.

## Round 1 rows at 7050ab9

| Round 1 row | Status |
|---|---|
| 1, stack edge | Closed. |
| 2, labels clip at 1024×768 | Closed at 1024×768. 1024×900 unknown. |
| 3, locked chip copy | Closed. |
| 4, Stay Put on a selected stacked tile at 1024×768 | Open as finding 1. |
| 5, Behind This Window below the inspector's scroll area at 1440 | Closed. |
| 6, Stay Put on a locked tile | Closed. |
| 7, hint wraps at 1440 | Closed. |

## Round 2 rows at 7050ab9

| Round 2 finding | Status |
|---|---|
| F1, Put Behind and Locked chips drop to icon only at 1024 | Closed. |
| F2, the hint copy reads "keep put" | Closed. |
| F3, the nosp class hides Stay Put on selected tiles under 66px (app.html:660) | Closed for plain tiles. Open on stacked tiles as finding 1. |
