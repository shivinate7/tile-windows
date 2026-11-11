# Checks for stack (Put Behind, Bring to Front, Take Out), lock, resize by the corner grip, and the drop on a spanned block.
# Engine cases run tile.ps1 -Scene on the fixture. Page cases drive the real board with pointer events, in headless Edge
# over the DevTools protocol, on a dry-run server (nothing moves), then read the scene and the tile boxes back. A red
# case fails on its outcome: the scene or the boxes end up wrong. A missing control only makes the drag do nothing.
# Run alone: powershell -NoProfile -ExecutionPolicy Bypass -File test\stack-lock.ps1
# test\run.ps1 runs this file in a child powershell and counts its FAIL lines.
#
# Interface the builder must meet (what these cases read and drive):
#   Scene JSON (config.json scenes, the page's work[id], tile.ps1 -Scene):
#     pins[i].lock    true on a locked tile. It never moves on a swap, a zone, the fill, or a resize that would cover it.
#     pins[i].behind  [{app, match}]: windows stacked behind pins[i]. match reads as on a pin: text in the window title.
#                     They share pins[i]'s rect and are never in the fill.
#     pins[i].slots   a span is the whole block of cells, as today.
#     bay             [{app, title}], as today. Take Out and a resize with no free cell write here (Windows That Stay Put).
#   tile.ps1 -Scene -From <fixture> -Json, placed[]: a stacked window has behind = true, pin = its front pin's index,
#     and slots, x, y, w, h equal to the front's. A minimized stacked window is placed too (Apply restores it).
#   app.html, names read by the harness (keep them): work, selId, prevs, preview(id), els (window id -> its tile element,
#     dataset.id), snap, and the Save button with id save.
#   app.html DOM the harness drives:
#     Every window is a .tile. A locked tile's lock button is .tile .lk. The resize grip is .tile .rsz, bottom-right.
#     #drop holds the drop label. On a taken cell, the lower 36% reads Put Behind and the upper 64% reads Swap. On a
#     locked tile it reads Behind and Locked, never Swap. On a spanned block the same split covers the whole block, and it
#     never reads Place here. A drop on the lower band stacks the dragged window behind; a drop on the upper zone swaps.
#     The inspector, for the selected front tile, has a Bring to Front and a Take Out button for each window behind it.
#     A grip drag of 1.4 cells to the right, on a 1x1 tile, makes a 2-column span (whole cells, rounded).
#   Run folders: one per run, under <TEMP>\tile-windows-test-runs, named <pid>-<UUID>. A run removes siblings older than a day.

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
$tile = Join-Path $root 'tile.ps1'; $serve = Join-Path $root 'serve.ps1'; $fixture = Join-Path $PSScriptRoot 'fixture.json'
$utf8 = New-Object Text.UTF8Encoding $false
$script:fail = 0
function Check($name, $ok, $detail = '') { if ($ok) { "PASS  $name" } else { $script:fail++; "FAIL  $name  $detail" } }

# Run folders (test-temp-standard): one folder per run, <pid>-<UUID>, under one temp root. The first request of a run
# removes sibling run folders older than one day, and keeps newer ones.
$SlTempRoot = Join-Path $env:TEMP 'tile-windows-test-runs'
$SlRunName = '^\d+-[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
function SlSweep($dir, $olderThan) {
  if (-not (Test-Path -LiteralPath $dir)) { return }
  @(Get-ChildItem -LiteralPath $dir -Directory | ? { $_.Name -match $SlRunName -and $_.LastWriteTime -lt (Get-Date).Subtract($olderThan) }) | % { Remove-Item -LiteralPath $_.FullName -Recurse -Force }
}
# The sweep, proven on its own folder: an old run folder goes, a new one stays.
$proof = Join-Path $env:TEMP ('tile-windows-sweep-proof-' + [guid]::NewGuid().ToString())
New-Item -ItemType Directory $proof | Out-Null
$oldRun = Join-Path $proof ('1-' + [guid]::NewGuid().ToString()); $newRun = Join-Path $proof ('2-' + [guid]::NewGuid().ToString())
New-Item -ItemType Directory $oldRun | Out-Null; New-Item -ItemType Directory $newRun | Out-Null
(Get-Item -LiteralPath $oldRun).LastWriteTime = (Get-Date).AddDays(-2)
SlSweep $proof ([TimeSpan]::FromDays(1))
Check 'run folders: the sweep removes a run folder older than a day' (-not (Test-Path -LiteralPath $oldRun))
Check 'run folders: the sweep keeps a run folder newer than a day' (Test-Path -LiteralPath $newRun)
Remove-Item -LiteralPath $proof -Recurse -Force

