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
# A config older than the starters gains what the starters added since: each scene whose "since" is newer than the config's version
# (a scene the owner deleted earlier stays deleted), the activity map, the meeting-size rule and the threshold defaults, and gives each scene the trigger fields.
# It never changes a value a scene already has.
function Update-TileConfig([string]$text) {
  try {
    $c = ConvertFrom-Json $text; $st = ConvertFrom-Json ([IO.File]::ReadAllText($TileStarters, $TileUtf8))
    if ([int]$c.version -ge [int]$st.version) { return $text }
    $have = @($c.scenes.id)
    $c.scenes = @($c.scenes) + @($st.scenes | ? { [int]$_.since -gt [int]$c.version -and $have -notcontains $_.id })
    # monitors and setups start empty (version 4, decision monitor-setups): a monitor or setup is added only when one is plugged in, never here.
    foreach ($k in 'activity', 'meetingSize', 'optDefaults', 'monitors', 'setups') { if (-not $c.PSObject.Properties[$k]) { $c | Add-Member $k $st.$k } }
    # A scene already there gains the fields the triggers read, with every switch off: its starter's screens and claudeGrid, and an auto block.
    foreach ($x in @($c.scenes)) {
      $sx = @($st.scenes | ? { $_.id -eq $x.id })[0]
      foreach ($k in 'screens', 'claudeGrid') { if ($sx -and $null -ne $sx.$k -and -not $x.PSObject.Properties[$k]) { $x | Add-Member $k $sx.$k } }
      if (-not $x.PSObject.Properties['layouts']) { $x | Add-Member layouts ([pscustomobject]@{}) }
      if (-not $x.PSObject.Properties['auto']) { $x | Add-Member auto $(if ($sx) { $sx.auto } else { $st.scenes[0].auto }) }
    }
    $c | Add-Member -Force version $st.version
    $out = ConvertTo-Json -Depth 10 $c; Save-TileConfigText $out; $out
  } catch { $text }
}
function Get-TileConfigText {
  if (Test-Path -LiteralPath $TileConfig) {
    $t = Read-TileFile $TileConfig
    try { Test-TileConfig $t; return (Update-TileConfig $t) } catch {
      # Check again under the lock: another writer may have fixed or already moved it.
      $ok = Use-TileLock { if (Test-Path -LiteralPath $TileConfig) { $t2 = Read-TileFile $TileConfig; try { Test-TileConfig $t2; $t2 } catch { Set-TileBad $TileConfig 'the starter scenes are back' } } }
      if ($ok) { return $ok }
    }
  }
  $t = [IO.File]::ReadAllText($TileStarters, $TileUtf8); Save-TileConfigText $t; $t
}
# Validates, then writes the text as given: a round trip through objects would cut nesting (ConvertTo-Json depth).
function Save-TileConfigText([string]$text) { Test-TileConfig $text; Use-TileLock { Write-TileFile $TileConfig $text } }

# The display name of an app (its process name), from the starters' appNames map: the one home the tray and the page's /appnames read.
# An app the map does not list shows with a capital letter.
function Get-TileAppNames {
  if (-not $script:TileAppNames) { $script:TileAppNames = (ConvertFrom-Json ([IO.File]::ReadAllText($TileStarters, $TileUtf8))).appNames }
  $script:TileAppNames
}
function Get-TileAppName([string]$app) {
  if (-not $app) { return 'A window' }
  $p = (Get-TileAppNames).PSObject.Properties[$app.ToLowerInvariant()]
  if ($p) { $p.Value } else { $app.Substring(0, 1).ToUpper() + $app.Substring(1) }
}

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

