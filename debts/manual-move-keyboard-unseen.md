# Manual-move guard misses a keyboard move outside window and activity scenes

Decision: live-move guard (`live-move-guard`). Found at f55111d. Recorded 2026-11-20 16:39 CST, narrowed 2026-11-20 21:42 CST. Line numbers are at f55111d.

The end-of-move hook sets `MoveEndTicks` at tray.ps1:596-597 (EVENT_SYSTEM_MOVESIZEEND). A window moved by keyboard shortcut, Win+Arrow or snap assist sends no such end, so the hook misses it. The rect compare (tray.ps1:242-248) catches the miss: a rect change on two reads counts as a manual move. But the window read that feeds the compare, `$sig.wins` (tray.ps1:841), runs only while a window or activity scene is on (tray.ps1:833-834). For a scene on any other trigger (desk, call, size, setup, gaps, noext, schedule), no manual move is counted, so an automatic apply moves the window back. The mouse-button check still holds while a button is down.

Harm: an automatic apply from those triggers moves that window back.

Likelihood: unmeasured.

Recovery: none in the code. The user moves the window again.

Fix: read the window rects for every trigger that can apply, or hook the location change. Write a red case first for each trigger above: move a window by keyboard, run an automatic apply, and check the window stays.
