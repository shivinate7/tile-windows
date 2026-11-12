# Live-desktop -Place check can flake

Decision: none. No decision record covers this check.

Found in code review round 3 of PR 13 (board-feedback), 2026-11-11: 22 of 23 placed. Second sighting on the merge check of PR 16 (run-undo), 2026-11-12 ~17:10 CST: 24 of 25 placed. The rerun passed. Recorded 2026-11-12 17:21 CST. Line numbers are at dad0c8c, the main commit.

The check at `test/run.ps1:60` (`-Place -DryRun matches all windows`) reads the live desktop twice: the snapshot at line 51 and the dry run at line 59. Any window that opens, closes or changes its title between the two reads fails the check.

Harm: a red full suite on a correct head costs a rerun (about 3 min). It also teaches readers to scroll past red, so they miss a real failure.

Severity: low. The cost is a rerun, not a wrong result.

Likelihood: seen twice, on 2026-11-11 and 2026-11-12.

Recovery: rerun the suite. The rerun passed on the second sighting.

Fix: read the desktop once and feed both sides the same snapshot.
