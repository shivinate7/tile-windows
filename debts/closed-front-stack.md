# Closed front window in a stack

Decision: stack-and-lock. Found in code review round 3 of PR 11 (the stack-and-lock pull request), head 60febd5, reviewer on Sonnet. Recorded 2026-11-11 13:37 CST. Line numbers are at 60febd5.

A pin keeps its front window and a list of windows behind it (`pin.behind`). When the front window is not open, Apply makes the first open back window the front (comment at app.html:890). Two paths go wrong after that.

(a) Bring to Front writes the promoted window into `pin.behind` twice. The paths are `bringFront` (app.html:909-913), the +N badge (app.html:1242) and the B key (app.html:1130). The inspector lists the window twice, Apply reports "no open window", and the closed front's entry is lost.

(b) `pinEdit` (app.html:841-845), `leavePin` (app.html:851-852) and `unpin` (app.html:1153) treat the closed front as the front on screen. An arrow, grip or Shift+arrow move can bring a different window of the same app to the front. Delete needs two presses. Keep Where It Is (app.html:805) leaves a stale pin front.

Severity: low to medium. Likelihood: low to moderate, in a scene with a closed front app and two open back windows. Recovery: Bring to Front or Take Out fixes either one. No lock or overlap breach.

No test covers a closed front with a move or Bring to Front.

Fix: first rewrite the pin's front entry to the promoted window, then drop the duplicate `behind[0]`.
