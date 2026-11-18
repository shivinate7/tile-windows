# A laptop with a portrait has no wide monitor for -Monitor wide

Decision: monitor setups. Recorded 2026-11-17 19:00 CST. Updated 2026-11-17 19:55 CST.

With two or more monitors and no non-built-in landscape monitor (a laptop with a portrait, say), a direct `tile.ps1 -Proc x` run on `-Monitor wide` (the default, or explicit) falls back to the widest screen, as main did. PR 34 (wide-fallback) builds it; coordinator ruling 19:03 CST.

Scenes and the role path do not fall back. A window pinned to `wide`, with no monitor holding that role, goes to `left` as "Its screen is unplugged" (item 14, the first setup; ruling 17:35 CST). On the same laptop and portrait, the two paths differ.
