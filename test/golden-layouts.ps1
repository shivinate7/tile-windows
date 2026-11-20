# Golden layouts (failure class: missing coverage; guards today's behaviour). Every starter scene in scenes.json runs through
# tile.ps1 -Scene <json> -From <snapshot> -Json, in process, on five snapshots built here from test/fixture.json (never the live desktop):
#   1365x1001, 3440x1392, 1080x1872: the fixture's windows on one monitor of that work area (a lone monitor holds the wide role).
#   fixture: the fixture's own three monitors, so the tall and laptop grids are frozen too.
#   empty: the fixture's monitors and no windows (the empty state).
# Each run's placed windows (id, monitor role, slots, rect), left and missing entries, and the grids it used are compared with the
# frozen file test/golden/<set>.json. Every starter needs a frozen entry, and every frozen entry a starter.
# Page (headless Edge over DevTools, the route bay.ps1 uses): the page's global cellRect(m, g, c0, r0, cs, rs) must give each placed
# window's frozen rect, for the cell span its slots cover on its grid. The page is asked directly; no page hook is used.
# The frozen files were written once from origin/main (9e6ae0a) by a one-off run. Nothing here rewrites them. A deliberate
# layout change re-freezes the affected file by hand, in the same commit, with its reason.
# Finer grid (L1): split copies of frozen starters (mult on the wide grid) must keep the frozen rects outside the split cell. Cases below the
# frozen-set loop; each runs tile.ps1 -Scene <json> -From <snapshot> -Json, a dry run.
# Free areas (L3): each frozen wide placement, rebuilt as an area of its grid, lands on its frozen rect. Cases after the split cases.
# Run alone: powershell -NoProfile -ExecutionPolicy Bypass -File test\golden-layouts.ps1
# test\run.ps1 runs this file in a child powershell and counts its FAIL lines.
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
$tile = Join-Path $root 'tile.ps1'; $serve = Join-Path $root 'serve.ps1'; $fixture = Join-Path $PSScriptRoot 'fixture.json'
$goldenDir = Join-Path $PSScriptRoot 'golden'
$utf8 = New-Object Text.UTF8Encoding $false
$script:fail = 0
function Check($name, $ok, $detail = '') { if ($ok) { "PASS  $name" } else { $script:fail++; "FAIL  $name  $detail" } }

# Run folders (test-temp-standard): one folder per run, <pid>-<UUID>, under one temp root per repo. The first request of a run
# removes sibling run folders older than a day and keeps newer ones. The sweep and its delete are run-folders.ps1's, shared with the other
# files, so each file still runs alone. The sweep takes its clock as a parameter: the proof below passes a fixed one.
. (Join-Path $PSScriptRoot 'run-folders.ps1')
$GoldenTempRoot = Join-Path $env:TEMP 'tile-windows-test-runs'
$GoldenRunName = '^\d+-[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
function GoldenSweep($dir, $olderThan, $now) { Invoke-RunFolderSweep $dir $GoldenRunName $olderThan $now }
[void](New-Item -ItemType Directory -Force $GoldenTempRoot)
GoldenSweep $GoldenTempRoot ([TimeSpan]::FromDays(1)) (Get-Date)
$run = Join-Path $GoldenTempRoot ("$PID-" + [guid]::NewGuid().ToString()); New-Item -ItemType Directory $run | Out-Null

# Environment this file reads or changes: the run's own home, and no monitor seam (TILE_SCREENS_FILE would stand in for a live read).
$savedEnv = @{ TILE_HOME = $env:TILE_HOME; TILE_SCREENS_FILE = $env:TILE_SCREENS_FILE }
$env:TILE_HOME = Join-Path $run 'home'; Remove-Item env:TILE_SCREENS_FILE -ErrorAction SilentlyContinue
$script:userDir = Join-Path $run 'profile'; New-Item -ItemType Directory -Force (Join-Path $script:userDir 'AppData\Roaming') | Out-Null
$script:udd = Join-Path $run 'edge'; $script:ws = $null; $script:cdpId = 0; $script:jsErr = ''

