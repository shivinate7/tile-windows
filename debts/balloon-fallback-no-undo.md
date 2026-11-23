# A run or gap fill shows a balloon with no Undo

Decision: undo from an automated act's notification (`run-undo`). Found at 9b60ed8. Recorded 2026-11-23 14:56 CST. Line numbers are at 9b60ed8.

A run or gap fill that moves windows shows a balloon with no Undo button in two cases.

(a) No Start shortcut exists. `Repair-ToastShortcut` (tray.ps1:379) fixes the app id on a shortcut that exists. It never creates one. `Test-ToastReady` (tray.ps1:375) then fails. `Apply-Scene` (tray.ps1:745) logs "Undo is not offered: no Start shortcut gives the toast the app name." (tray.ps1:771) and returns before it keeps a run record. `Invoke-GapFill` (tray.ps1:709) logs "Undo is not offered." (tray.ps1:723).

(b) The toast throws. `Apply-Scene` keeps the run record, then shows the balloon with `Note $msg` (tray.ps1:778). Its log has no "Undo is not offered" line. `Invoke-GapFill` logs it (tray.ps1:738).

The balloon has no button, so nothing in the UI reaches the kept record.

Harm: a scene run or gap fill moves windows, and the owner has no notification with Undo.

Likelihood: unmeasured. Case (a) needs the Start shortcut to be missing. install.ps1 creates it (install.ps1:86). If it cannot set the app id, it warns (install.ps1:88). Case (b) needs the toast call to throw.

Recovery: none in the code. The owner moves the windows back by hand.

Fix: log case (b) the way case (a) logs it. Write a red case first: a run whose toast throws, then check that its log line says Undo is not offered. Whether the tray should recreate a missing Start shortcut is an owner question. The comment at tray.ps1:378 says it never does.
