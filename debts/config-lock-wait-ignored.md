# Config write runs unlocked after a 10 s wait

Decision: monitor setups. Reported in the monitor-setups build. Recorded 2026-11-17 16:52 CST.

`Use-TileLock` (config.ps1:15) calls `$m.WaitOne(10000)` and drops its result. If another writer holds the lock for the full 10 s, the wait returns false, and the block runs anyway, unlocked.

Harm: two writers can each read the same config and write back their own change, so one change is lost. The writers are the server, the tray and tile.ps1. The lock is meant to cover all three.

Likelihood: unmeasured. It needs a hold of 10 s or more.

Recovery: none automatic. The lost change must be made again.

Fix: check the wait's result. On false, do not run the block: retry, or fail with a message the caller shows.