try {
  # The sweep, proven inside this run's folder with a fixed clock: an old run folder goes, a new one stays.
  $proof = Join-Path $run 'sweep-proof'; New-Item -ItemType Directory $proof | Out-Null
  $clock = [datetime]'2026-01-10T12:00:00'
  $oldRun = Join-Path $proof ('1-' + [guid]::NewGuid().ToString()); $newRun = Join-Path $proof ('2-' + [guid]::NewGuid().ToString())
  New-Item -ItemType Directory $oldRun | Out-Null; New-Item -ItemType Directory $newRun | Out-Null
  (Get-Item -LiteralPath $oldRun).LastWriteTime = $clock.AddDays(-2)
  (Get-Item -LiteralPath $newRun).LastWriteTime = $clock.AddHours(-1)
  GoldenSweep $proof ([TimeSpan]::FromDays(1)) $clock
  Check 'run folders: the sweep removes a run folder older than a day' (-not (Test-Path -LiteralPath $oldRun))
  Check 'run folders: the sweep keeps a run folder newer than a day' (Test-Path -LiteralPath $newRun)

  # The five snapshots. A monitor is one work area; the engine takes a lone monitor as the wide role.
  $fx = [IO.File]::ReadAllText($fixture, $utf8) | ConvertFrom-Json
  function GoldenMon($name, $role, $w, $h) { [pscustomobject]@{ name = $name; role = $role; x = 0; y = 0; w = $w; h = $h; bw = $w; bh = $h } }
  $sets = [ordered]@{
    '1365x1001' = [pscustomobject]@{ monitors = @(GoldenMon '\\.\DISPLAY1' 'wide' 1365 1001); windows = @($fx.windows) }
    '3440x1392' = [pscustomobject]@{ monitors = @(GoldenMon '\\.\DISPLAY1' 'wide' 3440 1392); windows = @($fx.windows) }
    '1080x1872' = [pscustomobject]@{ monitors = @(GoldenMon '\\.\DISPLAY1' 'wide' 1080 1872); windows = @($fx.windows) }
    'fixture'   = [pscustomobject]@{ monitors = @($fx.monitors); windows = @($fx.windows) }
    'empty'     = [pscustomobject]@{ monitors = @($fx.monitors); windows = @() }
  }

  $starters = [IO.File]::ReadAllText((Join-Path $root 'scenes.json'), $utf8) | ConvertFrom-Json
  $ids = @($starters.scenes | ForEach-Object { $_.id })
  # A scene as the page sends it: the scene plus the category map (the same as -Scene <name> resolves from scenes.json).
  function GoldenPosted($s) { $s | Add-Member -Force cats $starters.cats; $s | Add-Member -Force categories $starters.categories; ConvertTo-Json -Depth 10 -Compress $s }
  function GoldenStarter($id) { GoldenPosted (@($starters.scenes | ? { $_.id -eq $id })[0]) }
  # A starter's own copy, to edit. The frozen scene in scenes.json is never changed.
  function GoldenCopy($id) { ConvertFrom-Json (ConvertTo-Json -Depth 10 -Compress (@($starters.scenes | ? { $_.id -eq $id })[0])) }
  function GoldenRunPosted($postedJson, $snapJson, $name) {
    $raw = (& $tile -Scene $postedJson -From $snapJson -Json 3>$null) -join ''
    if (-not $raw) { throw "tile.ps1 printed nothing for $name" }
    ConvertFrom-Json $raw
  }
  function GoldenRun($id, $snapJson) { GoldenRunPosted (GoldenStarter $id) $snapJson $id }
  # One line per window, left entry and missing entry, in the same words for a run and for a frozen entry.
  function GoldenGrids($grids) { @($grids.PSObject.Properties | Sort-Object Name | % { "$($_.Name) $([int]$_.Value.c)x$([int]$_.Value.r)" }) }
  function GoldenLines($e, $grids) {
    [pscustomobject]@{
      grids = @(GoldenGrids $grids)
      placed = @(@($e.placed) | Sort-Object { [int64]$_.id } | % { "$([int64]$_.id) $($_.mon) slots $((@($_.slots) | % { [int]$_ }) -join '+') at $([int]$_.x),$([int]$_.y) $([int]$_.w)x$([int]$_.h)" })
      left = @(@($e.left) | Sort-Object { [int64]$_.id } | % { "$([int64]$_.id) $($_.app) $($_.why)" })
      missing = @(@($e.missing) | % { "pin $($_.pin) $($_.app) match [$($_.match)] $($_.why)" })
    }
  }
  function GoldenDiff($want, $got) {
    foreach ($k in 'grids', 'placed', 'left', 'missing') {
      $w = @($want.$k); $g = @($got.$k)
      if ($w.Count -ne $g.Count) { return "${k}: $($w.Count) frozen, $($g.Count) now" }
      for ($i = 0; $i -lt $w.Count; $i++) { if ($w[$i] -cne $g[$i]) { return "${k} $($i + 1): frozen '$($w[$i])', now '$($g[$i])'" } }
    }
    ''
  }

  foreach ($set in $sets.Keys) {
    $snapJson = ConvertTo-Json -Depth 6 -Compress $sets[$set]
    $file = Join-Path $goldenDir "$set.json"
    $gold = $null
    if (Test-Path -LiteralPath $file -PathType Leaf) { $gold = ConvertFrom-Json ([IO.File]::ReadAllText($file, $utf8)) }
    Check "golden ${set}: the frozen file exists" ($null -ne $gold) "no $file"
    if ($null -eq $gold) { continue }
    $names = @($gold.scenes.PSObject.Properties | % { $_.Name })
    $none = @($ids | ? { $names -notcontains $_ }); $extra = @($names | ? { $ids -notcontains $_ })
    Check "golden ${set}: the frozen file lists every starter, and no other" ($none.Count -eq 0 -and $extra.Count -eq 0) "no entry for: $($none -join ', '); extra: $($extra -join ', ')"
    foreach ($id in $ids) {
      $fz = $gold.scenes.PSObject.Properties[$id]
      if ($null -eq $fz) { continue }  # reported above
      $want = GoldenLines $fz.Value $fz.Value.grids
      # Scope before subject: an empty frozen entry would compare equal to an empty run, so it must hold something first.
      Check "golden ${set} ${id}: the frozen entry holds windows or missing pins" ($want.placed.Count + $want.left.Count + $want.missing.Count -gt 0) 'nothing frozen to compare'
      $s = @($starters.scenes | ? { $_.id -eq $id })[0]
      $got = $null; $err = ''
      try { $got = GoldenLines (GoldenRun $id $snapJson) $s.grids } catch { $err = "$_" }
      if ($null -eq $got) { Check "golden ${set} ${id}: tile.ps1 runs" $false $err; continue }
      $d = GoldenDiff $want $got
      Check "golden ${set} ${id}: placed windows, rects, left and missing match the frozen layout" ($d -eq '') $d
    }
  }
  # ---- Finer grid (L1, plan layout-free-build). A split doubles the wide grid: along x (mult [2,1]) or along y (mult [1,2]). Base cells
  # keep the L0 cut, so every window outside the split cell keeps its frozen rect. The split cell's kept window takes one half. Each
  # case edits a copy of a frozen starter and changes nothing else. Sets: the four frozen layouts that place windows.
  $splitSets = @('1365x1001', '3440x1392', '1080x1872', 'fixture')
  function SplitFrozen($set, $id) {
    $gold = ConvertFrom-Json ([IO.File]::ReadAllText((Join-Path $goldenDir "$set.json"), $utf8))
    $m = @{}; foreach ($p in @($gold.scenes.PSObject.Properties[$id].Value.placed)) { $m["$([int64]$p.id)"] = $p }; $m
  }
  function SplitPlaced($r) { $m = @{}; foreach ($p in @($r.placed)) { $m["$([int64]$p.id)"] = $p }; $m }
  function SameRect($a, $b) { [bool]($a -and $b -and [int]$a.x -eq [int]$b.x -and [int]$a.y -eq [int]$b.y -and [int]$a.w -eq [int]$b.w -and [int]$a.h -eq [int]$b.h) }
  function RectText($p) { if ($p) { "$([int]$p.x),$([int]$p.y) $([int]$p.w)x$([int]$p.h)" } else { 'not placed' } }
  function SetProp($o, [string]$name, $value) { Add-Member -InputObject $o -Force -NotePropertyName $name -NotePropertyValue $value }
  # One case. An error inside it is one FAIL line naming the case, and the run goes on (the same helper engine-layouts.ps1 keeps).
  function Case([string]$name, [scriptblock]$body) { try { & $body } catch { $script:fail++; "FAIL  $name  threw: $($_.Exception.Message)" } }
  # The frozen windows other than $skip: how many, and which differ from their frozen rect.
  function SplitOthers($got, $fz, $skip) {
    $others = @($fz.Keys | ? { $_ -ne $skip })
    $bad = @($others | ? { -not (SameRect $got[$_] $fz[$_]) })
    [pscustomobject]@{ n = $others.Count; bad = $bad; same = ($bad.Count -eq 0) }
  }
  # The frozen ids that the default entry left 'no free cell' (the fill ran out of blocks), read from its left list.
  function SplitNoCell($set) {
    $gold = ConvertFrom-Json ([IO.File]::ReadAllText((Join-Path $goldenDir "$set.json"), $utf8))
    @($gold.scenes.PSObject.Properties['default'].Value.left | ? { [string]$_.why -ceq 'no free cell' } | % { "$([int64]$_.id)" })
  }
  # layout-free item 6 (owner grant: yes, first recorded in commit 686934e, 2026-11-13 09:41 CST): the split's open half takes one window that the frozen run left 'no free cell', when there is one. $k is
  # 1001 in the split run, $f its frozen rect. The open half is the other half of $f's cell, at 1-based slot $slot.
  function SplitOpenHalf([string]$label, $set, $got, $fz, $k, $f, [string]$slot, [bool]$stacked) {
    $noCell = @(SplitNoCell $set)
    $added = @($got.Keys | ? { -not $fz.ContainsKey($_) })
    Check "${label} ${set}: scope, the frozen default left a window with no free cell, so the open half has one to take" ($noCell.Count -gt 0) 'the frozen left list has no no-free-cell entry'
    $takes = if ($noCell.Count) { $added.Count -eq 1 -and $noCell -contains $added[0] } else { $added.Count -eq 0 }
    Check "${label} ${set}: the open half takes one window the frozen run left with no free cell, and no other window is added" $takes "added: $($added -join ', ')"
    if ($added.Count -ne 1) { return }
    $e = $got[$added[0]]
    Check "${label} ${set}: the added window takes 1-based slot $slot" ((@($e.slots) -join '+') -ceq $slot) "now $(@($e.slots) -join '+')"
    $other = if ($stacked) {
      [int]$e.x -eq [int]$k.x -and [int]$e.w -eq [int]$k.w -and [int]$e.y -eq [int]$k.y + [int]$k.h -and [int]$e.y + [int]$e.h -eq [int]$f.y + [int]$f.h
    } else {
      [int]$e.y -eq [int]$k.y -and [int]$e.h -eq [int]$k.h -and [int]$e.x -eq [int]$k.x + [int]$k.w -and [int]$e.x + [int]$e.w -eq [int]$f.x + [int]$f.w
    }
    Check "${label} ${set}: the added window is the other half of 1001's cell, with no gap or overlap" ([bool]$other) "now $(RectText $e), 1001 $(RectText $k), frozen cell $(RectText $f)"
  }

  Case 'L1 split, horizontal: default 5x2 becomes 10x2; 1001 keeps the left half of slot 1; every other frozen window keeps its rect' {
    foreach ($set in $splitSets) {
      $fz = SplitFrozen $set 'default'; $snap = ConvertTo-Json -Depth 6 -Compress $sets[$set]
      $s = GoldenCopy 'default'
      SetProp $s.grids.wide 'mult' @(2, 1)
      SetProp $s.fill 'unit' @(2, 1)
      $s.pins = @($s.pins) + [pscustomobject]@{ app = 'claude'; match = 'Refactor the grid solver'; mon = 'wide'; slots = @(0) }
      $got = SplitPlaced (GoldenRunPosted (GoldenPosted $s) $snap "split default $set")
      $f = $fz['1001']; $k = $got['1001']
      Check "L1 split ${set}: scope, the frozen default places 1001 in wide slot 1" ([bool]($f -and [string]$f.mon -ceq 'wide' -and (@($f.slots) -join '+') -ceq '1')) "frozen: $(RectText $f)"
      Check "L1 split ${set}: 1001 keeps the left half of slot 1 (same x, y and height, narrower)" ([bool]($f -and $k -and [int]$k.x -eq [int]$f.x -and [int]$k.y -eq [int]$f.y -and [int]$k.h -eq [int]$f.h -and [int]$k.w -gt 0 -and [int]$k.w -lt [int]$f.w)) "now $(RectText $k), frozen $(RectText $f)"
      $o = SplitOthers $got $fz '1001'
      Check "L1 split ${set}: the other $($o.n) frozen windows keep their rects" $o.same "differ: $($o.bad -join ', ')"
      SplitOpenHalf 'L1 split' $set $got $fz $k $f '2' $false
    }
  }
  Case 'L1 span, horizontal: the solo chrome pin spans both halves of slot 1 and keeps its rect; 1001 keeps the left half of slot 2' {
    foreach ($set in $splitSets) {
      $fz = SplitFrozen $set 'solo'; $snap = ConvertTo-Json -Depth 6 -Compress $sets[$set]
      $s = GoldenCopy 'solo'
      Check "L1 span ${set}: scope, the solo starter has one wide pin, for chrome" ([bool](@($s.pins).Count -eq 1 -and [string]$s.pins[0].app -ceq 'chrome' -and [string]$s.pins[0].mon -ceq 'wide')) "pins: $(@($s.pins).Count)"
      SetProp $s.grids.wide 'mult' @(2, 1)
      SetProp $s.fill 'unit' @(2, 1)
      $s.pins[0].slots = @(0, 1)
      $s.pins = @($s.pins) + [pscustomobject]@{ app = 'claude'; match = 'Refactor the grid solver'; mon = 'wide'; slots = @(2) }
      $got = SplitPlaced (GoldenRunPosted (GoldenPosted $s) $snap "span solo $set")
      $f7 = $fz['1007']; $f1 = $fz['1001']; $k7 = $got['1007']; $k1 = $got['1001']
      Check "L1 span ${set}: scope, the frozen solo has chrome 1007 in slot 1 and 1001 in slot 2" ([bool]($f7 -and $f1 -and (@($f7.slots) -join '+') -ceq '1' -and (@($f1.slots) -join '+') -ceq '2')) "frozen: $(RectText $f7) | $(RectText $f1)"
      Check "L1 span ${set}: chrome 1007 spans both halves of slot 1 and keeps its frozen rect" (SameRect $k7 $f7) "now $(RectText $k7), frozen $(RectText $f7)"
      Check "L1 split ${set}: 1001 keeps the left half of slot 2 (same x, y and height, narrower)" ([bool]($f1 -and $k1 -and [int]$k1.x -eq [int]$f1.x -and [int]$k1.y -eq [int]$f1.y -and [int]$k1.h -eq [int]$f1.h -and [int]$k1.w -gt 0 -and [int]$k1.w -lt [int]$f1.w)) "now $(RectText $k1), frozen $(RectText $f1)"
    }
  }
  Case 'L1 split, stacked: default 5x2 becomes 5x4; 1001 keeps the top half of slot 1; every other frozen window keeps its rect' {
    foreach ($set in $splitSets) {
      $fz = SplitFrozen $set 'default'; $snap = ConvertTo-Json -Depth 6 -Compress $sets[$set]
      $s = GoldenCopy 'default'
      SetProp $s.grids.wide 'mult' @(1, 2)
      SetProp $s.fill 'unit' @(1, 2)
      $s.pins = @($s.pins) + [pscustomobject]@{ app = 'claude'; match = 'Refactor the grid solver'; mon = 'wide'; slots = @(0) }
      $got = SplitPlaced (GoldenRunPosted (GoldenPosted $s) $snap "split stacked $set")
      $f = $fz['1001']; $k = $got['1001']
      Check "L1 split stacked ${set}: scope, the frozen default places 1001 in wide slot 1" ([bool]($f -and [string]$f.mon -ceq 'wide' -and (@($f.slots) -join '+') -ceq '1')) "frozen: $(RectText $f)"
      Check "L1 split stacked ${set}: 1001 keeps the top half of slot 1 (same x, y and width, shorter)" ([bool]($f -and $k -and [int]$k.x -eq [int]$f.x -and [int]$k.y -eq [int]$f.y -and [int]$k.w -eq [int]$f.w -and [int]$k.h -gt 0 -and [int]$k.h -lt [int]$f.h)) "now $(RectText $k), frozen $(RectText $f)"
      $o = SplitOthers $got $fz '1001'
      Check "L1 split stacked ${set}: the other $($o.n) frozen windows keep their rects" $o.same "differ: $($o.bad -join ', ')"
      SplitOpenHalf 'L1 split stacked' $set $got $fz $k $f '6' $true
    }
  }

  # ---- L3 (free areas, plan layout-free-build, item 24): each frozen placement of a starter's wide grid, rebuilt as an area of that grid, lands on
  # its frozen rect. An area is the cells one window covers, as fractions of the work area, cut the way L0 cuts (a cell is int(W / c) wide, so the
  # last edge sits at c cells, not at W: on 4096 wide, five columns end at 4095). The starter's wide pins, zones and fill are dropped, since the areas
  # place the wide windows; its tall and laptop parts stay, so every frozen placement is checked.
  function L3Areas($mon, [int]$c, [int]$r, $placed) {
    $cw = [int]($mon.w / $c); $ch = [int]($mon.h / $r)
    foreach ($p in @($placed)) {
      $cols = @(); $rows = @()
      foreach ($s in @($p.slots)) { $s0 = [int]$s - 1; $cols += ($s0 % $c); $rows += [int][Math]::Floor($s0 / $c) }
      $c0 = [int](($cols | Measure-Object -Minimum).Minimum); $c1 = [int](($cols | Measure-Object -Maximum).Maximum)
      $r0 = [int](($rows | Measure-Object -Minimum).Minimum); $r1 = [int](($rows | Measure-Object -Maximum).Maximum)
      $x0 = $c0 * $cw; $x1 = ($c1 + 1) * $cw; $y0 = $r0 * $ch; $y1 = ($r1 + 1) * $ch
      $win = @($fx.windows | ? { [int64]$_.id -eq [int64]$p.id })[0]
      [pscustomobject]@{ rect = @(($x0 / $mon.w), ($y0 / $mon.h), (($x1 - $x0) / $mon.w), (($y1 - $y0) / $mon.h)); app = [string]$win.app; title = [string]$win.title }
    }
  }
  foreach ($set in @('1365x1001', '3440x1392', '1080x1872', 'fixture')) {
    $gold = ConvertFrom-Json ([IO.File]::ReadAllText((Join-Path $goldenDir "$set.json"), $utf8))
    $wideMon = @($sets[$set].monitors | ? { $_.role -eq 'wide' })[0]
    foreach ($id in $ids) {
      $fz = $gold.scenes.PSObject.Properties[$id]; if ($null -eq $fz) { continue }
      $frozen = @($fz.Value.placed); $onWide = @($frozen | ? { $_.mon -eq 'wide' })
      Case "L3 areas ${set} ${id}: every frozen placement, rebuilt as an area of its grid, lands on its frozen rect" {
        Check "L3 areas ${set} ${id}: scope, the frozen entry places windows on the wide grid" ($onWide.Count -gt 0) "no wide placement in golden/$set.json"
        $s = GoldenCopy $id; $gr = $s.grids.wide
        $areas = @(L3Areas $wideMon ([int]$gr.c) ([int]$gr.r) $onWide)
        SetProp $s.grids 'wide' ([pscustomobject]@{ c = [int]$gr.c; r = [int]$gr.r; free = [pscustomobject]@{ areas = $areas } })
        SetProp $s 'pins' @(@($s.pins) | ? { $_.mon -ne 'wide' }); SetProp $s 'zones' @(@($s.zones) | ? { $_ -and $_.mon -ne 'wide' })
        if ($s.fill.mon -eq 'wide') { SetProp $s 'fill' ([pscustomobject]@{ mon = 'wide'; apps = @(); skip = @(); sort = 'app' }) }
        $got = GoldenRunPosted (GoldenPosted $s) (ConvertTo-Json -Depth 6 -Compress $sets[$set]) "L3 $set $id"
        $byId = @{}; foreach ($p in @($got.placed)) { $byId["$([int64]$p.id)"] = $p }
        $bad = @(foreach ($p in $frozen) { $q = $byId["$([int64]$p.id)"]; if (-not ($q -and [string]$q.mon -ceq [string]$p.mon -and (SameRect $q $p))) { "$($p.id) $($p.mon) frozen $(RectText $p), now $(if ($q) { "$($q.mon) $(RectText $q)" } else { 'not placed' })" } })
        Check "L3 areas ${set} ${id}: the placed windows match the frozen layout (rect and monitor)" ($bad.Count -eq 0 -and @($got.placed).Count -eq $frozen.Count) "$($bad.Count) differ; placed $(@($got.placed).Count), frozen $($frozen.Count): $(@($bad | Select-Object -First 3) -join ' | ')"
      }
    }
  }

  # Page: headless Edge over DevTools, as bay.ps1 drives it. cellRect is a global; the page is asked for it directly.
  $edgeExe = @("${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe", "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe") | ? { Test-Path -LiteralPath $_ } | Select-Object -First 1
  if (-not $edgeExe) { 'SKIP  page check: Microsoft Edge not found in either Program Files folder.' } else {
    function GoldenSend($method, $params) {
      $script:cdpId++; $id = $script:cdpId
      $bytes = $utf8.GetBytes((@{ id = $id; method = $method; params = $params } | ConvertTo-Json -Depth 12 -Compress))
      $st = $script:ws.SendAsync([ArraySegment[byte]]::new($bytes), [Net.WebSockets.WebSocketMessageType]::Text, $true, [Threading.CancellationToken]::None)
      try { if (-not $st.Wait(30000)) { throw "DevTools send timed out: $method" } } catch { throw "DevTools send failed ($method): $($_.Exception.GetBaseException().Message)" }
      while ($true) {
        $ms = New-Object IO.MemoryStream
        do {
          $buf = New-Object byte[] 262144
          $t = $script:ws.ReceiveAsync([ArraySegment[byte]]::new($buf, 0, $buf.Length), [Threading.CancellationToken]::None)
          try { if (-not $t.Wait(90000)) { throw "DevTools reply timed out: $method" } } catch { throw "DevTools receive failed ($method): $($_.Exception.GetBaseException().Message)" }
          $ms.Write($buf, 0, $t.Result.Count); $eom = $t.Result.EndOfMessage
        } while (-not $eom)
        $o = [Text.Encoding]::UTF8.GetString($ms.ToArray()) | ConvertFrom-Json
        if ($o.id -eq $id) { if ($o.error) { throw "DevTools $method`: $($o.error.message)" }; return $o }
      }
    }
    function GoldenJs($expr) {
      $r = GoldenSend 'Runtime.evaluate' @{ expression = $expr; returnByValue = $true; awaitPromise = $true }
      if ($r.result.exceptionDetails) { $script:jsErr = "$($r.result.exceptionDetails.exception.description)"; return $null }
      $r.result.result.value
    }
    function GoldenStartBrowser {
      New-Item -ItemType Directory -Force $script:udd | Out-Null
      $edgeArgs = @('--headless', '--disable-gpu', '--no-first-run', '--remote-debugging-port=0', "--user-data-dir=$($script:udd)", '--window-size=1440,900', '--host-resolver-rules="MAP fonts.googleapis.com 0.0.0.0, MAP fonts.gstatic.com 0.0.0.0"', 'about:blank')
      # Edge starts with the real user folders: under a temp USERPROFILE it never opens its DevTools port. Its data goes to the run folder.
      $keepUser = $env:USERPROFILE; $keepApp = $env:APPDATA
      $env:USERPROFILE = [Environment]::GetFolderPath('UserProfile'); $env:APPDATA = [Environment]::GetFolderPath('ApplicationData')
      try { $proc = Start-Process $edgeExe -PassThru -WindowStyle Hidden -ArgumentList $edgeArgs } finally { $env:USERPROFILE = $keepUser; $env:APPDATA = $keepApp }
      $dt = Join-Path $script:udd 'DevToolsActivePort'; $deadline = (Get-Date).AddSeconds(30)
      while (-not (Test-Path -LiteralPath $dt)) { if ((Get-Date) -gt $deadline) { throw 'Edge did not open its DevTools port' }; Start-Sleep -Milliseconds 100 }
      $port = (Get-Content -LiteralPath $dt)[0]
      $page = $null
      while (-not $page) {
        try { $targets = Invoke-RestMethod "http://127.0.0.1:$port/json/list" } catch { $targets = @() }
        $pages = @($targets | ? { $_.type -eq 'page' -and $_.webSocketDebuggerUrl })
        if ($pages.Count) { $page = $pages[0] } else { Start-Sleep -Milliseconds 100 }
        if (-not $page -and (Get-Date) -gt $deadline) { throw 'Edge has no page target' }
      }
      $script:ws = New-Object Net.WebSockets.ClientWebSocket
      $ct = $script:ws.ConnectAsync([Uri]([string]$page.webSocketDebuggerUrl), [Threading.CancellationToken]::None)
      try { if (-not $ct.Wait(30000)) { throw 'DevTools connect timed out' } } catch { throw "DevTools connect failed: $($_.Exception.GetBaseException().Message)" }
      $proc
    }
    # One cell job per placed window: the cell span its slots cover on the grid its monitor role used, and the frozen rect.
    function GoldenCellJobs($set, $gold) {
      $sn = $sets[$set]; $jobs = @()
      foreach ($id in $ids) {
        $fz = $gold.scenes.PSObject.Properties[$id]; if ($null -eq $fz) { continue }
        foreach ($p in @($fz.Value.placed)) {
          $mon = @($sn.monitors | ? { $_.role -eq $p.mon })[0]
          $grid = $fz.Value.grids.PSObject.Properties[$p.mon].Value
          $c = [int]$grid.c; $cols = @(); $rows = @()
          foreach ($s in @($p.slots)) { $s0 = [int]$s - 1; $cols += ($s0 % $c); $rows += [Math]::Floor($s0 / $c) }
          $c0 = ($cols | Measure-Object -Minimum).Minimum; $r0 = ($rows | Measure-Object -Minimum).Minimum
          $jobs += @{ scene = $id; id = [int64]$p.id; m = @{ x = $mon.x; y = $mon.y; w = $mon.w; h = $mon.h }; g = @{ c = $c; r = [int]$grid.r }
            c0 = $c0; r0 = $r0; cs = ($cols | Measure-Object -Maximum).Maximum - $c0 + 1; rs = ($rows | Measure-Object -Maximum).Maximum - $r0 + 1
            want = "$([int]$p.x),$([int]$p.y),$([int]$p.w),$([int]$p.h)" }
        }
      }
      $jobs
    }
    $srv = $null; $total = 0; $bad = @()
    try {
      $snapPath = Join-Path $run 'page-snap.json'; [IO.File]::WriteAllText($snapPath, (ConvertTo-Json -Depth 6 -Compress $sets['1365x1001']), $utf8)
      $psi = New-Object Diagnostics.ProcessStartInfo 'powershell', "-NoProfile -ExecutionPolicy Bypass -File `"$serve`" -NoBrowser -From `"$snapPath`""
      $psi.UseShellExecute = $false; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true; $psi.CreateNoWindow = $true
      $psi.EnvironmentVariables['USERPROFILE'] = $script:userDir; $psi.EnvironmentVariables['APPDATA'] = Join-Path $script:userDir 'AppData\Roaming'; $psi.EnvironmentVariables['TILE_HOME'] = Join-Path $run 'page-home'
      $sp = [Diagnostics.Process]::Start($psi)
      $line = $sp.StandardOutput.ReadLineAsync(); if (-not $line.Wait(60000)) { throw 'the server did not print its URL' }
      $srv = @($sp, $line.Result)
      [void](GoldenStartBrowser)
      [void](GoldenSend 'Page.navigate' @{ url = $srv[1] })
      $ready = GoldenJs "new Promise((res, rej) => { const t0 = Date.now(); (function poll() { if (typeof cellRect === 'function') return res(true); if (Date.now() - t0 > 30000) return rej(new Error('no cellRect after 30 s')); setTimeout(poll, 100); })(); })"
      if (-not $ready) { throw "the page has no cellRect: $script:jsErr" }
      foreach ($set in $sets.Keys) {
        $file = Join-Path $goldenDir "$set.json"
        if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { continue }  # reported above
        $jobs = @(GoldenCellJobs $set (ConvertFrom-Json ([IO.File]::ReadAllText($file, $utf8))))
        $total += $jobs.Count
        if ($jobs.Count -eq 0) { continue }
        $json = ConvertTo-Json -InputObject @($jobs) -Depth 5 -Compress
        # One string back, joined by '|': a JSON array would come back from ConvertFrom-Json as one object in Windows PowerShell.
        $raw = GoldenJs "(($json).map(j => { try { const r = cellRect(j.m, j.g, j.c0, j.r0, j.cs, j.rs); return [r.x, r.y, r.w, r.h].join(','); } catch (e) { return 'error: ' + e.message; } })).join('|')"
        if ($null -eq $raw) { throw "the page did not evaluate cellRect: $script:jsErr" }
        $got = @($raw -split '\|')
        for ($i = 0; $i -lt $jobs.Count; $i++) {
          if ($got[$i] -cne $jobs[$i].want) { $bad += "$set $($jobs[$i].scene) window $($jobs[$i].id): frozen $($jobs[$i].want), page $($got[$i])" }
        }
      }
      Check 'page check: the frozen layouts give placed windows cell spans to check' ($total -gt 0) 'no placed window in any frozen file'
      Check 'page check: cellRect gives every placed window its frozen rect, on every set' ($total -gt 0 -and $bad.Count -eq 0) ("$($bad.Count) of $total differ: " + (@($bad | Select-Object -First 3) -join ' | '))
    } catch {
      $script:fail++; "FAIL  page check stopped: $_"
    } finally {
      if ($srv) { try { [void](Invoke-WebRequest -UseBasicParsing "$($srv[1])quit" -Method Post -Body 'quit') } catch {}; if (-not $srv[0].WaitForExit(5000)) { $srv[0].Kill() } }
      try { Get-CimInstance Win32_Process -Filter "Name='msedge.exe'" | ? { $_.CommandLine -like "*$($script:udd)*" } | % { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue } } catch {}
    }
  }
} catch {
  $script:fail++; "FAIL  run stopped: $_"
} finally {
  foreach ($k in $savedEnv.Keys) { if ($null -eq $savedEnv[$k]) { Remove-Item "env:$k" -ErrorAction SilentlyContinue } else { Set-Item "env:$k" $savedEnv[$k] } }
  Remove-Item -LiteralPath $run -Recurse -Force -ErrorAction SilentlyContinue
}
if ($script:fail) { "$($script:fail) check(s) failed."; exit 1 } else { exit 0 }
