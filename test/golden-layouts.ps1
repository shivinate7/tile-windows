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
# removes sibling run folders older than a day and keeps newer ones. This file keeps its own copy of the sweep, as bay.ps1 does,
# so each file runs alone. The sweep takes its clock as a parameter: the proof below passes a fixed one.
$GoldenTempRoot = Join-Path $env:TEMP 'tile-windows-test-runs'
$GoldenRunName = '^\d+-[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
function GoldenSweep($dir, $olderThan, $now) {
  if (-not (Test-Path -LiteralPath $dir)) { return }
  @(Get-ChildItem -LiteralPath $dir -Directory | ? { $_.Name -match $GoldenRunName -and $_.LastWriteTime -lt $now.Subtract($olderThan) }) | % { Remove-Item -LiteralPath $_.FullName -Recurse -Force }
}
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
  # A starter as the page sends it: the scene plus the category map (the same as -Scene <name> resolves from scenes.json).
  function GoldenStarter($id) { $s = @($starters.scenes | ? { $_.id -eq $id })[0]; $s | Add-Member -Force cats $starters.cats; $s | Add-Member -Force categories $starters.categories; ConvertTo-Json -Depth 10 -Compress $s }
  function GoldenRun($id, $snapJson) {
    $raw = (& $tile -Scene (GoldenStarter $id) -From $snapJson -Json 3>$null) -join ''
    if (-not $raw) { throw "tile.ps1 printed nothing for $id" }
    ConvertFrom-Json $raw
  }
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
