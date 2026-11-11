# App design review, round 3 (final)

Commit seen: 4894ec3. Same method as rounds 1 and 2. B's `impeccable detect` was refused by a hook, so its scan is unknown.

Round 3 is the last round. Open findings go to `debts/notes.md` (debts if Claude is likely to hit them in normal work, notes otherwise).

| # | By | Finding | Where it goes |
|---|---|---|---|
| 1 | A | Footer "Stop Server" stops the server with no ask and no undo | Debt: next lane adds an ask |
| 2 | A | Undo's disabled reason is hover-only | Note |
| 3 | A, B | 1024: tile labels clip ("PowerP…"); email breaks mid-word | Note: bay lane reworks tiles |
| 4 | B | 1440: Categories legend and Window section below the fold | Note |
| 5 | B | Permanent amber dry-run bar competes with the "No free cell" note | Note: bay lane replaces that note |
| 6 | B | Black outline means selected monitor, bezel and selected scene | Note |
| 7 | B | "Applies itself", "Theme: Match Windows" unclear; built-in note said twice | Note |
| 8 | B | Dark: saturated Chrome orange louder than the primary action | Note |
| 9 | B | Hit targets 26 to 32px with a mouse | Note (desktop tool; 44px under coarse pointer) |
