# Drag pin matches the full title when the app has several windows

Decision: fill controls (`fill-controls`). Found at d2ee88e. Recorded 2026-11-20 16:39 CST. Line numbers are at d2ee88e.

`matchFor` (app.html:1664) gives a pin made by dragging the window's full title when its app has more than one open window. A browser tab whose title changes then stops matching, and the pin silently stops placing the window. The inspector's "Title contains" field widens the match.

Harm: a pinned window is no longer placed after its title changes, and nothing says so.

Likelihood: unmeasured.

Recovery: widen the match by hand in the inspector's "Title contains" field.

Fix: match a drag-made pin on the app and the stable part of the title, not the whole title. Write a red case first: two windows of one app, then one title changes.
