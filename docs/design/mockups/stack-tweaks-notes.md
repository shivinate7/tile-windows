# Stack tweaks: design notes

Mockup: `stack-tweaks.html`, beside this file. Owner rulings 2026-11-16, about 09:05 CST.
Deep links: `#s=<state>`, plus `w=1024`, `t=light|dark` and `hide=<option,...>`. With no `t`,
the page follows the system theme. `#s=all` shows every state.
States: `sw-today`, `sw-in`, `sw-out`, `sw-span-in`, `sw-span-out`, `sw-sizes`, `sw-rev`,
`sw-locked`, `lk-today`, `lk-rest`, `lk-hover`, `lk-sel`, `ld-today`, `ld-drag`, `ld-confirm`,
`rz-today`, `rz-drag`, `rz-after`, `ms-rect`, `ms-wins`, `ms-shape`, `ms-empty-need`,
`ms-empty-cell`. Option keys for `hide`: `circle`, `reverse`, `padlock`, `confirm`, `tolist`,
`merge`, `needwin`, `mcell`.

Sizes: 1440 and 1024, the brief's sizes; `layout.py devices` gives no device list for this repo.
The scales are the board-feedback mockup's: 1440 width-bound (104px cells), 1024 at 57px cells.
Tokens and tile CSS are copied from `board-feedback.html`, which copies `app.html`. No web fonts,
so the page opens with no network.

Focus ids for the waiting page, each prefixed by its state key: `-swap-circle`,
`-put-behind-area`, `-behind-circle`, `-chip-above`, `-sizes`, `-padlock`, `-locked-chip`,
`-locked-confirm`, `-resize-label`, `-to-the-list`, `-resize-note`, `-list-chip`, `-merge-bar`.

Everything not named below stays as it is on main: the Drop Note, the layered stack look, the
named badge, the handles on every edge, Fill Empty Cells and Clear Board.

## 1. Swap is a circle (ruling 4)

1. **Reading of the ruling.** The owner wrote: a circle area in the square; hover in that area and
   it becomes Put Behind rather than Swap. The brief reads it as: inside the circle swaps, the rest
   of the cell puts behind. The mockup draws that (`sw-in`, `sw-out`). The words can also read the
   other way: the circle puts behind and the rest swaps. `sw-rev` draws that, with the same
   geometry and the labels swapped. Pick: the brief's reading. Owner grant: yes (which reading).
2. **Circle size.** Diameter is half the block's short side, rounded down, from 28 to 64px. The hit
   test is the distance from the block's centre, not the circle's bounding square.
   | Block | Size | Circle | Share of block | Narrowest Put Behind band |
   |---|---|---|---|---|
   | 1440, one cell | 104×105 | 51px | about 19% | 26px |
   | 1440, 2×1 span | 209×105 | 52px | about 10% | 26px |
   | 1024, one cell | 57×57 | 28px | about 19% | 14px |
   Gain: the circle is at least 28px (over the 24px of WCAG 2.5.8), and the band keeps at least
   14px on every side plus the corners. Loss: Swap shrinks from 64% of the cell to 10 to 19%.
   Other option: 60% of the short side (62px and 34px; band 21px and 11px). Pick: 50%.
   Departs from: `decisions/stack-and-lock.md`, "Swap (top 64%, the default)". After this change
   Put Behind is the larger target, so a careless drop stacks. Owner grant: yes.
3. **Labels.** The circle holds the swap icon, and the word "Swap" when it is 48px or wider. The
   Put Behind pill sits at the bottom of the block, with today's forms by width: "Put Behind
   Chrome" from 150px, "Put Behind" from 84px, a 10px "Behind" below that (`app.html` `frame()`,
   `pickForm()`). The zone under the pointer is solid; the other is dashed, as today. Each label
   shows once.
4. **Spans.** The circle sits at the centre of the whole block and is sized by its short side, so a
   2×1 span has the same circle as one cell. Swap keeps the span with the place, as today.
