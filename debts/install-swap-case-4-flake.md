# Install-swap case 4 failed once under load

Decision: none (install). Found at d2ee88e. Recorded 2026-11-20 16:39 CST. Line numbers are at d2ee88e.

Case 4 (the tray.pid wait) has a margin of about 5 s. The holder lets go 24 s after the install starts (test/install-swap.ps1:52, :317). With the wait, the install's retry gets through by about 29 s (test/install-swap.ps1:303-304). Case 4 failed once under load on 2026-11-17 and passed on rerun. The cause is not found.

Harm: a red suite run on a correct install.

Likelihood: seen once, on 2026-11-17, under load.

Recovery: a rerun passed.

Fix: find the cause of the slow path under load before widening the margin.
