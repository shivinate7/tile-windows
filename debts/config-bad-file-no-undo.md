# A config that does not parse is moved aside with a note only

Decision: undo from an automated act's notification (`run-undo`). Found at d15a42c. Recorded 2026-11-23 13:15 CST. Line numbers are at d15a42c.

When config.json does not parse, `Get-TileConfigText` (config.ps1:107) moves it aside with `Set-TileBad` (config.ps1:32, called at config.ps1:112), and the starter scenes take its place. The note reads "the starter scenes are back" and names the old file. The live config loses the owner's scenes, setups and layouts. The .bad copy keeps them. There is no Undo. A state.json that does not parse is moved aside the same way (config.ps1:150), but it loses only the recent log, so it has no debt.

Harm: the owner's scenes and layouts leave the live config, and a note is the only notice.

Likelihood: unmeasured. A config that does not parse is rare.

Recovery: manual. Copy the .bad file back over config.json. The note names the file.

Fix: offer a notice with Undo that copies the .bad file back and moves the starter config aside. Write a red case first: a config that does not parse, one read, then check that a notice with Undo shows and restores the owner's scenes.
