# The one home for scenes and settings: %USERPROFILE%\.tile-windows\config.json (TILE_HOME overrides the folder).
# Dot-sourced by tile.ps1, serve.ps1 and tray.ps1. The first read copies scenes.json (the starters).
$TileHome = if ($env:TILE_HOME) { $env:TILE_HOME } else { Join-Path $env:USERPROFILE '.tile-windows' }
$TileConfig = Join-Path $TileHome 'config.json'
$TileState = Join-Path $TileHome 'state.json'
$TileStarters = Join-Path $PSScriptRoot 'scenes.json'
$TileUtf8 = New-Object Text.UTF8Encoding $false
$TileNoteFile = Join-Path $TileHome 'note.txt'
$TileNote = ''  # set in this process when a read recovered from a bad file; the tray shows it as a balloon

# Run $fn with every writer to this home held off: the server, the tray and tile.ps1 can all write.
function Use-TileLock([scriptblock]$fn) {
  $h = [BitConverter]::ToString([Security.Cryptography.MD5]::Create().ComputeHash([Text.Encoding]::UTF8.GetBytes($TileHome.ToLowerInvariant()))).Replace('-', '').Substring(0, 12)
  $m = New-Object Threading.Mutex($false, "Local\TileWindows-Write-$h")
  try { try { [void]$m.WaitOne(10000) } catch [Threading.AbandonedMutexException] {}; & $fn } finally { try { $m.ReleaseMutex() } catch {}; $m.Dispose() }
}
# A file op that a reader holding the file can make fail for a moment: try again, up to ~1 s.
function Retry-TileIO([scriptblock]$fn) { for ($i = 0; ; $i++) { try { return (& $fn) } catch [IO.IOException] { if ($i -ge 20) { throw }; Start-Sleep -Milliseconds 50 } } }
# Write next to the target under a unique name, then swap, so a crash mid-write cannot lose the file.
function Write-TileFile([string]$path, [string]$text) {
  if (-not (Test-Path -LiteralPath $TileHome)) { New-Item -ItemType Directory -Force -Path $TileHome | Out-Null }
  $tmp = "$path.$PID.$([guid]::NewGuid().ToString('n')).tmp"; [IO.File]::WriteAllText($tmp, $text, $TileUtf8)
  try { Retry-TileIO { if (Test-Path -LiteralPath $path) { [IO.File]::Replace($tmp, $path, [NullString]::Value) } else { [IO.File]::Move($tmp, $path) } } }
  finally { if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force } }
}
function Read-TileFile([string]$path) { Retry-TileIO { [IO.File]::ReadAllText($path, $TileUtf8) } }
# Move a file that does not parse aside as <name>.bad (or <name>.<time>.bad when an older one is there),
# so the app can start fresh and the text is kept. The note stays in note.txt until the page dismisses it.
# Callers hold the lock.
function Set-TileBad([string]$path, [string]$fresh) {
  $bad = "$path.bad"; if (Test-Path -LiteralPath $bad) { $bad = "$path.$((Get-Date).ToString('yyyyMMdd-HHmmss-fff')).bad" }
  Retry-TileIO { [IO.File]::Copy($path, $bad, $false); [IO.File]::Delete($path) }
  $n = "$([IO.Path]::GetFileName($path)) could not be read, so $fresh. The old file is $([IO.Path]::GetFileName($bad))."
  $script:TileNote = $n; Write-TileFile $TileNoteFile ((@((Get-TileNote), $n) | ? { $_ }) -join ' ')
}
function Get-TileNote { if (Test-Path -LiteralPath $TileNoteFile) { Read-TileFile $TileNoteFile } else { '' } }
function Clear-TileNote { Use-TileLock { if (Test-Path -LiteralPath $TileNoteFile) { Retry-TileIO { [IO.File]::Delete($TileNoteFile) } } } }

function Test-TileConfig([string]$text) {
  $c = ConvertFrom-Json $text -ErrorAction Stop
  if (-not ($c.scenes -is [array]) -or @($c.scenes | ? { -not $_.id -or -not $_.name -or -not $_.grids }).Count) { throw 'Config needs a scenes array; each scene needs id, name and grids.' }
  if (@($c.scenes.id | Select-Object -Unique).Count -ne @($c.scenes).Count) { throw 'Scene ids must be unique.' }
}
function Get-TileConfigText {
  if (Test-Path -LiteralPath $TileConfig) {
    $t = Read-TileFile $TileConfig
    try { Test-TileConfig $t; return $t } catch {
      # Check again under the lock: another writer may have fixed or already moved it.
      $ok = Use-TileLock { if (Test-Path -LiteralPath $TileConfig) { $t2 = Read-TileFile $TileConfig; try { Test-TileConfig $t2; $t2 } catch { Set-TileBad $TileConfig 'the starter scenes are back' } } }
      if ($ok) { return $ok }
    }
  }
  $t = [IO.File]::ReadAllText($TileStarters, $TileUtf8); Save-TileConfigText $t; $t
}
# Validates, then writes the text as given: a round trip through objects would cut nesting (ConvertTo-Json depth).
function Save-TileConfigText([string]$text) { Test-TileConfig $text; Use-TileLock { Write-TileFile $TileConfig $text } }

# A scene by id or name, with the config's app -> category map attached as .cats.
function Get-TileScene([string]$key, $config) {
  if (-not $config) { $config = ConvertFrom-Json (Get-TileConfigText) }
  $s = @($config.scenes | ? { $_.id -eq $key -or $_.name -eq $key })[0]
  if (-not $s) { throw "No scene named '$key'. Scenes: $(@($config.scenes.name) -join ', ')." }
  $s | Add-Member -Force cats $config.cats; $s | Add-Member -Force categories $config.categories; $s
}

# state.json: the scene last applied and a short log, for the page and the tray. A bad file starts a fresh log.
function Get-TileStateText {
  $empty = '{"active":"","log":[]}'
  if (-not (Test-Path -LiteralPath $TileState)) { return $empty }
  $t = Read-TileFile $TileState
  try { $s = ConvertFrom-Json $t -ErrorAction Stop; if ($null -eq $s -or $s -is [array]) { throw 'not an object' }; $t }
  catch {
    $ok = Use-TileLock { if (Test-Path -LiteralPath $TileState) { $t2 = Read-TileFile $TileState; try { $s = ConvertFrom-Json $t2 -ErrorAction Stop; if ($null -eq $s -or $s -is [array]) { throw 'not an object' }; $t2 } catch { Set-TileBad $TileState 'the recent log starts over' } } }
    if ($ok) { $ok } else { $empty }
  }
}
# Never throws: it runs after windows have moved, and a log failure must not report the move as failed.
function Add-TileLog([string]$active, [string]$text) {
  try {
    Use-TileLock {
      $s = ConvertFrom-Json (Get-TileStateText)
      $log = @([pscustomobject]@{ t = (Get-Date).ToString('yyyy-MM-dd HH:mm'); x = $text }) + @($s.log | Select-Object -First 19)
      Write-TileFile $TileState (ConvertTo-Json -Depth 4 -Compress ([pscustomobject]@{ active = $active; log = $log }))
    }
  } catch { Write-Warning "Could not write the recent log: $($_.Exception.Message)" }
}
