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
#     is the text its aria-describedby names. Nothing else is greyed (coordinator ruling 21:33 CST). Two
#     states: plugged-in only (empty), and with an unplugged monitor and its setup (full).
#     The server's refusals (409, setup-plumbing.ps1) are not checked here.
#   Size id (item 3, coordinator ruling 21:04 CST): a monitor whose id is size-WxH is remembered by that id. The strip is the normal one, and
#     no Remember It by Its Size button is on the page. Two shapes: every monitor with a size id, and only the ultrawide.
#   Monitors and Setups, reads and names: a rename that returns keeps the text typed in another name field; a forget answered 200 whose config
#     re-read fails says it was forgotten, shows the failed read, and never says Could not forget; a rename that landed whose re-read fails
#     shows the failed read; the Monitor picker shows a renamed monitor once its inspector Name field is left; the built-in monitor reads
#     Built-in screen, with no maker or product code (dialog and inspector).
#   Monitors and Setups, a forget of a scene's setup: the forget turns that scene's setup switch off on the server, and the page takes it. The
#     card of the scene shows its switch off with no reload, a Save of another scene writes the switch off to config.json, and the pick-a-setup note
#     the forget answered shows on the page. With one scene aimed at the forgotten setup, the note does not say each of them, and the
#     footer does not repeat the note.
#   Offline, dialog: the offline page shows no Monitors and Setups button and sends no request. A guard: green on the old commit, and a
#     mutant with the button turns it red (run on a scratch copy).
#   Card menu (Follow Again, decision monitor-setups item 7; mockup cd-own): a scene with its own layout on the plugged setup offers
#     "Follow <closest setup> Again" in its card's menu, opened by the card's More button. A scene that follows another setup offers none.
#     Choosing it sends one POST /layout/remove for the plugged key, and the card then says it follows that setup. Undo sends one POST
#     /layout with the own layout as it was, and the card says own layout again. The offline page shows no such item and sends no POST.
#     The Meetings menu check and the offline item check are guards: they hold on the page as it stands.
#     Follow Again in flight (each case holds one request or one answer, then acts): an edit during the remove POST sends no POST /layout;
#     the key and name are read when the item is chosen, so a setup change during the flush removes nothing on the new setup; Undo is not
#     offered after the setup changed, nor is its toast Undo; a failed GET /layouts after the remove leaves the board not showing the removed
#     layout as saved; Enter on the item leaves focus on a control on the card; Tab from the open menu never leaves it open with focus outside.
#     The autosave flush before the remove is a guard: a mutant with the flush removed turns it red.
#   Card menu placement: at 1440 wide, a menu opened from a More button with no room below opens above
#     it and covers neither More nor Preview. With room below it opens below and covers neither (control).
#   Undo after a follow: the footer stops saying the scene follows a setup; the strip and card show its own layout.
#   Kind icons (decision monitor-setups, item 25; mockup card-kind-icon.html): each card shows its kind as one svg icon titled and labelled
#     Built-in, Custom or Not saved, and no kind word is on screen. An edited scene shows one amber dot in its bottom row, with a title or label
#     that says edited. At 1024 and 1440 no card's bottom-row label is cut, and at 1024 every card has one height.
# Guards: they hold on the page as it stands, and a mutant on a scratch copy turns each red. They are the unplugged, offline, Refresh
# clears Undo, delete, size id, and Could not forget cases.
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
# The config as it is on disk, read after the server has written it.
function Read-Config { [IO.File]::ReadAllText((Join-Path $tileHome 'config.json'), $utf8) | ConvertFrom-Json }
# The setup Office: one unplugged monitor (O9) in a setup of its own. Focus is aimed at it with its setup switch on. The Office cases forget it.
function Office-Config {
  $cfg = New-Config
  $cfg.monitors | Add-Member -NotePropertyName 'O9' -NotePropertyValue ([pscustomobject]@{ name = 'Office 24'; builtin = $false; lastSeen = $stamp; bw = 1920; bh = 1080 })
  $cfg.setups | Add-Member -NotePropertyName 'O9' -NotePropertyValue ([pscustomobject]@{ name = 'Office'; ids = @('O9'); lastUsed = $stamp })
  $sc = @($cfg.scenes | ? { $_.id -eq 'focus' })[0]
  $sc.auto.setup = $true; $sc | Add-Member -Force -NotePropertyName setupKey -NotePropertyValue 'O9'
  $cfg
}
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
# Follow Again: Focus has its own layout on the plugged setup and a layout on Laptop + Ultrawide, the closest known setup, and so does Meetings,
# which therefore follows it (its card carries the mark). The menu item is named for that setup.
$lapUltraFocus = '{"grids":{"U1":{"c":2,"r":2}},"pins":[],"zones":[],"fill":{"mon":"U1","apps":[],"skip":[],"sort":"app"},"bay":[]}'
$followLabel = 'Follow Laptop + Ultrawide Again'
# The list in a reply, with no null entry: a reply of nothing (an empty JSON array) is an empty list, so a count of it is 0.
function Reply-List($x) { @($x | ? { $null -ne $_ }) }
function New-FollowConfig {
  $cfg = New-Config
  Add-Member -InputObject $cfg.setups -NotePropertyName 'L1|U1' -NotePropertyValue ([pscustomobject]@{ name = 'Laptop + Ultrawide'; ids = @('L1', 'U1'); lastUsed = '2026-11-16T09:00:00' })
  Add-Layout $cfg 'focus' 'L1|U1' $lapUltraFocus
  Add-Layout $cfg 'meetings' 'L1|U1' $meetLayout
  Add-Layout $cfg 'focus' $plugKey $focusOwn
  $cfg
}

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
  // The card menu as a user meets it: a card's More button, the Follow items on screen, and a card. An item's label is its first bold text, or its aria-label.
  window.__fa = {
    card: s => { const b = [...document.querySelectorAll("[data-pick]")].find(x => x.dataset.pick === s); return b ? b.closest("article.card") : null },
    more: s => { const c = window.__fa.card(s); return c ? ([...c.querySelectorAll("button:not([data-pick]):not([data-apply])")].find(x => /\bmore\b|\bmenu\b|⋯/i.test((x.getAttribute("aria-label") || "") + " " + (x.title || "") + " " + x.textContent.trim())) || null) : null },
    label: x => (x.getAttribute("aria-label") || (x.querySelector("b") || x).textContent).replace(/\s+/g, " ").trim(),
    items: () => [...document.querySelectorAll("button, [role=menuitem], a")].filter(x => x.getClientRects().length > 0 && /^Follow .+ Again$/.test(window.__fa.label(x))),
    item: t => [...document.querySelectorAll("button, [role=menuitem], a")].find(x => x.getClientRects().length > 0 && window.__fa.label(x) === t) || null
  };
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
# Clicks OK on the page's confirm dialog once it is open. The one home of that step: Delete-Scene and the dialog's Forget both use it.
function Confirm-Ask($sock) {
  [void](WaitFor $sock 'document.getElementById("dlg").open && !!document.querySelector("#dlgform button[value=ok]")')
  [void](Js $sock 'document.querySelector("#dlgform button[value=ok]").click(); return true')
}
# Deletes the scene on the page through its Delete button and the confirm dialog, and waits until its card is gone.
function Delete-Scene($sock, [string]$scene) {
  [void](Js $sock 'document.getElementById("del").click(); return true')
  Confirm-Ask $sock
  WaitFor $sock ('!document.querySelector("[data-pick=__S__]")'.Replace('__S__', $scene))
}
# The read-failure words a page message uses (the strip's and the dialog's). One home for the failed-read checks.
$readFailRx = 'could not|couldn.t|failed|did not|didn.t|unable|not read'

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
# The server's note (POST /note clears it). A forget leaves one in the run's TILE_HOME, and every later page load shows it, so a case clears it first.
function Dismiss-Note([string]$url) { try { [void](Invoke-WebRequest -UseBasicParsing "$($url)note" -Method Post -Body 'dismiss') } catch { } }
# Forgets the setup Office from the Monitors and Setups dialog, as a user does: its Forget, OK on the confirm, then the dialog says it was
# forgotten, and Done closes the dialog. Answers 'forgot', or the step that did not happen.
function Forget-Office($sock) {
  $st = Open-Dialog $sock
  if ($st -ne 'open') { return $st }
  if ((Js $sock 'const b = document.querySelector("#mgdlg button[data-fk=setup][data-fid=O9]"); if (!b) return false; b.click(); return true') -ne $true) { return 'norow' }
  Confirm-Ask $sock
  if (-not (WaitFor $sock '/Forgot Office/.test((document.getElementById("mgsay") || {}).textContent || "")' 30)) { return 'nosay' }
  [void](Js $sock 'document.getElementById("mgdone").click(); return true')
  if (-not (WaitFor $sock '!document.getElementById("mgdlg").open' 10)) { return 'noclose' }
  'forgot'
}
# The forget's note reaches the page through the dialog's close listener, a task after Done, so a read waits for it to show.
function Wait-ForgetNote($sock) { [void](WaitFor $sock '/A setup you forgot/.test(document.body.innerText)' 30) }
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
  # One route answers 500 to a GET until the page is reloaded. A POST to it still goes through, so a save is not failed by it.
  # window.__failedRead names the route once it answers 500. Fail-Read also asks for it through the page's refresh, unless -NoRefresh: the case asks.
  function Fail-Route($sock, [string]$route) {
    [void](Js $sock ('const f = window.fetch; window.fetch = (u, o) => String(u) === "__R__" && !(o && String(o.method || "").toUpperCase() === "POST") ? (window.__failedRead = "__R__", Promise.resolve(new Response("read failed", { status: 500 }))) : f(u, o); return true'.Replace('__R__', $route)))
  }
  function Fail-Read($sock, [string]$route, [switch]$NoRefresh) {
    Fail-Route $sock $route
    if (-not $NoRefresh) { [void](Js $sock 'await document.getElementById("refresh").onclick(); await window.__h.settle(); return true') }
  }
  Case 'a failed GET /layouts on a re-read leaves the strip amber, with a message' {
    Put-Config (New-Config)
    $opened = Open-Page $ws $url 'focus'
    Check 'the page opens on Focus (control)' $opened 'the page did not open on Focus in time'
    Fail-Read $ws 'layouts'
    $bar = Js $ws $stripJs
    Check 'the strip is on the page (scope)' ($null -ne $bar -and -not $bar.hidden) 'the strip is missing or hidden'
    Check 'the strip is amber after a failed GET /layouts' ($null -ne $bar -and $bar.warn -eq $true) "strip text: '$($bar.text)'"
    Check 'the strip says the read failed' ([string]$bar.text -match $readFailRx) "strip text: '$($bar.text)'"
  }
  Case 'a failed GET /config on a re-read leaves the strip amber, with a message' {
    Put-Config (New-Config)
    $opened = Open-Page $ws $url 'focus'
    Check 'the page opens on Focus (control)' $opened 'the page did not open on Focus in time'
    Fail-Read $ws 'config'
    $bar = Js $ws $stripJs
    Check 'the strip is on the page (scope)' ($null -ne $bar -and -not $bar.hidden) 'the strip is missing or hidden'
    Check 'the strip is amber after a failed GET /config' ($null -ne $bar -and $bar.warn -eq $true) "strip text: '$($bar.text)'"
    Check 'the strip says the read failed' ([string]$bar.text -match $readFailRx) "strip text: '$($bar.text)'"
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

  # Full state: an unplugged monitor (Home 27) and the setup Home, which holds it. Forget is on for both; the plugged-in rows stay off.
  # Home also holds the plugged-in laptop, but it is not the setup in use, so its Forget is on (coordinator ruling 21:33 CST).
  Case 'Monitors and Setups: an unplugged monitor and its setup are listed, with Forget on for them' {
    $cfg = New-Config
    $cfg.monitors | Add-Member -NotePropertyName 'H27' -NotePropertyValue ([pscustomobject]@{ name = 'Home 27'; builtin = $false; lastSeen = $stamp; bw = 2560; bh = 1440 })
    $cfg.setups | Add-Member -NotePropertyName 'H27|L1' -NotePropertyValue ([pscustomobject]@{ name = 'Home'; ids = @('H27', 'L1'); lastUsed = $stamp })
    Put-Config $cfg
    $opened = Open-Page $ws $url 'focus'
    Check 'the page opens on Focus with the unplugged monitor known (control)' $opened 'the page did not open on Focus in time'
    $st = Open-Dialog $ws
    Check 'the strip has a Monitors and Setups button that opens a dialog (scope)' ($st -eq 'open') $(if ($st -eq 'nobutton') { 'no Monitors and Setups button in the strip' } else { 'no Monitors and Setups dialog after the click' })
    if ($st -eq 'open') {
      $r = Dlg-Rows $ws @('Laptop', 'Portrait', 'Ultrawide', 'Desk', 'Home 27', 'Home')
      $unlisted = @($r | ? { -not $_.row } | % { $_.n })
      Check 'the dialog lists the unplugged Home 27 and the setup Home, each in a name field' ($unlisted.Count -eq 0) "not listed: $($unlisted -join ', ')"
      $plugOn = @($r | ? { $_.n -in @('Laptop', 'Portrait', 'Ultrawide', 'Desk') -and $_.row -and -not $_.off } | % { $_.n })
      Check 'Forget stays off for each plugged-in monitor and for the setup in use' ($plugOn.Count -eq 0) "Forget on for: $($plugOn -join ', ')"
      $unplugOff = @($r | ? { $_.n -in @('Home 27', 'Home') -and $_.row -and $_.off } | % { $_.n })
      Check 'Forget is on for Home 27 and for the setup Home, which are not plugged in or in use' ($unplugOff.Count -eq 0) "Forget off for: $($unplugOff -join ', ')"
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

  # A rename whose save returns while the user types in another name field of the dialog: the typed text is kept. The save is held until the
  # test releases it, so the typing happens while it is in flight. The rename is sent from the Laptop's field without focus, so the field the
  # test types in is the only one with focus. Its redraw is what the case checks.
  Case 'Monitors and Setups: a rename that returns while another name field holds typed text keeps that text' {
    Put-Config (New-Config)
    $opened = Open-Page $ws $url 'focus'
    Check 'the page opens on Focus (control)' $opened 'the page did not open on Focus in time'
    $st = Open-Dialog $ws
    Check 'the Monitors and Setups dialog opens (scope)' ($st -eq 'open') "dialog: $st"
    if ($st -ne 'open') { return }
    # Holds each rename POST (counted in __held) until the test opens the gate.
    [void](Js $ws 'window.__gate = new Promise(r => { window.__open = r }); const g = window.fetch; window.fetch = (u, o) => { if (String(u) !== "rename" || !o || String(o.method || "").toUpperCase() !== "POST") return g(u, o); window.__held = (window.__held || 0) + 1; return window.__gate.then(() => g(u, o)); }; return true')
    [void](Js $ws 'const a = document.querySelector("#mgdlg input[data-rk=monitor][data-rid=L1]"); a.value = "Built-in"; a.dispatchEvent(new Event("change", { bubbles: true })); return true')
    $held = WaitFor $ws 'window.__held === 1' 30
    Check 'the rename save is held in flight (control)' $held 'no rename POST was held'
    if (-not $held) { return }
    [void](Js $ws 'const b = document.querySelector("#mgdlg input[data-rk=setup]"); b.focus(); b.value = "Typed name"; b.dispatchEvent(new Event("input", { bubbles: true })); return true')
    [void](Js $ws 'window.__open(); return true')
    $replied = WaitFor $ws '/Renamed to/.test((document.getElementById("mgsay") || {}).textContent || "")' 30
    Check 'the rename returns once released (control)' $replied 'no "Renamed to" after the gate opened'
    $field = Js $ws 'const b = document.querySelector("#mgdlg input[data-rk=setup]"); return b ? b.value : null'
    Check 'the setup name field keeps the text typed while the rename was in flight' ([string]$field -ceq 'Typed name') "field now: '$field'"
  }

  # A forget the server answered 200 whose config re-read then fails: the forget landed, so the dialog says it was forgotten and shows the
  # failed read, and the strip goes amber. The dialog never says Could not forget for a forget that landed.
  Case 'Monitors and Setups: a forget answered 200 whose config re-read fails says it was forgotten, shows the failed read, and never says Could not forget' {
    $cfg = New-Config
    $cfg.monitors | Add-Member -NotePropertyName 'H27' -NotePropertyValue ([pscustomobject]@{ name = 'Home 27'; builtin = $false; lastSeen = $stamp; bw = 2560; bh = 1440 })
    Put-Config $cfg
    $opened = Open-Page $ws $url 'focus'
    Check 'the page opens on Focus with the unplugged monitor known (control)' $opened 'the page did not open on Focus in time'
    $st = Open-Dialog $ws
    Check 'the Monitors and Setups dialog opens (scope)' ($st -eq 'open') "dialog: $st"
    if ($st -ne 'open') { return }
    Fail-Route $ws 'config'
    [void](Js $ws 'document.querySelector("#mgdlg button[data-fk=monitor][data-fid=H27]").click(); return true')
    Confirm-Ask $ws
    [void](WaitFor $ws '/Could not forget|Forgot/.test((document.getElementById("mgsay") || {}).textContent || "")' 30)
    $text = Js $ws 'return (document.getElementById("mgsay") || {}).textContent.replace(/\s+/g, " ").trim()'
    $sent = Js $ws 'return window.__h.posts("forget").length'
    Check 'the forget was sent and answered (control)' ($sent -eq 1 -and [string]$text -notmatch '^\s*$') "POST /forget count: $sent, dialog: '$text'"
    Check 'a forget answered 200 whose config re-read fails: the dialog says the item was forgotten' ([string]$text -match 'Forgot Home 27') "dialog: '$text'"
    Check 'a forget answered 200 whose config re-read fails: the dialog shows the failed read' ([string]$text -match 'Could not read the names again') "dialog: '$text'"
    Check 'a forget answered 200 whose config re-read fails: the dialog does not say Could not forget' ([string]$text -notmatch 'Could not forget') "dialog: '$text'"
    $bar = Js $ws $stripJs
    Check 'a forget answered 200 whose config re-read fails: the strip is amber' ($null -ne $bar -and $bar.warn -eq $true) "strip text: '$($bar.text)'"
  }

  # A rename that landed, then a re-read of the config that fails: the dialog or the strip says the read failed. It is not swallowed.
  Case 'Monitors and Setups: a failed re-read after a rename that landed is shown, not swallowed' {
    Put-Config (New-Config)
    $opened = Open-Page $ws $url 'focus'
    Check 'the page opens on Focus (control)' $opened 'the page did not open on Focus in time'
    $st = Open-Dialog $ws
    Check 'the Monitors and Setups dialog opens (scope)' ($st -eq 'open') "dialog: $st"
    if ($st -ne 'open') { return }
    Fail-Route $ws 'config'
    [void](Js $ws 'const a = document.querySelector("#mgdlg input[data-rk=monitor][data-rid=U1]"); a.value = "Wide 49"; a.dispatchEvent(new Event("change", { bubbles: true })); return true')
    $answered = WaitFor $ws '/Renamed to|Could not rename/.test((document.getElementById("mgsay") || {}).textContent || "")' 30
    $dialog = Js $ws 'return (document.getElementById("mgsay") || {}).textContent.replace(/\s+/g, " ").trim()'
    $bar = Js $ws $stripJs
    $sent = Js $ws 'return window.__h.posts("rename").length'
    Check 'the rename was sent and landed (control)' ($answered -and $sent -eq 1 -and [string]$dialog -match 'Renamed to Wide 49') "POST /rename count: $sent, dialog: '$dialog'"
    $shown = ([string]$dialog -match $readFailRx) -or ([string]$bar.text -match $readFailRx)
    Check 'a failed re-read after the rename is shown in the dialog or the strip' $shown "dialog: '$dialog' | strip: '$($bar.text)'"
  }

  # An inspector Name field: a monitor renamed there shows its new name on the Monitor picker once the field is left. The picker is not
  # redrawn while the field has focus, so the change has to show when the field is left.
  Case 'the inspector: a monitor renamed in its Name field shows the new name on the Monitor picker once the field is left' {
    Put-Config (New-Config)
    $opened = Open-Page $ws $url 'focus'
    Check 'the page opens on Focus (control)' $opened 'the page did not open on Focus in time'
    [void](Js $ws 'const b = [...document.querySelectorAll("#mon [data-mon]")].find(x => x.textContent.trim() === "Ultrawide"); if (b) b.click(); return true')
    $picked = WaitFor $ws 'document.getElementById("monName") && document.getElementById("monName").value === "Ultrawide"' 20
    Check 'the Name field holds Ultrawide, the monitor picked (scope)' $picked 'no Name field for Ultrawide after the pick'
    if (-not $picked) { return }
    [void](Js $ws 'const f = document.getElementById("monName"); f.focus(); f.value = "Wide 49"; f.dispatchEvent(new Event("change", { bubbles: true })); return true')
    $saved = WaitFor $ws 'cfg.monitors.U1.name === "Wide 49"' 30
    Check 'the rename was saved to config (control)' $saved 'the monitor was not renamed in config'
    [void](Js $ws 'document.getElementById("monName").blur(); return true')
    $shown = WaitFor $ws '[...document.querySelectorAll(".seg[aria-label=Monitor] button")].some(b => b.textContent.trim() === "Wide 49")' 20
    $names = Js $ws 'return [...document.querySelectorAll(".seg[aria-label=Monitor] button")].map(b => b.textContent.trim())'
    Check 'the Monitor picker shows Wide 49 once the Name field is left' $shown "the picker shows: $($names -join ', ')"
  }

  # The dialog's monitor line and the inspector's line say what the monitor is in plain words: Built-in screen for the built-in one. They give
  # no maker or product code, though Windows reports one (the snapshot's maker and product, as tile.ps1 -Json gives them).
  Case 'Monitors and Setups and the inspector: the built-in monitor is named in plain words, with no maker or product code' {
    $withCodes = ConvertFrom-Json $snapAText
    $laptop = @($withCodes.monitors | ? { $_.id -eq 'L1' })[0]
    $laptop | Add-Member -Force -NotePropertyName maker -NotePropertyValue 'BOE'
    $laptop | Add-Member -Force -NotePropertyName product -NotePropertyValue '0A1F'
    Put-Config (New-Config)
    $opened = Open-Page $ws $url 'focus' (ConvertTo-Json -Depth 10 -Compress -InputObject $withCodes)
    Check 'the page opens on Focus with the maker and product in the snapshot (control)' $opened 'the page did not open on Focus in time'
    $st = Open-Dialog $ws
    Check 'the Monitors and Setups dialog opens (scope)' ($st -eq 'open') "dialog: $st"
    if ($st -eq 'open') {
      $det = Js $ws 'const i = document.querySelector("#mgdlg input[data-rk=monitor][data-rid=L1]"); const row = i && i.closest(".lrow"); const s = row && row.querySelector("small"); return s ? s.textContent.replace(/\s+/g, " ").trim() : null'
      Check 'the Laptop row has its detail line (scope)' ($null -ne $det -and [string]$det -ne '') "detail: '$det'"
      Check 'the dialog detail line says Built-in screen' ([string]$det -match 'Built-in screen') "detail: '$det'"
      Check 'the dialog detail line gives no maker or product code' ([string]$det -notmatch 'BOE|0A1F') "detail: '$det'"
      [void](Js $ws 'document.getElementById("mgdone").click(); return true')
      [void](WaitFor $ws '!document.getElementById("mgdlg").open' 10)
    }
    [void](Js $ws 'const b = [...document.querySelectorAll("#mon [data-mon]")].find(x => x.textContent.trim() === "Laptop"); if (b) b.click(); return true')
    $notes = Js $ws 'return [...document.querySelectorAll("#mon p.note")].map(p => p.textContent.replace(/\s+/g, " ").trim())'
    $line = @(@($notes) | ? { $_ -match 'pixels' })
    Check 'the inspector line for the Laptop is shown (scope)' ($line.Count -eq 1) "notes: $(@($notes) -join ' | ')"
    if ($line.Count -eq 1) {
      Check 'the inspector line says Built-in screen' ([string]$line[0] -match '(?i)built-in screen') "inspector: '$($line[0])'"
      Check 'the inspector line gives no maker or product code' ([string]$line[0] -notmatch 'BOE|0A1F') "inspector: '$($line[0])'"
    }
  }

  # A forget of the setup Focus is aimed at turns Focus's setup switch off on the server. The page's copy of Focus still holds the switch on, so a
  # Save of another scene posts Focus back as the page has it, and the switch and the forgotten setup come back on disk.
  Case 'Monitors and Setups: after a forget of the setup Focus is aimed at, a Save of another scene leaves Focus with its setup switch off on disk' {
    Put-Config (Office-Config); Dismiss-Note $url
    $opened = Open-Page $ws $url 'focus'
    Check 'the page opens on Focus (control)' $opened 'the page did not open on Focus in time'
    $pre = Js $ws 'return { on: work.focus.auto.setup === true, key: work.focus.setupKey || null }'
    Check 'Focus is aimed at Office with its setup switch on before the forget (scope)' ($pre.on -eq $true -and $pre.key -ceq 'O9') "auto.setup: $($pre.on), setupKey: $($pre.key)"
    $res = Forget-Office $ws
    Check 'Office is forgotten from the dialog (control)' ($res -eq 'forgot') "forget: $res"
    if ($res -ne 'forgot') { return }
    $fd = @((Read-Config).scenes | ? { $_.id -eq 'focus' })[0]
    Check 'the forget turned Focus setup switch off on disk (control)' ($fd.auto.setup -ne $true -and -not $fd.setupKey) "Focus on disk: auto.setup $($fd.auto.setup), setupKey '$($fd.setupKey)'"
    [void](Js $ws 'document.querySelector("[data-pick=meetings]").click(); return true')
    $picked = WaitFor $ws 'selId === "meetings"' 20
    Check 'Meetings is open in the inspector (scope)' $picked 'Meetings did not open after its card was clicked'
    if (-not $picked) { return }
    [void](Js $ws 'const n = document.getElementById("sceneName"); n.value = "Meetings Renamed"; n.dispatchEvent(new Event("change", { bubbles: true })); return true')
    $canSave = WaitFor $ws '!document.getElementById("save").disabled' 20
    Check 'Save is on after the rename of Meetings (scope)' $canSave 'Save stays off after the rename of Meetings'
    if (-not $canSave) { return }
    $sent = Js $ws 'document.getElementById("save").click(); await window.__h.settle(); return window.__h.posts("config").length'
    Check 'the Save sent one POST /config (control)' ($sent -eq 1) "POST /config count: $sent"
    $disk = Read-Config
    $md = @($disk.scenes | ? { $_.id -eq 'meetings' })[0]
    $fa = @($disk.scenes | ? { $_.id -eq 'focus' })[0]
    Check 'the Save wrote the new name of Meetings to config.json (control)' ($md.name -ceq 'Meetings Renamed') "Meetings on disk: '$($md.name)'"
    Check 'after the Save, Focus on disk has its setup switch off' ($fa.auto.setup -ne $true) "Focus on disk: auto.setup $($fa.auto.setup)"
    Check 'after the Save, Focus on disk names no setup' (-not $fa.setupKey) "Focus on disk: setupKey '$($fa.setupKey)'"
  }

  # The card of Focus shows the trigger chips that are on; the setup one reads Setup. After a forget, with no reload, it must read off.
  Case 'Monitors and Setups: after a forget of the setup Focus is aimed at, the card of Focus shows its setup switch off, with no reload' {
    Put-Config (Office-Config); Dismiss-Note $url
    $opened = Open-Page $ws $url 'focus'
    Check 'the page opens on Focus (control)' $opened 'the page did not open on Focus in time'
    $chips = 'return [...document.querySelector("[data-pick=focus]").closest("article.card").querySelectorAll(".chips i")].map(i => i.textContent.trim())'
    [void](WaitFor $ws '[...document.querySelectorAll(".chips i")].some(i => i.textContent.trim() === "Setup")' 20)
    $before = Js $ws $chips
    Check 'the card of Focus shows its Setup switch on before the forget (scope)' (@($before) -ccontains 'Setup') "chips: $(@($before) -join ', ')"
    $res = Forget-Office $ws
    Check 'Office is forgotten from the dialog (control)' ($res -eq 'forgot') "forget: $res"
    if ($res -ne 'forgot') { return }
    $after = Js $ws $chips
    Check 'right after the forget, the card of Focus shows its setup switch off' (@($after) -cnotcontains 'Setup') "chips on the card of Focus: $(@($after) -join ', ')"
  }

  # The forget answer carries the server's note: "A setup you forgot was the one Focus used ... Pick a setup for each of them ...". The page
  # shows it right after the forget. Matched on the note's own words: "pick a setup" alone also sits in the page's setup picker.
  Case 'Monitors and Setups: after a forget of the setup Focus is aimed at, the pick-a-setup note shows on the page' {
    Put-Config (Office-Config); Dismiss-Note $url
    $opened = Open-Page $ws $url 'focus'
    Check 'the page opens on Focus (control)' $opened 'the page did not open on Focus in time'
    $note = 'const t = document.body.innerText.replace(/\s+/g, " "); return /A setup you forgot/.test(t) && /pick a setup/i.test(t)'
    $before = Js $ws $note
    Check 'no note shows before the forget (scope)' ($before -ne $true) 'the note shows before any forget'
    $res = Forget-Office $ws
    Check 'Office is forgotten from the dialog (control)' ($res -eq 'forgot') "forget: $res"
    if ($res -ne 'forgot') { return }
    Wait-ForgetNote $ws
    $shown = Js $ws $note
    Check 'right after the forget, the pick-a-setup note shows on the page' ($shown -eq $true) 'the forget answered with the note, and the page does not show it'
  }

  # One scene aimed at the forgotten setup: the note says "Pick a setup" and does not say "each of them", which is for two or more scenes.
  Case 'Monitors and Setups: after a forget of the one setup a scene is aimed at, the pick-a-setup note does not say each of them' {
    Put-Config (Office-Config); Dismiss-Note $url
    $opened = Open-Page $ws $url 'focus'
    Check 'the page opens on Focus (control)' $opened 'the page did not open on Focus in time'
    if (-not $opened) { return }
    $aimed = @((Read-Config).scenes | ? { $_.setupKey -ceq 'O9' }).Count
    Check 'exactly one scene is aimed at Office (scope)' ($aimed -eq 1) "scenes aimed at Office: $aimed"
    $res = Forget-Office $ws
    Check 'Office is forgotten from the dialog (control)' ($res -eq 'forgot') "forget: $res"
    if ($res -ne 'forgot') { return }
    Wait-ForgetNote $ws
    $note = Js $ws 'const t = document.body.innerText.replace(/\s+/g, " "); const m = t.match(/A setup you forgot[^]*?pick a setup[^.]*\./i); return m ? m[0] : null'
    Check 'the pick-a-setup note shows after the forget (scope)' ([string]$note -match 'Pick a setup') "note: '$note'"
    Check 'the pick-a-setup note does not say each of them, with one scene aimed at the setup' ([string]$note -notmatch 'each of them') "note: '$note'"
  }

  # The footer status line holds the forget's own message. The server's note shows once, in the dialog message line or the toast.
  Case 'Monitors and Setups: after a forget of the one setup a scene is aimed at, the footer does not repeat the pick-a-setup note' {
    Put-Config (Office-Config); Dismiss-Note $url
    $opened = Open-Page $ws $url 'focus'
    Check 'the page opens on Focus (control)' $opened 'the page did not open on Focus in time'
    if (-not $opened) { return }
    $res = Forget-Office $ws
    Check 'Office is forgotten from the dialog (control)' ($res -eq 'forgot') "forget: $res"
    if ($res -ne 'forgot') { return }
    $footer = [string](Js $ws 'return document.getElementById("msg").textContent.replace(/\s+/g, " ").trim()')
    Check 'the footer names the forget (scope)' ($footer -match 'Forgot Office') "footer: '$footer'"
    Check 'the footer does not repeat the pick-a-setup note' ($footer -notmatch 'A setup you forgot|pick a setup') "footer: '$footer'"
  }

  # Follow Again on the card menu. Each case opens its own page, and opens the menu as a user does, through the card's More button.
  Case 'card menu: Focus, with its own layout on the plugged setup, offers "Follow Laptop + Ultrawide Again"; Meetings, which follows, offers none' {
    Put-Config (New-FollowConfig)
    $opened = Open-Page $ws $url 'focus'
    Check 'the page opens on Focus (control)' $opened 'the page did not open on Focus in time'
    if (-not $opened) { return }
    [void](Js $ws 'const m = window.__fa.more("focus"); if (m) m.click(); return true')
    [void](WaitFor $ws 'window.__fa.items().length > 0' 15)
    $focusMenu = Js $ws 'return { items: window.__fa.items().map(x => window.__fa.label(x)) }'
    Check 'the Focus card menu offers "Follow Laptop + Ultrawide Again"' (@($focusMenu.items) -ccontains $followLabel) "items: $(@($focusMenu.items) -join ' | ')"
    $openedMeet = Open-Page $ws $url 'meetings'
    Check 'the page opens on Meetings (control)' $openedMeet 'the page did not open on Meetings in time'
    if (-not $openedMeet) { return }
    [void](Js $ws 'const m = window.__fa.more("meetings"); if (m) m.click(); return true')
    $meetMenu = Js $ws 'return { items: window.__fa.items().map(x => window.__fa.label(x)) }'
    Check 'the Meetings card menu offers no Follow item (it follows; it has no own layout on the plugged setup)' (@(@($meetMenu.items) | ? { $_ }).Count -eq 0) "items: $(@($meetMenu.items) -join ' | ')"
  }

  Case 'choosing the Follow item sends one request to the remove route for the plugged setup, and the card then says it follows' {
    Put-Config (New-FollowConfig)
    $opened = Open-Page $ws $url 'focus'
    Check 'the page opens on Focus (control)' $opened 'the page did not open on Focus in time'
    if (-not $opened) { return }
    $cardBefore = Js $ws 'const c = window.__fa.card("focus"); return c ? c.textContent.replace(/\s+/g, " ") : null'
    Check 'the Focus card says own layout before the choice (control)' ([string]$cardBefore -match 'own layout') "card text: '$cardBefore'"
    [void](Js $ws 'const m = window.__fa.more("focus"); if (m) m.click(); return true')
    [void](WaitFor $ws ('window.__fa.item("' + $followLabel + '") !== null') 15)
    $has = Js $ws ('return window.__fa.item("' + $followLabel + '") !== null')
    Check 'the Focus card menu has the Follow item (scope)' ($has -eq $true) 'no Follow item on the Focus card menu'
    if ($has -ne $true) { return }
    [void](Js $ws ('window.__fa.item("' + $followLabel + '").click(); await window.__h.settle(); return true'))
    [void](WaitFor $ws 'window.__fa.card("focus") && /follows Laptop \+ Ultrawide/i.test(window.__fa.card("focus").textContent)' 20)
    $rmBodies = @(Reply-List (Js $ws 'return window.__posts.filter(p => /(^|\/)layout\/remove$/.test(p.url)).map(p => p.body)'))
    $urls = @(Reply-List (Js $ws 'return window.__posts.map(p => p.url)'))
    Check 'the follow sends one request to the remove route' ($rmBodies.Count -eq 1) "requests to the remove route: $($rmBodies.Count); POST urls: $($urls -join ', ')"
    $body = if ($rmBodies.Count -eq 1) { ConvertFrom-Json $rmBodies[0] }
    Check 'that request names the plugged-in key and Focus' ($null -ne $body -and $body.key -ceq $plugKey -and $body.scene -ceq 'focus') "sent: $(if ($body) { "scene $($body.scene), key $($body.key)" } else { 'no request' })"
    Check 'the follow writes no layout through POST /layout' (@($urls | ? { $_ -match '(^|/)layout$' }).Count -eq 0) "POST urls: $($urls -join ', ')"
    $card = Js $ws 'const c = window.__fa.card("focus"); return c ? c.textContent.replace(/\s+/g, " ") : null'
    Check 'the Focus card says it follows Laptop + Ultrawide' ([string]$card -match 'follows Laptop \+ Ultrawide') "card text: '$card'"
    Check 'the Focus card no longer says own layout' ([string]$card -notmatch 'own layout') "card text: '$card'"
  }

  Case 'Undo after the follow writes the own layout back with one POST /layout, the card says own layout again, and the footer stops saying it follows' {
    Put-Config (New-FollowConfig)
    $opened = Open-Page $ws $url 'focus'
    Check 'the page opens on Focus (control)' $opened 'the page did not open on Focus in time'
    if (-not $opened) { return }
    $pre = Canon (Js $ws 'return layoutOf(work.focus)')
    [void](Js $ws 'const m = window.__fa.more("focus"); if (m) m.click(); return true')
    [void](WaitFor $ws ('window.__fa.item("' + $followLabel + '") !== null') 15)
    $has = Js $ws ('return window.__fa.item("' + $followLabel + '") !== null')
    Check 'the Focus card menu has the Follow item (scope)' ($has -eq $true) 'no Follow item on the Focus card menu'
    if ($has -ne $true) { return }
    [void](Js $ws ('window.__fa.item("' + $followLabel + '").click(); await window.__h.settle(); return true'))
    [void](WaitFor $ws 'window.__fa.card("focus") && /follows Laptop \+ Ultrawide/i.test(window.__fa.card("focus").textContent)' 20)
    [void](WaitFor $ws '!inflight.focus && /follows Laptop \+ Ultrawide until you change it/.test(document.getElementById("msg").textContent)' 20)
    $msgFollowed = [string](Js $ws 'return document.getElementById("msg").textContent.replace(/\s+/g, " ").trim()')
    Check 'the footer says the scene follows Laptop + Ultrawide after the follow (control)' ($msgFollowed -match 'follows Laptop \+ Ultrawide until you change it') "footer: '$msgFollowed'"
    $n0 = [int](Js $ws 'return window.__h.posts("layout").length')
    [void](Js $ws 'document.getElementById("undo").click(); await window.__h.settle(); return true')
    $undoBodies = @(Reply-List (Js $ws ('return window.__h.posts("layout").slice(' + $n0 + ').map(p => p.body)')))
    Check 'Undo sends one POST /layout' ($undoBodies.Count -eq 1) "POST /layout sent by Undo: $($undoBodies.Count)"
    if ($undoBodies.Count -eq 1) {
      $ub = ConvertFrom-Json $undoBodies[0]
      Check 'that POST /layout names the plugged-in key and Focus' ($ub.key -ceq $plugKey -and $ub.scene -ceq 'focus') "sent: scene $($ub.scene), key $($ub.key)"
      Check 'Undo writes the own layout back as it was before the follow' ((Canon $ub.layout) -ceq $pre) 'the layout Undo sent is not the own layout'
    }
    [void](WaitFor $ws 'window.__fa.card("focus") && /own layout/i.test(window.__fa.card("focus").textContent)' 20)
    $card = Js $ws 'const c = window.__fa.card("focus"); return c ? c.textContent.replace(/\s+/g, " ") : null'
    Check 'the Focus card says own layout again' ([string]$card -match 'own layout') "card text: '$card'"
    [void](WaitFor $ws '!inflight.focus' 20)
    $strip = Js $ws $stripJs
    Check 'the strip says Focus has its own layout (control)' ([string]$strip.text -match 'own layout') "strip text: '$($strip.text)'"
    $footer = [string](Js $ws 'return document.getElementById("msg").textContent.replace(/\s+/g, " ").trim()')
    Check 'the footer no longer says the scene follows a setup until you change it' ($footer -notmatch 'follows .+ until you change it') "footer: '$footer'"
  }

  # ---- Follow Again in flight. Each case holds one request or one answer in the page, then acts while it waits. ----
  # Hold-Js: one wrapper for one POST route, installed after the page's own wrapper. Mode 'answer': the request is sent and its reply waits
  # for the gate. Mode 'send': the request waits for the gate, then is sent. Mode 'record': nothing waits. A hold sets __<tag>Answered when its
  # reply came, counts each send in __<tag>Sends, and sets __<tag>Watch to the watched hold's Answered flag at the send. __<tag>Open opens the gate.
  function Hold-Js([string]$route, [string]$tag, [string]$mode, [string]$watch = '') {
    $p = 'window.__' + $tag
    $held = switch ($mode) {
      'answer' { 'g(u, o).then(r => { ' + $p + 'Answered = true; return ' + $p + 'Gate.then(() => r) })' }
      'send' { $p + 'Gate.then(() => g(u, o)).then(r => { ' + $p + 'Answered = true; return r })' }
      default { 'g(u, o)' }
    }
    $watchJs = if ($watch) { $p + 'Watch = window.__' + $watch + 'Answered === true, ' } else { '' }
    $p + 'Answered = false; ' + $p + 'Sends = 0; ' + $p + 'Watch = null; ' + $p + 'Gate = new Promise(r => { ' + $p + 'Open = r }); const g = window.fetch; window.fetch = (u, o) => String(u) === "' + $route + '" && o && String(o.method || "").toUpperCase() === "POST" ? (' + $p + 'Sends++, ' + $watchJs + $held + ') : g(u, o); return true'
  }
  # A key press in the page, sent through the DevTools Input domain as the browser takes it. A key that types text is a keyDown with the text.
  function Press-Key($sock, [string]$key, [int]$code, [string]$text = '') {
    $down = @{ type = $(if ($text) { 'keyDown' } else { 'rawKeyDown' }); key = $key; code = $key; windowsVirtualKeyCode = $code; nativeVirtualKeyCode = $code }
    if ($text) { $down.text = $text }
    [void](Cdp $sock 'Input.dispatchKeyEvent' $down)
    [void](Cdp $sock 'Input.dispatchKeyEvent' @{ type = 'keyUp'; key = $key; code = $key; windowsVirtualKeyCode = $code; nativeVirtualKeyCode = $code })
  }
  # The Focus card's More button, pressed as a user does, and the wait until its Follow item is on screen. Returns whether the item is there.
  function Open-Follow-Menu($sock) {
    [void](Js $sock 'const m = window.__fa.more("focus"); if (m) m.click(); return true')
    [void](WaitFor $sock 'window.__fa.items().length > 0' 15)
    [bool](Js $sock ('return window.__fa.item("' + $followLabel + '") !== null'))
  }
  # Card menu placement. The Focus card's menu is opened in a 1440-wide window of the given height. Its rect is
  # checked against the card's More button and its Preview button, read once the menu is open. At 520 high Focus's More button sits near the
  # bottom edge, with no room below for its menu; at 900 high there is room.
  function Menu-Geometry($sock) {
    Js $sock 'const R = e => { const r = e.getBoundingClientRect(); return { l: r.left, t: r.top, r: r.right, b: r.bottom } }; const c = document.getElementById("cmenu"); const m = window.__fa.more("focus"); const a = document.querySelector("[data-apply=focus]"); return { menu: c ? Object.assign(R(c), { h: c.offsetHeight }) : null, more: m ? R(m) : null, apply: a ? R(a) : null, ih: innerHeight, iw: innerWidth }'
  }
  # Two rects share some area. A touching edge is not an overlap.
  function Overlaps($a, $b) { return (($a.l -lt $b.r) -and ($b.l -lt $a.r) -and ($a.t -lt $b.b) -and ($b.t -lt $a.b)) }
  function Check-Menu-Placement([int]$height, [bool]$roomBelow, [string]$tag) {
    [void](Cdp $ws 'Emulation.setDeviceMetricsOverride' @{ width = 1440; height = $height; deviceScaleFactor = 1; mobile = $false })
    try {
      $opened = Open-Page $ws $url 'focus'
      Check "${tag}: the page opens on Focus (control)" $opened 'the page did not open on Focus in time'
      if (-not $opened) { return }
      $has = Open-Follow-Menu $ws
      Check "${tag}: the Focus card menu is open with its Follow item (control)" $has 'no Follow item on the Focus card menu'
      if (-not $has) { return }
      $g = Menu-Geometry $ws
      $below = (($g.more.b + $g.menu.h + 12) -le $g.ih)
      Check "${tag}: the More button has $(if ($roomBelow) { 'room' } else { 'no room' }) below for its menu (scope)" ($below -eq $roomBelow) "More bottom $($g.more.b), menu height $($g.menu.h), window height $($g.ih)"
      Check "${tag}: the menu lies inside the window (control)" ($g.menu.t -ge 0 -and $g.menu.b -le $g.ih) "menu top $($g.menu.t), bottom $($g.menu.b), window height $($g.ih)"
      Check "${tag}: the menu does not cover its own More button" (-not (Overlaps $g.menu $g.more)) "menu $($g.menu.t) to $($g.menu.b); More $($g.more.t) to $($g.more.b)"
      Check "${tag}: the menu does not cover the card's Preview button" (-not (Overlaps $g.menu $g.apply)) "menu $($g.menu.t) to $($g.menu.b); Preview $($g.apply.t) to $($g.apply.b)"
    } finally { [void](Cdp $ws 'Emulation.clearDeviceMetricsOverride') }
  }
  # The red case: no room below the More button, so the menu must open above it. Its control, in the same card at 900 high, has room below.
  Case 'card menu at 1440: with no room below its More button, the menu opens above and covers neither More nor Preview' {
    Check-Menu-Placement 520 $false 'no room below'
  }
  Case 'card menu at 1440: with room below its More button, the menu opens below and covers neither (control)' {
    Check-Menu-Placement 900 $true 'room below'
  }

  # The follow has finished: its message is set, and the preview it started has rendered (its in-flight entry is gone).
  $followedJs = '!inflight.focus && /follows Laptop \+ Ultrawide until you change it/.test(document.getElementById("msg").textContent)'
  $followEndJs = '!inflight.focus && /follows Laptop \+ Ultrawide until you change it|Could not follow again/.test(document.getElementById("msg").textContent)'
  $portraitFocus = '{"grids":{"P1":{"c":2,"r":1}},"pins":[],"zones":[],"fill":{"mon":"P1","apps":[],"skip":[],"sort":"app"},"bay":[]}'   # Focus on the Portrait setup (P1|U1)

  Case 'Follow Again: an edit during the remove POST sends no POST /layout, and the card still says it follows' {
    Put-Config (New-FollowConfig)
    $opened = Open-Page $ws $url 'focus'
    Check 'the page opens on Focus (control)' $opened 'the page did not open on Focus in time'
    if (-not $opened) { return }
    [void](Js $ws (Hold-Js 'layout/remove' 'rm' 'answer'))
    $has = Open-Follow-Menu $ws
    Check 'the Focus card menu has the Follow item (scope)' $has 'no Follow item on the Focus card menu'
    if (-not $has) { return }
    [void](Js $ws ('window.__fa.item("' + $followLabel + '").click(); return true'))
    $answered = WaitFor $ws 'window.__rmAnswered === true' 20
    Check 'the remove is answered and its reply is held (scope)' $answered 'the remove was not answered in time'
    if (-not $answered) { return }
    $during = Board-Edit $ws 1001
    Check 'an edit during the remove POST sends no POST /layout (the page is busy)' (@(Reply-List $during.layout).Count -eq 0) "POST /layout sent during the remove: $(@(Reply-List $during.layout).Count)"
    [void](Js $ws 'window.__rmOpen(); return true')
    [void](WaitFor $ws $followEndJs 20)
    $card = Js $ws 'const c = window.__fa.card("focus"); return c ? c.textContent.replace(/\s+/g, " ") : null'
    Check 'the card still says it follows Laptop + Ultrawide after the remove' ([string]$card -match 'follows Laptop \+ Ultrawide') "card text: '$card'"
    $all = Js $ws 'return { layout: window.__h.posts("layout") }'
    Check 'no POST /layout is sent at any point in the follow' (@(Reply-List $all.layout).Count -eq 0) "POST /layout sent: $(@(Reply-List $all.layout).Count)"
    $own = Js $ws 'const c = await (await fetch("config", { cache: "no-store" })).json(); const f = c.scenes.find(s => s.id === "focus"); return !!(f.layouts && f.layouts["L1|P1|U1"])'
    Check 'the server holds no own layout for Focus on the plugged-in setup' ($own -eq $false) 'the server still holds the own layout'
  }

  Case 'Follow Again: a setup change during the flush of an autosave does not remove the new setup''s layout' {
    $cfg = New-FollowConfig
    Add-Member -InputObject $cfg.setups -NotePropertyName 'P1|U1' -NotePropertyValue ([pscustomobject]@{ name = 'Portrait + Ultrawide'; ids = @('P1', 'U1'); lastUsed = '2026-11-01T09:00:00' })
    Add-Layout $cfg 'focus' 'P1|U1' $portraitFocus
    Put-Config $cfg
    $opened = Open-Page $ws $url 'focus'
    Check 'the page opens on Focus (control)' $opened 'the page did not open on Focus in time'
    if (-not $opened) { return }
    [void](Js $ws (Hold-Js 'layout' 'ls' 'answer'))
    [void](Board-Edit $ws 1001)
    $answered = WaitFor $ws 'window.__lsAnswered === true' 20
    Check 'the autosave is answered under the plugged-in setup before the item is chosen (scope)' $answered 'the autosave was not answered in time'
    if (-not $answered) { return }
    $has = Open-Follow-Menu $ws
    Check 'the Focus card menu has the Follow item (scope)' $has 'no Follow item on the Focus card menu'
    if (-not $has) { return }
    [void](Js $ws ('window.__fa.item("' + $followLabel + '").click(); return true'))
    $flushing = Js $ws 'return svBusy["focus"] === true'
    Check 'the item waits on the autosave still in flight (control)' ($flushing -eq $true) 'the autosave was not in flight when the item was chosen'
    Plug $snapBText
    [void](Js $ws 'await document.getElementById("refresh").onclick(); return true')
    $now = Js $ws 'return plug.key'
    Check 'Refresh moved the page onto the new setup (control)' ($now -ceq 'P1|U1') "plug key: $now"
    [void](Js $ws 'window.__lsOpen(); return true')
    [void](WaitFor $ws $followEndJs 20)
    $rm = @(Reply-List (Js $ws 'return window.__posts.filter(p => /(^|\/)layout\/remove$/.test(p.url)).map(p => p.body)'))
    $onNew = @($rm | ? { (ConvertFrom-Json $_).key -ceq 'P1|U1' })
    Check 'the remove names the setup the item was chosen on, never the new setup' ($onNew.Count -eq 0) "remove requests under P1|U1: $($onNew.Count)"
    $kept = Js $ws 'const c = await (await fetch("config", { cache: "no-store" })).json(); const f = c.scenes.find(s => s.id === "focus"); return !!(f.layouts && f.layouts["P1|U1"])'
    Check 'the new setup keeps its own focus layout' ($kept -eq $true) 'the new setup''s focus layout was removed'
  }

  Case 'Follow Again: after a setup change, Undo is not offered and sends nothing under the new setup key' {
    Put-Config (New-FollowConfig)
    $opened = Open-Page $ws $url 'focus'
    Check 'the page opens on Focus (control)' $opened 'the page did not open on Focus in time'
    if (-not $opened) { return }
    [void](Js $ws (Hold-Js 'layout/remove' 'rm' 'answer'))
    $has = Open-Follow-Menu $ws
    Check 'the Focus card menu has the Follow item (scope)' $has 'no Follow item on the Focus card menu'
    if (-not $has) { return }
    [void](Js $ws ('window.__fa.item("' + $followLabel + '").click(); return true'))
    $answered = WaitFor $ws 'window.__rmAnswered === true' 20
    Check 'the remove is answered under the old setup before the setup changes (scope)' $answered 'the remove was not answered in time'
    if (-not $answered) { return }
    Plug $snapBText
    [void](Js $ws 'await document.getElementById("refresh").onclick(); return true')
    $now = Js $ws 'return plug.key'
    Check 'Refresh moved the page onto the new setup (control)' ($now -ceq 'P1|U1') "plug key: $now"
    [void](Js $ws 'window.__rmOpen(); return true')
    [void](WaitFor $ws $followEndJs 20)
    $offered = Js $ws 'return { undo: !document.getElementById("undo").disabled, toastUndo: !document.getElementById("toastUndo").hidden }'
    Check 'Undo is not offered after the setup changed (no Undo entry for the old setup)' (-not $offered.undo) 'the Undo button is enabled for a follow made on the old setup'
    Check 'the toast offers no Undo for that follow either' (-not $offered.toastUndo) 'the toast offers Undo for a follow made on the old setup'
    [void](Js $ws 'document.getElementById("undo").onclick(); await window.__h.settle(); return true')
    $log = Js $ws 'return { layout: window.__h.posts("layout") }'
    $under = @(Posts-Under (Reply-List $log.layout) 'P1|U1')
    Check 'Undo sends no POST /layout under the new setup key' ($under.Count -eq 0) "POST /layout under P1|U1: $($under.Count)"
  }

  Case 'Follow Again: a failed GET /layouts after the remove leaves the board not showing the removed layout as saved' {
    Put-Config (New-FollowConfig)
    $opened = Open-Page $ws $url 'focus'
    Check 'the page opens on Focus (control)' $opened 'the page did not open on Focus in time'
    if (-not $opened) { return }
    $ownCanon = Canon (Js $ws 'return layoutOf(work.focus)')
    Fail-Read $ws 'layouts' -NoRefresh
    $has = Open-Follow-Menu $ws
    Check 'the Focus card menu has the Follow item (scope)' $has 'no Follow item on the Focus card menu'
    if (-not $has) { return }
    [void](Js $ws ('window.__fa.item("' + $followLabel + '").click(); return true'))
    $failed = WaitFor $ws 'window.__failedRead === "layouts"' 20
    Check 'the read after the remove was asked for and failed (scope)' $failed 'the read after the remove was not asked for in time'
    if (-not $failed) { return }
    [void](WaitFor $ws '!inflight.focus' 20)
    $msg = Js $ws 'return document.getElementById("msg").textContent'
    Check 'the page reports the follow as done' ([string]$msg -match 'follows Laptop \+ Ultrawide') "message: '$msg'"
    $undo = Js $ws 'return !document.getElementById("undo").disabled'
    Check 'the Undo entry for the follow exists (control)' ($undo -eq $true) 'Undo is not offered after the follow'
    $bar = Js $ws $stripJs
    $shown = Canon (Js $ws 'return layoutOf(work.focus)')
    Check 'the board does not show the removed layout as saved' (-not ($shown -ceq $ownCanon -and -not $bar.warn)) "the board still shows the removed own layout as saved; strip amber: $($bar.warn)"
  }

  # Guard, holds on the page as it stands: an autosave still in flight is written before the remove is sent, so the remove cannot land first
  # and the layout cannot come back. A mutant with the flush removed turns it red (the report carries that run).
  Case 'Follow Again: an autosave in flight is written before the remove is sent (guard)' {
    Put-Config (New-FollowConfig)
    $opened = Open-Page $ws $url 'focus'
    Check 'the page opens on Focus (control)' $opened 'the page did not open on Focus in time'
    if (-not $opened) { return }
    [void](Js $ws (Hold-Js 'layout' 'ls' 'send'))
    [void](Js $ws (Hold-Js 'layout/remove' 'rm' 'record' 'ls'))
    [void](Board-Edit $ws 1001)
    $inFlight = WaitFor $ws 'svBusy["focus"] === true' 15
    Check 'the autosave is in flight when the item is chosen (control)' $inFlight 'no autosave in flight'
    if (-not $inFlight) { return }
    $has = Open-Follow-Menu $ws
    Check 'the Focus card menu has the Follow item (scope)' $has 'no Follow item on the Focus card menu'
    if (-not $has) { return }
    $sends = Js $ws ('window.__fa.item("' + $followLabel + '").click(); return window.__rmSends')
    Check 'the remove is not sent while the autosave is in flight' ([int]$sends -eq 0) "remove requests sent at once: $sends"
    [void](Js $ws 'window.__lsOpen(); return true')
    [void](WaitFor $ws $followEndJs 20)
    $seen = Js $ws 'return { sends: window.__rmSends, answered: window.__rmWatch }'
    Check 'the remove is sent once, after the autosave is answered' ($seen.sends -eq 1 -and $seen.answered -eq $true) "remove sends: $($seen.sends); autosave answered when the remove was sent: $($seen.answered)"
  }

  Case 'Follow Again: Enter on the Follow item leaves keyboard focus on a control on the Focus card' {
    Put-Config (New-FollowConfig)
    $opened = Open-Page $ws $url 'focus'
    Check 'the page opens on Focus (control)' $opened 'the page did not open on Focus in time'
    if (-not $opened) { return }
    $has = Open-Follow-Menu $ws
    Check 'the Focus card menu has the Follow item (scope)' $has 'no Follow item on the Focus card menu'
    if (-not $has) { return }
    $inMenu = Js $ws 'return !!(document.activeElement && document.activeElement.closest("#cmenu"))'
    Check 'keyboard focus is in the open menu before Enter (control)' ($inMenu -eq $true) 'focus is not in the open menu'
    Press-Key $ws 'Enter' 13 "`r"
    $done = WaitFor $ws $followedJs 20
    Check 'Enter on the item makes the follow (scope)' $done 'the follow did not finish after Enter'
    if (-not $done) { return }
    $where = Js $ws 'const a = document.activeElement; const c = a ? a.closest("article.card") : null; return { onFocusCard: !!c && c === window.__fa.card("focus"), on: a ? a.tagName : null }'
    Check 'after the follow, keyboard focus is on a control on the Focus card, not on the body' ($where.onFocusCard -eq $true) "focus on: $($where.on)"
  }

  Case 'Follow Again: Tab from the open card menu never leaves it open with focus on the body' {
    Put-Config (New-FollowConfig)
    $opened = Open-Page $ws $url 'focus'
    Check 'the page opens on Focus (control)' $opened 'the page did not open on Focus in time'
    if (-not $opened) { return }
    $has = Open-Follow-Menu $ws
    Check 'the Focus card menu has the Follow item (scope)' $has 'no Follow item on the Focus card menu'
    if (-not $has) { return }
    $inMenu = Js $ws 'return !!(document.activeElement && document.activeElement.closest("#cmenu"))'
    Check 'keyboard focus is in the open menu before Tab (control)' ($inMenu -eq $true) 'focus is not in the open menu'
    Press-Key $ws 'Tab' 9
    $after = Js $ws 'const m = document.getElementById("cmenu"); const a = document.activeElement; return { open: !!m, inMenu: !!(a && a.closest("#cmenu")), on: a ? a.tagName : null }'
    Check 'Tab from the open menu closes it or keeps focus in it, never leaves it open with focus outside' (-not ($after.open -and -not $after.inMenu)) "menu open: $($after.open); focus on: $($after.on)"
  }

  # Kind icons (decision monitor-setups, item 25; mockup card-kind-icon.html). A card's kind is Built-in for the built-in scene, Custom for a scene
  # in the config, and Not saved for a scene the page holds with no config entry. Each card shows its kind as one icon (an svg) titled and
  # labelled with the kind word, and no kind word is on screen. No user path keeps a scene unsaved, so the Not saved card is set in the page's
  # work map the way the page's own self-test sets one.
  $kindWords = 'Built-in', 'Custom', 'Not saved'
  $kindJs = @'
const words = ["Built-in", "Custom", "Not saved"];
const cardsOf = () => [...document.querySelectorAll("#cards [data-pick]")].map(b => ({ id: b.dataset.pick, card: b.closest("article.card") }));
// The text a reader sees: not the text of a visually hidden, aria-hidden or hidden part, nor of a part that is not drawn.
const seen = el => { const w = document.createTreeWalker(el, NodeFilter.SHOW_TEXT); let t = ""; while (w.nextNode()) { const p = w.currentNode.parentElement; if (!p || p.closest(".vh,[aria-hidden=true],[hidden]") || p.getClientRects().length === 0) continue; t += w.currentNode.textContent + " " } return t.replace(/\s+/g, " ").trim() };
'@
  # The amber dot: a box of 6 to 8 px filled with the page's --hi, or an amber ::before of that size, in a card's bottom row.
  $dotJs = @'
const amber = (() => { const p = document.createElement("i"); p.style.background = "var(--hi)"; document.body.appendChild(p); const c = getComputedStyle(p).backgroundColor; p.remove(); return c })();
const sized = v => parseFloat(v) >= 6 && parseFloat(v) <= 8;
const dotsIn = card => { const row = card.querySelector(".crow"); if (!row) return -1; return [row, ...row.querySelectorAll("*")].filter(el => { const cs = getComputedStyle(el), pb = getComputedStyle(el, "::before"), r = el.getBoundingClientRect(); return (cs.backgroundColor === amber && sized(r.width) && sized(r.height)) || (pb.content !== "none" && pb.content !== "normal" && pb.backgroundColor === amber && sized(pb.width)) }).length };
// The elements in a card whose title or label says edited.
const editedLabels = card => [...card.querySelectorAll("[title],[aria-label]")].filter(x => /\bedited\b/i.test((x.getAttribute("title") || "") + " " + (x.getAttribute("aria-label") || ""))).length;
'@
  # The cut check: a bottom-row element whose own text is wider inside than its box is cut. Also the card heights, and the Solo row (the control).
  $cutJs = @'
const cut = [], heights = [];
let soloRow = false;
for (const { id, card } of cardsOf()) {
  heights.push(Math.round(card.getBoundingClientRect().height));
  const row = card.querySelector(".crow");
  if (id === "solo") soloRow = !!row && row.clientWidth > 0;
  for (const el of card.querySelectorAll(".crow, .crow *")) {
    if (!(el instanceof HTMLElement) || el.closest(".vh") || el.getClientRects().length === 0 || el.clientWidth === 0) continue;
    const own = [...el.childNodes].some(n => n.nodeType === 3 && n.textContent.trim() !== "");
    if (own && el.scrollWidth > el.clientWidth + 1) cut.push(id + ": " + el.textContent.trim().slice(0, 30) + " is " + el.scrollWidth + " px in a " + el.clientWidth + " px box");
  }
}
return { cards: cardsOf().length, heights, cut, soloRow };
'@
  # The kind rail: Focus has its own layout and Meetings follows Laptop + Ultrawide, so the rail shows a layout mark and a More button, and a
  # Not saved scene is added beside them. Opens the live page on Focus at the window size the caller set, and waits until the rail is drawn.
  function Open-Kind-Rail($sock) {
    Put-Config (New-FollowConfig)
    if (-not (Open-Page $sock $url 'focus')) { return $false }
    [void](Js $sock 'const s = clone(work.focus); s.id = "kind-probe"; s.name = "Kind probe"; work["kind-probe"] = s; await preview("kind-probe"); render(); return true')
    WaitFor $sock '!!document.querySelector("[data-pick=kind-probe]") && !!document.querySelector("[data-pick=solo]")' 30
  }
  # Each scene the rail shows, with the kind it must show: the built-in scene, a saved scene, and the Not saved probe.
  $expectKind = @{ 'kind-probe' = 'Not saved' }
  foreach ($x in @((New-Config).scenes)) { $expectKind[[string]$x.id] = $(if ($x.builtIn) { 'Built-in' } else { 'Custom' }) }

  Case 'each card shows its kind as one icon titled and labelled with the kind word, and no kind word is on screen' {
    $opened = Open-Kind-Rail $ws
    Check 'the kind rail opens on Focus, with a Not saved card (control)' $opened 'the page did not draw the rail in time'
    if (-not $opened) { return }
    # Js hands back the list as one array. Wrapping it in @() makes the list one element, and each card would then match every card's icons.
    $cards = Js $ws ($kindJs + 'return cardsOf().map(({ id, card }) => ({ id, text: seen(card), titles: [...card.querySelectorAll("[title]")].map(x => x.getAttribute("title")), labels: [...card.querySelectorAll("[aria-label]")].map(x => x.getAttribute("aria-label")), icons: [...card.querySelectorAll("[aria-label]")].filter(x => words.includes(x.getAttribute("aria-label"))).map(x => ({ title: x.getAttribute("title"), label: x.getAttribute("aria-label"), svg: x.tagName.toLowerCase() === "svg" || !!x.querySelector("svg") })) }))')
    Check 'the rail lists every card, one entry each (scope)' (@($cards | ? { $_.id }).Count -eq $expectKind.Count) "entries listed: $(@($cards).Count)"
    foreach ($id in $expectKind.Keys) {
      $want = $expectKind[$id]
      $c = @($cards | ? { $_.id -eq $id })[0]
      Check "the $id card is on the page (scope)" ($null -ne $c) 'no card with that scene id'
      if ($null -eq $c) { continue }
      $icons = @($c.icons)
      $shown = @($icons | ? { $_.title -ceq $want -and $_.label -ceq $want -and $_.svg })
      $iconList = if ($icons.Count) { ($icons | % { "title '$($_.title)', label '$($_.label)', svg $($_.svg)" }) -join '; ' } else { 'none' }
      # The control reads the kind from the card's title or label, which both the old card and the icon carry. The visible text is checked below.
      $named = @(@($c.titles) + @($c.labels))
      Check "the $id card's title or label names its kind $want (control)" ($named -contains $want) "titles and labels: $($named -join ' | ')"
      Check "the $id card shows $want as one icon, titled and labelled $want" ($icons.Count -eq 1 -and $shown.Count -eq 1) "kind icons on the card: $iconList"
      Check "the $id card shows no kind word as visible text" (-not @($kindWords | ? { ([string]$c.text).Contains($_) }).Count) "visible text: '$($c.text)'"
    }
  }

  Case 'an edited scene shows one amber edited dot in its bottom row, with a title or label that says edited' {
    $opened = Open-Kind-Rail $ws
    Check 'the kind rail opens on Focus (control)' $opened 'the page did not draw the rail in time'
    if (-not $opened) { return }
    # The name is changed and the change is committed, as a user does. Focus is saved, so its card reads edited, not Not saved.
    [void](Js $ws 'const f = document.getElementById("sceneName"); f.value = "Focus renamed"; f.dispatchEvent(new Event("change", { bubbles: true })); return true')
    $edited = WaitFor $ws '/edited/.test(document.querySelector("[data-pick=focus]").closest("article.card").textContent)' 30
    Check 'the Focus card reads edited once its name is changed and not saved (scope)' $edited 'the Focus card does not read edited'
    if (-not $edited) { return }
    $d = Js $ws ($kindJs + $dotJs + 'const f = cardsOf().find(c => c.id === "focus").card, s = cardsOf().find(c => c.id === "solo").card; return { focusDots: dotsIn(f), focusLabels: editedLabels(f), soloDots: dotsIn(s), soloLabels: editedLabels(s) }')
    Check 'the Solo card, not edited, shows no edited dot or label (control)' ($d.soloDots -eq 0 -and $d.soloLabels -eq 0) "amber dots $($d.soloDots), edited labels $($d.soloLabels)"
    Check 'the edited Focus card has a title or label that says edited' ($d.focusLabels -gt 0) 'no title or label on the Focus card says edited'
    Check 'the edited Focus card shows one amber dot in its bottom row' ($d.focusDots -eq 1) "amber dots in its bottom row: $($d.focusDots)"
  }

  Case 'at 1024 and 1440 no card bottom-row label is cut, and at 1024 every card has one height' {
    foreach ($w in 1440, 1024) {
      [void](Cdp $ws 'Emulation.setDeviceMetricsOverride' @{ width = $w; height = 900; deviceScaleFactor = 1; mobile = $false })
      try {
        $opened = Open-Kind-Rail $ws
        Check "${w}: the kind rail opens on Focus (control)" $opened 'the page did not draw the rail in time'
        if (-not $opened) { continue }
        $m = Js $ws ($kindJs + $cutJs)
        Check "${w}: every card is drawn (scope)" ([int]$m.cards -eq $expectKind.Count) "cards drawn: $($m.cards) of $($expectKind.Count)"
        Check "${w}: the Solo card's bottom row is measured (control)" ([bool]$m.soloRow) 'no bottom row on the Solo card'
        Check "${w}: no card's bottom-row label is cut" (@($m.cut).Count -eq 0) (@($m.cut) -join ' | ')
        if ($w -eq 1024) { Check '1024: every card has one height' (@(@($m.heights) | Sort-Object -Unique).Count -eq 1) "card heights: $(@($m.heights) -join ', ')" }
      } finally { [void](Cdp $ws 'Emulation.clearDeviceMetricsOverride') }
    }
  }

  Case 'the offline page shows no Follow item on any card and sends no POST' {
    $fileUrl = ([Uri]$appHtml).AbsoluteUri
    $loaded = Go $ws $fileUrl 'typeof snap !== "undefined" && !!snap && /^Offline/.test(document.getElementById("msg").textContent)'
    Check 'the offline page loads its sample (scope)' $loaded 'the offline sample did not load in time'
    if (-not $loaded) { return }
    [void](Js $ws $installJs)
    [void](Js $ws 'for (const s of ["default", "focus", "meetings", "review"]) { const m = window.__fa.more(s); if (m) m.click(); } return true')
    $off = Js $ws 'return { items: window.__fa.items().map(x => window.__fa.label(x)), posts: window.__posts.length }'
    Check 'the offline page shows no Follow item' (@(@($off.items) | ? { $_ }).Count -eq 0) "items: $(@($off.items) -join ' | ')"
    Check 'the offline page sends no POST' ($off.posts -eq 0) "POSTs sent: $($off.posts)"
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
