# Stack and lock

Kind: build
Plan: docs/design/mockups/stack-and-lock-notes.md#stack-and-lock (windows)

**Question.** How does the board stack a window behind another, lock a tile, resize a span, and take a drop on a spanned block?

**Ruling (owner, 2026-11-11 10:37-10:44 CST; the designer's open picks approved 11:16 CST; every option in the board-feedback mockup approved as an improvement, not an alternative, 16:31 CST).**
- Stack: a drag over a taken cell splits into Swap (top 64%, the default) and Put Behind (bottom band). A stacked tile shows a layered stack look: the back window is a layer under the front tile, and a strip at the front tile's top names the back app. The 3px stack edge goes. At 1440 the +N badge names the back app ("Excel", or "Excel +1" for two; Named Badge). At 1024 a narrow tile shows the back app's initial in its category colour, and the count moves to the tooltip and label. A click brings the back window to the front. The inspector lists the back windows with Bring to Front and Take Out (to Windows That Stay Put). On Apply the back window gets the same rect and is not minimized.
  If the front window is not open on Apply, the first open back window takes its place as the new front.
  After a Put Behind drop, a Drop Note on the tile that took the drop names the stack ("Excel is behind Claude") with Undo. It stays about 6 seconds or until the next press. The status bar keeps the same words.
- Lock: a padlock on every tile. A locked tile never moves (no swap; zone and fill flow around it). A drop on it offers only Put Behind. The lock saves in the scene.
- Resize: handles on every edge and corner, drawn just outside the tile. A drag snaps the span to whole cells, with a live "2×2" label. Covered windows move to free cells in fill order, else to Windows That Stay Put. A resize stops at a locked tile. Shift+arrows stays.
  Ctrl+Shift+arrows resize from the top and left edges.
- Spanned drop: a drop on a spanned block targets the whole block, as Swap or Put Behind, never a 1x1 Place here and never a tile over another. Swap keeps the span with the place.
- On cells under 84px the Put Behind label reads "Behind"; the tooltip keeps the full name.

The look for the stack and resize is in `docs/design/mockups/board-feedback-notes.md` (Put Behind, Resize from any corner). The lock and spanned-drop picks, with the options not taken, are in `docs/design/mockups/stack-and-lock-notes.md`.

**Why.** The owner wants windows stacked and pinned in place inside a scene, and spans set by drag, without tiles drawn over each other.