5. **Locked tile.** No circle: the whole cell is Put Behind, with the "Locked, so no Swap" chip, as
   today (`sw-locked`).
6. **Drag chip above the block.** At 1024 today's chip (`#ghost`, 14px right of and 34px above the
   pointer) covers the circle. Over a taken block, the chip moves to just above the block. Gain:
   the circle and both zones stay in view. Loss: the chip stops following the pointer there.
   Departs from: `app.html` `frame()`, which places `#ghost` at the pointer. Pick: above the block.
7. **Edge flicker.** The zone keeps its state until the pointer is 3px past the circle's edge, so a
   pointer on the edge does not flicker between the two. A proposal; not drawn.
8. **Board hint.** "On a taken cell, the circle swaps and the rest puts it behind." It replaces the
   sentence about the lower band.
9. **Builder note.** `dropZone()` changes from a y ratio (`>=.64`) to a radius test against the
   block's centre. `#drop.split` and its two `.dz` children become one zone with a circle child.

## 2. Padlock when needed (ruling 1)

10. **When it shows.** On hover, on keyboard focus inside the tile (`:focus-within`), and on a
    selected tile. A locked tile always shows its filled chip (`lk-rest`). A hidden padlock is
    `visibility:hidden`, so it takes no click and no Tab stop. Unlike the grip, which stays
    hit-testable when faint, an invisible lock that clicks would be a trap.
    Departs from: `decisions/stack-and-lock.md`, "a padlock on every tile" (`app.html` `.tile .lk`).
    The ruling covers it.
11. **Touch.** A touch screen has no hover, so the padlock shows on selection only. L and the
    inspector's Lock switch stay as the other ways in.
12. **App tag width.** At rest the tag takes the full tile width; while the padlock shows, it stops
    20px short, as today. Gain: at 1024 more of the app name reads at rest. Loss: on hover a long
    name gets its ellipsis sooner. Other option: keep the 20px at rest too, so nothing changes on
    hover. Pick: full width at rest.

## 3. Move a locked tile (ruling 2)

13. **Where the warning comes.** The drag runs as for any tile, and the chip at the pointer shows a
    padlock (`ld-drag`). At the release a warning opens at the drop, in the page
    (`role="alertdialog"`): "Terminal is locked. Move it to the Laptop? It stays locked there."
    with Cancel and Move It (`ld-confirm`). Until Move It, nothing is saved: the tile waits dashed
    in the target, and its old cell stays dimmed. Other option: warn at the press, before the drag
    starts; that stops the drag mid-gesture. Pick: warn at the drop.
    Departs from: `app.html` `drag.locked`, which stops the drag in `pointerdown`, `frame()` and
    `endDrag()` and says "Unlock it first".
14. **The lock moves with it.** After Move It, the tile is locked in its new cell. Other option:
    the move also unlocks it. Pick: it stays locked. Owner grant: yes.
15. **Focus and keys.** Move It takes focus. Esc or Cancel puts the tile back and focus back on the
    tile. A press outside the warning cancels it.
16. **Each drop kind.**
    - Empty cell: as drawn.
    - Swap onto an unlocked tile: "Terminal is locked. Swap it with Notepad? Notepad moves to
      Terminal's cell, and Terminal stays locked."
    - Put Behind: "Terminal is locked. Put it behind Notepad? A window behind another has no lock,
      so its lock goes." A back window has no pin of its own (`putBehind()`).
    - Onto another locked tile: Put Behind only, as today, with the same warning.
    - The list: "Terminal is locked. Move it to Windows That Stay Put? Its lock goes."
      Departs from: `app.html` `unplace()`, which refuses a locked window.
    - The keyboard: arrows on a locked tile open the same warning at the tile.
    Owner grant: yes (the lock goes on Put Behind and on the list).
