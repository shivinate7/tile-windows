# Save As New drops closed windows' Stay Put and held entries

Decision: bay list (`bay-list`). Found at f55111d. Recorded 2026-11-20 21:42 CST. Line numbers are at f55111d.

Save As New (`saveAsNew`, app.html:3246) builds the copy in two ways. In id mode it copies the saved scene with `layouts` set to `{}`. The layout keys are grids, pins, zones, fill and bay (app.html:966), so the copy loses its bay and held entries, open windows' too. Outside id mode it runs `stripIds(clone(cur))` with no `all` flag. `stripIds` keeps a bay or held entry only when its window is open (app.html:3233-3234), so a closed window's Stay Put or held entry is dropped. Save (app.html:3236) and autosave (app.html:3237) pass `all` and keep them.

Harm: on reopen the window rejoins the fill, and an automatic apply can move a window the owner kept.

Likelihood: unmeasured.

Recovery: none in the code. The owner adds the window back to Stay Put by hand.

Fix: keep closed windows' entries in the copy in both modes, as Save and autosave do. Write a red case first: Save As New with a closed Stay Put window, in id mode and outside it, then open the copy and check the entry is there.
