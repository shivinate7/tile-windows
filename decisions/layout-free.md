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
- Splitter Tree is a solid concept. Which part joins Shared Edges is open (question (b)).

**Ruling (owner, 2026-11-17 19:09 CST; owner's words, answers question (a)):**

> Only that cell splits... I'd imagine we can then have the board be 10x2 basically if a split occured, and all others kinda just still stay the same so they've all kinda just expanded to two cells if they were originally one

- A split doubles the board's grid along the split's direction. A 5×2 board becomes 10×2 on a side-by-side split. This is notes item 4, Finer Grid.
- The split cell becomes two one-cell halves.
- Every other window that was one cell now spans two cells. On screen, nothing else moves or resizes.
- This joins the 14:12 words "it should result in a finer grid being created when the split occurs".
- Notes item 3, Subdivide the Cell (the grid stays 5×2), is not chosen.

**Open** (question (b) asked 2026-11-17 14:14 CST; the owner has not answered it):
- (b) Which part of Splitter Tree joins Shared Edges? For example: a closed window's space goes to its neighbour at once, with no dashed gap (mockup state `tree-gap`, notes item 17); or a drag that scales a whole column (mockup state `tree-drag`).
  - Owner asked 2026-11-17 19:09 CST whether a closed or minimized window's space could be taken live by its neighbours. Not answered.

Not yet asked: (c) the fast action's trigger, direction and share. S stays with the menu, as drawn, until the owner rules on it.

Notes item 8 (one level) was picked only while item 3 stood, so it has no ruling now.

**Why.** The owner wants one action for the common split, and a menu when the split needs a choice. The owner wants "the gaps between items is immediately addressed" (notes item 23). Shared Edges is the only option that passes all six tests in the notes. Free Rects shows a gap during a drag, and its release guesses which neighbour changes.
