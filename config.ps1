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
# A monitor's native size (bw, bh; w, h when those are absent) as two numbers, w then h.
function Get-TileMonSize($m) {
  $w = [double]$(if ($null -ne $m.bw) { $m.bw } else { $m.w }); $h = [double]$(if ($null -ne $m.bh) { $m.bh } else { $m.h })
  $w; $h
}
# A monitor's shape, read from its native size: laptop for the built-in screen, else tall when it is taller than wide, wide when it is
# landscape (any aspect, 16:9 included), else '' (a zero width or height, or a square, has no shape). The one home for the shape rule;
# Register names by it and Get-TileRoles seeds by it. Ultrawide (wider than 2:1) is a name only, never a role.
function Get-TileMonShape($m) {
  if ($m.builtin) { return 'laptop' }
  $w, $h = Get-TileMonSize $m
  if ($w -le 0 -or $h -le 0) { return '' }
  if ($h -gt $w) { 'tall' } elseif ($w -gt $h) { 'wide' } else { '' }
}
# The seeding pick (decision monitor-setups item 14): each role goes to one monitor of the ids, the widest candidate of its shape, then the
# lowest id. Returns a hashtable role -> id. A monitor the config does not know has no shape.
function Get-TileRoles($monitors, $ids) {
  $cand = @(foreach ($id in @($ids)) {
    $mp = if ($monitors) { $monitors.PSObject.Properties[[string]$id] }; if (-not $mp) { continue }
    $shape = Get-TileMonShape $mp.Value; if (-not $shape) { continue }
    $w, $h = Get-TileMonSize $mp.Value
    [pscustomobject]@{ id = [string]$id; shape = $shape; w = $w }
  })
  $role = @{}
  foreach ($c in @($cand | Sort-Object @{ Expression = { $_.w }; Descending = $true }, @{ Expression = { $_.id }; Descending = $false })) {
    if (-not $role.ContainsKey($c.shape)) { $role[$c.shape] = $c.id }
  }
  $role
}
# The key of a set of monitors: their ids, sorted, joined. Order, position and scale never reach it.
function Get-TileSetupKey($monitors) {
  $ids = [string[]]@($monitors | ForEach-Object { [string]$_.id })
  [Array]::Sort($ids, [StringComparer]::Ordinal)
  $ids -join '|'
}
# The setup key of monitors that all carry an id, else '' (no monitors, or one without an id, has no setup). Where a monitor list may come
# from an older snapshot or a Windows screen list, which have no ids.
function Get-TileKnownSetupKey($monitors) {
  $m = @($monitors | Where-Object { $_ })
  if (-not $m.Count -or @($m | Where-Object { -not $_.id }).Count) { return '' }
  Get-TileSetupKey $m
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
    $probe = [pscustomobject]@{ builtin = [bool]$m.builtin; bw = $bw; bh = $bh }
    $base = switch (Get-TileMonShape $probe) { 'laptop' { 'Laptop' } 'tall' { 'Portrait' } 'wide' { if ($bw -gt 2 * $bh) { 'Ultrawide' } else { 'Monitor' } } default { 'Monitor' } }
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
#      with its grids mapped onto the key's monitors: a monitor that is not in the key has no grid. A monitor in the key that the closest
#      setup lacks gets a grid seeded from the scene's role template when it holds a role of the pick (Get-TileRoles), not no grid
#      (coordinator picks, 2026-11-17 12:35 and 13:26 CST). Its pins, zones and fill name monitors
#      by id and stay as they are, so a window on an unplugged monitor is remembered and has no cell;
#   3. the scene's role template (grids, pins, zones, fill by wide, tall and laptop), seeded by the pick (Get-TileRoles): each role goes to one monitor, read from
#      config.monitors (Register stores it). A monitor that holds no role takes no grid; a role no monitor has keeps its name
#      as the pin's monitor, so those windows have no cell either.
# The closest known setup: of the setups whose key is in $held (the keys that hold a layout), the one sharing the most monitors with $ids,
# a tie to the one used last. Returns its config.setups property (.Name is the key, .Value the setup), or $null when none shares a monitor.
# $except is a key that is never the pick. The one home for the pick: Resolve-TileLayout, Get-TileFollows and the snapshot's setup.follows read it.
function Get-TileClosestSetup($cfg, $ids, $held, [string]$except = '') {
  $best = $null; $bestN = 0; $bestUsed = [datetime]::MinValue
  foreach ($p in @($cfg.setups.PSObject.Properties)) {
    if ($p.Name -ceq $except -or @($held) -cnotcontains $p.Name) { continue }
    $n = @($p.Value.ids | Where-Object { @($ids) -ccontains $_ }).Count
    if (-not $n) { continue }
    $used = [datetime]::MinValue; $u = $p.Value.lastUsed
    if ($u -is [datetime]) { $used = $u } elseif ($u) { try { $used = [datetime]::Parse([string]$u, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind) } catch {} }
    if ($n -gt $bestN -or ($n -eq $bestN -and $used -gt $bestUsed)) { $best = $p; $bestN = $n; $bestUsed = $used }
  }
  $best
}
# The name of the setup a scene follows on $key: the closest known setup that holds a layout of the scene, while the scene has none of its own for $key; else ''.
function Get-TileFollows($cfg, $scene, [string]$key) {
  $lays = $scene.layouts
  if (-not $lays -or $lays.PSObject.Properties[$key]) { return '' }
  $sp = $cfg.setups.PSObject.Properties[$key]
  $ids = @($(if ($sp) { $sp.Value.ids } else { $key -split '\|' }) | Where-Object { $_ })
  $pick = Get-TileClosestSetup $cfg $ids @($lays.PSObject.Properties.Name) $key
  if ($pick) { [string]$pick.Value.name } else { '' }
}
function Resolve-TileLayout($cfg, $scene, [string]$key) {
  $sp = $cfg.setups.PSObject.Properties[$key]
  $ids = @($(if ($sp) { $sp.Value.ids } else { $key -split '\|' }) | Where-Object { $_ })
  $lays = $scene.layouts
  $own = if ($lays) { $lays.PSObject.Properties[$key] }
  if ($own) { return (Copy-TileObject $own.Value) }
  $pick = if ($lays) { Get-TileClosestSetup $cfg $ids @($lays.PSObject.Properties.Name) $key }
  $best = if ($pick) { $lays.PSObject.Properties[$pick.Name].Value }
  if ($best) {
    $r = Copy-TileObject $best; $g = [pscustomobject]@{}
    foreach ($gp in @($r.grids.PSObject.Properties)) { if ($ids -ccontains $gp.Name) { $g | Add-Member -NotePropertyName $gp.Name -NotePropertyValue $gp.Value } }
    $pick = Get-TileRoles $cfg.monitors $ids
    foreach ($shape in $pick.Keys) {
      $id = $pick[$shape]
      if ($g.PSObject.Properties[$id]) { continue }
      $tg = if ($scene.grids) { $scene.grids.PSObject.Properties[$shape] }
      if ($tg) { $g | Add-Member -NotePropertyName $id -NotePropertyValue ([pscustomobject]@{ c = $tg.Value.c; r = $tg.Value.r }) }
    }
    $r | Add-Member -Force grids $g
    return $r
  }
  $role = Get-TileRoles $cfg.monitors $ids; $grids = [pscustomobject]@{}
  foreach ($shape in $role.Keys) {
    $tg = if ($scene.grids) { $scene.grids.PSObject.Properties[$shape] }
    if ($tg) { $grids | Add-Member -NotePropertyName $role[$shape] -NotePropertyValue ([pscustomobject]@{ c = $tg.Value.c; r = $tg.Value.r }) }
  }
  $tpl = Copy-TileObject ([pscustomobject]@{ pins = @($scene.pins | Where-Object { $_ }); zones = @($scene.zones | Where-Object { $_ }); fill = $(if ($scene.fill) { $scene.fill } else { [pscustomobject]@{} }) })
  $at = { param($v) if ($v -and $role.ContainsKey([string]$v)) { $role[[string]$v] } else { $v } }
  foreach ($x in @($tpl.pins) + @($tpl.zones)) { if ($x -and $x.PSObject.Properties['mon']) { $x.mon = & $at $x.mon } }
  if ($tpl.fill.PSObject.Properties['mon']) { $tpl.fill.mon = & $at $tpl.fill.mon }
  if (-not $tpl.fill.PSObject.Properties['held']) { $tpl.fill | Add-Member held @() }
  foreach ($h in @($tpl.fill.held)) { if ($h -and $h.PSObject.Properties['mon']) { $h.mon = & $at $h.mon } }
  [pscustomobject]@{ grids = $grids; pins = @($tpl.pins); zones = @($tpl.zones); fill = $tpl.fill; bay = [pscustomobject]@{} }
}
