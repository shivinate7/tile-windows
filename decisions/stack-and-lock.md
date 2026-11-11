# Stack and lock

Kind: build
Plan: docs/design/mockups/stack-and-lock-notes.md#stack-and-lock (windows)

**Question.** How does the board stack a window behind another, lock a tile, resize a span, and take a drop on a spanned block?

**Ruling (owner, 2026-11-11 10:37-10:44 CST; the designer's open picks approved 11:16 CST).**
- Stack: a drag over a taken cell splits into Swap (top 64%, the default) and Put Behind (bottom band). A stacked tile shows a +N badge; a click brings the back window to the front. The inspector lists the back windows with Bring to Front and Take Out (to Windows That Stay Put). On Apply the back window gets the same rect and is not minimized.
  If the front window is not open on Apply, the first open back window takes its place as the new front.
- Lock: a padlock on every tile. A locked tile never moves (no swap; zone and fill flow around it). A drop on it offers only Put Behind. The lock saves in the scene.
- Resize: a corner handle drags the span across whole cells, with a live "2×2" label. Covered windows move to free cells in fill order, else to Windows That Stay Put. A resize stops at a locked tile. Shift+arrows stays.
- Spanned drop: a drop on a spanned block targets the whole block, as Swap or Put Behind, never a 1x1 Place here and never a tile over another. Swap keeps the span with the place.
- On cells under 84px the Put Behind label reads "Behind"; the tooltip keeps the full name.

The full picks, with the options not taken, are in `docs/design/mockups/stack-and-lock-notes.md`.

**Why.** The owner wants windows stacked and pinned in place inside a scene, and spans set by drag, without tiles drawn over each other.
