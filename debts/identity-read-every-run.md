# Every scene run reads monitor identity

Decision: monitor setups (`monitor-setups`). Found at d2ee88e. Recorded 2026-11-20 16:39 CST. Line numbers are at d2ee88e.

A scene run calls `Get-Screens` with `-Identity` (tile.ps1:523), so every `-Scene` or `-Default` run reads monitor identity first, not only after a display change.

Harm: each scene run adds about 0.7 s.

Likelihood: measured once, 637-739 ms over 3 samples of a whole -Monitors run. Not re-measured.

Recovery: not a fault. None needed.

Fix: read identity only when the monitor set has changed. Measure a scene run before and after.
