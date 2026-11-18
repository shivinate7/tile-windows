# Identity read runs on every scene run

Decision: monitor setups. Recorded 2026-11-17 16:52 CST.

Every `-Scene` or `-Default` run now reads monitor identity first (tile.ps1:259-260), so the cost is paid on each scene run, not only on a display change.

The builder measured a whole `-Monitors` run at 637-739 ms over 3 samples. Not re-measured here.
