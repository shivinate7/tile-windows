# App design review, round 2

Commit seen: 76b7bd7. Same screens and method as round 1. B ran the impeccable skill (audit, critique; single context).

| # | By | Finding | Sort |
|---|---|---|---|
| 1 | A, B | Text under 11px: tile body 10.5px, tile tag 10px, rail labels 10.5px | FIX (11px floor, 12px body) |
| 2 | A, B | Grey "Other" chips and muted helper text near the contrast floor in light | FIX (measure, then raise) |
| 3 | B | Amber Preview button blends into the amber dry-run bar in light | FIX |
| 4 | A, B | Coarse-pointer sizing misses trigger radio rows, monitor-name buttons, day buttons, Preview and stepper buttons | FIX |
| 5 | B | 1024: board starts about 250px down, large empty space below it; at 1440 lower 40% empty | FIX (scale the board to its pane) |
| 6 | B | Inspector reads as one column; group gap equals row gap; section labels same weight as field labels | FIX |
| 7 | B | Save as new, Revert, Delete wrap raggedly; Delete orphaned; destructive looks neutral | FIX |
| 8 | B | "No free cell" outcome styled like help text | FIX |
| 9 | B | Header crowded; Saved and Dry run pills repeat the banner | FIX |
| 10 | B | Dark: Browse orange and Other grey tiles hard to tell apart | FIX |
| 11 | B | Scene card text clips at 1440 | FIX |
| 12 | A | Undo disabled with no reason | FIX |
| 13 | A | One act, two names: Preview / Apply / "click Apply" | FIX (one verb per act) |
| 14 | A | Footer status off screen at 1440; answer not at the press | FIX |
| 15 | A | Selected monitor and selected tile share one outline | FIX |
| 16 | A | No meta theme-color; no skip link; inputs lack name/autocomplete; placeholders lack "…" | FIX |
| 17 | A | Button labels not in Title Case | CLASH: mockups and house style use sentence case. Owner decides. |
| 18 | B | "System" theme button with half-circle icon is ambiguous | FIX |
