# An explicit Save drops Stay Put entries for closed windows

Decision: bay list (`bay-list`). Found at d2ee88e. Recorded 2026-11-20 16:39 CST. Line numbers are at d2ee88e.

`stripIds` (app.html:3198-3200) keeps only list entries that match an open window when the owner presses Save. An autosave keeps the closed windows' entries (app.html:3196). So an explicit Save drops the Stay Put entry of a closed window.

Harm: on reopen the window rejoins the fill, and an automatic apply can move a window the owner kept.

Likelihood: unmeasured.

Recovery: none in the code. The owner adds the window back to Stay Put by hand.

Fix: keep closed windows' entries on an explicit Save, as the autosave does. Write a red case first: save with a closed Stay Put window, reopen it, then apply.
