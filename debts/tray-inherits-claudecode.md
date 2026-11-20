# Tray started from an agent shell stays guarded

Decision: live-move-guard. Recorded 2026-11-17 18:32 CST, from the 18:22 CST coordinator ruling.

`install.ps1` starts `tray.ps1` with `Start-Process`. A process started from an agent shell inherits `CLAUDECODE`. So the live-move guard refuses the tray's live applies.

A tray started by `install.ps1` through WMI (README, "Reinstall from a commit (Claude sessions)") does not inherit the agent's environment, so it avoids this. Measured on this machine 2026-11-20 10:31 CST: it applied a scheduled scene live (moved 7 windows), so it did not carry `CLAUDECODE`. The debt stays for a plain run from an agent shell.

Recovery: the owner restarts the tray from his own session.
