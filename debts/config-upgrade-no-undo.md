# A config upgrade adds starter scenes with no notice

Decision: undo from an automated act's notification (`run-undo`). Found at d15a42c. Recorded 2026-11-23 13:15 CST. Line numbers are at d15a42c.

When a config's version is below the starter version, `Update-TileConfig` (config.ps1:51) runs on the next read. It adds each starter scene with a newer `since` that the config lacks (config.ps1:56), adds missing fields (config.ps1:58-59), and saves config.json (config.ps1:67). It changes no value a scene already has, and each added scene's switches start off. The owner gets no notice and no Undo.

Harm: a scene the owner did not make appears in their list after an upgrade, with no notice.

Likelihood: unmeasured. It runs once per version bump.

Recovery: the owner deletes the scene by hand.

Fix: offer a notice with Undo that names the added scenes and removes them on a click. Write a red case first: an old-version config, one read, then check that a notice names the added scenes and that its Undo removes them.
