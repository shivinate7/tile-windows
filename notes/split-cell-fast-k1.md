# The fast split ships as K1 while question K is open, and it splits side by side

Decision: layout free (`layout-free`). Recorded 2026-11-19 13:12 CST. Line numbers are at b1735e7.

splitFast calls splitCell with side-by-side and keeps the left half (app.html:1787). Two paths reach it: Shift+S (app.html:2101) and a double-click (app.html:2138).

The code labels this K1, "the owner's pick while question K is open" (app.html:1786). No record holds K1. A search of docs, decisions, notes and debts at b1735e7 found no record of it.

Question K, the fast-split trigger, is still open (docs/plans/layout-free-build.md:152, :156). Its proposal splits the cell along its longer side (:156). The code always splits side by side, whatever the cell's shape (app.html:1787). Plan L2 also says splitFast ships with no trigger until question K (:39). The code has two triggers.

Departs from: plan :39 and :156.

Checked by reading the code, not by a run.
