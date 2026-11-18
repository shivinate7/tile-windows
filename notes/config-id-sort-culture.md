# Id tie-break sort is culture-based

Decision: monitor setups. Recorded 2026-11-17 16:52 CST.

`Get-TileRoles` (config.ps1:148) breaks a width tie by monitor id with `Sort-Object`, which compares strings by culture. The setup key sorts its ids with `[StringComparer]::Ordinal` (config.ps1:156).

It matters only when two monitors tie on width and their ids differ only in case or in culture order. No case seen.
