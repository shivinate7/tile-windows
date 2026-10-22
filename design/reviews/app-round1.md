# App design review, round 1

Commit seen: 3bd4ef1. Screens: app.html at 1440 and 1024, light and dark, sample data (`serve.ps1 -From test/fixture.json`).
Reviewers were blind to the mockups and decisions. A = Vercel guidelines + house checklist. B = impeccable lenses (manual; the skill call was refused).

Sort: FIX = plain defect or agrees with mockups B/C. CLASH = conflicts with the design records (owner decides).

| # | By | Finding | Sort |
|---|---|---|---|
| 1 | A, B | 1024: monitor labels clipped ("1536×", "12…"); Portrait flush against Ultrawide; tiles about 60px, titles truncated | FIX |
| 2 | B | Canvas undersized at 1440; lower half empty; help text wider than the monitors | FIX |
| 3 | A | Process ids in view: tile chips (`claude`, `ms-teams`), "Not open: olk", raw titles in the "No free cell" note | FIX (mockups use app names and short codes) |
| 4 | A | Inspector note names `tile.ps1 -Default` | FIX |
| 5 | A, B | Dry-run state is a small pill; Apply still says "10 moves" | FIX (say "Preview" in dry run) |
| 6 | B | Header Apply and scene-card Apply: same word and style, different acts | FIX |
| 7 | B | Tiles do not show category colour; pinned and filled tiles look alike | FIX (mockup B colours tiles by category, marks pins) |
| 8 | A | Disabled Save, Revert, Delete give no reason on the control | FIX |
| 9 | A | No h1, no main landmark | FIX |
| 10 | A | Buttons 20 to 30px tall; no coarse-pointer sizing | FIX |
| 11 | A, B | Muted note text and dark disabled Delete near or below contrast floor | FIX |
| 12 | B | Save enabled in dark shot, disabled in light shot, same "Saved" state | FIX (check state logic) |
| 13 | B | "Built-in" and "Custom" tags look like buttons | FIX |
| 14 | B | Inspector: empty Window panel first, radio group unlabelled, heading levels uneven | FIX |
| 15 | B | "Save as new" appears twice | FIX |
| 16 | B | One blue marks action, selection, toggle and info | FIX |
| 17 | A | Laptop monitor empty box has no words | FIX |
| 18 | A | Show grid is a toggle labelled as an action; theme button is icon-only | FIX |
| 19 | A | Delete dialog focuses first input or primary, not Cancel | FIX |
| 20 | A | Apply result shows in a footer out of view | FIX (show the result at the button) |
| 21 | B | Default scene thumbnail weighted bottom-right | Polish, FIX if cheap |

No clashes with the design records.
