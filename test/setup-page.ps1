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
# The unplugged and offline cases already hold on the old page (the engine lists the unplugged window, and the offline page never
# posts): they are guards that the builder must keep green. The other cases are red on the old page.
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
# Opens the live page on a scene: the card is clicked, as a user would.
function Open-Page($sock, [string]$url, [string]$scene) {
  if (-not (Go $sock $url $livePageReady)) { return $false }
  [void](Js $sock $installJs)
  [void](Js $sock ('document.querySelector("[data-pick=__S__]").click(); return true'.Replace('__S__', $scene)))
  WaitFor $sock ('selId === "__S__"'.Replace('__S__', $scene))
}
# One board edit: window 1001 pinned to a cell of the wide monitor. Returns the POSTs it sent to /layout and /config.
function Board-Edit($sock, [int]$id, [int]$slot = 9) {
  Js $sock ('pinWin(__ID__, snap.monitors.find(m => m.role === "wide"), __SLOT__); await preview(selId); await window.__h.settle(); return { layout: window.__h.posts("layout"), config: window.__h.posts("config") }'.Replace('__ID__', "$id").Replace('__SLOT__', "$slot"))
}

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
    $pre = Js $ws 'const r = await fetch("layouts", { cache: "no-store" }); return await r.json()'
    [void](Board-Edit $ws 1001)
    $p = Js $ws 'document.getElementById("undo").click(); await window.__h.settle(); return { layout: window.__h.posts("layout") }'
    $lay = @($p.layout)
    Check 'Undo sends one more POST /layout (two in all)' ($lay.Count -eq 2) "POST /layout count after Undo: $($lay.Count)"
    $restored = $false
    if ($lay.Count -eq 2) { $restored = (Canon (ConvertFrom-Json $lay[1].body).layout) -ceq (Canon $pre.focus) }
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
