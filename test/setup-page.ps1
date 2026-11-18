# Monitor setups, the page (decision monitor-setups): what the board, the inspector and the scene cards do for the plugged-in setup.
# Plain asserts, one FAIL line per failing check. Its own file, run in a child powershell by test\run.ps1 (its FAIL lines count there).
# Run alone: powershell -NoProfile -ExecutionPolicy Bypass -File test\setup-page.ps1
#
# The page runs in headless Edge, driven over the DevTools protocol. No #selftest hook is used: a hook is app.html code, so a commit
# whose page is not built answers no hook at all, and a case would fail for "no hook", which is not the named cause. Each case writes
# its own config, opens the page on a dry-run server (-From: no window moves), wraps fetch before it acts, and reads what the page sent
# and what it shows. Waits are on page conditions, never on a fixed time.
#
# The contract checked (the builder meets it):
#   Board: a board edit on a scene sends one POST /layout with the plugged-in setup key and no POST /config. Default (built-in) too.
#   Undo: sends one more POST /layout, which writes the layout back as it was before the edit.
#   Unplugged: a window a layout pins to a monitor not in the snapshot is listed in Windows That Stay Put, reason "Its screen is unplugged".
#   Inspector: after a layout-only edit there is no Revert button, and Save is off with "No name or trigger changes to save".
#   Cards: a scene with no layout of its own on the plugged setup reads "follows <setup>"; one with its own layout reads "own layout".
#   Offline (file://): the sample loads, and a board edit sends no POST.
#   Setup change: a POST /layout the server refuses (409: the setup changed) leaves the strip amber, with a message that the setup
#     changed and a Refresh control. The strip offers no retry under the old key. Refresh or Apply onto the new setup clears Undo:
#     no POST /layout under the new key carries the old setup's layout.
#   Autosave: a board edit's POST /layout keeps the Windows That Stay Put and held entries of closed windows as the server had them.
#   Failed read: a re-read whose GET /config or GET /layouts fails leaves the strip amber, with a message.
#   Delete: deleting a scene whose save was refused, or still in flight, leaves the strip clear, and a late refusal does not bring it back.
#   Monitors and Setups (decision monitor-setups, item 13): the strip has a Monitors and Setups button, and it opens a dialog that lists each
#     monitor and each setup in a name field. Forget is off for the monitor plugged in and for the setup in use, and each off Forget's reason
#     is the text its aria-describedby names. An unplugged monitor and its setup have Forget on. Two states: plugged-in only (empty), and
#     with an unplugged monitor and its setup (full).
#     The Forget of a setup that holds a plugged-in monitor is refused by the server (409, setup-plumbing.ps1), not checked here.
#   Size id (item 3, coordinator ruling 21:04 CST): a monitor whose id is size-WxH is remembered by that id. The strip is the normal one, and
#     no Remember It by Its Size button is on the page. Two shapes: every monitor with a size id, and only the ultrawide.
#   Offline, dialog: the offline page shows no Monitors and Setups button and sends no request. A guard: green on the old commit, and a
#     mutant with the button turns it red (run on a scratch copy).
# Guards: they hold on the page as it stands, and a mutant on a scratch copy turns each red. They are the unplugged, offline, Refresh
# clears Undo, and delete cases. The setup change, Apply, autosave and failed-read cases are red on the page as it stands.
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
$serve = Join-Path $root 'serve.ps1'; $appHtml = Join-Path $root 'app.html'
$fixture = Join-Path $PSScriptRoot 'fixture.json'; $scenesFile = Join-Path $root 'scenes.json'
$utf8 = New-Object Text.UTF8Encoding $false
$script:fail = 0
function Check($name, $ok, $detail = '') { if ($ok) { "PASS  $name" } else { $script:fail++; "FAIL  $name  $detail" } }
# One case. An error inside it is one FAIL line, and the run goes on.
function Case([string]$name, [scriptblock]$body) { try { & $body } catch { $script:fail++; "FAIL  $name  threw: $($_.Exception.Message)" } }

$edge = @("${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe", "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe") | ? { Test-Path -LiteralPath $_ } | Select-Object -First 1
if (-not $edge) { 'SKIP  page cases: Microsoft Edge not found in either Program Files folder.'; exit 0 }

# Run folder (test-temp-standard): <TEMP>\tile-windows-test-runs\<pid>-<UUID>, removed at the end. The sweep of old run folders is stack-lock.ps1's.
$runRoot = Join-Path $env:TEMP 'tile-windows-test-runs'
New-Item -ItemType Directory -Force $runRoot | Out-Null
$runDir = Join-Path $runRoot ("$PID-" + [guid]::NewGuid().ToString())
New-Item -ItemType Directory $runDir | Out-Null

# Strip what the code under test reads from the caller, and point the profile and the server's TILE_HOME into the run folder.
$saved = @{ USERPROFILE = $env:USERPROFILE; APPDATA = $env:APPDATA; TILE_HOME = $env:TILE_HOME; TILE_SCREENS_FILE = $env:TILE_SCREENS_FILE }
$prof = Join-Path $runDir 'profile'; New-Item -ItemType Directory -Force (Join-Path $prof 'AppData\Roaming') | Out-Null
$tileHome = Join-Path $runDir 'tile-home'; New-Item -ItemType Directory $tileHome | Out-Null
$env:USERPROFILE = $prof; $env:APPDATA = Join-Path $prof 'AppData\Roaming'; $env:TILE_HOME = $null; $env:TILE_SCREENS_FILE = $null

$srv = $null; $ws = $null; $edgeProc = $null
$edgeProfile = Join-Path $runDir 'edge-profile'

# The plugged-in monitors: the fixture's three screens, with the ids a real snapshot carries. The setup key is the sorted ids.
$plugKey = 'L1|P1|U1'
$snapObj = [IO.File]::ReadAllText($fixture, $utf8) | ConvertFrom-Json
$snapObj.monitors = @(
  [pscustomobject]@{ id = 'L1'; name = 'Panel 1'; role = 'laptop'; x = -1536; y = 769; w = 1536; h = 912; bw = 1536; bh = 960; builtin = $true }
  [pscustomobject]@{ id = 'U1'; name = 'Panel 2'; role = 'wide'; x = 0; y = 0; w = 4096; h = 1680; bw = 4096; bh = 1728; builtin = $false }
  [pscustomobject]@{ id = 'P1'; name = 'Panel 3'; role = 'tall'; x = 4096; y = -1354; w = 1200; h = 1872; bw = 1200; bh = 1920; builtin = $false }
)
$snapPath = Join-Path $runDir 'snap.json'
[IO.File]::WriteAllText($snapPath, (ConvertTo-Json -Depth 10 -Compress -InputObject $snapObj), $utf8)