# ---------- Engine: tile.ps1 -Scene on the fixture (dry run) ----------
# Fixture: claude 1001 'Refactor the grid solver', 1002 'Pin parser edge cases', 1003 'Draft release notes',
# 1004 'Claude' (minimized); chrome 1005 'Pull request 212', 1006 'Quarterly roadmap', 1007 'quoted'; WindowsTerminal
# 1008 'pwsh - tiler', 1009 'pwsh - docs watch'. Wide grid 5x2; slots are 0-based in a scene, 1-based in placed[].
function SlPlace($scene) { (& $tile -Scene $scene -From $fixture -Json 3>$null) -join '' | ConvertFrom-Json }
function SlSceneJson($pins, $fill = '[]', $extra = '') {
  '{"id":"sl","name":"Stack and lock","trigger":{"type":"manual","days":[],"time":"09:00"},"grids":{"wide":{"c":5,"r":2}},"pins":' + $pins + ',"fill":{"mon":"wide","apps":' + $fill + ',"skip":[],"sort":"app"}' + $extra + '}'
}
function SlPins { '[' + (@($args) -join ',') + ']' }

$eStack = SlPlace (SlSceneJson (SlPins '{"app":"claude","match":"Refactor","mon":"wide","slots":[3],"behind":[{"app":"claude","match":"Claude"}]}'))
$eFront = @($eStack.placed | ? { $_.id -eq 1001 })[0]; $eBack = @($eStack.placed | ? { $_.id -eq 1004 })[0]
$eSame = [bool]($eFront -and $eBack -and $eBack.x -eq $eFront.x -and $eBack.y -eq $eFront.y -and $eBack.w -eq $eFront.w -and $eBack.h -eq $eFront.h)
Check 'stack: a back window is placed on its front window''s rect, marked behind, in the front pin' ($eSame -and $eBack.behind -eq $true -and $eBack.pin -eq 0) "front: $($eFront | ConvertTo-Json -Compress) back: $($eBack | ConvertTo-Json -Compress)"
Check 'stack: Apply places a minimized back window (it is restored, not left minimized)' ([bool]($eBack -and $eBack.from.x -le -20000)) "back: $($eBack | ConvertTo-Json -Compress)"

$eOnce = SlPlace (SlSceneJson (SlPins '{"app":"chrome","match":"Quarterly","mon":"wide","slots":[3],"behind":[{"app":"claude","match":"Refactor"}]}') '["*"]')
$eCl = @($eOnce.placed | ? { $_.id -eq 1001 })
Check 'stack: a stacked window is placed once, on its front window''s cell, and the fill does not take it' ($eCl.Count -eq 1 -and $eCl[0].behind -eq $true -and ($eCl[0].slots -join ',') -eq '4') "claude placements: $($eCl | ConvertTo-Json -Compress)"

$eSpan = SlPlace (SlSceneJson (SlPins '{"app":"chrome","match":"Quarterly","mon":"wide","slots":[0,1,5,6]}'))
$eSpanCh = @($eSpan.placed | ? { $_.id -eq 1006 })[0]
Check 'control: a span pin places its whole 2x2 block (as today)' ([bool]($eSpanCh -and ($eSpanCh.slots -join ',') -eq '1,2,6,7')) "chrome: $($eSpanCh | ConvertTo-Json -Compress)"

# ---------- Page: headless Edge over DevTools, on a dry-run server ----------
$edgeExe = @("${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe", "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe") | ? { Test-Path -LiteralPath $_ } | Select-Object -First 1
if (-not $edgeExe) { 'SKIP  page cases: Microsoft Edge not found in either Program Files folder.'; if ($script:fail) { "$($script:fail) check(s) failed."; exit 1 } else { exit 0 } }

