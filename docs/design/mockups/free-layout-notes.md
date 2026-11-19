# Free Layout on the board: design notes

Mockup: `free-layout.html`, beside this file. Lane L4 of Layout Free (decision `layout-free`; plan
`docs/plans/layout-free-build.md`, section L4). The rules of Free Layout are items 14-29 of
`layout-free-notes.md`; Shared Edges is ruled (item 23). This file holds only this mockup's own
choices, numbered F1 to F16, and cites those items. It sits beside `split-cell.html`: the same board,
windows, scales, tokens and mockup controls.

Owner rulings drawn: switch-on moves nothing (item 14); a plain drag moves the grabbed row's part of
a line, Shift moves the whole line (item 16; the coordinator's Shift pick, 2026-11-18 11:14 CST);
live gap-fill covers closed and minimized windows, and the neighbours grow into the space at once
(2026-11-18 11:08 CST).

Open owner picks, drawn at their defaults (the brief's S1, G1, K1, M1). No record lists numbered
options for them, so each is read as the plan's stated default:
- S1, shares: halves only. Split in Free Layout offers halves (state `split-area`).
- G1, gap-fill scope: Free Layout monitors only. Every gap state is on the Free Layout ultrawide.
- K1, fast split: the proposed Shift+S or double-click. Drawn dotted in the keyboard list.
- M1, midpoint share: when both opposite sides qualify, they meet in the middle (item G). The
  figures come from `Get-CollapsedAreas` in `tile.ps1` on main (74f87cb), run on this board's
  areas at 4096 × 1680 with Terminal locked.

Deep links: `#s=<state>`, plus `w=1024`, `t=light|dark` and `hide=<option,...>`. With no `t`, the
page follows the system theme. `#s=all` shows every state.

| State | Shows | Option key | Focus id |
|---|---|---|---|
| `free-on` | Switch on, nothing moves | shared | `free-on-seams` |
| `drag-segment` | Plain drag, one row | shared | `drag-segment-seam` |
| `drag-line` | Shift-drag, the whole line | shared | `drag-line-seam` |
| `drag-floor` | A drag stops at 400 × 300 px | shared | `drag-floor-seam` |
| `lock-around` | Shift-drag across a locked row: Go Around | `around` | `lock-around-seam` |
| `lock-refuse` | Shift-drag across a locked row: Refuse Shift | `refuse` | `lock-refuse-seam` |
| `keys` | Keyboard: Shift+arrows move a line | shared | `keys-seam` |
| `assign-drop` | Drop a window on an empty space | shared | `assign-drop-area` |
| `assign-fill` | A new window takes the first empty space | shared | `assign-fill-area` |
| `gap-lent` | A minimized window: Lent Space | `lent` | `gap-lent-area` |
| `gap-grown` | A minimized window: Grown Neighbours | `grown` | `gap-grown-area` |
| `gap-stays` | No neighbour can take the space | shared | `gap-stays-area` |
| `close-gap` | Close Gap on an empty space | shared | `close-gap-preview` |
| `split-area` | Split in Free Layout | shared | `split-area-menu` |
| `one-by-one` | The switch on a 1×1 monitor | shared | `one-by-one-switch` |
| `empty` | Every space empty | shared | `empty-board` |
| `back` | Back to the Grid popover | shared | `back-popover` |
| `err-save` | Error: the layout did not save | shared | `err-save-bar` |
| `err-apply` | Error: an app will not fit its space | shared | `err-apply-results` |

Sizes and themes: 1440 and 1024, light and dark, as the other mockups here. `layout.py devices`
returns `unknown` for this repo, so the sizes are the brief's. Scales are the board-feedback
mockup's (0.1323 at 1440, 0.0755 at 1024). Tokens and tile CSS are copied from `app.html` on main
(74f87cb; `:root` is unchanged since b6bc537). The seam, guide, size readout, preview and popover CSS
is copied from the approved `edges-*` states of `layout-free.html`. No web fonts, so the page opens
with no network. Each frame adds today's setup strip above the board (`app.html` `.setbar`,
`idBar()`), which `split-cell.html` predates; it carries the save error (F14).

## Choices

F1. **Where the switch lives, and its words.** Item 14 as drawn in `layout-free.html`: the Free
    Layout switch in the Monitor section, the key F, the callout "Free Layout is on. Nothing moved.",
    and the monitor label "Free Layout" in place of "5×2". The Columns and Rows steppers are off with
    "Free Layout is on. Turn it off to change the grid." Gain: one switch per monitor, next to the
    grid it replaces (`ux-control-beside-area`). Loss: none new. Pick: as drawn.

F2. **Seams come from the spaces.** The page works out each line from the spaces: a line runs
    between two crossings where both sides have an edge, and each such run is one grip (item 16).
    So after a plain drag, the line in the other row keeps its own grip. A part that touches a locked
    window is dotted, with no grip, and says why (item 18). Gain: one rule draws every state, so the
    builder gets the rule, not a list. Loss: a long line in many rows shows many grips. Pick: as drawn.
    How spaces appear and go: switch-on makes one space per cell (or span), Split adds one space
    (F13), and Close Gap removes one (F12). There is no tool to draw a space by hand: that was Free
    Rects, rejected (item 22).

F3. **The Shift move is found at the drag.** Every drag shows a tip at the pointer that names the
    other move: "This row only. Shift moves the whole line." on a plain drag, "Shift: the whole line,
    2 rows" with Shift held. The board hint says it too. Gain: Shift is found without the keyboard
    list. Loss: a tip covers part of the lower row during the drag. Pick: as drawn.

F4. **The size floor shows where it stopped.** At 400 × 300 px (item 20) the line stops, a stop bar
    marks it, and the size that stopped it turns ink. The tip says "Smallest size: 400 × 300 px. The
    line stops here." Gain: the stop reads as a rule, not a stuck control. Loss: none. Ruled: as drawn, 2026-11-19 13:10 CST (owner: "F4/F6/F12: yes to all three").
    The floor itself
    is item 20 of `layout-free-notes.md`, ruled at the same time (decision `layout-free`).

F5. **Shift-drag across a locked row (item 18, owned by L4).** Two options, each with its switch:
    - Go Around (ruled, state `lock-around`): Shift moves every part of the line that can move and
      leaves the part beside the locked window. The tip and status bar say what stayed. Gain: the
      lock rule reads as today's ("Swaps, zones and fill go around it"), and Shift never dead-ends.
      Loss: the "whole line" ends with a jog; on this two-row board it moves what a plain drag moves.
    - Refuse Shift (state `lock-refuse`): the Shift-drag does nothing, with a no-entry pointer and
      "Terminal is locked, so the whole line cannot move. Let go of Shift to move the lower part."
      Gain: the whole line stays straight. Loss: a refusal where a partial move was possible.
    Ruled: Go Around, 2026-11-19 13:10 CST (owner: "F5: Go Around").

F6. **Keys (item 19, owned by L4).** The monitor decides: on a Free Layout monitor, Shift+arrows move
    the selected window's right or bottom line by 1/48 of the monitor (85 px on 4096), in its row
    only, as the plain drag does; Ctrl+Shift+arrows move its left or top line. Alt added to either
    moves the whole line, as the Shift-drag does. On a grid monitor, Shift+arrows keep today's
    whole-cell resize. Plain arrows move the window to the next space; a window there swaps with it.
    The inspector reads Width and Height in pixels (item 19). Gain: one set of keys, the same moves
    as the pointer, and the whole-line move has a keyboard way (the plan named none). Loss: a key
    means two things by monitor; Alt+Shift+arrows is a three-key chord. Ruled: as drawn, 2026-11-19 13:10 CST (owner: "F4/F6/F12: yes to all three").
    Departs from: plan L4 (Shift+arrows move lines by 1/48, no whole-line key) — adds Alt for the
    whole line, and arrows swap with the next space.

F7. **Assign by drop, one home.** A drop on an empty space pins the window there; the space lights
    and says "Notepad goes here" (state `assign-drop`). A drop on a space a window holds uses today's
    targets: the Swap circle and Put Behind (`app.html` `dropZone()`, `swapInto()`, `putBehind()`).
    Move To in the inspector lists spaces ("Choose a Space"). Gain: nothing new to learn. Loss: none.
    Pick: as drawn (ruled, owner, 2026-11-19 16:50 CST: a drop on a held space offers Swap and Put Behind).

F8. **"Space", the word on the screen.** The engine's area is a "space" on the screen: Empty space,
    Choose a Space, Split Chrome's Space, Close Gap. The act keeps its name: Split Cell on the
    inspector button and the key S (split-cell S1). Gain: a plain word that also reads for an empty
    one. Loss: two words for one thing across code and screen. Pick: space.

F9. **A new window fills the first empty space in reading order** (item 26; `Resolve-FreeAreas`
    sorts spaces by top line, then left line). State `assign-fill` shows two empty spaces, the first
    one taken, the other marked Fills next. Pick: as drawn.

F10. **Whether the board shows a gone window's space as lent (owned by L4).** The tray works out the
     gone window's space at apply time and never saves it (item G). Two options:
     - Lent Space (ruled, state `gap-lent`): the board keeps the saved layout and draws the space as
       lent, each part hatched in the colour of the window that has it, with a solid edge on that
       window's side. Selecting it says who has how much and that restore gives it back. Gain: what
       you drag is what saves; the board never shows a layout that is not saved. Loss: the board and
       the screen differ while the window is gone; for a closed window that never reopens, they
       differ with no end, until Close Gap or a drag.
     - Grown Neighbours (state `gap-grown`): the board draws the screen: the neighbours grown, and
       the gone window's saved space as a dashed outline. Gain: the board matches the screen. Loss: a
       drag on a grown neighbour edits a rect that is not saved, so it is unclear what it changes.
     A closed window's space is lent the same way (ruling 2026-11-18 11:08 CST: closed and
     minimized); its space fills again when that app opens and matches the area. Ruled: Lent Space, 2026-11-19 13:10 CST (owner: "F10: Lent Space"). The hatch carries meaning (space on loan), as `layout-free-notes.md` item 29
     says of every hatch here; each part keeps a solid or dashed edge, so forced colours keep it.

