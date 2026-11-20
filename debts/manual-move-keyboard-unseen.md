# Manual-move guard misses a keyboard or Win+Arrow move

Decision: live-move guard (`live-move-guard`). Found at d2ee88e. Recorded 2026-11-20 16:39 CST. Line numbers are at d2ee88e.

The manual-move guard hooks only the end of a move or size (tray.ps1:580-581). A window moved by keyboard shortcut, Win+Arrow or snap assist may not register. The mouse-button check still holds while a button is down.

Harm: an automatic apply moves that window back.

Likelihood: unmeasured.

Recovery: none in the code. The user moves the window again.

Fix: treat a move the hook misses as a manual move, or hook the location change. Write a red case first: move a window by keyboard, run an automatic apply, and check the window stays.
