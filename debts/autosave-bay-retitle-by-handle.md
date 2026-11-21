# Autosave retitles a closed bay entry from another app's window

Decision: bay list (`bay-list`). Found at f55111d. Recorded 2026-11-20 21:42 CST. Line numbers are at f55111d.

Autosave saves through `forSaveLayout` (called at app.html:1676, defined at app.html:3237), which calls `stripIds` without the `own` flag. Its bay branch takes each entry's title from `winById(b.id)` whenever that handle is in use (app.html:3233), and does not check that the window belongs to the entry's app. So a closed entry whose handle now belongs to another app's window takes that window's title. Save checks the app (`own`, app.html:3236), so it does not do this.

Harm: the saved bay entry names another app's window, so it no longer names the window the owner put there.

Likelihood: unmeasured.

Recovery: none in the code.

Fix: check the app on the autosave path too, as Save does. Write a red case first: a closed bay entry whose handle now belongs to another app's window, then autosave, and check the title is kept.
