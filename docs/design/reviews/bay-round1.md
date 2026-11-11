# Bay and zones design review, round 1

Commit seen: 98605b6. Screens: main, bay full, zone, zone draw; 1440 and 1024; light and dark. A = Vercel + house checklist. B = impeccable lenses by hand (the skill call was refused). No clashes with the design records; all FIX.

| # | By | Finding |
|---|---|---|
| 1 | B | Zone drawing is hidden: only a footer sentence explains it. Needs a visible "Draw Zone" control or first-use hint |
| 2 | A, B | Full bay clips its last row with no scroll cue; at 1024 the bay sits at the fold, so the drop target is nearly off screen |
| 3 | A | 1024: board shrinks to about 45% width; tile text breaks mid-word ("Clau/de") |
| 4 | A, B | "Claude Zone" chip and the "3×2" draw badge cover tile text |
| 5 | A | Selecting a zone pushes Monitor and Columns below the fold |
| 6 | A | Zone drawing and placing a window have no keyboard path on screen |
| 7 | B | No visible drag-over state for the bay or for a swap |
| 8 | B | Empty zone cells look like an empty grid; zone needs a stronger fill and a count on the board |
| 9 | B | Bay cards: "No free cell" and "Not in this scene" share one style; repeated on every card |
| 10 | B | Bay competes with the board; should be quieter |
| 11 | A | "Bay" is jargon; "cells 1, 2, 3, 6, 7, 8" shown as text |
| 12 | A, B | Instruction paragraph is dense; shortcuts bury the main hint |
