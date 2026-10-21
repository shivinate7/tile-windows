# Undo moves windows

**Question.** After a live Apply in the sandbox, should Undo move only the boxes, or also the real windows?

**Ruling.** Undo moves the real windows back at once. It sends the previous rects to `/apply` and shows per-window results, as Apply does. Undo before any Apply only resets the boxes.

**Date.** 2026-10-21

**Why.** The owner wants a one-click restore.

**Check.** `test/run.ps1`: "Apply then Undo sends the original rects".
