# A scene run shows a balloon with no Undo when no toast can show

Decision: undo from an automated act's notification (`run-undo`). Found at d15a42c. Recorded 2026-11-23 13:15 CST. Line numbers are at d15a42c.

`Apply-Scene` (tray.ps1:692) shows the run toast, with its Undo button, only when `Test-ToastReady` passes (tray.ps1:356). That check needs the Start shortcut to carry the app id. When it fails, `Apply-Scene` calls `Note` and returns (tray.ps1:717). It returns before it keeps the run record (`$script:runUndo`), so no Undo exists for that run, and no link can undo it. When the toast throws, the record is kept, but the balloon (tray.ps1:723) has no button. The balloon is the coordinator pick of 2026-11-12 16:07 CST in `run-undo`, which the 2026-11-23 ruling overrides. Every scene apply goes through this function: schedule, monitor change, call start and end, desk, window, activity, size, gaps, noext, grid, and the offer's click.

Harm: a scene run moves windows, and the owner has no notification with Undo.

Likelihood: unmeasured. It needs the Start shortcut to lack the app id, or the toast to throw. install.ps1 warns when it cannot set the id.

Recovery: none in the code. The owner moves the windows back by hand.

Fix: repair the app id on the Start shortcut at each tray start, so the toast path holds. Keep the balloon only as a last resort, and have its log line say that Undo is not offered. Write a red case first: a Start shortcut with no app id, then a scene run that moves a window, then check that a toast with Undo shows and that Undo puts the window back.
