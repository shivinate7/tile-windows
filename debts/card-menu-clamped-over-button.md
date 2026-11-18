# At 1440 a card's menu opens over its own button

Decision: monitor setups. Found in monitor setups design re-check, 2026-11-17 22:18 CST.

At 1440, a card at the bottom of the window opens its ⋯ menu over its own button and over Preview. `placeMenu` clamps the menu's top to the window's bottom edge, so it cannot open below the button without covering the row.

Fix: open the menu above the button when there is no room below. Queued as lane card-row-fit.
