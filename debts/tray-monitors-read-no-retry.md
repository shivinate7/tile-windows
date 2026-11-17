# Tray does not retry a failed monitor read

Decision: monitor setups. Reported in the monitor-setups build. Recorded 2026-11-17 16:52 CST.

`Read-Monitors` (tray.ps1:500) returns `$null` when `tile.ps1 -Monitors` throws or prints no monitor. `Get-MonitorKey` then returns '' (tray.ps1:27). The tick clears `dirtyAt` before it reads (tray.ps1:623), so no retry is queued. With key '', `Step-Tray` (tray.ps1:194) fires nothing. The next check waits for the next display change.

Harm: a monitor change that lands during the failed read is missed until the next display change. A 'display' scene does not fire for it.

Likelihood: unmeasured. How often the read fails is not measured.

Recovery: the next display change, or a tray restart.

Fix: on a null read, keep the dirty mark so the next tick retries, but stop after a set count. Each retry starts a tile.ps1 run, so the count is the cost, and the record must name it.
