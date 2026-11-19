# Run folders (test-temp-standard): the one home of the delete that removes an old run folder. Each test file dot-sources this file,
# so each still runs alone. Remove-Item cannot pass the 260-character limit, and a headless Edge profile nests deep enough to reach it.
# The \\?\ prefix lifts that limit for the delete.
function Remove-RunFolder([string]$path) {
  if (-not [IO.Directory]::Exists('\\?\' + $path)) { return }
  [IO.Directory]::Delete('\\?\' + $path, $true)
}
# Removes the folders under $dir whose names match $nameRx and whose last write is older than $olderThan, as of $now.
function Invoke-RunFolderSweep([string]$dir, [string]$nameRx, [TimeSpan]$olderThan, [datetime]$now = (Get-Date)) {
  if (-not (Test-Path -LiteralPath $dir)) { return }
  @(Get-ChildItem -LiteralPath $dir -Directory | ? { $_.Name -match $nameRx -and $_.LastWriteTime -lt $now.Subtract($olderThan) }) | % { Remove-RunFolder $_.FullName }
}
