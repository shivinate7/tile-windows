# A keyboard move just after an own apply is not counted

Decision: live-move guard (`live-move-guard`). Found at f55111d. Recorded 2026-11-20 21:42 CST. Line numbers are at f55111d.

An own apply sets `skipRead` (tray.ps1:292). In a window or activity scene, the next window read, about 3 s later, clears it (tray.ps1:244) and skips the compare that counts a move (tray.ps1:245). A keyboard move made in that gap is taken into the baseline and never counted. A later automatic re-flow then moves the window back. This is pre-existing.

Harm: a window the user moved by keyboard goes back when a later automatic apply re-flows the layout.

Likelihood: unmeasured.

Recovery: none in the code. The user moves the window again.

Fix: count a rect change on the first read after an own apply, measured against where the apply put the window. Write a red case first: apply, move a window by keyboard within 3 s, read, re-flow, and check the window stays.
