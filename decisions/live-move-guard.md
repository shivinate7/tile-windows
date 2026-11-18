# Live-move guard

Kind: build
Plan: docs/plans/live-move-guard.md#live-move-guard (windows)

**Question.** Can a test run or an agent shell move the owner's real windows?

**Ruling.** `tile.ps1` refuses any run that could move windows when `TILE_TEST_SUITE` (set by `test/run.ps1`) or `CLAUDECODE` (set in every Claude Code agent shell) is set. The run goes ahead only with `TILE_TEST_ALLOW_LIVE=1`. Exempt: `-DryRun`, bare `-Json` (no `-Scene`, `-Default`, `-Place` or `-PlaceFile`), `-Monitors`, `-From`, `-Lib` and `-List`.

**Date.** 2026-11-17. Coordinator ruling 17:55 CST added `CLAUDECODE`. Coordinator ruling 18:22 CST kept a tray and a server started from an agent shell guarded.

**Recorded.** 2026-11-17 18:35 CST.

**Mistake.** On 2026-11-17 a test-author ran `tile.ps1` without `-DryRun`. It moved the owner's real windows, including the claude window.

**Harm it stops.** A test or agent run moves the owner's real windows.

**Why.** The suite and agent shells run on the owner's desktop. A flagless run reaches real windows unless the code refuses it.

**Cost.** One environment read per run. No process. No file.

**Check.** `test/safe-moves.ps1`. The suite cases fail on commit 656a8cf (before the guard). The CLAUDECODE cases fail on commit 62acbd4 (suite guard only). The exempt-run controls stay green.
