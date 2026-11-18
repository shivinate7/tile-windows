# The setup dialog shows the saved native size, not the live one

Decision: monitor setups. Recorded 2026-11-17 23:10 CST.

The inspector and the dialog prefer the saved native size over the live one. Register-TileSetup
writes the native size on first sight only. After a resolution change, the old size shows.
