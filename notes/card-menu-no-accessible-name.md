# The card menu has no accessible name

Decision: monitor setups. Recorded 2026-11-17 22:14 CST.

`placeMenu` builds `#cmenu` with `role="menu"` and no `aria-label` or `aria-labelledby`, so the menu has no accessible name.
