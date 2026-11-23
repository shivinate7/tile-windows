# A config read turns off a scene's setup switch with a note only

Decision: undo from an automated act's notification (`run-undo`). Found at d15a42c. Recorded 2026-11-23 13:15 CST. Line numbers are at d15a42c.

Every config read passes through `Update-TileSetupSwitch` (config.ps1:75, called from `Get-TileConfigText` at config.ps1:110). If the text still holds the old "Use This Scene for This Many Screens" switch, it removes that switch from each scene that had it on, saves the file, and adds a note (config.ps1:88-89). The note shows in the page header and as a tray balloon. The Forget cascade (serve.ps1:199-200) also turns a switch off, but it follows the owner's own Forget, so it has no debt.

Harm: a scene's trigger is off after the read. The owner learns of it from a note only, and the old switch value is gone.

Likelihood: unmeasured. It runs only on a config that still holds the old switch.

Recovery: the owner picks a setup for the scene under Use This Scene on This Setup. The old switch value is not kept.

Fix: keep the removed switch value, and offer a notice with Undo that restores it. Write a red case first: a config with the old switch on, one read, then check that a notice with Undo shows and restores the switch.
