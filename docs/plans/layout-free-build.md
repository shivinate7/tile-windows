## layout-free-build

**Status.** L0 (PR 45, golden layouts), L1 (PR 46, finer grid), L3 (PR 50, free areas) and L5b (PR 43, gap watch) are merged. L2, L4 and L5a are not built. The four owner questions are open, asked 2026-11-18 11:15 CST (keys S, G, K, M, at the end).

**Source.** The Plan agent's build plan (opus), revised after a refuter, 2026-11-18 11:20 CST. It was first checked against origin/main 9e6ae0a. The symbols that replace its line numbers were checked against origin/main b6bc537 by 2026-11-18 11:23 CST. Its other claims, such as the columns cap of 8 and the span stepper following `g.c`, were not re-checked. Main has no docs/map/.

**Terms.** A lane is one build unit, L0 to L5b. Each lane merges alone. "Item N" means item N of `docs/design/mockups/layout-free-notes.md`. Item G is the gap rule below. Questions 1 to 4 are at the end.

**Tests.** Tests use only `-DryRun`, `-From`, or `-GapFill` with `-DryRun`, so no test moves a real window.

One fact drives L1. On the 1365px test area, five columns are 273px wide (`[int](1365/5)`), but ten columns are 2×136=272px. A plain 10×2 grid would shift column 4 by 4px, so "nothing else moves" would fail.

**L0. Freeze today's rects** (test only, already its own lane; no designer)
- New `test/golden-layouts.ps1`, wired into `test/run.ps1`.
- Freezes the `-Scene -Json -DryRun` rects of every starter scene and the fixture at 1365×1001, 3440×1392, 1080×1872 and the fixture's 4096×1680.
- A page check: `cellRect` in `app.html` gives the engine's rects on the same areas, including one grid with `mult`. The `mult` case stays red until L1 and L2 land.
- Every later lane must keep L0 green.

**L1. Engine: finer grid** (`tile.ps1`; no designer; needs L0)

Status: built in PR 46 (finer grid), merged at commit fce4790. Its engine and red cases were on branch `finer-grid`, at head commit 37a94e0.

- New `grids[mon].mult:[mx,my]`: cell edges come from the base grid, and each base cell is then divided.
- New `fill.unit:[ux,uy]`: each filled window gets one aligned block of cells.
- Tests first:
  - after a split, every other window's rect equals L0 on all four areas;
  - the two halves tile the old cell with no 1px gap;
  - with `unit [2,1]`, filled windows take slots 2k and 2k+1;
  - zones and held cells work on doubled slots;
  - with no `mult`, the output is exactly today's.

