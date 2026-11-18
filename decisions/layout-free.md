# Layout free

Kind: build
Plan: docs/design/mockups/layout-free-notes.md#split-cell (windows)
Plan: docs/design/mockups/layout-free-notes.md#free-layout (windows)

**Question.** How does a cell split, and how does a window's edge move when the board is not on the grid?

**Ruling (owner, 2026-11-17 14:12 CST; owner's words):**

> on splitting, I imagine there's like a fast mode where one click/action immediately splits it in two, but there's maybe another mode via right click or hitting a button that gives you options like split: choose how -- I also agree that it should result in a finer grid being created when the split occurs / on shared edges ... yes, it looks fine do that / free rects definitely not it / shared edges+splitter tree also a solid concept

- Split Cell has two ways in. A fast action splits the selected cell in two at once. A right-click, or a button, opens a menu of split options: direction and share ("choose how"). The popover in the notes (notes item 1) is that menu.
- The owner agrees a split makes a finer grid on the shared edges. Its scope is set by the 19:09 CST ruling below.
- Free Layout model: Shared Edges (notes item 23, the Shared Edges pick). Free Rects is rejected (notes item 22).
- Splitter Tree is a solid concept. Which part joins Shared Edges is ruled at 2026-11-18 11:08 CST, below.

**Ruling (owner, 2026-11-17 19:09 CST; owner's words, answers question (a)):**

> Only that cell splits... I'd imagine we can then have the board be 10x2 basically if a split occured, and all others kinda just still stay the same so they've all kinda just expanded to two cells if they were originally one

- A split doubles the board's grid along the split's direction. A 5×2 board becomes 10×2 on a side-by-side split. This is notes item 4, Finer Grid.
- The split cell becomes two one-cell halves.
- Every other window that was one cell now spans two cells. On screen, nothing else moves or resizes.
- This joins the 14:12 words "it should result in a finer grid being created when the split occurs".
- Notes item 3, Subdivide the Cell (the grid stays 5×2), is not chosen.

**Ruling (owner, 2026-11-18 11:08 CST; the answer chosen in the question box: "Closed and minimized"):**

- Live gap-filling covers closed and minimized windows. When a tiled window closes or minimizes, its neighbours grow into the space at once. When a minimized window is restored, the layout makes room for it again.
- This answers the 19:09 CST question and the gap half of question (b). Mockup state `tree-gap` joins Shared Edges (notes item 17).

**Ruling (owner asked 2026-11-18 11:08 CST, owner's words: "could it be both ways?"; reading recorded by the coordinator 2026-11-18 11:09 CST):**

- The question: does dragging the edge between two columns resize the whole column, or only the row grabbed?
- The reading: both. A plain drag moves only the grabbed edge segment, that row. Holding Shift while dragging moves the whole column line. The plain drag is the mockup the owner approved at 14:12 CST ("yes, it looks fine do that", state `edges-drag`).
- Shift is the coordinator's pick, open to the owner's change. The pick is the coordinator's, 2026-11-18 11:14 CST. Reason: it matches the `edges-drag` caption in layout-free.html, so the mockup needs no change.
- This closes the drag half of question (b). Question (b) is closed.

Not yet asked: (c) the fast action's trigger, direction and share. S stays with the menu, as drawn, until the owner rules on it.

Not yet asked: how a closed window's space divides when more than one neighbour takes it.

Notes item 8 (one level) was picked only while item 3 stood, so it has no ruling now.

**Why.** The owner wants one action for the common split, and a menu when the split needs a choice. The owner wants "the gaps between items is immediately addressed" (notes item 23). Shared Edges is the only option that passes all six tests in the notes. Free Rects shows a gap during a drag, and its release guesses which neighbour changes.