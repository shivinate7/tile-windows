# Engine layouts (decision monitor-setups, items 5 and 9): tile.ps1 places a scene by monitor id. Plain asserts, one FAIL line per failing
# check. Touches no real profile: USERPROFILE and TILE_HOME point into this run's folder.
# Run alone: powershell -NoProfile -ExecutionPolicy Bypass -File test\engine-layouts.ps1
# test\run.ps1 runs this file in a child powershell and counts its FAIL lines. Old run folders are swept by stack-lock.ps1.
#
# Contract the builder meets (what a posted scene carries, and what tile.ps1 reads on the call):
#   scene.layouts: {<setup key>: layout}. The posted scene does not carry the key. tile.ps1 derives it on each call from the ids of the
#     monitors that call reads (config.ps1's Get-TileSetupKey: -From's snapshot, the TILE_SCREENS_FILE seam, or the live read).
#   layout: {grids: {<monitor id>: {c, r}}, pins: [{app, match, mon: <id>, slots}], zones: [{mon: <id>, slots, app | cat}],
#     fill: {mon: <id>, apps, skip, sort}, bay: []}. A layout found for the key replaces the scene's role template for that call.
#   Slots are 0-based in the posted JSON. Output slots are 1-based, as today.
#   No layouts entry for the key, and role-keyed grids (wide, tall, laptop): the role path runs, as today.
#   A scene posted as a resolved layout (Resolve-TileLayout's output: grids keyed by monitor id at the top level, pins and fill by id)
#     runs by id too. The caller resolves when the current key has no entry; this file does not test how it resolves.
#   placed[].mon is not asserted here. Placement is checked by id, slots and rect (x, y, w, h).
# Item 9: a window a layout places on a monitor that is not plugged in is claimed (never moved), listed in left with why
#   'Its screen is unplugged', and kept out of missing.
# Safety: every scene run here passes -From (always a dry run) or -DryRun. -Json on a scene with neither moves real windows.
#
# Red on 31ea7c1: the id cases (desk, rearranged, item 9, seam, setup B, full size) fail by an assert. The controls (empty layout,
# -Monitor wide, role-keyed scene, a layout for another setup) pass there and must stay green.
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
$tile = Join-Path $root 'tile.ps1'
$utf8 = New-Object Text.UTF8Encoding $false
$script:fail = 0
function Check($name, $ok, $detail = '') { if ($ok) { "PASS  $name" } else { $script:fail++; "FAIL  $name  $detail" } }
# One case. An error inside it is one FAIL line naming the case, and the run goes on.
function Case([string]$name, [scriptblock]$body) { try { & $body } catch { $script:fail++; "FAIL  $name  threw: $($_.Exception.Message)" } }

# Run folder: one per run under the temp root the suite uses, named <pid>-<uuid>. Teardown removes it.
$runRoot = Join-Path $env:TEMP 'tile-windows-test-runs'
New-Item -ItemType Directory -Force -Path $runRoot | Out-Null
$run = Join-Path $runRoot ("$PID-" + [guid]::NewGuid().ToString('n'))
New-Item -ItemType Directory -Path $run | Out-Null
$saved = @{ USERPROFILE = $env:USERPROFILE; APPDATA = $env:APPDATA; TILE_HOME = $env:TILE_HOME; TILE_SCREENS_FILE = $env:TILE_SCREENS_FILE }
$env:USERPROFILE = Join-Path $run 'profile'; $env:APPDATA = Join-Path $env:USERPROFILE 'AppData\Roaming'
$env:TILE_HOME = $null; $env:TILE_SCREENS_FILE = $null