**L2. Page: Split Cell** (`app.html`; designer yes; needs L1)
- `cellRect` learns `mult` and reuses `bround`, which rounds half to even as `[int]` does in `Pass` (136.5 becomes 136). It takes each edge from `EdgeX` and `EdgeY` in `Pass`, not from span times sub-width. Base step: `bround(m.w/g.c)`. Sub-step: `bround(base/mx)`. Edge: `floor(i/mx)*base + (i%mx)*sub`. A window's width is its end edge minus its start edge. Span times sub-width puts base column 1 at 272 px on 1365 px; the engine puts it at 273. Rows work the same with `my`, `r` and `h`. The L0 `mult` case turns green.
- A pure `splitLayout()` keeps the base `c` and `r` and sets `mult`. A 5×2 board split side by side posts `c` 5 and `mult` [2,1], not `c` 10. A stacked split posts `mult` [1,2] (5×2 becomes 5×4). The engine doubles the slots from `mult`, as `test/golden-layouts.ps1` on branch `finer-grid` posts it. It remaps every pin, zone and held entry, and sets `fill.unit`.
- The columns cap of 8 rises to a proposed 24. The rows cap of 4 rises to a proposed 8, so a stacked split is possible. The span stepper already follows `g.c`, so it needs no change.
- Ways in:
  - S, a right-click (the browser's own menu is suppressed) and an inspector button open the "choose how" menu.
  - Selecting an empty cell is new (notes item 2).
  - `splitFast(sel)` ships with no trigger until question 3 (key K).
  - J joins the halves.
- While question 1 (key S) is open, the menu offers halves only: direction, and which half the window keeps. The bar snaps to the middle only.
- Edits autosave through `POST /layout` (in `serve.ps1`), with a Drop Note and Undo.
- Tests (`#selftest-split`):
  - 5×2 becomes 10×2 and 2×4 becomes 2×8 with every slot remapped;
  - the split window is pinned (item 5);
  - a locked tile cannot split;
  - one `POST /layout` per split;
  - item 11's cases (a stacked tile, a zone cell, a held cell);
  - item 6: an empty half fills only after every whole block.
- The L2 designer owns:
  - rewriting notes items 5–13 for Finer Grid;
  - item 6 (the empty half fills last, and Keep This Half Empty);
  - item 11 (the split cases);
  - the fast action's look;
  - the 27px halves at 1024 wide;
  - the right-click menu.

**L3. Engine: Free Layout areas and item G** (`tile.ps1`; no designer; after L1, since both edit the `Pass` function)

Status: built in PR 50 (free areas), merged at commit 74f87cb.

- `layouts[key].grids[monId].free.areas`. Each area is a rect in fractions, plus a pin, an app and title, or nothing.
- Each line is rounded once, so neighbours share a pixel.
- The fill takes empty areas in reading order. Zones pause (item 26).
- A pure `Get-CollapsedAreas($areas,$absent,$locked)` follows item G.
- Tests: areas built from a grid give L0 exactly, so switching on moves nothing. Item G's cases below.

**Item G. Who takes a closed or minimized window's space** (in L3; used by L5a and Close Gap)
- A side qualifies when its neighbours exactly cover the gone window's edge: none sticks out past it, none is locked, and they leave no hole. A side also needs a share that leaves no overlap with a live area.
- If left and right both qualify, they meet at the midpoint. Otherwise, if above and below both qualify, they meet at the midpoint.
- Otherwise the first single side that qualifies takes it all, in the order of notes item 17 (left, above, right, below). When one side cannot take the region, the next side in that order does.
- If a midpoint share would leave a window under 400×300, or would overlap a live area, the whole space goes to the first side that qualifies.
- If no side can take it (a pinwheel centre, or only locked neighbours), the space stays a dashed gap.
- Close Gap calls the same function. When no side can take it, Close Gap is off and says why (item 17).
- The result is worked out at apply time and never saved, so a restored window gets its saved rect back.
- Tests:
  - a middle column's space is split by its left and right neighbours;
  - two stacked halves on one side both grow;
  - with a locked left neighbour, the right side takes it all;
  - a pinwheel centre stays a gap;
  - restore gives back the saved rects;
  - two neighbours gone at once give the same result in either order.

**L4. Page: Free Layout** (`app.html`; designer yes; needs L2 and L3)
- A switch in the Monitor section, and the F key.
- A plain drag moves only the grabbed row's edge segment. Shift-drag moves the whole column line (the `edges-drag` caption, notes item 16).
- Size floor 400×300.
- Back to Grid popover, with Snap to Cells as the default.
- Split cuts the selected area. Edits autosave.
- Tests (`#selftest-free`):
  - switching on changes no rect;
  - a plain drag moves one segment only;
  - Shift moves the line in every row;
  - a drag stops at the floor;
  - no drag opens a gap;
  - snapping lands every edge on a cell line;
  - on a 1×1 monitor the switch is off with item 15's reason.
- The L4 designer owns:
  - item 19, Shift+arrows: in Free Layout they move lines by 1/48 of the monitor, against today's whole-cell resize. Which one wins where.
  - item 15, the switch on a 1×1 monitor;
  - Shift-drag across a locked row (item 18);
  - whether the board shows a gone window's space as lent.

**L5a. Engine: gap-fill run** (`tile.ps1`; no designer; needs L3)
- Red test first: `-GapFill` is added to the live-move guard `if` in `tile.ps1`, under its `# Live-move guard` comment. Under TILE_TEST_SUITE or CLAUDECODE it is refused unless `-DryRun` or TILE_TEST_ALLOW_LIVE=1 is set.
- `-GapFill -Absent <ids> -Last <json>` applies item G to the active scene.
- A window moves only if it sits at its scene rect, or at the last rect the tray gave it (`-Last`), so neighbours shrink back on restore. A window the owner moved by hand stays put.
- No new window is pulled in. Windows That Stay Put are untouched. The saved layout is never written.
- Tests: the guard refusal; a hand-moved neighbour stays put; a restore shrinks neighbours from their last rect; no new window is pulled in.

**L5b. Tray: close and minimize hook** (`tray.ps1`; no designer)

Status: built in PR 43 (the gap-watch pull request), merged at commit ee47541. Until lane L5a lands, gap-fill only logs.

- `tray.ps1 -Lib` returns at its `if ($Lib) { return }` line, before the `TileInput` class. So the pure parts live in PowerShell above that line, where `-Lib` tests reach them:
  - `Test-GapEvent` (the filter);
  - `Step-GapFill` (state plus events in, a GapFill run or nothing out).
- A new type, `TileWinWatch1`, defined after the `-Lib` return; `TileInput`'s text stays as it is.
  - It hooks 0x8001, 0x8002, 0x8003, 0x0016 and 0x0017, out of context and skipping its own process.
  - Its callback keeps only idObject=0 and idChild=0 for a handle in a static tiled set, which the tray sets after each apply. It drops everything else in C# and records the handle and event with a time.
- The existing 1 s tick reads that record, as it reads MoveEndTicks. There is no new timer, so the space is taken up to 1 s after the event.
- Hook cost: Windows sends every create, show and hide event in the session to the tray's thread, often hundreds a second. Each costs one C# call, two compares and one set lookup under a lock; PowerShell never sees them. Only a tiled handle's last event is stored, so the store is bounded by the tiled set. The existing 1 s tick drains it. No polling, no new timer. The tray's own process is skipped.
- Tests:
  - an untiled handle does nothing;
  - a burst in one tick gives one run;
  - an event within N ms of the tray's own apply is ignored;
  - no toast, the run-undo record is unchanged, one log line;
  - Free Layout monitors only, until question 2 (key G).

**Order**
- L0 first.
- Then in parallel: the L2 and L4 designers, L1, and L5b against a stubbed engine.
- L3 and L2 follow L1. L4 follows L2 and L3. L5a follows L3.
- Gap-fill switches on only when L5a and L5b are both in.
- One builder at a time on `tile.ps1`, and one on `app.html`.

**Risks**
- The notes' save shape (`grids.wide.free`, scenes version 4) is stale. Layouts now live per setup, and config is already version 4. The new fields add to the layout without a version bump. An older engine ignores them and moves windows by the grid.
- A tray started from an agent shell is refused live moves (`debts/tray-inherits-claudecode.md`).
- Apps with their own minimum size can break a shared line.
- Apps that hide to the tray rely on event 0x8003.

**Questions for the owner**

Status: all four are open, asked 2026-11-18 11:15 CST. Keys S, G, K and M name questions 1 to 4 in order.

1. **Key S, share.** A 1/3 or 2/3 share needs a tripled grid, and quarters or a second split need ×4. Allow those, or halves only? Departs from: decision `layout-free`, 2026-11-17 19:09 CST ruling ("doubles"), and notes items 1 and 10. Status: open.
2. **Key G, gap-fill scope.** Does live gap-filling apply to plain grid scenes, or only to Free Layout boards (the default above)? Departs from: the constraint that existing grid scenes keep working unchanged. Status: open.
3. **Key K, fast-split trigger.** What triggers the fast split? Proposed: Shift+S, or a double-click on the selected tile, splits it in half along its longer side. Departs from: decision `layout-free`, open item (c). Status: open.
4. **Key M, midpoint share.** When both opposite sides qualify, should they share the space at the midpoint (item G)? Departs from: decision `layout-free`, 2026-11-18 11:08 CST ruling (state `tree-gap` joins Shared Edges, and the neighbours grow into the space at once), and notes item 21 (Splitter Tree), where the one sibling takes the space. Status: open.

**Critical files for implementation**
- `tile.ps1`
- `app.html`
- `tray.ps1`
- `test/run.ps1`
- `test/golden-layouts.ps1` (new, L0)
