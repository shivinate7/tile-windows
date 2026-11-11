# Triggers review, round 3 (final)

Commit seen: ec5f39c. Round 2 rows 1-9 and C1-C3 are fixed. Code verdict: pass, net safety value positive against main. Open findings go to the debt store per the review cap; none is fixed here.

| # | By | Finding | Home |
|---|---|---|---|
| 1 | B | A switch can show On and do nothing; the rail chip looks healthy | debt inert-trigger-switch |
| 2 | A | Choosing "On a Schedule" pushes the rows below down about 80px (B: acceptable) | note |
| 3 | A | Folded summary and rail count triggers and scenes without naming them | note |
| 4 | A, B | "On" word shows beside some switches only, far from the toggle, clipped at 1024 | note |
| 5 | B | Rail chip names ("Return", "Gap") differ from the switch names | note |
| 6 | B | The amber warning box is heavy and repeats on every scene | note |
| 7 | B | Group labels look alike; extras do not read as a separate zone | note |
| 8 | B | At 1024 the sticky Save bar covers the last lines of the inspector | note |
| 9 | Code | `Read-Num` lets "NaN" through (`tray.ps1`); a hand edit only | note |
| 10 | Code | A saved value over its cap shows uncapped in the page; the tray uses the cap | note |
| 11 | Code | A bad hand-edited value falls back with no warning | note |
| 12 | Code | Unverified: focus restore may snap back after Tab out of an edited field | note |
