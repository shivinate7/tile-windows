# A free half in a zone reads as a whole empty cell

Decision: layout free (`layout-free`). Found in PR 70 (the Split Cell engine) and PR 72 (the Split Cell board). Recorded 2026-11-20 05:53 CST. Line numbers are at 8392b9f.

Mockup S6 (`docs/design/mockups/split-cell-notes.md`) draws a free half in a zone as "Open half" with "Zone fills last". The engine now fills zone halves last (PR 70), so that label would be true. The board does not show it yet.

Harm: a free half inside a zone reads as a whole empty cell.

Likelihood: unmeasured.

Fix: label a zone's free half "Open half / Zone fills last", as S6 draws it, in `app.html` `cellItems` (kind zone, app.html:1957).
