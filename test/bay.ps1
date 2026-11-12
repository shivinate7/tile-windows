# Checks for the Windows That Stay Put list (decision bay-list): Flowing Columns, and Reason Said Once. Page cases only:
# headless Edge over DevTools, on a dry-run server (nothing moves). Each set loads a snapshot (23 windows, 6 windows, or
# an empty bay), presses Show N More so every window shows, and reads the list's boxes back. The engine case reads the
# snapshot's reasons first, so a fixture mistake cannot pass for a product failure. Scope comes before subject (P7): a
# case reads a split column, or a shared reason, only after it has checked that one exists.
# Run alone: powershell -NoProfile -ExecutionPolicy Bypass -File test\bay.ps1
# test\run.ps1 runs this file in a child powershell and counts its FAIL lines.
#
# Interface the builder must meet (what these cases read):
#   List body: #bgrps, as today. Each window is a button.chip with data-bay=<window id> and class cat-<c> on the button.
#     Its label: <b> (app), <span> (title), and a <small> with its reason, unless the reason is shared (see below).
#   Column: the chips that share a left edge (within 2px). Columns read left to right; within one, top to bottom.
#     K = floor((list width + 12) / 182) is the auto-fill count at 170px with a 12px gap. With 23 windows the list has
#     exactly K columns: four at 1440 (863px wide), three at 1024 (the list is narrower than four columns there).
#   Category heading: an h3 inside #bgrps. Its category is the nearest class cat-<c> on it or an ancestor, so today's
#     .bgrp wrapper counts. Its text holds the category name and, when the category shares a reason, that reason once.
#   Continuation rule: an element with classes cont and cat-<c> inside #bgrps, at the top of a column that opens partway
#     through category c. Its left edge is the column's, it sits above that column's first chip, it is 4px tall or less, and
#     its background is that chip's border-left colour.
#   Reason Said Once (on by default, no setting): the shared reason of a category is the reason more than half the windows
#     the list shows share (coordinator ruling, 2026-11-12 14:06 CST). Capped ("Show N More"), only the visible windows count.
#     A window with no reason line ("Not in this scene") counts as not sharing and shows no line, as on main. The shared reason
#     shows once in the category's heading, on the heading's own row, after the name. Chips with it have no <small> (an empty
#     one counts as none). A chip with another reason keeps its <small>. A category with no shared reason keeps every <small>.
#   Packed target: not in the DOM. The packed-height checks read its consequence: no column stops short of its next unit when
#     that unit would still end within the list's height (each rule's full box counted).
#   Height: the list's content (top of the first item to the bottom of the last) is shorter than today's list at the same
#     width. Today's list is one column per category at the auto-fill track width, each chip with its reason line. This
#     file builds that list in the page (probe) from the chips' own app and title text, so the reason lines count as today.
#   Names the harness reads (keep them): snap, selId, prevs, preview(id), and the Show N More button with id baymore.
#   Do not put class flow on #bay for the new layout: layout() toggles .bay.flow for the board's height.
#
# Run folders (test-temp-standard): one folder per run, <pid>-<UUID>, under one temp root per repo. The first request of a run
# removes sibling run folders older than a day and keeps newer ones. This file keeps its own copy of the sweep and of the
# headless-Edge helpers that stack-lock.ps1 has, because the fill-keep branch edits stack-lock.ps1 (see the commit message).
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
$tile = Join-Path $root 'tile.ps1'; $serve = Join-Path $root 'serve.ps1'; $fixture = Join-Path $PSScriptRoot 'fixture.json'
$utf8 = New-Object Text.UTF8Encoding $false
$script:fail = 0
function Check($name, $ok, $detail = '') { if ($ok) { "PASS  $name" } else { $script:fail++; "FAIL  $name  $detail" } }

$BayTempRoot = Join-Path $env:TEMP 'tile-windows-test-runs'
$BayRunName = '^\d+-[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
function BaySweep($dir, $olderThan) {
  if (-not (Test-Path -LiteralPath $dir)) { return }
  @(Get-ChildItem -LiteralPath $dir -Directory | ? { $_.Name -match $BayRunName -and $_.LastWriteTime -lt (Get-Date).Subtract($olderThan) }) | % { Remove-Item -LiteralPath $_.FullName -Recurse -Force }
}
[void](New-Item -ItemType Directory -Force $BayTempRoot)
BaySweep $BayTempRoot ([TimeSpan]::FromDays(1))
$run = Join-Path $BayTempRoot ("$PID-" + [guid]::NewGuid().ToString()); New-Item -ItemType Directory $run | Out-Null
# The sweep, proven inside this run's folder: an old run folder goes, a new one stays.
$proof = Join-Path $run 'sweep-proof'; New-Item -ItemType Directory $proof | Out-Null
$oldRun = Join-Path $proof ('1-' + [guid]::NewGuid().ToString()); $newRun = Join-Path $proof ('2-' + [guid]::NewGuid().ToString())
New-Item -ItemType Directory $oldRun | Out-Null; New-Item -ItemType Directory $newRun | Out-Null
(Get-Item -LiteralPath $oldRun).LastWriteTime = (Get-Date).AddDays(-2)
BaySweep $proof ([TimeSpan]::FromDays(1))
Check 'run folders: the sweep removes a run folder older than a day' (-not (Test-Path -LiteralPath $oldRun))
Check 'run folders: the sweep keeps a run folder newer than a day' (Test-Path -LiteralPath $newRun)

# Every path below comes from this run folder, never from the system temp folder directly.
$script:userDir = Join-Path $run 'profile'; New-Item -ItemType Directory -Force (Join-Path $script:userDir 'AppData\Roaming') | Out-Null
$savedEnv = @{ TILE_HOME = $env:TILE_HOME }
$env:TILE_HOME = Join-Path $run 'home'

