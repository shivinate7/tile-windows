# Stack and lock

Kind: build
Plan: docs/design/mockups/stack-and-lock-notes.md#stack-and-lock (windows)

**Question.** How does the board stack a window behind another, lock a tile, resize a span, and take a drop on a spanned block?

**Ruling (owner, 2026-11-11 10:37-10:44 CST; the designer's open picks approved 11:16 CST; every option in the board-feedback mockup approved as an improvement, not an alternative, 16:31 CST; the padlock, lock drag, resize, swap and span-by-merge picks changed or added 2026-11-16 ~09:05 CST on the choices page; the lock correction at 10:20 CST).**
- Stack: a drag over a taken cell shows Swap as a circle in the middle of the cell. Hovering anywhere else on the cell turns the drop into Put Behind. The circle is half the block's short side, rounded down, from 28 to 64px, and a span has one circle at the centre of the whole block (coordinator pick, 2026-11-16: inside the circle swaps, the rest of the cell puts behind; 50% size; owner to confirm the reading). A stacked tile shows a layered stack look: the back window is a layer under the front tile, and a strip at the front tile's top names the back app. The 3px stack edge goes. At 1440 the +N badge names the back app ("Excel", or "Excel +1" for two; Named Badge). At 1024 a narrow tile shows the back app's initial in its category colour, and the count moves to the tooltip and label. A click brings the back window to the front. The inspector lists the back windows with Bring to Front and Take Out (to Windows That Stay Put). On Apply the back window gets the same rect and is not minimized.
  If the front window is not open on Apply, the first open back window takes its place as the new front (coordinator default, 2026-11-11 12:28 CST, owner not asked).
  After a Put Behind drop, a Drop Note on the tile that took the drop names the stack ("Excel is behind Claude") with Undo. It stays about 6 seconds or until the next press. The status bar keeps the same words.
- Lock: the padlock shows only on hover, keyboard focus or selection. A locked tile always shows its padlock (coordinator reading; owner to confirm). A locked tile can be dragged. At the release a warning opens at the drop, in the page, with Cancel and Move It; until Move It nothing is saved. A moved locked tile stays locked in its new cell (coordinator pick, 2026-11-16). A locked window put behind another, or dragged to Windows That Stay Put, loses its lock, because a back window or a window in the list has no scene field for a lock (owner correction, 2026-11-16 10:20 CST). Until a drag moves it, zone and fill flow around it. A drop on a locked tile offers only Put Behind. The "Locked, so no Swap" chip and the inspector Lock switch stay. The lock saves in the scene.
- Grid change with a locked tile: the grid changes and the locked tile keeps its cell, which may change size, so the window can move on Apply (coordinator default, 2026-11-11 13:05 CST, owner not asked).
- Resize: handles on every edge and corner, drawn just outside the tile. A drag snaps the span to whole cells, with a live "2×2" label. Every window the new span covers (pinned or filled, with its stack) goes to Windows That Stay Put, never to a free cell. Its chip reads "Covered by a resize": the scene's bay entry carries `why` (the engine hands it back in `left[].why`). A Drop Note under the resized tile names them with Undo. A resize still stops at a locked tile. Shift+arrows stays.
  Ctrl+Shift+arrows resize from the top and left edges.
- Span by merge: Ctrl+click cells or tiles, then Merge in the bar under the picks. The first window picked keeps the span; the others go to Windows That Stay Put, as a resize sends them. Merge is blocked until a window is picked (a span belongs to a window), when the picks are not a rectangle (Fill to Rectangle adds the missing cells), and when a locked tile is in the pick (coordinator picks, 2026-11-16). It also makes a span, beside the drag handles.
- Spanned drop: a drop on a spanned block targets the whole block, as Swap or Put Behind, never a 1x1 Place here and never a tile over another. Swap keeps the span with the place.
- On cells under 84px the Put Behind label reads "Behind"; the tooltip keeps the full name.

Open, not rulings: the badge click (revisit after these changes); other stacking models (the owner wants mockups before choosing).

The look for the stack and resize is in `docs/design/mockups/board-feedback-notes.md` (Put Behind, Resize from any corner). The lock and spanned-drop picks, with the options not taken, are in `docs/design/mockups/stack-and-lock-notes.md`.

**Why.** The owner wants windows stacked and pinned in place inside a scene, and spans set by drag, without tiles drawn over each other.

Open owner review: the Tile Windows Choices page