# A config as the starters give it, with the three monitors and the one setup they make. Each case adds what it needs.
$stamp = '2026-11-17T09:00:00'
function New-Config {
  $c = [IO.File]::ReadAllText($scenesFile, $utf8) | ConvertFrom-Json
  $c.monitors = [pscustomobject]@{
    L1 = [pscustomobject]@{ name = 'Laptop'; builtin = $true; lastSeen = $stamp; bw = 1536; bh = 960 }
    P1 = [pscustomobject]@{ name = 'Portrait'; builtin = $false; lastSeen = $stamp; bw = 1200; bh = 1920 }
    U1 = [pscustomobject]@{ name = 'Ultrawide'; builtin = $false; lastSeen = $stamp; bw = 4096; bh = 1728 }
  }
  $c.setups = [pscustomobject]@{ 'L1|P1|U1' = [pscustomobject]@{ name = 'Desk'; ids = @('L1', 'P1', 'U1'); lastUsed = $stamp } }
  $c
}
function Add-Layout($cfg, [string]$scene, [string]$key, [string]$json) {
  $sc = @($cfg.scenes | ? { $_.id -eq $scene })[0]
  $sc.layouts | Add-Member -Force -NotePropertyName $key -NotePropertyValue (ConvertFrom-Json $json)
}
function Put-Config($cfg) { [IO.File]::WriteAllText((Join-Path $tileHome 'config.json'), (ConvertTo-Json -Depth 20 -Compress -InputObject $cfg), $utf8) }
# A layout as the server keeps it: keys sorted at every depth, so two layouts compare by their content.
function Canon($o) {
  if ($null -eq $o) { return 'null' }
  if ($o -is [pscustomobject]) { $parts = foreach ($p in @($o.PSObject.Properties | Sort-Object Name)) { (ConvertTo-Json -Compress $p.Name) + ':' + (Canon $p.Value) }; return '{' + ($parts -join ',') + '}' }
  if ($o -is [array]) { $parts = foreach ($x in $o) { Canon $x }; return '[' + ($parts -join ',') + ']' }
  ConvertTo-Json -Compress $o
}
# The layouts the page is shown: focus has its own layout on the plugged setup; meetings has one only on Laptop + Ultrawide.
$focusOwn = '{"grids":{"P1":{"c":1,"r":2},"U1":{"c":3,"r":1}},"pins":[{"app":"claude","match":"Refactor the grid solver","mon":"GONE","slots":[0]}],"zones":[],"fill":{"mon":"U1","apps":[],"skip":[],"sort":"app"},"bay":[]}'
$meetLayout = '{"grids":{"U1":{"c":4,"r":2}},"pins":[],"zones":[],"fill":{"mon":"U1","apps":["*"],"skip":[],"sort":"app"},"bay":[]}'

# A child powershell, with the run's profile and TILE_HOME. Stdout is redirected so the caller can read the server's URL.
function Start-Child([string]$argLine) {
  $psi = New-Object Diagnostics.ProcessStartInfo 'powershell', "-NoProfile -ExecutionPolicy Bypass $argLine"
  $psi.UseShellExecute = $false; $psi.RedirectStandardOutput = $true; $psi.CreateNoWindow = $true
  $psi.EnvironmentVariables['USERPROFILE'] = $prof; $psi.EnvironmentVariables['APPDATA'] = Join-Path $prof 'AppData\Roaming'
  $psi.EnvironmentVariables['TILE_HOME'] = $tileHome; $psi.EnvironmentVariables['TILE_SCREENS_FILE'] = ''
  [Diagnostics.Process]::Start($psi)
}