# ---------- The windows: the owner's screenshot counts (Code 10, Browse 2, Other 11) and the 6-window set ----------
# Row: app, title, minimized (1 or 0). Category: claude and WindowsTerminal are code, chrome is browse, all else is other.
function BayCatOf($app) { if ($app -in 'claude', 'WindowsTerminal') { 'code' } elseif ($app -eq 'chrome') { 'browse' } else { 'other' } }
$BayCatName = @{ code = 'Code'; browse = 'Browse'; other = 'Other' }
$BayReason = @{ fill = 'Fill is off'; min = 'Minimized: it stays minimized' }
$BayRows23 = @(
  @('claude', 'Refactor the grid solver', 0), @('claude', 'Batch runner notes', 0), @('claude', 'Triage the open items', 0),
  @('claude', 'Retrospective draft', 0), @('claude', 'Settings cleanup', 0), @('claude', 'Build the report sheet', 0),
  @('claude', 'Hook timing review', 0), @('claude', 'Board resize handles', 0), @('WindowsTerminal', 'pwsh - tiler', 1),
  @('claude', 'Voice macros', 0), @('chrome', 'Tile Windows - Docs', 0), @('chrome', 'Quarterly roadmap', 1),
  @('explorer', 'Projects', 1), @('excel', 'Budget FY27.xlsx', 1), @('stickynotes', 'Sticky Notes', 0), @('winsettings', 'Settings', 1),
  @('stickynotes', 'Sticky Notes', 0), @('stickynotes', 'Sticky Notes', 0), @('stickynotes', 'Sticky Notes', 0), @('devicehelper', 'Device Helper', 1),
  @('stickynotes', 'Sticky Notes', 0), @('stickynotes', 'Sticky Notes', 0), @('calendar', 'Calendar', 1))
$BayRows6 = @(
  @('claude', 'Refactor the grid solver', 0), @('claude', 'Voice macros', 0), @('WindowsTerminal', 'pwsh - tiler', 1),
  @('chrome', 'Quarterly roadmap', 1), @('excel', 'Budget FY27.xlsx', 1), @('stickynotes', 'Sticky Notes', 0))
$BayRowsEmpty = @(@('claude', 'Refactor the grid solver', 0), @('chrome', 'Tile Windows - Docs', 0))
function BayWins($rows) {
  $i = 0
  foreach ($r in $rows) { $i++; $min = [bool]$r[2]
    [pscustomobject]@{ id = 2000 + $i; app = $r[0]; title = $r[1]; min = $min; cat = (BayCatOf $r[0]); reason = $(if ($min) { 'min' } else { 'fill' }) } }
}
# A snapshot file in the run folder: the fixture's monitors, and these windows. Minimized windows sit off screen, as the fixture's do.
function BaySnapFile($path, $wins) {
  $fx = [IO.File]::ReadAllText($fixture, $utf8) | ConvertFrom-Json
  $sw = foreach ($w in $wins) {
    if ($w.min) { [ordered]@{ id = $w.id; app = $w.app; title = $w.title; x = -25600; y = -25600; w = 160; h = 28; min = $true } }
    else { [ordered]@{ id = $w.id; app = $w.app; title = $w.title; x = 100 + 700 * ($w.id % 4); y = 80 + 200 * ($w.id % 3); w = 600; h = 400 } }
  }
  [IO.File]::WriteAllText($path, (ConvertTo-Json -Depth 6 -Compress -InputObject ([ordered]@{ monitors = $fx.monitors; windows = @($sw) })), $utf8)
}
# Scenes: fill off puts every window in the list ('fill is off'); fill on places the windows that fit.
$BaySceneFillOff = '{"id":"bay","name":"Bay list","trigger":{"type":"manual","days":[],"time":"09:00"},"grids":{"wide":{"c":5,"r":2}},"pins":[],"fill":{"mon":"wide","apps":["*"],"skip":[],"sort":"app","off":true}}'
$BaySceneFillOn = '{"id":"bay","name":"Bay list","trigger":{"type":"manual","days":[],"time":"09:00"},"grids":{"wide":{"c":5,"r":2}},"pins":[],"fill":{"mon":"wide","apps":["*"],"skip":[],"sort":"app"}}'
$wins23 = BayWins $BayRows23; $wins6 = BayWins $BayRows6; $winsEmpty = BayWins $BayRowsEmpty
$snap23 = Join-Path $run 'bay23.json'; $snap6 = Join-Path $run 'bay6.json'; $snapEmpty = Join-Path $run 'bay-empty.json'
BaySnapFile $snap23 $wins23; BaySnapFile $snap6 $wins6; BaySnapFile $snapEmpty $winsEmpty
# Mixed: three Other windows that Fill is off lists, and one PowerToys window, which the engine skips (it is in no reason's list): "Not in this scene".
$BayRowsNone = @(@('stickynotes', 'Sticky Notes', 0), @('stickynotes', 'Sticky Notes', 0), @('stickynotes', 'Sticky Notes', 0), @('PowerToys', 'Settings', 0))
$winsNone = BayWins $BayRowsNone; $winsNone[3].reason = 'none'
$snapNone = Join-Path $run 'bay-none.json'; BaySnapFile $snapNone $winsNone

# ---------- Engine: scope for the page cases (no page, no move) ----------
$eng = (& $tile -Scene $BaySceneFillOff -From $snap23 -DryRun -Json 3>$null) -join '' | ConvertFrom-Json
$engFill = @(@($eng.left) | ? { $_.why -eq 'fill is off' })
$engFillIds = (@($engFill | % { [int]$_.id }) | Sort-Object) -join ','
$wantFillIds = (@($wins23 | ? { -not $_.min } | % { $_.id }) | Sort-Object) -join ','
Check 'bay: the engine lists each non-minimized window as fill is off (scope for the page cases)' ($engFillIds -eq $wantFillIds) "got $engFillIds"

