# A name typed before a redraw may not save

Decision: monitor setups. Recorded 2026-11-17 23:10 CST.

mgRender restores typed text with a script value set. A script value set fires no change event, so
a name typed before a redraw may not save. Unverified.
