# A monitor set plugged in adds a setup with no notice

Decision: undo from an automated act's notification (`run-undo`), and items 4, 5 and 7 of the monitor setups record (`monitor-setups`). Found at d15a42c. Recorded 2026-11-23 13:15 CST. Line numbers are at d15a42c.

The page reads the snapshot on load and on Refresh (app.html:942, app.html:956). Each read calls `Add-SnapshotSetup` (serve.ps1:90), which calls `Register-TileSetup` (config.ps1:223) under the lock and saves config.json (serve.ps1:96). It adds each monitor the config does not know, named by its shape, and the setup those monitors make. It writes no note. The page then shows the new setup as following a closest one ("follows ... until you change it", app.html:1085), so the board shows another setup's layout for it. Scene layouts are not written by this path.

Harm: a monitor and a setup appear in the owner's config, and the board shows another layout for the new setup. No notice says so.

Likelihood: unmeasured. It runs each time a monitor set is read that the config does not know.

Recovery: Forget (`Forget-Known`, serve.ps1:174) removes a setup. That is the owner's own act, done by hand.

Fix: show a notice with Undo when a monitor or setup is added. Undo removes only what the add made, and leaves any layout alone. Write a red case first: a snapshot with a monitor id the config does not know, then check that config has the new entry, and that a notice with Undo shows and removes it.
