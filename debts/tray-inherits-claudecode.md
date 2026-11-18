# Tray started from an agent shell stays guarded

Decision: live-move-guard. Recorded 2026-11-17 18:32 CST, from the 18:22 CST coordinator ruling.

`install.ps1` starts `tray.ps1` with `Start-Process`. A process started from an agent shell inherits `CLAUDECODE`. So the live-move guard refuses the tray's live applies.

Recovery: the owner restarts the tray from his own session.