# Monitor setups (config version 4, decision monitor-setups). config.monitors holds each monitor ever seen: {name, builtin, lastSeen, bw, bh}.
# config.setups holds each set of monitors ever plugged in together: {name, ids[], lastUsed}. A scene keeps one layout per setup in scene.layouts.
# A monitor's shape role, read from its native size (bw, bh; w, h when those are absent): laptop for the built-in screen, else wide when it is
# wider than 2:1, tall when it is taller than wide, else ''. The one home for the names Register gives and the roles Resolve seeds by.
function Get-TileMonShape($m) {
  if ($m.builtin) { return 'laptop' }
  $w = [double]$(if ($null -ne $m.bw) { $m.bw } else { $m.w }); $h = [double]$(if ($null -ne $m.bh) { $m.bh } else { $m.h })
  if ($h -le 0) { return '' }
  if ($w -gt 2 * $h) { 'wide' } elseif ($h -gt $w) { 'tall' } else { '' }
}
# The key of a set of monitors: their ids, sorted, joined. Order, position and scale never reach it.
function Get-TileSetupKey($monitors) {
  $ids = [string[]]@($monitors | ForEach-Object { [string]$_.id })
  [Array]::Sort($ids, [StringComparer]::Ordinal)
  $ids -join '|'
}
# Adds what the config does not know yet (each unknown monitor, named by shape; the setup these monitors make, named Desk when it is the
# first) and notes that they are plugged in now. Returns the setup key. A repeat call adds nothing; it only moves lastSeen and lastUsed.
function Register-TileSetup($cfg, $monitors) {
  $mons = @($monitors | Where-Object { $_ }); $key = Get-TileSetupKey $mons
  if (-not $mons.Count) { return '' }
  foreach ($k in 'monitors', 'setups') { if (-not $cfg.PSObject.Properties[$k]) { $cfg | Add-Member $k ([pscustomobject]@{}) } }
  $now = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ss')
  foreach ($m in $mons) {
    $id = [string]$m.id; $known = $cfg.monitors.PSObject.Properties[$id]
    if ($known) { $known.Value | Add-Member -Force lastSeen $now; continue }
    $bw = [int]$(if ($null -ne $m.bw) { $m.bw } else { $m.w }); $bh = [int]$(if ($null -ne $m.bh) { $m.bh } else { $m.h })
    $base = switch (Get-TileMonShape ([pscustomobject]@{ builtin = [bool]$m.builtin; bw = $bw; bh = $bh })) { 'laptop' { 'Laptop' } 'wide' { 'Ultrawide' } 'tall' { 'Portrait' } default { 'Monitor' } }
    # A second monitor of a shape reads "Ultrawide 2"; a monitor of no shape reads "Monitor 1", "Monitor 2" until the owner renames it.
    $taken = @($cfg.monitors.PSObject.Properties | ForEach-Object { [string]$_.Value.name })
    $name = if ($base -eq 'Monitor') { 'Monitor 1' } else { $base }; $n = 2
    while ($taken -contains $name) { $name = "$base $n"; $n++ }
    $cfg.monitors | Add-Member -NotePropertyName $id -NotePropertyValue ([pscustomobject]@{ name = $name; builtin = [bool]$m.builtin; lastSeen = $now; bw = $bw; bh = $bh })
  }
  $sp = $cfg.setups.PSObject.Properties[$key]
  if ($sp) { $sp.Value | Add-Member -Force lastUsed $now }
  else {
    $ids = [string[]]@($mons | ForEach-Object { [string]$_.id }); [Array]::Sort($ids, [StringComparer]::Ordinal)
    $name = if (-not @($cfg.setups.PSObject.Properties).Count) { 'Desk' } else { (@($ids | ForEach-Object { [string]$cfg.monitors.$_.name }) -join ' + ') }
    $cfg.setups | Add-Member -NotePropertyName $key -NotePropertyValue ([pscustomobject]@{ name = $name; ids = $ids; lastUsed = $now })
  }
  $key
}
# A deep copy: the config text is nested deeper than ConvertTo-Json's default depth.
function Copy-TileObject($o) { ConvertFrom-Json (ConvertTo-Json -Depth 20 -Compress -InputObject $o) }
# The layout a scene shows on a setup, without changing the config. In order:
#   1. its own layout for that key;
#   2. the closest known setup's layout (the setup sharing the most monitors that has a layout in this scene; a tie goes to the one used last),
#      with its grids mapped onto the key's monitors: a monitor that is not in the key has no grid. Its pins, zones and fill name monitors
#      by id and stay as they are, so a window on an unplugged monitor is remembered and has no cell;
#   3. the scene's role template (grids, pins, zones, fill by wide, tall and laptop), seeded by shape: each role goes to the monitor of that
#      shape, read from config.monitors (Register stores it). A monitor of no shape takes no grid; a role no monitor has keeps its name
#      as the pin's monitor, so those windows have no cell either.
function Resolve-TileLayout($cfg, $scene, [string]$key) {
  $sp = $cfg.setups.PSObject.Properties[$key]
  $ids = @($(if ($sp) { $sp.Value.ids } else { $key -split '\|' }) | Where-Object { $_ })
  $lays = $scene.layouts
  $own = if ($lays) { $lays.PSObject.Properties[$key] }
  if ($own) { return (Copy-TileObject $own.Value) }
  $best = $null; $bestN = 0; $bestUsed = [datetime]::MinValue
  if ($lays) {
    foreach ($p in @($cfg.setups.PSObject.Properties)) {
      $lp = $lays.PSObject.Properties[$p.Name]
      if (-not $lp) { continue }
      $n = @($p.Value.ids | Where-Object { $ids -ccontains $_ }).Count
      if (-not $n) { continue }
      $used = [datetime]::MinValue; $u = $p.Value.lastUsed
      if ($u -is [datetime]) { $used = $u } elseif ($u) { try { $used = [datetime]::Parse([string]$u, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind) } catch {} }
      if ($n -gt $bestN -or ($n -eq $bestN -and $used -gt $bestUsed)) { $best = $lp.Value; $bestN = $n; $bestUsed = $used }
    }
  }
  if ($best) {
    $r = Copy-TileObject $best; $g = [pscustomobject]@{}
    foreach ($gp in @($r.grids.PSObject.Properties)) { if ($ids -ccontains $gp.Name) { $g | Add-Member -NotePropertyName $gp.Name -NotePropertyValue $gp.Value } }
    $r | Add-Member -Force grids $g
    return $r
  }
  $role = @{}; $grids = [pscustomobject]@{}
  foreach ($id in $ids) {
    $mp = $cfg.monitors.PSObject.Properties[$id]; if (-not $mp) { continue }
    $shape = Get-TileMonShape $mp.Value; if (-not $shape) { continue }
    if (-not $role.ContainsKey($shape)) { $role[$shape] = $id }
    $tg = if ($scene.grids) { $scene.grids.PSObject.Properties[$shape] }
    if ($tg) { $grids | Add-Member -NotePropertyName $id -NotePropertyValue ([pscustomobject]@{ c = $tg.Value.c; r = $tg.Value.r }) }
  }
  $tpl = Copy-TileObject ([pscustomobject]@{ pins = $(if ($scene.pins) { @($scene.pins) } else { @() }); zones = $(if ($scene.zones) { @($scene.zones) } else { @() }); fill = $(if ($scene.fill) { $scene.fill } else { [pscustomobject]@{} }) })
  $at = { param($v) if ($v -and $role.ContainsKey([string]$v)) { $role[[string]$v] } else { $v } }
  foreach ($x in @($tpl.pins) + @($tpl.zones)) { if ($x -and $x.PSObject.Properties['mon']) { $x.mon = & $at $x.mon } }
  if ($tpl.fill.PSObject.Properties['mon']) { $tpl.fill.mon = & $at $tpl.fill.mon }
  if (-not $tpl.fill.PSObject.Properties['held']) { $tpl.fill | Add-Member held @() }
  foreach ($h in @($tpl.fill.held)) { if ($h -and $h.PSObject.Properties['mon']) { $h.mon = & $at $h.mon } }
  [pscustomobject]@{ grids = $grids; pins = @($tpl.pins); zones = @($tpl.zones); fill = $tpl.fill; bay = [pscustomobject]@{} }
}
