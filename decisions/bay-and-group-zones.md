# Overflow bay and group zones

**Question.** How does the owner move windows in and out of the board, and fill many cells at once?

**Ruling (2026-10-22, owner).** Two features, built after PR 2 merges.

1. **Overflow bay.** A tray along the board that holds every window without a cell: overflow from a full grid, minimized windows, and windows the owner takes off the board. Drag a window from the bay onto a cell to place it. Drag a tile off the board into the bay to unplace it. On Apply, bay windows stay where they are (or stay minimized). The bay groups windows by category and shows the app name and title.
2. **Group zones.** Drag across cells to draw a rectangle (for example 4 columns by 2 rows on an 8×2 grid). Give the zone an app or category, such as "Claude". The zone fills with that app's windows in fill order. Then the owner can swap which windows sit in which cell, by dragging from the bay or between cells. Windows that do not fit go to the bay. A zone is saved in a scene as intent (app or category plus cells), so it works as windows change.

**Why.** Moving pieces one by one is slow; the owner wants to block out an area for one kind of window, then fine-tune.

**Open point.** The owner's example said "a 4x4 in an 8x2 grid". An 8×2 grid has two rows, so the zone is read as up to 8 columns by 2 rows. Confirm on the first build.
