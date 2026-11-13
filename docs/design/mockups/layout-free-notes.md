# Split Cell and Free Layout: design notes

Mockup: `layout-free.html`, beside this file. Owner asks of 2026-11-13 09:22 CST.
Deep links: `#s=<state>`, plus `w=1024`, `t=light|dark` and `hide=<option,...>`. With no `t`,
the page follows the system theme. `#s=all` shows every state.
States: `split-pick`, `split-cell`, `split-finer`, `edges-on`, `edges-drag`, `edges-gap`,
`edges-back`, `tree-on`, `tree-drag`, `tree-gap`, `rects-on`, `rects-drag`, `rects-gap`.
Option keys for `hide`: `cell`, `finer`, `edges`, `tree`, `rects`. Each option has a switch on
the page that hides it.

Sizes: 1440 and 1024, the brief's sizes. `layout.py devices` gives no device list for this repo.
Scales are the board-feedback mockup's (0.1323 at 1440, 0.0755 at 1024). Tokens and tile CSS are
copied from `app.html` on main (378d26a). No web fonts, so the page opens with no network. The
`--ann-*` tokens are for the mockup's labels only.

Focus ids for the waiting page, one per state: `split-pick-popover`, `split-cell-result`,
`split-finer-result`, `edges-on-seams`, `edges-drag-seam`, `edges-gap-empty`,
`edges-back-popover`, `tree-on-splitters`, `tree-drag-splitter`, `tree-gap-result`,
`rects-on-handles`, `rects-drag-overlap`, `rects-gap-band`.

Each frame with a new scene shape shows "Saves in the scene as" under it.

## Today's model

- A cell is a uniform slot. `tile.ps1` `Pass` sets `$w = [int]($area.W / $Cols)` and
  `$h = [int]($area.H / $Rows)`. `Put` takes a window's rect as the box around its slot indices.
  Windows meet with no space between them.
- Pins, zones and the held layout (`fill.held`) all store `slots`. The engine knows no sub-cell
  and no uneven line.
- The fill puts one window in each open slot, row by row (`Pass`, `$open = 0..($Cols*$Rows-1)`).
- The engine can already move windows to screen rects: `-Place` takes `[{app,title,x,y,w,h,id}]`.
  A scene that the tray or a trigger replays goes through `-Scene` only.
- The inspector's Columns stepper stops at 8 (`app.html` `renderInsp()`,
  `stepper("columns",g.c,…,1,8)`).
- Resize snaps a span to whole cells, and covered windows move to free cells
  (decision `stack-and-lock`). A locked tile never moves.
- Built-in scenes keep their layout: Save is off with "Built-in scenes keep their layout. Use
  Save As New to change it." (`renderInsp()`). The owner's board is Default, a built-in scene, so
  every drawn edit shows Edited, Save off, and Save As New.
- `scenes.json` is `"version": 3`.
- Keys in use (`app.html` keydown): arrows, Shift+arrows, Ctrl+Shift+arrows, Enter, Space,
  Delete, Backspace, K, L, B, Esc. S, J and F are free.

## Split Cell

1. **Trigger.** Select a tile and press S, or press Split Cell in the inspector's Window
   section. A popover opens under the tile (`ux-answer-at-press`): Direction (Side by Side,
   Stacked), "Claude keeps" (Left or Right; Top or Bottom when stacked), and "Claude's share"
   (1/3, 1/2, 2/3; the bar between the halves reaches quarters, item 10). Three choices, not five: the critique counted five as too many for one popover row. The tile previews the split with a dashed line and a hatched empty
   half. Enter splits, Esc cancels. Gain: one key, one choice, seen before it acts. Loss: a
   popover over the board at 1024 covers the row under it. Pick: as drawn.
2. **Empty cell.** Selecting an empty cell is new. Today only windows select, and Draw Zone picks
   cells. A click on an empty cell selects it; the Window section becomes "Empty Space" with Split
   Cell. Both halves are then empty. Not drawn. Owner grant: yes.
3. **Model: Subdivide the Cell (pick).** The grid stays 5×2. Cell 2 becomes 2a and 2b. The scene
   saves `grids.wide.splits: [{slot, dir, at}]`, and a pin gains `part` (0 = left or top,
   1 = right or bottom). The engine change is small: `Put` cuts the cell rect by `at` when the
   pin has a `part`. Gain: nothing else on the board changes; zones, fill and held entries keep
   their slots. Loss: a second kind of slot address. Pick: this.
4. **Model: Finer Grid.** The grid doubles to 10×2 and every pin, zone and held entry gets
   doubled slots. Loss: the fill puts one window per slot, so every filled window becomes half
   as wide unless the fill learns a fill unit (`fill.unit: [2,1]`); the Columns stepper must pass
   8; the board shows 20 drop targets of about 53px at 1440 and 28px at 1024; a 1/3 share needs
   a 15×2 grid. Gain: one slot kind. Not picked.
