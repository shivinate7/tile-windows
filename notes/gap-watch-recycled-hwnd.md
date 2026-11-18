# A recycled window handle stays tiled

Decision: layout free (`layout-free`). Recorded 2026-11-18 12:35 CST. Line numbers are at commit ee47541.

The tray replaces the tiled set after each apply (`Set-GapWatch`, tray.ps1:481-485) and clears it only in `Clear-GapWatch`. Between applies, the hook keeps every event on a handle in that set (tray.ps1:589). Windows can reuse a closed window's handle. A new window on that handle still counts as tiled until the next apply.

L5a should check that the handle still belongs to the same window before it acts on an event.
