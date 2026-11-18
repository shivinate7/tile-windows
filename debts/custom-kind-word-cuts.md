# The card's kind word "Custom" cuts off

Decision: monitor setups. Found in monitor setups design re-check, 2026-11-17 22:18 CST.

On a card, the kind word "Custom" (the `.tagt` span in `renderRail`) cuts to "CU…" at 1024 and to "CUST…" at 1440. The full word is only in a hover title on that span, and the span takes no keyboard focus. At 1440 the label on the Focus card shows about 40 of its 56 px, and "· edited" is hidden except in the hover title.

Fix: pending an owner pick, either drop "Custom" from cards or tighten the row. Queued as lane card-row-fit.
