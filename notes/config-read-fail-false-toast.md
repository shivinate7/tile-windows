# A failed config read shows a false failure toast

Decision: monitor setups. Recorded 2026-11-17 19:43 CST.

`readKnown` throws when the config read fails. The throw runs through `resnap`, and the catches in `applyScene` and `placeBack` then show "Apply failed" or "Undo failed". The windows have already moved by then, so the toast is false.
