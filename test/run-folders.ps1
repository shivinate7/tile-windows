# Run folders (test-temp-standard): the one home of the delete that removes an old run folder. Each test file dot-sources this file,
# so each still runs alone. Remove-Item cannot pass the 260-character limit, and a headless Edge profile nests deep enough to reach it.
# The \\?\ prefix lifts that limit for the delete.
function Remove-RunFolder([string]$path) {
  if (-not [IO.Directory]::Exists('\\?\' + $path)) { return }
  [IO.Directory]::Delete('\\?\' + $path, $true)
}
# The first file under $dir, at any depth, that another process holds open, or $null. A file is held when it will not open with no share:
# a handle open elsewhere refuses it. The probe writes nothing and deletes nothing.
function Find-RunFolderHeld([string]$dir) {
  foreach ($f in [IO.Directory]::EnumerateFiles('\\?\' + $dir, '*', [IO.SearchOption]::AllDirectories)) {
    try { [IO.File]::Open($f, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::None).Dispose() } catch { return $f.Replace('\\?\', '') }
  }
  $null
}
# Removes the folders under $dir whose names match $nameRx and whose last write is older than $olderThan, as of $now. A folder with a
# file that another process holds open is skipped whole: every file in it is probed before any is deleted, one warning line names the
# folder, and the sweep goes on.
# $except is the caller's own folder (its path), left alone. Matched by name, since $TEMP can be an 8.3 path (SHIVAM~1) while FullName is long.
function Invoke-RunFolderSweep([string]$dir, [string]$nameRx, [TimeSpan]$olderThan, [datetime]$now = (Get-Date), [string]$except = '') {
  if (-not (Test-Path -LiteralPath $dir)) { return }
  $ownName = if ($except) { Split-Path -Leaf $except } else { '' }
  @(Get-ChildItem -LiteralPath $dir -Directory | ? { $_.Name -match $nameRx -and $_.Name -ne $ownName -and $_.LastWriteTime -lt $now.Subtract($olderThan) }) | % {
    $p = $_.FullName
    try {
      $held = Find-RunFolderHeld $p
      if ($held) { Write-Warning "run folder sweep skipped ${p}: $held is open in another process" } else { Remove-RunFolder $p }
    } catch { $why = $_.Exception.Message -replace '\s+', ' '; Write-Warning "run folder sweep could not fully remove ${p}: $why" }
  }
}
