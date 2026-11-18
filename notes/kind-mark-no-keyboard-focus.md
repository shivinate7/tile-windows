# The kind mark cannot be reached by keyboard

Decision: monitor setups. Recorded 2026-11-18 12:21 CST.

The kind mark in `app.html` (`kmark` in `renderRail`) is a `span role="img"` with no `tabindex`, so it takes no keyboard focus. The card's pick button name omits the kind, because the mark sits in `.crow`, outside that button. The hidden ", edited" text in the mark's `.vh` span is inside `role="img"`, so it is never read.
