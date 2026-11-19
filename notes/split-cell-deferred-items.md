# Four Split Cell items moved to a later lane

Decision: layout free (`layout-free`). Recorded 2026-11-19 13:12 CST. Line numbers are at b1735e7.

The coordinator moved four L2 items out of PR 51 (Split Cell) to a later lane. PR 51 built none of them. Departs from: the L2 section of the layout-free plan (docs/plans/layout-free-build.md:38, :49, :52), which lists them, and the owner grant that makes selecting the open half part of layout-free item 2 (docs/design/mockups/split-cell-notes.md:98).

- Selecting an empty cell (plan :38). A press on an empty cell starts a zone draw, not a selection (app.html:2028).
- An empty half that fills only after every whole block (plan :49). No code fills an empty half last. A search of app.html, tile.ps1, serve.ps1 and test/ found no "fills last" rule. The coordinator says it needs an engine change that no lane covers.
- Keep This Half Empty (plan :52). No engine keepEmpty. The same search found none.
- Open-half labels. The mockup labels the open half "Open half" and "Fills last" (docs/design/mockups/split-cell-notes.md:95-96). app.html shows no label for it. The phrase appears only in code comments (app.html:1827, :1842) and in a test name (test/setup-page.ps1:1646).

Checked by reading the code, not by a run.