# DevTools protocol: one command, and the reply with its id. Events that arrive first are read past.
$script:cdpId = 0
function Cdp($sock, [string]$method, $params = @{}) {
  $script:cdpId++; $id = $script:cdpId
  $bytes = $utf8.GetBytes((ConvertTo-Json -Depth 10 -Compress -InputObject @{ id = $id; method = $method; params = $params }))
  $sock.SendAsync([ArraySegment[byte]]::new($bytes), [Net.WebSockets.WebSocketMessageType]::Text, $true, [Threading.CancellationToken]::None).GetAwaiter().GetResult()
  while ($true) {
    $ms = New-Object IO.MemoryStream
    do {
      $buf = New-Object byte[] 65536
      $res = $sock.ReceiveAsync([ArraySegment[byte]]::new($buf), [Threading.CancellationToken]::None).GetAwaiter().GetResult()
      $ms.Write($buf, 0, $res.Count)
    } while (-not $res.EndOfMessage)
    $msg = $utf8.GetString($ms.ToArray()) | ConvertFrom-Json
    if ($msg.id -eq $id) { if ($msg.error) { throw "DevTools $method : $($msg.error.message)" }; return $msg }
  }
}
# Runs a body in the page and returns its JSON value. The body returns a value; a throw in the page is a throw here.
function Js($sock, [string]$body) {
  $expr = '(async () => { ' + $body + ' })().then(v => JSON.stringify(v === undefined ? null : v))'
  $r = Cdp $sock 'Runtime.evaluate' @{ expression = $expr; awaitPromise = $true; returnByValue = $true }
  if ($r.result.exceptionDetails) { throw ('page script: ' + [string]$r.result.exceptionDetails.exception.description) }
  $v = [string]$r.result.result.value
  if ($v) { ConvertFrom-Json $v }
}
# Waits until a page condition holds, up to a deadline. Not a sleep: it polls the page and stops as soon as the page is ready.
function WaitFor($sock, [string]$cond, [int]$seconds = 120) {
  $t0 = Get-Date
  while ($true) {
    if ((Js $sock ('try { return !!(' + $cond + ') } catch (e) { return false }')) -eq $true) { return $true }
    if (((Get-Date) - $t0).TotalSeconds -gt $seconds) { return $false }
    Start-Sleep -Milliseconds 250
  }
}
# Opens a URL and waits for its page to be ready. The old page's marker is gone only once the new page has replaced it.
function Go($sock, [string]$url, [string]$cond) {
  [void](Js $sock 'window.__gen = 1; return true')
  $nav = Cdp $sock 'Page.navigate' @{ url = $url }
  if ($nav.result.errorText) { return $false }
  WaitFor $sock ('window.__gen === undefined && document.readyState === "complete" && (' + $cond + ')')
}
# The page is ready for a live run: the snapshot, the config, and a preview of every scene.
$livePageReady = 'typeof snap !== "undefined" && !!snap && typeof cfg !== "undefined" && !!cfg && typeof prevs !== "undefined" && Object.keys(prevs).length >= cfg.scenes.length'
# Wraps fetch so each POST is recorded, and gives a settle that waits for the POSTs in flight (and any they start).
$installJs = @'
if (!window.__h) {
  window.__posts = []; window.__pending = [];
  const f = window.fetch.bind(window);
  window.fetch = (u, o) => { const p = f(u, o); if (o && String(o.method || "").toUpperCase() === "POST") { window.__posts.push({ url: String(u), body: String(o.body || "") }); window.__pending.push(p.catch(() => {})) } return p };
  window.__h = {
    settle: async () => { for (let i = 0; i < 50; i++) { const n = window.__pending.length; await Promise.allSettled(window.__pending.slice()); await new Promise(r => setTimeout(r, 0)); if (window.__pending.length === n) return } },
    posts: u => window.__posts.filter(p => p.url === u)
  }
}
return true
'@
# The server reads the -From file on every request, so the file is the plugged-in setup. A is the Desk setup of this file; B (the wide and
# the tall screens) is plugged in by writing it. Open-Page plugs A back in, so a case never starts on B.
$snapAText = [IO.File]::ReadAllText($snapPath, $utf8)
$snapBText = ConvertTo-Json -Depth 10 -Compress -InputObject ([pscustomobject]@{ monitors = @($snapObj.monitors | ? { @('U1', 'P1') -contains $_.id }); windows = @($snapObj.windows) })
function Plug([string]$text) { [IO.File]::WriteAllText($snapPath, $text, $utf8) }
# The POSTs of a log (from window.__h.posts) sent under one setup key.
function Posts-Under($posts, [string]$key) { @(@($posts) | ? { $_ -and (ConvertFrom-Json $_.body).key -ceq $key }) }
# The POSTs of a log sent under one setup key whose layout is the given canonical text.
function Posts-Carrying($posts, [string]$key, [string]$canon) { @(@($posts) | ? { $_ -and ((ConvertFrom-Json $_.body).key -ceq $key) -and ((Canon (ConvertFrom-Json $_.body).layout) -ceq $canon) }) }
# The autosave strip as the page shows it: hidden or not, amber or not, its text, and its buttons.
$stripJs = 'const b = document.getElementById("setbar"); return { hidden: b.hidden, warn: b.classList.contains("warn"), text: b.textContent.replace(/\s+/g, " ").trim(), buttons: [...b.querySelectorAll("button")].map(x => x.textContent.trim()) }'
# Deletes the scene on the page through its Delete button and the confirm dialog, and waits until its card is gone.
function Delete-Scene($sock, [string]$scene) {
  [void](Js $sock 'document.getElementById("del").click(); return true')
  [void](WaitFor $sock 'document.getElementById("dlg").open && !!document.querySelector("#dlgform button[value=ok]")')
  [void](Js $sock 'document.querySelector("#dlgform button[value=ok]").click(); return true')
  WaitFor $sock ('!document.querySelector("[data-pick=__S__]")'.Replace('__S__', $scene))
}

# Opens the live page on a scene: the card is clicked, as a user would. $snapText, when given, is the snapshot the server shows instead of A.
function Open-Page($sock, [string]$url, [string]$scene, [string]$snapText = '') {
  Plug $(if ($snapText) { $snapText } else { $snapAText })
  if (-not (Go $sock $url $livePageReady)) { return $false }
  [void](Js $sock $installJs)
  [void](Js $sock ('document.querySelector("[data-pick=__S__]").click(); return true'.Replace('__S__', $scene)))
  WaitFor $sock ('selId === "__S__"'.Replace('__S__', $scene))
}
# One board edit: window 1001 pinned to a cell of the wide monitor. Returns the POSTs it sent to /layout and /config.
function Board-Edit($sock, [int]$id, [int]$slot = 9) {
  Js $sock ('pinWin(__ID__, snap.monitors.find(m => m.role === "wide"), __SLOT__); await preview(selId); await window.__h.settle(); return { layout: window.__h.posts("layout"), config: window.__h.posts("config") }'.Replace('__ID__', "$id").Replace('__SLOT__', "$slot"))
}
# The Monitors and Setups dialog and the strip's button for it. Helpers answer null or false for a missing piece, so no page script throws.
# A row is the smallest element that holds one name field (an input whose value is the name) and one Forget button.
$dlgHelpers = @'
const dlgOf = () => [...document.querySelectorAll("dialog, [role=dialog]")].find(d => /Monitors and Setups/.test(d.textContent) && (d.tagName !== "DIALOG" || d.open));
const forgetsIn = el => [...el.querySelectorAll("button")].filter(b => b.textContent.trim() === "Forget");
const rowOf = name => { const d = dlgOf(); if (!d) return null; const f = [...d.querySelectorAll("input")].find(i => i.value === name); if (!f) return null; let r = f; while (r && r !== d && forgetsIn(r).length === 0) r = r.parentElement; return r && forgetsIn(r).length === 1 ? r : null; };
const forgetOf = name => { const r = rowOf(name); return r ? forgetsIn(r)[0] : null; };
const offOf = name => { const b = forgetOf(name); return !!b && (b.disabled || b.getAttribute("aria-disabled") === "true"); };
const reasonOf = name => { const b = forgetOf(name); if (!b) return ""; return (b.getAttribute("aria-describedby") || "").split(/\s+/).filter(Boolean).map(id => { const e = document.getElementById(id); return e ? e.textContent : ""; }).join(" ").replace(/\s+/g, " ").trim(); };
'@
# The strip's Monitors and Setups button, found by its text, aria-label or title.
$mgBtnTest = '[...document.querySelectorAll("#setbar button")].find(x => /Monitors and Setups/.test(x.textContent + " " + (x.getAttribute("aria-label") || "") + " " + (x.title || "")))'
$hasMgJs = "return !!($mgBtnTest)"
$openDlgJs = "const b = $mgBtnTest; if (!b) return false; b.click(); return true"
$dlgUpCond = '[...document.querySelectorAll("dialog, [role=dialog]")].some(d => /Monitors and Setups/.test(d.textContent) && (d.tagName !== "DIALOG" || d.open))'
# Clicks the strip's button and waits for the dialog. Answers 'nobutton', 'noopen' or 'open'.
function Open-Dialog($sock) {
  if ((Js $sock $hasMgJs) -ne $true) { return 'nobutton' }
  [void](Js $sock $openDlgJs)
  if (WaitFor $sock $dlgUpCond 20) { 'open' } else { 'noopen' }
}
# The named rows of the open dialog: whether each is listed, whether its Forget is off, and the text its Forget names as its reason.
function Dlg-Rows($sock, [string[]]$names) {
  Js $sock ($dlgHelpers + 'const names = ' + (ConvertTo-Json -Compress -InputObject @($names)) + '; return names.map(n => ({ n: n, row: !!rowOf(n), off: offOf(n), reason: reasonOf(n) }))')
}
# A snapshot whose monitors carry size ids (size-WxH, as tile.ps1 gives a monitor with no device): every one of them, and only the ultrawide.
$sizeAllObj = ConvertFrom-Json $snapAText
foreach ($m in @($sizeAllObj.monitors)) { $m.id = "size-$($m.bw)x$($m.bh)" }
$sizeAll = ConvertTo-Json -Depth 10 -Compress -InputObject $sizeAllObj
$sizeOneObj = ConvertFrom-Json $snapAText
$sizeU1 = @($sizeOneObj.monitors | ? { $_.id -eq 'U1' })[0]
$sizeU1.id = "size-$($sizeU1.bw)x$($sizeU1.bh)"
$sizeOne = ConvertTo-Json -Depth 10 -Compress -InputObject $sizeOneObj
# Wraps fetch before the page's own scripts run, so a request made while the page loads is recorded too.
$recordJs = '(() => { window.__sent = []; const f = window.fetch.bind(window); window.fetch = (u, o) => { window.__sent.push(((o && o.method) || "GET").toUpperCase() + " " + String(u)); return f(u, o); }; })();'

