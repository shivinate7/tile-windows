# A card menu in a short window covers its own button

Decision: monitor setups. Recorded 2026-11-17 23:05 CST.

When the window is too short for the menu below or above (height under about 214 px), `placeMenu` clamps the menu's top to 8 px, and the menu covers its own ⋯ button. The comment in `placeMenu` that says it "never covers its own button" is false there. An older comment above `placeMenu` still says the menu opens "under its button".
