# Wait-Halves returns on the first poll

Decision: layout free (`layout-free`). Found at d2ee88e. Recorded 2026-11-20 16:39 CST. Line numbers are at d2ee88e.

The test helper Wait-Halves (test/setup-page.ps1:3510-3518) returns on the first poll that shows enough halves. A half drawn in a later pass is then missed.

Harm: a page test reads a half as missing and goes red. Rarely.

Likelihood: rare. Unmeasured.

Recovery: none in the code.

Fix: wait for no requests in flight before the first read, as Empty-Select does. Write a red case first: draw a half on a later pass and expect the helper to wait for it.
