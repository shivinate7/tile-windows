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
# Gap fill (L5a, plan layout-free-build): the cases after item G. -GapFill runs on a Free Layout board; its contract is in that section.
# Open halves fill last (layout-free item 6): the cases after the L1 section, on a 1360x1000 monitor. The keepEmpty cases key by monitor id.
# Free-area rect bounds: the cases after the L3 zones case. No window is placed under 1 px or outside the work area.
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
  # -min: a minimized window as -From carries it (min true, at -32000). w and h give its rect for when it is restored.
  function FgWin([int]$id, $app, $title, [int]$x, [int]$y = 0, [int]$w = 400, [int]$h = 300, [switch]$min) {
    if ($min) { [pscustomobject]@{ id = $id; app = $app; title = $title; x = -32000; y = -32000; w = $w; h = $h; min = $true } }
    else { [pscustomobject]@{ id = $id; app = $app; title = $title; x = $x; y = $y; w = $w; h = $h } }
  }
  function FgPin($app, $match, [int[]]$slots, [string]$mon = 'wide') { [pscustomobject]@{ app = $app; match = $match; mon = $mon; slots = @($slots) } }
  function FgGrid([int]$mx, [int]$my) { [pscustomobject]@{ c = 5; r = 2; mult = @($mx, $my) } }
  # $key names the grid and every pin, zone and fill entry that uses it: 'wide' (the role path), or a monitor id (an id-keyed scene).
  function FgScene([string]$name, $grid, $pins = @(), $fill = $null, $zones = @(), [string]$key = 'wide') { Write-Json $name ([pscustomobject]@{ id = $name; name = $name; grids = (KeyedOne $key $grid); pins = @($pins); zones = @($zones); fill = $fill }) }
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
  # ---- Open halves fill last (layout-free item 6, owner grant: yes, first recorded in commit 686934e, 2026-11-13 09:41 CST). With fill.unit larger than 1x1 the fill takes the free aligned blocks first, then
  # the open halves (free fine cells of a part-taken block) in reading order. Two open halves one above the other make one window. A kept slot
  # (fill.keepEmpty, keyed by monitor id only) is never filled by the fill or a zone, and its block is not free. The monitor is 1360x1000: a base cell is
  # 272x500 and a half 136 wide (stacked: 250 high), so every expected rect is whole pixels. A check named 'control:' is green on the old code too.
  $ohM = FgMon 1360 1000
  $ohId = 'FG-1360x1000'
  # The 1-based slots of block $b, sorted: a 2x1 block of the horizontal split (10 fine columns), a 1x2 block of the stacked split (5 fine columns).
  function OhPairH([int]$b) { $row = [Math]::Floor($b / 5); $c = ($b % 5) * 2; "$($row * 10 + $c + 1)+$($row * 10 + $c + 2)" }
  function OhPairV([int]$b) { $p = [Math]::Floor($b / 5); $c = $b % 5; "$($p * 10 + $c + 1)+$($p * 10 + $c + 6)" }
  # The rect of fine cell $s (0-based): a half of the horizontal split (10 by 2), or of the stacked split (5 by 4), on the 1360x1000 monitor.
  function OhHalfH([int]$s) { $row = [Math]::Floor($s / 10); $c = $s % 10; '{0},{1},136,500' -f ([Math]::Floor($c / 2) * 272 + ($c % 2) * 136), ($row * 500) }
  function OhHalfV([int]$s) { $row = [Math]::Floor($s / 5); $c = $s % 5; '{0},{1},272,250' -f ($c * 272), ([Math]::Floor($row / 2) * 500 + ($row % 2) * 250) }
  # True when window $id is placed on exactly the slots $pair (sorted, 1-based) with rect $rect.
  function OhIs($res, [int64]$id, [string]$pair, [string]$rect) { $p = PlacedOf $res $id; [bool]($p -and (SlotKey $p) -ceq $pair -and (RectOf $p) -ceq $rect) }

  Case 'open half (layout-free item 6), horizontal: nine windows take the nine free blocks, the tenth takes the open right half, and the eleventh has no free cell' {
    $fill = [pscustomobject]@{ mon = 'wide'; apps = @('claude'); skip = @(); sort = 'app'; unit = @(2, 1) }
    $sc = FgScene 'oh-h10-scene.json' (FgGrid 2 1) @((FgPin 'chrome' 'Pin A' @(0))) $fill
    $wins = @((FgWin 7001 'chrome' 'Pin A' 0)) + @(1..11 | % { FgWin (7010 + $_) 'claude' "Fill $_" (100 * $_) })
    $r = Invoke-SceneFrom $sc (Write-Snap 'oh-h10-snap.json' @($ohM) $wins)
    Check 'scope: the pin takes the left half of cell 1 (slot 1, 0,0,136,500)' (OnCell $r 7001 1 '0,0,136,500') (Desc $r 7001)
    $bad = @(foreach ($k in 1..9) { if (-not (OhIs $r (7010 + $k) (OhPairH $k) (CellRect $ohM 5 2 $k))) { Desc $r (7010 + $k) } })
    Check 'control: windows 1 to 9 take the nine free blocks in order, each at its old cell rect' ($bad.Count -eq 0) ($bad -join ' | ')
    Check 'open half: window 10 takes the open half, slot 2, the right half of the pinned cell (136,0,136,500)' (OnCell $r 7020 2 (OhHalfH 1)) (Desc $r 7020)
    Check 'control: window 11 has no free cell, every free cell now being taken' ((LeftWhy $r 7021) -ceq 'no free cell') (Desc $r 7021)
  }
  Case 'control: open half, horizontal: with nine windows every free block is taken, and no window reaches the open half' {
    $fill = [pscustomobject]@{ mon = 'wide'; apps = @('claude'); skip = @(); sort = 'app'; unit = @(2, 1) }
    $sc = FgScene 'oh-h9-scene.json' (FgGrid 2 1) @((FgPin 'chrome' 'Pin A' @(0))) $fill
    $wins = @((FgWin 7101 'chrome' 'Pin A' 0)) + @(1..9 | % { FgWin (7110 + $_) 'claude' "Fill $_" (100 * $_) })
    $r = Invoke-SceneFrom $sc (Write-Snap 'oh-h9-snap.json' @($ohM) $wins)
    Check 'scope: the pin takes the left half of cell 1 (slot 1, 0,0,136,500)' (OnCell $r 7101 1 '0,0,136,500') (Desc $r 7101)
    $bad = @(foreach ($k in 1..9) { if (-not (OhIs $r (7110 + $k) (OhPairH $k) (CellRect $ohM 5 2 $k))) { Desc $r (7110 + $k) } })
    Check 'control: windows 1 to 9 take the nine free blocks in order, each at its old cell rect' ($bad.Count -eq 0) ($bad -join ' | ')
    $onHalf = @($r.placed | ? { @($_.slots) -contains 2 })
    Check 'control: with nine windows, no window takes slot 2, the open half' ($onHalf.Count -eq 0) "on slot 2: $(@($onHalf | % { $_.title }) -join ', ')"
  }
  Case 'open half (layout-free item 6), stacked: nine windows take the nine free blocks, and the tenth takes the open bottom half of the pinned cell' {
    $fill = [pscustomobject]@{ mon = 'wide'; apps = @('claude'); skip = @(); sort = 'app'; unit = @(1, 2) }
    $sc = FgScene 'oh-v10-scene.json' (FgGrid 1 2) @((FgPin 'chrome' 'Pin A' @(0))) $fill
    $wins = @((FgWin 7201 'chrome' 'Pin A' 0)) + @(1..10 | % { FgWin (7210 + $_) 'claude' "Stack $_" (100 * $_) })
    $r = Invoke-SceneFrom $sc (Write-Snap 'oh-v10-snap.json' @($ohM) $wins)
    Check 'scope: the pin takes the top half of cell 1 (slot 1, 0,0,272,250)' (OnCell $r 7201 1 '0,0,272,250') (Desc $r 7201)
    $bad = @(foreach ($k in 1..9) { if (-not (OhIs $r (7210 + $k) (OhPairV $k) (CellRect $ohM 5 2 $k))) { Desc $r (7210 + $k) } })
    Check 'control: windows 1 to 9 take the nine free blocks in order, each at its old cell rect' ($bad.Count -eq 0) ($bad -join ' | ')
    Check 'open half: window 10 takes the open bottom half, slot 6, the bottom half of the pinned cell (0,250,272,250)' (OnCell $r 7220 6 (OhHalfV 5)) (Desc $r 7220)
  }
  Case 'open halves (layout-free item 6), horizontal: two open halves one above the other form one window, a 136-wide rectangle two rows tall' {
    $fill = [pscustomobject]@{ mon = 'wide'; apps = @('claude'); skip = @(); sort = 'app'; unit = @(2, 1) }
    $sc = FgScene 'oh-rect-scene.json' (FgGrid 2 1) @((FgPin 'chrome' 'Pin A' @(0)), (FgPin 'chrome' 'Pin B' @(10))) $fill
    $wins = @((FgWin 7301 'chrome' 'Pin A' 0), (FgWin 7302 'chrome' 'Pin B' 500)) + @(1..9 | % { FgWin (7310 + $_) 'claude' "Fill $_" (100 * $_) })
    $r = Invoke-SceneFrom $sc (Write-Snap 'oh-rect-snap.json' @($ohM) $wins)
    Check 'scope: pin A takes slot 1 (0,0,136,500) and pin B takes slot 11 (0,500,136,500)' ((OnCell $r 7301 1 '0,0,136,500') -and (OnCell $r 7302 11 '0,500,136,500')) "$(Desc $r 7301) | $(Desc $r 7302)"
    $free = @(1, 2, 3, 4, 6, 7, 8, 9)
    $bad = @(foreach ($i in 0..7) { $b = $free[$i]; if (-not (OhIs $r (7311 + $i) (OhPairH $b) (CellRect $ohM 5 2 $b))) { Desc $r (7311 + $i) } })
    Check 'control: windows 1 to 8 take the eight free blocks in order, each at its old cell rect' ($bad.Count -eq 0) ($bad -join ' | ')
    Check 'open halves: window 9 takes both open halves, slots 2 and 12, as one rectangle (136,0,136,1000)' (OhIs $r 7319 '2+12' '136,0,136,1000') (Desc $r 7319)
  }
  Case 'open halves (layout-free item 6), horizontal: two open halves that do not touch each take one window, in reading order' {
    $fill = [pscustomobject]@{ mon = 'wide'; apps = @('claude'); skip = @(); sort = 'app'; unit = @(2, 1) }
    $sc = FgScene 'oh-two-scene.json' (FgGrid 2 1) @((FgPin 'chrome' 'Pin A' @(0)), (FgPin 'chrome' 'Pin B' @(4))) $fill
    $wins = @((FgWin 7401 'chrome' 'Pin A' 0), (FgWin 7402 'chrome' 'Pin B' 500)) + @(1..10 | % { FgWin (7410 + $_) 'claude' "Fill $_" (100 * $_) })
    $r = Invoke-SceneFrom $sc (Write-Snap 'oh-two-snap.json' @($ohM) $wins)
    Check 'scope: pin B takes slot 5 (the left half of cell 3, 544,0,136,500)' (OnCell $r 7402 5 '544,0,136,500') (Desc $r 7402)
    $free = @(1, 3, 4, 5, 6, 7, 8, 9)
    $bad = @(foreach ($i in 0..7) { $b = $free[$i]; if (-not (OhIs $r (7411 + $i) (OhPairH $b) (CellRect $ohM 5 2 $b))) { Desc $r (7411 + $i) } })
    Check 'control: windows 1 to 8 take the eight free blocks in order, each at its old cell rect' ($bad.Count -eq 0) ($bad -join ' | ')
    Check 'open half: window 9 takes open slot 2 (136,0,136,500), the first in reading order' (OnCell $r 7419 2 (OhHalfH 1)) (Desc $r 7419)
    Check 'open half: window 10 takes open slot 6 (680,0,136,500), the second in reading order' (OnCell $r 7420 6 (OhHalfH 5)) (Desc $r 7420)
  }
  Case 'control: open half, fill off: the open half stays empty, and the claude windows are listed as fill is off' {
    $fill = [pscustomobject]@{ mon = 'wide'; apps = @('claude'); skip = @(); sort = 'app'; unit = @(2, 1); off = $true }
    $sc = FgScene 'oh-off-scene.json' (FgGrid 2 1) @((FgPin 'chrome' 'Pin A' @(0))) $fill
    $wins = @((FgWin 7501 'chrome' 'Pin A' 0)) + @(1..3 | % { FgWin (7510 + $_) 'claude' "Fill $_" (100 * $_) })
    $r = Invoke-SceneFrom $sc (Write-Snap 'oh-off-snap.json' @($ohM) $wins)
    Check 'scope: the pin takes the left half of cell 1 (slot 1, 0,0,136,500)' (OnCell $r 7501 1 '0,0,136,500') (Desc $r 7501)
    $onHalf = @($r.placed | ? { @($_.slots) -contains 2 })
    Check 'control: no window takes slot 2, the open half, with fill off' ($onHalf.Count -eq 0) "on slot 2: $(@($onHalf | % { $_.title }) -join ', ')"
    Check 'control: the three claude windows are left as fill is off' (@(7511..7513 | ? { (LeftWhy $r $_) -ceq 'fill is off' }).Count -eq 3) "$(LeftWhy $r 7511) | $(LeftWhy $r 7512) | $(LeftWhy $r 7513)"
  }
  Case 'control: no unit, or unit 1x1, horizontal: each free fine cell is one block, as today, so ten windows take fine cells 2 to 11, one each' {
    foreach ($tag in 'no unit', 'unit 1x1') {
      $fill = [pscustomobject]@{ mon = 'wide'; apps = @('claude'); skip = @(); sort = 'app' }
      if ($tag -eq 'unit 1x1') { $fill | Add-Member -NotePropertyName unit -NotePropertyValue @(1, 1) }
      $key = $tag -replace ' ', ''
      $sc = FgScene "oh-$key-scene.json" (FgGrid 2 1) @((FgPin 'chrome' 'Pin A' @(0))) $fill
      $wins = @((FgWin 7601 'chrome' 'Pin A' 0)) + @(1..10 | % { FgWin (7610 + $_) 'claude' "Fill $_" (100 * $_) })
      $r = Invoke-SceneFrom $sc (Write-Snap "oh-$key-snap.json" @($ohM) $wins)
      Check "scope: ${tag}, the pin takes the left half of cell 1 (slot 1, 0,0,136,500)" (OnCell $r 7601 1 '0,0,136,500') (Desc $r 7601)
      $bad = @(foreach ($k in 1..9) { if (-not (OnCell $r (7610 + $k) ($k + 1) (OhHalfH $k))) { Desc $r (7610 + $k) } })
      Check "control: ${tag}, windows 1 to 9 take fine cells 2 to 10, one each, at their half rects" ($bad.Count -eq 0) ($bad -join ' | ')
      Check "control: ${tag}, window 10 takes fine cell 11, the first cell of the second row (0,500,136,500)" (OnCell $r 7620 11 (OhHalfH 10)) (Desc $r 7620)
    }
  }
  Case 'control: open half, empty: a pin with no other window places nothing else, and no open half is invented' {
    $fill = [pscustomobject]@{ mon = 'wide'; apps = @('claude'); skip = @(); sort = 'app'; unit = @(2, 1) }
    $sc = FgScene 'oh-empty-scene.json' (FgGrid 2 1) @((FgPin 'chrome' 'Pin A' @(0))) $fill
    $r = Invoke-SceneFrom $sc (Write-Snap 'oh-empty-snap.json' @($ohM) @())
    Check 'control: empty, nothing is placed' (@($r.placed).Count -eq 0) "placed $(@($r.placed).Count)"
    Check 'control: empty, nothing is left' (@($r.left).Count -eq 0) "left $(@($r.left).Count)"
  }
  Case 'open half (layout-free item 6), zone: the zone takes its whole free block before its own open half' {
    $fill = [pscustomobject]@{ mon = 'wide'; apps = @(); skip = @(); sort = 'app'; unit = @(2, 1) }
    $zone = [pscustomobject]@{ mon = 'wide'; slots = @(0, 1, 2, 3); app = 'chrome' }
    $sc = FgScene 'oh-zone-scene.json' (FgGrid 2 1) @((FgPin 'claude' 'Pinned' @(0))) $fill @($zone)
    $wins = @((FgWin 7801 'claude' 'Pinned' 0), (FgWin 7802 'chrome' 'Zone A' 500), (FgWin 7803 'chrome' 'Zone B' 1000))
    $r = Invoke-SceneFrom $sc (Write-Snap 'oh-zone-snap.json' @($ohM) $wins)
    Check 'scope: the pin takes the left half of cell 1 (slot 1, 0,0,136,500)' (OnCell $r 7801 1 '0,0,136,500') (Desc $r 7801)
    Check 'scope: both zone windows are placed' ((PlacedOf $r 7802) -and (PlacedOf $r 7803)) "$(Desc $r 7802) | $(Desc $r 7803)"
    Check 'open half: zone window A takes the whole free block, slots 3+4 (272,0,272,500)' (OhIs $r 7802 (OhPairH 1) (CellRect $ohM 5 2 1)) (Desc $r 7802)
    Check 'open half: zone window B takes the zone''s own open half, slot 2 (136,0,136,500)' (OnCell $r 7803 2 (OhHalfH 1)) (Desc $r 7803)
  }
  Case 'band limit (layout-free item 6), horizontal: an open half stays in its own unit, so open slots 2 and 3 take two 136-wide windows, not one 272-wide' {
    $fill = [pscustomobject]@{ mon = 'wide'; apps = @('claude'); skip = @(); sort = 'app'; unit = @(2, 1) }
    $sc = FgScene 'oh-band-h-scene.json' (FgGrid 2 1) @((FgPin 'chrome' 'Pin A' @(0)), (FgPin 'chrome' 'Pin B' @(3))) $fill
    $wins = @((FgWin 9001 'chrome' 'Pin A' 0), (FgWin 9002 'chrome' 'Pin B' 408)) + @(1..10 | % { FgWin (9010 + $_) 'claude' "Fill $_" (100 * $_) })
    $r = Invoke-SceneFrom $sc (Write-Snap 'oh-band-h-snap.json' @($ohM) $wins)
    Check 'scope: pin B takes slot 4, the right half of cell 2 (408,0,136,500)' (OnCell $r 9002 4 '408,0,136,500') (Desc $r 9002)
    $free = @(2, 3, 4, 5, 6, 7, 8, 9)
    $bad = @(foreach ($i in 0..7) { $b = $free[$i]; if (-not (OhIs $r (9011 + $i) (OhPairH $b) (CellRect $ohM 5 2 $b))) { Desc $r (9011 + $i) } })
    Check 'control: windows 1 to 8 take the eight whole blocks 2 to 9 in order, each at its cell rect' ($bad.Count -eq 0) ($bad -join ' | ')
    Check 'band: window 9 takes open slot 2, a 136-wide half (136,0,136,500), not a 272-wide unit with slot 3' (OnCell $r 9019 2 (OhHalfH 1)) (Desc $r 9019)
    Check 'band: window 10 takes open slot 3, the other 136-wide half (272,0,136,500)' (OnCell $r 9020 3 (OhHalfH 2)) (Desc $r 9020)
  }
  Case 'band limit (layout-free item 6), stacked: an open half stays in its own unit, so open slots 6 and 11 take two 272 by 250 windows, not one 272 by 500' {
    $fill = [pscustomobject]@{ mon = 'wide'; apps = @('claude'); skip = @(); sort = 'app'; unit = @(1, 2) }
    $sc = FgScene 'oh-band-v-scene.json' (FgGrid 1 2) @((FgPin 'chrome' 'Pin A' @(0)), (FgPin 'chrome' 'Pin B' @(15))) $fill
    $wins = @((FgWin 9201 'chrome' 'Pin A' 0), (FgWin 9202 'chrome' 'Pin B' 0 750)) + @(1..10 | % { FgWin (9210 + $_) 'claude' "Stack $_" (100 * $_) })
    $r = Invoke-SceneFrom $sc (Write-Snap 'oh-band-v-snap.json' @($ohM) $wins)
    Check 'scope: pin A takes slot 1 (0,0,272,250) and pin B takes slot 16 (0,750,272,250)' ((OnCell $r 9201 1 '0,0,272,250') -and (OnCell $r 9202 16 '0,750,272,250')) "$(Desc $r 9201) | $(Desc $r 9202)"
    $free = @(1, 2, 3, 4, 6, 7, 8, 9)
    $bad = @(foreach ($i in 0..7) { $b = $free[$i]; if (-not (OhIs $r (9211 + $i) (OhPairV $b) (CellRect $ohM 5 2 $b))) { Desc $r (9211 + $i) } })
    Check 'control: windows 1 to 8 take the eight whole blocks in order, each at its cell rect' ($bad.Count -eq 0) ($bad -join ' | ')
    Check 'band: window 9 takes open slot 6, the 272 by 250 half (0,250,272,250), not a unit with slot 11' (OnCell $r 9219 6 (OhHalfV 5)) (Desc $r 9219)
    Check 'band: window 10 takes open slot 11, the other half (0,500,272,250)' (OnCell $r 9220 11 (OhHalfV 10)) (Desc $r 9220)
  }
  Case 'zone capacity (layout-free item 6, the same way): with unit 2x1, a zone of one base cell holds one window, the block at 272 wide, and no more' {
    $fill = [pscustomobject]@{ mon = $ohId; apps = @(); skip = @(); sort = 'app'; unit = @(2, 1) }
    $zone = [pscustomobject]@{ mon = $ohId; slots = @(0, 1); app = 'chrome' }
    $sc = FgScene 'oh-zcap-scene.json' (FgGrid 2 1) @() $fill @($zone) $ohId
    $wins = @((FgWin 9301 'chrome' 'Zone A' 0), (FgWin 9302 'chrome' 'Zone B' 500))
    $r = Invoke-SceneFrom $sc (Write-Snap 'oh-zcap-snap.json' @($ohM) $wins)
    Check 'capacity: zone window A takes the zone''s one block, slots 1+2 at 272 wide (0,0,272,500)' (OhIs $r 9301 (OhPairH 0) (CellRect $ohM 5 2 0)) (Desc $r 9301)
    Check 'capacity: zone window B is not placed in the zone, so it is left as zone full' ((-not (PlacedOf $r 9302)) -and (LeftWhy $r 9302) -ceq 'zone full') (Desc $r 9302)
  }
  Case 'keep (fill.keepEmpty, monitor id), zone: a zone never fills a kept slot, so its third window goes past the kept half' {
    $fill = [pscustomobject]@{ mon = $ohId; apps = @(); skip = @(); sort = 'app'; keepEmpty = @([pscustomobject]@{ mon = $ohId; slots = @(1) }) }
    $zone = [pscustomobject]@{ mon = $ohId; slots = @(0, 1, 2, 3); app = 'chrome' }
    $sc = FgScene 'oh-zkeep-scene.json' (FgGrid 2 1) @() $fill @($zone) $ohId
    $wins = @((FgWin 7901 'chrome' 'Zone A' 0), (FgWin 7902 'chrome' 'Zone B' 500), (FgWin 7903 'chrome' 'Zone C' 1000))
    $r = Invoke-SceneFrom $sc (Write-Snap 'oh-zkeep-snap.json' @($ohM) $wins)
    Check 'scope: the three zone windows are placed' (@($r.placed).Count -eq 3) "placed $(@($r.placed).Count), left $(@($r.left).Count)"
    $onKept = @($r.placed | ? { @($_.slots) -contains 2 })
    Check 'keep: no zone window covers slot 2, the kept half' ($onKept.Count -eq 0) "on slot 2: $(@($onKept | % { $_.title }) -join ', ')"
    Check 'keep: the third zone window takes slot 4, past the kept slot 2 (408,0,136,500)' (OnCell $r 7903 4 '408,0,136,500') (Desc $r 7903)
  }
  Case 'keep (fill.keepEmpty, monitor id), horizontal: a kept half breaks its block, so the fill starts at the next whole block and never covers the kept half' {
    $fill = [pscustomobject]@{ mon = $ohId; apps = @('claude'); skip = @(); sort = 'app'; unit = @(2, 1); keepEmpty = @([pscustomobject]@{ mon = $ohId; slots = @(1) }) }
    $sc = FgScene 'oh-k1-scene.json' (FgGrid 2 1) @() $fill @() $ohId
    $wins = @(1..9 | % { FgWin (8000 + $_) 'claude' "Fill $_" (100 * $_) })
    $r = Invoke-SceneFrom $sc (Write-Snap 'oh-k1-snap.json' @($ohM) $wins)
    Check 'scope: the nine claude windows are placed' (@($r.placed).Count -eq 9) "placed $(@($r.placed).Count), left $(@($r.left).Count)"
    $onKept = @($r.placed | ? { @($_.slots) -contains 2 })
    Check 'keep: no window covers slot 2, the kept half' ($onKept.Count -eq 0) "on slot 2: $(@($onKept | % { $_.title }) -join ', ')"
    Check 'keep: window 1 takes the next whole block, slots 3+4 (272,0,272,500)' (OhIs $r 8001 (OhPairH 1) (CellRect $ohM 5 2 1)) (Desc $r 8001)
  }
  Case 'control: keep, horizontal: a kept open half stays empty, so the tenth window is left with no free cell' {
    $fill = [pscustomobject]@{ mon = $ohId; apps = @('claude'); skip = @(); sort = 'app'; unit = @(2, 1); keepEmpty = @([pscustomobject]@{ mon = $ohId; slots = @(1) }) }
    $sc = FgScene 'oh-k2-scene.json' (FgGrid 2 1) @((FgPin 'chrome' 'Pin A' @(0) $ohId)) $fill @() $ohId
    $wins = @((FgWin 8101 'chrome' 'Pin A' 0)) + @(1..10 | % { FgWin (8110 + $_) 'claude' "Fill $_" (100 * $_) })
    $r = Invoke-SceneFrom $sc (Write-Snap 'oh-k2-snap.json' @($ohM) $wins)
    Check 'scope: the pin takes the left half of cell 1 (slot 1, 0,0,136,500)' (OnCell $r 8101 1 '0,0,136,500') (Desc $r 8101)
    $onKept = @($r.placed | ? { @($_.slots) -contains 2 })
    Check 'control: no window covers slot 2, the kept open half' ($onKept.Count -eq 0) "on slot 2: $(@($onKept | % { $_.title }) -join ', ')"
    Check 'control: window 10 is left with no free cell' ((LeftWhy $r 8120) -ceq 'no free cell') (Desc $r 8120)
  }
  Case 'control: keep, horizontal: a pin on a kept half still takes it' {
    $fill = [pscustomobject]@{ mon = $ohId; apps = @(); skip = @(); sort = 'app'; keepEmpty = @([pscustomobject]@{ mon = $ohId; slots = @(1) }) }
    $sc = FgScene 'oh-k3-scene.json' (FgGrid 2 1) @((FgPin 'chrome' 'Pin K' @(1) $ohId)) $fill @() $ohId
    $r = Invoke-SceneFrom $sc (Write-Snap 'oh-k3-snap.json' @($ohM) @((FgWin 8201 'chrome' 'Pin K' 0)))
    Check 'control: the pin takes its kept half, slot 2 (136,0,136,500)' (OnCell $r 8201 2 (OhHalfH 1)) (Desc $r 8201)
  }
  Case 'control: keep, fill off: a held window on a kept half still takes it' {
    $fill = [pscustomobject]@{ mon = $ohId; apps = @(); skip = @(); sort = 'app'; off = $true; keepEmpty = @([pscustomobject]@{ mon = $ohId; slots = @(1) }); held = @([pscustomobject]@{ app = 'claude'; title = 'Held K'; mon = $ohId; slots = @(1) }) }
    $sc = FgScene 'oh-k4-scene.json' (FgGrid 2 1) @() $fill @() $ohId
    $r = Invoke-SceneFrom $sc (Write-Snap 'oh-k4-snap.json' @($ohM) @((FgWin 8301 'claude' 'Held K' 0)))
    Check 'control: the held window takes its kept half, slot 2 (136,0,136,500)' (OnCell $r 8301 2 (OhHalfH 1)) (Desc $r 8301)
  }
  Case 'control: keep, horizontal: a kept slot keyed by a role name is not a monitor id, so it holds nothing' {
    $fill = [pscustomobject]@{ mon = $ohId; apps = @('claude'); skip = @(); sort = 'app'; unit = @(2, 1); keepEmpty = @([pscustomobject]@{ mon = 'wide'; slots = @(2) }) }
    $sc = FgScene 'oh-k5-scene.json' (FgGrid 2 1) @() $fill @() $ohId
    $wins = @(1..9 | % { FgWin (8400 + $_) 'claude' "Fill $_" (100 * $_) })
    $r = Invoke-SceneFrom $sc (Write-Snap 'oh-k5-snap.json' @($ohM) $wins)
    Check 'scope: the nine claude windows are placed' (@($r.placed).Count -eq 9) "placed $(@($r.placed).Count), left $(@($r.left).Count)"
    Check 'control: window 2 takes block 1, slots 3+4 (272,0,272,500), as the role-named entry holds nothing' (OhIs $r 8402 (OhPairH 1) (CellRect $ohM 5 2 1)) (Desc $r 8402)
  }
  Case 'control: keep, role-keyed scene: fill.keepEmpty is ignored, so the kept slot 2 takes window 2 at its half rect, as on main' {
    $fill = [pscustomobject]@{ mon = 'wide'; apps = @('claude'); skip = @(); sort = 'app'; keepEmpty = @([pscustomobject]@{ mon = 'wide'; slots = @(1) }) }
    $sc = FgScene 'oh-rolekeep-scene.json' (FgGrid 2 1) @() $fill
    $wins = @(1..3 | % { FgWin (8500 + $_) 'claude' "Fill $_" (100 * $_) })
    $r = Invoke-SceneFrom $sc (Write-Snap 'oh-rolekeep-snap.json' @($ohM) $wins)
    Check 'scope: the three claude windows are placed' (@($r.placed).Count -eq 3) "placed $(@($r.placed).Count), left $(@($r.left).Count)"
    Check 'control: window 2 takes slot 2, the kept slot, at its half rect (136,0,136,500), as on main' (OnCell $r 8502 2 (OhHalfH 1)) (Desc $r 8502)
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

  # ---- Free-area rect bounds. Resolve-FreeAreas keeps an area whose rect is four finite numbers with a width and height above 0,
  # and Get-AreaPixelRects rounds each line to a whole pixel, so an area can reach its window 0 px wide or high, or past the work area's edge.
  # Contract: no window is placed under 1 px wide or high, and none is placed outside the work area (0,0 to W,H). An area that rounds to under 1 px is dropped,
  # as an area with a bad rect already is: its pin is listed missing, 'not in a free area'. For an area past an edge, a drop and a clamp both meet the
  # contract, so its window is either not placed or placed inside the work area; no clamped rect is pinned. Each case has a control area, a valid one whose
  # window must land on its exact rect, so the scene is live before a bad area is judged. Every run is a dry run (-From). Window ids start at 7001.
  # Red on c921613: every subject check fails by an assert (the bad window is placed at its bad rect). The controls pass there and must stay green.
  # When no area keeps a pixel, Resolve-FreeAreas returns $null and the run takes the grid. The empty-state case checks that fallback: without the
  # statement that returns $null for an empty keep list, its run throws and its grid check fails by an assert.
  # The pixel rect an area of fractions [fx, fy, fw, fh] gets on a $w by $h work area: each line rounded once, as Get-AreaPixelRects rounds it.
  function FbPx([double]$f, [int]$n) { [int][Math]::Round([Math]::Round($f, 9) * $n) }
  function FbWant([int]$w, [int]$h, $f) { $x = FbPx $f[0] $w; $y = FbPx $f[1] $h; '{0},{1},{2},{3}' -f $x, $y, ((FbPx ($f[0] + $f[2]) $w) - $x), ((FbPx ($f[1] + $f[3]) $h) - $y) }
  # One pinned area per item (@{ rect; app; title }); item i's window is 7001 + i. The grid is one column per item, which only a run with every area dropped uses.
  function FbRun([string]$tag, [int]$w, [int]$h, $items) {
    $n = @($items).Count; $areas = @(); $pins = @(); $wins = @()
    for ($i = 0; $i -lt $n; $i++) {
      $it = $items[$i]
      $areas += FreeArea $it.rect $i
      $pins += FgPin $it.app $it.title @($i)
      $wins += FgWin (7001 + $i) $it.app $it.title (100 * $i)
    }
    $sc = FgScene "FB-$tag-scene.json" (FreeGrid $n 1 $areas) $pins
    Invoke-SceneFrom $sc (Write-Snap "FB-$tag.json" @(FgMon $w $h) $wins)
  }
  function FbInside($p, [int]$w, [int]$h) { [int]$p.x -ge 0 -and [int]$p.y -ge 0 -and ([int]$p.x + [int]$p.w) -le $w -and ([int]$p.y + [int]$p.h) -le $h }
  function FbInsideOrAbsent($r, [int64]$id, [int]$w, [int]$h) { $p = PlacedOf $r $id; (-not $p) -or (FbInside $p $w $h) }
  function FbSizedOrAbsent($r, [int64]$id) { $p = PlacedOf $r $id; (-not $p) -or ([int]$p.w -ge 1 -and [int]$p.h -ge 1) }
  function FbMissingText($r) { "missing: $(@($r.missing | % { "$($_.app) ($($_.why))" }) -join ', ')" }
  function FbIsMissing($r, [string]$app) { @($r.missing | ? { $_.app -ceq $app -and $_.why -ceq 'not in a free area' }).Count -eq 1 }

  Case 'free-area bounds: an area that rounds to 0 px wide or high is dropped, so no window is placed 0 px wide or high (four work areas)' {
    foreach ($dim in $l3Sizes) {
      $w = [int]$dim[0]; $h = [int]$dim[1]; $tag = "${w}x$h"; $ctl = @(0.4, 0, 0.6, 1)
      $r = FbRun "zero-$tag" $w $h @(@{ rect = $ctl; app = 'chrome'; title = 'Control' }, @{ rect = @(0, 0, (0.3 / $w), 1); app = 'claude'; title = 'Sliver W' }, @{ rect = @(0.2, 0, 0.2, (0.3 / $h)); app = 'ms-teams'; title = 'Sliver H' })
      $scope = (RectOf (PlacedOf $r 7001)) -ceq (FbWant $w $h $ctl)
      Check "free-area bounds zero ${tag}: scope, the control area takes its window at $(FbWant $w $h $ctl)" $scope "$(Desc $r 7001)"
      if (-not $scope) { continue }
      Check "free-area bounds zero ${tag}: an area 0 px wide places no window under 1 px" (FbSizedOrAbsent $r 7002) (Desc $r 7002)
      Check "free-area bounds zero ${tag}: an area 0 px high places no window under 1 px" (FbSizedOrAbsent $r 7003) (Desc $r 7003)
      Check "free-area bounds zero ${tag}: the pin of the 0 px wide area is listed missing, not in a free area" (FbIsMissing $r 'claude') (FbMissingText $r)
      Check "free-area bounds zero ${tag}: the pin of the 0 px high area is listed missing, not in a free area" (FbIsMissing $r 'ms-teams') (FbMissingText $r)
    }
  }
  Case 'free-area bounds: an area past an edge of the work area places its window inside the work area or not at all (four work areas, four edges)' {
    foreach ($dim in $l3Sizes) {
      $w = [int]$dim[0]; $h = [int]$dim[1]; $tag = "${w}x$h"; $ctl = @(0, 0, 0.4, 0.4)
      $r = FbRun "edge-$tag" $w $h @(
        @{ rect = $ctl; app = 'chrome'; title = 'Control' },
        @{ rect = @(0.9, 0, 0.5, 0.4); app = 'claude'; title = 'Right edge' },
        @{ rect = @(0, 0.9, 0.4, 0.5); app = 'ms-teams'; title = 'Bottom edge' },
        @{ rect = @(-0.3, 0.45, 0.4, 0.4); app = 'outlook'; title = 'Left edge' },
        @{ rect = @(0.5, -0.2, 0.3, 0.4); app = 'chrome'; title = 'Top edge' })
      $scope = (RectOf (PlacedOf $r 7001)) -ceq (FbWant $w $h $ctl)
      Check "free-area bounds edge ${tag}: scope, the control area takes its window at $(FbWant $w $h $ctl)" $scope "$(Desc $r 7001)"
      if (-not $scope) { continue }
      Check "free-area bounds edge ${tag}: an area past the right edge (x 0.9, w 0.5) places its window inside the work area or not at all" (FbInsideOrAbsent $r 7002 $w $h) (Desc $r 7002)
      Check "free-area bounds edge ${tag}: an area past the bottom edge (y 0.9, h 0.5) places its window inside the work area or not at all" (FbInsideOrAbsent $r 7003 $w $h) (Desc $r 7003)
      Check "free-area bounds edge ${tag}: an area past the left edge (x -0.3) places its window inside the work area or not at all" (FbInsideOrAbsent $r 7004 $w $h) (Desc $r 7004)
      Check "free-area bounds edge ${tag}: an area past the top edge (y -0.2) places its window inside the work area or not at all" (FbInsideOrAbsent $r 7005 $w $h) (Desc $r 7005)
    }
  }
  Case 'free-area bounds control: an area that ends exactly on an edge, and one that rounds to exactly 1 px, keep their rects (four work areas)' {
    foreach ($dim in $l3Sizes) {
      $w = [int]$dim[0]; $h = [int]$dim[1]; $tag = "${w}x$h"
      $items = @(@{ rect = @(0.5, 0.5, 0.5, 0.5); app = 'chrome'; title = 'Corner' }, @{ rect = @(0, 0, (0.6 / $w), 0.4); app = 'claude'; title = 'One wide' }, @{ rect = @(0.2, 0, 0.2, (0.6 / $h)); app = 'ms-teams'; title = 'One high' })
      $r = FbRun "keep-$tag" $w $h $items
      $bad = @(0..2 | ? { -not ((RectOf (PlacedOf $r (7001 + $_))) -ceq (FbWant $w $h $items[$_].rect)) } | % { "$($items[$_].title): want $(FbWant $w $h $items[$_].rect); $(Desc $r (7001 + $_))" })
      Check "free-area bounds control ${tag}: the corner area (x1 = 1, y1 = 1), a 1 px wide area and a 1 px high area each keep their window at their rect" ($bad.Count -eq 0) ($bad -join ' | ')
    }
  }
  Case 'free-area bounds, empty state: when every area is bad, the run falls back to the grid, and no window is placed under 1 px or outside the work area (1365x1001)' {
    $w = 1365; $h = 1001; $m = FgMon $w $h; $r = $null; $thrown = ''
    try { $r = FbRun 'none' $w $h @(@{ rect = @(0, 0, (0.3 / $w), 1); app = 'claude'; title = 'Sliver W' }, @{ rect = @(0.2, 0, 0.2, (0.3 / $h)); app = 'ms-teams'; title = 'Sliver H' }, @{ rect = @(1.05, 0, 0.5, 1); app = 'chrome'; title = 'Past right edge' }) } catch { $thrown = $_.Exception.Message }
    Check 'free-area bounds empty: the run does not throw' ($thrown -eq '') "threw: $thrown"
    # Each area clamps to under 1 px, so Resolve-FreeAreas returns $null and the grid of three columns places window i+1 in cell i+1.
    $grid = @(0..2 | ? { -not (OnCell $r (7001 + $_) ($_ + 1) (CellRect $m 3 1 $_)) } | % { "$(Desc $r (7001 + $_)), want slot $($_ + 1) at $(CellRect $m 3 1 $_)" })
    Check 'free-area bounds empty: every area is bad, so the run falls back to the grid: each window takes its own cell' ($grid.Count -eq 0) ($grid -join ' | ')
    $placed = @(@($r.placed) | ? { $null -ne $_ })
    $small = @($placed | ? { [int]$_.w -lt 1 -or [int]$_.h -lt 1 } | % { "id $($_.id) rect $(RectOf $_)" })
    Check 'free-area bounds empty: no window is placed under 1 px' ($small.Count -eq 0) ($small -join ' | ')
    $out = @($placed | ? { -not (FbInside $_ $w $h) } | % { "id $($_.id) rect $(RectOf $_)" })
    Check 'free-area bounds empty: no window is placed outside the work area' ($out.Count -eq 0) ($out -join ' | ')
  }
  Case 'free-area bounds, full size: ten cell areas and an eleventh past the corner, eleven fill windows: the ten cells keep their rects, and window 11 is inside the work area or not placed (1365x1001)' {
    $w = 1365; $h = 1001; $m = FgMon $w $h; $cw = [int]($w / 5); $ch = [int]($h / 2)
    $areas = @(0..9 | % { FreeArea @((($_ % 5) * $cw / $w), ([Math]::Floor($_ / 5) * $ch / $h), ($cw / $w), ($ch / $h)) }) + @(FreeArea @(0.9, 0.9, 0.5, 0.5))
    $fill = [pscustomobject]@{ mon = 'wide'; apps = @('claude'); skip = @(); sort = 'app' }
    $sc = FgScene 'FB-full-scene.json' (FreeGrid 5 2 $areas) @() $fill
    $r = Invoke-SceneFrom $sc (Write-Snap 'FB-full.json' @($m) @(0..10 | % { FgWin (7101 + $_) 'claude' "Fill $($_ + 1)" (100 * $_) }))
    $bad = @(0..9 | ? { -not ((RectOf (PlacedOf $r (7101 + $_))) -ceq (CellRect $m 5 2 $_)) } | % { "Fill $($_ + 1): $(Desc $r (7101 + $_))" })
    $scope = $bad.Count -eq 0
    Check 'free-area bounds full: scope, windows 1 to 10 take the ten cells, each at its cell rect' $scope ($bad -join ' | ')
    if (-not $scope) { return }
    Check 'free-area bounds full: window 11, the fill window for the area past the corner, is inside the work area or not placed' (FbInsideOrAbsent $r 7111 $w $h) (Desc $r 7111)
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
    [pscustomobject]@{ id = 'G10'; size = @(1200, 900); areas = $gGrid3; calls = $gSub3 },
    # G11, G12: the centre area (3) is gone; the left (G11) or right (G12) neighbour was grown up into gone area 0 (top corner), so its midpoint
    # share hits live area 1 above the centre. G13 is the mirror: the centre's above and below overlap, and left and right meet at the midpoint.
    [pscustomobject]@{ id = 'G11'; size = @(1500, 1200); areas = @((GArea @(0, 0, (1 / 3), (1 / 3))), (GArea @((1 / 3), (1 / 6), (1 / 3), (1 / 6))), (GArea @(0, (1 / 3), (1 / 3), (1 / 3))), (GArea @((1 / 3), (1 / 3), (1 / 3), (1 / 3))), (GArea @((2 / 3), (1 / 3), (1 / 3), (1 / 3))), (GArea @((1 / 3), (2 / 3), (1 / 3), (1 / 3)))); calls = @([pscustomobject]@{ absent = @(0, 3); locked = @() }, [pscustomobject]@{ absent = @(3, 0); locked = @() }) },
    [pscustomobject]@{ id = 'G12'; size = @(1500, 1200); areas = @((GArea @((2 / 3), 0, (1 / 3), (1 / 3))), (GArea @((1 / 3), (1 / 6), (1 / 3), (1 / 6))), (GArea @(0, (1 / 3), (1 / 3), (1 / 3))), (GArea @((1 / 3), (1 / 3), (1 / 3), (1 / 3))), (GArea @((2 / 3), (1 / 3), (1 / 3), (1 / 3))), (GArea @((1 / 3), (2 / 3), (1 / 3), (1 / 3)))); calls = @([pscustomobject]@{ absent = @(0, 3); locked = @() }, [pscustomobject]@{ absent = @(3, 0); locked = @() }) },
    [pscustomobject]@{ id = 'G13'; size = @(1500, 1200); areas = @((GArea @(0, 0, (1 / 3), (1 / 3))), (GArea @((1 / 3), 0, (1 / 3), (1 / 3))), (GArea @((1 / 6), (1 / 3), (1 / 6), (1 / 3))), (GArea @((1 / 3), (1 / 3), (1 / 3), (1 / 3))), (GArea @((2 / 3), (1 / 3), (1 / 3), (1 / 3))), (GArea @((1 / 3), (2 / 3), (1 / 3), (1 / 3)))); calls = @([pscustomobject]@{ absent = @(0, 3); locked = @() }, [pscustomobject]@{ absent = @(3, 0); locked = @() }) }
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

  # Gap-fill order: a side whose share would overlap is not taken; the next qualifying side takes the region. Keys are found by the absent subset.
  function GKey([string]$id, $sub, $absent) {
    for ($k = 0; $k -lt @($sub).Count; $k++) { if ((GSet ($sub[$k].absent)) -eq (GSet $absent)) { return "$id|$k" } }
    "$id|no-call"
  }
  # The 2x2 with {1,2} gone: area 0 takes the top line and area 3 the bottom line, with no gap and no overlap. The mirror {0,3}:
  # area 1 takes the top line and area 2 the bottom line.
  Case 'L3 item G: a side whose share would overlap is skipped for the next qualifying side, 2x2 absent {1,2} and its mirror {0,3}' {
    GCheck 'L3 item G: 2x2 absent {1,2}: area 0 takes the top line, area 3 the bottom line, no gap and no overlap (1200 x 900)' (GKey 'G9' $gSub2 @(1, 2)) @(@(0, 0, 1, 0.5), $null, $null, @(0, 0.5, 1, 0.5))
    GCheck 'L3 item G: 2x2 absent {0,3} (mirror): area 1 takes the top line, area 2 the bottom line (1200 x 900)' (GKey 'G9' $gSub2 @(0, 3)) @($null, @(0, 0, 1, 0.5), @(0, 0.5, 1, 0.5), $null)
  }

  # Midpoint fall-through (item G): when left and right both qualify but their midpoint share would overlap a live area, the pair is not taken
  # and the above and below pair is tried at its midpoint. G11 (left neighbour grown up) and G12 (right neighbour grown up) are the two sides of
  # one case. Both absent orders give the same result. Areas: 0 gone (top corner), 1 above the centre, 2 left, 3 centre gone, 4 right, 5 below.
  # Expected (1500 x 1200): above and below meet at y 1/2, area 1 takes y 1/6..1/2 and area 5 takes 1/2..1. Left and right keep their rects,
  # except the neighbour that grew into area 0, which keeps that growth. A pair that never gets its turn gives the centre to area 1 alone.
  $wantG11 = @($null, @((1 / 3), (1 / 6), (1 / 3), (1 / 3)), @(0, 0, (1 / 3), (2 / 3)), $null, @((2 / 3), (1 / 3), (1 / 3), (1 / 3)), @((1 / 3), (1 / 2), (1 / 3), (1 / 2)))
  $wantG12 = @($null, @((1 / 3), (1 / 6), (1 / 3), (1 / 3)), @(0, (1 / 3), (1 / 3), (1 / 3)), $null, @((2 / 3), 0, (1 / 3), (2 / 3)), @((1 / 3), (1 / 2), (1 / 3), (1 / 2)))
  Case 'L3 item G: midpoint overlap on the left: above and below meet at the midpoint, not the left side (G11, both absent orders)' {
    GCheck 'L3 item G: left neighbour grown up, left and right midpoint overlaps area 1: above and below meet at y 1/2, no gap, no overlap (G11, absent {0,3})' 'G11|0' $wantG11
    GCheck 'L3 item G: same case, absent {3,0}: the same result (G11, absent order reversed)' 'G11|1' $wantG11
  }
  Case 'L3 item G: midpoint overlap on the right: above and below meet at the midpoint, not the right side (G12, both absent orders)' {
    GCheck 'L3 item G: right neighbour grown up, left and right midpoint overlaps area 1: above and below meet at y 1/2, no gap, no overlap (G12, absent {0,3})' 'G12|0' $wantG12
    GCheck 'L3 item G: same case, absent {3,0}: the same result (G12, absent order reversed)' 'G12|1' $wantG12
  }
  # Mirror (control): above and below overlap, and left and right both qualify. Left and right still meet at the midpoint; the pair order is unchanged.
  $wantG13 = @($null, @(0, 0, (2 / 3), (1 / 3)), @((1 / 6), (1 / 3), (1 / 3), (1 / 3)), $null, @((1 / 2), (1 / 3), (1 / 2), (1 / 3)), @((1 / 3), (2 / 3), (1 / 3), (1 / 3)))
  Case 'L3 item G: control: above and below overlap, left and right meet at the midpoint (G13, both absent orders)' {
    GCheck 'L3 item G: control, mirror of G11: the above and below midpoint overlaps, so left and right meet at x 1/2 (G13, absent {0,3})' 'G13|0' $wantG13
    GCheck 'L3 item G: control, same case, absent {3,0}: the same result (G13, absent order reversed)' 'G13|1' $wantG13
  }

  # ---- Gap fill (L5a, plan layout-free-build, L5a and item G; owner ruling 2026-11-18 11:08 CST: closed and minimized). ----
  # Contract the builder meets. Every run here passes -From, so it is a dry run:
  #   tile.ps1 -Scene <json> -From <snap> -GapFill -Absent <ids> -Last <json> -Json, printing {placed, missing, left}.
  #   placed lists only the windows the run moves, each with its to-rect (x, y, w, h). A window it does not move is not listed.
  #   -Absent: handle ids of the windows that closed or minimized. An absent window is not placed. Its area is a gone region for Get-CollapsedAreas.
  #   -Last: [{id, x, y, w, h}], the rect the tray last gave each tiled window. It is read the way -Place is read (JsonText).
  #   A window moves only from its scene rect or its -Last rect. Any other rect is a hand move: it stays put, and its area counts as locked.
  #   A pin with lock true locks its area. tile.ps1's header says the page reads that lock; -GapFill reads it too. A locked area never moves.
  #   Nothing is placed into a gap: no fill, no pin.
  #   A minimized window is a -From window with min true, at x and y -32000 (FgWin's -min).
  # On 74f87cb the flags are ignored, so each run is a plain scene run, and each case fails on the rect it expects there.
  Case 'L5a scope: tile.ps1 declares -GapFill, -Absent and -Last' {
    $tk = $null; $te = $null
    $ast = [Management.Automation.Language.Parser]::ParseFile($tile, [ref]$tk, [ref]$te)
    $declared = @($ast.ParamBlock.Parameters | % { [string]$_.Name.VariablePath.UserPath })
    $notDeclared = @('GapFill', 'Absent', 'Last') | ? { $declared -notcontains $_ }
    Check 'L5a scope: tile.ps1 declares -GapFill, -Absent and -Last' ($notDeclared.Count -eq 0) "not declared: $($notDeclared -join ', ')"
  }
  # A board: one area per window, pin index = area index. $fr: fractions of a 1200 x 900 work area (quarter lines are whole pixels).
  # $who: [app, title] per area. $gone: areas whose window is gone. $locks: areas whose pin is locked. $cur: area -> snapshot rect (a hand move).
  # $last: area -> -Last rect (default: the scene rect). $rev: the windows, -Absent and -Last listed in reverse (fixture order independence).
  function GfPx($f) { @([int][Math]::Round($f[0] * 1200), [int][Math]::Round($f[1] * 900), [int][Math]::Round($f[2] * 1200), [int][Math]::Round($f[3] * 900)) }
  function GfId([int]$i) { 6401 + $i }
  function GfPin($app, $match, [bool]$lock = $false) { $p = FgPin $app $match @(0); if ($lock) { $p | Add-Member -NotePropertyName lock -NotePropertyValue $true }; $p }
  function GfScenePath([string]$tag, $fr, $who, $locks) {
    $areas = @(); $pins = @()
    for ($i = 0; $i -lt @($fr).Count; $i++) { $areas += FreeArea $fr[$i] $i; $pins += GfPin $who[$i][0] $who[$i][1] ($locks -contains $i) }
    FgScene "L5a-$tag-scene.json" (FreeGrid 1 1 $areas) $pins $null
  }
  function GfBoard([string]$tag, $fr, $who, $gone, $locks, [string]$closure, $cur = @{}, $last = @{}, [bool]$rev = $false) {
    $sc = GfScenePath $tag $fr $who $locks
    $wins = @(); $lastOut = @(); $absent = @()
    for ($i = 0; $i -lt @($fr).Count; $i++) {
      $id = GfId $i; $px = GfPx $fr[$i]
      $lr = if ($last.ContainsKey($i)) { $last[$i] } else { $px }
      $lastOut += [pscustomobject]@{ id = $id; x = $lr[0]; y = $lr[1]; w = $lr[2]; h = $lr[3] }
      if ($gone -contains $i) {
        $absent += $id
        if ($closure -eq 'minimized') { $wins += FgWin $id $who[$i][0] $who[$i][1] 0 0 $px[2] $px[3] -min }
        continue
      }
      $cr = if ($cur.ContainsKey($i)) { $cur[$i] } else { $px }
      $wins += FgWin $id $who[$i][0] $who[$i][1] $cr[0] $cr[1] $cr[2] $cr[3]
    }
    if ($rev) { [array]::Reverse($wins); [array]::Reverse($absent); [array]::Reverse($lastOut) }
    [pscustomobject]@{ scene = $sc; snap = (Write-Snap "L5a-$tag-$closure.json" @(FgMon 1200 900) $wins); wins = @($wins); absent = @($absent); last = (ConvertTo-Json -InputObject @($lastOut) -Depth 4 -Compress) }
  }
  function GfGo($b) { ConvertFrom-Json ((& $tile -Scene $b.scene -From $b.snap -GapFill -Absent @($b.absent) -Last $b.last -Json 3>$null) -join '') }
  # Expected moves: area index -> 'x,y,w,h' for a move, or 'stay'. Returns the same table keyed by window id.
  function GfExpect($exp) { $h = @{}; foreach ($k in $exp.Keys) { $h["$(GfId ([int]$k))"] = $exp[$k] }; $h }
  # The run's moves against $expect (id string -> 'x,y,w,h' or 'stay'). A stay passes when the window is not placed, or is placed at its own snapshot
  # rect. A placed window that $expect does not name fails too. The FAIL line names each window that is wrong.
  function GfCheck([string]$name, $r, $wins, [hashtable]$expect) {
    $bad = @()
    foreach ($id in $expect.Keys) {
      $p = PlacedOf $r ([int64]$id); $want = $expect[$id]
      if ($want -eq 'stay') {
        $w = @($wins | ? { "$($_.id)" -eq $id })[0]
        if ($p -and $w -and (RectOf $p) -cne ('{0},{1},{2},{3}' -f [int]$w.x, [int]$w.y, [int]$w.w, [int]$w.h)) { $bad += "id $id moved to $(RectOf $p), should stay" }
      } elseif (-not $p -or (RectOf $p) -cne $want) { $bad += "id $id $(Desc $r ([int64]$id)), want $want" }
    }
    foreach ($p in @($r.placed)) { if (-not $expect.ContainsKey("$($p.id)")) { $bad += "id $($p.id) moved to $(RectOf $p), should stay" } }
    Check $name ($bad.Count -eq 0) ($bad -join ' | ')
  }
  # The shapes. Each is a board whose gone area is one window; the four single-side shapes give the one side that takes it, and the midpoint
  # shapes give the two sides. 'lock' rows put a lock on the one side that would take it, so that side never moves.
  $gfRows = @(
    [pscustomobject]@{ name = 'left and right, midpoint'; fr = @(@(0, 0, 0.25, 1), @(0.25, 0, 0.5, 1), @(0.75, 0, 0.25, 1)); who = @(@('chrome', 'Left'), @('claude', 'Gone'), @('outlook', 'Right')); gone = @(1); locks = @(); exp = @{ 0 = '0,0,600,900'; 2 = '600,0,600,900' } },
    [pscustomobject]@{ name = 'left and right, left locked'; fr = @(@(0, 0, 0.25, 1), @(0.25, 0, 0.5, 1), @(0.75, 0, 0.25, 1)); who = @(@('chrome', 'Left'), @('claude', 'Gone'), @('outlook', 'Right')); gone = @(1); locks = @(0); exp = @{ 0 = 'stay'; 2 = '300,0,900,900' } },
    [pscustomobject]@{ name = 'left and right, right locked'; fr = @(@(0, 0, 0.25, 1), @(0.25, 0, 0.5, 1), @(0.75, 0, 0.25, 1)); who = @(@('chrome', 'Left'), @('claude', 'Gone'), @('outlook', 'Right')); gone = @(1); locks = @(2); exp = @{ 0 = '0,0,900,900'; 2 = 'stay' } },
    [pscustomobject]@{ name = 'right side takes it (left edge gone)'; fr = @(@(0, 0, 0.25, 1), @(0.25, 0, 0.75, 1)); who = @(@('claude', 'Gone'), @('chrome', 'Right')); gone = @(0); locks = @(); exp = @{ 1 = '0,0,1200,900' } },
    [pscustomobject]@{ name = 'right side locked, gap stays'; fr = @(@(0, 0, 0.25, 1), @(0.25, 0, 0.75, 1)); who = @(@('claude', 'Gone'), @('chrome', 'Right')); gone = @(0); locks = @(1); exp = @{ 1 = 'stay' } },
    [pscustomobject]@{ name = 'left side takes it (right edge gone)'; fr = @(@(0, 0, 0.75, 1), @(0.75, 0, 0.25, 1)); who = @(@('chrome', 'Left'), @('claude', 'Gone')); gone = @(1); locks = @(); exp = @{ 0 = '0,0,1200,900' } },
    [pscustomobject]@{ name = 'left side locked, gap stays'; fr = @(@(0, 0, 0.75, 1), @(0.75, 0, 0.25, 1)); who = @(@('chrome', 'Left'), @('claude', 'Gone')); gone = @(1); locks = @(0); exp = @{ 0 ='stay' } },
    [pscustomobject]@{ name = 'above side takes it (bottom gone)'; fr = @(@(0, 0, 1, 0.5), @(0, 0.5, 1, 0.5)); who = @(@('chrome', 'Top'), @('claude', 'Gone')); gone = @(1); locks = @(); exp = @{ 0 = '0,0,1200,900' } },
    [pscustomobject]@{ name = 'above side locked, gap stays'; fr = @(@(0, 0, 1, 0.5), @(0, 0.5, 1, 0.5)); who = @(@('chrome', 'Top'), @('claude', 'Gone')); gone = @(1); locks = @(0); exp = @{ 0 = 'stay' } },
    [pscustomobject]@{ name = 'below side takes it (top gone)'; fr = @(@(0, 0, 1, 0.5), @(0, 0.5, 1, 0.5)); who = @(@('claude', 'Gone'), @('chrome', 'Bottom')); gone = @(0); locks = @(); exp = @{ 1 = '0,0,1200,900' } },
    [pscustomobject]@{ name = 'below side locked, gap stays'; fr = @(@(0, 0, 1, 0.5), @(0, 0.5, 1, 0.5)); who = @(@('claude', 'Gone'), @('chrome', 'Bottom')); gone = @(0); locks = @(1); exp = @{ 1 = 'stay' } },
    [pscustomobject]@{ name = 'above and below, midpoint'; fr = @(@(0, 0, 1, 0.25), @(0, 0.25, 1, 0.5), @(0, 0.75, 1, 0.25)); who = @(@('chrome', 'Top'), @('claude', 'Gone'), @('outlook', 'Bottom')); gone = @(1); locks = @(); exp = @{ 0 = '0,0,1200,450'; 2 = '0,450,1200,450' } },
    [pscustomobject]@{ name = 'above and below, top locked'; fr = @(@(0, 0, 1, 0.25), @(0, 0.25, 1, 0.5), @(0, 0.75, 1, 0.25)); who = @(@('chrome', 'Top'), @('claude', 'Gone'), @('outlook', 'Bottom')); gone = @(1); locks = @(0); exp = @{ 0 = 'stay'; 2 = '0,225,1200,675' } },
    [pscustomobject]@{ name = 'above and below, bottom locked'; fr = @(@(0, 0, 1, 0.25), @(0, 0.25, 1, 0.5), @(0, 0.75, 1, 0.25)); who = @(@('chrome', 'Top'), @('claude', 'Gone'), @('outlook', 'Bottom')); gone = @(1); locks = @(2); exp = @{ 0 = '0,0,1200,675'; 2 = 'stay' } }
  )
  foreach ($row in $gfRows) {
    foreach ($closure in 'closed', 'minimized') {
      Case "L5a gap, $($row.name) ($closure)" {
        $b = GfBoard $row.name $row.fr $row.who $row.gone $row.locks $closure
        $r = GfGo $b
        GfCheck "L5a gap, $($row.name), ${closure}: each named window takes its rect, the rest stay" $r $b.wins (GfExpect $row.exp)
      }
    }
  }
  # Hand move: the left neighbour was moved by hand, to a rect that is neither its scene rect nor its -Last rect. It stays put, and no placed window
  # lands on it.
  foreach ($closure in 'closed', 'minimized') {
    Case "L5a hand move, ${closure}: a neighbour moved by hand stays put, and no placed window overlaps it" {
      $row = $gfRows[0]
      $b = GfBoard 'hand' $row.fr $row.who $row.gone @() $closure @{ 0 = @(20, 20, 260, 860) }
      $r = GfGo $b
      $p0 = PlacedOf $r 6401
      Check "L5a hand move, ${closure}: the hand-moved window is not placed, or stays at its own rect" ((-not $p0) -or ((RectOf $p0) -ceq '20,20,260,860')) (Desc $r 6401)
      $hand = [pscustomobject]@{ x = 20; y = 20; w = 260; h = 860 }
      $over = @($r.placed | ? { "$($_.id)" -ne '6401' -and ([Math]::Min($_.x + $_.w, $hand.x + $hand.w) - [Math]::Max($_.x, $hand.x) -gt 0) -and ([Math]::Min($_.y + $_.h, $hand.y + $hand.h) - [Math]::Max($_.y, $hand.y) -gt 0) } | % { "id $($_.id) at $(RectOf $_)" })
      Check "L5a hand move, ${closure}: no placed window overlaps the hand-moved one" ($over.Count -eq 0) ($over -join ' | ')
    }
  }
  # Restore: the gone window is back, at its scene rect, and the neighbours that grew into its space shrink back from their -Last rects. A locked
  # neighbour stays at its -Last rect. 'new-id' is a window reopened under a new handle (no -Last entry for it).
  $rowM = $gfRows[0]
  foreach ($variant in 'same-id', 'new-id', 'locked') {
    Case "L5a restore, ${variant}: the neighbours shrink from their -Last rects, and a locked one stays" {
      $locks = if ($variant -eq 'locked') { @(0) } else { @() }
      $sc = GfScenePath "restore-$variant" $rowM.fr $rowM.who $locks
      $mid = if ($variant -eq 'new-id') { 6502 } else { 6402 }
      $wins = @((FgWin 6401 'chrome' 'Left side' 0 0 600 900), (FgWin $mid 'claude' 'Gone' 300 0 600 900), (FgWin 6403 'outlook' 'Right side' 600 0 600 900))
      $lastRects = @([pscustomobject]@{ id = 6401; x = 0; y = 0; w = 600; h = 900 }, [pscustomobject]@{ id = 6403; x = 600; y = 0; w = 600; h = 900 })
      if ($variant -eq 'same-id') { $lastRects += [pscustomobject]@{ id = 6402; x = 300; y = 0; w = 600; h = 900 } }
      $snap = Write-Snap "L5a-restore-$variant.json" @(FgMon 1200 900) $wins
      $r = ConvertFrom-Json ((& $tile -Scene $sc -From $snap -GapFill -Absent @() -Last (ConvertTo-Json -InputObject @($lastRects) -Depth 4 -Compress) -Json 3>$null) -join '')
      $exp = @{}; $exp['6401'] = $(if ($variant -eq 'locked') { 'stay' } else { '0,0,300,900' }); $exp['6403'] = '900,0,300,900'; $exp["$mid"] = 'stay'
      GfCheck "L5a restore, ${variant}: the neighbours go back to their scene rects, the restored window stays" $r $wins $exp
    }
  }
  # Two gone windows at once, the middle two of four. The outer neighbours take the midpoint, whichever order the ids come in.
  $fr4 = @(@(0, 0, 0.25, 1), @(0.25, 0, 0.25, 1), @(0.5, 0, 0.25, 1), @(0.75, 0, 0.25, 1))
  $who4 = @(@('chrome', 'L'), @('claude', 'M1'), @('claude', 'M2'), @('outlook', 'R'))
  foreach ($closure in 'closed', 'minimized') {
    foreach ($order in 'asc', 'desc') {
      Case "L5a two gone, $closure, ids ${order}: the outer neighbours meet at the midpoint in either order" {
        $b = GfBoard "order-$order" $fr4 $who4 @(1, 2) @() $closure @{} @{} ($order -eq 'desc')
        $r = GfGo $b
        GfCheck "L5a two gone, $closure, ids ${order}: the left window takes 0,0,600,900 and the right one 600,0,600,900" $r $b.wins (GfExpect @{ 0 = '0,0,600,900'; 3 = '600,0,600,900' })
      }
    }
  }
  # Fill: the gone area stays a gap, so the fill places no window into it. The spare outlook window would fill it on a plain run.
  foreach ($closure in 'closed', 'minimized') {
    Case "L5a fill, ${closure}: a gap takes no window, so the spare window the fill would place stays where it is" {
      $fill = [pscustomobject]@{ mon = 'wide'; apps = @('outlook'); skip = @(); sort = 'app' }
      $areas = @((FreeArea @(0, 0, 0.25, 1) 0), (FreeArea @(0.25, 0, 0.5, 1) 1), (FreeArea @(0.75, 0, 0.25, 1) 2))
      $sc = FgScene "L5a-fill-$closure-scene.json" (FreeGrid 1 1 $areas) @((GfPin 'chrome' 'Left'), (GfPin 'claude' 'Gone'), (GfPin 'outlook' 'Right')) $fill
      $wins = @((FgWin 6401 'chrome' 'Left side' 0 0 300 900), (FgWin 6403 'outlook' 'Right side' 900 0 300 900), (FgWin 6420 'outlook' 'Spare' 100 100 400 300))
      if ($closure -eq 'minimized') { $wins += FgWin 6402 'claude' 'Gone' 0 0 300 900 -min }
      $last = '[{"id":6401,"x":0,"y":0,"w":300,"h":900},{"id":6402,"x":300,"y":0,"w":600,"h":900},{"id":6403,"x":900,"y":0,"w":300,"h":900}]'
      $snap = Write-Snap "L5a-fill-$closure.json" @(FgMon 1200 900) $wins
      $r = ConvertFrom-Json ((& $tile -Scene $sc -From $snap -GapFill -Absent @(6402) -Last $last -Json 3>$null) -join '')
      $exp = GfExpect @{ 0 = '0,0,600,900'; 2 = '600,0,600,900' }; $exp['6420'] = 'stay'
      GfCheck "L5a fill, ${closure}: the neighbours meet at the midpoint, and the spare window stays" $r $wins $exp
    }
  }
  # Empty: -Absent empty, so the gone window's area is only empty. Nothing moves, as with no -GapFill.
  Case 'L5a empty: with -Absent empty, a window missing from the snapshot leaves its area empty and nothing moves' {
    $b = GfBoard 'empty' $rowM.fr $rowM.who $rowM.gone @() 'closed'
    $b.absent = @()
    $r = GfGo $b
    GfCheck 'L5a empty: the two neighbours stay at their scene rects' $r $b.wins (GfExpect @{ 0 = 'stay'; 2 = 'stay' })
  }
  # Full size: ten areas, the top middle one gone. A midpoint share would leave the left window 360 px wide, under the 400 floor, so the left side
  # takes the whole space (the first side that qualifies). Every other window stays.
  $fr10 = @(); $who10 = @()
  for ($i = 0; $i -lt 10; $i++) { $fr10 += , @((($i % 5) * 0.2), ([Math]::Floor($i / 5) * 0.5), 0.2, 0.5); $who10 += , @('claude', "Cell $($i + 1)") }
  foreach ($closure in 'closed', 'minimized') {
    Case "L5a full size, ${closure}: ten areas, the top middle one gone; the left neighbour takes the space, the other nine stay" {
      $b = GfBoard 'full' $fr10 $who10 @(2) @() $closure
      $r = GfGo $b
      $exp = @{}; for ($i = 0; $i -lt 10; $i++) { $exp[$i] = 'stay' }; $exp[1] = '240,0,480,450'
      GfCheck "L5a full size, ${closure}: the left window takes 240,0,480,450, the others stay (1200 x 900, ten areas)" $r $b.wins (GfExpect $exp)
    }
  }
  # Off: no -GapFill gives today's output. The literals are frozen from 74f87cb, the old commit: the closed middle window, no flag.
  $gfOffJson = '{"placed":[{"id":6401,"app":"chrome","title":"Left","mon":"wide","slots":[1],"pin":0,"zone":-1,"x":0,"y":0,"w":300,"h":900,"from":{"x":0,"y":0,"w":300,"h":900},"ok":true,"note":"dry run"},{"id":6403,"app":"outlook","title":"Right","mon":"wide","slots":[3],"pin":2,"zone":-1,"x":900,"y":0,"w":300,"h":900,"from":{"x":900,"y":0,"w":300,"h":900},"ok":true,"note":"dry run"}],"missing":[{"pin":1,"app":"claude","match":"Gone","why":"no open window"}],"left":[]}'
  $gfOffText = @('chrome    slots 1      x=0 y=0 300x900  Left', 'outlook   slots 3      x=900 y=0 300x900  Right', 'Grid 3x1 (400 x 900 per slot): pinned 2, tiled 0 of 0 others.') -join "`n"
  Case 'L5a off: a run with no -GapFill gives today''s output, as -Json and as text' {
    $b = GfBoard 'off' $rowM.fr $rowM.who $rowM.gone @() 'closed'
    $j = (& $tile -Scene $b.scene -From $b.snap -Json 3>$null) -join ''
    $t = (((& $tile -Scene $b.scene -From $b.snap 3>$null) | Out-String) -replace "`r", '').TrimEnd()
    Check 'L5a off: -Json output is byte-identical to today' ($j -ceq $gfOffJson) "got $j"
    Check 'L5a off: text output is byte-identical to today' ($t -ceq $gfOffText) "got $(($t -split "`n") -join ' / ')"
  }

} finally {
  foreach ($k in $saved.Keys) { if ($null -eq $saved[$k]) { Remove-Item "env:$k" -ErrorAction SilentlyContinue } else { Set-Item "env:$k" $saved[$k] } }
  Remove-Item -LiteralPath $run -Recurse -Force -ErrorAction SilentlyContinue
}
if ($script:fail) { "$($script:fail) check(s) failed."; exit 1 } else { 'All engine-layouts checks passed.' }
