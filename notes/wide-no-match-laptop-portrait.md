# A laptop with a portrait has no wide monitor for -Monitor wide

Decision: monitor setups. Recorded 2026-11-17 19:00 CST.

With two or more monitors and no non-built-in landscape monitor (a laptop with a portrait, say), `tile.ps1 -Proc x` on the default `-Monitor wide` throws "No monitor matches 'wide'." Main tiled on the widest screen. This follows item 14 (the first setup: with two or more monitors a built-in never takes `wide`). It is a visible change. No fallback to the widest screen is built.