try {
  # The product's own key and resolution functions (one home: config.ps1). Dot-sourcing reads no file.
  . (Join-Path $root 'config.ps1')

  # ---- Fixture: this file's own desk (laptop and ultrawide), with ids. Positions are work areas (x, y, w, h); bw, bh the bounds. ----
  $LAP = 'BOE0A3-builtin'; $ULT = 'DEL4199-ABC123'; $TAL = 'AUO2D9B-TAL1'
  function Mon($id, [int]$x, [int]$y, [int]$w, [int]$h, [int]$bw, [int]$bh, [bool]$builtin = $false) { [pscustomobject]@{ name = "DISPLAY $id"; id = $id; builtin = $builtin; x = $x; y = $y; w = $w; h = $h; bw = $bw; bh = $bh } }
  function Win([int]$id, $app, $title, [int]$x) { [pscustomobject]@{ id = $id; app = $app; title = $title; x = $x; y = 0; w = 400; h = 300 } }
  # Expected rect of slot $slot (0-based) on a grid of $c columns and $r rows over a work area, as the engine cuts it.
  function CellRect($m, [int]$c, [int]$r, [int]$slot) {
    $w = [int]($m.w / $c); $h = [int]($m.h / $r)
    '{0},{1},{2},{3}' -f ([int]$m.x + ($slot % $c) * $w), ([int]$m.y + [int][Math]::Floor($slot / $c) * $h), $w, $h
  }
  function RectOf($p) { '{0},{1},{2},{3}' -f [int]$p.x, [int]$p.y, [int]$p.w, [int]$p.h }
  function PlacedOf($res, [int64]$id) { @($res.placed | ? { [int64]$_.id -eq $id })[0] }
  function LeftWhy($res, [int64]$id) { (@($res.left | ? { [int64]$_.id -eq $id }) | % { [string]$_.why }) -join ';' }
  # True when window $id is placed in exactly slot $slot (1-based, as the output gives it) with rect $rect.
  function OnCell($res, [int64]$id, [int]$slot, [string]$rect) { $p = PlacedOf $res $id; [bool]$p -and ((@($p.slots) -join '+') -eq "$slot") -and ((RectOf $p) -eq $rect) }
  function Desc($res, [int64]$id) { $p = PlacedOf $res $id; if ($p) { "id $id slots $(@($p.slots) -join '+') rect $(RectOf $p)" } else { "id $id not placed; left why: '$(LeftWhy $res $id)'" } }
  # A hashtable of id -> value as an object with those names as properties (ids contain '-' and '|', so no literal syntax).
  function Keyed([hashtable]$h) { $o = New-Object PSObject; foreach ($k in $h.Keys) { $o | Add-Member -NotePropertyName ([string]$k) -NotePropertyValue $h[$k] }; $o }
  function KeyedOne($k, $v) { $h = @{}; $h[$k] = $v; Keyed $h }
  function Layout($grids, $pins, $fill, $zones = @()) { [pscustomobject]@{ grids = $grids; pins = @($pins); zones = @($zones); fill = $fill; bay = @() } }
  function Write-Json([string]$name, $obj, [int]$depth = 12) { $p = Join-Path $run $name; [IO.File]::WriteAllText($p, (ConvertTo-Json -InputObject $obj -Depth $depth -Compress), $utf8); $p }
  function Write-Snap([string]$name, $mons, $wins) { Write-Json $name ([pscustomobject]@{ monitors = @($mons); windows = @($wins) }) 6 }

  # Tile runs. Every scene run here is a dry run: -From forces it, and the seam run passes -DryRun.
  function Invoke-SceneFrom([string]$scenePath, [string]$snap) { ConvertFrom-Json ((& $tile -Scene $scenePath -From $snap -Json 3>$null) -join '') }
  function Invoke-SceneSeam([string]$scenePath, $mons) {
    $seam = Join-Path $run ('seam-' + [guid]::NewGuid().ToString('n') + '.json'); [IO.File]::WriteAllText($seam, (ConvertTo-Json -InputObject @($mons) -Depth 4 -Compress), $utf8)
    $env:TILE_SCREENS_FILE = $seam
    try { ConvertFrom-Json ((& $tile -Scene $scenePath -DryRun -Json 3>$null) -join '') } finally { $env:TILE_SCREENS_FILE = $null }
  }
  function Invoke-SceneNamed([string]$name, [string]$snap, [string]$cfgHome) {
    $env:TILE_HOME = $cfgHome
    try { ConvertFrom-Json ((& $tile -Scene $name -From $snap -Json 3>$null) -join '') } finally { $env:TILE_HOME = $null }
  }

  # ---- The desk: laptop (builtin) and ultrawide, one window per claim below ----
  $lapDesk = Mon $LAP 0 0 1920 1040 1920 1080 $true
  $ultDesk = Mon $ULT 1920 0 3440 1400 3440 1440
  $kDesk = Get-TileSetupKey @($lapDesk, $ultDesk)
  $kLap = Get-TileSetupKey @($lapDesk)
  $kUlt = Get-TileSetupKey @($ultDesk)
  # Claude 2001 and 2002 (laptop fill); Chrome 2003 (pinned to the ultrawide by title 'Pull'); Teams 2004 (in no list).
  $wins = @((Win 2001 'claude' 'Claude - chat' 0), (Win 2002 'claude' 'Claude - notes' 500), (Win 2003 'chrome' 'Pull request 212 - Example' 1000), (Win 2004 'ms-teams' 'Chat | Teams' 1500))
  $snapDesk = Write-Snap 'desk.json' @($lapDesk, $ultDesk) $wins

  # The desk layout, keyed by both ids. Chrome sits on the ultrawide's second cell, which the role template never uses.
  $gDesk = @{}; $gDesk[$ULT] = [pscustomobject]@{ c = 5; r = 2 }; $gDesk[$LAP] = [pscustomobject]@{ c = 4; r = 1 }
  $layDesk = Layout (Keyed $gDesk) @([pscustomobject]@{ app = 'chrome'; match = 'Pull'; mon = $ULT; slots = @(1) }) ([pscustomobject]@{ mon = $LAP; apps = @('claude', 'chrome'); skip = @(); sort = 'app' })
  # The scene's own role template (seed): Chrome on the wide role's first cell, so a run that ignores the layout is visible as that rect.
  $tplDesk = [pscustomobject]@{ grids = [pscustomobject]@{ wide = [pscustomobject]@{ c = 5; r = 2 } }; pins = @([pscustomobject]@{ app = 'chrome'; match = 'Pull'; mon = 'wide'; slots = @(0) }); fill = [pscustomobject]@{ mon = 'wide'; apps = @('claude'); skip = @(); sort = 'app' } }
  $sceneDesk = Write-Json 'desk-scene.json' ([pscustomobject]@{ id = 'desk'; name = 'Desk'; grids = $tplDesk.grids; pins = $tplDesk.pins; fill = $tplDesk.fill; layouts = (KeyedOne $kDesk $layDesk) })

  Case 'scope: the desk snapshot holds both ids, and the posted scene keys a layout by their setup key' {
    $snapObj = Get-Content -Raw -LiteralPath $snapDesk | ConvertFrom-Json
    $sc = Get-Content -Raw -LiteralPath $sceneDesk | ConvertFrom-Json
    $wantIds = (@($LAP, $ULT) | Sort-Object) -join ','
    $gotIds = (@($snapObj.monitors.id) | Sort-Object) -join ','
    Check 'scope: the desk snapshot holds the laptop and the ultrawide ids' ($gotIds -ceq $wantIds) "got $gotIds"
    Check 'scope: the posted scene has a layout for the desk key' ($sc.layouts.PSObject.Properties.Name -contains $kDesk) "keys: $($sc.layouts.PSObject.Properties.Name -join ' ')"
  }

  # ---- 1. A layout keyed by ids places windows on the right screens ----
  Case 'desk: a layout keyed by ids places each window on its screen and cell' {
    $r = Invoke-SceneFrom $sceneDesk $snapDesk
    Check 'desk: Chrome is pinned on the ultrawide id, in its second cell' (OnCell $r 2003 2 (CellRect $ultDesk 5 2 1)) (Desc $r 2003)
    Check 'desk: Claude windows fill the laptop cells 1 and 2, in order' ((OnCell $r 2001 1 (CellRect $lapDesk 4 1 0)) -and (OnCell $r 2002 2 (CellRect $lapDesk 4 1 1))) "$(Desc $r 2001) | $(Desc $r 2002)"
    Check 'desk: nothing is left or missing' (@($r.left).Count -eq 0 -and @($r.missing).Count -eq 0) "left: $(@($r.left | % { $_.id }) -join ',') missing: $(@($r.missing | % { $_.app }) -join ',')"
  }

  # Rearranged: the same two ids, moved (the ultrawide to x 0, the laptop to x 3440). The key is the same; the cells are the same.
  $ultMoved = Mon $ULT 0 0 3440 1400 3440 1440
  $lapMoved = Mon $LAP 3440 0 1920 1040 1920 1080 $true
  $snapMoved = Write-Snap 'moved.json' @($lapMoved, $ultMoved) $wins
  Case 'rearranged: the same ids in new positions keep the setup key, the cells, and take the new coordinates' {
    Check 'scope: moving the monitors keeps the setup key' ((Get-TileSetupKey @($lapMoved, $ultMoved)) -ceq $kDesk) "key: $(Get-TileSetupKey @($lapMoved, $ultMoved))"
    $r = Invoke-SceneFrom $sceneDesk $snapMoved
    Check 'rearranged: Chrome keeps the ultrawide second cell, at the new x' (OnCell $r 2003 2 (CellRect $ultMoved 5 2 1)) (Desc $r 2003)
    Check 'rearranged: Claude keeps laptop cells 1 and 2, at the laptop new x' ((OnCell $r 2001 1 (CellRect $lapMoved 4 1 0)) -and (OnCell $r 2002 2 (CellRect $lapMoved 4 1 1))) "$(Desc $r 2001) | $(Desc $r 2002)"
  }

  # ---- Item 9: the ultrawide is unplugged. The layout that names it is posted resolved, as the caller does with Resolve-TileLayout. ----
  $mons = New-Object PSObject
  $mons | Add-Member -NotePropertyName $LAP -NotePropertyValue ([pscustomobject]@{ name = 'Laptop'; builtin = $true; lastSeen = '2026-11-17T09:00:00'; bw = 1920; bh = 1080 })
  $mons | Add-Member -NotePropertyName $ULT -NotePropertyValue ([pscustomobject]@{ name = 'Ultrawide'; builtin = $false; lastSeen = '2026-11-17T09:00:00'; bw = 3440; bh = 1440 })
  $sets = New-Object PSObject
  $sets | Add-Member -NotePropertyName $kDesk -NotePropertyValue ([pscustomobject]@{ name = 'Desk'; ids = @($LAP, $ULT); lastUsed = '2026-11-17T09:00:00' })
  $cfgRes = [pscustomobject]@{ monitors = $mons; setups = $sets }
  $sceneDeskObj = [pscustomobject]@{ id = 'desk'; name = 'Desk'; grids = $tplDesk.grids; pins = $tplDesk.pins; fill = $tplDesk.fill; layouts = (KeyedOne $kDesk $layDesk) }
  $resLap = Resolve-TileLayout $cfgRes $sceneDeskObj $kLap
  $postLap = Write-Json 'post-laptop.json' ([pscustomobject]@{ id = 'post'; name = 'Post'; grids = $resLap.grids; pins = @($resLap.pins); zones = @($resLap.zones); fill = $resLap.fill; bay = @($resLap.bay) })
  $lapOnly = Write-Snap 'laptop-only.json' @($lapDesk) $wins

  Case 'item 9: with the ultrawide unplugged, its window is claimed, listed in left, and kept out of missing' {
    $lapObj = Get-Content -Raw -LiteralPath $lapOnly | ConvertFrom-Json
    Check 'scope: the laptop-only snapshot has no ultrawide id, and Chrome is open' ((@($lapObj.monitors.id) -notcontains $ULT) -and @($lapObj.windows | ? { $_.app -eq 'chrome' }).Count -ge 1) (@($lapObj.monitors.id) -join ',')
    Check 'scope: the posted layout names the ultrawide id for Chrome' (@($resLap.pins | ? { $_.app -eq 'chrome' -and $_.mon -eq $ULT }).Count -eq 1) ($resLap.pins | ConvertTo-Json -Compress)
    $r = Invoke-SceneFrom $postLap $lapOnly
    Check 'item 9: Chrome is not placed (never moved)' (-not (PlacedOf $r 2003)) (Desc $r 2003)
    Check 'item 9: Chrome is listed in left with why "Its screen is unplugged"' ((LeftWhy $r 2003) -ceq 'Its screen is unplugged') (Desc $r 2003)
    Check 'item 9: Chrome is not in missing' (@($r.missing | ? { $_.app -eq 'chrome' }).Count -eq 0) "missing: $(@($r.missing | ? { $_.app -eq 'chrome' } | ConvertTo-Json -Compress))"
    Check 'item 9: Claude still fills the laptop cells 1 and 2' ((OnCell $r 2001 1 (CellRect $lapDesk 4 1 0)) -and (OnCell $r 2002 2 (CellRect $lapDesk 4 1 1))) "$(Desc $r 2001) | $(Desc $r 2002)"
  }

  Case 'item 9: with the ultrawide back, Chrome returns to its cell and leaves left' {
    $r = Invoke-SceneFrom $sceneDesk $snapDesk
    Check 'item 9: Chrome is back in the ultrawide second cell' (OnCell $r 2003 2 (CellRect $ultDesk 5 2 1)) (Desc $r 2003)
    Check 'item 9: Chrome is not in left' ((LeftWhy $r 2003) -eq '') "left why: '$(LeftWhy $r 2003)'"
  }

  # ---- The live seam: TILE_SCREENS_FILE with ids. No window is needed: a pin on a window that is not open reports missing. ----
  $gSeam = @{}; $gSeam[$ULT] = [pscustomobject]@{ c = 5; r = 2 }
  $laySeam = Layout (Keyed $gSeam) @([pscustomobject]@{ app = 'zz-none'; match = ''; mon = $ULT; slots = @(1) }) ([pscustomobject]@{ mon = $ULT; apps = @(); skip = @(); sort = 'app' })
  $sceneSeam = Write-Json 'seam-scene.json' ([pscustomobject]@{ id = 'seam'; name = 'Seam'; layouts = (KeyedOne $kDesk $laySeam) })
  Case 'seam: a scene run finds each screen by its id in TILE_SCREENS_FILE' {
    $seamObj = @($lapDesk, $ultDesk)
    $wantSeam = (@($LAP, $ULT) | Sort-Object) -join ','
    $gotSeam = (@($seamObj.id) | Sort-Object) -join ','
    Check 'scope: the seam holds the two ids' ($gotSeam -ceq $wantSeam) "got $gotSeam"
    $r = Invoke-SceneSeam $sceneSeam $seamObj
    Check 'seam: the pin on the ultrawide id reports no open window (its screen was found by id)' (@($r.missing | ? { $_.app -eq 'zz-none' -and $_.why -eq 'no open window' }).Count -eq 1) "missing: $(@($r.missing | ConvertTo-Json -Compress))"
  }

  # ---- Setup B's layout leaves setup A's untouched. The run reads config.json by name and must write nothing. ----
  $tallB = Mon $TAL 1920 0 1080 1880 1080 1920
  $kB = Get-TileSetupKey @($lapDesk, $tallB)
  $snapB = Write-Snap 'setup-b.json' @($lapDesk, $tallB) $wins
  $gB = @{}; $gB[$TAL] = [pscustomobject]@{ c = 1; r = 4 }
  $layB = Layout (Keyed $gB) @() ([pscustomobject]@{ mon = $TAL; apps = @('claude', 'chrome'); skip = @(); sort = 'app' })
  $cfgHome = Join-Path $run 'home'; New-Item -ItemType Directory -Path $cfgHome | Out-Null
  $starters = [IO.File]::ReadAllText((Join-Path $root 'scenes.json'), $utf8) | ConvertFrom-Json
  $laysB = @{}; $laysB[$kDesk] = $layDesk; $laysB[$kB] = $layB
  $named = [pscustomobject]@{ id = 'by-name'; name = 'By name'; grids = [pscustomobject]@{ wide = [pscustomobject]@{ c = 5; r = 2 } }; pins = @(); fill = [pscustomobject]@{ mon = 'wide'; apps = @('claude'); skip = @(); sort = 'app' }; layouts = (Keyed $laysB) }
  $cfgObj = $starters; $cfgObj.scenes = @($starters.scenes) + $named
  $cfgPath = Join-Path $cfgHome 'config.json'
  [IO.File]::WriteAllText($cfgPath, (ConvertTo-Json -InputObject $cfgObj -Depth 20), $utf8)
  $cfgBefore = [IO.File]::ReadAllText($cfgPath, $utf8)
  Case 'setup B: its layout places its windows on the tall screen, in order' {
    Check 'scope: setup B has its own key, not the desk key' ($kB -cne $kDesk -and @($starters.version)[0] -eq 4) "B: $kB desk: $kDesk"
    $rB = Invoke-SceneNamed 'by-name' $snapB $cfgHome
    Check 'setup B: Claude and Chrome sit in the tall screen cells 1, 2 and 3' ((OnCell $rB 2001 1 (CellRect $tallB 1 4 0)) -and (OnCell $rB 2002 2 (CellRect $tallB 1 4 1)) -and (OnCell $rB 2003 3 (CellRect $tallB 1 4 2))) "$(Desc $rB 2001) | $(Desc $rB 2002) | $(Desc $rB 2003)"
  }
  Case 'control: the run writes no config and no state, and setup A''s layout is still there' {
    $cfgAfter = [IO.File]::ReadAllText($cfgPath, $utf8)
    Check 'control: config.json is byte-for-byte unchanged after the run' ($cfgAfter -ceq $cfgBefore) 'the run rewrote config.json'
    Check 'control: no state.json is written by the run' (-not (Test-Path -LiteralPath (Join-Path $cfgHome 'state.json'))) 'a state.json appeared'
    $layA = (ConvertFrom-Json $cfgAfter).scenes | ? { $_.id -eq 'by-name' } | % { $_.layouts.PSObject.Properties[$kDesk].Value }
    Check 'control: setup A''s layout reads back unchanged' ((ConvertTo-Json -Depth 12 -Compress $layA) -ceq (ConvertTo-Json -Depth 12 -Compress $layDesk)) 'setup A''s layout changed'
  }

  # ---- Full size: a ten-cell ultrawide grid with ten Claude windows fills every cell. ----
  $gUlt = @{}; $gUlt[$ULT] = [pscustomobject]@{ c = 5; r = 2 }
  $layUlt = Layout (Keyed $gUlt) @() ([pscustomobject]@{ mon = $ULT; apps = @('claude'); skip = @(); sort = 'app' })
  $sceneUlt = Write-Json 'ult-scene.json' ([pscustomobject]@{ id = 'ult'; name = 'Ultrawide only'; layouts = (KeyedOne $kUlt $layUlt) })
  $ten = @(1..10 | % { Win (3000 + $_) 'claude' "Claude $_" (100 * $_) })
  $snapTen = Write-Snap 'ult-ten.json' @($ultDesk) $ten
  Case 'full size: ten windows fill the ten cells of the ultrawide layout, one per cell' {
    $r = Invoke-SceneFrom $sceneUlt $snapTen
    Check 'full size: all ten windows are placed' (@($r.placed).Count -eq 10) "placed: $(@($r.placed).Count), left: $(@($r.left).Count)"
    $bad = @(1..10 | ? { -not (OnCell $r (3000 + $_) $_ (CellRect $ultDesk 5 2 ($_ - 1))) })
    Check 'full size: each window sits in its cell, in order' ($bad.Count -eq 0) "not in its cell: $($bad -join ',')"
  }

  # ---- Controls (green on 31ea7c1, must stay green) ----
  $snapEmpty = Write-Snap 'ult-empty.json' @($ultDesk) @()
  Case 'control: a layout with no open windows places nothing and names nothing missing or left' {
    $r = Invoke-SceneFrom $sceneUlt $snapEmpty
    Check 'control: nothing is placed' (@($r.placed).Count -eq 0) "placed: $(@($r.placed).Count)"
    Check 'control: nothing is missing or left' (@($r.missing).Count -eq 0 -and @($r.left).Count -eq 0) "missing: $(@($r.missing).Count) left: $(@($r.left).Count)"
  }
  Case 'control: -Monitor wide still tiles the widest screen in its 5x2 grid (text output)' {
    $txt = (& $tile -Monitor wide -From $snapDesk 3>$null) | Out-String
    Check 'control: -Monitor wide prints the 5x2 grid of the ultrawide' ($txt -match 'Grid 5x2 \(688 x 700 per slot\)') $txt
    Check 'control: -Monitor wide puts Claude at the ultrawide origin (x=1920, y=0)' ($txt -match 'x=1920 y=0 688x700') $txt
  }
  $sceneRole = Write-Json 'role-scene.json' ([pscustomobject]@{ id = 'role'; name = 'Role'; grids = $tplDesk.grids; pins = $tplDesk.pins; fill = $tplDesk.fill })
  Case 'control: a role-keyed scene on the same ids places by role, as today' {
    $r = Invoke-SceneFrom $sceneRole $snapDesk
    Check 'control: Chrome is in the wide role first cell (the ultrawide)' (OnCell $r 2003 1 (CellRect $ultDesk 5 2 0)) (Desc $r 2003)
    Check 'control: Claude fills the wide role cells 2 and 3' ((OnCell $r 2001 2 (CellRect $ultDesk 5 2 1)) -and (OnCell $r 2002 3 (CellRect $ultDesk 5 2 2))) "$(Desc $r 2001) | $(Desc $r 2002)"
  }
  Case 'control: a layout for another setup is not used when this setup has none' {
    $r = Invoke-SceneFrom $sceneDesk $snapTen
    # The template's Chrome pin has no window here, so its slot stays free: Claude 3001 takes the first cell.
    Check 'control: with no layout for this setup, the role template places Claude 3001 on the ultrawide first cell' (OnCell $r 3001 1 (CellRect $ultDesk 5 2 0)) (Desc $r 3001)
  }
} finally {
  foreach ($k in $saved.Keys) { if ($null -eq $saved[$k]) { Remove-Item "env:$k" -ErrorAction SilentlyContinue } else { Set-Item "env:$k" $saved[$k] } }
  Remove-Item -LiteralPath $run -Recurse -Force -ErrorAction SilentlyContinue
}
if ($script:fail) { "$($script:fail) check(s) failed."; exit 1 } else { 'All engine-layouts checks passed.' }
