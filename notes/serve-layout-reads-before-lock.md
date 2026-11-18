# POST /layout and POST /layout/remove read monitors before the lock

Decision: monitor setups. Recorded 2026-11-17 16:52 CST. Extended 2026-11-17 22:14 CST to POST /layout/remove.

The `POST layout` and `POST layout/remove` route arms each evaluate `@(Get-Plugged)` before `Save-SceneLayout` or `Remove-SceneLayout` takes the lock (`Use-TileLock`). If a monitor is plugged or unplugged between that read and the lock, the 409 check compares the key against the older set. No case seen.