# ---------- Page: headless Edge over DevTools ----------
$edgeExe = @("${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe", "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe") | ? { Test-Path -LiteralPath $_ } | Select-Object -First 1
if (-not $edgeExe) { 'SKIP  page cases: Microsoft Edge not found in either Program Files folder.'; if ($script:fail) { "$($script:fail) check(s) failed."; exit 1 } else { exit 0 } }

$script:udd = Join-Path $run 'edge'; $script:ws = $null; $script:cdpId = 0; $script:url = ''
function BaySend($method, $params) {
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
# Runs JS in the page. A promise is awaited in the page, so waits inside the page are bounded there.
function BayJs($expr) {
  $r = BaySend 'Runtime.evaluate' @{ expression = $expr; returnByValue = $true; awaitPromise = $true }
  if ($r.result.exceptionDetails) { $script:jsErr = "$($r.result.exceptionDetails.exception.description)"; return $null }
  $r.result.result.value
}
function BayGet($expr) { $s = BayJs ('JSON.stringify(' + $expr + ')'); if ($s) { $s | ConvertFrom-Json } }
function BayViewport($w, $h) { [void](BaySend 'Emulation.setDeviceMetricsOverride' @{ width = $w; height = $h; deviceScaleFactor = 1; mobile = $false }) }
# After a change: the preview has come back and the list has finished any CSS transition.
function BaySettle { [void](BayJs "preview(selId).then(() => Promise.all(document.getAnimations().filter(a => { const t = a.effect && a.effect.getComputedTiming(); return !t || t.iterations !== Infinity; }).map(a => a.finished.catch(() => null))))") }
function BayStartBrowser {
  New-Item -ItemType Directory -Force $script:udd | Out-Null
  $edgeArgs = @('--headless', '--disable-gpu', '--no-first-run', '--remote-debugging-port=0', "--user-data-dir=$($script:udd)", '--window-size=1440,900', '--host-resolver-rules="MAP fonts.googleapis.com 0.0.0.0, MAP fonts.gstatic.com 0.0.0.0"', 'about:blank')
  # Edge starts with the real user folders (under a temp USERPROFILE it never opens its DevTools port). Its data goes to the run folder.
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
# A dry-run server on one snapshot, with its own scenes folder in the run folder. Returns the process and its tokened URL.
function BayStartServer($snapPath, $homeDir) {
  $psi = New-Object Diagnostics.ProcessStartInfo 'powershell', "-NoProfile -ExecutionPolicy Bypass -File `"$serve`" -NoBrowser -From `"$snapPath`""
  $psi.UseShellExecute = $false; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true; $psi.CreateNoWindow = $true
  $psi.EnvironmentVariables['USERPROFILE'] = $script:userDir; $psi.EnvironmentVariables['APPDATA'] = Join-Path $script:userDir 'AppData\Roaming'; $psi.EnvironmentVariables['TILE_HOME'] = $homeDir
  $p = [Diagnostics.Process]::Start($psi)
  $line = $p.StandardOutput.ReadLineAsync(); if (-not $line.Wait(60000)) { throw 'the server did not print its URL' }
  @($p, $line.Result)
}
function BayStopServer($srv) {
  if (-not $srv) { return }
  try { [void](Invoke-WebRequest -UseBasicParsing "$($srv[1])quit" -Method Post -Body 'quit') } catch {}
  if (-not $srv[0].WaitForExit(5000)) { $srv[0].Kill() }
}
# Sets the server's config to one scene (id bay), as the page sends it.
function BayConfigScene($url, $sceneJson) {
  $cfg = (Invoke-WebRequest -UseBasicParsing "${url}config").Content | ConvertFrom-Json
  $cfg.scenes = @((ConvertFrom-Json $sceneJson))
  $body = ConvertTo-Json -Depth 12 -Compress $cfg
  if ((Invoke-WebRequest -UseBasicParsing "${url}config" -Method Post -ContentType 'application/json; charset=utf-8' -Body ($utf8.GetBytes($body))).Content -ne 'Saved') { throw 'the config was not saved' }
}
# Loads (or reloads) the page, and waits in the page until the scene is drawn.
function BayLoad($url) {
  $before = BayJs 'String(performance.timeOrigin)'
  [void](BaySend 'Page.navigate' @{ url = $url })
  $ready = $null; $tries = 0
  while (-not $ready -and $tries -lt 3) {
    $tries++
    $ready = BayJs "new Promise((res, rej) => { const t0 = Date.now(); (function poll() { if (String(performance.timeOrigin) !== '$before' && typeof snap === 'object' && snap && selId && prevs[selId] && document.querySelectorAll('.tile').length) return res(true); if (Date.now() - t0 > 30000) return rej(new Error('no scene after 30 s')); setTimeout(poll, 100); })(); })"
  }
  if (-not $ready) { throw "the page did not draw the scene: $script:jsErr" }
  BaySettle
}
# Presses Show N More, when it is shown, so every window is in the list. Show Fewer is left alone.
function BayShowAll {
  [void](BayJs "(() => { const b = document.getElementById('baymore'); if (b && !b.hidden && /^Show \d+ More$/.test(b.textContent.trim())) b.click(); return true; })()")
  BaySettle
}

# The list as the page draws it. Chips, headings and rules are read in the page's own coordinates. The probe builds today's
# list at this width (one column per category, auto-fill tracks, each chip with its reason line) from the chips' app and
# title text, so the baseline follows the chips' text. Today's CSS for the probe is copied from the page's .bgrp rules.
$BayMeasureJs = @'
(() => {
  const list = document.getElementById('bgrps');
  const catOf = el => { const m = (el.getAttribute('class') || '').match(/(?:^|\s)cat-([a-z]+)/); return m ? m[1] : null; };
  const box = el => { const r = el.getBoundingClientRect(); return { l: r.left, t: r.top, r: r.right, b: r.bottom, w: r.width, h: r.height }; };
  const chips = [...list.querySelectorAll('[data-bay]')].map(el => {
    const li = el.closest('li'), s = el.querySelector('small'), b = box(el);
    return { id: +el.dataset.bay, cat: catOf(el), l: b.l, t: b.t, r: b.r, bt: b.b, w: b.w, h: b.h,
      hidden: !!(li && li.hidden) || b.w === 0 || b.h === 0, small: s ? s.textContent.trim() : null,
      edge: getComputedStyle(el).borderLeftColor,
      app: (el.querySelector('b') || {}).textContent || '', title: (el.querySelector('span') || {}).textContent || '' };
  });
  const heads = [...list.querySelectorAll('h3')].map(h => {
    const owner = h.closest('[class*="cat-"]'), b = box(h);
    return { cat: owner ? catOf(owner) : null, text: h.textContent.replace(/\s+/g, ' ').trim(), l: b.l, t: b.t };
  });
  const rules = [...list.querySelectorAll('.cont')].map(el => { const b = box(el); return { cat: catOf(el), l: b.l, t: b.t, h: b.h, bg: getComputedStyle(el).backgroundColor }; });
  let top = Infinity, bottom = -Infinity;
  for (const el of list.querySelectorAll('*')) { const r = el.getBoundingClientRect(); if (r.width && r.height) { top = Math.min(top, r.top); bottom = Math.max(bottom, r.bottom); } }
  const L = box(list), W = L.w, spec = __SPEC__;
  const K = Math.max(1, Math.floor((W + 12) / 182));
  const probe = document.createElement('div');
  probe.style.cssText = `position:absolute;visibility:hidden;left:0;top:0;width:${W}px;display:grid;grid-template-columns:repeat(${K},minmax(170px,1fr));gap:8px 12px`;
  for (const cat of [...new Set(spec.map(s => s.cat))]) {
    const block = document.createElement('div'), h = document.createElement('h3'), ul = document.createElement('ul');
    h.style.cssText = 'display:flex;gap:6px;align-items:center;margin:0 0 4px;font:600 11px var(--f);text-transform:uppercase;letter-spacing:.08em;color:var(--muted)';
    h.appendChild(Object.assign(document.createElement('i'), { className: 'sw' }));
    h.appendChild(document.createTextNode(spec.find(s => s.cat === cat).name));
    ul.style.cssText = 'list-style:none;margin:0;padding:0;display:grid;gap:4px';
    block.append(h, ul);
    for (const s of spec.filter(x => x.cat === cat)) {
      const src = chips.find(c => c.id === s.id) || {};
      const li = document.createElement('li'), btn = document.createElement('button');
      btn.type = 'button'; btn.className = 'chip cat-' + cat;
      const b = document.createElement('b'); b.textContent = src.app || '';
      const sp = document.createElement('span'); sp.textContent = src.title || '';
      const sm = document.createElement('small'); sm.textContent = s.reason;
      btn.append(b, sp, sm); li.appendChild(btn); ul.appendChild(li);
    }
    probe.appendChild(block);
  }
  document.body.appendChild(probe);
  const todayH = probe.getBoundingClientRect().height;
  probe.remove();
  return { listL: L.l, listR: L.r, listW: W, listH: L.h, K, contentH: bottom - top, todayH, chips, heads, rules, scrollW: list.scrollWidth, clientW: list.clientWidth };
})()
'@
function BayMeasure($spec) {
  $specJson = ConvertTo-Json -Compress -InputObject @($spec)
  BayGet $BayMeasureJs.Replace('__SPEC__', $specJson)
}

# ---------- Analysis: pure functions on one measurement ----------
# Columns: the chips' left edges, clustered within 2px, numbered from the left. Each chip gets its column and its category.
function BayAnalyse($m) {
  $chips = @($m.chips | ? { -not $_.hidden })
  $lefts = @($chips | ForEach-Object { [double]$_.l } | Sort-Object)
  $anchors = New-Object Collections.ArrayList
  foreach ($x in $lefts) { if ($anchors.Count -eq 0 -or $x - $anchors[$anchors.Count - 1] -gt 2) { [void]$anchors.Add($x) } }
  $items = foreach ($c in $chips) {
    $col = 0; $best = [double]::MaxValue
    for ($k = 0; $k -lt $anchors.Count; $k++) { $d = [Math]::Abs([double]$c.l - $anchors[$k]); if ($d -lt $best) { $best = $d; $col = $k } }
    [pscustomobject]@{ id = [int]$c.id; cat = $c.cat; col = $col; l = [double]$c.l; t = [double]$c.t; small = $c.small; edge = $c.edge }
  }
  [pscustomobject]@{ cols = $anchors.Count; items = @($items) }
}
function BayColsOf($items, $cat) { @($items | ? { $_.cat -eq $cat } | ForEach-Object { $_.col } | Sort-Object -Unique) }
function BayText($wins, $id) { $w = @($wins | ? { $_.id -eq $id })[0]; if ($w) { $BayReason[$w.reason] } else { '' } }
# Two boxes overlap by more than 1px in both directions.
function BayOverlaps($chips) {
  $bad = @()
  for ($i = 0; $i -lt $chips.Count; $i++) { for ($j = $i + 1; $j -lt $chips.Count; $j++) {
    $a = $chips[$i]; $b = $chips[$j]
    if ([Math]::Min($a.r, $b.r) - [Math]::Max($a.l, $b.l) -gt 1 -and [Math]::Min($a.bt, $b.bt) - [Math]::Max($a.t, $b.t) -gt 1) { $bad += "$($a.id)/$($b.id)" }
  } }
  $bad
}
# A column that opens partway through a category: its first window's category is the last one of the column before it.
function BayRuleProblems($items, $rules, $cols) {
  $problems = @()
  for ($j = 1; $j -lt $cols; $j++) {
    $colJ = @($items | ? { $_.col -eq $j } | Sort-Object t); $prev = @($items | ? { $_.col -eq ($j - 1) } | Sort-Object t)
    if (-not $colJ.Count -or -not $prev.Count) { continue }
    $first = $colJ[0]; $last = $prev[$prev.Count - 1]
    if ($first.cat -ne $last.cat) { continue }
    $name = $BayCatName[$first.cat]
    $ok = @($rules | ? { $_.cat -eq $first.cat -and [Math]::Abs($_.l - $first.l) -le 2 -and $_.t -lt $first.t -and $_.h -gt 0 -and $_.h -le 4 -and $_.bg -eq $first.edge }).Count -gt 0
    if (-not $ok) { $problems += "column $($j + 1) opens partway through $name with no $name rule of its colour above its first window" }
  }
  $problems
}
function BayLoneProblems($items, $splits) {
  $problems = @()
  foreach ($c in $splits) { foreach ($j in (BayColsOf $items $c)) {
    $n = @($items | ? { $_.cat -eq $c -and $_.col -eq $j }).Count
    if ($n -lt 2) { $problems += "column $($j + 1) holds $n $($BayCatName[$c]) window, and $($BayCatName[$c]) is split across columns" }
  } }
  $problems
}

# The list's columns as the DOM has them, shown windows only: each column's full height (its ul, which holds each rule's margins), and its
# items in order: kind (head, rule or chip), category, top within the column, height, window id, reason line and heading text.
$BayColsJs = @'
(() => {
  const list = document.getElementById('bgrps'), LR = list.getBoundingClientRect();
  const catIn = el => { const m = el && (el.getAttribute('class') || '').match(/(?:^|\s)cat-([a-z]+)/); return m ? m[1] : null; };
  const cols = [...list.children].map(ul => {
    const ur = ul.getBoundingClientRect();
    return { h: ur.height, items: [...ul.children].map(li => {
      const r = li.getBoundingClientRect(), h3 = li.querySelector('h3'), btn = li.querySelector('[data-bay]'), sm = li.querySelector('small');
      const k = li.classList.contains('cont') ? 'rule' : h3 ? 'head' : 'chip';
      return { k, cat: k === 'chip' ? catIn(btn) : catIn(k === 'rule' ? li : h3), t: +(r.top - ur.top).toFixed(2), h: r.height,
        id: btn ? +btn.dataset.bay : null, small: sm ? sm.textContent.trim() : null, head: h3 ? h3.textContent.replace(/\s+/g, ' ').trim() : null };
    }) };
  });
  const mid = list.querySelector('h3.mid');
  const gap = list.children.length ? parseFloat(getComputedStyle(list.children[0]).rowGap) : 0;
  return { listH: LR.height, cols, gap, midMargin: mid ? parseFloat(getComputedStyle(mid).marginTop) : null };
})()
'@

# ---------- Packed height and heading rows: pure functions on the columns ----------
# The packed target is not in the DOM, so these read its consequence. A column that stops short of its next column's first unit
# could have taken that unit and still end within the list's height, which is the tallest column with each rule's full box counted.
# A packer that packs to a target never leaves that room. The gap is the list's own row gap; a heading's own break adds the mid margin
# (read from the page) and the windows it keeps with it, as the packer checks them.
function BayPackProblems($cols, $midM, $gap) {
  $problems = @()
  if ($null -eq $midM -or -not $cols.Count) { return $problems }
  $g = [double]$gap
  $T = [double](($cols | % { $_.h } | Measure-Object -Maximum).Maximum)
  $counts = @{}; foreach ($c in $cols) { foreach ($it in @($c.items)) { if ($it.k -eq 'chip') { $counts[$it.cat] = 1 + [int]$counts[$it.cat] } } }
  for ($j = 0; $j -lt $cols.Count - 1; $j++) {
    $cur = @($cols[$j].items); $nxt = @($cols[$j + 1].items)
    if (-not $cur.Count -or -not $nxt.Count) { continue }
    $s = $nxt[0]
    if ($s.k -eq 'rule') {
      if ($nxt.Count -lt 2) { continue }
      $need = $g + [double]$nxt[1].h
    } elseif ($s.k -eq 'head') {
      $n = [int]$counts[$s.cat]; $keep = if ($n -le 3) { $n } else { 2 }
      if ($nxt.Count -lt 1 + $keep) { continue }
      $need = $g + [double]$midM + [double]$s.h
      for ($q = 1; $q -le $keep; $q++) { $need += $g + [double]$nxt[$q].h }
    } else { continue }
    $F = [double]$cols[$j].h
    if ($F + $need -le $T - 4) { $problems += "column $($j + 1) ends at $([int]$F)px and could take column $($j + 2)'s first unit ($([int]$need)px with its gap) under the list's $([int]$T)px" }
  }
  $problems
}
# A reasoned heading at a column's top, with a rule of its category at the top of the next column: the first window under each must line up.
function BayHeadRowProblems($cols) {
  $pairs = 0; $problems = @()
  for ($j = 0; $j -lt $cols.Count - 1; $j++) {
    $a = @($cols[$j].items); $b = @($cols[$j + 1].items)
    if ($a.Count -lt 2 -or $b.Count -lt 2) { continue }
    if ($a[0].k -ne 'head' -or $b[0].k -ne 'rule' -or $a[0].cat -ne $b[0].cat) { continue }
    if (-not @($BayReason.Values | ? { $a[0].head -like "*$_*" }).Count) { continue }
    $pairs++
    if ($a[1].k -ne 'chip' -or $b[1].k -ne 'chip') { $problems += "$($BayCatName[$a[0].cat]): the window after its heading is not a window"; continue }
    if ([Math]::Abs([double]$a[1].t - [double]$b[1].t) -gt 2) { $problems += "$($BayCatName[$a[0].cat]): the first window under its heading sits $([int]$a[1].t)px down, under the rule in column $($j + 2) it sits $([int]$b[1].t)px down" }
  }
  [pscustomobject]@{ pairs = $pairs; problems = $problems }
}

# ---------- Checks on the packed list and the capped list ----------
# Full state, one width: the packed columns (scope, then height, then the packer's room) and the heading rows.
function BayPackChecks($set, $w, $colsObj) {
  $lbl = "$($set.tag) at $w px"; $cols = @($colsObj.cols)
  $colsOf = @{}
  for ($j = 0; $j -lt $cols.Count; $j++) { foreach ($it in @($cols[$j].items)) { if ($it.cat) { $colsOf[$it.cat] = @($colsOf[$it.cat]) + $j } } }
  $splits = @($colsOf.Keys | ? { @($colsOf[$_] | Sort-Object -Unique).Count -gt 1 })
  Check "bay: ${lbl}: a category splits across columns (scope for the packed-height checks)" ($splits.Count -gt 0) "no category splits: each sits in one column"
  if ($splits.Count -eq 0) { return }
  $T = [double](($cols | % { $_.h } | Measure-Object -Maximum).Maximum)
  Check "bay: ${lbl}: the list is as tall as its tallest column, each rule's full box counted" ([Math]::Abs([double]$colsObj.listH - $T) -le 1) "list $([int]$colsObj.listH)px, tallest column $([int]$T)px"
  $pp = @(BayPackProblems $cols $colsObj.midMargin $colsObj.gap)
  Check "bay: ${lbl}: no column stops short of its next unit when that unit fits under the list's height" ($pp.Count -eq 0) ($pp -join ' | ')
  # The heading row is read where the packing puts a reasoned heading over a rule: at 1440 that is required. At 1024 no 3-column packing of
  # this fixture makes that pair and keeps every column from stopping short (the bay-list decision; enumerated over every cut position), so
  # the heading row has nothing to read there. If a pair does appear at 1024, its alignment is read.
  $hr = BayHeadRowProblems $cols
  if ($w -eq 1440) { Check "bay: ${lbl}: a reasoned heading at a column's top has its category's rule at the next column's top (scope for the heading row)" ($hr.pairs -gt 0) "no reasoned heading lines up with a rule in the next column" }
  if ($w -eq 1440 -or $hr.pairs -gt 0) { Check "bay: ${lbl}: a heading with a reason is one row tall: its first window lines up with the next column's first window under a rule" ($hr.problems.Count -eq 0) ($hr.problems -join ' | ') }
  else { Check "bay: ${lbl}: heading rows: nothing to read, no reasoned heading sits over a rule in the next column" $true }
}
# Capped, before Show N More is pressed, one width: the heading's reason and the lines follow the windows shown (the ruling), and the
# list is no taller than main's list for the same windows (today's probe; main puts a heading's first window 4px higher, so 4px is allowed).
function BayCapChecks($set, $w, $mc, $capCols, $more, $wins) {
  $lbl = "$($set.tag) capped at $w px"
  $items = @(@($capCols.cols) | % { @($_.items) })
  $vis = @($items | ? { $_.k -eq 'chip' })
  $visWins = @($wins | ? { @($vis | % { $_.id }) -contains $_.id })
  Check "bay: ${lbl}: the list is capped, with Show N More still to press (scope)" (($more -match '^Show \d+ More$') -and $visWins.Count -lt $wins.Count) "button reads '$more'; $($visWins.Count) of $($wins.Count) windows shown"
  Check "bay: ${lbl}: the list is no taller than main's list for the same windows" ($mc.listH -le $mc.todayH + 4.5) "list $([int]$mc.listH)px, main $([int]$mc.todayH)px"
  foreach ($c in 'code', 'browse', 'other') {
    $vc = @($visWins | ? { $_.cat -eq $c })
    if (-not $vc.Count) { continue }
    $name = $BayCatName[$c]
    $headItem = @($items | ? { $_.k -eq 'head' -and $_.cat -eq $c })
    $headText = if ($headItem.Count) { $headItem[0].head } else { '' }
    $chipsC = @($vis | ? { $_.cat -eq $c })
    Check "bay: ${lbl}: all $name windows shown are drawn (scope for the reason checks)" ($chipsC.Count -eq $vc.Count) "$($chipsC.Count) of $($vc.Count) drawn"
    # PowerShell names are case-blind: the reason key is $key, and the reason's text is $R.
    foreach ($key in 'fill', 'min') {
      $R = $BayReason[$key]
      if ($headText -like "*$R*") {
        $n = @($vc | ? { $_.reason -eq $key }).Count
        Check "bay: ${lbl}: $name's heading reason is shared by more than half the windows it shows" ($n * 2 -gt $vc.Count) "heading reads '$headText'; $n of $($vc.Count) shown windows say '$R'"
      }
    }
    $shared = $null; foreach ($key in 'fill', 'min') { if (@($vc | ? { $_.reason -eq $key }).Count * 2 -gt $vc.Count) { $shared = $key } }
    if ($null -ne $shared) {
      $R = $BayReason[$shared]
      $occ = ([regex]::Matches($headText, [regex]::Escape($R))).Count
      Check "bay: ${lbl}: $name's heading shows '$R' once, the reason the windows shown share" ($occ -eq 1) "heading reads '$headText'"
      $lines = @($chipsC | ? { (BayText $wins $_.id) -eq $R -and $_.small })
      Check "bay: ${lbl}: $name windows that share '$R' show no line of their own" ($lines.Count -eq 0) "$($lines.Count) still show a line"
      $other = @($chipsC | ? { (BayText $wins $_.id) -ne $R })
      $kept = @($other | ? { $_.small -eq (BayText $wins $_.id) })
      if ($other.Count) { Check "bay: ${lbl}: $name windows with another reason keep their own line" ($kept.Count -eq $other.Count) "$($other.Count - $kept.Count) of $($other.Count) lost their line" }
    } else {
      $bad = @($chipsC | ? { $_.small -ne (BayText $wins $_.id) })
      Check "bay: ${lbl}: $name shares no reason among the windows shown, so every window keeps its line" ($bad.Count -eq 0) "$($bad.Count) without their line"
    }
  }
}
# Mixed set, full state, one width: a window the scene gives no reason shows no line, and the reason the rest share shows once.
function BayNoneChecks($set, $w, $m, $wins) {
  $lbl = "$($set.tag) at $w px"
  $items = @($m.chips | ? { -not $_.hidden })
  Check "bay: ${lbl}: every window is in the list (scope)" ($items.Count -eq $wins.Count) "$($items.Count) of $($wins.Count) windows in the list"
  $fillIds = @($wins | ? { $_.reason -eq 'fill' } | % { $_.id }); $noneIds = @($wins | ? { $_.reason -eq 'none' } | % { $_.id })
  Check "bay: ${lbl}: the mixed set has its 'Not in this scene' window (scope)" ($noneIds.Count -eq 1 -and @($items | ? { $_.id -eq $noneIds[0] }).Count -eq 1) "no 'Not in this scene' window in the list"
  $R = $BayReason['fill']
  $head = @($m.heads | ? { $_.cat -eq 'other' })
  $headText = if ($head.Count) { $head[0].text } else { 'no heading' }
  $occ = if ($head.Count) { ([regex]::Matches($head[0].text, [regex]::Escape($R))).Count } else { 0 }
  Check "bay: ${lbl}: Other's heading shows '$R' once, the reason three of its four windows share" ($occ -eq 1 -and @($fillIds).Count * 2 -gt $wins.Count) "heading reads '$headText'"
  $lineOn = @($items | ? { $_.small -and (@($fillIds) + @($noneIds)) -contains $_.id })
  Check "bay: ${lbl}: the windows that share '$R', and the 'Not in this scene' window, show no line (as on main)" ($lineOn.Count -eq 0) "$($lineOn.Count) show a line"
}

# ---------- The cases ----------
# The list at one width, every window shown: columns, height, order, overlap, the rule, the lone window, and each category's reason.
function BayListChecks($set, $w, $m) {
  $wins = @($set.wins); $lbl = "$($set.tag) at $w px"
  $cats = @('code', 'browse', 'other') | ? { $c = $_; @($wins | ? { $_.cat -eq $c }).Count -gt 0 }
  $A = BayAnalyse $m; $items = @($A.items); $cols = $A.cols
  $K = [int]$m.K
  $chipsVis = @($m.chips | ? { -not $_.hidden })
  # Scope: the chips in the list are the windows we gave.
  Check "bay: ${lbl}: every window is in the list" ($chipsVis.Count -eq $wins.Count) "$($chipsVis.Count) of $($wins.Count) windows in the list"
  if ($set.kind -eq 'big') {
    if ($w -eq 1440) { Check "bay: ${lbl}: the list has room for more than three columns (scope)" ($K -gt 3) "K=$K" }
    Check "bay: ${lbl}: the list uses every column that fits" ($cols -eq $K) "list has $cols column(s); $K fit at $([int]$m.listW) px"
    if ($w -eq 1440) { Check "bay: ${lbl}: the list uses more than three columns" ($cols -gt 3) "list has $cols column(s), today's one per category" }
    Check "bay: ${lbl}: the list is shorter than today's list" ($m.contentH -lt ($m.todayH - 1)) "list $([int]$m.contentH)px, today $([int]$m.todayH)px"
  }
  $ordBad = @()
  foreach ($c in 'code', 'browse', 'other') {
    $want = (@($wins | ? { $_.cat -eq $c } | ForEach-Object { $_.id })) -join ','
    $got = (@($items | ? { $_.cat -eq $c } | Sort-Object col, t | ForEach-Object { $_.id })) -join ','
    if ($want -ne $got) { $ordBad += "$($BayCatName[$c]): want $want, got $got" }
  }
  Check "bay: ${lbl}: each category's windows stay in order" ($ordBad.Count -eq 0) ($ordBad -join ' | ')
  $ov = @(BayOverlaps $chipsVis)
  Check "bay: ${lbl}: no two windows overlap" ($ov.Count -eq 0) "overlapping: $($ov -join ' ')"
  $outside = @($chipsVis | ? { $_.l -lt $m.listL - 1 -or $_.r -gt $m.listR + 1 })
  Check "bay: ${lbl}: every window is inside the list" ($outside.Count -eq 0 -and $m.scrollW -le $m.clientW + 1) "$($outside.Count) outside the list's edges"
  $heads = @($m.heads | ? { $_.cat })
  Check "bay: ${lbl}: one heading per category" ($heads.Count -eq $cats.Count) "$($heads.Count) headings for $($cats.Count) categories"
  # Rules and lone windows: scope first. A split must exist before the rule and the lone check read it.
  $splits = @($cats | ? { (BayColsOf $items $_).Count -gt 1 })
  if ($set.kind -eq 'big') {
    Check "bay: ${lbl}: a category splits across columns (scope for the rule and lone checks)" ($splits.Count -gt 0) "no category splits: each sits in one column"
  }
  if ($splits.Count) {
    $rp = @(BayRuleProblems $items @($m.rules) $cols)
    Check "bay: ${lbl}: a column that opens partway through a category starts with its colour rule" ($rp.Count -eq 0) ($rp -join ' | ')
    $lp = @(BayLoneProblems $items $splits)
    Check "bay: ${lbl}: no split category leaves one window alone in a column" ($lp.Count -eq 0) ($lp -join ' | ')
  } elseif ($set.kind -eq 'small') {
    Check "bay: ${lbl}: no category splits, so the rule and lone checks have nothing to read" $true
  }
  # Reason Said Once, per category. The shared reason is the one more than half the category's windows give.
  foreach ($c in $cats) {
    $mine = @($wins | ? { $_.cat -eq $c }); $name = $BayCatName[$c]
    $chipsC = @($chipsVis | ? { $_.cat -eq $c })
    Check "bay: ${lbl}: all $name windows are in the list (scope for the reason checks)" ($chipsC.Count -eq $mine.Count) "$($chipsC.Count) of $($mine.Count) in the list"
    $shared = $null
    foreach ($r in 'fill', 'min') { if (@($mine | ? { $_.reason -eq $r }).Count * 2 -gt $mine.Count) { $shared = $r } }
    if ($null -eq $shared) {
      $bad = @($chipsC | ? { $_.small -ne (BayText $mine $_.id) })
      Check "bay: ${lbl}: $name shares no reason, so every window keeps its own line" ($bad.Count -eq 0) "$($bad.Count) without their line"
      continue
    }
    $R = $BayReason[$shared]
    $head = @($m.heads | ? { $_.cat -eq $c })
    $occ = if ($head.Count) { ([regex]::Matches($head[0].text, [regex]::Escape($R))).Count } else { 0 }
    $headText = if ($head.Count) { $head[0].text } else { 'no heading' }
    Check "bay: ${lbl}: $name's heading shows '$R' once" ($occ -eq 1) "heading reads '$headText'"
    $sharing = @($chipsC | ? { (BayText $mine $_.id) -eq $R })
    $lines = @($sharing | ? { $_.small })
    Check "bay: ${lbl}: $name windows that share '$R' show no line of their own" ($lines.Count -eq 0) "$($lines.Count) of $($sharing.Count) still show a line"
    $other = @($chipsC | ? { (BayText $mine $_.id) -ne $R })
    if ($other.Count) {
      $kept = @($other | ? { $_.small -eq (BayText $mine $_.id) })
      Check "bay: ${lbl}: $name windows with another reason keep their own line" ($kept.Count -eq $other.Count) "$($other.Count - $kept.Count) of $($other.Count) lost their line"
    }
  }
}

function BayEmptyChecks($w, $m) {
  Check "bay: empty bay at $w px draws no list: no window, heading or rule" ($m.chips.Count -eq 0 -and @($m.heads).Count -eq 0 -and @($m.rules).Count -eq 0) "$($m.chips.Count) chips, $(@($m.heads).Count) headings"
}

# ---------- Run the sets ----------
$pageRan = $false
try {
  $sets = @(
    @{ tag = '23 windows'; kind = 'big'; wins = $wins23; snap = $snap23; scene = $BaySceneFillOff; home = 'home-23' },
    @{ tag = '6 windows'; kind = 'small'; wins = $wins6; snap = $snap6; scene = $BaySceneFillOff; home = 'home-6' },
    @{ tag = 'empty bay'; kind = 'empty'; wins = $winsEmpty; snap = $snapEmpty; scene = $BaySceneFillOn; home = 'home-empty' },
    @{ tag = 'mixed reasons'; kind = 'mixed'; wins = $winsNone; snap = $snapNone; scene = $BaySceneFillOff; home = 'home-mixed' }
  )
  $browser = BayStartBrowser; $pageRan = $true
  foreach ($set in $sets) {
    $srv = BayStartServer $set.snap (Join-Path $run $set.home)
    try {
      $script:url = $srv[1]
      BayConfigScene $script:url $set.scene
      $spec = @($set.wins | ForEach-Object { [pscustomobject]@{ id = $_.id; cat = $_.cat; name = $BayCatName[$_.cat]; reason = $BayReason[$_.reason] } })
      foreach ($w in 1440, 1024) {
        BayViewport $w 900
        BayLoad $script:url
        if ($set.kind -eq 'big') {
          # Capped first: the list as it opens, before Show N More is pressed (the capped checks).
          $more = BayJs "document.getElementById('baymore').textContent.trim()"
          $capCols = BayGet $BayColsJs
          $visIds = @(@($capCols.cols) | % { @($_.items) } | ? { $_.k -eq 'chip' } | % { [int]$_.id })
          $mc = BayMeasure @($spec | ? { $visIds -contains $_.id })
          BayCapChecks $set $w $mc $capCols $more $set.wins
        }
        if ($set.kind -ne 'empty') { BayShowAll }
        $m = BayMeasure $spec
        if ($set.kind -eq 'empty') { BayEmptyChecks $w $m }
        elseif ($set.kind -eq 'mixed') { BayNoneChecks $set $w $m $set.wins }
        else { BayListChecks $set $w $m }
        if ($set.kind -eq 'big') { BayPackChecks $set $w (BayGet $BayColsJs) }
      }
    } finally { BayStopServer $srv }
  }
} catch {
  $script:fail++; "FAIL  run stopped: $_"
} finally {
  if ($pageRan) {
    try { Get-CimInstance Win32_Process -Filter "Name='msedge.exe'" | ? { $_.CommandLine -like "*$($script:udd)*" } | % { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue } } catch {}
  }
  foreach ($k in $savedEnv.Keys) { if ($null -eq $savedEnv[$k]) { Remove-Item "env:$k" -ErrorAction SilentlyContinue } else { Set-Item "env:$k" $savedEnv[$k] } }
  Remove-Item -LiteralPath $run -Recurse -Force -ErrorAction SilentlyContinue
}
if ($script:fail) { "$($script:fail) check(s) failed."; exit 1 } else { exit 0 }
