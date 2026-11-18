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
# Free Layout areas (L3, plan layout-free-build, items 24 to 26, and item G): the cases at the end. Areas sit in grids.wide.free.areas of a
# role-keyed scene. Item G's Get-CollapsedAreas is read through tile.ps1 -Lib in a child powershell; its contract is in that section.
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
  # ---- Free Layout areas (L3, plan layout-free-build, items 24 to 26). grids.wide = {c, r, free: {areas}}. An area is a rect of fractions of the
  # work area (x, y, w, h) and holds a pin (an index into pins), an app and title, or nothing. A pinned or named area takes its window at the
  # area's rect. The fill takes the first empty area in reading order. Zones pause while areas are on. Each line is rounded once, so neighbours
  # share its pixel. Each run is a dry run (-From). Fractions are written so each line's pixel is known or sits within a pixel of a stated point.
  function FreeArea($rect, $pin = $null, $app = $null, $title = $null) {
    $a = [pscustomobject]@{ rect = @([double[]]$rect) }
    if ($null -ne $pin) { $a | Add-Member -NotePropertyName pin -NotePropertyValue $pin }
    if ($app) { $a | Add-Member -NotePropertyName app -NotePropertyValue $app; $a | Add-Member -NotePropertyName title -NotePropertyValue $title }
    $a
  }
  function FreeGrid([int]$c, [int]$r, $areas) { [pscustomobject]@{ c = $c; r = $r; free = [pscustomobject]@{ areas = @($areas) } } }
  $l3Sizes = @(@(1365, 1001), @(3440, 1392), @(1080, 1872), @(4096, 1680))

  Case 'L3 pins: each area takes the window its pin names, at the area''s own rect, on each of the four work areas' {
    foreach ($dim in $l3Sizes) {
      $w = [int]$dim[0]; $h = [int]$dim[1]; $tag = "${w}x$h"; $m = FgMon $w $h
      $px = [int][Math]::Floor($w * 0.4); $f = $px / $w
      $areas = @((FreeArea @(0, 0, $f, 1) 0), (FreeArea @($f, 0, (1 - $f), 1) 1))
      $sc = FgScene "L3-pins-$tag-scene.json" (FreeGrid 2 1 $areas) @((FgPin 'chrome' 'Left' @(0)), (FgPin 'claude' 'Right' @(1)))
      $snap = Write-Snap "L3-pins-$tag.json" @($m) @((FgWin 6001 'chrome' 'Left side' 0), (FgWin 6002 'claude' 'Right side' 500))
      $r = Invoke-SceneFrom $sc $snap
      Check "L3 pins ${tag}: scope, no pin is missing" (@($r.missing).Count -eq 0) "missing: $(@($r.missing | % { $_.app }) -join ',')"
      Check "L3 pins ${tag}: Left side takes the left area, 0,0 ${px}x$h" ((RectOf (PlacedOf $r 6001)) -ceq "0,0,$px,$h") (Desc $r 6001)
      Check "L3 pins ${tag}: Right side takes the right area, $px,0 $($w - $px)x$h" ((RectOf (PlacedOf $r 6002)) -ceq "$px,0,$($w - $px),$h") (Desc $r 6002)
    }
  }
  Case 'L3 areas: an area named by app and title takes that window, and an empty area takes nothing (four work areas)' {
    foreach ($dim in $l3Sizes) {
      $w = [int]$dim[0]; $h = [int]$dim[1]; $tag = "${w}x$h"; $m = FgMon $w $h
      $px = [int][Math]::Floor($w * 0.4); $py = [int][Math]::Floor($h * 0.3); $fx = $px / $w; $fy = $py / $h
      $areas = @((FreeArea @(0, 0, $fx, $fy) 0), (FreeArea @($fx, 0, (1 - $fx), $fy) $null 'claude' 'Notes'), (FreeArea @(0, $fy, $fx, (1 - $fy))), (FreeArea @($fx, $fy, (1 - $fx), (1 - $fy))))
      $sc = FgScene "L3-named-$tag-scene.json" (FreeGrid 2 2 $areas) @((FgPin 'chrome' 'Top left' @(0)))
      $snap = Write-Snap "L3-named-$tag.json" @($m) @((FgWin 6101 'chrome' 'Top left' 0), (FgWin 6102 'claude' 'Notes' 500), (FgWin 6103 'outlook' 'Spare' 1000))
      $r = Invoke-SceneFrom $sc $snap
      Check "L3 named ${tag}: scope, the pin is not missing" (@($r.missing).Count -eq 0) "missing: $(@($r.missing | % { $_.app }) -join ',')"
      Check "L3 named ${tag}: the pinned window takes the top-left area, 0,0 ${px}x$py" ((RectOf (PlacedOf $r 6101)) -ceq "0,0,$px,$py") (Desc $r 6101)
      Check "L3 named ${tag}: the window named by app and title takes the top-right area, $px,0 $($w - $px)x$py" ((RectOf (PlacedOf $r 6102)) -ceq "$px,0,$($w - $px),$py") (Desc $r 6102)
      Check "L3 named ${tag}: a window no area names is not placed" (-not (PlacedOf $r 6103)) (Desc $r 6103)
    }
  }
  Case 'L3 control: a free layout with no open window places nothing and lists nothing left or missing' {
    $m = FgMon 1365 1001
    $areas = @((FreeArea @(0, 0, 0.4, 0.3) $null 'claude' 'Notes'), (FreeArea @(0.4, 0, 0.6, 0.3) $null 'outlook' 'Inbox'), (FreeArea @(0, 0.3, 1, 0.7)))
    $sc = FgScene 'L3-empty-scene.json' (FreeGrid 2 2 $areas)
    $r = Invoke-SceneFrom $sc (Write-Snap 'L3-empty.json' @($m) @())
    Check 'L3 control: nothing is placed' (@($r.placed).Count -eq 0) "placed: $(@($r.placed).Count)"
    Check 'L3 control: nothing is left or missing' (@($r.left).Count -eq 0 -and @($r.missing).Count -eq 0) "left: $(@($r.left).Count) missing: $(@($r.missing).Count)"
  }
  Case 'L3 full size: ten areas, each named by one window, take the ten windows at their cell rects (1365x1001)' {
    $m = FgMon 1365 1001; $cw = [int]($m.w / 5); $ch = [int]($m.h / 2)
    $areas = @(0..9 | % { FreeArea @((($_ % 5) * $cw / $m.w), ([Math]::Floor($_ / 5) * $ch / $m.h), ($cw / $m.w), ($ch / $m.h)) $null 'claude' "Cell $($_ + 1)" })
    $sc = FgScene 'L3-full-scene.json' (FreeGrid 5 2 $areas)
    $wins = @(0..9 | % { FgWin (6201 + $_) 'claude' "Cell $($_ + 1)" (100 * $_) })
    $r = Invoke-SceneFrom $sc (Write-Snap 'L3-full.json' @($m) $wins)
    Check 'L3 full size: all ten windows are placed' (@($r.placed).Count -eq 10) "placed $(@($r.placed).Count), left $(@($r.left).Count), missing $(@($r.missing).Count)"
    $bad = @(0..9 | ? { -not ((RectOf (PlacedOf $r (6201 + $_))) -ceq (CellRect $m 5 2 $_)) } | % { "Cell $($_ + 1): $(Desc $r (6201 + $_))" })
    Check 'L3 full size: each window sits at its cell rect' ($bad.Count -eq 0) ($bad -join ' | ')
  }
  Case 'L3 odd width: neighbours share the pixel of their line, and the far edge lands on the right edge (1365 wide)' {
    $m = FgMon 1365 1001
    $areas = @((FreeArea @(0, 0, 0.3125, 1) 0), (FreeArea @(0.3125, 0, 0.1875, 1) 1), (FreeArea @(0.5, 0, 0.5, 1) 2))
    $sc = FgScene 'L3-odd-scene.json' (FreeGrid 3 1 $areas) @((FgPin 'chrome' 'Col A' @(0)), (FgPin 'claude' 'Col B' @(1)), (FgPin 'ms-teams' 'Col C' @(2)))
    $r = Invoke-SceneFrom $sc (Write-Snap 'L3-odd.json' @($m) @((FgWin 6301 'chrome' 'Col A' 0), (FgWin 6302 'claude' 'Col B' 500), (FgWin 6303 'ms-teams' 'Col C' 1000)))
    $a = PlacedOf $r 6301; $b = PlacedOf $r 6302; $c3 = PlacedOf $r 6303
    Check 'L3 odd width: scope, all three windows are placed' ([bool]($a -and $b -and $c3)) "$(Desc $r 6301) | $(Desc $r 6302) | $(Desc $r 6303)"
    if (-not ($a -and $b -and $c3)) { return }
    Check 'L3 odd width: the first line sits within a pixel of 5/16 of the width (426.56)' ([Math]::Abs(([double]$a.x + $a.w) - 426.5625) -lt 1) (Desc $r 6301)
    Check 'L3 odd width: the second line sits within a pixel of half the width (682.5)' ([Math]::Abs(([double]$b.x + $b.w) - 682.5) -lt 1) (Desc $r 6302)
    Check 'L3 odd width: the first area ends where the second starts (no gap, no overlap)' (([int]$a.x + [int]$a.w) -eq [int]$b.x) "$(Desc $r 6301) | $(Desc $r 6302)"
    Check 'L3 odd width: the second area ends where the third starts (no gap, no overlap)' (([int]$b.x + [int]$b.w) -eq [int]$c3.x) "$(Desc $r 6302) | $(Desc $r 6303)"
    Check 'L3 odd width: the third area ends on the right edge (1365)' (([int]$c3.x + [int]$c3.w) -eq 1365) (Desc $r 6303)
    Check 'L3 odd width: every area starts at the top and is 1001 high' ([bool]($a.y -eq 0 -and $b.y -eq 0 -and $c3.y -eq 0 -and $a.h -eq 1001 -and $b.h -eq 1001 -and $c3.h -eq 1001)) "$(Desc $r 6301) | $(Desc $r 6302) | $(Desc $r 6303)"
  }
  Case 'L3 odd height: stacked neighbours share the pixel of their line, and the bottom lands on the bottom edge (1001 high)' {
    $m = FgMon 1365 1001
    $areas = @((FreeArea @(0, 0, 1, 0.3125) 0), (FreeArea @(0, 0.3125, 1, 0.1875) 1), (FreeArea @(0, 0.5, 1, 0.5) 2))
    $sc = FgScene 'L3-oddh-scene.json' (FreeGrid 1 3 $areas) @((FgPin 'chrome' 'Row A' @(0)), (FgPin 'claude' 'Row B' @(1)), (FgPin 'ms-teams' 'Row C' @(2)))
    $r = Invoke-SceneFrom $sc (Write-Snap 'L3-oddh.json' @($m) @((FgWin 6311 'chrome' 'Row A' 0), (FgWin 6312 'claude' 'Row B' 500), (FgWin 6313 'ms-teams' 'Row C' 1000)))
    $a = PlacedOf $r 6311; $b = PlacedOf $r 6312; $c3 = PlacedOf $r 6313
    Check 'L3 odd height: scope, all three windows are placed' ([bool]($a -and $b -and $c3)) "$(Desc $r 6311) | $(Desc $r 6312) | $(Desc $r 6313)"
    if (-not ($a -and $b -and $c3)) { return }
    Check 'L3 odd height: the first line sits within a pixel of 0.3125 of the height (312.81)' ([Math]::Abs(([double]$a.y + $a.h) - 312.8125) -lt 1) (Desc $r 6311)
    Check 'L3 odd height: the second line sits within a pixel of half the height (500.5)' ([Math]::Abs(([double]$b.y + $b.h) - 500.5) -lt 1) (Desc $r 6312)
    Check 'L3 odd height: the first area ends where the second starts (no gap, no overlap)' (([int]$a.y + [int]$a.h) -eq [int]$b.y) "$(Desc $r 6311) | $(Desc $r 6312)"
    Check 'L3 odd height: the second area ends where the third starts (no gap, no overlap)' (([int]$b.y + [int]$b.h) -eq [int]$c3.y) "$(Desc $r 6312) | $(Desc $r 6313)"
    Check 'L3 odd height: the third area ends on the bottom edge (1001)' (([int]$c3.y + [int]$c3.h) -eq 1001) (Desc $r 6313)
    Check 'L3 odd height: every area spans the full width (1365) from x 0' ([bool]($a.x -eq 0 -and $b.x -eq 0 -and $c3.x -eq 0 -and $a.w -eq 1365 -and $b.w -eq 1365 -and $c3.w -eq 1365)) "$(Desc $r 6311) | $(Desc $r 6312) | $(Desc $r 6313)"
  }
  Case 'L3 control: even width, two halves share their line and reach both edges (1080 wide, green on the old code)' {
    $m = FgMon 1080 1872
    $areas = @((FreeArea @(0, 0, 0.5, 1) 0), (FreeArea @(0.5, 0, 0.5, 1) 1))
    $sc = FgScene 'L3-even-scene.json' (FreeGrid 2 1 $areas) @((FgPin 'chrome' 'Left' @(0)), (FgPin 'claude' 'Right' @(1)))
    $r = Invoke-SceneFrom $sc (Write-Snap 'L3-even.json' @($m) @((FgWin 6321 'chrome' 'Left' 0), (FgWin 6322 'claude' 'Right' 500)))
    $a = PlacedOf $r 6321; $b = PlacedOf $r 6322
    Check 'L3 control: scope, both halves are placed' ([bool]($a -and $b)) "$(Desc $r 6321) | $(Desc $r 6322)"
    Check 'L3 control: the halves share their line (540) and the right half ends at 1080' ([bool]($a -and $b -and ([int]$a.x + [int]$a.w) -eq [int]$b.x -and ([int]$b.x + [int]$b.w) -eq 1080 -and [int]$a.x -eq 0)) "$(Desc $r 6321) | $(Desc $r 6322)"
  }
  Case 'L3 fill: an empty area takes the next window in reading order, and a window past the last empty area is not placed' {
    $m = FgMon 1365 1001; $t = 3 / 7; $b = 4 / 7
    # Listed out of reading order: bottom-right, top-right, the pinned top-left, bottom-left.
    $areas = @((FreeArea @(0.4, $t, 0.6, $b)), (FreeArea @(0.4, 0, 0.6, $t)), (FreeArea @(0, 0, 0.4, $t) 0), (FreeArea @(0, $t, 0.4, $b)))
    $fill = [pscustomobject]@{ mon = 'wide'; apps = @('claude'); skip = @(); sort = 'app' }
    $sc = FgScene 'L3-fill-scene.json' (FreeGrid 2 2 $areas) @((FgPin 'chrome' 'Pinned' @(0))) $fill
    $snap = Write-Snap 'L3-fill.json' @($m) @((FgWin 6401 'chrome' 'Pinned' 0), (FgWin 6402 'claude' 'Fill 1' 100), (FgWin 6403 'claude' 'Fill 2' 300), (FgWin 6404 'claude' 'Fill 3' 500), (FgWin 6405 'claude' 'Fill 4' 700))
    $r = Invoke-SceneFrom $sc $snap
    Check 'L3 fill: the pinned window takes the top-left area' ((RectOf (PlacedOf $r 6401)) -ceq '0,0,546,429') (Desc $r 6401)
    Check 'L3 fill: Fill 1 takes the top-right area, the first empty one in reading order' ((RectOf (PlacedOf $r 6402)) -ceq '546,0,819,429') (Desc $r 6402)
    Check 'L3 fill: Fill 2 takes the bottom-left area, the second in reading order' ((RectOf (PlacedOf $r 6403)) -ceq '0,429,546,572') (Desc $r 6403)
    Check 'L3 fill: Fill 3 takes the bottom-right area, the last in reading order' ((RectOf (PlacedOf $r 6404)) -ceq '546,429,819,572') (Desc $r 6404)
    Check 'L3 fill: Fill 4 is not placed, since no empty area is left' (-not (PlacedOf $r 6405)) (Desc $r 6405)
  }
  Case 'L3 zones: a zone places its window as today with no areas (control), and pauses while areas are on' {
    $m = FgMon 1365 1001
    $zone = [pscustomobject]@{ mon = 'wide'; slots = @(0, 1); app = 'chrome' }
    $snap = Write-Snap 'L3-zone.json' @($m) @((FgWin 6501 'chrome' 'Zone A' 0))
    $ctl = FgScene 'L3-zone-ctl-scene.json' ([pscustomobject]@{ c = 2; r = 1 }) @() $null @($zone)
    $rc = Invoke-SceneFrom $ctl $snap
    Check 'L3 zones control: with no areas, Zone A takes slot 1 (the zone runs as today)' (OnCell $rc 6501 1 (CellRect $m 2 1 0)) (Desc $rc 6501)
    $areas = @((FreeArea @(0, 0, 0.5, 1)), (FreeArea @(0.5, 0, 0.5, 1)))
    $sc = FgScene 'L3-zone-free-scene.json' (FreeGrid 2 1 $areas) @() $null @($zone)
    $r = Invoke-SceneFrom $sc $snap
    Check 'L3 zones: with areas on, the zone is paused, so Zone A is not placed' (-not (PlacedOf $r 6501)) (Desc $r 6501)
  }

  # ---- Item G (L3, plan layout-free-build, item G): Get-CollapsedAreas($areas, $absent, $locked, $size), defined in tile.ps1 before its -Lib
  # return. A child powershell dot-sources tile.ps1 -Lib, so no variable of this file meets tile.ps1's param block. It runs each call of each
  # case and prints one line per call: case, call index, and the result as JSON (or MISSING when the function is not defined).
  # Contract: $areas = [{rect: [fx, fy, fw, fh]}] in fractions of the work area; $absent and $locked = 0-based indexes into $areas; $size = @(W, H)
  # in pixels, for the 400 x 300 floor. Returns one entry per area, in order: its new rect in fractions, or $null for an area whose window is
  # gone and whose space stays a gap. A locked area, or one the call does not touch, returns its rect as it was.
  function GArea($rect) { [pscustomobject]@{ rect = @([double[]]$rect) } }
  # Every subset of 0..n-1, as the calls of a case: absent = the subset, locked = none. The empty subset comes first, the full set last.
  function GSubsets([int]$n) {
    $calls = @()
    for ($mask = 0; $mask -lt (1 -shl $n); $mask++) {
      $s = @(); for ($b = 0; $b -lt $n; $b++) { if ($mask -band (1 -shl $b)) { $s += $b } }
      $calls += [pscustomobject]@{ absent = @($s); locked = @() }
    }
    ,$calls
  }
  function GSet($a) { '{' + ((@($a) | % { $_ }) -join ',') + '}' }
  # A 2x2 grid (areas 0 and 1 on top, 2 and 3 below) and a 3x1 grid of equal cells. Each absent subset of each is one call (G9, G10).
  $gGrid2 = @((GArea @(0, 0, 0.5, 0.5)), (GArea @(0.5, 0, 0.5, 0.5)), (GArea @(0, 0.5, 0.5, 0.5)), (GArea @(0.5, 0.5, 0.5, 0.5)))
  $gGrid3 = @((GArea @(0, 0, (1 / 3), 1)), (GArea @((1 / 3), 0, (1 / 3), 1)), (GArea @((2 / 3), 0, (1 / 3), 1)))
  $gSub2 = GSubsets 4; $gSub3 = GSubsets 3
  $g1 = @(0, 0, 0.25, 1), @(0.25, 0, 0.5, 1), @(0.75, 0, 0.25, 1)
  $gCases = @(
    [pscustomobject]@{ id = 'G1'; size = @(1200, 900); areas = @((GArea $g1[0]), (GArea $g1[1]), (GArea $g1[2])); calls = @([pscustomobject]@{ absent = @(1); locked = @() }) },
    [pscustomobject]@{ id = 'G2'; size = @(1200, 900); areas = @((GArea @(0, 0, 0.5, 1)), (GArea @(0.5, 0, 0.5, 0.5)), (GArea @(0.5, 0.5, 0.5, 0.5))); calls = @([pscustomobject]@{ absent = @(0); locked = @() }) },
    [pscustomobject]@{ id = 'G3'; size = @(1200, 900); areas = @((GArea $g1[0]), (GArea $g1[1]), (GArea $g1[2])); calls = @([pscustomobject]@{ absent = @(1); locked = @(0) }) },
    [pscustomobject]@{ id = 'G4'; size = @(1200, 900); areas = @((GArea @(0, 0, 0.6, 0.4)), (GArea @(0.6, 0, 0.4, 0.6)), (GArea @(0.4, 0.6, 0.6, 0.4)), (GArea @(0, 0.4, 0.4, 0.6)), (GArea @(0.4, 0.4, 0.2, 0.2))); calls = @([pscustomobject]@{ absent = @(4); locked = @() }) },
    [pscustomobject]@{ id = 'G5'; size = @(1000, 600); areas = @((GArea @(0, 0, 0.2, 1)), (GArea @(0.2, 0, 0.2, 1)), (GArea @(0.4, 0, 0.6, 1))); calls = @([pscustomobject]@{ absent = @(1); locked = @() }) },
    [pscustomobject]@{ id = 'G6'; size = @(1200, 900); areas = @((GArea @(0, 0, 0.25, 1)), (GArea @(0.25, 0, 0.25, 1)), (GArea @(0.5, 0, 0.25, 1)), (GArea @(0.75, 0, 0.25, 1))); calls = @([pscustomobject]@{ absent = @(1, 2); locked = @() }, [pscustomobject]@{ absent = @(2, 1); locked = @() }) },
    [pscustomobject]@{ id = 'G7'; size = @(1200, 900); areas = @((GArea $g1[0]), (GArea $g1[1]), (GArea $g1[2])); calls = @([pscustomobject]@{ absent = @(1); locked = @() }, [pscustomobject]@{ absent = @(); locked = @() }) },
    [pscustomobject]@{ id = 'G8'; size = @(1200, 900); areas = @((GArea @(0, 0, 1, 0.25)), (GArea @(0, 0.25, 1, 0.5)), (GArea @(0, 0.75, 1, 0.25))); calls = @([pscustomobject]@{ absent = @(1); locked = @() }) },
    [pscustomobject]@{ id = 'G9'; size = @(1200, 900); areas = $gGrid2; calls = $gSub2 },
    [pscustomobject]@{ id = 'G10'; size = @(1200, 900); areas = $gGrid3; calls = $gSub3 }
  )
  $gOut = @(); $gRes = @{}
  try {
    $gCasesPath = Join-Path $run 'L3-g-cases.json'; [IO.File]::WriteAllText($gCasesPath, (ConvertTo-Json -InputObject @($gCases) -Depth 8 -Compress), $utf8)
    $gProbe = Join-Path $run 'L3-g-probe.ps1'
    $probeLines = @(
      'param([string]$probeTile, [string]$probeCases)',
      '. $probeTile -Lib',
      '[Console]::Out.WriteLine(''MOVEWIN '' + [bool](Get-Command Move-Win -ErrorAction SilentlyContinue))',
      '$has = [bool](Get-Command Get-CollapsedAreas -ErrorAction SilentlyContinue)',
      '$cases = Get-Content -Raw -LiteralPath $probeCases | ConvertFrom-Json',
      'foreach ($c in $cases) { $i = 0; foreach ($call in @($c.calls)) {',
      '  if ($has) { $o = @(Get-CollapsedAreas @($c.areas) @($call.absent) @($call.locked) @($c.size)); $txt = ConvertTo-Json -InputObject @($o) -Depth 4 -Compress }',
      '  else { $txt = ''MISSING'' }',
      '  [Console]::Out.WriteLine($c.id + [char]9 + $i + [char]9 + $txt); $i++',
      '} }'
    )
    [IO.File]::WriteAllText($gProbe, ($probeLines -join "`r`n"), $utf8)
    $gOut = @(& powershell -NoProfile -ExecutionPolicy Bypass -File $gProbe -probeTile $tile -probeCases $gCasesPath)
    foreach ($ln in $gOut) { $p = "$ln" -split "`t"; if ($p.Count -eq 3) { $gRes["$($p[0])|$($p[1])"] = $p[2] } }
  } catch { $script:fail++; "FAIL  L3 item G probe stopped: $_" }
  Case 'L3 control: tile.ps1 -Lib still loads and defines Move-Win, as the item G probe needs (green on the old code)' {
    Check 'L3 control: the -Lib child runs and defines Move-Win' ([bool]($gOut | ? { $_ -eq 'MOVEWIN True' })) "probe output: $(@($gOut) -join ' / ')"
  }
  function GText($x) { (@($x) | % { if ($null -eq $_) { 'gap' } else { @($_) -join ',' } }) -join ' | ' }
  function GSame($a, $b) {
    if ($null -eq $a -or $null -eq $b) { return ($null -eq $a -and $null -eq $b) }
    if (@($a).Count -ne 4 -or @($b).Count -ne 4) { return $false }
    for ($k = 0; $k -lt 4; $k++) { if ([Math]::Abs([double]$a[$k] - [double]$b[$k]) -gt 1e-9) { return $false } }
    $true
  }
  # One check per call: the result must match $want entry by entry. An undefined function is one FAIL line naming that cause.
  function GCheck([string]$name, [string]$key, $want) {
    $txt = $gRes[$key]
    if ($null -eq $txt) { Check $name $false 'the probe printed no line for this call'; return }
    if ($txt -eq 'MISSING') { Check $name $false 'Get-CollapsedAreas is not defined by tile.ps1 -Lib'; return }
    $got = ConvertFrom-Json $txt  # assigned, not wrapped: PowerShell 5.1 emits a JSON array as one object
    $ok = (@($got).Count -eq @($want).Count)
    if ($ok) { for ($k = 0; $k -lt @($want).Count; $k++) { if (-not (GSame $got[$k] $want[$k])) { $ok = $false } } }
    Check $name $ok "got $(GText $got); want $(GText $want)"
  }
  Case 'L3 item G: a closed middle column is split at the midpoint by its left and right neighbours (1200 x 900)' {
    GCheck 'L3 item G: a closed middle column is split at the midpoint by its left and right neighbours (1200 x 900)' 'G1|0' @(@(0, 0, 0.5, 1), $null, @(0.5, 0, 0.5, 1))
  }
  Case 'L3 item G: restoring gives back the saved rects' {
    GCheck 'L3 item G: the closed middle column of the restore case is split at the midpoint first (G7, first call)' 'G7|0' @(@(0, 0, 0.5, 1), $null, @(0.5, 0, 0.5, 1))
    GCheck 'L3 item G: restoring (no gap) gives back the saved rects, with the same areas object (G7, second call)' 'G7|1' @(@(0, 0, 0.25, 1), @(0.25, 0, 0.5, 1), @(0.75, 0, 0.25, 1))
  }
  Case 'L3 item G: two stacked halves on one side both grow into a closed column' {
    GCheck 'L3 item G: two stacked halves on the right both grow left into the closed left column (1200 x 900)' 'G2|0' @($null, @(0, 0, 1, 0.5), @(0, 0.5, 1, 0.5))
  }
  Case 'L3 item G: a locked left neighbour means the right side takes the whole space' {
    GCheck 'L3 item G: with a locked left neighbour, the right side takes the whole space and the locked area stays put' 'G3|0' @(@(0, 0, 0.25, 1), $null, @(0.25, 0, 0.75, 1))
  }
  Case 'L3 item G: a pinwheel centre stays a gap' {
    GCheck 'L3 item G: a pinwheel centre stays a gap, and its four neighbours keep their rects (1200 x 900)' 'G4|0' @(@(0, 0, 0.6, 0.4), @(0.6, 0, 0.4, 0.6), @(0.4, 0.6, 0.6, 0.4), @(0, 0.4, 0.4, 0.6), $null)
  }
  Case 'L3 item G: a midpoint share that leaves a window under 400 x 300 gives the whole space to the first side that qualifies' {
    GCheck 'L3 item G: the midpoint share would leave the left window 300 px wide, so the left side takes the whole space (1000 x 600)' 'G5|0' @(@(0, 0, 0.4, 1), $null, @(0.4, 0, 0.6, 1))
  }
  Case 'L3 item G: two neighbours gone at once give the same result in either order' {
    $want6 = @(@(0, 0, 0.5, 1), $null, $null, @(0.5, 0, 0.5, 1))
    GCheck 'L3 item G: two neighbours gone, in the order 1 then 2, meet the outer neighbours at the midpoint (1200 x 900)' 'G6|0' $want6
    GCheck 'L3 item G: two neighbours gone, in the order 2 then 1, give the same result' 'G6|1' $want6
  }
  Case 'L3 item G: an above and below pair meet at the midpoint when no left or right side qualifies' {
    GCheck 'L3 item G: an above and below pair meet at the midpoint (1200 x 900)' 'G8|0' @(@(0, 0, 1, 0.5), $null, @(0, 0.5, 1, 0.5))
  }

  # Two returned rects overlap when each axis overlaps by more than 1e-9, so a shared edge is no overlap. A gap ($null) overlaps nothing.
  function GRect($r) { if ($null -eq $r) { 'gap' } else { '[' + (@($r) -join ',') + ']' } }
  function GOver($p, $q) {
    if ($null -eq $p -or $null -eq $q) { return $false }
    # [Math] on a mixed int and double picks the int overload, so 0 and 0.5 give 0. Cast first.
    $p = [double[]]@($p); $q = [double[]]@($q)
    $ox = [Math]::Min($p[0] + $p[2], $q[0] + $q[2]) - [Math]::Max($p[0], $q[0])
    $oy = [Math]::Min($p[1] + $p[3], $q[1] + $q[3]) - [Math]::Max($p[1], $q[1])
    ($ox -gt 1e-9) -and ($oy -gt 1e-9)
  }
  # One check per call. The result has $want entries (one per area), and no two returned non-null rects overlap. The FAIL line names the first pair.
  function GNoOverlap([string]$name, [string]$key, [int]$want) {
    $txt = $gRes[$key]
    if ($null -eq $txt) { Check $name $false 'the probe printed no line for this call'; return }
    if ($txt -eq 'MISSING') { Check $name $false 'Get-CollapsedAreas is not defined by tile.ps1 -Lib'; return }
    $got = ConvertFrom-Json $txt  # assigned, not wrapped: PowerShell 5.1 emits a JSON array as one object
    $n = @($got).Count
    $pair = ''
    for ($a = 0; $a -lt $n -and $pair -eq ''; $a++) {
      for ($b = $a + 1; $b -lt $n -and $pair -eq ''; $b++) {
        if (GOver ($got[$a]) ($got[$b])) { $pair = "area $a $(GRect ($got[$a])) overlaps area $b $(GRect ($got[$b]))" }
      }
    }
    $why = $pair
    if ($n -ne $want) { $why = "got $n entries, want $want" }
    Check $name (($n -eq $want) -and ($pair -eq '')) "$why; the result is $(GText $got)"
  }
  # A neighbour that grows into two gaps at once overlaps the area past them: area 0 in the diagonal {1,2} grows right into one gap and down into the other, over area 3.
  # The empty and full subsets are included: nothing gone, and everything gone.
  Case 'L3 item G overlap: no two returned areas overlap, for every absent subset of a 2x2 grid' {
    for ($k = 0; $k -lt @($gSub2).Count; $k++) {
      GNoOverlap "L3 item G overlap: 2x2 grid, absent $(GSet ($gSub2[$k].absent)): no two returned areas overlap" "G9|$k" 4
    }
  }
  Case 'L3 item G overlap: no two returned areas overlap, for every absent subset of a 3x1 grid' {
    for ($k = 0; $k -lt @($gSub3).Count; $k++) {
      GNoOverlap "L3 item G overlap: 3x1 grid, absent $(GSet ($gSub3[$k].absent)): no two returned areas overlap" "G10|$k" 3
    }
  }

} finally {
  foreach ($k in $saved.Keys) { if ($null -eq $saved[$k]) { Remove-Item "env:$k" -ErrorAction SilentlyContinue } else { Set-Item "env:$k" $saved[$k] } }
  Remove-Item -LiteralPath $run -Recurse -Force -ErrorAction SilentlyContinue
}
if ($script:fail) { "$($script:fail) check(s) failed."; exit 1 } else { 'All engine-layouts checks passed.' }
