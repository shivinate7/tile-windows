# Split logic is inline, and the planned pure function and self-test do not exist

Decision: layout free (`layout-free`). Recorded 2026-11-19 13:12 CST. Line numbers are at b1735e7.

The L2 section of the plan specifies a pure `splitLayout()` (docs/plans/layout-free-build.md:34) and a `#selftest-split` page (:43). Neither exists at b1735e7. No file names splitLayout. The self-test hooks in app.html run only undo, scenes, builtin and triggers (app.html:2431).

The split logic is inline. splitPlan checks the grid caps (app.html:1755). splitCell does the edit, and sets `g.mult` inline (app.html:1770-1785, :1782). The split cases live in test/setup-page.ps1, from :1443 on, including the double-click cases at :1956 to :2002.

Checked by reading the code, not by a run.
