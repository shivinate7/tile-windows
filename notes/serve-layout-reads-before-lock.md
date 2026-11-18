# POST /layout reads monitors before the lock

Decision: monitor setups. Recorded 2026-11-17 16:52 CST.

The handler evaluates `@(Get-Plugged)` (serve.ps1:170) before `Save-SceneLayout` takes the lock (serve.ps1:118). If a monitor is plugged or unplugged between that read and the lock, the 409 check compares the key against the older set. No case seen.
