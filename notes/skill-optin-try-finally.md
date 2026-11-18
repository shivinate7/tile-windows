# The SKILL.md opt-in form needs try/finally

Decision: live-move guard. Recorded 2026-11-17 19:55 CST.

The PowerShell opt-in form in `SKILL.md` sets `TILE_TEST_ALLOW_LIVE=1`, runs the command, then clears the variable with `Remove-Item Env:TILE_TEST_ALLOW_LIVE`. A throw in the run skips the clear. In a PowerShell session that stays open, the variable then stays set, so later runs in that session skip the live-move guard. A `try`/`finally` around the run would clear it on every exit. The form has no `try`/`finally` yet.
