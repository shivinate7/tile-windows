# A late 409 after Refresh can raise a false setup strip

Decision: monitor setups. Recorded 2026-11-17 19:43 CST.

A 409 that arrives late, after Refresh, can set the stale flag on the fresh scene. Nothing is lost. The strip then shows "setup changed" falsely.
