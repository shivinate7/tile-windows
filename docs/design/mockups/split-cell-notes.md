# Split Cell on the board: design notes

Mockup: `split-cell.html`, beside this file. Lane L2 of Layout Free (decision `layout-free`).
The rules of a split are items 1-13 of `layout-free-notes.md` (items 5-13 rewritten for Finer
Grid). This file holds only the mockup's own choices, numbered S1 to S8, and cites those items.

Owner rulings drawn: a split doubles the grid along its direction (5×2 to 10×2); the split cell
becomes two halves; every other one-cell window spans two cells; nothing else moves (2026-11-17
19:09 CST). S, a right-click and an inspector button open the "choose how" menu; while question S
(shares) is open, the menu offers halves only. Question K, the fast split's trigger, is open; its
look is drawn and marked Proposed.

Deep links: `#s=<state>`, plus `w=1024`, `t=light|dark` and `hide=<option,...>`. With no `t`, the
page follows the system theme. `#s=all` shows every state. The three `small-*` states open at 1024
by default, because at 1440 a half is today's narrow tile.

| State | Shows | Option key | Focus id |
|---|---|---|---|
| `menu-list` | Right-click, the split menu | `list` | `menu-list-menu` |
| `menu-pop` | Right-click, the popover | `pop` | `menu-pop-popover` |
| `split-done` | After a split, 10×2 | shared | `split-done-result` |
| `fast-longer` | Fast split, longer side (proposed) | `longer` | `fast-longer-result` |
| `fast-side` | Fast split, always side by side (proposed) | `side` | `fast-side-result` |
| `fill-last` | A new window takes the open half last | `last` | `fill-last-half` |
| `fill-keep` | Keep This Half Empty | `keep` | `fill-keep-half` |
| `case-stack` | Split a stacked tile | shared | `case-stack-result` |
| `case-lock` | Right-click a locked tile | shared | `case-lock-menu` |
| `case-zone` | Split a cell in a zone | shared | `case-zone-result` |
| `case-held` | Split a held cell, fill off | shared | `case-held-half` |
| `case-second` | Split another cell, the grid stays 10×2 | shared | `case-second-menu` |
| `case-again` | Split a half again | shared | `case-again-menu` |
| `join` | Join the halves, back to 5×2 | shared | `join-result` |
| `small-initial` | 1024 halves, Initial Only | `initial` | `small-initial-tile` |
| `small-vertical` | 1024 halves, Vertical Name | `vertical` | `small-vertical-tile` |
| `small-zoom` | 1024 halves, Zoom to the Monitor | `zoom` | `small-zoom-board` |

Sizes and themes: 1440 and 1024, light and dark, as the other mockups here. `layout.py devices`
gives no device list for this repo, so the sizes are the brief's. Scales are the board-feedback
mockup's (0.1323 at 1440, 0.0755 at 1024). Tokens and tile CSS are copied from `app.html` on main
(b6bc537; `:root` is the same as in 378d26a). The menu, stack strip, badge and zone CSS are copied
from `app.html` too. No web fonts, so the page opens with no network.

The scene section is drawn in id mode: the layout saves as the board changes, and Save keeps only
the name and triggers (`app.html` `renderInsp()`, `idm()`). The L2 plan autosaves each split
through POST /layout.

## Choices

S1. **The split menu: Menu List or Popover.** Both open from S, Shift+F10 and the Menu key on the
    selected tile (under it), from a right-click (at the pointer), and from Split Cell in the
    inspector (under the button).
    - Menu List (pick, state `menu-list`): `app.html`'s `.menu` with `role="menu"`, one home for
      menus. Two groups, Side by Side and Stacked, each with "Claude Keeps Left/Right" (or
      Top/Bottom). Each group's line says what the grid becomes ("Grid goes to 10×2", "Grid stays
      10×2" when no doubling is needed, layout-free item 7). A glyph on each item shows the kept
      half filled in the window's colour and the open half dashed. Gain: one click splits; the
      grid result shows before the press. Loss: four items where the popover has two rows.
    - Popover (state `menu-pop`): Direction, then the half the window keeps, then Split. Gain:
      fewer words. Loss: two picks and a confirm, and a right-click that opens a dialog, not a
      menu.

