## live-move-guard

**Problem.** A flagless `tile.ps1` run moves the owner's real windows. On 2026-11-17 a test-author ran it without `-DryRun`, and it moved the claude window.

**Guard.** `tile.ps1` refuses a run that could move windows when `TILE_TEST_SUITE` or `CLAUDECODE` is set. The run goes ahead only with `TILE_TEST_ALLOW_LIVE=1`.

**Exempt.** `-DryRun`, bare `-Json` (no `-Scene`, `-Default`, `-Place` or `-PlaceFile`), `-Monitors`, `-From`, `-Lib` and `-List`.

**Check.** `test/safe-moves.ps1`. Its red cases fail before each guard landed. Its exempt-run controls stay green.