F11. **A gap that stays.** When no side qualifies (here: Terminal and File Explorer locked), the
     space stays empty on the screen and draws as a yellow hatched gap with "Excel closed, Stays
     empty". The inspector says why and leads on with Unlock File Explorer (`ux-no-dead-end`). Close
     Gap is not offered: the space is still Excel's, and comes back to it. Pick: as drawn.

F12. **Close Gap uses the gone-window rule.** Close Gap on an empty space removes it, and the
     neighbours take it by item G: both sides meet in the middle when both qualify. The board
     previews each strip, hatched in its window's colour, while the button has focus. Unlike a gone
     window, this saves. Gain: one rule for every space that empties (plan: "Close Gap calls the same
     function"). Loss: an owner who wanted one neighbour to take it all drags the line after.
     Departs from: `layout-free-notes.md` item 17 (Close Gap grows the one neighbour that shares the
     whole edge) — both qualifying sides meet in the middle, by the owner's F12 grant. Question M (a gone window's share) stays open. Ruled: yes, 2026-11-19 13:10 CST (owner: "F4/F6/F12: yes to all three").

F13. **Split in Free Layout** (item 28). The split menu of `split-cell.html` (S1, Menu List), halves
     only (S1 default). Each group says "Adds a line", since no grid doubles. The heading names the
     space: "Split Chrome's Space". The empty half is a space with no pin and no app. Pick: as drawn.