S2. **Menu behaviour.** The focused item previews on the board: a dashed line and a hatched open
    half (`ux-answer-at-press`). The hatch is opaque, so the tile's title never shows through it.
    Arrows move the focus, Enter or a click splits, Esc closes and puts focus back on the tile.
    A right-click on the board never shows the browser's own menu. With no room below, the menu
    opens above, as `placeMenu()` does today. A locked tile's menu leads with Unlock (L), so the
    refusal is no dead end (state `case-lock`). A half's menu adds Join Halves (J) (state
    `case-again`). Departs from: `.menu` is `position:fixed` under a button today; at the pointer
    it needs the same edge clamp. Gain: the split shows before it acts, and every way in ends in
    the same menu. Loss: at the pointer the menu covers the row under the tile. Pick: as drawn.

S3. **The fast split's look (question K, proposed).** Shift+S or a double-click on the selected
    tile splits at once, with the Drop Note and Undo as any split. Two rules drawn:
    - Longer Side (the plan's proposal, state `fast-longer`): the cut halves the longer side. On
      this ultrawide a cell is 819 × 840 px, and on the owner's 3440 × 1392 area it is 688 × 696
      px. Both are a little taller than wide, so the fast split stacks (5×4), not the owner's
      10×2 example. Gain: halves are never thinner than they are tall. Loss: on the owner's
      boards it does the less likely split.
    - Always Side by Side (state `fast-side`): gives the owner's 10×2 example. Gain: the result is
      known before the press. Loss: on a portrait monitor's cell it makes tall, thin halves.
    Pick: Always Side by Side. Double-click is free today (`app.html` has no `dblclick`); S and
    Shift+S are free (`stage` keydown). The keyboard list shows the proposed line dotted.

S4. **The Columns and Rows steppers on a split monitor.** Drawn with the fine count (10) and a
    note: "Split side by side: each filled window takes 2 columns, so it keeps its size. Join
    every split to go back to 5×2." What + does on c = 10 with `mult [2,1]` is open: step the base
    grid (5 to 6, so 10 to 12, splits kept), or turn the stepper off with "Join every split to
    change the grid." Pick: step the base grid. The columns cap rises to a proposed 24, and the
    rows cap to a proposed 8 (L2 plan).

S5. **Small halves.** Layout-free item 12. The three options share one board: a selected half
    (Claude, cell 3) and a stacked half (Claude, cell 15, Terminal behind), so each option shows
    both the selected and the stacked case. Pick: Initial Only.

S6. **The open half on the board.** A dashed box that reads as space, with "Open half" and
    "Fills last" (or "Stays empty" with fill off, "Zone fills last" in a zone, "Kept empty" with a
    no-entry mark under Keep This Half Empty). Under 40px it is the dashed box alone; its label is
    in its accessible name. Selecting it is layout-free item 2 (owner grant). Gain: the cell's own
    dashed look, so it reads as space, not a window. Loss: two words in a 47px box at 1440 wrap to
    three lines. Pick: as drawn.

S7. **Words.** The board hint gains "Right-click a window to split its cell." The keyboard list
    gains "S or Shift+F10 opens Split Cell on the selected window or open half. J joins a split
    cell." The monitor label reads the fine grid ("10×2"). The inspector names a half by both
    numbers: "Pinned · Ultrawide cell 3, the left half of cell 2." Gain: the right-click is
    found without the keyboard list, and a half names both numbers. Loss: a longer hint line.
    Pick: as drawn.

S8. **Save shapes.** The "Saves in the layout as" blocks use the L1 plan's fields (`mult`,
    `fill.unit`) and a proposed `fill.keepEmpty`. The builder owns the shape. Layouts live per
    setup now, so the blocks show only the changed keys. Gain: the builder sees each state's data.
    Loss: a field name here may differ from L1's. Pick: L1's names win.

## Departs from today

- A right-click on the board opens the split menu, not the browser's menu (S2).
- A filled window becomes pinned when it splits (layout-free item 5).
- A tile under 40px wide drops its lock, Stay Put, grip and stack badge (S5, layout-free item 12).

## Input needed

- Owner grant: yes. Keep This Half Empty (layout-free item 6, state `fill-keep`).
- Owner grant: yes. Empty-cell selection, for Split Cell on an open cell (layout-free item 2).
- Question K: the fast split's trigger (Shift+S, double-click, or both) and its rule (S3).
- Open: Menu List or Popover (S1). Pick: Menu List.
- Open: 1024 halves (S5). Pick: Initial Only.
- Open: what the Columns stepper does on a split monitor (S4).
