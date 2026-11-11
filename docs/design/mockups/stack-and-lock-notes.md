# Stack and lock: design notes

Mockup: `stack-and-lock.html`, beside this file. Owner ruling 2026-11-11 10:37-10:44 CST.
Deep links: `#s=taken|behind|locked|spanned|stacked|inspector|resize|all`, plus `w=1024` and
`t=light|dark`. With no `t`, the page follows the system theme.

Sizes: 1440 and 1024, the brief's sizes. `layout.py devices` gives no device list for this repo.
Fonts: the page loads no web fonts, so that it opens with no network. The app's font stacks fall
back to Segoe UI here. The app itself loads Sora, DM Mono and Bricolage Grotesque.
The `--ann-*` tokens are for the mockup's labels only. They are not product colours.

1. **Split geometry.** A taken cell splits into a Swap zone (the top 64%, which holds the centre)
   and a Put Behind band (the bottom 36%). The zone under the pointer is solid; the other is dashed.
   Gain: a plain drop in the middle swaps, as ruled. The band is a large, steady target.
   Loss: a drop low in the cell now stacks. Today it swaps.
   Other options: left and right halves (no centre, so "the default swaps" does not hold), or a
   small Put Behind chip in one corner (a hard target on a 78px cell). Pick: the bottom band.
2. **Labels by cell width.** 110px or wider: "Swap with Claude" and "Put Behind Claude", with
   icons. This keeps the 110px rule in `app.html` `frame()`. From 84 to 110px: "Swap" and "Put
   Behind". Under 84px (the 1024 cells): "Swap" and "Behind". The tooltip keeps the full name.
   Departs from: the ruled name "Put Behind", on cells under 84px only. Pick: as above.
3. **Swap keeps today's cues.** The target tile keeps `.tile.swap`. The `#dest` outline still
   shows "Claude moves here" at the dragged tile's cell (`frame()`, `swapTarget()`). Put Behind
   shows no `#dest`, because the window in front does not move. Pick: keep both.
4. **Lock icon.** A padlock button in each tile's top-right corner. An open outline means
   unlocked. A filled ink chip means locked. The pin moves from the top-right corner to the spot
   under the lock (today: `.pinmark` at top-right), so the app tag keeps its width.
   Gain: lock is one click from the board, as ruled. Loss: at 1024 the app tag clips sooner
   ("Clau…"). Option: "Lock on Every Tile" off shows the lock only on hover, focus or selection.
   Pick: on every tile, as the brief says.
5. **Lock and pin differ.** A pin holds the scene's cell, and it can still swap (`swapInto`). A
   lock never moves. The two use different glyphs. A locked tile shows no resize handle and has a
   default cursor, not grab. Dragging it does nothing: unlock it first. Pick: as above.
6. **Drag over a locked tile.** The whole cell is one Put Behind target, with a "Locked, so no
   Swap" chip ("Locked" on narrow cells). The chip says why Swap is missing
   (`ux-control-earns-place`). Pick: as drawn.
7. **Drop on a spanned block.** The whole 2×2 block is the target, split as in item 1. Swap keeps
   the span with the place: Terminal takes the 2×2 block, and Chrome goes to Terminal's old cell at
   1×1. Put Behind puts Terminal behind Chrome at 2×2. Today `swapTarget()` returns null for any
   span over 1×1, so the board shows "Place here" over one cell, and `pinEdit` drops Chrome's pin.
   Other option: the span goes with the window (Chrome stays 2×2), which has no room in a 1×1 cell.
   Owner grant: yes. Pick: the span stays with the place.
8. **Stack badge.** A "+N" ink chip with a stack icon, at the bottom-left of the front tile. A
   click brings the window directly behind to the front, and the front window goes to the back.
   The tooltip names the windows behind. On a selected stacked tile, Stay Put moves up one row
   so that it clears the badge. Other option: the badge on the top row, which clips the app tag
   more. Pick: bottom-left.
9. **Stack edge.** The front tile is inset 3px from the top and right, and the back window's edge
   shows there. Gain: you see the stack without reading the badge. Loss: the front tile is 3px
   smaller. Option: "Stack Edge" off. Pick: on.
10. **Behind This Window.** A list in the inspector's Window section, right after the Lock switch and
    above Width and Height, so it shows without a scroll at 1440. Each row has
    Bring to Front and Take Out. Take Out sends the window to Windows That Stay Put, as Keep Where
    It Is does today (`bayEdit`). Other option: Take Out puts the window in the next free cell.
    Pick: Windows That Stay Put.
11. **Lock switch in the inspector.** A "Lock" switch in the Window section gives a keyboard and
    screen-reader path to the tile's lock. Option: "Lock Switch in Inspector" off. Pick: on.
12. **New keys.** L locks or unlocks the focused window. B brings the window behind it to the
    front. The Esc line adds "a resize". Shift+arrows still resize (`app.html` Keyboard list).
    Pick: add them. This is a proposal; the ruling names no keys.
13. **Resize handle.** A corner grip at the bottom-right, on a selected or hovered tile. Dragging
    it draws an outline that snaps to whole cells, styled like the zone outline (`#zdraw`), with a
    live label "2×2 · 2 windows move". The label uses "×", as the monitor labels do
    (`render()`, `${g.c}×${g.r}`), not "x". The Width and Height steppers follow during the drag.
    The tile does not stretch until the drop, so no tile is drawn over another. Pick: as drawn.
14. **Resize over taken cells.** A window that the new span covers moves to a free cell in fill
    order. With no free cell, it goes to Windows That Stay Put. `#dest` outlines show where each
    one goes. Today `pinEdit` drops each pin that the new span covers, and the window fills again.
    The resize stops at a locked tile. Other options: covered windows go behind the resized one,
    or the resize stops at any taken cell. Owner grant: yes. Pick: move to free cells.
15. **Board hint.** One fixed sentence is added: "On a taken cell, the middle swaps and the lower
    band puts it behind." It does not change during a drag. Pick: add it.
16. **Builder note.** The stage's `pointerdown` handler (`app.html`, near line 831) must skip
    `.tile .lk`, `.tile .stk` and `.tile .rsz`, as it skips `.stayput` today. Otherwise a click on
    the lock, the badge or the handle starts a drag.
