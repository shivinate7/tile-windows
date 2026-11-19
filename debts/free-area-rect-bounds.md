# Free-area rects accept zero and off-screen sizes

Decision: layout free (`layout-free`). Found in tile.ps1 at commit 74f87cb (PR 50, the free-areas pull request). Recorded 2026-11-18 16:29 CST. Line numbers are at 74f87cb.

`Resolve-FreeAreas` (tile.ps1:196) keeps an area when its rect has four finite numbers and a width and height above 0 (tile.ps1:201-204). It checks nothing else. `Get-AreaPixelRects` (tile.ps1:183-191) rounds each edge to whole pixels (:186-188). `Pass` passes the pixel rect to `Move-Win` as it comes (:646, :658). `Move-Win` (tile.ps1:164-175) sends the size to `MoveWindow` with no clamp. It warns only after the move, when the window ends more than 20 px from the size asked for (:174-175).

Checked by reading the code, not by a run. Rounding checked in PowerShell on a 1365 px screen:
- A width of 0.0002 at x 0 rounds to 0 px, so the window gets w=0.
- An area at x 0.9 with w 0.5 gets x=1228 and w=683. It ends at 1911 px, past the 1365 px edge.

Harm: a window sent at zero width, or placed partly off-screen.

Likelihood: unmeasured. No page sends free areas yet (app.html has no Free Layout), so only a hand-edited scene can reach it today.

Recovery: none in the code. `Move-Win` only warns, after the move (tile.ps1:174-175).

Fix: in `Resolve-FreeAreas`, require each edge in 0 to 1, x + w <= 1 and y + h <= 1, and at least 1 px wide and high after rounding. Write a red case for each example first.