try {
  $probe = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, 0); $probe.Start(); $port = $probe.LocalEndpoint.Port; $probe.Stop()
  $srv = Start-Child "-File `"$serve`" -NoBrowser -From `"$snapPath`""
  $url = $srv.StandardOutput.ReadLine()
  # Edge starts with the real USERPROFILE: with it redirected, Edge never opens its DevTools port (checked on this machine). Its state
  # lives in the run folder (--user-data-dir); the server child keeps the redirected profile and its own TILE_HOME.
  $env:USERPROFILE = $saved.USERPROFILE
  try { $edgeProc = Start-Process $edge -PassThru -WindowStyle Hidden -ArgumentList '--headless', '--disable-gpu', '--no-first-run', "--remote-debugging-port=$port", "--user-data-dir=$edgeProfile", '--host-resolver-rules="MAP fonts.googleapis.com 0.0.0.0, MAP fonts.gstatic.com 0.0.0.0"', 'about:blank' } finally { $env:USERPROFILE = $prof }

  # The page target: DevTools answers once Edge is up. A wait on that answer, not a sleep.
  $targets = @(); $t0 = Get-Date; $lastErr = ''
  while (-not $targets.Count -and ((Get-Date) - $t0).TotalSeconds -lt 60) {
    try { $raw = (Invoke-WebRequest -UseBasicParsing "http://127.0.0.1:$port/json/list").Content; $targets = @(($raw | ConvertFrom-Json) | ? { $_.type -eq 'page' }) } catch { $lastErr = $_.Exception.Message }
    if (-not $targets.Count) { Start-Sleep -Milliseconds 250 }
  }
  if (-not $targets.Count) { throw "DevTools listed no page on port $port within 60 s: $lastErr" }
  $ws = New-Object Net.WebSockets.ClientWebSocket
  [void]$ws.ConnectAsync([Uri]$targets[0].webSocketDebuggerUrl, [Threading.CancellationToken]::None).GetAwaiter().GetResult()

  Case 'a board edit sends one POST /layout for the plugged-in setup' {
    Put-Config (New-Config)
    $opened = Open-Page $ws $url 'focus'
    Check 'the page opens on Focus (control)' $opened 'the page did not open on Focus in time'
    $p = Board-Edit $ws 1001
    $lay = @($p.layout)
    Check 'a board edit sends one POST /layout' ($lay.Count -eq 1) "POST /layout count: $($lay.Count)"
    Check 'the POST /layout carries the plugged-in setup key' ($lay.Count -eq 1 -and ((ConvertFrom-Json $lay[0].body).key -ceq $plugKey)) "key sent: $(if ($lay.Count -eq 1) { (ConvertFrom-Json $lay[0].body).key } else { 'no POST /layout' })"
    Check 'a board edit sends no POST /config' (@($p.config).Count -eq 0) "POST /config count: $(@($p.config).Count)"
  }

  Case 'Undo writes the layout back with one more POST /layout' {
    Put-Config (New-Config)
    $opened = Open-Page $ws $url 'focus'
    Check 'the page opens on Focus (control)' $opened 'the page did not open on Focus in time'
    $pre = Js $ws 'return layoutOf(work.focus)'   # the layout the page shows before the edit: the one Undo must write back
    [void](Board-Edit $ws 1001)
    $p = Js $ws 'document.getElementById("undo").click(); await window.__h.settle(); return { layout: window.__h.posts("layout") }'
    $lay = @($p.layout)
    Check 'Undo sends one more POST /layout (two in all)' ($lay.Count -eq 2) "POST /layout count after Undo: $($lay.Count)"
    $restored = $false
    if ($lay.Count -eq 2) { $restored = (Canon (ConvertFrom-Json $lay[1].body).layout) -ceq (Canon $pre) }
    Check 'Undo writes the layout back as it was before the edit' $restored 'the layout Undo sent is not the one from before the edit'
  }

  Case 'a window pinned to an unplugged monitor is listed as unplaced, with its reason' {
    $cfg = New-Config; Add-Layout $cfg 'focus' $plugKey $focusOwn; Put-Config $cfg
    $opened = Open-Page $ws $url 'focus'
    Check 'the page opens on Focus (control)' $opened 'the page did not open on Focus in time'
    $entry = Js $ws 'const e = [...document.querySelectorAll("[data-bay]")].find(x => x.dataset.bay === "1001"); return e ? (e.getAttribute("aria-label") || "") : null'
    Check 'window 1001 is listed in Windows That Stay Put' ($null -ne $entry) 'no entry for window 1001 in Windows That Stay Put'
    Check 'its entry says "Its screen is unplugged"' ([string]$entry -like '*Its screen is unplugged*') "entry label: '$entry'"
  }

  Case 'after a layout-only edit the inspector has no Revert and Save is off' {
    Put-Config (New-Config)
    $opened = Open-Page $ws $url 'focus'
    Check 'the page opens on Focus (control)' $opened 'the page did not open on Focus in time'
    [void](Board-Edit $ws 1001)
    $ins = Js $ws 'const sv = document.getElementById("save"); const rv = [...document.querySelectorAll("#scenebox button")].find(b => /revert/i.test(b.textContent)); const why = document.getElementById("whyoff"); return { save: !!sv, saveOff: !!sv && sv.disabled, revert: !!rv, text: (why ? why.textContent : "") + " " + (sv ? (sv.title || "") : "") }'
    Check 'the inspector has a Save button (scope)' ($ins.save -eq $true) 'no Save button in the inspector'
    Check 'the inspector has no Revert button' ($ins.revert -ne $true) 'a Revert button is in the inspector'
    Check 'Save is off after a layout-only edit' ($ins.saveOff -eq $true) 'Save is on after a layout-only edit'
    Check 'Save says "No name or trigger changes to save"' ([string]$ins.text -like '*No name or trigger changes to save*') "text beside Save: '$($ins.text)'"
  }

  Case 'a scene card says whose layout it shows: follows a setup, or its own layout' {
    $cfg = New-Config
    Add-Member -InputObject $cfg.setups -NotePropertyName 'L1|U1' -NotePropertyValue ([pscustomobject]@{ name = 'Laptop + Ultrawide'; ids = @('L1', 'U1'); lastUsed = '2026-11-16T09:00:00' })
    Add-Layout $cfg 'meetings' 'L1|U1' $meetLayout
    Add-Layout $cfg 'focus' $plugKey $focusOwn
    Put-Config $cfg
    $opened = Open-Page $ws $url 'focus'
    Check 'the page opens on Focus (control)' $opened 'the page did not open on Focus in time'
    $cards = Js $ws 'const card = id => { const b = [...document.querySelectorAll("[data-pick]")].find(x => x.dataset.pick === id); const a = b && b.closest("article.card"); return a ? a.textContent.replace(/\s+/g, " ") : null }; return { meetings: card("meetings"), focus: card("focus") }'
    Check 'the Meetings card is on the page (scope)' ($null -ne $cards.meetings) 'no Meetings card'
    Check 'the Meetings card says it follows Laptop + Ultrawide' ([string]$cards.meetings -match 'follows Laptop \+ Ultrawide') "card text: '$($cards.meetings)'"
    Check 'the Focus card is on the page (scope)' ($null -ne $cards.focus) 'no Focus card'
    Check 'the Focus card says own layout' ([string]$cards.focus -match 'own layout') "card text: '$($cards.focus)'"
  }

  Case 'a board edit on a built-in scene autosaves its layout' {
    Put-Config (New-Config)
    $opened = Open-Page $ws $url 'default'
    Check 'the page opens on Default (control)' $opened 'the page did not open on Default in time'
    $p = Board-Edit $ws 1001
    $lay = @($p.layout)
    Check 'a board edit on Default sends one POST /layout' ($lay.Count -eq 1) "POST /layout count: $($lay.Count)"
    $body = if ($lay.Count -eq 1) { ConvertFrom-Json $lay[0].body }
    Check 'that POST /layout names Default and the plugged-in setup key' ($null -ne $body -and $body.scene -ceq 'default' -and $body.key -ceq $plugKey) "sent: $(if ($body) { "scene $($body.scene), key $($body.key)" } else { 'no POST /layout' })"
    Check 'a board edit on Default sends no POST /config' (@($p.config).Count -eq 0) "POST /config count: $(@($p.config).Count)"
  }

  # A save the server refuses with 409 (the setup changed after the edit): the strip says so and offers no retry under the old key.
  Case 'a layout save refused with 409 (the setup changed) leaves the strip amber, with Refresh, and no retry under the old key' {
    Put-Config (New-Config)
    $opened = Open-Page $ws $url 'focus'
    Check 'the page opens on Focus (control)' $opened 'the page did not open on Focus in time'
    Plug $snapBText
    $p = Board-Edit $ws 1001
    $sent = @(Posts-Under $p.layout $plugKey)
    Check 'the edit sends its POST /layout under the setup the page holds (control)' ($sent.Count -eq 1) "POST /layout under $($plugKey): $($sent.Count)"
    $bar = Js $ws $stripJs
    Check 'the strip is on the page (scope)' ($null -ne $bar -and -not $bar.hidden) 'the strip is missing or hidden'
    Check 'the strip is amber after the refused save (control)' ($null -ne $bar -and $bar.warn -eq $true) 'the strip is not amber'
    Check 'the strip says the setup changed' ([string]$bar.text -match 'changed') "strip text: '$($bar.text)'"
    Check 'the strip has a Refresh control' (@($bar.buttons | ? { $_ -ceq 'Refresh' }).Count -eq 1) "strip buttons: $(@($bar.buttons) -join ', ')"
    Check 'the strip has no Try Again control' (@($bar.buttons | ? { $_ -match 'Try Again' }).Count -eq 0) "strip buttons: $(@($bar.buttons) -join ', ')"
    # Press the strip's own button (Try Again on the old page, which resends the old key). No POST /layout may go under the old key after the 409.
    [void](Js $ws 'const b = document.querySelector("#setbar button"); if (b) b.click(); await window.__h.settle(); return true')
    $after = Js $ws 'return { layout: window.__h.posts("layout") }'
    $again = @(Posts-Under $after.layout $plugKey)
    Check 'no POST /layout under the old setup key after the 409' ($again.Count -eq 1) "POST /layout under the old key: $($again.Count)"
  }

  # Refresh reads the windows again and clears Undo. A board change made on the old setup is not undone onto the new one.
  Case 'Refresh onto a new setup: Undo sends no POST /layout under the new key carrying the old layout' {
    Put-Config (New-Config)
    $opened = Open-Page $ws $url 'focus'
    Check 'the page opens on Focus (control)' $opened 'the page did not open on Focus in time'
    $preCanon = Canon (Js $ws 'return layoutOf(work.focus)')
    [void](Board-Edit $ws 1001)
    Plug $snapBText
    [void](Js $ws 'await document.getElementById("refresh").onclick(); await window.__h.settle(); return true')
    $now = Js $ws 'return plug.key'
    Check 'Refresh moved the page onto the new setup (control)' ($now -ceq 'P1|U1') "plug key: $now"
    [void](Js $ws 'await document.getElementById("undo").onclick(); await window.__h.settle(); return true')
    $log = Js $ws 'return { layout: window.__h.posts("layout") }'
    $carried = @(Posts-Carrying $log.layout 'P1|U1' $preCanon)
    Check 'Undo after Refresh sends no POST /layout under the new key carrying the old layout' ($carried.Count -eq 0) "POSTs carrying the old layout under the new key: $($carried.Count)"
  }

  # Apply on a live server moves windows and re-reads the setup. Every -From server is a dry run, which does not re-read, so this case
  # answers the scene call as a live one would (its placed notes stop saying dry run). The page's own code does the rest.
  Case 'Apply onto a new setup: Undo sends no POST /layout under the new key carrying the old layout' {
    Put-Config (New-Config)
    $opened = Open-Page $ws $url 'focus'
    Check 'the page opens on Focus (control)' $opened 'the page did not open on Focus in time'
    $preCanon = Canon (Js $ws 'return layoutOf(work.focus)')
    [void](Board-Edit $ws 1001)
    Plug $snapBText
    [void](Js $ws 'const g = window.fetch; window.fetch = async (u, o) => { const r = await g(u, o); if (String(u) !== "scene" || !r.ok) return r; const j = await r.json(); for (const p of j.placed || []) if (/^dry run/.test(p.note || "")) p.note = "moved"; return new Response(JSON.stringify(j), { status: 200, headers: { "Content-Type": "application/json" } }) }; return true')
    [void](Js $ws 'await document.getElementById("apply").onclick(); await window.__h.settle(); return true')
    $now = Js $ws 'return plug.key'
    Check 'Apply moved the page onto the new setup (control)' ($now -ceq 'P1|U1') "plug key: $now"
    [void](Js $ws 'for (let i = 0; i < 3; i++) { await document.getElementById("undo").onclick(); await window.__h.settle(); } return true')
    $log = Js $ws 'return { layout: window.__h.posts("layout") }'
    $carried = @(Posts-Carrying $log.layout 'P1|U1' $preCanon)
    Check 'Undo after Apply sends no POST /layout under the new key carrying the old layout' ($carried.Count -eq 0) "POSTs carrying the old layout under the new key: $($carried.Count)"
  }

  # Autosave writes the layout as the server has it. A Windows That Stay Put entry and a held fill entry, both for closed windows, are kept.
  $keepLayout = '{"grids":{"U1":{"c":4,"r":3}},"pins":[],"zones":[],"fill":{"mon":"U1","apps":[],"skip":[],"sort":"app","held":[{"app":"slack","title":"Huddle","mon":"U1","slots":[0]},{"app":"teams-old","title":"Standup","mon":"U1","slots":[1]}]},"bay":[{"app":"slack","title":"Huddle"},{"app":"teams-old","title":"Standup"}]}'
  Case 'a board edit saves the Windows That Stay Put and held entries of closed windows as the server had them' {
    $cfg = New-Config; Add-Layout $cfg 'focus' $plugKey $keepLayout; Put-Config $cfg
    $opened = Open-Page $ws $url 'focus'
    Check 'the page opens on Focus (control)' $opened 'the page did not open on Focus in time'
    $stored = Js $ws 'const c = await (await fetch("config", { cache: "no-store" })).json(); return c.scenes.find(s => s.id === "focus").layouts["L1|P1|U1"]'
    Check 'the server holds two Windows That Stay Put entries and two held entries (scope)' (@($stored.bay).Count -eq 2 -and @($stored.fill.held).Count -eq 2) "bay: $(@($stored.bay).Count), held: $(@($stored.fill.held).Count)"
    $p = Board-Edit $ws 1001
    $sent = @(Posts-Under $p.layout $plugKey)
    Check 'the edit sends one POST /layout under the plugged-in setup (control)' ($sent.Count -eq 1) "POST /layout under the key: $($sent.Count)"
    $body = if ($sent.Count -eq 1) { (ConvertFrom-Json $sent[0].body).layout }
    Check 'the POST /layout keeps the Windows That Stay Put entries as the server had them' ($null -ne $body -and (Canon $body.bay) -ceq (Canon $stored.bay)) "bay sent: $(if (-not $body) { 'no POST /layout' } elseif ($null -eq $body.bay) { 'no bay' } else { Canon $body.bay })"
    Check 'the POST /layout keeps the held entries of the closed windows as the server had them' ($null -ne $body -and (Canon $body.fill.held) -ceq (Canon $stored.fill.held)) "held sent: $(if (-not $body) { 'no POST /layout' } elseif ($null -eq $body.fill -or $null -eq $body.fill.held) { 'no held' } else { Canon $body.fill.held })"
  }

  # A re-read whose GET /layouts or GET /config fails: the strip says so in amber, instead of showing the old copy as if it were current.
  function Fail-Read($sock, [string]$route) {
    [void](Js $sock ('const f = window.fetch; window.fetch = (u, o) => String(u) === "__R__" ? Promise.resolve(new Response("read failed", { status: 500 })) : f(u, o); await document.getElementById("refresh").onclick(); await window.__h.settle(); return true'.Replace('__R__', $route)))
  }
  Case 'a failed GET /layouts on a re-read leaves the strip amber, with a message' {
    Put-Config (New-Config)
    $opened = Open-Page $ws $url 'focus'
    Check 'the page opens on Focus (control)' $opened 'the page did not open on Focus in time'
    Fail-Read $ws 'layouts'
    $bar = Js $ws $stripJs
    Check 'the strip is on the page (scope)' ($null -ne $bar -and -not $bar.hidden) 'the strip is missing or hidden'
    Check 'the strip is amber after a failed GET /layouts' ($null -ne $bar -and $bar.warn -eq $true) "strip text: '$($bar.text)'"
    Check 'the strip says the read failed' ([string]$bar.text -match 'could not|couldn.t|failed|did not|didn.t|unable|not read') "strip text: '$($bar.text)'"
  }
  Case 'a failed GET /config on a re-read leaves the strip amber, with a message' {
    Put-Config (New-Config)
    $opened = Open-Page $ws $url 'focus'
    Check 'the page opens on Focus (control)' $opened 'the page did not open on Focus in time'
    Fail-Read $ws 'config'
    $bar = Js $ws $stripJs
    Check 'the strip is on the page (scope)' ($null -ne $bar -and -not $bar.hidden) 'the strip is missing or hidden'
    Check 'the strip is amber after a failed GET /config' ($null -ne $bar -and $bar.warn -eq $true) "strip text: '$($bar.text)'"
    Check 'the strip says the read failed' ([string]$bar.text -match 'could not|couldn.t|failed|did not|didn.t|unable|not read') "strip text: '$($bar.text)'"
  }

  # Delete a scene whose save was refused: the strip must not keep the deleted scene's save state.
  Case 'deleting a scene whose save was refused clears the strip' {
    Put-Config (New-Config)
    $opened = Open-Page $ws $url 'focus'
    Check 'the page opens on Focus (control)' $opened 'the page did not open on Focus in time'
    Plug $snapBText
    [void](Board-Edit $ws 1001)
    $before = Js $ws $stripJs
    Check 'the strip is amber before the delete (control)' ($null -ne $before -and $before.warn -eq $true) 'the strip is not amber before the delete'
    [void](Delete-Scene $ws 'focus')
    $after = Js $ws $stripJs
    Check 'the strip is clear after the delete' ($null -ne $after -and $after.warn -ne $true) "strip text: '$($after.text)'"
  }

  # Delete a scene whose save is still in flight. The save's answer (a 409 here) comes after the delete and must not bring the strip back.
  Case 'deleting a scene whose save is in flight: its late refusal leaves the strip clear' {
    Put-Config (New-Config)
    $opened = Open-Page $ws $url 'focus'
    Check 'the page opens on Focus (control)' $opened 'the page did not open on Focus in time'
    # Holds every POST /layout until the test opens the gate.
    [void](Js $ws 'window.__gate = new Promise(r => { window.__open = r }); const g = window.fetch; window.fetch = (u, o) => String(u) === "layout" && o && String(o.method || "").toUpperCase() === "POST" ? window.__gate.then(() => g(u, o)) : g(u, o); return true')
    [void](Board-Edit $ws 1001)
    $inFlight = WaitFor $ws 'svBusy["focus"] === true'
    Check 'the save is in flight when the delete starts (control)' $inFlight 'no save in flight'
    [void](Delete-Scene $ws 'focus')
    $stillBusy = Js $ws 'return svBusy["focus"] === true'
    Check 'the save is still in flight after the delete (control)' ($stillBusy -eq $true) 'the save ended before the delete'
    Plug $snapBText
    $mid = Js $ws $stripJs
    Check 'the strip is clear while the save is in flight' ($null -ne $mid -and $mid.warn -ne $true) "strip text: '$($mid.text)'"
    [void](Js $ws 'window.__open(); return true')
    [void](WaitFor $ws 'window.__h.posts("layout").length === 1 && svBusy["focus"] === false')
    $after = Js $ws $stripJs
    Check 'the late refusal leaves the strip clear' ($null -ne $after -and $after.warn -ne $true) "strip text: '$($after.text)'"
  }

  # The strip's Monitors and Setups button opens a dialog listing each monitor and setup in a name field. Empty state first: only the
  # plugged-in monitors and Desk. Forget is off for each plugged-in monitor and for the setup in use, and each off Forget names its reason.
  Case 'Monitors and Setups: the strip button opens a dialog that lists the plugged-in monitors and the setup, with Forget off for them' {
    Put-Config (New-Config)
    $opened = Open-Page $ws $url 'focus'
    Check 'the page opens on Focus (control)' $opened 'the page did not open on Focus in time'
    $st = Open-Dialog $ws
    Check 'the strip has a Monitors and Setups button that opens a dialog (scope)' ($st -eq 'open') $(if ($st -eq 'nobutton') { 'no Monitors and Setups button in the strip' } else { 'no Monitors and Setups dialog after the click' })
    if ($st -eq 'open') {
      $r = Dlg-Rows $ws @('Laptop', 'Portrait', 'Ultrawide', 'Desk')
      $unlisted = @($r | ? { -not $_.row } | % { $_.n })
      Check 'the dialog lists each plugged-in monitor and the setup in use, each in a name field' ($unlisted.Count -eq 0) "not listed: $($unlisted -join ', ')"
      $forgetOn = @($r | ? { $_.row -and -not $_.off } | % { $_.n })
      Check 'Forget is off for each plugged-in monitor and for the setup in use' ($forgetOn.Count -eq 0) "Forget on for: $($forgetOn -join ', ')"
      $noReason = @($r | ? { $_.row -and $_.off -and $_.reason -notmatch 'plugged|in use' } | % { $_.n })
      Check 'each off Forget names its reason, tied to the button' ($noReason.Count -eq 0) "no reason for: $($noReason -join ', ')"
    }
  }

  # Full state: an unplugged monitor (Home 27) and the setup Home, made of two monitors that are not plugged in (Home 27 and Home 28). Forget is
  # on for both; the plugged-in rows stay off. (Home holds no plugged-in monitor: a setup that holds one cannot be forgotten, ruling 21:04 CST.)
  Case 'Monitors and Setups: an unplugged monitor and its setup are listed, with Forget on for them' {
    $cfg = New-Config
    $cfg.monitors | Add-Member -NotePropertyName 'H27' -NotePropertyValue ([pscustomobject]@{ name = 'Home 27'; builtin = $false; lastSeen = $stamp; bw = 2560; bh = 1440 })
    $cfg.monitors | Add-Member -NotePropertyName 'H28' -NotePropertyValue ([pscustomobject]@{ name = 'Home 28'; builtin = $false; lastSeen = $stamp; bw = 2560; bh = 1440 })
    $cfg.setups | Add-Member -NotePropertyName 'H27|H28' -NotePropertyValue ([pscustomobject]@{ name = 'Home'; ids = @('H27', 'H28'); lastUsed = $stamp })
    Put-Config $cfg
    $opened = Open-Page $ws $url 'focus'
    Check 'the page opens on Focus with the unplugged monitors known (control)' $opened 'the page did not open on Focus in time'
    $st = Open-Dialog $ws
    Check 'the strip has a Monitors and Setups button that opens a dialog (scope)' ($st -eq 'open') $(if ($st -eq 'nobutton') { 'no Monitors and Setups button in the strip' } else { 'no Monitors and Setups dialog after the click' })
    if ($st -eq 'open') {
      $r = Dlg-Rows $ws @('Laptop', 'Portrait', 'Ultrawide', 'Desk', 'Home 27', 'Home 28', 'Home')
      $unlisted = @($r | ? { -not $_.row } | % { $_.n })
      Check 'the dialog lists the unplugged Home 27 and Home 28 and the setup Home, each in a name field' ($unlisted.Count -eq 0) "not listed: $($unlisted -join ', ')"
      $plugOn = @($r | ? { $_.n -in @('Laptop', 'Portrait', 'Ultrawide', 'Desk') -and $_.row -and -not $_.off } | % { $_.n })
      Check 'Forget stays off for each plugged-in monitor and for the setup in use' ($plugOn.Count -eq 0) "Forget on for: $($plugOn -join ', ')"
      $unplugOff = @($r | ? { $_.n -in @('Home 27', 'Home 28', 'Home') -and $_.row -and $_.off } | % { $_.n })
      Check 'Forget is on for Home 27, Home 28 and the setup Home, which are not plugged in or in use' ($unplugOff.Count -eq 0) "Forget off for: $($unplugOff -join ', ')"
    }
  }

  # A monitor whose id is a size (size-WxH, tile.ps1 Get-MonitorIdentity: a monitor with no device) is remembered by that id (decision
  # monitor-setups item 3, coordinator ruling 21:04 CST). So the strip is the normal one, and no Remember It by Its Size button is on the page.
  # Both shapes: every monitor with a size id, and only the ultrawide.
  Case 'size id: a snapshot whose monitors carry size ids shows the normal strip, with no Remember It by Its Size button anywhere' {
    Put-Config (New-Config)
    foreach ($v in @(@{ label = 'every monitor'; text = $sizeAll }, @{ label = 'one monitor, the ultrawide'; text = $sizeOne })) {
      $opened = Open-Page $ws $url 'focus' $v.text
      Check "size id ($($v.label)): the page opens on Focus (control)" $opened 'the page did not open on Focus in time'
      if (-not $opened) { continue }
      $shown = WaitFor $ws '!document.getElementById("setbar").hidden' 20
      Check "size id ($($v.label)): the strip is shown (scope)" $shown 'the strip stays hidden for a snapshot with size ids'
      if (-not $shown) { continue }
      $bar = Js $ws $stripJs
      Check "size id ($($v.label)): the strip is not amber" ($bar.warn -ne $true) "strip text: '$($bar.text)'"
      $remembers = Js $ws 'return [...document.querySelectorAll("button")].filter(b => /Remember It by Its Size/.test(b.textContent)).length'
      Check "size id ($($v.label)): no Remember It by Its Size button anywhere on the page" ($remembers -eq 0) "buttons with that name: $remembers"
    }
  }

  Case 'the offline page loads its sample and a board edit sends no POST' {
    $fileUrl = ([Uri]$appHtml).AbsoluteUri
    $loaded = Go $ws $fileUrl 'typeof snap !== "undefined" && !!snap && /^Offline/.test(document.getElementById("msg").textContent)'
    Check 'the offline page loads its sample' $loaded 'the offline sample did not load in time'
    if ($loaded) {
      [void](Js $ws $installJs)
      $p = Js $ws 'pinWin(snap.windows[0].id, snap.monitors.find(m => m.role === "wide"), 9); await window.__h.settle(); return { all: window.__posts }'
      Check 'a board edit on the offline page sends no POST' (@($p.all).Count -eq 0) "POSTs sent: $(@($p.all).Count)"
    }
  }

  # The offline page has no setup strip, so no Monitors and Setups button, and it sends no request: not while it loads, not after.
  # The recorder is installed before the page's scripts run, so a request made during the load is in the list.
  Case 'the offline page shows no Monitors and Setups button, and sends no request' {
    $pre = Cdp $ws 'Page.addScriptToEvaluateOnNewDocument' @{ source = $recordJs }
    $preId = $pre.result.identifier
    try {
      $loaded = Go $ws ([Uri]$appHtml).AbsoluteUri 'typeof snap !== "undefined" && !!snap && /^Offline/.test(document.getElementById("msg").textContent)'
      Check 'the offline page loads its sample (scope)' $loaded 'the offline sample did not load in time'
      if ($loaded) {
        $o = Js $ws 'const shown = [...document.querySelectorAll("button")].filter(x => /Monitors and Setups/.test(x.textContent + " " + (x.getAttribute("aria-label") || "") + " " + (x.title || "")) && x.getClientRects().length > 0); return { shown: shown.length, sent: window.__sent || [] }'
        Check 'the offline page shows no Monitors and Setups button' ($o.shown -eq 0) "shown: $($o.shown)"
        Check 'the offline page sends no request, while it loads or after' (@($o.sent).Count -eq 0) "sent: $(@($o.sent) -join ' | ')"
      }
    } finally { if ($preId) { [void](Cdp $ws 'Page.removeScriptToEvaluateOnNewDocument' @{ identifier = $preId }) } }
  }
} catch {
  $script:fail++; "FAIL  page cases stopped: $($_.Exception.Message)"
} finally {
  try { if ($ws) { $ws.Dispose() } } catch { }
  if ($edgeProc) { Get-CimInstance Win32_Process -Filter "Name='msedge.exe'" | ? { $_.CommandLine -like "*$edgeProfile*" } | % { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue } }
  if ($srv -and -not $srv.HasExited) {
    try { [void](Invoke-WebRequest -UseBasicParsing "$($url)quit" -Method Post -Body 'quit') } catch { }
    if (-not $srv.WaitForExit(5000)) { $srv.Kill() }
  }
  foreach ($k in $saved.Keys) { if ($null -eq $saved[$k]) { Remove-Item "env:$k" -ErrorAction SilentlyContinue } else { Set-Item "env:$k" $saved[$k] } }
  Remove-Item -LiteralPath $runDir -Recurse -Force -ErrorAction SilentlyContinue
}
if ($script:fail) { "$($script:fail) check(s) failed."; exit 1 } else { 'All checks passed.' }
