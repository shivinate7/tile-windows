# Dropping a promoted window behind another lists it twice

Decision: stack and lock (`stack-and-lock`). Found in app.html at c2c2904 (PR 87, the closed-front pull request, review round 1, finding F4). The fault predates PR 87, and that change does not touch it. Recorded 2026-11-20 13:13 CST. Line numbers are at c2c2904.

putBehind (app.html:1737) lists the promoted window twice when the window is dropped behind another window. One entry is then left with no open window.

Probe on the branch copy: behind = [Draft release notes, Draft release, Quarterly], missing = 1.

Harm: a stack lists one window twice, and one entry has no open window.

Likelihood: unmeasured. Dropping a window behind another is a normal stack action.

Recovery: not checked in the review.

Fix: write a red case first. Drop a promoted window behind another window, then check that the stack lists each window once and none is missing. Then fix putBehind.
