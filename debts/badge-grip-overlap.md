# Badge and grip overlap on a narrow stacked tile

Decision: stack-and-lock (stack and lock windows on the board). Found in the design fix check after round 3 of PR 11 (the stack-and-lock pull request), head d2e0c4c, design reviewer on Opus. Recorded 2026-11-11 14:06 CST. Line numbers are at d2e0c4c.

A stacked tile shows a +N badge (`.stk`, app.html:301) at its bottom left. The resize grip (`.rsz`, app.html:314) is a 20 px box in its bottom right corner. Both have z-index 1. The grip comes later in the markup (app.html:602), so it paints and takes hits over the badge. Its pointerdown calls preventDefault (app.html:1091), so a press there starts a resize, and the badge's click handler (app.html:1257) never runs.

At 1024 a tile is about 51 by 55 px. By the CSS arithmetic the grip covers x 30 to 50 and the badge runs from about x 9 to 46, in the same lower band. The design reviewer measured the "+2" text at about x 30 to 43. A click there starts a resize instead of bringing the back window forward. A small drag resizes the tile.

The grip is transparent until hover or selection, but it still takes hits, so the overlap is live on idle tiles too. Hiding it with opacity alone leaves the hit area; use display or pointer-events.

Severity: medium. Likelihood: likely in normal use at 1024. Present since 0912afc (the round 1 design-fix commit on stack and lock). Recovery: Bring to Front in the inspector, as the decision lists.

Unmeasured in a browser in this record. The 51 by 55 size and the overlap come from the design fix check at d2e0c4c. The x ranges are CSS arithmetic.

Fix: give the badge and the grip disjoint hit areas on narrow tiles. For example, put the badge on the left half only, or hide the grip on a narrow stacked tile until hover. Measure both boxes in a browser to prove the fix.
