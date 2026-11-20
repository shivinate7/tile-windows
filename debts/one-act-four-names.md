# One act has four names

Decision: bay and group zones (`bay-and-group-zones`). Found at d2ee88e. Recorded 2026-11-20 16:39 CST. Line numbers are at d2ee88e. The reviewer ruled Debt (docs/design/reviews/bay-round3.md row 2).

The page names one act four ways: pin, keep put, stay put and keep where it is. The names appear at app.html:717, :1322, :1401 and :1542.

Harm: a user can read four names as four acts.

Likelihood: unmeasured.

Recovery: none in the code.

Fix: pick one verb and use it on every label named here (design round 3, row 2). Write a red label check first: it fails on the four names.
