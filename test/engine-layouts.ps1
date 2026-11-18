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
# Finer grid (L1, plan layout-free-build, items 2 to 5): the cases after the solo cases. One lone monitor, a 5x2 base, mult [2,1] or [1,2],
# unit fill, zones and held windows on the doubled slots. Each runs tile.ps1 -Scene <json> -From <snapshot> -Json, a dry run.
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
  # One seam writer for every seam run: $mons becomes the TILE_SCREENS_FILE list. Returns its path.
  function Write-Seam($mons) { $seam = Join-Path $run ('seam-' + [guid]::NewGuid().ToString('n') + '.json'); [IO.File]::WriteAllText($seam, (ConvertTo-Json -InputObject @($mons) -Depth 4 -Compress), $utf8); $seam }
  # -Text gives the scene run's text output (a screen that is not plugged in prints no grid line); else its -Json result.
  function Invoke-SceneSeam([string]$scenePath, $mons, [switch]$Text) {
    $env:TILE_SCREENS_FILE = Write-Seam $mons
    try { if ($Text) { (& $tile -Scene $scenePath -DryRun 3>$null) | Out-String } else { ConvertFrom-Json ((& $tile -Scene $scenePath -DryRun -Json 3>$null) -join '') } }
    finally { $env:TILE_SCREENS_FILE = $null }
  }
  function Invoke-MonitorsSeam($mons) {
    $env:TILE_SCREENS_FILE = Write-Seam $mons
    try { @(ConvertFrom-Json ((& $tile -Monitors 3>$null) -join '')) } finally { $env:TILE_SCREENS_FILE = $null }
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

  # ---- Item 9, fill: the layout's fill names the unplugged ultrawide and the browse apps (the browse category in scenes.json). ----
  $browseApps = @(([IO.File]::ReadAllText((Join-Path $root 'scenes.json'), $utf8) | ConvertFrom-Json).cats.PSObject.Properties | ? { $_.Value -eq 'browse' } | % { $_.Name })
  $fillUlt = [pscustomobject]@{ mon = $ULT; apps = $browseApps; skip = @(); sort = 'app' }
  $gFillDesk = @{}; $gFillDesk[$ULT] = [pscustomobject]@{ c = 5; r = 2 }; $gFillDesk[$LAP] = [pscustomobject]@{ c = 4; r = 1 }
  $layFill = Layout (Keyed $gFillDesk) @() $fillUlt
  $sceneFill = Write-Json 'fill-scene.json' ([pscustomobject]@{ id = 'fill'; name = 'Fill'; layouts = (KeyedOne $kDesk $layFill) })
  $resFill = Resolve-TileLayout $cfgRes ([pscustomobject]@{ id = 'fill'; name = 'Fill'; layouts = (KeyedOne $kDesk $layFill) }) $kLap
  $postFill = Write-Json 'post-fill.json' ([pscustomobject]@{ id = 'post-fill'; name = 'Post fill'; grids = $resFill.grids; pins = @($resFill.pins); zones = @($resFill.zones); fill = $resFill.fill; bay = @($resFill.bay) })

  Case 'item 9, fill: a fill that names the unplugged ultrawide lists its Chrome in left, not unlisted' {
    $lapObj = Get-Content -Raw -LiteralPath $lapOnly | ConvertFrom-Json
    $pf = Get-Content -Raw -LiteralPath $postFill | ConvertFrom-Json
    Check 'scope: the laptop-only snapshot has no ultrawide id, and Chrome is open' ((@($lapObj.monitors.id) -notcontains $ULT) -and @($lapObj.windows | ? { $_.app -eq 'chrome' }).Count -ge 1) (@($lapObj.monitors.id) -join ',')
    Check 'scope: the posted fill names the ultrawide id, and its apps include chrome' (([string]$pf.fill.mon -ceq $ULT) -and (@($pf.fill.apps) -contains 'chrome')) "fill: $(ConvertTo-Json -Depth 4 -Compress $pf.fill)"
    $r = Invoke-SceneFrom $postFill $lapOnly
    Check 'item 9, fill: Chrome is not placed (never moved)' (-not (PlacedOf $r 2003)) (Desc $r 2003)
    Check 'item 9, fill: Chrome is listed in left with why "Its screen is unplugged"' ((LeftWhy $r 2003) -ceq 'Its screen is unplugged') (Desc $r 2003)
    Check 'item 9, fill: Chrome is not in missing' (@($r.missing | ? { $_.app -eq 'chrome' }).Count -eq 0) "missing: $(@($r.missing | ? { $_.app -eq 'chrome' } | ConvertTo-Json -Compress))"
    Check 'item 9, fill: Teams is not listed in left as unplugged (the ruling covers only what the fill would place)' ((LeftWhy $r 2004) -notmatch 'unplugged') (Desc $r 2004)
  }
  Case 'item 9, fill: with the ultrawide plugged in, the same fill places Chrome on its first ultrawide cell' {
    $rd = Invoke-SceneFrom $sceneFill $snapDesk
    Check 'item 9, fill: plugged in, Chrome is in the ultrawide first cell' (OnCell $rd 2003 1 (CellRect $ultDesk 5 2 0)) (Desc $rd 2003)
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
    # Scope first: -Monitors lists the ultrawide id with role wide, read from the seam (tile.ps1 Get-MonitorObjects).
    $seamMons = Invoke-MonitorsSeam $seamObj
    Check 'scope: -Monitors under the seam lists the ultrawide id with role wide' (@($seamMons | ? { $_.id -ceq $ULT -and $_.role -ceq 'wide' }).Count -eq 1) "got: $(@($seamMons | % { "$($_.id)=$($_.role)" }) -join ' ')"
    # Subject: the scene pass on that screen prints its grid. A screen that is not plugged in prints none, so the same grid text shows it was found.
    $txt = Invoke-SceneSeam $sceneSeam $seamObj -Text
    Check 'seam: the scene pass on the ultrawide id prints its 5x2 grid' ($txt -match 'Grid 5x2 \(688 x 700 per slot\)') "output: $txt"
    $r = Invoke-SceneSeam $sceneSeam $seamObj
    Check 'seam: the pin on the ultrawide id reports no open window' (@($r.missing | ? { $_.app -eq 'zz-none' -and $_.why -eq 'no open window' }).Count -eq 1) "missing: $(@($r.missing | ConvertTo-Json -Compress))"
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

  # ---- Wide role (decision monitor-setups, item 14): with two or more monitors a built-in never takes wide. A lone plugged monitor holds
  # wide, as on main's Pick. Pick (tile.ps1) and Get-TileRoles (config.ps1) name the same wide monitor. Laptop with a portrait has no wide
  # monitor, so the scene's wide pin is not placed. ----
  $wideScene = Write-Json 'wide-role-scene.json' ([pscustomobject]@{ id = 'wide-role'; name = 'Wide role'; grids = [pscustomobject]@{ wide = [pscustomobject]@{ c = 2; r = 1 }; tall = [pscustomobject]@{ c = 1; r = 2 } }; pins = @([pscustomobject]@{ app = 'chrome'; match = ''; mon = 'wide'; slots = @(0) }, [pscustomobject]@{ app = 'claude'; match = ''; mon = 'tall'; slots = @(0) }); fill = [pscustomobject]@{ mon = 'wide'; apps = @(); skip = @(); sort = 'app' } })
  $chromeW = Win 4101 'chrome' 'Procore - Chrome' 0
  $claudeW = Win 4102 'claude' 'Claude - chat' 500
  $snapWideLap = Write-Snap 'wide-laptop.json' @($lapDesk) @($chromeW)
  $snapWidePort = Write-Snap 'wide-portrait.json' @($lapDesk, $tallB) @($chromeW, $claudeW)
  $snapWideUlt = Write-Snap 'wide-ultrawide.json' @($lapDesk, $ultDesk) @($chromeW, $claudeW)
  $snapSoloLap = Write-Snap 'solo-laptop.json' @($lapDesk) @($chromeW, $claudeW)
  # The wide monitor's id by Pick: tile.ps1 -Monitors prints each monitor's role. '' when no monitor takes wide.
  function Wide-Of($mons) { $w = @($mons | ? { $_.role -ceq 'wide' }); if ($w.Count) { [string]$w[0].id } else { '' } }
  # Assigned, not piped: ConvertFrom-Json emits a JSON array as one object, and @() around it would nest the list.
  function Pick-From([string]$snap) { $pm = ConvertFrom-Json ((& $tile -Monitors -From $snap 3>$null) -join ''); Wide-Of $pm }
  function Pick-Seam($list) { Wide-Of (Invoke-MonitorsSeam $list) }
  # The wide monitor's id by Get-TileRoles over the same monitors, stored as config.monitors stores them.
  function Config-Wide($list) {
    $m = New-Object PSObject
    foreach ($x in @($list)) { $m | Add-Member -NotePropertyName ([string]$x.id) -NotePropertyValue ([pscustomobject]@{ name = $x.name; builtin = [bool]$x.builtin; bw = $x.bw; bh = $x.bh }) }
    $roles = Get-TileRoles $m @($list | % { [string]$_.id })
    [string]$roles['wide']
  }
  function Named([string]$id) { if ($id) { $id } else { 'none' } }

  Case 'wide, laptop alone: a role-keyed scene pinned to wide places Chrome on the laptop, a lone plugged monitor holding wide' {
    $lapObj = Get-Content -Raw -LiteralPath $snapWideLap | ConvertFrom-Json
    Check 'scope: the snapshot holds the built-in laptop alone, with Chrome open' ((@($lapObj.monitors.id) -join ',') -ceq $LAP -and @($lapObj.windows | ? { $_.app -eq 'chrome' }).Count -eq 1) (@($lapObj.monitors.id) -join ',')
    $r = Invoke-SceneFrom $wideScene $snapWideLap
    Check 'wide, laptop alone: Chrome is in the first cell of the 2x1 wide grid, on the laptop' (OnCell $r 4101 1 (CellRect $lapDesk 2 1 0)) (Desc $r 4101)
    Check 'wide, laptop alone: Chrome is not listed in left' ((LeftWhy $r 4101) -eq '') "left why: '$(LeftWhy $r 4101)'"
  }
  Case 'wide, laptop and portrait: wide places nothing on the laptop, and the portrait takes tall' {
    $pObj = Get-Content -Raw -LiteralPath $snapWidePort | ConvertFrom-Json
    $wantPort = (@($LAP, $TAL) | Sort-Object) -join ','
    Check 'scope: the snapshot holds the laptop and the portrait, with Chrome and Claude open' (((@($pObj.monitors.id) | Sort-Object) -join ',') -ceq $wantPort -and @($pObj.windows).Count -eq 2) (@($pObj.monitors.id) -join ',')
    $r = Invoke-SceneFrom $wideScene $snapWidePort
    Check 'wide, laptop and portrait: Chrome is not placed on the laptop (wide does not fall back to the built-in)' (-not (PlacedOf $r 4101)) (Desc $r 4101)
    Check 'wide, laptop and portrait: Chrome is listed in left as "Its screen is unplugged"' ((LeftWhy $r 4101) -ceq 'Its screen is unplugged') (Desc $r 4101)
    Check 'control: wide, laptop and portrait: Claude takes the portrait tall cell 1' (OnCell $r 4102 1 (CellRect $tallB 1 2 0)) (Desc $r 4102)
  }
  Case 'control: wide, laptop and ultrawide: the ultrawide takes wide, and Chrome is in its first wide cell' {
    $uObj = Get-Content -Raw -LiteralPath $snapWideUlt | ConvertFrom-Json
    $wantUlt = (@($LAP, $ULT) | Sort-Object) -join ','
    Check 'scope: the snapshot holds the laptop and the ultrawide, with Chrome and Claude open' (((@($uObj.monitors.id) | Sort-Object) -join ',') -ceq $wantUlt -and @($uObj.windows).Count -eq 2) (@($uObj.monitors.id) -join ',')
    $r = Invoke-SceneFrom $wideScene $snapWideUlt
    Check 'control: Chrome is in the ultrawide first wide cell (2 columns)' (OnCell $r 4101 1 (CellRect $ultDesk 2 1 0)) (Desc $r 4101)
  }
  Case 'wide: Pick and Get-TileRoles name the same wide monitor on each setup, read by -From and by the seam' {
    $setups = @(
      [pscustomobject]@{ name = 'laptop alone'; list = @($lapDesk); snap = $snapWideLap },
      [pscustomobject]@{ name = 'laptop and portrait'; list = @($lapDesk, $tallB); snap = $snapWidePort },
      [pscustomobject]@{ name = 'laptop and ultrawide'; list = @($lapDesk, $ultDesk); snap = $snapWideUlt })
    foreach ($su in $setups) {
      $snapIds = @((Get-Content -Raw -LiteralPath $su.snap | ConvertFrom-Json).monitors).Count
      Check "scope: wide, $($su.name): the snapshot holds $(@($su.list).Count) monitor(s)" ($snapIds -eq @($su.list).Count) "snapshot monitors: $snapIds"
      $want = Config-Wide $su.list
      $fromPick = Pick-From $su.snap
      $seamPick = Pick-Seam $su.list
      Check "wide, $($su.name), -From: Pick names the same wide monitor as Get-TileRoles" ($fromPick -ceq $want) "Pick $(Named $fromPick), Get-TileRoles $(Named $want)"
      Check "wide, $($su.name), seam: Pick names the same wide monitor as Get-TileRoles" ($seamPick -ceq $want) "Pick $(Named $seamPick), Get-TileRoles $(Named $want)"
    }
  }
  # A lone plugged monitor holds wide, as on main's Pick: Get-TileRoles (config.ps1) and Pick name it for wide, on a laptop, a 16:9 external and a portrait.
  Case 'wide, lone plugged monitor: Get-TileRoles and Pick name it for wide, on a laptop, a 16:9 external and a portrait' {
    $snapLoneUlt = Write-Snap 'lone-ultrawide.json' @($ultDesk) @($chromeW)
    $snapLonePort = Write-Snap 'lone-portrait.json' @($tallB) @($chromeW)
    $lones = @(
      [pscustomobject]@{ name = 'laptop'; list = @($lapDesk); snap = $snapWideLap; want = $LAP },
      [pscustomobject]@{ name = 'ultrawide'; list = @($ultDesk); snap = $snapLoneUlt; want = $ULT },
      [pscustomobject]@{ name = 'portrait'; list = @($tallB); snap = $snapLonePort; want = $TAL })
    foreach ($lo in $lones) {
      $snapN = @((Get-Content -Raw -LiteralPath $lo.snap | ConvertFrom-Json).monitors).Count
      Check "scope: lone $($lo.name): the snapshot holds one monitor" ($snapN -eq 1) "snapshot monitors: $snapN"
      $want = Config-Wide $lo.list
      Check "lone $($lo.name): Get-TileRoles names it for wide" ($want -ceq $lo.want) "Get-TileRoles $(Named $want), want $(Named $lo.want)"
      $fromPick = Pick-From $lo.snap
      Check "lone $($lo.name), -From: Pick names the same wide monitor as Get-TileRoles" ($fromPick -ceq $want) "Pick $(Named $fromPick), Get-TileRoles $(Named $want)"
      $seamPick = Pick-Seam $lo.list
      Check "lone $($lo.name), seam: Pick names the same wide monitor as Get-TileRoles" ($seamPick -ceq $want) "Pick $(Named $seamPick), Get-TileRoles $(Named $want)"
    }
  }
  # -Proc with the default -Monitor wide. A snapshot names the built-in, so Pick must take it for wide, not throw.
  Case 'wide, laptop alone: -From -Proc chrome, with the default -Monitor wide, runs and prints its grid' {
    $lapObj = Get-Content -Raw -LiteralPath $snapWideLap | ConvertFrom-Json
    Check 'scope: the snapshot holds the built-in laptop alone' ((@($lapObj.monitors).Count -eq 1) -and [bool]$lapObj.monitors[0].builtin) "monitors: $(@($lapObj.monitors).Count)"
    $threw = ''; $txt = ''
    try { $txt = (& $tile -From $snapWideLap -Proc chrome -DryRun 3>$null) | Out-String } catch { $threw = $_.Exception.Message }
    Check 'wide, laptop alone: -From -Proc chrome, default -Monitor wide, does not throw and prints a grid' ($threw -eq '' -and $txt -match 'Grid \d+x\d+') $(if ($threw) { "threw: $threw" } else { "no grid line in: $($txt.Trim())" })
  }
  # Control, green on the old code: the seam path reads no built-in flag, so the laptop is a wide candidate there.
  Case 'control: laptop alone on the seam, -Proc chrome -DryRun with the default -Monitor wide prints a grid' {
    $env:TILE_SCREENS_FILE = Write-Seam @($lapDesk)
    try { $txt = (& $tile -Proc chrome -DryRun 3>$null) | Out-String } finally { $env:TILE_SCREENS_FILE = $null }
    Check 'control: seam laptop alone, -Proc chrome -DryRun, default -Monitor wide, prints its grid' ($txt -match 'Grid \d+x\d+') "output: $($txt.Trim())"
  }
  # -Proc with -Monitor wide on a laptop and a portrait: no monitor takes wide, since a built-in never does with two or more monitors (decision
  # monitor-setups item 14). The direct path falls back to the widest screen, the laptop (its bounds width 1920 beats the portrait's 1080), as
  # main did (coordinator ruling 2026-11-17 19:03 CST), and does not throw. These runs read a -From snapshot, whose builtin flags Pick reads.
  # The TILE_SCREENS_FILE seam, without -Json or -Monitors, reads no builtin flag, so its laptop is a wide candidate and the seam never shows the no-wide case.
  $snapWidePortX = Write-Snap 'wide-portrait-x.json' @($lapDesk, $tallB) @((Win 4103 'x' 'Doc X' 0))
  Case 'wide, laptop and portrait: -Proc x with the default -Monitor wide does not throw, and lands on the laptop' {
    $pObj = Get-Content -Raw -LiteralPath $snapWidePortX | ConvertFrom-Json
    $wantPort = (@($LAP, $TAL) | Sort-Object) -join ','
    Check 'scope: the snapshot holds the laptop and the portrait' (((@($pObj.monitors.id) | Sort-Object) -join ',') -ceq $wantPort) (@($pObj.monitors.id) -join ',')
    $wideNamed = Pick-From $snapWidePortX
    Check 'scope: no monitor takes wide on that snapshot' ($wideNamed -ceq '') "Pick names $(Named $wideNamed)"
    $threw = ''; $txt = ''
    try { $txt = (& $tile -From $snapWidePortX -Proc x -DryRun 3>$null) | Out-String } catch { $threw = $_.Exception.Message }
    Check 'wide, laptop and portrait, -Proc x, default -Monitor wide: does not throw' ($threw -eq '') "threw: $threw"
    Check 'wide, laptop and portrait, -Proc x, default -Monitor wide: window x lands on the laptop (x=0 y=0 384x520)' ($txt -match 'x=0 y=0 384x520') "output: $($txt.Trim())"
  }
  Case 'wide, laptop and portrait: -Proc x with -Monitor wide given explicitly does not throw, and lands on the laptop' {
    Check 'scope: no monitor takes wide on that snapshot' ((Pick-From $snapWidePortX) -ceq '') "Pick names $(Named (Pick-From $snapWidePortX))"
    $threw = ''; $txt = ''
    try { $txt = (& $tile -From $snapWidePortX -Proc x -Monitor wide -DryRun 3>$null) | Out-String } catch { $threw = $_.Exception.Message }
    Check 'wide, laptop and portrait, -Proc x, explicit -Monitor wide: does not throw' ($threw -eq '') "threw: $threw"
    Check 'wide, laptop and portrait, -Proc x, explicit -Monitor wide: window x lands on the laptop (x=0 y=0 384x520)' ($txt -match 'x=0 y=0 384x520') "output: $($txt.Trim())"
  }
  # The same fallback with the portrait listed first. The widest screen is still the laptop (1920 beats 1080), so the list order must not pick it.
  # A fallback that takes the first listed screen lands the window on the portrait (x=1920) and fails the rect check.
  $snapPortFirst = Write-Snap 'wide-portrait-first.json' @($tallB, $lapDesk) @((Win 4103 'x' 'Doc X' 0))
  Case 'wide, portrait listed first: -Proc x with the default -Monitor wide lands on the laptop, the widest, not the first listed' {
    $pObj = Get-Content -Raw -LiteralPath $snapPortFirst | ConvertFrom-Json
    $firstId = [string](@($pObj.monitors.id)[0])
    Check 'scope: the portrait is listed first in the snapshot' ($firstId -ceq $TAL) "first listed: $firstId"
    Check 'scope: no monitor takes wide on that snapshot' ((Pick-From $snapPortFirst) -ceq '') "Pick names $(Named (Pick-From $snapPortFirst))"
    $threw = ''; $txt = ''
    try { $txt = (& $tile -From $snapPortFirst -Proc x -DryRun 3>$null) | Out-String } catch { $threw = $_.Exception.Message }
    Check 'wide, portrait listed first, -Proc x, default -Monitor wide: does not throw' ($threw -eq '') "threw: $threw"
    Check 'wide, portrait listed first, -Proc x, default -Monitor wide: window x lands on the laptop (x=0 y=0 384x520)' ($txt -match 'x=0 y=0 384x520') "output: $($txt.Trim())"
  }
  Case 'solo: a laptop alone places Chrome and Claude on the laptop, whichever role the starter pins Chrome to' {
    $solo = @(([IO.File]::ReadAllText((Join-Path $root 'scenes.json'), $utf8) | ConvertFrom-Json).scenes | ? { $_.id -eq 'solo' })[0]
    $soloPin = @($solo.pins | ? { $_.app -eq 'chrome' })
    Check 'scope: the Solo starter has one Chrome pin' ($soloPin.Count -eq 1) "Chrome pins: $($soloPin.Count)"
    $soloFile = Write-Json 'solo-starter.json' $solo
    $r = Invoke-SceneFrom $soloFile $snapSoloLap
    Check 'solo, laptop alone: Chrome is on the laptop left half' (OnCell $r 4101 1 (CellRect $lapDesk 2 1 0)) (Desc $r 4101)
    Check 'solo, laptop alone: Claude is on the laptop right half' (OnCell $r 4102 2 (CellRect $lapDesk 2 1 1)) (Desc $r 4102)
  }
  # The Solo starter resolved for a lone built-in 1920x1080 (the key with no layout, as the caller resolves it) is posted by id. Its 2x1 laptop
  # grid puts Chrome left and Claude right, the rects the raw Solo scene gives on the role path (coordinator ruling 2026-11-17 18:07 CST).
  Case 'solo, resolved: the lone built-in resolves Solo to its 2x1 wide cell, and the posted layout puts Chrome left and Claude right' {
    $solo = @(([IO.File]::ReadAllText((Join-Path $root 'scenes.json'), $utf8) | ConvertFrom-Json).scenes | ? { $_.id -eq 'solo' })[0]
    $wideCell = "$($solo.grids.wide.c),$($solo.grids.wide.r)"; $lapCell = "$($solo.grids.laptop.c),$($solo.grids.laptop.r)"
    Check 'scope: the Solo starter has a 2x1 wide cell and a 1x1 laptop cell' ($wideCell -ceq '2,1' -and $lapCell -ceq '1,1') "wide $wideCell, laptop $lapCell"
    $cfgSolo = [pscustomobject]@{}
    $kSolo = Register-TileSetup $cfgSolo @($lapDesk)
    $roleSolo = Get-TileRoles $cfgSolo.monitors @($LAP)
    Check 'scope: the lone built-in holds the laptop and wide roles' ([string]$roleSolo['laptop'] -ceq $LAP -and [string]$roleSolo['wide'] -ceq $LAP) "laptop '$([string]$roleSolo['laptop'])', wide '$([string]$roleSolo['wide'])'"
    $soloRaw = Write-Json 'solo-raw.json' $solo
    $raw = Invoke-SceneFrom $soloRaw $snapSoloLap
    Check 'control: the raw Solo scene on the role path puts Chrome left and Claude right' ((OnCell $raw 4101 1 (CellRect $lapDesk 2 1 0)) -and (OnCell $raw 4102 2 (CellRect $lapDesk 2 1 1))) "$(Desc $raw 4101) | $(Desc $raw 4102)"
    $resSolo = Resolve-TileLayout $cfgSolo $solo $kSolo
    $postSolo = Write-Json 'post-solo.json' ([pscustomobject]@{ id = 'post-solo'; name = 'Post solo'; grids = $resSolo.grids; pins = @($resSolo.pins); zones = @($resSolo.zones); fill = $resSolo.fill; bay = @($resSolo.bay) })
    $r = Invoke-SceneFrom $postSolo $snapSoloLap
    Check 'solo, resolved: Chrome is on the laptop left half (960 wide)' (OnCell $r 4101 1 (CellRect $lapDesk 2 1 0)) (Desc $r 4101)
    Check 'solo, resolved: Claude is on the laptop right half' (OnCell $r 4102 2 (CellRect $lapDesk 2 1 1)) (Desc $r 4102)
    $same = [bool](PlacedOf $r 4101) -and [bool](PlacedOf $r 4102) -and ((RectOf (PlacedOf $r 4101)) -ceq (RectOf (PlacedOf $raw 4101))) -and ((RectOf (PlacedOf $r 4102)) -ceq (RectOf (PlacedOf $raw 4102)))
    Check 'solo, resolved: the rects match the raw Solo scene on the role path' $same "resolved: $(Desc $r 4101) | $(Desc $r 4102); raw: $(Desc $raw 4101) | $(Desc $raw 4102)"
  }
  # ---- Finer grid (L1, plan layout-free-build, items 2 to 5). One lone monitor holds the wide role, so each run is the wide grid of a
  # 5x2 base. mult [2,1] splits each cell in two along x; mult [1,2] along y. A base cell keeps CellRect's int cut, so a split cell's
  # halves must tile it exactly. Every run is a dry run (-From).
  function FgMon([int]$w, [int]$h) { Mon "FG-${w}x$h" 0 0 $w $h $w $h }
  function FgWin([int]$id, $app, $title, [int]$x, [int]$y = 0) { [pscustomobject]@{ id = $id; app = $app; title = $title; x = $x; y = $y; w = 400; h = 300 } }
  function FgPin($app, $match, [int[]]$slots) { [pscustomobject]@{ app = $app; match = $match; mon = 'wide'; slots = @($slots) } }
  function FgGrid([int]$mx, [int]$my) { [pscustomobject]@{ c = 5; r = 2; mult = @($mx, $my) } }
  function FgScene([string]$name, $grid, $pins = @(), $fill = $null, $zones = @()) { Write-Json $name ([pscustomobject]@{ id = $name; name = $name; grids = [pscustomobject]@{ wide = $grid }; pins = @($pins); zones = @($zones); fill = $fill }) }
  # The slots a placed window covers, sorted, as the output numbers them (1-based): '1+2'.
  function SlotKey($p) { (@($p.slots) | Sort-Object) -join '+' }

  Case 'control: a lone 5x2 wide grid with no mult cuts 1365x1001 into L0 cells: a pin on slot 2 gets the L0 cell rect' {
    $m = FgMon 1365 1001
    $snap = Write-Snap 'fg-base-snap.json' @($m) @((FgWin 5000 'chrome' 'Base A' 0))
    $sc = FgScene 'fg-base-scene.json' ([pscustomobject]@{ c = 5; r = 2 }) @((FgPin 'chrome' 'Base A' @(1)))
    $r = Invoke-SceneFrom $sc $snap
    Check 'control: the pin on slot 2 is placed at the L0 cell rect (x 273, 273x500)' ((RectOf (PlacedOf $r 5000)) -ceq (CellRect $m 5 2 1)) (Desc $r 5000)
  }
  Case 'L1 halves, horizontal: the two halves of a 5x2 cell tile it exactly, on 1365x1001 (odd width), 4096x1680 and 1080x1872' {
    foreach ($dim in @(@(1365, 1001), @(4096, 1680), @(1080, 1872))) {
      $w = [int]$dim[0]; $h = [int]$dim[1]; $tag = "${w}x$h"; $m = FgMon $w $h
      $snap = Write-Snap "fg-halves-$tag.json" @($m) @((FgWin 5101 'chrome' 'Half A' 0), (FgWin 5102 'claude' 'Half B' 500))
      $sc = FgScene "fg-halves-$tag-scene.json" (FgGrid 2 1) @((FgPin 'chrome' 'Half A' @(0)), (FgPin 'claude' 'Half B' @(1)))
      $r = Invoke-SceneFrom $sc $snap
      $a = PlacedOf $r 5101; $b = PlacedOf $r 5102; $cw = [int]($w / 5); $ch = [int]($h / 2)
      Check "L1 halves ${tag}: both halves are placed" ([bool]($a -and $b)) "$(Desc $r 5101) | $(Desc $r 5102)"
      Check "L1 halves ${tag}: the left half starts at the old cell's left edge (x 0)" ([bool]($a -and [int]$a.x -eq 0)) (Desc $r 5101)
      Check "L1 halves ${tag}: the right half starts where the left half ends (no gap, no overlap)" ([bool]($a -and $b -and [int]$b.x -eq [int]$a.x + [int]$a.w)) "$(Desc $r 5101) | $(Desc $r 5102)"
      Check "L1 halves ${tag}: the right half ends at the old cell's right edge (x $cw)" ([bool]($b -and [int]$b.x + [int]$b.w -eq $cw)) (Desc $r 5102)
      Check "L1 halves ${tag}: both halves have the old cell's top and height (y 0, h $ch)" ([bool]($a -and $b -and [int]$a.y -eq 0 -and [int]$b.y -eq 0 -and [int]$a.h -eq $ch -and [int]$b.h -eq $ch)) "$(Desc $r 5101) | $(Desc $r 5102)"
    }
  }
  Case 'L1 fill, horizontal: a unit of [2,1] gives each filled window one block of two slots, the old cell''s full width' {
    $m = FgMon 1365 1001
    $fill = [pscustomobject]@{ mon = 'wide'; apps = @('claude'); skip = @(); sort = 'app'; unit = @(2, 1) }
    $sc = FgScene 'fg-unit-scene.json' (FgGrid 2 1) @() $fill
    $r = Invoke-SceneFrom $sc (Write-Snap 'fg-unit3.json' @($m) @((FgWin 5201 'claude' 'Fill 1' 0), (FgWin 5202 'claude' 'Fill 2' 500), (FgWin 5203 'claude' 'Fill 3' 1000)))
    Check 'scope: the three claude windows are all placed' (@($r.placed).Count -eq 3) "placed $(@($r.placed).Count)"
    for ($i = 0; $i -lt 3; $i++) {
      $p = PlacedOf $r (5201 + $i)
      Check "L1 fill: window $($i + 1) takes slots $(2 * $i + 1)+$(2 * $i + 2), at the old cell's rect $(CellRect $m 5 2 $i)" ([bool]($p -and (SlotKey $p) -ceq "$(2 * $i + 1)+$(2 * $i + 2)" -and (RectOf $p) -ceq (CellRect $m 5 2 $i))) (Desc $r (5201 + $i))
    }
    $rf = Invoke-SceneFrom $sc (Write-Snap 'fg-unit10.json' @($m) @(1..10 | % { FgWin (5300 + $_) 'claude' "Full $_" (100 * $_) }))
    $bad = @()
    for ($i = 0; $i -lt 10; $i++) {
      $row = [Math]::Floor($i / 5); $col = $i % 5
      $want = "$($row * 10 + 2 * $col + 1)+$($row * 10 + 2 * $col + 2)"
      $p = PlacedOf $rf (5301 + $i)
      if (-not ($p -and (SlotKey $p) -ceq $want -and (RectOf $p) -ceq (CellRect $m 5 2 $i))) { $bad += "$(Desc $rf (5301 + $i)), want slots $want" }
    }
    Check 'L1 fill, full size: ten windows take the ten blocks, one per old cell, each at its old rect' ($bad.Count -eq 0 -and @($rf.placed).Count -eq 10) "$($bad -join ' | ')"
    $re = Invoke-SceneFrom $sc (Write-Snap 'fg-unit-empty.json' @($m) @())
    Check 'control: unit fill with no window places nothing and lists nothing left or missing' (@($re.placed).Count -eq 0 -and @($re.left).Count -eq 0 -and @($re.missing).Count -eq 0) "placed $(@($re.placed).Count), left $(@($re.left).Count), missing $(@($re.missing).Count)"
  }
  Case 'L1 zone, horizontal: a zone on the two halves of one cell takes one half each' {
    $m = FgMon 1365 1001; $cw = [int]($m.w / 5)
    $zone = [pscustomobject]@{ mon = 'wide'; slots = @(0, 1); app = 'chrome' }
    $sc = FgScene 'fg-zone-scene.json' (FgGrid 2 1) @() $null @($zone)
    $r = Invoke-SceneFrom $sc (Write-Snap 'fg-zone-snap.json' @($m) @((FgWin 5401 'chrome' 'Zone A' 0), (FgWin 5402 'chrome' 'Zone B' 500)))
    $a = PlacedOf $r 5401; $b = PlacedOf $r 5402
    Check 'L1 zone: Zone A takes slot 1, the left half of the old cell' ([bool]($a -and (SlotKey $a) -ceq '1' -and [int]$a.x -eq 0 -and [int]$a.w -gt 0 -and [int]$a.w -lt $cw)) (Desc $r 5401)
    Check 'L1 zone: Zone B takes slot 2, and the two halves tile the old cell (no gap, no overlap)' ([bool]($a -and $b -and (SlotKey $b) -ceq '2' -and [int]$b.x -eq [int]$a.x + [int]$a.w -and [int]$b.x + [int]$b.w -eq $cw)) (Desc $r 5402)
  }
  Case 'L1 held, horizontal: a held window on slot 2 stays in the right half of the old cell' {
    $m = FgMon 1365 1001; $cw = [int]($m.w / 5); $ch = [int]($m.h / 2)
    $fill = [pscustomobject]@{ mon = 'wide'; apps = @(); skip = @(); sort = 'app'; off = $true; held = @([pscustomobject]@{ app = 'claude'; title = 'Held A'; mon = 'wide'; slots = @(1) }) }
    $sc = FgScene 'fg-held-scene.json' (FgGrid 2 1) @() $fill
    $r = Invoke-SceneFrom $sc (Write-Snap 'fg-held-snap.json' @($m) @((FgWin 5501 'claude' 'Held A' 0)))
    $p = PlacedOf $r 5501
    Check 'L1 held: Held A takes slot 2' ([bool]($p -and (SlotKey $p) -ceq '2')) (Desc $r 5501)
    Check "L1 held: Held A is the right half of the old cell (x above 0, ends at x $cw, y 0, h $ch)" ([bool]($p -and [int]$p.x -gt 0 -and [int]$p.x + [int]$p.w -eq $cw -and [int]$p.y -eq 0 -and [int]$p.h -eq $ch)) (Desc $r 5501)
  }
  Case 'L1 stacked halves: the two halves of a 5x2 cell tile it exactly, on 1365x1002 (a 501-high cell, so the halves are unequal)' {
    $m = FgMon 1365 1002; $cw = [int]($m.w / 5); $ch = [int]($m.h / 2)
    $snap = Write-Snap 'fg-sh-snap.json' @($m) @((FgWin 5601 'chrome' 'Top A' 0), (FgWin 5602 'claude' 'Bottom B' 500))
    $sc = FgScene 'fg-sh-scene.json' (FgGrid 1 2) @((FgPin 'chrome' 'Top A' @(0)), (FgPin 'claude' 'Bottom B' @(5)))
    $r = Invoke-SceneFrom $sc $snap
    $a = PlacedOf $r 5601; $b = PlacedOf $r 5602
    Check 'L1 stacked halves: both halves are placed' ([bool]($a -and $b)) "$(Desc $r 5601) | $(Desc $r 5602)"
    Check "L1 stacked halves: both halves span the old cell's width (x 0, w $cw)" ([bool]($a -and $b -and [int]$a.x -eq 0 -and [int]$b.x -eq 0 -and [int]$a.w -eq $cw -and [int]$b.w -eq $cw)) "$(Desc $r 5601) | $(Desc $r 5602)"
    Check 'L1 stacked halves: the bottom half starts where the top half ends (no gap, no overlap)' ([bool]($a -and $b -and [int]$a.y -eq 0 -and [int]$b.y -eq [int]$a.y + [int]$a.h)) "$(Desc $r 5601) | $(Desc $r 5602)"
    Check "L1 stacked halves: the bottom half ends at the old cell's bottom edge (y $ch)" ([bool]($b -and [int]$b.y + [int]$b.h -eq $ch)) (Desc $r 5602)
  }
  Case 'L1 stacked fill: a unit of [1,2] gives each filled window one block of two slots, the old cell''s full height' {
    $m = FgMon 1365 1002
    $fill = [pscustomobject]@{ mon = 'wide'; apps = @('claude'); skip = @(); sort = 'app'; unit = @(1, 2) }
    $sc = FgScene 'fg-su-scene.json' (FgGrid 1 2) @() $fill
    $r = Invoke-SceneFrom $sc (Write-Snap 'fg-su-snap.json' @($m) @((FgWin 5701 'claude' 'Stack 1' 0), (FgWin 5702 'claude' 'Stack 2' 500), (FgWin 5703 'claude' 'Stack 3' 1000)))
    Check 'scope: the three claude windows are all placed' (@($r.placed).Count -eq 3) "placed $(@($r.placed).Count)"
    for ($i = 0; $i -lt 3; $i++) {
      $p = PlacedOf $r (5701 + $i)
      Check "L1 stacked fill: window $($i + 1) takes slots $($i + 1)+$($i + 6), at the old cell's rect $(CellRect $m 5 2 $i)" ([bool]($p -and (SlotKey $p) -ceq "$($i + 1)+$($i + 6)" -and (RectOf $p) -ceq (CellRect $m 5 2 $i))) (Desc $r (5701 + $i))
    }
  }
  Case 'L1 stacked zone: a zone on the two halves of one cell takes one half each' {
    $m = FgMon 1365 1002; $cw = [int]($m.w / 5); $ch = [int]($m.h / 2)
    $zone = [pscustomobject]@{ mon = 'wide'; slots = @(0, 5); app = 'chrome' }
    $sc = FgScene 'fg-sz-scene.json' (FgGrid 1 2) @() $null @($zone)
    $r = Invoke-SceneFrom $sc (Write-Snap 'fg-sz-snap.json' @($m) @((FgWin 5801 'chrome' 'Zone Top' 0 0), (FgWin 5802 'chrome' 'Zone Bottom' 0 600)))
    $a = PlacedOf $r 5801; $b = PlacedOf $r 5802
    Check "L1 stacked zone: Zone Top takes slot 1, the top half of the old cell (x 0, w $cw)" ([bool]($a -and (SlotKey $a) -ceq '1' -and [int]$a.x -eq 0 -and [int]$a.w -eq $cw -and [int]$a.y -eq 0 -and [int]$a.h -gt 0 -and [int]$a.h -lt $ch)) (Desc $r 5801)
    Check 'L1 stacked zone: Zone Bottom takes slot 6, and the two halves tile the old cell (no gap, no overlap)' ([bool]($a -and $b -and (SlotKey $b) -ceq '6' -and [int]$b.y -eq [int]$a.y + [int]$a.h -and [int]$b.y + [int]$b.h -eq $ch)) (Desc $r 5802)
  }
  Case 'L1 stacked held: a held window on slot 6 stays in the bottom half of the old cell' {
    $m = FgMon 1365 1002; $cw = [int]($m.w / 5); $ch = [int]($m.h / 2)
    $fill = [pscustomobject]@{ mon = 'wide'; apps = @(); skip = @(); sort = 'app'; off = $true; held = @([pscustomobject]@{ app = 'claude'; title = 'Held B'; mon = 'wide'; slots = @(5) }) }
    $sc = FgScene 'fg-shh-scene.json' (FgGrid 1 2) @() $fill
    $r = Invoke-SceneFrom $sc (Write-Snap 'fg-shh-snap.json' @($m) @((FgWin 5901 'claude' 'Held B' 0 0)))
    $p = PlacedOf $r 5901
    Check 'L1 stacked held: Held B takes slot 6' ([bool]($p -and (SlotKey $p) -ceq '6')) (Desc $r 5901)
    Check "L1 stacked held: Held B is the bottom half of the old cell (y above 0, ends at y $ch, x 0, w $cw)" ([bool]($p -and [int]$p.y -gt 0 -and [int]$p.y + [int]$p.h -eq $ch -and [int]$p.x -eq 0 -and [int]$p.w -eq $cw)) (Desc $r 5901)
  }
} finally {
  foreach ($k in $saved.Keys) { if ($null -eq $saved[$k]) { Remove-Item "env:$k" -ErrorAction SilentlyContinue } else { Set-Item "env:$k" $saved[$k] } }
  Remove-Item -LiteralPath $run -Recurse -Force -ErrorAction SilentlyContinue
}
if ($script:fail) { "$($script:fail) check(s) failed."; exit 1 } else { 'All engine-layouts checks passed.' }