17. **Status line and key list.** The Keyboard list says "A locked window moves only after a
    warning." The Lock switch's hint reads "It moves only after a warning." on a locked tile.

## 4. Resize sends covered windows to the list (ruling 3)

18. **Covered windows.** Every window the new span covers goes to Windows That Stay Put, pinned or
    filled, with any windows behind it. No window moves to another cell. A locked tile still stops
    the resize. Departs from: `app.html` `planResize()`, which sends covered pins to free cells
    through `fit()` and does not count filled windows (`rz-today`); and from
    `decisions/stack-and-lock.md`, "Covered windows move to free cells in fill order". The ruling
    covers it.
19. **During the drag.** Each covered tile gets a "To the list" tag (the stay icon alone under 84px),
    and the label reads "3×1 · 2 windows go to the list". The `#rzdest` outlines go.
20. **After the drop.** A Drop Note under the resized tile: "VS Code and Notepad went to Windows
    That Stay Put", with Undo (`app.html` `dropNote()`). Their chips in the list wear a blue ring
    for about 1.5 seconds. The status line keeps the same words.
21. **List reason.** The chips read "Covered by a resize", a new `BAYWHY` entry. "You kept it here"
    would be false. This needs the scene's bay entry to carry its reason.
22. **Builder note.** Each covered window is written into the scene's bay (`bayEdit()`), or the
    fill would put a filled window back in a free cell at once.

## 5. Pick cells, then Merge (ruling 5)

23. **Picking.** Ctrl+click toggles a cell or a tile into the pick; a selected tile counts as the
    first pick. A pick shows a blue ring, a tint and a check; a dashed outline with a "2×1" label
    shows the block. Esc or a plain click clears the pick. While two or more cells are picked, the
    selected tile hides Stay Put, the grip and the handles, which act on one window only.
24. **Merge bar.** A bar under the picks, or above them when the stage has no room below, in the
    Drop Note's look. It says what Merge does in words, with Cancel and Merge (`ms-rect`). Other
    option: Merge in the inspector. Pick: the bar, so the answer shows at the pick
    (`ux-answer-at-press`).
25. **Several windows.** The first window picked keeps the span. The others go to Windows That Stay
    Put, as a resize sends them (item 18), and the bar names them (`ms-wins`). Other option: the
    others go behind the first. Pick: the list, so Merge and resize act alike.
26. **Not a rectangle.** Merge is off, and the bar says why. A dashed amber outline shows the block,
    and each missing cell is hatched. Fill to Rectangle adds the missing cells to the pick, so the
    owner sees what they cover before Merge (`ms-shape`). Other option: Merge fills the rectangle
    on its own. Pick: Fill to Rectangle.
27. **No window in the cells.** A span belongs to a window today (a pin's `slots`).
    - Option one: Merge is off: "A span belongs to a window. Ctrl+click a window next to them, or
      drag one in." (`ms-empty-need`).
    - Option two: the cells become one cell the fill uses as one (`ms-empty-cell`). This needs a
      merged-cell field in the scene and in `tile.ps1`.
    Pick: option one. Owner grant: yes.
28. **Other cases.** A locked tile in the pick: Merge is off, "Terminal is locked. Leave its cell
    out." A Ctrl+click on another monitor starts a new pick there, and the status line says so. A
    picked stacked tile: its back windows go with it, to the span or to the list. Not drawn.
29. **Disabled Merge.** Its reason sits in the bar as text, tied with `aria-describedby`, because a
    disabled button takes no focus (the `#whyoff` pattern).
30. **Keyboard.** Shift+arrows, Ctrl+Shift+arrows and the Width and Height steppers already make a
    span. No second key path is added. The Keyboard list adds "Ctrl+click cells to pick them, then
    Merge joins them."
31. **Builder note.** The stage's `pointerdown` handler must check Ctrl before it starts a zone
    (`zdraw`), since a press on an empty cell draws a zone today and Shift+click sets zone corners.
