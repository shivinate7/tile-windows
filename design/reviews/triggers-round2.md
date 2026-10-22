# Triggers design review, round 2

Commit seen: 3405d4e. Screen: the scene inspector's trigger section and the scene rail, 1440 and 1024, light and dark. No clashes with the design records; all FIX.

| # | By | Finding |
|---|---|---|
| 1 | A, B | Schedule days, "At" time and "Go Back" checkbox render once after the last radio, away from the radio they belong to; read as part of the Teams-call option |
| 2 | A, B | Disabled controls (opacity .5) give no reason and fail contrast, worst in dark; unselected radios nearly vanish in dark |
| 3 | A, B | Inline thresholds wrap into 3-4 word columns ("but / not / for"); at 1024 "After a lock of" wraps over three lines |
| 4 | B | 4 radios plus 7 extras, each with a switch, note and inputs; extras sit below the fold under the sticky Save block, which takes about 100px at 1024 |
| 5 | B | Conflict and "does nothing" notes are 12px muted text apart from the switch; easy to miss |
| 6 | B | The "Nothing is switched on" / "triggers move your windows" callout swaps and the panel height jumps |
| 7 | A | Mixed case: "When the Monitors Change" beside "When I apply a scene"; heading "Applies Itself" against lead-in "Scene applies itself" |
| 8 | A, B | Unknown: rail trigger chips and conflict notes never render, because the sample data has no trigger on |
| 9 | B | Keyboard: disabled schedule and call fields drop out of tab order, so their options are hidden until the radio is chosen |

Compare: finding 7 agrees with decision button-case (Title Case for labels). Finding 4 extends round 1 row 7 (group the switches).

## Code review, round 2

Commit seen: 3405d4e. Round 1 asks 1-7 hold; 57 guards go red when broken. Merge kept the bay and zones logic.

| # | Finding |
|---|---|
| C1 | `Get-Opt` casts a hand-edited non-numeric value with `[double]`; the throw stops every trigger, the schedule too. Use TryParse with the default |
| C2 | No upper limit on inline thresholds; a large offer lead offers every remaining meeting in one tick |
| C3 | Agenda start/end validation has no red proof |