# One run folder, and a temp profile for every child: the real profile is never named.
[void](New-Item -ItemType Directory -Force $SlTempRoot)
SlSweep $SlTempRoot ([TimeSpan]::FromDays(1))
$run = Join-Path $SlTempRoot ("$PID-" + [guid]::NewGuid().ToString()); New-Item -ItemType Directory $run | Out-Null
# The browser keeps the real USERPROFILE (Edge will not open its DevTools port under a changed one). The server child
# gets a temp profile, and TILE_HOME points the engine and the server at the run folder.
$savedEnv = @{ TILE_HOME = $env:TILE_HOME }
$profile = Join-Path $run 'profile'; New-Item -ItemType Directory -Force (Join-Path $profile 'AppData\Roaming') | Out-Null
$env:TILE_HOME = Join-Path $run 'home'
$srv = $null; $edgeProc = $null; $script:ws = $null; $script:cdpId = 0; $script:url = ''; $script:udd = Join-Path $run 'edge'

function SlSend($method, $params) {
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
# Runs JS in the page. A promise is awaited in the page, so waits inside the page are bounded there, not in PowerShell.
function SlJs($expr) {
  $r = SlSend 'Runtime.evaluate' @{ expression = $expr; returnByValue = $true; awaitPromise = $true }
  if ($r.result.exceptionDetails) { $script:jsErr = "$($r.result.exceptionDetails.exception.description)"; return $null }
  $r.result.result.value
}
function SlGet($expr) { $s = SlJs ('JSON.stringify(' + $expr + ')'); if ($s) { $s | ConvertFrom-Json } }
function SlMouse($type, $x, $y, $buttons) { [void](SlSend 'Input.dispatchMouseEvent' @{ type = $type; x = [double]$x; y = [double]$y; button = 'left'; buttons = [int]$buttons; clickCount = 1 }) }
function SlFrame { [void](SlJs 'new Promise(r => requestAnimationFrame(() => requestAnimationFrame(() => r(true))))') }
# After a change: the preview has come back, and the tiles have finished any CSS transition (a box read mid-slide is a lie).
function SlSettle { [void](SlJs "preview(selId).then(() => Promise.all(document.getAnimations().filter(a => { const t = a.effect && a.effect.getComputedTiming(); return !t || t.iterations !== Infinity; }).map(a => a.finished.catch(() => null))))") }
function SlClick($at) { SlMouse 'mousePressed' $at[0] $at[1] 1; SlMouse 'mouseReleased' $at[0] $at[1] 0; SlSettle }
# Press at $from, move in eight steps to $to, then release there (or hold, with -Hold, to read the label mid-drag).
function SlDrag($from, $to, [switch]$Hold) {
  SlMouse 'mousePressed' $from[0] $from[1] 1
  for ($i = 1; $i -le 8; $i++) { SlMouse 'mouseMoved' ($from[0] + ($to[0] - $from[0]) * $i / 8) ($from[1] + ($to[1] - $from[1]) * $i / 8) 1 }
  SlFrame
  if (-not $Hold) { SlRelease $to }
}
function SlRelease($to) { SlMouse 'mouseReleased' $to[0] $to[1] 0; SlSettle }
# A tile's box in the viewport (null when it is not on the board), and points inside it by fraction.
function SlBox($id) { SlGet "(() => { const e = els.get($id); if (!e || e.hidden) return null; const r = e.getBoundingClientRect(); return { l: r.left, t: r.top, w: r.width, h: r.height }; })()" }
function SlAt($b, $fx, $fy) { @([double]($b.l + $b.w * $fx), [double]($b.t + $b.h * $fy)) }
function SlSame($a, $b) { [bool]($a -and $b -and [Math]::Abs($a.l - $b.l) -lt 1 -and [Math]::Abs($a.t - $b.t) -lt 1 -and [Math]::Abs($a.w - $b.w) -lt 1 -and [Math]::Abs($a.h - $b.h) -lt 1) }
function SlFmt($b) { if (-not $b) { 'none' } else { '{0},{1} {2}x{3}' -f [int]$b.l, [int]$b.t, [int]$b.w, [int]$b.h } }
function SlShort($x) { $j = ($x | ConvertTo-Json -Depth 6 -Compress); if ($j.Length -gt 400) { $j.Substring(0, 400) } else { $j } }
function SlLabel { SlJs "document.getElementById('drop').textContent" }
# The scene the server holds (after a Save), and the scene the page holds (work).
function SlSavedScene { ((Invoke-WebRequest -UseBasicParsing "$($script:url)config").Content | ConvertFrom-Json).scenes | ? { $_.id -eq 'sl' } | Select-Object -First 1 }
function SlPin($s, $text) { @($s.pins | ? { "$($_.match)" -like "*$text*" })[0] }
function SlHasBehind($pin, $text) { [bool]@($pin.behind | ? { ("$($_.match)$($_.title)") -like "*$text*" }).Count }
function SlHasBay($s, $text) { [bool]@($s.bay | ? { "$($_.title)" -like "*$text*" }).Count }
function SlCells($pin) { ($pin.slots | Sort-Object) -join ',' }
# Sets the config to one scene (id sl), then loads the page on it.
function SlCase($sceneJson) {
  $cfg = (Invoke-WebRequest -UseBasicParsing "$($script:url)config").Content | ConvertFrom-Json
  $cfg.scenes = @((ConvertFrom-Json $sceneJson))
  $body = ConvertTo-Json -Depth 12 -Compress $cfg
  if ((Invoke-WebRequest -UseBasicParsing "$($script:url)config" -Method Post -ContentType 'application/json; charset=utf-8' -Body ($utf8.GetBytes($body))).Content -ne 'Saved') { throw 'the config was not saved' }
  SlLoad
}
# Loads (or reloads) the page from the server's config, and waits (in the page) until the scene is drawn and settled.
function SlLoad {
  $before = SlJs 'String(performance.timeOrigin)'
  [void](SlSend 'Page.navigate' @{ url = $script:url })
  $ready = $null; $tries = 0
  while (-not $ready -and $tries -lt 3) {
    $tries++
    $ready = SlJs "new Promise((res, rej) => { const t0 = Date.now(); (function poll() { if (String(performance.timeOrigin) !== '$before' && typeof snap === 'object' && snap && selId && prevs[selId] && document.querySelectorAll('.tile').length) return res(true); if (Date.now() - t0 > 30000) return rej(new Error('no scene after 30 s')); setTimeout(poll, 100); })(); })"
  }
  if (-not $ready) {
    $diag = SlJs "JSON.stringify({ snap: typeof snap === 'object' && !!snap, selId: typeof selId === 'string' ? selId : null, drawn: typeof prevs === 'object' && !!selId && !!prevs[selId], tiles: document.querySelectorAll('.tile').length, url: location.href, status: (document.getElementById('status') || {}).textContent })"
    throw "the page did not draw the scene: $script:jsErr $diag"
  }
  SlSettle
}
function SlStartServer {
  $psi = New-Object Diagnostics.ProcessStartInfo 'powershell', "-NoProfile -ExecutionPolicy Bypass -File `"$serve`" -NoBrowser -From `"$fixture`""
  $psi.UseShellExecute = $false; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true; $psi.CreateNoWindow = $true
  $psi.EnvironmentVariables['USERPROFILE'] = $profile; $psi.EnvironmentVariables['APPDATA'] = Join-Path $profile 'AppData\Roaming'; $psi.EnvironmentVariables['TILE_HOME'] = $env:TILE_HOME
  $p = [Diagnostics.Process]::Start($psi)
  $line = $p.StandardOutput.ReadLineAsync(); if (-not $line.Wait(60000)) { throw 'the server did not print its URL' }
  @($p, $line.Result)
}
function SlStartBrowser {
  New-Item -ItemType Directory -Force $script:udd | Out-Null
  $args2 = @('--headless', '--disable-gpu', '--no-first-run', '--remote-debugging-port=0', "--user-data-dir=$($script:udd)", '--window-size=1440,900', '--host-resolver-rules="MAP fonts.googleapis.com 0.0.0.0, MAP fonts.gstatic.com 0.0.0.0"', 'about:blank')
  # Edge starts with the real user folders (under a temp USERPROFILE it never opens its DevTools port). Its data goes to
  # the run folder (--user-data-dir); the variables go back at once, and the server child keeps the temp profile.
  $keepUser = $env:USERPROFILE; $keepApp = $env:APPDATA
  $env:USERPROFILE = [Environment]::GetFolderPath('UserProfile'); $env:APPDATA = [Environment]::GetFolderPath('ApplicationData')
  try { $proc = Start-Process $edgeExe -PassThru -WindowStyle Hidden -ArgumentList $args2 } finally { $env:USERPROFILE = $keepUser; $env:APPDATA = $keepApp }
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
  try { if (-not $ct.Wait(30000)) { throw 'DevTools connect timed out' } } catch { throw "DevTools connect failed to $($page.webSocketDebuggerUrl): $($_.Exception.GetBaseException().Message)" }
  # --window-size does not hold under headless DevTools; the board needs a desktop-sized viewport.
  [void](SlSend 'Emulation.setDeviceMetricsOverride' @{ width = 1440; height = 900; deviceScaleFactor = 1; mobile = $false })
  $proc
}

# Scenes for the page cases (pins are JSON; each case wraps them in one scene, id sl). Windows are fixture ids by title.
$pinsCQ = SlPins '{"app":"claude","match":"Refactor","mon":"wide","slots":[0]}' '{"app":"chrome","match":"Quarterly","mon":"wide","slots":[1]}'
$pinsCQLock = SlPins '{"app":"claude","match":"Refactor","mon":"wide","slots":[0],"lock":true}' '{"app":"chrome","match":"Quarterly","mon":"wide","slots":[1]}'
$pinsResizeLock = SlPins '{"app":"claude","match":"Refactor","mon":"wide","slots":[0]}' '{"app":"chrome","match":"Quarterly","mon":"wide","slots":[1],"lock":true}'
$pinsSpan = SlPins '{"app":"chrome","match":"Quarterly","mon":"wide","slots":[0,1,5,6]}' '{"app":"WindowsTerminal","match":"tiler","mon":"wide","slots":[3]}'
$pinsFull = SlPins '{"app":"claude","match":"Refactor","mon":"wide","slots":[0]}' '{"app":"claude","match":"Pin parser","mon":"wide","slots":[1]}' '{"app":"claude","match":"Draft release","mon":"wide","slots":[2]}' '{"app":"chrome","match":"Pull request","mon":"wide","slots":[3]}' '{"app":"chrome","match":"Quarterly","mon":"wide","slots":[4]}' '{"app":"chrome","match":"quoted","mon":"wide","slots":[5]}' '{"app":"WindowsTerminal","match":"tiler","mon":"wide","slots":[6]}' '{"app":"WindowsTerminal","match":"docs watch","mon":"wide","slots":[7]}' '{"app":"explorer","match":"Projects","mon":"wide","slots":[8]}' '{"app":"explorer","match":"Downloads","mon":"wide","slots":[9]}'

try {
  $srvPair = SlStartServer; $srv = $srvPair[0]; $script:url = $srvPair[1]
  $edgeProc = SlStartBrowser

  # Harness control: the page draws a two-pin scene (a green case, so a red below is a real outcome).
  SlCase (SlSceneJson $pinsCQ)
  $ctl = SlGet 'prevs[selId].placed.length'
  Check 'harness: the page draws the two pinned windows (control)' ($ctl -eq 2) "placed: $ctl"

  # Stack: a drop on the lower band of a taken cell stacks the dragged window behind; the upper zone swaps (control).
  SlCase (SlSceneJson $pinsCQ)
  $from = SlAt (SlBox 1006) 0.5 0.5; SlDrag $from (SlAt (SlBox 1001) 0.5 0.85)
  $a1 = SlBox 1001; $c1 = SlBox 1006; $s1 = SlGet 'work[selId]'
  Check 'stack: a Put Behind drop leaves both windows on the front window''s cell' (SlSame $a1 $c1) "claude $(SlFmt $a1), chrome $(SlFmt $c1)"
  Check 'stack: the scene keeps the dropped window behind the front window' ([bool]@($s1.pins | % { @($_.behind) } | ? { $_.app -eq 'chrome' }).Count) (SlShort $s1.pins)

  SlCase (SlSceneJson $pinsCQ)
  $a0 = SlBox 1001; $c0 = SlBox 1006
  SlDrag (SlAt (SlBox 1006) 0.5 0.5) (SlAt (SlBox 1001) 0.5 0.35)
  $a2 = SlBox 1001; $c2 = SlBox 1006
  Check 'control: a drop on the upper zone of a taken cell still swaps' ((SlSame $a2 $c0) -and (SlSame $c2 $a0)) "claude $(SlFmt $a2), chrome $(SlFmt $c2)"

  # Stack: Bring to Front swaps the front with the window behind; Take Out sends the window to the bay.
  $pinsStack = SlPins '{"app":"claude","match":"Refactor","mon":"wide","slots":[0],"behind":[{"app":"claude","match":"Draft release"}]}'
  SlCase (SlSceneJson $pinsStack)
  SlClick (SlAt (SlBox 1001) 0.5 0.5)
  $bf = SlJs "(() => { const b = [...document.querySelectorAll('button')].find(x => x.textContent.trim() === 'Bring to Front'); if (!b) return false; b.click(); return true; })()"
  SlSettle
  $s2 = SlGet 'work[selId]'; $front2 = SlPin $s2 'Draft release'
  Check 'stack: Bring to Front makes the window behind the front window' ([bool]$front2 -and $front2.app -eq 'claude') "button found: $bf; pins: $(SlShort $s2.pins)"
  Check 'stack: Bring to Front keeps the old front window behind' ([bool]$front2 -and (SlHasBehind $front2 'Refactor')) "pins: $(SlShort $s2.pins)"

  SlCase (SlSceneJson $pinsStack)
  SlClick (SlAt (SlBox 1001) 0.5 0.5)
  $tk = SlJs "(() => { const b = [...document.querySelectorAll('button')].find(x => x.textContent.trim() === 'Take Out'); if (!b) return false; b.click(); return true; })()"
  SlSettle
  $s3 = SlGet 'work[selId]'; $front3 = SlPin $s3 'Refactor'
  Check 'stack: Take Out removes the window from the stack' ([bool]$front3 -and -not (SlHasBehind $front3 'Draft')) "button found: $tk; pins: $(SlShort $s3.pins)"
  Check 'stack: Take Out sends the window to Windows That Stay Put (the bay)' (SlHasBay $s3 'Draft release') "bay: $(SlShort $s3.bay)"

  # Lock: a drop on a locked tile stacks behind it and never moves it; the label offers Put Behind, not Swap.
  SlCase (SlSceneJson $pinsCQLock)
  $lk0 = SlBox 1001
  SlDrag (SlAt (SlBox 1006) 0.5 0.5) (SlAt $lk0 0.5 0.5)
  $lk1 = SlBox 1001; $s4 = SlGet 'work[selId]'
  Check 'lock: a drop on a locked tile does not move the locked tile' (SlSame $lk1 $lk0) "before $(SlFmt $lk0), after $(SlFmt $lk1)"
  Check 'lock: a drop on a locked tile stacks the dropped window behind it, not a swap' ([bool]@($s4.pins | ? { "$($_.match)" -like '*Refactor*' } | % { @($_.behind) } | ? { $_.app -eq 'chrome' }).Count) (SlShort $s4.pins)

  SlCase (SlSceneJson $pinsCQLock)
  SlDrag (SlAt (SlBox 1006) 0.5 0.5) (SlAt (SlBox 1001) 0.5 0.5) -Hold
  $lbl = SlLabel
  Check 'lock: over a locked tile the drop label offers Behind' ("$lbl" -match 'Behind') "label: $lbl"
  Check 'lock: over a locked tile the drop label never offers Swap' ("$lbl" -notmatch 'Swap') "label: $lbl"
  Check 'lock: over a locked tile the drop label says Locked' ("$lbl" -match 'Locked') "label: $lbl"
  SlRelease (SlAt (SlBox 1001) 0.5 0.5)

  # Lock: the lock control locks the tile, and Save keeps the lock in the scene.
  SlCase (SlSceneJson $pinsCQ)
  $lockAt = SlGet "(() => { const e = els.get(1001); const k = e.querySelector('.lk'); const r = (k || e).getBoundingClientRect(); return k ? [r.left + r.width / 2, r.top + r.height / 2] : [r.right - 8, r.top + 8]; })()"
  SlClick @([double]$lockAt[0], [double]$lockAt[1])
  [void](SlJs "(() => { const b = document.getElementById('save'); if (b && !b.disabled) { b.click(); return true; } return false; })()")
  SlSettle
  $saved = SlSavedScene; $savedPin = SlPin $saved 'Refactor'
  Check 'lock: the lock control locks the tile, and Save keeps the lock in the scene' ([bool]($savedPin -and $savedPin.lock -eq $true)) "saved pin: $(SlShort $savedPin)"
  SlLoad
  $reloaded = SlPin (SlGet 'work[selId]') 'Refactor'
  Check 'lock: the saved lock is still on the tile after the page reloads' ([bool]($reloaded -and $reloaded.lock -eq $true)) "reloaded pin: $(SlShort $reloaded)"

  # Resize: a span drag by the corner grip snaps to whole cells; a covered window moves to a free cell; no free cell
  # sends it to the bay; a resize stops at a locked tile.
  SlCase (SlSceneJson $pinsCQ)
  $b5 = SlBox 1001; SlDrag (SlAt $b5 (($b5.w - 6) / $b5.w) (($b5.h - 6) / $b5.h)) (SlAt $b5 ((($b5.w - 6) + 1.4 * $b5.w) / $b5.w) (($b5.h - 6) / $b5.h))
  $s5 = SlGet 'work[selId]'; $p5 = SlPin $s5 'Refactor'
  Check 'resize: a corner drag of 1.4 cells snaps to a 2-column span' ([bool]$p5 -and (SlCells $p5) -eq '0,1') "claude pin: $(SlShort $p5)"

  SlCase (SlSceneJson $pinsCQ)
  $b6 = SlBox 1001; SlDrag (SlAt $b6 (($b6.w - 6) / $b6.w) (($b6.h - 6) / $b6.h)) (SlAt $b6 ((($b6.w - 6) + 1.4 * $b6.w) / $b6.w) (($b6.h - 6) / $b6.h))
  $s6 = SlGet 'work[selId]'; $q6 = SlPin $s6 'Quarterly'; $p6 = SlPin $s6 'Refactor'
  Check 'resize: a covered window moves to the first free cell' ([bool]$q6 -and (SlCells $q6) -eq '2' -and (SlCells $p6) -eq '0,1') "chrome pin: $(SlShort $q6); claude pin: $(SlShort $p6)"

  SlCase (SlSceneJson $pinsFull)
  $b7 = SlBox 1001; SlDrag (SlAt $b7 (($b7.w - 6) / $b7.w) (($b7.h - 6) / $b7.h)) (SlAt $b7 ((($b7.w - 6) + 1.4 * $b7.w) / $b7.w) (($b7.h - 6) / $b7.h))
  $s7 = SlGet 'work[selId]'
  Check 'resize: with no free cell, the covered window goes to Windows That Stay Put' (SlHasBay $s7 'Pin parser') "bay: $(SlShort $s7.bay)"

  # The grip ends over the locked cell (cell 2), so a span over it must stop short. A 1x1 window that moves rather than
  # resizes would land on the locked cell and swap with it.
  SlCase (SlSceneJson $pinsResizeLock)
  $b8 = SlBox 1001; SlDrag (SlAt $b8 (($b8.w - 6) / $b8.w) (($b8.h - 6) / $b8.h)) (SlAt $b8 ((($b8.w - 6) + 0.6 * $b8.w) / $b8.w) (($b8.h - 6) / $b8.h))
  $s8 = SlGet 'work[selId]'; $l8 = SlPin $s8 'Quarterly'; $c8 = SlPin $s8 'Refactor'
  Check 'resize: a resize stops at a locked tile, which keeps its cell' ([bool]$l8 -and $l8.lock -eq $true -and (SlCells $l8) -eq '1') "locked pin: $(SlShort $l8)"

  # Spanned drop: the whole 2x2 block is the target. Put Behind stacks behind it and keeps its span. Swap gives the block
  # to the dropped window and moves the spanned window to the dropped window's old 1x1 cell.
  SlCase (SlSceneJson $pinsSpan)
  $blk = SlBox 1006; $term = SlBox 1008
  SlDrag (SlAt $term 0.5 0.5) (SlAt $blk 0.5 0.85) -Hold
  $lbl2 = SlLabel
  Check 'span: a drop on a spanned block labels the whole block Put Behind' ("$lbl2" -match 'Behind') "label: $lbl2"
  Check 'span: a drop on a spanned block never labels one cell (Place here, or Here on a narrow cell)' ("$lbl2" -notmatch '(?i)place here|^here$') "label: $lbl2"
  SlRelease (SlAt $blk 0.5 0.85)

  SlCase (SlSceneJson $pinsSpan)
  $blk3 = SlBox 1006; $term3 = SlBox 1008
  SlDrag (SlAt $term3 0.5 0.5) (SlAt $blk3 0.5 0.85)
  $s9 = SlGet 'work[selId]'; $ch9 = SlPin $s9 'Quarterly'; $tm9 = SlPin $s9 'tiler'
  Check 'span: Put Behind on a spanned block keeps the block''s 2x2 span' ([bool]$ch9 -and (SlCells $ch9) -eq '0,1,5,6') "chrome pin: $(SlShort $ch9)"
  Check 'span: Put Behind on a spanned block stacks the dropped window behind it' ([bool]$ch9 -and (SlHasBehind $ch9 'tiler')) "chrome pin: $(SlShort $ch9)"

  SlCase (SlSceneJson $pinsSpan)
  $blk4 = SlBox 1006; $term4 = SlBox 1008
  SlDrag (SlAt $term4 0.5 0.5) (SlAt $blk4 0.5 0.35)
  $s10 = SlGet 'work[selId]'; $tm10 = SlPin $s10 'tiler'; $ch10 = SlPin $s10 'Quarterly'
  Check 'span: a swap on a spanned block gives the dropped window the whole 2x2 block' ([bool]$tm10 -and (SlCells $tm10) -eq '0,1,5,6') "terminal pin: $(SlShort $tm10)"
  Check 'span: a swap on a spanned block moves the spanned window to the dropped window''s old 1x1 cell' ([bool]$ch10 -and (SlCells $ch10) -eq '3') "chrome pin: $(SlShort $ch10)"
  $placed10 = @((SlGet 'prevs[selId].placed') | ? { -not $_.behind })
  $cellsUsed = @($placed10 | % { $_.slots }); $dupCells = @($cellsUsed | Group-Object | ? { $_.Count -gt 1 }).Count
  Check 'span: after a swap on a spanned block, the spanned window keeps a cell' ([bool]@($placed10 | ? { $_.app -eq 'chrome' }).Count) "placed: $(SlShort $placed10)"
  # A guard, not a new claim: a swap that drops the spanned window still shows no overlap, so this one passes on the old code.
  Check 'span: after a swap on a spanned block, no two windows share a cell (no tile overlaps)' ($placed10.Count -gt 0 -and $dupCells -eq 0) "duplicate cells: $dupCells"
} catch {
  $script:fail++; "FAIL  run stopped: $_ (line $($_.InvocationInfo.ScriptLineNumber))"
} finally {
  # Only the browsers this run started: each one's command line names this run's profile folder.
  Get-CimInstance Win32_Process -Filter "Name='msedge.exe'" | ? { $_.CommandLine -like "*$($script:udd)*" } | % { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
  if ($script:ws) { $script:ws.Dispose() }
  if ($srv -and -not $srv.HasExited) { $srv.Kill() }
  foreach ($k in $savedEnv.Keys) { if ($null -eq $savedEnv[$k]) { Remove-Item "env:$k" -ErrorAction SilentlyContinue } else { Set-Item "env:$k" $savedEnv[$k] } }
  if (Test-Path -LiteralPath $run) { Remove-Item -LiteralPath $run -Recurse -Force -ErrorAction SilentlyContinue }
}
if ($script:fail) { "$($script:fail) check(s) failed."; exit 1 } else { 'All checks passed.' }