5. **The window keeps its half by a pin.** Split pins the window to its half, as a drop on a cell
   pins it today (board hint "Drag a window to a cell to pin it"). Without the pin, the next fill
   could move it out. Departs from: a window the fill placed becomes pinned.
6. **The empty half fills last.** An open half joins the fill only after every whole cell is
   taken. So a split never reflows the board: the fill does not pull the window from cell 7 into
   2b. With every cell full, 2b stays empty, as the owner asked. With fill off, it stays empty.
   Option: a "Keep This Half Empty" switch on a selected half (`keep: "empty"`), so the fill
   never uses it. Not drawn. Owner grant: yes.
7. **A span.** On a 2×1 span, Side by Side at 1/2 is the same as today's resize to 1×1, so Split
   calls the resize edit (`resizeStep()`) for any share that lands on a cell line. It is one home,
   not a second. Another share cuts the cell that the line falls in. Stacked on a span cuts each
   cell under it at the same share.
8. **One level.** A half cannot be split again. Split Cell on a half is off with "This cell is
   split once already. Join the halves first." Gain: the slot address stays two parts. Loss: no
   quarter-cell in two steps (drag the bar to 1/4 instead). Pick: one level.
9. **Join.** J on a selected half, or Join Halves in the inspector, makes the cell whole. If both
   halves hold a window, the selected one keeps the cell and the other goes to a free cell in fill
   order, else to Windows That Stay Put, as resize does (decision `stack-and-lock`).
10. **Share after the split.** The bar between the halves drags to change the share; it snaps to
    quarters and thirds. Pick: as drawn.
