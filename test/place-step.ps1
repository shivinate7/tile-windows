# The -Place -DryRun step of test\run.ps1 (section 2): one read of the live desktop, and the dry run of what it read. The one home of both,
# so test\place-dryrun.ps1 runs the same code the check runs. Dot-sourced by both files; $tile is the path of tile.ps1.
# One read of the live desktop, as the -Json snapshot text (serve.ps1 reads it the same way).
function Read-Desktop([string]$tile) { (& $tile -Json 2>$null) -join '' }
# Feeds a snapshot back to -PlaceFile -DryRun and says whether every window in it matched: Ok, the engine's last line (Last), and the
# window count of the snapshot (N). $file is where the snapshot text is written for the engine to read.
function Test-PlaceDryRun([string]$tile, [string]$snapText, [string]$file) {
  [IO.File]::WriteAllText($file, $snapText, (New-Object Text.UTF8Encoding $false))
  $n = @(($snapText | ConvertFrom-Json).windows).Count
  $last = @(& $tile -PlaceFile $file -DryRun 3>$null)[-1]
  [pscustomobject]@{ Ok = ($last -eq "Placed $n of $n (0 unmatched)."); Last = $last; N = $n }
}
