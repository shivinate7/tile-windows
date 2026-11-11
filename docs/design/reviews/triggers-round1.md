# Triggers design review, round 1

Commit seen: 055e873. Screen: the scene inspector's trigger section and the new scene cards, 1440 and 1024, light and dark. No clashes with the design records; all FIX.

| # | By | Finding |
|---|---|---|
| 1 | A, B | No cross-scene view: rail cards do not show which triggers a scene has on; no "N scenes apply themselves" summary |
| 2 | B | Conflicts invisible: two scenes can hold the same trigger; no warning, no stated tie-break |
| 3 | A, B | "Applies itself" (pick one) and "Also applies itself" (any) look alike; the split is unexplained |
| 4 | A, B | No tuning: thresholds (1 minute, 30 s, meeting size, gap length) are baked into labels; schedule fields hidden until chosen |
| 5 | A, B | Vague labels: "Offer Before a Meeting", "When the Monitor Set Matches", "When a Call Matches This Meeting Size", "Grid Follows the Claude Count" |
| 6 | A, B | "It changes your windows only when you apply it" is false once a switch is on; the warning that triggers move windows is missing |
| 7 | B | Nine flat switches; group them (calls and meetings, monitors, activity, schedule) |
| 8 | A, B | Built-in Default: "No changes to save" beside live switches; say how trigger switches save |
| 9 | A | Ticking a switch gives no answer at the press; choosing "On a Schedule" pushes the section down |
| 10 | A | Dark: unchecked checkbox border faint; checkbox rows about 19px tall |

Owner-default chosen by the coordinator (low stakes, reversible): thresholds are editable inline with their current values as defaults; when two scenes hold the same trigger, the first in rail order wins and the inspector says "also used by …".
