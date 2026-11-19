# A 40 to 64 px stack strip shows a name where the mockup shows an initial

Decision: layout free (`layout-free`). Recorded 2026-11-19 13:12 CST. Line numbers are at b1735e7.

The mockup calls the strip above a stacked front tile the stack strip (docs/design/mockups/split-cell.html:380). The mockup shows that strip as the app's initial when the tile is under 64 px wide. There `n` is `b.w<64`, and the strip uses `tiny||n` for the initial (split-cell.html:547, :549). The S5 pick is Initial Only (docs/design/mockups/split-cell-notes.md:93).

The app shows the initial only when the tile is under 40 px on a split grid (app.html:1154, `tiny`). From 40 to 64 px, the strip shows the app name, cut with an ellipsis (app.html:1162, and the `.peek .pn` rule at app.html:452). So a stacked half from 40 to 64 px wide shows an ellipsized name where the mockup shows an initial.

Checked by reading the code, not by a run.
