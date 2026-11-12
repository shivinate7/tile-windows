# Bay columns: design notes

Mockup: `bay-columns.html`, beside this file. Owner request 2026-11-12 11:14 CST: the Windows That
Stay Put list uses three narrow category columns, leaves most of its width empty, and a long list
runs far down the page.

Deep links: `#s=today|flow|blocks|all`, plus `n=6` (default 23 windows), `list=fewer` (the
"Show N More" state), `w=1024` (default 1440), `t=light|dark` (default: the system theme),
`once=1` (item 4) and `hide=flow,blocks`. A single layout is drawn under Today, so the heights
read side by side. Each drawing prints its measured list height.
Focus ids for the waiting page: `bay-flow` (Flowing Columns), `bay-blocks` (Category Blocks),
`bay-today`.

Sizes: 1440 and 1024, the brief's sizes; `layout.py devices` gives no device list for this repo.
The list's inner width is taken from the `app.html` frame: 878px at 1440 (canvas column
1440 - 232 - 268, less padding) and 710px at 1024 (the `max-width:1180px` frame, 1024 - 252).
Tokens, chip and header CSS are copied from `app.html` (lines 13-23 and 278-297). No web fonts.
Sample windows are invented; the counts follow the screenshot: Code 10, Browse 2, Other 11.

## Today

`app.html` `renderBay()` writes one `.bgrp` per category into `.bgrps`, which is
`repeat(auto-fill,minmax(170px,1fr))` (line 287). Each category is one column, so three
categories use three tracks and the rest stay empty. The longest category sets the height.

## Measured list height (list body, light and dark are equal)

| Case | Today | Flowing Columns | Category Blocks |
|---|---|---|---|
| 1440, 23 windows | 536px | 335px | 494px |
| 1024, 23 windows | 536px | 413px | 542px |
| 1440, 6 windows | 157px | 161px | 163px |
| 1024, 6 windows | 157px | 161px | 163px |
| 23, Show N More | 110px | 114px | 116px |

Reader: the "List body height" line under each drawing (`getBoundingClientRect` of the list body),
read 2026-11-12 in the Browser pane, page served from a local static server. Fonts fall back to
Segoe UI, so the app's own figures will differ by a few pixels. The screenshot's list is about twice as wide as 1440's 878px;
there the gain grows (more columns), but that width is not drawn and not measured.

## Options

1. **Flowing Columns (pick).** One list in category order, packed down and then across into as
   many 170px columns as fit, at the shortest height that fits. A header keeps its first two
   windows with it, and a split never leaves one window alone in a column. A column that opens
   partway through a category starts with a 3px rule in the category colour, at a header's height,
   so chips line up across columns; the name is not repeated (`ux-label-once`). A header that
   starts below another category gets 8px more space above it. Each header shows its count.
   Gain: 37% shorter at 1440 and 23% at 1024 with 23 windows; the width fills; a shorter list
   gives the board more height, because `layout()` subtracts `bay.offsetHeight` when it sizes the
   board (lines 683-685). Lose: a category can share a column with the next, so categories are
   told apart by header, rule and chip edge, not by column; adding one window can move later
   chips to the next column; with 6 windows it is no shorter than today (161px against 157px).
2. **Category Blocks (alternative).** Each category takes one or more whole columns, at the
   fewest rows that fit, split evenly, with the same no-lone-window rule; its header, count and a
   2px colour rule span its columns, and blocks are 20px apart (columns 12px). Gain: each category
   stays one block, as today; a change in one category moves no other category's chips. Lose:
   little gain while categories are few: 8% shorter at 1440, and 1% taller at 1024, where three
   categories already fill three columns.
3. **Show N More.** Both layouts keep today's cap from `renderBay()`: two windows per category
   (one under 820px of window height), then the layout packs what shows. No change from main.
4. **Reason Said Once (off by default; `once=1`).** When more than half the windows share a
   reason, the note says it once ("Most are here because fill is off; the others say why.") and
   those chips drop their second line. Gain: with Flowing Columns, 271px at 1440 and 390px at
   1024. Lose: a chip no longer says its own reason; the reader has to read the note.
   Pick: leave it off; build it only on the owner's grant.
   Departs from: `renderBay()`, which puts the reason in each chip's `<small>`, and
   `board-feedback-notes.md` item 5, which shows "Fill is off" on every window. Owner grant: yes.

**Pick: Flowing Columns.** Gain: the largest cut in height at both brief sizes, and it uses the
empty width the owner pointed at. Lose: categories are columns no longer; header, colour rule and
chip edge carry them.
Departs from: main's `.bgrps` (one column per category, `app.html` line 287, and the `.bgrp` per
category in `renderBay()`). The bay still groups by category, as `decisions/bay-and-group-zones.md`
rules, so no ruling changes.

## Builder notes

5. `renderBay()` packs in script: measure each chip and header at the column width, find the
   shortest height that fits the column count, then write one `ul` per column. It re-packs on a
   width change (a `ResizeObserver` on `#bay`). The packing rules are in the mockup's
   `renderFlow()`.
6. A cheaper build is CSS columns (`columns:170px` on one list, `break-after:avoid` on headers,
   `break-inside:avoid` on chips). It gets close to the same height, but it cannot draw the
   continuation rule or keep two windows with a header. Builder's choice; the rule is the part
   that keeps a split category readable.
7. Drag and drop do not change: each chip keeps `data-bay`, and the drop slot stays in `.bfoot`.
