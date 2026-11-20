# Draw Zone is hard to find

Decision: bay and group zones (`bay-and-group-zones`). Found at d2ee88e. Recorded 2026-11-20 16:39 CST. Line numbers are at d2ee88e. The reviewer ruled Debt (docs/design/reviews/bay-round3.md row 1).

Draw Zone has no armed state, and the live hint (app.html:1322) never names zones.

Harm: a user does not find Draw Zone.

Likelihood: unmeasured.

Recovery: none in the code.

Fix: add an armed state and a hint that names zones (design round 3, row 1). Write a red case first: the live hint names zones while Draw Zone is armed.
