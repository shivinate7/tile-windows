# Autosave writes the saved layout with no notice and no Undo

Decision: undo from an automated act's notification (`run-undo`), and item 8 of the monitor setups record (`monitor-setups`). Found at d15a42c. Recorded 2026-11-23 13:15 CST. Line numbers are at d15a42c.

Each board edit is written at once for the plugged-in setup. `layoutEdited` (app.html:1663) and `saveLayout` (app.html:1668) post the layout with no Save click, and the write shows no notice. The only Undo is the header button (app.html:705), which steps back the open page's own board edits. Item 8 says "Undo is the way back" (owner, 2026-11-17 11:38 CST). A failed save shows "Not saved" with "Undo still works" (app.html:1081). That is a message on failure, not a notice on success.

The write also changes more than the owner's edit. On the autosave path, `stripIds` (app.html:3237) drops handles, and one path retitles a closed bay entry from another app's window. That bug has its own debt, `autosave-bay-retitle-by-handle`.

Harm: a saved layout changes with no notice. The owner finds out only by looking.

Likelihood: unmeasured. It runs on every board edit.

Recovery: the header Undo, in the open page only. Refresh clears it (app.html:704).

Fix: the owner rules first, as the Open item in `run-undo` asks. For a write the owner did not make, such as a closed entry's change, show a notice with Undo that restores the entry. Write a red case first: a closed bay entry whose handle now belongs to another app's window, then an autosave, then check that a notice with Undo shows and restores the entry.