11. **Cases.** A stacked tile: its back windows go with it into the kept half. A locked tile:
    Split Cell is off with "Locked. Unlock it first." (today's lock reason). A cell in a zone: both
    halves belong to the zone. A held cell with fill off (decision `fill-controls`): the held entry
    gains `part`.
12. **Small halves at 1024.** A half cell is about 27px wide at 1024. The tile shows its colour
    and the first letter of its app only. The inspector names the window. Not fixable inside the
    board's scale.
13. **Drop Note.** After the split, a note under the tile says "Split cell 2. Claude keeps the
    left half." with Undo, in the Drop Note look (decision `stack-and-lock`). The status bar keeps
    the same words.

## Free Layout

You said "trigger"; in this app, Triggers apply scenes on their own (Main Trigger, Extra
Triggers). So the control is a switch named **Free Layout**, in the inspector's Monitor section,
and the key F.

14. **Switch-on moves nothing.** In every option, switching on keeps each window's rect, on the
    board and on the screen. No Apply runs. The grid lines go, and the monitor label reads "Free
    Layout" in place of "5×2". A callout under the switch says "Free Layout is on. Nothing moved."
    The page draws cells and free rects with one function, so a rect at switch-on is the cell it
    was.
15. **Per monitor.** The switch is per monitor and per scene. On the laptop (1×1, one window) it
    is off with "One window fills this monitor. Split it first." On the portrait (1×2) it gives one
    line between Outlook and Teams.

### Option: Shared Edges (pick)

16. **How a drag works.** A grip sits on each line where windows meet. A line runs between two
    crossings where both sides have an edge, so every window that touches it lies inside its
    length. Dragging it moves those windows' edges together: one side grows, the other shrinks.
    Shift drags the whole line across rows. Gain: no gap opens at any point; one window pair
    changes, not a column. Loss: two windows that share no line cannot change size against each
    other in one drag.
17. **Gaps.** A drag cannot open a gap. A window that leaves (Keep Where It Is) leaves empty
    space, drawn as a dashed box. With Fill Empty Cells on, a new window fills it. Close Gap in the
    inspector grows the neighbour that shares the whole edge (left, above, right, below, in that
    order); with none, Close Gap is off and says why.
18. **Lock.** A line that touches a locked window is dotted, with no grip, and its tooltip says
    "Terminal is locked, so this line does not move." (decision `stack-and-lock`: a resize stops
    at a locked tile).
19. **Keys.** Shift+arrows move the selected window's right or bottom line by 1/48 of the monitor,
    Ctrl+Shift+arrows its left or top line. Width and Height in the inspector read in pixels.
20. **Size floor.** A drag stops when a window would be under 400 × 300 px. Unmeasured: many
    apps have their own minimum. Owner grant: yes.

### Option: Splitter Tree

21. The board becomes a tree of splits, as in a tiling window manager: three columns at the
    full-height lines, then rows, then columns. A drag on a splitter scales everything on both
    sides: the top-level drag in `tree-drag` changes five windows. A window that leaves gives its
    space to its sibling at once (`tree-gap`), so the tree holds no empty space unless a split adds
    it. Gain: never a gap, even on removal; it fits Split Cell. Loss: one window cannot change
    alone; a lock blocks every splitter above it (the right column's top splitter is dotted); a
    grid of 3 rows or more can hold a pinwheel of spans that no tree can cut, so switch-on would
    have to move windows there. Any spans on a 2-row grid cut into a tree. Not picked.

### Option: Free Rects

22. Today's eight handles move by the pixel. Windows may overlap or leave a gap during the drag;
    on release, the neighbour shrinks out of an overlap or grows into a gap. Gain: closest to "as
    I see fit"; a window can also move anywhere. Loss: a gap or an overlap shows during the drag,
    and the release guesses which neighbour changes. Not picked.

### The six tests

| Test | Shared Edges | Splitter Tree | Free Rects |
|---|---|---|---|
| Nothing moves at switch-on | Yes | Yes on 2 rows; no on a pinwheel | Yes |
| No gap during a drag | Yes | Yes | No |
| Resize per window, not per column | Per window pair | No: per branch | Yes |
| A lock stops it | The touching line only | Every splitter above it | On release only |
| Saves and replays through `-Scene` | Yes, areas | Yes, tree | Yes, areas |
| Back to the grid | Same flow | Same flow | Same flow |

23. **Pick: Shared Edges.** It is the only option that passes all six. The line the owner drags is
    the only thing that moves, and the gap is closed by the same move, which is the owner's "the
    gaps between items is immediately addressed". Splitter Tree fails per-window resize and makes
    a lock freeze half the board. Free Rects shows the gap it promises to close.

### Shared rules for every option

24. **Save.** `grids.wide` keeps `c` and `r` and gains `free: {areas: [...]}`. Each area has
    `rect: [x, y, w, h]` as fractions of the work area, and either `pin: <index>` (the scene's pin
    keeps its lock and back windows), or `app` and `title` (matched as the held layout matches,
    decision `fill-controls`), or nothing (empty space). The tree option saves `free: {tree}`
    instead. `scenes.json` goes to version 4. Free Rects saves the same areas as Shared Edges.
25. **Apply.** The engine computes each line's pixel position once per monitor and rounds it once,
    so two windows that share a line share the rounded pixel and no 1px gap opens. `Pass` gains a
    free branch. A one-off Apply could use `-Place` today, but a trigger replays the scene, so the
    branch is needed.
26. **Fill, zones and the list.** In Free Layout, every window keeps its area. Fill Empty Cells on:
    a new window takes the first empty area in reading order, else Windows That Stay Put. Fill off:
    as today, a new window waits in Windows That Stay Put. Zones pause, because their cells are
    gone; Draw Zone is off with "Zones pause in Free Layout. Turn it off to draw a zone." Departs
    from: zones run while fill is on (decision `fill-controls`). Owner grant: yes.
27. **Back to the grid.** Switching off opens a popover at the switch: Snap to Cells (each edge
    moves to the nearest cell line of `c`×`r`) or Restore the Grid Layout (the cells each window
    had at switch-on). The board previews the result, and the popover counts the windows that
    change size. Nothing moves until Back to Grid; Undo covers it. A window that would snap to
    zero width keeps one cell, and the neighbour gives it up. Pick: Snap to Cells as the default.
28. **Split in Free Layout.** Split Cell cuts the selected area. It adds a line, so the empty half
    is an area. One act, two homes in the save (slot `part` in the grid, `areas` in Free Layout).
    Considered and not drawn: Split always turns on Free Layout for the monitor, for one home.
    Not picked, because one split would pause zones and drop the grid for the whole monitor.
29. **Hatching.** The overlap, the gap and the split preview are hatched, each with a solid or
    dashed border so forced colours keep them. The critique's detector flags repeating-gradient
    stripes as decoration; here they carry meaning (space that will change), so they stay.

## Departs from today

- Split pins the window it splits (item 5).
- Selecting an empty cell (item 2).
- Zones pause in Free Layout (item 26).
- Windows meet at uneven lines; the engine places by fractions, not slots (items 24 and 25).
- `scenes.json` version 4.

## Input needed

- Owner grant: yes. Empty-cell selection (item 2).
- Owner grant: yes. Keep This Half Empty switch, or the empty half always fillable (item 6).
- Owner grant: yes. The size floor, 400 × 300 px (item 20).
- Owner grant: yes. Zones pause in Free Layout (item 26).
- Open: should Free Layout's line drag reach across monitors? Drawn as no.
- Open: at 1024, a half cell is 27px wide. Is the inspector enough there, or should the board
  zoom to one monitor while Split or Free Layout is in use?
