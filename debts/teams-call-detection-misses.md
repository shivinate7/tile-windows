# Teams call detection misses some calls

Decision: scene triggers (`triggers`). Found at d2ee88e. Recorded 2026-11-20 16:39 CST. Line numbers are at d2ee88e.

`Test-TeamsCall` reads the microphone privacy store (tray.ps1:38). It falls back to window titles only when the store cannot be read (tray.ps1:39), and then matches only "Meeting with ... | Microsoft Teams" or "Call | Microsoft Teams". It misses: microphone access off for desktop apps; a call joined muted from the start in some builds; Teams in a browser; other call window titles; non-English Teams. A start or end needs two readings 3 s apart, so a scene lags a call by up to 6 s.

Harm: a call scene does not fire.

Likelihood: unmeasured.

Recovery: none in the code.

Fix: write a red fixture for each miss named here, then widen the detection to cover it.