F14. **Errors.** Two, both from real paths:
     - The save fails (state `err-save`): today's setup strip, unchanged (`app.html` `idBar()`, the
       `failed` branch): "Not saved. … Undo still works." with Try Again.
     - An app will not fit its space (state `err-apply`): `Move-Win` in `tile.ps1` notes "off size",
       and today's results row shows that raw text. The row says it in words, "will not go under
       500 px wide, so it covers 90 px of Excel", leads on with Give It 500 px (moves the line), and
       keeps the engine's words under What the Server Said (`ux-machine-text-hidden`). A pin no space
       holds (`Resolve-FreeAreas` "not in a free area") gets a row of the same form.
     Departs from: today's results row (raw engine text) — plain words, a fix button, and the raw
     text behind a disclosure.

F15. **The switch on a 1×1 monitor (item 15, owned by L4).** Off, with item 15's words, "One
     window fills this monitor. Split it first." (plan L4's test reads them), and a Split Cell button beside it,
     which opens the split menu on that window (`ux-no-dead-end`). A split makes the Free Layout switch
     available. It does not turn it on (item 28, Split in Free Layout, `layout-free-notes.md`).
     Gain: the reason leads straight to the fix. Loss: none. Pick: as drawn.

F16. **Empty state.** A Free Layout monitor whose spaces are all empty keeps its lines; each space
     reads Empty with its size. One sentence takes the board hint's place: "No window is placed on
     the ultrawide. Drag one here from Windows That Stay Put, or let windows fill the spaces." and one
     control, Turn On Fill Empty Cells (`ux-unknown-is-not-empty`). It sits under the board, not on
     it, so at 1024 it covers no space. Pick: as drawn.

