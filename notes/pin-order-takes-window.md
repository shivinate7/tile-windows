# A plugged pin can take a window an unplugged pin matches

Decision: monitor setups. Recorded 2026-11-17 16:52 CST.

Passes run in order (tile.ps1:566): plugged monitors first, then the phantom passes for unplugged ones. A plugged pin claims its window first, so an unplugged pin that matches the same window finds it claimed.

Pre-existing: main's role order (`tall`, `laptop`, `wide`) has the same effect. Not seen in use.
