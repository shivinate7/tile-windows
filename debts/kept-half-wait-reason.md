# A window waiting for a kept half reads "No room"

Decision: fill controls (`fill-controls`). Found at d2ee88e. Recorded 2026-11-20 16:39 CST. Line numbers are at d2ee88e.

The waiting reason for a window in fill-keep reads "No room: add a column" (BAYWHY, app.html:1233), though the kept half is the reason.

Harm: the reason points at the wrong fix, adding a column.

Likelihood: unmeasured.

Recovery: none in the code.

Fix: give a kept half its own reason in BAYWHY. Write a red case first: a window beside a kept half reads the kept-half reason.