Also drawn, not new: Draw Zone is off in Free Layout with "Zones pause in Free Layout. Turn it off
to draw a zone." (item 26; Owner grant: yes there). Back to the Grid (item 27) as approved, with
Snap to Cells the default and the count of windows that change size. A line drag adds no Drop Note:
the sizes read at the line while it moves, and Undo in the top bar takes it back, as a resize does.

## Saves

The "Saves in the layout as" blocks use the L3 engine's shape: `grids[mon].free.areas`, each area a
`rect` in fractions with a `pin` index, an `app` and `title`, or nothing. A filled window's area
names its app and title, as the held layout does. The keys are drawn as `wide` for reading; in id
mode they are monitor ids. The builder owns the shape.

## Departs from the plan and notes

- Departs from: plan L4 keys (Shift+arrows only) — Alt+Shift+arrows move the whole line, and arrows
  swap with the next space (F6).
- Departs from: `layout-free-notes.md` item 17, Close Gap grows one neighbour — both qualifying
  sides meet in the middle, by the owner's F12 grant (question M stays open).
- Departs from: today's Apply results row (raw engine text) — plain words, a fix, and a disclosure
  (F14).

## Input needed

- Ruled: Go Around for the Shift-drag across a locked row (F5; owner, 2026-11-19 13:10 CST: "F5: Go Around").
- Ruled: Lent Space for a gone window's space on the board (F10; owner, 2026-11-19 13:10 CST: "F10: Lent Space").
- Ruled: yes, keys on a Free Layout monitor, with Alt+Shift+arrows for the whole line (F6; owner, 2026-11-19 13:10 CST: "F4/F6/F12: yes to all three").
- Ruled: yes, the size floor, 400 × 300 px (F4; item 20 of `layout-free-notes.md`; owner, 2026-11-19 13:10 CST: "F4/F6/F12: yes to all three").
- Ruled: yes, Close Gap shares the space at the middle (F12; owner, 2026-11-19 13:10 CST: "F4/F6/F12: yes to all three").
- Open, drawn at defaults: S1, G1, K1, M1, read as the plan's defaults (top of this file).
