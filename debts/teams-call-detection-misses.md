# Teams call detection misses some calls

Decision: scene triggers (`triggers`). Found at d2ee88e. Rewritten 2026-11-23 15:28 CST at d413b9a (PR 116, browser calls; PR 119, calendar gate).

`Test-TeamsCall` reads the microphone privacy store. A Teams call in Edge or Chrome counts when the browser holds the mic on a Teams meeting title, and stays on while that browser holds the mic. When the store cannot be read, a "Call | Microsoft Teams" window counts, and a "Meeting with ... | Microsoft Teams" window counts only during a Teams event on today's agenda (or always, with no agenda for today). It still misses: microphone access off for desktop apps; a call joined muted from the start in some builds; other call window titles; non-English Teams; and, with the store unreadable, a meeting window for a call not on the calendar. Not yet proven on a live call: background tabs, a meeting window that is not Teams' main window.

Harm: a call scene does not fire.

Likelihood: unmeasured.

Recovery: none in the code.

Fix: write a red fixture for each miss named here, then widen the detection to cover it.
