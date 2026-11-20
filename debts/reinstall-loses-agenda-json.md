# A reinstall loses agenda.json

Decision: scene triggers (`triggers`). Found at d2ee88e. Recorded 2026-11-20 16:39 CST. Line numbers are at d2ee88e.

`agenda.json` lives in the app folder, and tray.ps1:821 reads it from there. A reinstall renames the new app into place and removes the old folder (install.ps1:60-65), so the file is gone until the morning task writes it again.

Harm: the meeting-size, gap and offer triggers do nothing until the next write.

Likelihood: unmeasured.

Recovery: the morning task writes agenda.json again.

Fix: keep agenda.json across a reinstall, for example by holding it outside the app folder. Write a red case first: install over a folder that holds an agenda.json, then check the file is still there.
