# First-run config.json copies appNames that nothing reads

Decision: none (config). Found at d2ee88e. Recorded 2026-11-20 16:39 CST. Line numbers are at d2ee88e.

On a first run, the starters text is written to config.json (config.ps1:116), and that text holds an appNames map. Get-TileAppNames reads appNames from the starters file only (config.ps1:124). The copy in config.json is never read.

Harm: a user who edits the map in config.json sees no change.

Likelihood: every first run writes the copy.

Recovery: edit the map in scenes.json.

Fix: stop writing appNames into config.json, or read it from there. Write a red case first: a first run's config.json holds no appNames.
