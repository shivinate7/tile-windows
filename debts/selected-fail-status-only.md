# A failed preview shows only in the status line

Decision: none (board preview). Found at d2ee88e. Recorded 2026-11-20 16:39 CST. Line numbers are at d2ee88e.

`pfail` is set when a scene's preview fails (app.html:1014) and cleared when one succeeds (app.html:1010). The render never reads it. A failed preview of the selected scene shows only in the status line, as on main before PR 63. The page self-test reads it at app.html:3391.

Harm: the board shows no failed state, so a failed preview of the selected scene is easy to miss.

Likelihood: unmeasured.

Recovery: none in the code. The user reads the status line.

Fix: draw a failed state on the selected scene's board from `pfail`. Write a red case first: a failed preview of the selected scene shows a board message.
