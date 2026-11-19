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
#     that says edited. A Not saved scene shows neither. At 1024 and 1440 no card's bottom-row label is cut, and at 1024 every card has one height.
#   Inspector kind (monitor-setups notes, item 25; the owner's yes): the Scene section shows the selected scene's kind once, in words
#     (Built-in, Custom or Not saved), no other kind's word, and it changes when a scene of another kind is selected. An edited saved scene's
#     section says edited once. Its reasons line does not count, and an unsaved scene's edited is not checked.
#   Split Cell (layout-free items 1-13; split-cell-notes.md; plan lane L2). The menu opens on S with a window selected, or from the
#     inspector's Split Cell button. Its items are role=menuitem buttons "Claude Keeps Left|Right|Top|Bottom" under a group label (a p)
#     that starts "Side by Side" or "Stacked". A locked tile (class lock) has its split items disabled (disabled or aria-disabled=true),
#     with "Locked. Unlock it first." in the title or the aria-describedby target. A split posts one POST /layout: grids.U1 keeps c and r,
#     sets mult, and sets fill.unit ([2,1] side, [1,2] stacked). A side split maps base slot s to 2s and 2s+1. A stacked split maps s to
#     s+row*c and s+(row+1)*c. The split window's pin takes its kept slot only. J joins: mult and fill.unit are absent or [1,1] again.
#     Undo sends one more POST /layout with the layout as it was. cellRect is checked against tile.ps1 -Json, whose slots are 1-based.
#     Guard, green on main (its red is a mutant on a scratch copy): split: S with no window selected opens no menu and sends nothing.
#   Split Cell, small halves, notes and menu (layout-free items 4, 12, 13; split-cell-notes S5): an unsplit tile under 40px keeps its lock,
#     grip and badge, and only a split half gives them up. A half under 40px draws no window title, one initial, and a selected Stay Put
#     stays inside it. A join says "Joined cell N." with the cell the window was cut from, and a second split names its original cell.
#     A right-click on an unselected window opens its split menu, though selecting it scrolls the inspector. Join Halves has the category colour.
#   Split Cell, double-click (split-cell notes): a double-click on the selected window splits it side by side, one POST /layout with the grid
#     doubled. On an unselected window it selects only, and sends no POST. On a selected locked window it sends no POST. Real pointer and mouse
#     events (Click-Double), not a synthetic dblclick.
#   Free Layout (layout-free items 14-29; free-layout-notes F1-F16; plan lane L4). The page's contract, as the checks at the end of this
#     file read it: the switch is input[role=switch] labelled Free Layout in the Monitor section (the section that holds #monh), and the
#     key F toggles it. A monitor label reads Free Layout. Each tile is .tile[data-id]. Each space carries data-space (its index in reading
#     order): an empty one has class empty, a lent one class lent with one i per borrower (class fromL or fromR), a gap that stays class
#     gap. A save sends one POST /layout whose grids.U1 keeps c and r and holds free.areas (tile.ps1's shape). The page draws each tile at
#     px() of the engine's rect, and tile.ps1 places each pinned window at its area's pixel rect.
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
    more: s => { const c = window.__fa.card(s); return c ? ([...c.querySelectorAll("button:not([data-pick]):not([data-apply])")].find(x => /\bmore\b|\bmenu\b|â‹¯/i.test((x.getAttribute("aria-label") || "") + " " + (x.title || "") + " " + x.textContent.trim())) || null) : null },
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
  # $mods: the held modifier keys (CDP bits: Alt 1, Ctrl 2, Shift 8).
  function Press-Key($sock, [string]$key, [int]$code, [string]$text = '', [int]$mods = 0) {
    $down = @{ type = $(if ($text) { 'keyDown' } else { 'rawKeyDown' }); key = $key; code = $key; windowsVirtualKeyCode = $code; nativeVirtualKeyCode = $code; modifiers = $mods }
    if ($text) { $down.text = $text }
    [void](Cdp $sock 'Input.dispatchKeyEvent' $down)
    [void](Cdp $sock 'Input.dispatchKeyEvent' @{ type = 'keyUp'; key = $key; code = $key; windowsVirtualKeyCode = $code; nativeVirtualKeyCode = $code; modifiers = $mods })
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
  # labelled with the kind word, and no kind word is on screen. A failed Save As New keeps its copy in the work map with no config entry
  # (saveAsNew in app.html), so a user can reach a Not saved card. The probe builds that state directly: a clone of Focus in the work map, no config entry.
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
  # Waits until the Scene section shows the named scene, so a read is of the scene the page selected.
  function Scene-Shows($sock, [string]$scene, [string]$name) {
    WaitFor $sock ('selId === "' + $scene + '" && !!document.getElementById("sceneName") && document.getElementById("sceneName").value === "' + $name + '"') 30
  }
  # Selects a scene as a user does (its card's button), then waits until the Scene section shows it.
  function Select-Scene($sock, [string]$scene, [string]$name) {
    [void](Js $sock ('document.querySelector("[data-pick=' + $scene + ']").click(); return true'))
    Scene-Shows $sock $scene $name
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

  Case 'an edited scene shows one amber dot with a title or label that says edited, and a Not saved scene shows neither' {
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
    # The Not saved probe has no config entry, so the page counts it edited (its crumb reads Edited). Its card still shows no amber dot and
    # no edited title or label: the card marks only a saved scene that is edited (kindEdited in app.html). Read as added, then after a rename.
    $probeOn = Select-Scene $ws 'kind-probe' 'Kind probe'
    Check 'Kind probe is selected (scope)' $probeOn 'the Scene section did not show Kind probe in time'
    if (-not $probeOn) { return }
    $crumb = Js $ws 'const c = document.getElementById("sedit"); return !!c && !c.hidden'
    Check 'Kind probe, as added: the crumb reads Edited, so the page counts it edited (control)' ($crumb -eq $true) 'the crumb does not read Edited'
    $probeJs = $kindJs + $dotJs + 'const p = cardsOf().find(c => c.id === "kind-probe").card; return { kind: p.querySelector(".kd").getAttribute("title"), dots: dotsIn(p), labels: editedLabels(p) }'
    $asAdded = Js $ws $probeJs
    Check 'Kind probe, as added: its card is Not saved (scope)' ($asAdded.kind -ceq 'Not saved') "kind title: '$($asAdded.kind)'"
    Check 'Kind probe, as added: its card shows no amber dot' ($asAdded.dots -eq 0) "amber dots in its bottom row: $($asAdded.dots)"
    Check 'Kind probe, as added: no title or label on its card says edited' ($asAdded.labels -eq 0) "titles or labels that say edited: $($asAdded.labels)"
    # The name is changed and committed, as a user does. The change stays in the work map, so the card is still Not saved.
    [void](Js $ws 'const f = document.getElementById("sceneName"); f.value = "Probe renamed"; f.dispatchEvent(new Event("change", { bubbles: true })); return true')
    $renamed = WaitFor $ws '(() => { const b = document.querySelector("[data-pick=kind-probe]"); return !!b && b.closest("article.card").textContent.includes("Probe renamed") })()' 30
    Check 'Kind probe, renamed: its card shows the new name (scope)' $renamed 'its card does not show the new name'
    if (-not $renamed) { return }
    $afterRename = Js $ws $probeJs
    Check 'Kind probe, renamed: its card is still Not saved (scope)' ($afterRename.kind -ceq 'Not saved') "kind title: '$($afterRename.kind)'"
    Check 'Kind probe, renamed: its card shows no amber dot' ($afterRename.dots -eq 0) "amber dots in its bottom row: $($afterRename.dots)"
    Check 'Kind probe, renamed: no title or label on its card says edited' ($afterRename.labels -eq 0) "titles or labels that say edited: $($afterRename.labels)"
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

  # ---- Split Cell (layout-free items 1-13; split-cell-notes.md; plan lane L2) --------------------------------------------------
  # Every check here is new. On main each one FAILs and names its cause (no menu, no button, no POST, no pin). No lookup throws: a
  # missing control answers null or false, and a POST check requires the route to have reached its click, so it cannot pass by accident.
  $splitWins = @(
    @('claude', 'Refactor the grid solver'), @('chrome', 'Quarterly roadmap'), @('chrome', 'Pull request 212'),
    @('WindowsTerminal', 'pwsh - tiler'), @('explorer', 'Projects'), @('ms-teams', 'Design sync'),
    @('claude', 'Pin parser edge cases'), @('WindowsTerminal', 'pwsh - docs watch'), @('explorer', 'Downloads'), @('notepad', 'todo.txt')
  )
  # The pin of window $i (an index into $splitWins) on these slots. $behind lists the windows stacked behind it.
  function Split-Pin([int]$i, $slots, [bool]$lock = $false, $behind = $null) {
    $p = [pscustomobject]@{ app = $splitWins[$i][0]; match = $splitWins[$i][1]; mon = 'U1'; slots = @($slots) }
    if ($lock) { $p | Add-Member -NotePropertyName lock -NotePropertyValue $true }
    if ($behind) { $p | Add-Member -NotePropertyName behind -NotePropertyValue @($behind) }
    $p
  }
  # The Focus scene's layout on the plugged setup, as JSON: the U1 grid (c by r, with mult and fill.unit when given), the pins, the zones,
  # and a fill on U1 that places nothing. $fillOver merges into the fill (held entries, off).
  function Split-Json([int]$c, [int]$r, $pins, $mult = $null, $unit = $null, $zones = @(), $fillOver = @{}) {
    $g = [ordered]@{ c = $c; r = $r }
    if ($mult) { $g['mult'] = @(@($mult) -split ',' | % { [int]$_ }) }
    $f = [ordered]@{ mon = 'U1'; apps = @(); skip = @(); sort = 'app' }
    if ($unit) { $f['unit'] = @(@($unit) -split ',' | % { [int]$_ }) }
    foreach ($k in $fillOver.Keys) { $f[$k] = $fillOver[$k] }
    ConvertTo-Json -Depth 12 -Compress -InputObject ([ordered]@{ grids = [ordered]@{ U1 = $g }; pins = @($pins); zones = @($zones); fill = $f; bay = @() })
  }
  function Put-Split([string]$json) { $cfg = New-Config; Add-Layout $cfg 'focus' $plugKey $json; Put-Config $cfg }
  # The integers of a value (a number, an array, or nothing), in order.
  function Split-Ints($v) { @(@($v) | ? { $null -ne $_ } | % { [int]$_ }) }
  # A grid axis or a unit as the page must leave it: its two numbers, or 1,1 when absent (a join drops it).
  function Split-Axis($v) { $x = (Split-Ints $v) -join ','; if ($x -eq '') { '1,1' } else { $x } }
  # The slots of the one pin with this match text, sorted and joined. A text that names no single pin says so.
  function Split-SlotsOf($layout, [string]$match) {
    $p = @(@($layout.pins) | ? { $_ -and [string]$_.match -ceq $match })
    if ($p.Count -ne 1) { return "no single pin for '$match'" }
    ((Split-Ints $p[0].slots | Sort-Object) -join ',')
  }
  # True when a pin, a zone or a held entry of the layout holds this slot.
  function Split-HasSlot($layout, [int]$slot) {
    $all = @(@($layout.pins) + @($layout.zones) + @($layout.fill.held) | ? { $_ })
    @($all | ? { (Split-Ints $_.slots) -contains $slot }).Count -gt 0
  }
  # The pins whose slots differ from $want (match text -> "a,b", sorted), one line each.
  function Split-Diff($layout, [hashtable]$want) {
    @(foreach ($m in $want.Keys) { $got = Split-SlotsOf $layout $m; if ($got -ne $want[$m]) { "'$m' has $got, want $($want[$m])" } })
  }
  # The checks on one split's layout, one check each so a failure names its cause: the grid keeps c and r and sets mult and unit; the
  # split window's pin holds its kept slot; every other pin in $want holds its doubled slots.
  function Split-Verify([string]$name, $layout, [int]$c, [int]$r, [string]$mult, [string]$unit, [string]$cutMatch, [string]$cutSlot, [hashtable]$want) {
    if (-not $layout) { Check "split: $name has a layout to check (not run: no POST /layout)" $false 'no POST /layout was sent, so there is no layout to read'; return }
    $g = $layout.grids.U1
    $gc = (Split-Ints $g.c) -join ','; $gr = (Split-Ints $g.r) -join ','
    Check "split: $name keeps c $c and r $r" (($gc -eq "$c") -and ($gr -eq "$r")) "c '$gc', r '$gr'"
    $gm = (Split-Ints $g.mult) -join ','
    Check "split: $name sets mult [$mult]" ($gm -eq $mult) "mult '$gm'"
    $fu = (Split-Ints $layout.fill.unit) -join ','
    Check "split: $name sets fill.unit [$unit]" ($fu -eq $unit) "fill.unit '$fu'"
    $cut = Split-SlotsOf $layout $cutMatch
    Check "split: $name pins the split window to slot $cutSlot" ($cut -eq $cutSlot) "its pin holds: $cut"
    $d = @(Split-Diff $layout $want)
    Check "split: $name doubles every other pin's slots" ($d.Count -eq 0) ($d -join ' | ')
  }
  # The other pins after a split of the 5 by 2 board (window 0 is the split window). Side: slot s -> 2s and 2s+1. Stacked: slot s in row r
  # -> s+5r and s+5(r+1). Join: every pin back to its own slot.
  $splitWantSide = @{ 'Quarterly roadmap' = '2,3'; 'Pull request 212' = '4,5'; 'pwsh - tiler' = '6,7'; 'Projects' = '8,9'; 'Design sync' = '10,11'; 'Pin parser edge cases' = '12,13'; 'pwsh - docs watch' = '14,15'; 'Downloads' = '16,17'; 'todo.txt' = '18,19' }
  $splitWantStack = @{ 'Quarterly roadmap' = '1,6'; 'Pull request 212' = '2,7'; 'pwsh - tiler' = '3,8'; 'Projects' = '4,9'; 'Design sync' = '10,15'; 'Pin parser edge cases' = '11,16'; 'pwsh - docs watch' = '12,17'; 'Downloads' = '13,18'; 'todo.txt' = '14,19' }
  $splitWantJoin = @{ 'Quarterly roadmap' = '1'; 'Pull request 212' = '2'; 'pwsh - tiler' = '3'; 'Projects' = '4'; 'Design sync' = '5'; 'Pin parser edge cases' = '6'; 'pwsh - docs watch' = '7'; 'Downloads' = '8'; 'todo.txt' = '9' }
  # A 2 by 4 board stacked: window 1 on slot 3, window 2 on slot 4, window 3 on slot 7 (rows 2 and 3 of the old 4-row cap).
  $splitWant2x4 = @{ 'Quarterly roadmap' = '5,7'; 'Pull request 212' = '8,10'; 'pwsh - tiler' = '13,15' }
  # JS, read in the page. The split menu is open. The inspector's Split Cell button is pressed (answers whether there is one).
  $splitMenuJs = '[...document.querySelectorAll("[role=menu]")].some(m => m.getClientRects().length > 0 && /Split Cell/.test(m.textContent))'
  $splitInspJs = 'const b = [...document.querySelectorAll("button")].find(x => /^Split Cell/.test(x.textContent.trim()) && x.getClientRects().length > 0 && !x.closest("[role=menu]")); if (!b) return false; b.click(); return true'
  # An expression, for WaitFor: the inspector's Split Cell button is on screen.
  $splitInspHasJs = '[...document.querySelectorAll("button")].some(x => /^Split Cell/.test(x.textContent.trim()) && x.getClientRects().length > 0 && !x.closest("[role=menu]"))'
  # preventScroll: a focus that scrolls the stage queues a scroll event for the next frame, and that event closes a split menu opened before it.
  function Split-FocusJs([int]$id) { 'const t = document.querySelector(".tile[data-id=\"__ID__\"]"); if (!t) return false; t.focus({ preventScroll: true }); return document.activeElement === t'.Replace('__ID__', "$id") }
  # JS: waits until window $id's tile is at rest: no ResizeObserver relayout queued (rlay), no transition running on it, and its rect unchanged over two
  # frame pairs. Answers true, or false after 5 seconds. A relayout or a transition lands on the frames after a selection, so a read before it is mid-move.
  $tileRestJs = @'
const t = document.querySelector('.tile[data-id="__ID__"]'); if (!t) return false;
const geo = () => { const r = t.getBoundingClientRect(); return [r.left, r.top, r.width, r.height].join(","); };
const moving = () => rlay !== 0 || t.getAnimations({ subtree: true }).length > 0;
let last = null, still = 0; const t0 = performance.now();
while (performance.now() - t0 < 5000 && still < 2) {
  await new Promise(r => requestAnimationFrame(() => requestAnimationFrame(r)));
  const g = geo(); still = (!moving() && g === last) ? still + 1 : 0; last = g;
}
return still >= 2;
'@
  # The wait and its Check are one statement, so the Check line prints and no caller captures it into a value.
  function Wait-Tile-Rest($sock, [int]$id, [string]$tag) {
    $rest = (Js $sock $tileRestJs.Replace('__ID__', "$id")) -eq $true
    Check "$tag, window $id is at rest (wait)" $rest 'the tile is missing, or it still moves (a layout or a transition) after 5 s'
  }
  # JS: finds the menu item "Claude Keeps <keep>" under the group label that starts with <dir>, clicks it, and answers its read-out
  # ({disabled, why}). Answers null when no such item is open.
  function Split-ItemJs([string]$dir, [string]$keep) {
    $js = @'
const menu = [...document.querySelectorAll("[role=menu]")].find(m => /Split Cell/.test(m.textContent));
if (!menu) return null;
let grp = "", hit = null;
for (const el of menu.querySelectorAll("p, [role=menuitem]")) {
  const t = el.textContent.replace(/\s+/g, " ").trim();
  if (el.tagName === "P") { grp = /^Side by Side/.test(t) ? "Side by Side" : /^Stacked/.test(t) ? "Stacked" : ""; continue; }
  if (grp === "__DIR__" && t.endsWith("Keeps __KEEP__")) { hit = el; break; }
}
if (!hit) return null;
const ids = (hit.getAttribute("aria-describedby") || "").split(/\s+/).filter(Boolean);
const why = [hit.getAttribute("title") || ""].concat(ids.map(i => (document.getElementById(i) || {}).textContent || "")).join(" ").replace(/\s+/g, " ").trim();
const disabled = hit.disabled === true || hit.getAttribute("aria-disabled") === "true";
hit.click();
return { disabled: disabled, why: why };
'@
    $js.Replace('__DIR__', $dir).Replace('__KEEP__', $keep)
  }
  # Selects a window as a user does: it takes focus, then Enter. Answers whether the page then has it selected.
  function Split-Select($sock, [int]$id) {
    if ((Js $sock (Split-FocusJs $id)) -ne $true) { return $false }
    Press-Key $sock 'Enter' 13
    WaitFor $sock "selWin === $id" 10
  }
  # One way in to a split, checked step by step. Selects window $id, opens the split menu with S ($route 'key') or with the inspector's Split
  # Cell button ($route 'button'), then clicks "Claude Keeps $keep" under "$dir". Answers the item's read-out ($info, null when there is none)
  # and the POSTs /layout the click sent after it. A missing control is a Check that names it.
  function Split-Route($sock, [int]$id, [string]$route, [string]$dir, [string]$keep, [string]$tag, [int]$postWait = 10) {
    # Its result goes to $script:splitLast, not the output: its Check lines are printed where they happen, and must not be captured.
    $out = [pscustomobject]@{ info = $null; sent = @() }
    $script:splitLast = $out
    $sel = Split-Select $sock $id
    Check "split: $tag, window $id is selected (control)" $sel "no tile $id, or Enter did not select it"
    if (-not $sel) { return }
    # A scroll event closes a split menu opened before it, and the selection's redraw and any relayout land on the frames after it. Wait for rest first.
    Wait-Tile-Rest $sock $id "split: $tag, after the selection"
    if ($route -eq 'key') { [void](Js $sock (Split-FocusJs $id)); Press-Key $sock 's' 83 's' }
    else {
      $btnOk = WaitFor $sock $splitInspHasJs 10
      Check "split: $tag, the inspector has a Split Cell button (scope)" $btnOk 'no Split Cell button in the inspector'
      if (-not $btnOk) { return }
      [void](Js $sock $splitInspJs)
    }
    $open = WaitFor $sock $splitMenuJs 10
    $how = if ($route -eq 'key') { 'S' } else { 'the Split Cell button' }
    Check "split: $tag, the split menu opens (scope)" $open "no split menu after $how"
    if (-not $open) { return }
    $before = [int](Js $sock 'return window.__h.posts("layout").length')
    $info = Js $sock (Split-ItemJs $dir $keep)
    Check "split: $tag, the menu has 'Claude Keeps $keep' under '$dir' (scope)" ($null -ne $info) "no menu item 'Claude Keeps $keep' under '$dir'"
    if ($null -eq $info) { return }
    $out.info = $info
    [void](WaitFor $sock ('window.__h.posts("layout").length > ' + $before) $postWait)
    $a = Js $sock ('await window.__h.settle(); return window.__h.posts("layout").slice(' + $before + ')')
    $out.sent = @($a | ? { $_ })
  }
  # tile.ps1 -Scene -From -Json, in process, as golden-layouts.ps1 runs it. Its slots come back 1-based (tile.ps1, the -Json line).
  function Split-Engine([string]$scene, [string]$snapJson) {
    $env:TILE_HOME = $tileHome; $env:TILE_SCREENS_FILE = $null
    try { $raw = (& (Join-Path $root 'tile.ps1') -Scene $scene -From $snapJson -Json 3>$null) -join '' } finally { $env:TILE_HOME = $null }
    if (-not $raw) { throw 'tile.ps1 printed nothing' }
    ConvertFrom-Json $raw
  }
  # The page's cellRect for each probe ({id, g: mult|plain, c0, r0, cs, rs, want}), against the engine's rect (want, "x,y,w,h"). Answers the
  # mismatches, one line each. The monitor is 1365 by 1001; c0, r0, cs and rs are in fine cells.
  function Split-Probe($sock, $probes) {
    $js = 'const Q = __Q__; const G = { mult: { c: 5, r: 2, mult: [2, 1] }, plain: { c: 5, r: 2 } }; const m = { x: 0, y: 0, w: 1365, h: 1001 }; return Q.map(q => { try { const r = cellRect(m, G[q.g], q.c0, q.r0, q.cs, q.rs); return [r.x, r.y, r.w, r.h].join(","); } catch (e) { return "error"; } }).join("|");'
    $q = ConvertTo-Json -Depth 4 -Compress -InputObject @($probes | % { [pscustomobject]@{ g = $_.g; c0 = $_.c0; r0 = $_.r0; cs = $_.cs; rs = $_.rs } })
    $got = ([string](Js $sock ($js.Replace('__Q__', $q)))) -split '\|'
    @(for ($i = 0; $i -lt @($probes).Count; $i++) { if ($got[$i] -ne $probes[$i].want) { "window $($probes[$i].id): page $($got[$i]), engine $($probes[$i].want)" } })
  }

  Case 'split: S, then Side by Side Claude Keeps Right, on a full 5 by 2 board: one POST /layout with the doubled grid and every pin doubled' {
    Put-Split (Split-Json 5 2 (0..9 | % { Split-Pin $_ @($_) }))
    $opened = Open-Page $ws $url 'focus'
    Check 'split: the page opens on Focus (control)' $opened 'the page did not open on Focus in time'
    if (-not $opened) { return }
    Split-Route $ws 1001 'key' 'Side by Side' 'Right' 'S, side by side'; $r = $script:splitLast
    $sent = @($r.sent | ? { $_ })
    Check 'split: S and the item send one POST /layout' ($sent.Count -eq 1) "POST /layout count: $($sent.Count)"
    $lay = if ($sent.Count -eq 1) { (ConvertFrom-Json $sent[0].body).layout } else { $null }
    Check 'split: the POST carries the plugged-in setup key' ($sent.Count -eq 1 -and ((ConvertFrom-Json $sent[0].body).key -ceq $plugKey)) 'no POST /layout to read the setup key from, or it carries another key'
    Split-Verify 'S, side by side' $lay 5 2 '2,1' '2,1' 'Refactor the grid solver' '1' $splitWantSide
  }

  Case 'split: the inspector Split Cell button, then Claude Keeps Left, on an empty board: one POST /layout, the grid doubled' {
    Put-Split (Split-Json 5 2 @(Split-Pin 0 @(0)))
    $opened = Open-Page $ws $url 'focus'
    Check 'split: the page opens on Focus (control)' $opened 'the page did not open on Focus in time'
    if (-not $opened) { return }
    Split-Route $ws 1001 'button' 'Side by Side' 'Left' 'Split Cell button, side by side'; $r = $script:splitLast
    $sent = @($r.sent | ? { $_ })
    Check 'split: the button and the item send one POST /layout' ($sent.Count -eq 1) "POST /layout count: $($sent.Count)"
    $lay = if ($sent.Count -eq 1) { (ConvertFrom-Json $sent[0].body).layout } else { $null }
    Split-Verify 'Split Cell button, side by side' $lay 5 2 '2,1' '2,1' 'Refactor the grid solver' '0' @{}
  }

  Case 'split: S, then Stacked Claude Keeps Top, on a 5 by 2 board: mult [1,2], fill.unit [1,2], every pin doubled by row' {
    Put-Split (Split-Json 5 2 (0..9 | % { Split-Pin $_ @($_) }))
    $opened = Open-Page $ws $url 'focus'
    Check 'split: the page opens on Focus (control)' $opened 'the page did not open on Focus in time'
    if (-not $opened) { return }
    Split-Route $ws 1001 'key' 'Stacked' 'Top' 'S, stacked'; $r = $script:splitLast
    $sent = @($r.sent | ? { $_ })
    Check 'split: S and the item send one POST /layout' ($sent.Count -eq 1) "POST /layout count: $($sent.Count)"
    $lay = if ($sent.Count -eq 1) { (ConvertFrom-Json $sent[0].body).layout } else { $null }
    Split-Verify 'S, stacked' $lay 5 2 '1,2' '1,2' 'Refactor the grid solver' '0' $splitWantStack
  }

  Case 'split: S, then Stacked Claude Keeps Top, on a 2 by 4 board (rows above the old cap of 4): mult [1,2], the 8 rows kept' {
    Put-Split (Split-Json 2 4 @((Split-Pin 0 @(0)), (Split-Pin 1 @(3)), (Split-Pin 2 @(4)), (Split-Pin 3 @(7))))
    $opened = Open-Page $ws $url 'focus'
    Check 'split: the page opens on Focus (control)' $opened 'the page did not open on Focus in time'
    if (-not $opened) { return }
    Split-Route $ws 1001 'key' 'Stacked' 'Top' 'S, stacked, 2 by 4'; $r = $script:splitLast
    $sent = @($r.sent | ? { $_ })
    Check 'split: S and the item send one POST /layout on a 2 by 4 board, rows above the old cap' ($sent.Count -eq 1) "POST /layout count: $($sent.Count)"
    $lay = if ($sent.Count -eq 1) { (ConvertFrom-Json $sent[0].body).layout } else { $null }
    Split-Verify 'S, stacked, 2 by 4' $lay 2 4 '1,2' '1,2' 'Refactor the grid solver' '0' $splitWant2x4
  }

  Case 'split: a locked tile cannot split: its split items are disabled with "Locked. Unlock it first.", and a click sends no POST /layout' {
    Put-Split (Split-Json 5 2 @(Split-Pin 0 @(0) $true))
    $opened = Open-Page $ws $url 'focus'
    Check 'split: the page opens on Focus (control)' $opened 'the page did not open on Focus in time'
    if (-not $opened) { return }
    Split-Route $ws 1001 'key' 'Side by Side' 'Left' 'locked tile' 3; $r = $script:splitLast
    $lk = Js $ws 'const t = document.querySelector(".tile[data-id=\"1001\"]"); return !!t && t.classList.contains("lock")'
    Check 'split: the window''s tile shows the lock (scope)' ($lk -eq $true) 'the tile has no lock class'
    $noItem = 'no such item was open in the split menu'
    Check 'split: the locked tile''s Side by Side item is disabled' ($null -ne $r.info -and [bool]$r.info.disabled) $(if ($null -eq $r.info) { $noItem } else { 'the item is enabled' })
    Check 'split: the disabled item gives the reason "Locked. Unlock it first."' ($null -ne $r.info -and ([string]$r.info.why -match 'Locked\. Unlock it first\.')) $(if ($null -eq $r.info) { $noItem } else { "reason: '$($r.info.why)'" })
    Check 'split: clicking the disabled item sends no POST /layout' ($null -ne $r.info -and @($r.sent | ? { $_ }).Count -eq 0) $(if ($null -eq $r.info) { 'no such item was open, so nothing was clicked' } else { "POST /layout count: $(@($r.sent | ? { $_ }).Count)" })
  }

  Case 'split: S with no window selected opens no split menu and sends no POST /layout (guard; green on main)' {
    Put-Split (Split-Json 5 2 @(Split-Pin 0 @(0)))
    $opened = Open-Page $ws $url 'focus'
    Check 'split: the page opens on Focus (control)' $opened 'the page did not open on Focus in time'
    if (-not $opened) { return }
    # "No selection": no window is selected (selWin null or unset, no .tile.sel), and the keypress goes to the board itself, not to a window.
    $none = Js $ws 'return (typeof selWin === "undefined" || selWin === null) && !document.querySelector(".tile.sel")'
    Check 'split: no window is selected before S (control)' ($none -eq $true) 'a window is selected'
    $focus = Js $ws 'const s = document.getElementById("stage"); if (!s) return false; s.focus(); return document.activeElement === s'
    Check 'split: the board, not a window, has focus when S is pressed (control)' ($focus -eq $true) 'the board did not take focus'
    Press-Key $ws 's' 83 's'
    [void](Js $ws 'await window.__h.settle(); return true')
    $menu = Js $ws $splitMenuJs
    Check 'split: S with no selection opens no split menu' ($menu -ne $true) 'a split menu opened'
    $a = Js $ws 'return window.__h.posts("layout")'
    $sent = @($a | ? { $_ })
    Check 'split: S with no selection sends no POST /layout' ($sent.Count -eq 0) "POST /layout count: $($sent.Count)"
  }

  Case 'split: J on the left half joins the halves: mult and fill.unit go back to [1,1], every pin halves back, one POST /layout' {
    $seed = @(Split-Pin 0 @(0)) + @(1..9 | % { Split-Pin $_ @((2 * $_), (2 * $_ + 1)) })
    Put-Split (Split-Json 5 2 $seed '2,1' '2,1')
    $opened = Open-Page $ws $url 'focus'
    Check 'split: the page opens on Focus (control)' $opened 'the page did not open on Focus in time'
    if (-not $opened) { return }
    $sel = Split-Select $ws 1001
    Check 'split: window 1001, on the left half, is selected (control)' $sel 'no tile 1001 to select'
    if (-not $sel) { return }
    $before = [int](Js $ws 'return window.__h.posts("layout").length')
    Press-Key $ws 'j' 74 'j'
    [void](WaitFor $ws ('window.__h.posts("layout").length > ' + $before) 10)
    $a = Js $ws ('await window.__h.settle(); return window.__h.posts("layout").slice(' + $before + ')')
    $sent = @($a | ? { $_ })
    Check 'split: J sends one POST /layout' ($sent.Count -eq 1) "POST /layout count: $($sent.Count)"
    $lay = if ($sent.Count -eq 1) { (ConvertFrom-Json $sent[0].body).layout } else { $null }
    if (-not $lay) { return }   # the count check above names the cause: J sent no POST /layout
    $g = $lay.grids.U1
    Check 'split: J keeps c 5 and r 2' (((Split-Ints $g.c) -join ',') -eq '5' -and ((Split-Ints $g.r) -join ',') -eq '2') "c/r after J: '$((Split-Ints $g.c) -join ',')', '$((Split-Ints $g.r) -join ',')'"
    # Absent or [1,1] both mean the grid is today's: the page may drop mult and unit, or write them as 1,1.
    Check 'split: J sets mult back to [1,1] (absent or 1,1)' ((Split-Axis $g.mult) -eq '1,1') "mult after J: '$(Split-Axis $g.mult)'"
    Check 'split: J sets fill.unit back to [1,1] (absent or 1,1)' ((Split-Axis $lay.fill.unit) -eq '1,1') "fill.unit after J: '$(Split-Axis $lay.fill.unit)'"
    Check 'split: J puts the split window on its whole cell, slot 0' ((Split-SlotsOf $lay 'Refactor the grid solver') -eq '0') "its pin holds: $(Split-SlotsOf $lay 'Refactor the grid solver')"
    $d = @(Split-Diff $lay $splitWantJoin)
    Check 'split: J halves every other pin back to its own cell' ($d.Count -eq 0) ($d -join ' | ')
  }

  Case 'split: cellRect on a split grid gives tile.ps1''s rect for every window at 1365 by 1001 (control: a plain 5 by 2 grid)' {
    $mon = [pscustomobject]@{ name = '\\.\DISPLAY1'; role = 'wide'; x = 0; y = 0; w = 1365; h = 1001; bw = 1365; bh = 1001 }
    $snap = ConvertTo-Json -Depth 8 -Compress -InputObject ([pscustomobject]@{ monitors = @($mon); windows = @($snapObj.windows) })
    # Control: ten windows, one per cell of a plain 5 by 2 grid. Green on main.
    $plainPins = @(0..9 | % { [pscustomobject]@{ app = $splitWins[$_][0]; match = $splitWins[$_][1]; mon = 'wide'; slots = @($_) } })
    $plainScene = ConvertTo-Json -Depth 8 -Compress -InputObject ([pscustomobject]@{ id = 'plain6'; name = 'Plain'; grids = [pscustomobject]@{ wide = [pscustomobject]@{ c = 5; r = 2 } }; pins = $plainPins; zones = @(); fill = [pscustomobject]@{ mon = 'wide'; apps = @(); skip = @(); sort = 'app' } })
    $pe = Split-Engine $plainScene $snap
    Check 'split: tile.ps1 places all 10 windows on the plain grid (scope)' (@($pe.placed).Count -eq 10) "placed: $(@($pe.placed).Count)"
    $pProbes = @(@($pe.placed) | % { $s = @(Split-Ints $_.slots | % { $_ - 1 } | Sort-Object); [pscustomobject]@{ id = [int64]$_.id; g = 'plain'; c0 = $s[0] % 5; r0 = [math]::Floor($s[0] / 5); cs = $s.Count; rs = 1; want = "$([int]$_.x),$([int]$_.y),$([int]$_.w),$([int]$_.h)" } })
    # Subject: 14 windows on a mult grid (c 5, r 2, mult [2,1]). Spans run across a base edge (1 and 2), halves sit on fine columns 1 and 3.
    $geo = @(
      @('claude', 'Refactor the grid solver', @(1, 2)), @('claude', 'Pin parser edge cases', @(0)), @('claude', 'Draft release notes', @(3)),
      @('chrome', 'Pull request 212', @(4, 5)), @('chrome', 'Quarterly roadmap', @(6)), @('chrome', 'quoted', @(7)),
      @('WindowsTerminal', 'pwsh - tiler', @(8, 9)), @('WindowsTerminal', 'pwsh - docs watch', @(10)), @('explorer', 'Projects', @(11)),
      @('explorer', 'Downloads', @(12, 13)), @('ms-teams', 'Design sync', @(14)), @('outlook', 'Inbox', @(15, 16)),
      @('notepad', 'todo.txt', @(17)), @('Spotify', 'Spotify', @(18, 19))
    )
    $splitPins = @($geo | % { [pscustomobject]@{ app = $_[0]; match = $_[1]; mon = 'wide'; slots = @($_[2]) } })
    $splitScene = ConvertTo-Json -Depth 8 -Compress -InputObject ([pscustomobject]@{ id = 'split6'; name = 'Split'; grids = [pscustomobject]@{ wide = [pscustomobject]@{ c = 5; r = 2; mult = @(2, 1) } }; pins = $splitPins; zones = @(); fill = [pscustomobject]@{ mon = 'wide'; apps = @(); skip = @(); sort = 'app' } })
    $se = Split-Engine $splitScene $snap
    Check 'split: tile.ps1 places all 14 windows on the split grid (scope)' (@($se.placed).Count -eq 14) "placed: $(@($se.placed).Count)"
    $sProbes = @(@($se.placed) | % { $s = @(Split-Ints $_.slots | % { $_ - 1 } | Sort-Object); [pscustomobject]@{ id = [int64]$_.id; g = 'mult'; c0 = $s[0] % 10; r0 = [math]::Floor($s[0] / 10); cs = $s.Count; rs = 1; want = "$([int]$_.x),$([int]$_.y),$([int]$_.w),$([int]$_.h)" } })
    Plug $snap
    $loaded = Go $ws $url 'typeof cellRect === "function"'
    Check 'split: the page has cellRect (control)' $loaded 'the page did not load cellRect in time'
    if (-not $loaded) { return }
    $pBad = @(Split-Probe $ws $pProbes)
    Check 'split: cellRect gives the engine rect for every plain-grid window (control)' ($pBad.Count -eq 0) ($pBad -join ' | ')
    $sBad = @(Split-Probe $ws $sProbes)
    Check 'split: cellRect gives the engine rect for every window on the split grid' ($sBad.Count -eq 0) ($sBad -join ' | ')
  }

  Case 'split: Undo after a split writes the layout back with one more POST /layout' {
    Put-Split (Split-Json 5 2 (0..9 | % { Split-Pin $_ @($_) }))
    $opened = Open-Page $ws $url 'focus'
    Check 'split: the page opens on Focus (control)' $opened 'the page did not open on Focus in time'
    if (-not $opened) { return }
    $pre = Js $ws 'return layoutOf(work.focus)'   # the layout the page shows before the split: Undo must write it back
    Split-Route $ws 1001 'key' 'Side by Side' 'Right' 'undo, S, side by side'; $r = $script:splitLast
    $sent = @($r.sent | ? { $_ })
    Check 'split: the split sends one POST /layout before Undo (scope)' ($sent.Count -eq 1) "POST /layout count: $($sent.Count)"
    if ($sent.Count -ne 1) { Check 'split: Undo writes the layout back with one more POST /layout (not run: the split sent nothing)' $false 'no split to undo'; return }
    $u = Js $ws 'const u = document.getElementById("undo"); if (!u || u.disabled) return false; u.click(); return true'
    Check 'split: Undo is enabled after the split (scope)' ($u -eq $true) 'Undo is missing or disabled'
    [void](WaitFor $ws 'window.__h.posts("layout").length > 1' 10)
    $a = Js $ws 'await window.__h.settle(); return window.__h.posts("layout")'   # one JSON array: assign it before @() (ConvertFrom-Json does not unroll it)
    $all = @($a | ? { $_ })
    Check 'split: Undo sends one more POST /layout (two in all)' ($all.Count -eq 2) "POST /layout count: $($all.Count)"
    $restored = ($all.Count -eq 2) -and ((Canon (ConvertFrom-Json $all[1].body).layout) -ceq (Canon $pre))
    Check 'split: Undo writes the layout back as it was before the split' $restored 'the layout Undo sent is not the one from before the split'
  }

  Case 'split: a stacked tile keeps its stack on the kept half: the back window stays on the front pin, and the kept half still shows the stack' {
    $back = [pscustomobject]@{ app = 'claude'; match = 'Pin parser edge cases' }
    Put-Split (Split-Json 5 2 @(Split-Pin 0 @(0) $false @($back)))
    $opened = Open-Page $ws $url 'focus'
    Check 'split: the page opens on Focus (control)' $opened 'the page did not open on Focus in time'
    if (-not $opened) { return }
    $stacked = Js $ws 'const t = document.querySelector(".tile[data-id=\"1001\"]"); return !!t && t.classList.contains("stacked")'
    Check 'split: window 1001 shows its stack before the split (control)' ($stacked -eq $true) 'the tile is not stacked'
    Split-Route $ws 1001 'key' 'Side by Side' 'Left' 'stacked tile'; $r = $script:splitLast
    $sent = @($r.sent | ? { $_ })
    Check 'split: the stacked tile sends one POST /layout' ($sent.Count -eq 1) "POST /layout count: $($sent.Count)"
    $lay = if ($sent.Count -eq 1) { (ConvertFrom-Json $sent[0].body).layout } else { $null }
    if (-not $lay) { return }   # the count check above names the cause
    $front = @(@($lay.pins) | ? { $_ -and [string]$_.match -ceq 'Refactor the grid solver' })
    $behind = if ($front.Count -eq 1) { (@(@($front[0].behind) | ? { $_ } | % { [string]$_.match }) -join ',') } else { 'no single front pin' }
    Check 'split: the back window stays behind the front pin' ($behind -eq 'Pin parser edge cases') "behind: '$behind'"
    $own = @(@($lay.pins) | ? { $_ -and [string]$_.match -ceq 'Pin parser edge cases' }).Count
    Check 'split: the back window has no pin of its own' ($own -eq 0) "pins of its own: $own"
    Check 'split: the front window keeps the left half, slot 0' ((Split-SlotsOf $lay 'Refactor the grid solver') -eq '0') "its pin holds: $(Split-SlotsOf $lay 'Refactor the grid solver')"
    $sg = Js $ws 'await window.__h.settle(); const t = document.querySelector(".tile[data-id=\"1001\"]"); return !!t && t.classList.contains("stacked")'
    Check 'split: the kept half still shows the stack (strip and badge)' ($sg -eq $true) 'the kept half is not stacked'
  }

  Case 'split: a cell in a zone: the zone takes both halves and its other cell doubles, and the window keeps its half' {
    $zone = [pscustomobject]@{ mon = 'U1'; app = 'claude'; slots = @(0, 5) }
    Put-Split (Split-Json 5 2 @(Split-Pin 0 @(0)) $null $null @($zone))
    $opened = Open-Page $ws $url 'focus'
    Check 'split: the page opens on Focus (control)' $opened 'the page did not open on Focus in time'
    if (-not $opened) { return }
    $zc = Js $ws 'return document.querySelectorAll(".zone").length'
    Check 'split: the zone is drawn before the split (control)' ([int]$zc -gt 0) 'no zone on the board'
    Split-Route $ws 1001 'key' 'Side by Side' 'Right' 'zone cell'; $r = $script:splitLast
    $sent = @($r.sent | ? { $_ })
    Check 'split: the zone cell sends one POST /layout' ($sent.Count -eq 1) "POST /layout count: $($sent.Count)"
    $lay = if ($sent.Count -eq 1) { (ConvertFrom-Json $sent[0].body).layout } else { $null }
    if (-not $lay) { return }   # the count check above names the cause
    $zs = if ($lay) { @(@($lay.zones) | ? { $_ -and [string]$_.app -ceq 'claude' })[0] } else { $null }
    $zslots = if ($zs) { (Split-Ints $zs.slots | Sort-Object) -join ',' } else { 'no zone' }
    Check 'split: the zone takes both halves of cell 0 and doubles cell 5: slots 0,1,10,11' ($zslots -eq '0,1,10,11') "zone slots: $zslots"
    Check 'split: the window in the zone keeps the right half, slot 1' ((Split-SlotsOf $lay 'Refactor the grid solver') -eq '1') "its pin holds: $(Split-SlotsOf $lay 'Refactor the grid solver')"
  }

  Case 'split: a held cell with fill off: the split pins the held window and drops its hold, the other hold doubles, the open half stays empty' {
    $held = @(
      [pscustomobject]@{ mon = 'U1'; slots = @(0); id = 1001; app = 'claude'; title = 'Refactor the grid solver' },
      [pscustomobject]@{ mon = 'U1'; slots = @(6); id = 1002; app = 'claude'; title = 'Pin parser edge cases' })
    Put-Split (Split-Json 5 2 @() $null $null @() @{ off = $true; held = $held })
    $opened = Open-Page $ws $url 'focus'
    Check 'split: the page opens on Focus (control)' $opened 'the page did not open on Focus in time'
    if (-not $opened) { return }
    Split-Route $ws 1001 'key' 'Side by Side' 'Left' 'held cell'; $r = $script:splitLast
    $sent = @($r.sent | ? { $_ })
    Check 'split: the held cell sends one POST /layout' ($sent.Count -eq 1) "POST /layout count: $($sent.Count)"
    $lay = if ($sent.Count -eq 1) { (ConvertFrom-Json $sent[0].body).layout } else { $null }
    if (-not $lay) { return }   # the count check above names the cause
    Check 'split: the held window is pinned to the kept half, slot 0' ((Split-SlotsOf $lay 'Refactor the grid solver') -eq '0') "its pin holds: $(Split-SlotsOf $lay 'Refactor the grid solver')"
    $hs = @(@($lay.fill.held) | ? { $_ })
    Check 'split: the split drops the hold on the split window' (@($hs | ? { [string]$_.title -ceq 'Refactor the grid solver' }).Count -eq 0) 'its hold is still in fill.held'
    $other = (@($hs | ? { [string]$_.title -ceq 'Pin parser edge cases' } | % { (Split-Ints $_.slots | Sort-Object) -join ',' }) -join '|')
    Check 'split: the other hold doubles to slots 12,13' ($other -eq '12,13') "its hold: '$other'"
    Check 'split: the open half, slot 1, is held by nothing' ($null -ne $lay -and -not (Split-HasSlot $lay 1)) 'slot 1 is named by a pin, a zone or a hold'
    Check 'split: fill stays off' ($null -ne $lay -and $lay.fill.off -eq $true) 'fill.off is not true after the split'
  }

  # ---- Split Cell: small halves, notes and the split menu (layout-free items 4, 12, 13; split-cell-notes S5; plan lane L2) ------------
  # Each case seeds its own layout, sets its own viewport and theme, and resets them in finally, so no case depends on another.
  # A control is green on main. Each red check names its cause in its detail. A case checks its scope before it reads its subject.
  $smallBack = [pscustomobject]@{ app = 'claude'; match = 'Pin parser edge cases' }
  $halfSeed = @(Split-Pin 0 @(0)) + @(1..9 | % { Split-Pin $_ @((2 * $_), (2 * $_ + 1)) })
  $halfStackSeed = @(Split-Pin 0 @(0)) + @(1..9 | % { $i = $_; $row = [int][math]::Floor($i / 5); Split-Pin $i @(($i + 5 * $row), ($i + 5 * ($row + 1))) })
  $tileJs = @'
try {
const t = document.querySelector('.tile[data-id="__ID__"]'); if (!t) return null;
const R = e => { const r = e.getBoundingClientRect(); return { l: r.left, t: r.top, r: r.right, b: r.bottom, w: r.width, h: r.height }; };
const disp = s => { const e = t.querySelector(s); return e ? getComputedStyle(e).display : "missing"; };
const span = t.children[1], tag = t.firstChild, sp = t.querySelector(".stayput");
const sc = getComputedStyle(span), sr = span.getBoundingClientRect(), tr = R(t), gr = R(tag);
return { w: tr.w, tile: tr, lk: disp(".lk"), rsz: disp(".rsz"), stk: disp(".stk"), sp: disp(".stayput"),
  spRect: sp && getComputedStyle(sp).display !== "none" ? R(sp) : null,
  titleShown: sc.display !== "none" && sc.visibility !== "hidden" && parseFloat(sc.opacity) > 0 && sr.width > 0 && sr.height > 0,
  tag: tag.textContent, tagSW: tag.scrollWidth, tagCW: tag.clientWidth, tagL: gr.l, tagR: gr.r, tileL: tr.l, tileR: tr.r,
  tagIn: gr.l >= tr.l - 0.5 && gr.r <= tr.r + 0.5, lock: t.classList.contains("lock"), stacked: t.classList.contains("stacked") };
} catch (e) { return { error: String(e) }; }
'@
  $splitNoteJs = 'const s = document.querySelector(".dnote span"); return s ? s.textContent.replace(/\s+/g, " ").trim() : null'
  $splitReadJs = @'
const m = document.getElementById("smenu"); if (!m) return null;
const fill = s => { const e = m.querySelector(s); return e ? getComputedStyle(e).fill : null; };
const h = m.querySelector("#smh");
return { title: h ? h.textContent.replace(/\s+/g, " ").trim() : "", join: fill('[data-sp="join"] .gl .k'), keep: fill('[data-sp]:not([data-sp="join"]):not([aria-disabled="true"]) .gl .k') };
'@
  $splitFrameJs = 'await Promise.race([new Promise(r => requestAnimationFrame(() => requestAnimationFrame(r))), new Promise(r => setTimeout(r, 2000))]); return true'
  function Tile-Metrics($sock, [int]$id) { Js $sock $tileJs.Replace('__ID__', "$id") }
  # True when rect $a lies inside rect $b, with half a pixel of slack.
  function Inside($a, $b) { ($a.l -ge $b.l - 0.5) -and ($a.r -le $b.r + 0.5) -and ($a.t -ge $b.t - 0.5) -and ($a.b -le $b.b + 0.5) }
  function Set-View($sock, [int]$w, [int]$h) { [void](Cdp $sock 'Emulation.setDeviceMetricsOverride' @{ width = $w; height = $h; deviceScaleFactor = 1; mobile = $false }) }
  # The page's own theme, set as its theme control sets it; nothing is stored.
  function Set-Theme($sock, [string]$t) { [void](Js $sock ("setTheme('" + $t + "'); return true")) }
  function Reset-Look($sock) {
    try { [void](Cdp $sock 'Emulation.clearDeviceMetricsOverride') } catch { }
    try { [void](Js $sock "setTheme('system'); return true") } catch { }
  }
  # A right-click as a mouse makes it: pressed, then released, at the point.
  function Click-Right($sock, [double]$x, [double]$y) {
    [void](Cdp $sock 'Input.dispatchMouseEvent' @{ type = 'mousePressed'; x = $x; y = $y; button = 'right'; buttons = 2; clickCount = 1 })
    [void](Cdp $sock 'Input.dispatchMouseEvent' @{ type = 'mouseReleased'; x = $x; y = $y; button = 'right'; buttons = 0; clickCount = 1 })
  }
  # A double-click as a mouse makes it: a move to the point, then two presses and releases, the second pair with clickCount 2. The page's
  # dblclick comes from those events, not from a synthetic dblclick.
  function Click-Double($sock, [double]$x, [double]$y) {
    [void](Cdp $sock 'Input.dispatchMouseEvent' @{ type = 'mouseMoved'; x = $x; y = $y })
    foreach ($n in 1, 2) {
      [void](Cdp $sock 'Input.dispatchMouseEvent' @{ type = 'mousePressed'; x = $x; y = $y; button = 'left'; buttons = 1; clickCount = $n })
      [void](Cdp $sock 'Input.dispatchMouseEvent' @{ type = 'mouseReleased'; x = $x; y = $y; button = 'left'; buttons = 0; clickCount = $n })
    }
  }
  # The centre of window $id's tile, and whether that point lands on the tile and not on a button in it (a click on a button is not the tile's).
  function Tile-Centre($sock, [int]$id) {
    Js $sock ('const t = document.querySelector(".tile[data-id=\"__ID__\"]"); if (!t) return null; const r = t.getBoundingClientRect(); const x = r.left + r.width / 2, y = r.top + r.height / 2; const el = document.elementFromPoint(x, y); return { x: x, y: y, hit: t.contains(el) && !(el && el.closest("button")) };'.Replace('__ID__', "$id"))
  }
  # The layout POSTs the page sent after the first $before of them, once the page has settled (its own timers and requests included).
  # The comma keeps an empty or a one-item list a list: a function's output is unrolled, so a bare one-item array would come back as the item.
  function Layout-Posts-After($sock, [int]$before) {
    , @((Js $sock ('await window.__h.settle(); return window.__h.posts("layout").slice(' + $before + ')')) | ? { $_ })
  }
  # Opens the split menu of window $id with its focus and S, without selecting it first. Answers the menu's read-out, or null.
  function Split-Menu-Open($sock, [int]$id) {
    if ((Js $sock 'return !!document.getElementById("smenu")') -eq $true) { Press-Key $sock 'Escape' 27 }
    # The tile takes focus on each poll until it holds it, so the S press reaches the tile and not a node the page just replaced.
    # preventScroll keeps the harness's own focus from scrolling the stage, and a scroll event would close the menu it opens.
    $focusCond = '(() => { const t = document.querySelector(".tile[data-id=\"' + $id + '\"]"); if (!t) return false; t.focus({ preventScroll: true }); return document.activeElement === t; })()'
    [void](WaitFor $sock $focusCond 10); [void](Js $sock $splitFrameJs); Press-Key $sock 's' 83 's'
    if (-not (WaitFor $sock $splitMenuJs 10)) { return $null }
    Js $sock $splitReadJs
  }
  # Selects window $id, then opens its split menu with S. Answers the menu's read-out, or null.
  function Split-Open($sock, [int]$id) {
    if (-not (Split-Select $sock $id)) { return $null }
    Split-Menu-Open $sock $id
  }
  # Clicks the open split menu's item for dir and keep, waits for the POST it sends, and answers the item, the POSTs sent and the drop note.
  function Split-Pick($sock, [string]$dir, [string]$keep) {
    $before = [int](Js $sock 'return window.__h.posts("layout").length')
    $info = Js $sock (Split-ItemJs $dir $keep)
    if ($null -eq $info) { return [pscustomobject]@{ item = $null; sent = 0; note = $null } }
    [void](WaitFor $sock ('window.__h.posts("layout").length > ' + $before) 10)
    [void](Js $sock 'await window.__h.settle(); return true')
    $after = [int](Js $sock 'return window.__h.posts("layout").length')
    [pscustomobject]@{ item = $info; sent = $after - $before; note = (Js $sock $splitNoteJs) }
  }

  Case 'split small: an unsplit tile under 40px keeps its lock, grip and badge (red: the tiny rule hides them on any small tile)' {
    # Window 1001 is unlocked and stacked (grip and badge); window 1006 is locked (lock). A lock hides the grip, so they are not one tile.
    Put-Split (Split-Json 10 2 @((Split-Pin 0 @(0) $false @($smallBack)), (Split-Pin 1 @(1) $true)))
    Set-View $ws 1024 900
    try {
      $opened = Open-Page $ws $url 'focus'
      Check 'split small: the page opens on Focus at 1024 (control)' $opened 'the page did not open on Focus in time'
      if (-not $opened) { return }
      $sel = Split-Select $ws 1001
      Check 'split small: window 1001 is selected (control)' $sel 'no tile 1001 to select'
      Wait-Tile-Rest $ws 1001 'split small'
      $m = Tile-Metrics $ws 1001
      Wait-Tile-Rest $ws 1006 'split small'
      $lk = Tile-Metrics $ws 1006
      $plain = Js $ws 'return layoutOf(work.focus).grids.U1.mult === undefined'
      Check 'split small: window 1001 is an unlocked, stacked, unsplit tile under 40px wide (scope)' ($m -and $m.w -gt 0 -and $m.w -lt 40 -and $m.stacked -eq $true -and $m.lock -eq $false -and $plain -eq $true) "width $(if ($m) { $m.w }), stacked: $(if ($m) { $m.stacked }), locked: $(if ($m) { $m.lock }), mult absent: $plain"
      Check 'split small: window 1006 is a locked, unsplit tile under 40px wide (scope)' ($lk -and $lk.w -gt 0 -and $lk.w -lt 40 -and $lk.lock -eq $true) "width $(if ($lk) { $lk.w }), locked: $(if ($lk) { $lk.lock })"
      Check 'split small: the locked unsplit tile under 40px keeps its lock' ($lk -and $lk.lk -ne 'none') "lock display: $(if ($lk) { $lk.lk })"
      Check 'split small: the unsplit tile under 40px keeps its grip' ($m -and $m.rsz -ne 'none') "grip display: $(if ($m) { $m.rsz })"
      Check 'split small: the unsplit stacked tile under 40px keeps its stack badge' ($m -and $m.stk -ne 'none') "badge display: $(if ($m) { $m.stk })"
      Check 'split small: the selected unsplit tile under 40px keeps Stay Put (control)' ($m -and $m.sp -ne 'none') "Stay Put display: $(if ($m) { $m.sp })"
    } finally { Reset-Look $ws }
  }

  Case 'split small: the same unsplit tile at 1440 is 40px or wider and keeps its lock, grip and badge (control)' {
    Put-Split (Split-Json 10 2 @((Split-Pin 0 @(0) $false @($smallBack)), (Split-Pin 1 @(1) $true)))
    Set-View $ws 1440 900
    try {
      $opened = Open-Page $ws $url 'focus'
      Check 'split small: the page opens on Focus at 1440 (control)' $opened 'the page did not open on Focus in time'
      if (-not $opened) { return }
      $sel = Split-Select $ws 1001
      Check 'split small: window 1001 is selected at 1440 (control)' $sel 'no tile 1001 to select'
      Wait-Tile-Rest $ws 1001 'split small at 1440'
      $m = Tile-Metrics $ws 1001
      Wait-Tile-Rest $ws 1006 'split small at 1440'
      $lk = Tile-Metrics $ws 1006
      Check 'split small: window 1001 is an unsplit tile 40px or wider at 1440 (scope)' ($m -and $m.w -ge 40) "width $(if ($m) { $m.w })"
      Check 'split small: at 1440 the locked unsplit tile keeps its lock (control)' ($lk -and $lk.lk -ne 'none') "lock display: $(if ($lk) { $lk.lk })"
      Check 'split small: at 1440 the unlocked unsplit tile keeps its grip (control)' ($m -and $m.rsz -ne 'none') "grip display: $(if ($m) { $m.rsz })"
      Check 'split small: at 1440 the unlocked unsplit stacked tile keeps its badge (control)' ($m -and $m.stk -ne 'none') "badge display: $(if ($m) { $m.stk })"
    } finally { Reset-Look $ws }
  }

  Case 'split small: a split half under 40px gives up its lock, grip and badge, as the design sets (control)' {
    $seedBack = @(Split-Pin 0 @(0) $false @($smallBack)) + @(1..9 | % { Split-Pin $_ @((2 * $_), (2 * $_ + 1)) })
    Put-Split (Split-Json 5 2 $seedBack '2,1' '2,1')
    Set-View $ws 1024 900
    try {
      $opened = Open-Page $ws $url 'focus'
      Check 'split small: the page opens on Focus at 1024 with a split grid (control)' $opened 'the page did not open on Focus in time'
      if (-not $opened) { return }
      $sel = Split-Select $ws 1001
      Check 'split small: window 1001 is selected (control)' $sel 'no tile 1001 to select'
      Wait-Tile-Rest $ws 1001 'split small, split half'
      $m = Tile-Metrics $ws 1001
      $grid = Js $ws 'return layoutOf(work.focus).grids.U1.mult'
      Check 'split small: window 1001 is a split half under 40px wide, on a grid with mult 2,1 (scope)' ($m -and $m.w -gt 0 -and $m.w -lt 40 -and ((@($grid) -join ',') -eq '2,1')) "width $(if ($m) { $m.w }), mult: $(@($grid) -join ',')"
      Check 'split small: the split half gives up its lock, as the design sets (control)' ($m -and $m.lk -eq 'none') "lock display: $(if ($m) { $m.lk })"
      Check 'split small: the split half gives up its grip, as the design sets (control)' ($m -and $m.rsz -eq 'none') "grip display: $(if ($m) { $m.rsz })"
      Check 'split small: the split half gives up its badge, as the design sets (control)' ($m -and $m.stk -eq 'none') "badge display: $(if ($m) { $m.stk })"
    } finally { Reset-Look $ws }
  }

  Case 'split small: a narrow half at 1024 (21px in this harness; the brief said 27px) draws no window title, its tag is one initial, and a selected Stay Put stays inside the half' {
    Put-Split (Split-Json 5 2 $halfSeed '2,1' '2,1')
    Set-View $ws 1024 900
    try {
      $opened = Open-Page $ws $url 'focus'
      Check 'split small: the page opens on Focus at 1024 with a split grid (control)' $opened 'the page did not open on Focus in time'
      if (-not $opened) { return }
      $sel = Split-Select $ws 1001
      Check 'split small: window 1001, the left half, is selected (control)' $sel 'no tile 1001 to select'
      Wait-Tile-Rest $ws 1001 'split small, narrow half'
      $m = Tile-Metrics $ws 1001
      Check 'split small: window 1001 is a split half under 40px wide at 1024 (scope)' ($m -and $m.w -gt 0 -and $m.w -lt 40) "width $(if ($m) { $m.w })"
      Check 'split small: the half tag is one initial (control)' ($m -and ([string]$m.tag) -match '^\S$') "tag: '$(if ($m) { $m.tag })'"
      Check 'split small: the half initial is not cut off inside its tag (text fits the tag box)' ($m -and $m.tagSW -le ($m.tagCW + 0.5)) "tag text width $(if ($m) { $m.tagSW }), tag box width $(if ($m) { $m.tagCW })"
      Check 'split small: the half initial sits inside the half, not past its edge (control)' ($m -and $m.tagIn -eq $true) "tag box x $(if ($m) { [math]::Round($m.tagL, 1) }) to $(if ($m) { [math]::Round($m.tagR, 1) }), half x $(if ($m) { [math]::Round($m.tileL, 1) }) to $(if ($m) { [math]::Round($m.tileR, 1) })"
      Check 'split small: the half draws no window title, only its initial (the mockup shows the initial only)' ($m -and $m.titleShown -eq $false) 'the window title is drawn inside the half'
      Check 'split small: a selected half keeps Stay Put inside the half, or gives it way' ($m -and ($null -eq $m.spRect -or (Inside $m.spRect $m.tile))) 'Stay Put is drawn outside the half (its rect is past the half edge)'
    } finally { Reset-Look $ws }
  }

  Case 'split note: joining a split of cell 2 says "Joined cell 2." and the cell it names holds the joined window once the grid halves back (item 13)' {
    Put-Split (Split-Json 5 2 (0..9 | % { Split-Pin $_ @($_) }))
    Set-View $ws 1440 900
    try {
      $opened = Open-Page $ws $url 'focus'
      Check 'split note: the page opens on Focus (control)' $opened 'the page did not open on Focus in time'
      if (-not $opened) { return }
      $menu = Split-Open $ws 1006
      Check 'split note: S opens the split menu of window 1006, in cell 2 (scope)' ($null -ne $menu) 'no split menu after S'
      if ($null -eq $menu) { return }
      $first = Split-Pick $ws 'Side by Side' 'Left'
      Check 'split note: the split sends one POST /layout (scope)' ($null -ne $first.item -and $first.sent -eq 1) "item sent: $($null -ne $first.item), POST /layout count: $($first.sent)"
      Check 'split note: the first split names the cell it cuts, "Split cell 2." (control)' ([string]$first.note -match '^Split cell 2\.') "note: '$($first.note)'"
      [void](Js $ws (Split-FocusJs 1006))
      Press-Key $ws 'j' 74 'j'
      [void](WaitFor $ws 'window.__h.posts("layout").length > 1' 15)
      [void](Js $ws 'await window.__h.settle(); return true')
      $j = Js $ws $splitNoteJs
      Check 'split note: joining that split says "Joined cell 2." (today it names the fine cell 3)' ([string]$j -match '^Joined cell 2\.') "note: '$j'"
      Check 'split note: the joined grid reads 5x2 again, as the note says (control)' ([string]$j -match 'The grid is 5\D2 again\.') "note: '$j'"
      [void](WaitFor $ws '(() => { const q = prev() && prev().placed.find(x => x.id === 1006 && !x.behind); return !!q && q.slots.length === 1 && q.slots[0] === 2; })()' 15)
      $held = Js $ws 'const q = prev() && prev().placed.find(x => x.id === 1006 && !x.behind); return q ? q.slots : null'
      $named = if ([string]$j -match 'Joined cell (\d+)\.') { [int]$matches[1] } else { 0 }
      Check 'split note: the cell the join names holds the joined window on the 5x2 grid (today it names a cell another window holds)' ($named -gt 0 -and (@(Split-Ints $held) -contains $named)) "the note names cell $named; window 1006 holds slot(s) $(@(Split-Ints $held) -join ',')"
    } finally { Reset-Look $ws }
  }

  foreach ($v in @(@{ label = 'side by side'; dir = 'Side by Side'; keep = 'Right' }, @{ label = 'stacked'; dir = 'Stacked'; keep = 'Top' })) {
    Case ('split note: a ' + $v.label + ' second split of window 1005, on two fine cells, names its original cell: Split Cell 3 and Split cell 3') {
      Put-Split (Split-Json 5 2 $halfSeed '2,1' '2,1')
      Set-View $ws 1440 900
      try {
        $opened = Open-Page $ws $url 'focus'
        Check 'split note: the page opens on Focus with a split grid (control)' $opened 'the page did not open on Focus in time'
        if (-not $opened) { return }
        $menu = Split-Open $ws 1005
        Check ('split menu: S opens the menu of window 1005 on its ' + $v.label + ' second split (scope)') ($null -ne $menu) 'no split menu after S'
        if ($null -eq $menu) { return }
        Check 'split menu: a second split titles its menu with the original cell, "Split Cell 3" (today it names the fine cells 5+6)' ($menu.title -eq 'Split Cell 3') "title: '$($menu.title)'"
        $p = Split-Pick $ws $v.dir $v.keep
        Check ('split note: the ' + $v.label + ' second split sends one POST /layout (scope)') ($null -ne $p.item -and $p.sent -eq 1) "item sent: $($null -ne $p.item), POST /layout count: $($p.sent)"
        Check 'split note: the second split names the original cell, "Split cell 3." (today it names "5+6")' ([string]$p.note -match '^Split cell 3\.') "note: '$($p.note)'"
      } finally { Reset-Look $ws }
    }
  }

  Case 'split note: a second split of the half of cell 1 keeps its number, Split Cell 1 and Split cell 1 (control)' {
    Put-Split (Split-Json 5 2 $halfSeed '2,1' '2,1')
    Set-View $ws 1440 900
    try {
      $opened = Open-Page $ws $url 'focus'
      Check 'split note: the page opens on Focus with a split grid (control)' $opened 'the page did not open on Focus in time'
      if (-not $opened) { return }
      $menu = Split-Open $ws 1001
      Check 'split menu: S opens the menu of window 1001, the half of cell 1 (scope)' ($null -ne $menu) 'no split menu after S'
      if ($null -eq $menu) { return }
      Check 'split menu: the menu of the half of cell 1 is titled "Split Cell 1" (control)' ($menu.title -eq 'Split Cell 1') "title: '$($menu.title)'"
      $p = Split-Pick $ws 'Stacked' 'Top'
      Check 'split note: the second split of the half sends one POST /layout (scope)' ($null -ne $p.item -and $p.sent -eq 1) "item sent: $($null -ne $p.item), POST /layout count: $($p.sent)"
      Check 'split note: the second split of the half names cell 1, "Split cell 1." (control)' ([string]$p.note -match '^Split cell 1\.') "note: '$($p.note)'"
    } finally { Reset-Look $ws }
  }

  Case 'split menu: the first right-click on an unselected window opens its split menu, though selecting it scrolls the inspector' {
    Put-Split (Split-Json 5 2 @(Split-Pin 0 @(0) $false @($smallBack)))
    Set-View $ws 1440 600
    try {
      $opened = Open-Page $ws $url 'focus'
      Check 'split menu: the page opens on Focus at 1440 by 600 (control)' $opened 'the page did not open on Focus in time'
      if (-not $opened) { return }
      $pre = Js $ws 'const t = document.querySelector(".tile[data-id=\"1001\"]"); return { stacked: !!t && t.classList.contains("stacked"), sel: !!document.querySelector(".tile.sel") };'
      Check 'split menu: window 1001 is stacked and no window is selected before the right-click (control)' ($pre.stacked -eq $true -and $pre.sel -eq $false) "stacked: $($pre.stacked), a window selected: $($pre.sel)"
      $pt = Js $ws 'const t = document.querySelector(".tile[data-id=\"1001\"]"); if (!t) return null; const r = t.getBoundingClientRect(); const x = r.left + r.width / 2, y = r.top + r.height / 2; return { x: x, y: y, hit: t.contains(document.elementFromPoint(x, y)) };'
      Check 'split menu: the pointer lands on window 1001 (scope)' ($pt -and $pt.hit -eq $true) 'the pointer does not land on window 1001'
      if (-not ($pt -and $pt.hit -eq $true)) { return }
      Click-Right $ws ([double]$pt.x) ([double]$pt.y)
      [void](Js $ws $splitFrameJs)
      $a = Js $ws 'const h = document.getElementById("winh"), ins = h ? h.closest(".insp") : null; return { sel: typeof selWin === "undefined" ? null : selWin, scroll: ins ? ins.scrollTop : null, menu: !!document.getElementById("smenu") };'
      Check 'split menu: the right-click selects window 1001 (control)' ($a -and $a.sel -eq 1001) "selected: $(if ($a) { $a.sel })"
      Check 'split menu: selecting it scrolls the inspector (scope: the case reaches the scroll)' ($a -and $a.scroll -gt 0) "inspector scrollTop: $(if ($a) { $a.scroll })"
      Check 'split menu: the first right-click opens the split menu, though the inspector scroll that selects the window follows it (today that scroll closes it)' ($a -and $a.menu -eq $true) 'the split menu is closed after the inspector scroll'
      if ($a -and $a.menu -eq $true) { Press-Key $ws 'Escape' 27 }
      Click-Right $ws ([double]$pt.x) ([double]$pt.y)
      [void](Js $ws $splitFrameJs)
      $b = Js $ws 'return !!document.getElementById("smenu")'
      Check 'split menu: a right-click on the selected window opens its split menu (control)' ($b -eq $true) 'no split menu after the second right-click'
    } finally { Reset-Look $ws }
  }

  foreach ($v in @(@{ label = 'a side half'; seed = $halfSeed; mult = '2,1' }, @{ label = 'a stacked half'; seed = $halfStackSeed; mult = '1,2' })) {
    Case ('split menu: the Join Halves icon on ' + $v.label + ' has the window category colour, in light and in dark (today it is black)') {
      Put-Split (Split-Json 5 2 $v.seed $v.mult $v.mult)
      Set-View $ws 1440 900
      try {
        $opened = Open-Page $ws $url 'focus'
        Check 'split menu: the page opens on Focus with a split grid (control)' $opened 'the page did not open on Focus in time'
        if (-not $opened) { return }
        # Selected first: a pinned narrow window that S selects scrolls the inspector, and that scroll closes the menu S opens.
        $selOk = Split-Select $ws 1001
        Check 'split menu: window 1001 is selected before S, so the menu is not closed by the inspector scroll (control)' $selOk 'no tile 1001 to select'
        foreach ($theme in @('light', 'dark')) {
          Set-Theme $ws $theme
          $menu = Split-Menu-Open $ws 1001
          $state = if ($null -eq $menu) { Js $ws 'return { active: document.activeElement ? (document.activeElement.className || document.activeElement.tagName) : null, dataId: document.activeElement ? document.activeElement.getAttribute("data-id") : null, sel: typeof selWin === "undefined" ? null : selWin, busy: typeof isBusy === "undefined" ? null : isBusy }' } else { $null }
          Check ('split menu: the split menu opens on ' + $v.label + ', in ' + $theme + ' (scope)') ($null -ne $menu) ("no split menu after S; page state: " + (ConvertTo-Json -Compress -InputObject $state))
          if ($null -eq $menu) { continue }
          Check ('split menu: a kept half of ' + $v.label + ' has a category colour, in ' + $theme + ' (control)') ((([string]$menu.keep) -ne '') -and ($menu.keep -ne 'rgb(0, 0, 0)')) "kept-half fill: $($menu.keep)"
          Check ('split menu: the Join Halves icon on ' + $v.label + ' is not black, in ' + $theme) ((([string]$menu.join) -ne '') -and ($menu.join -ne 'rgb(0, 0, 0)')) "Join Halves fill: $($menu.join)"
          Check ('split menu: the Join Halves icon on ' + $v.label + ' has the kept-half colour, in ' + $theme) ((([string]$menu.join) -ne '') -and ($menu.join -eq $menu.keep)) "Join Halves fill $($menu.join), kept-half fill $($menu.keep)"
        }
      } finally { Reset-Look $ws }
    }
  }

  # Double-click (split-cell notes): a double-click on the selected window splits its cell side by side, one POST /layout; a double-click on an
  # unselected window selects it and does not split; a double-click on a selected locked window does not split. Each sends real pointer
  # and mouse events (Click-Double), so the page's press, release and dblclick run as they do for a user.
  Case 'split dblclick: a double-click on the selected window splits its cell side by side: one POST /layout, the grid doubled' {
    Put-Split (Split-Json 5 2 (0..9 | % { Split-Pin $_ @($_) }))
    Set-View $ws 1440 900
    try {
      $opened = Open-Page $ws $url 'focus'
      Check 'split dblclick: the page opens on Focus (control)' $opened 'the page did not open on Focus in time'
      if (-not $opened) { return }
      $sel = Split-Select $ws 1001
      Check 'split dblclick: window 1001 is selected before the double-click (control)' $sel 'no tile 1001, or Enter did not select it'
      if (-not $sel) { return }
      $pt = Tile-Centre $ws 1001
      Check 'split dblclick: the double-click lands on window 1001, not on a button in it (scope)' ($pt -and $pt.hit -eq $true) 'the point is off window 1001'
      if (-not ($pt -and $pt.hit -eq $true)) { return }
      $before = [int](Js $ws 'return window.__h.posts("layout").length')
      Click-Double $ws ([double]$pt.x) ([double]$pt.y)
      [void](WaitFor $ws ('window.__h.posts("layout").length > ' + $before) 10)
      $sent = Layout-Posts-After $ws $before
      Check 'split dblclick: the double-click on the selected window sends one POST /layout' ($sent.Count -eq 1) "POST /layout count: $($sent.Count)"
      $lay = if ($sent.Count -eq 1) { (ConvertFrom-Json $sent[0].body).layout } else { $null }
      Check 'split dblclick: the POST carries the plugged-in setup key' ($sent.Count -eq 1 -and ((ConvertFrom-Json $sent[0].body).key -ceq $plugKey)) 'no POST /layout to read the setup key from, or it carries another key'
      Split-Verify 'double-click, side by side' $lay 5 2 '2,1' '2,1' 'Refactor the grid solver' '0' $splitWantSide
    } finally { Reset-Look $ws }
  }

  Case 'split dblclick: a double-click on an unselected window sends no POST /layout and leaves that window selected' {
    Put-Split (Split-Json 5 2 (0..9 | % { Split-Pin $_ @($_) }))
    Set-View $ws 1440 900
    try {
      $opened = Open-Page $ws $url 'focus'
      Check 'split dblclick: the page opens on Focus (control)' $opened 'the page did not open on Focus in time'
      if (-not $opened) { return }
      $other = Split-Select $ws 1002
      Check 'split dblclick: window 1002 is selected, so window 1001 is not (scope)' ($other -and ((Js $ws 'return selWin') -eq 1002)) 'window 1002 is not selected'
      if (-not $other) { return }
      $pt = Tile-Centre $ws 1001
      Check 'split dblclick: the double-click lands on window 1001, not on a button in it (scope)' ($pt -and $pt.hit -eq $true) 'the point is off window 1001'
      if (-not ($pt -and $pt.hit -eq $true)) { return }
      $before = [int](Js $ws 'return window.__h.posts("layout").length')
      Click-Double $ws ([double]$pt.x) ([double]$pt.y)
      $sent = Layout-Posts-After $ws $before
      Check 'split dblclick: a double-click on an unselected window sends no POST /layout' ($sent.Count -eq 0) "POST /layout count: $($sent.Count)"
      $now = Js $ws 'return selWin'
      Check 'split dblclick: a double-click on an unselected window selects it' ($now -eq 1001) "selected window: $now"
    } finally { Reset-Look $ws }
  }

  Case 'split dblclick: a double-click on a selected locked window sends no POST /layout' {
    Put-Split (Split-Json 5 2 @(Split-Pin 0 @(0) $true))
    Set-View $ws 1440 900
    try {
      $opened = Open-Page $ws $url 'focus'
      Check 'split dblclick: the page opens on Focus (control)' $opened 'the page did not open on Focus in time'
      if (-not $opened) { return }
      $lk = Js $ws 'const t = document.querySelector(".tile[data-id=\"1001\"]"); return !!t && t.classList.contains("lock")'
      Check 'split dblclick: window 1001 is locked (scope)' ($lk -eq $true) 'the tile has no lock class'
      if ($lk -ne $true) { return }
      $sel = Split-Select $ws 1001
      Check 'split dblclick: window 1001 is selected before the double-click (control)' $sel 'no tile 1001, or Enter did not select it'
      if (-not $sel) { return }
      $pt = Tile-Centre $ws 1001
      Check 'split dblclick: the double-click lands on window 1001, not on a button in it (scope)' ($pt -and $pt.hit -eq $true) 'the point is off window 1001'
      if (-not ($pt -and $pt.hit -eq $true)) { return }
      $before = [int](Js $ws 'return window.__h.posts("layout").length')
      Click-Double $ws ([double]$pt.x) ([double]$pt.y)
      $sent = Layout-Posts-After $ws $before
      Check 'split dblclick: a double-click on the selected locked window sends no POST /layout' ($sent.Count -eq 0) "POST /layout count: $($sent.Count)"
    } finally { Reset-Look $ws }
  }

  # Inspector kind (monitor-setups notes, item 25: the owner's yes, to say the kind once in words in the inspector's Scene section). The Scene
  # section's visible text holds the selected scene's kind word once and no other kind's word. The kind words are counted without the reasons
  # line (#whyoff): it says why a control is off ("Built-in scenes cannot be deleted.", "Not saved yet, so nothing to revert to."), and those
  # words are not the kind. The word edited is counted over the whole section, reasons line included. The kind words match case-sensitively,
  # so a note's "built-in" does not count. Read as a user sees it: no visually hidden or hidden text.
  $sceneKindJs = @'
const sceneKind = () => {
  const box = document.getElementById("scenebox"), name = document.getElementById("sceneName"), line = document.getElementById("skind"), crumb = document.getElementById("sedit");
  if (!box) return { name: null, text: "", line: null, crumb: false, builtIn: 0, custom: 0, notSaved: 0, edited: 0 };
  // The visible text of the box, without the parts that the skip selector names.
  const shown = skip => {
    const w = document.createTreeWalker(box, NodeFilter.SHOW_TEXT);
    let t = "";
    while (w.nextNode()) {
      const p = w.currentNode.parentElement;
      if (!p || p.closest(skip) || p.getClientRects().length === 0) continue;
      t += w.currentNode.textContent + " ";
    }
    return t.replace(/\s+/g, " ").trim();
  };
  const t = shown("#whyoff, .vh, [aria-hidden=true], [hidden]"), all = shown(".vh, [aria-hidden=true], [hidden]");
  const n = re => (t.match(re) || []).length;
  return { name: name ? name.value : null, text: t, line: line ? line.textContent.replace(/\s+/g, " ").trim() : null, crumb: !!crumb && !crumb.hidden, builtIn: n(/\bBuilt-in\b/g), custom: n(/\bCustom\b/g), notSaved: n(/\bNot saved\b/g), edited: (all.match(/\bedited\b/gi) || []).length };
};
'@
  Case 'the Scene section shows the kind of each scene once, in words, and no other kind word, as the page changes scene' {
    $opened = Open-Kind-Rail $ws
    Check 'the kind rail opens on Focus, with the Not saved probe (control)' $opened 'the page did not draw the rail in time'
    if (-not $opened) { return }
    # Default is built-in, Focus is saved (Custom), and the probe is not saved. Each is selected in turn on this one page.
    $steps = @(
      [pscustomobject]@{ scene = 'default'; name = 'Default'; word = 'Built-in' }
      [pscustomobject]@{ scene = 'focus'; name = 'Focus'; word = 'Custom' }
      [pscustomobject]@{ scene = 'kind-probe'; name = 'Kind probe'; word = 'Not saved' }
    )
    foreach ($s in $steps) {
      Select-Scene $ws $s.scene $s.name
      $k = Js $ws ($sceneKindJs + 'return sceneKind()')
      $counts = @{ 'Built-in' = $k.builtIn; 'Custom' = $k.custom; 'Not saved' = $k.notSaved }
      Check "$($s.name): the Scene section shows its name (scope)" ($k.name -ceq $s.name) "name in the Scene section: '$($k.name)'"
      Check "$($s.name): the Scene section shows $($s.word) once, in words" ($counts[$s.word] -eq 1) "$($s.word) in the Scene section: $($counts[$s.word]); its visible text: '$($k.text)'"
      foreach ($other in @($kindWords | ? { $_ -ne $s.word })) {
        Check "$($s.name): the Scene section shows no $other" ($counts[$other] -eq 0) "$other in the Scene section: $($counts[$other]); its visible text: '$($k.text)'"
      }
      Check "$($s.name): the Scene section says no edited (control)" ($k.edited -eq 0) "edited in the Scene section: $($k.edited); its visible text: '$($k.text)'"
      if ($s.scene -eq 'kind-probe') {
        # The probe has no config entry, so the page counts it edited: the crumb reads Edited. Its inspector line must still never say edited.
        Check 'Kind probe, Not saved: the crumb reads Edited, so the page counts the probe edited (control)' $k.crumb 'the crumb does not read Edited'
        Check 'Kind probe, Not saved: the inspector line starts with its kind word (control)' ([string]$k.line).StartsWith('Not saved') "the inspector line reads: '$($k.line)'"
        Check 'Kind probe, Not saved: the inspector line never says edited' ([string]$k.line -notmatch '\bedited\b') "the inspector line reads: '$($k.line)'"
      }
    }
  }

  Case 'the Scene section says edited once when a saved scene is changed, and not before' {
    Put-Config (New-Config)
    $opened = Open-Page $ws $url 'focus'
    Check 'the page opens on Focus (control)' $opened 'the page did not open on Focus in time'
    if (-not $opened) { return }
    Scene-Shows $ws 'focus' 'Focus'
    $before = Js $ws ($sceneKindJs + 'return sceneKind()')
    Check 'Focus, unchanged: the Scene section says no edited (control)' ($before.edited -eq 0) "edited in the Scene section: $($before.edited); its visible text: '$($before.text)'"
    # The name is changed and the change is committed, as a user does. The crumb's Edited mark is the page's own sign that the edit took (control).
    [void](Js $ws 'const f = document.getElementById("sceneName"); f.value = "Focus renamed"; f.dispatchEvent(new Event("change", { bubbles: true })); return true')
    $marked = WaitFor $ws '!document.getElementById("sedit").hidden' 30
    Check 'the crumb reads Edited once the name is changed (scope)' $marked 'the page did not mark Focus as edited'
    if (-not $marked) { return }
    $after = Js $ws ($sceneKindJs + 'return sceneKind()')
    Check 'edited Focus: the Scene section says edited once' ($after.edited -eq 1) "edited in the Scene section: $($after.edited); its visible text: '$($after.text)'"
    Check 'edited Focus: the Scene section still shows Custom once' ($after.custom -eq 1) "Custom in the Scene section: $($after.custom); its visible text: '$($after.text)'"
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
  # ---- Free Layout (layout-free items 14-29; free-layout-notes F1-F16; plan lane L4) -----------------------------------------------
  # Every check here is new: on main each one FAILs and names its cause (no switch, no seam, no space, no POST, no strip). A missing
  # control answers null or false, so no lookup throws. Each case's first line names its mutant: the defect a scratch copy of the built
  # lane must turn red. The times sign is built from a code point, so this file stays ASCII.
  $tile = Join-Path $root 'tile.ps1'
  $times = [char]0x00D7
  $freeJs = @'
const tileOf = id => document.querySelector('.tile[data-id="' + id + '"]');
const RR = e => { if (!e) return null; const r = e.getBoundingClientRect(); return { l: r.left, t: r.top, r: r.right, b: r.bottom, w: r.width, h: r.height }; };
const rectsOf = ids => { const o = {}; for (const id of ids) o[id] = RR(tileOf(id)); return o; };
const monhSec = () => { const h = document.getElementById("monh"); return h ? h.closest("section") : null; };
const freeSw = () => { const s = monhSec(); if (!s) return null; return [...s.querySelectorAll("input[role=switch]")].find(i => /Free Layout/.test((i.closest("label") || {}).textContent || "")) || null; };
const swOn = () => { const s = freeSw(); return !!s && !s.disabled && s.getAttribute("aria-disabled") !== "true"; };
const pageText = () => (document.body.innerText || "").replace(/\s+/g, " ");
const btnNamed = rx => [...document.querySelectorAll("button")].find(b => b.getClientRects().length > 0 && rx.test(b.textContent.replace(/\s+/g, " ").trim())) || null;
const monBtn = name => [...document.querySelectorAll("#mon button[data-mon]")].find(b => b.textContent.trim() === name) || null;
const spaceOf = i => document.querySelector('.space[data-space="' + i + '"]');
const spRect = r => { const p = px({ x: r[0], y: r[1], w: r[2], h: r[3] }); const st = document.getElementById("stage").getBoundingClientRect(); return { l: st.left + parseFloat(p.left), t: st.top + parseFloat(p.top), w: parseFloat(p.width), h: parseFloat(p.height) }; };
const nearRect = (el, s, tol) => { if (!el || !s) return false; const b = el.getBoundingClientRect(); return Math.abs(b.left - s.l) <= tol && Math.abs(b.top - s.t) <= tol && Math.abs(b.width - s.w) <= tol && Math.abs(b.height - s.h) <= tol; };
'@
  # The ultrawide's ten windows in cell order: window i sits in cell i (row by row, five to a row) and is pin i of the layout.
  $flWins = @(
    @{ id = 1001; app = 'claude'; match = 'Refactor the grid solver' }
    @{ id = 1002; app = 'claude'; match = 'Pin parser edge cases' }
    @{ id = 1005; app = 'chrome'; match = 'Pull request 212' }
    @{ id = 1006; app = 'chrome'; match = 'Quarterly roadmap' }
    @{ id = 1010; app = 'explorer'; match = 'Projects' }
    @{ id = 1008; app = 'WindowsTerminal'; match = 'pwsh - tiler' }
    @{ id = 1009; app = 'WindowsTerminal'; match = 'pwsh - docs watch' }
    @{ id = 1011; app = 'explorer'; match = 'Downloads' }
    @{ id = 1012; app = 'ms-teams'; match = 'Design sync' }
    @{ id = 1014; app = 'notepad'; match = 'todo.txt' }
  )
  $flIds = @($flWins | % { [int]$_.id })
  # Pixel edge of a fraction of the 4096 by 1680 ultrawide work area, rounded as tile.ps1's Get-AreaPixelRects rounds it.
  function Fl-Px([double]$f, [int]$n) { [int][Math]::Round([Math]::Round($f, 9) * $n) }
  # An area's rect in pixels, as the engine places it: @(x, y, w, h).
  function Fl-AreaPx($rect) { $x0 = Fl-Px $rect[0] 4096; $x1 = Fl-Px ($rect[0] + $rect[2]) 4096; $y0 = Fl-Px $rect[1] 1680; $y1 = Fl-Px ($rect[1] + $rect[3]) 1680; @($x0, $y0, ($x1 - $x0), ($y1 - $y0)) }
  # Cell i of the 5 by 2 board, as a free area's rect in fractions.
  function Fl-Cell([int]$i) { @([double](($i % 5) / 5), [double]([Math]::Floor($i / 5) / 2), 0.2, 0.5) }
  # The board's pins and areas. Window i is pin i unless cell i is in $noPin (an empty space). $lock: the windows whose pin is locked.
  function Fl-Board([int[]]$noPin = @(), [int[]]$lock = @()) {
    $pins = @(); $map = @{}
    for ($i = 0; $i -lt 10; $i++) {
      if ($noPin -contains $i) { continue }
      $p = [pscustomobject]@{ app = $flWins[$i].app; match = $flWins[$i].match; mon = 'U1'; slots = @($i) }
      if ($lock -contains $i) { $p | Add-Member -NotePropertyName lock -NotePropertyValue $true }
      $map[$i] = $pins.Count; $pins += $p
    }
    $areas = @()
    for ($i = 0; $i -lt 10; $i++) {
      $a = [ordered]@{ rect = @(Fl-Cell $i) }
      if ($map.ContainsKey($i)) { $a['pin'] = $map[$i] }
      $areas += $a
    }
    [pscustomobject]@{ areas = $areas; pins = @($pins) }
  }
  # The saved layout of the plugged setup: grids.U1 keeps c 5 and r 2 and, unless -grid, holds the board's areas as free.areas.
  function Fl-Json($board, [switch]$grid, [hashtable]$fillOver = @{}) {
    $f = [ordered]@{ mon = 'U1'; apps = @(); skip = @(); sort = 'app' }
    foreach ($k in $fillOver.Keys) { $f[$k] = $fillOver[$k] }
    $g = [ordered]@{ c = 5; r = 2 }
    if (-not $grid) { $g['free'] = [ordered]@{ areas = @($board.areas) } }
    ConvertTo-Json -Depth 12 -Compress -InputObject ([ordered]@{ grids = [ordered]@{ U1 = $g }; pins = @($board.pins); zones = @(); fill = $f; bay = @() })
  }
  # The aligned snapshot: each board window sits at its cell, so the page and the engine start from the same rects.
  $flSnapObj = ConvertFrom-Json $snapAText
  for ($i = 0; $i -lt 10; $i++) {
    $sw1 = @($flSnapObj.windows | ? { [int]$_.id -eq $flWins[$i].id })[0]
    if ($sw1) { $p = Fl-AreaPx (Fl-Cell $i); $sw1.x = $p[0]; $sw1.y = $p[1]; $sw1.w = $p[2]; $sw1.h = $p[3] }
  }
  $flSnap = ConvertTo-Json -Depth 10 -Compress -InputObject $flSnapObj
  # The aligned snapshot without some windows (closed), or with some minimized.
  function Fl-Snap([int[]]$closed = @(), [int[]]$minimized = @()) {
    $o = ConvertFrom-Json $flSnap
    $o.windows = @($o.windows | ? { $closed -notcontains [int]$_.id })
    foreach ($w in @($o.windows | ? { $minimized -contains [int]$_.id })) { $w | Add-Member -Force -NotePropertyName min -NotePropertyValue $true }
    ConvertTo-Json -Depth 10 -Compress -InputObject $o
  }
  # Saves $layoutJson for the plugged setup, opens the page on Focus with $snapText, and selects the ultrawide. Answers whether it opened.
  function Fl-Open($sock, [string]$layoutJson, [string]$snapText = $flSnap) {
    Put-Split $layoutJson
    $ok = Open-Page $sock $url 'focus' $snapText
    if ($ok) { [void](Fl-Select $sock 'Ultrawide') }
    $ok
  }
  # Selects a monitor in the Monitor section by its name, and waits until the page shows it selected.
  function Fl-Select($sock, [string]$name) {
    [void](Js $sock ($freeJs + 'const b = monBtn("' + $name + '"); if (!b) return false; b.click(); return true'))
    WaitFor $sock ('[...document.querySelectorAll("#mon button[data-mon]")].some(x => x.textContent.trim() === "' + $name + '" && x.getAttribute("aria-pressed") === "true")') 10
  }
  # The POSTs the page sent to /layout and /config since it opened, read once it has settled. Each /layout body is parsed.
  function Fl-Saves($sock) {
    $p = Js $sock 'await window.__h.settle(); return { layout: window.__h.posts("layout"), config: window.__h.posts("config") }'
    [pscustomobject]@{ layout = @(@($p.layout) | ? { $_ } | % { ConvertFrom-Json $_.body }); config = @(@($p.config) | ? { $_ }) }
  }
  # The rects of the given tiles now: id -> {l, t, r, b, w, h}, or null for a tile not on the board.
  function Fl-Rects($sock, [int[]]$ids) { Js $sock ($freeJs + 'return rectsOf([' + (($ids | % { "$_" }) -join ',') + ']);') }
  # The ids (of $ids) whose tile rect moved by more than half a pixel between two reads. A tile missing from either read counts as moved.
  function Fl-Moved($before, $after, [int[]]$ids) {
    @($ids | ? {
      $b = $before."$_"; $a = $after."$_"
      if (-not $b -or -not $a) { return $true }
      ([Math]::Abs($b.l - $a.l) -gt 0.5) -or ([Math]::Abs($b.t - $a.t) -gt 0.5) -or ([Math]::Abs($b.r - $a.r) -gt 0.5) -or ([Math]::Abs($b.b - $a.b) -gt 0.5)
    })
  }
  # The point on the seam between two side-by-side tiles (left, right), and between two stacked tiles (top, bottom).
  function Fl-SeamV($rects, [int]$left, [int]$right) { $a = $rects."$left"; $b = $rects."$right"; @((($a.r + $b.l) / 2), (($a.t + $a.b) / 2)) }
  function Fl-SeamH($rects, [int]$top, [int]$bottom) { $a = $rects."$top"; $b = $rects."$bottom"; @((($a.l + $a.r) / 2), (($a.b + $b.t) / 2)) }
  # The centre of a tile, from a read of the rects.
  function Fl-Centre($rects, [int]$id) { $a = $rects."$id"; @(($a.l + $a.w / 2), ($a.t + $a.h / 2)) }
  # A left click as a mouse makes it, at the point.
  function Fl-Click($sock, [double]$x, [double]$y) {
    [void](Cdp $sock 'Input.dispatchMouseEvent' @{ type = 'mouseMoved'; x = $x; y = $y })
    [void](Cdp $sock 'Input.dispatchMouseEvent' @{ type = 'mousePressed'; x = $x; y = $y; button = 'left'; buttons = 1; clickCount = 1 })
    [void](Cdp $sock 'Input.dispatchMouseEvent' @{ type = 'mouseReleased'; x = $x; y = $y; button = 'left'; buttons = 0; clickCount = 1 })
    [void](Js $sock 'await window.__h.settle(); return true')
  }
  # A pointer drag as a mouse makes it: a press at (x0, y0), ten moves to (x1, y1), a release. Shift is held when $shift. $probe, a page
  # expression, is read while the button is still down, and its value is returned.
  function Fl-Drag($sock, [double]$x0, [double]$y0, [double]$x1, [double]$y1, [bool]$shift = $false, [string]$probe = '') {
    $m = $(if ($shift) { 8 } else { 0 })
    [void](Cdp $sock 'Input.dispatchMouseEvent' @{ type = 'mouseMoved'; x = $x0; y = $y0; modifiers = $m })
    [void](Cdp $sock 'Input.dispatchMouseEvent' @{ type = 'mousePressed'; x = $x0; y = $y0; button = 'left'; buttons = 1; clickCount = 1; modifiers = $m })
    for ($s = 1; $s -le 10; $s++) { [void](Cdp $sock 'Input.dispatchMouseEvent' @{ type = 'mouseMoved'; x = $x0 + ($x1 - $x0) * $s / 10; y = $y0 + ($y1 - $y0) * $s / 10; button = 'left'; buttons = 1; modifiers = $m }) }
    $mid = $(if ($probe) { Js $sock $probe } else { $null })
    [void](Cdp $sock 'Input.dispatchMouseEvent' @{ type = 'mouseReleased'; x = $x1; y = $y1; button = 'left'; buttons = 0; clickCount = 1; modifiers = $m })
    [void](Js $sock 'await window.__h.settle(); return true')
    $mid
  }
  # The area of window $id in a saved layout: the one whose pin names that window, or $null.
  function Fl-AreaOf($layout, [int]$id) {
    $mt = $flWins[[Array]::IndexOf($flIds, $id)].match
    @(@($layout.grids.U1.free.areas) | ? { $null -ne $_.pin -and @($layout.pins)[[int]$_.pin].match -eq $mt })[0]
  }
  # The saved areas against what a case expects: $want maps a window id to its rect in fractions, 'any' (not checked) or 'gone'
  # (no space). A window not in $want keeps its cell. Answers one line per window that differs.
  function Fl-AreaDiff($layout, [hashtable]$want) {
    @(for ($i = 0; $i -lt 10; $i++) {
      $id = $flIds[$i]; $a = Fl-AreaOf $layout $id
      if ($want.ContainsKey($id) -and $want[$id] -eq 'gone') { if ($a) { "window $id still has a space" }; continue }
      if ($want.ContainsKey($id) -and $want[$id] -eq 'any') { continue }
      if ($null -eq $a) { "window $id has no space"; continue }
      $exp = $(if ($want.ContainsKey($id)) { $want[$id] } else { Fl-Cell $i })
      $d = 0; for ($k = 0; $k -lt 4; $k++) { $d = [Math]::Max($d, [Math]::Abs([double]$a.rect[$k] - [double]$exp[$k])) }
      if ($d -gt 0.0006) { "window ${id}: space $((@($a.rect) | % { [Math]::Round($_, 4) }) -join ','), want $((@($exp) | % { [Math]::Round($_, 4) }) -join ',')" }
    })
  }
  # The engine's answer for the focus scene on the plugged setup, from the snapshot file (-DryRun: nothing moves). $extra: more switches.
  function Fl-Engine([string[]]$extra = @()) {
    $p = Start-Child ("-File `"$tile`" -Scene focus -From `"$snapPath`" -Json " + ($extra -join ' ') + " -DryRun")
    $out = $p.StandardOutput.ReadToEnd(); [void]$p.WaitForExit(60000)
    # tile.ps1 writes its warnings to stdout too, so the answer is the last line that is a JSON object.
    $line = @(($out -split "`r?`n") | ? { $_.StartsWith('{') }) | Select-Object -Last 1
    if (-not $line) { return $null }
    try { ConvertFrom-Json $line } catch { $null }
  }
  # The pinned free areas of a saved layout: the ones whose pin names a window. A layout with none leaves the engine check nothing to compare.
  function Fl-Pinned($layout) { @(@($layout.grids.U1.free.areas) | ? { $null -ne $_.pin }) }
  # tile.ps1 places each pinned window at its space's pixel rect. Answers one line per window that differs (none when it agrees).
  function Fl-EngineDiff($eng, $layout) {
    if (-not $eng -or -not $eng.placed) { return @('tile.ps1 placed no windows') }
    $out = @()
    foreach ($a in @(Fl-Pinned $layout)) {
      $mt = @($layout.pins)[[int]$a.pin].match
      $wid = [int64](@($flWins | ? { $_.match -eq $mt })[0].id)
      $got = @($eng.placed | ? { [int64]$_.id -eq $wid })[0]
      if (-not $got) { $out += "${mt}: not placed"; continue }
      $g = @([int]$got.x, [int]$got.y, [int]$got.w, [int]$got.h); $want = Fl-AreaPx $a.rect
      if (($g -join ',') -ne ($want -join ',')) { $out += "${mt}: engine $($g -join ','), space $($want -join ',')" }
    }
    @($out)
  }
  # The page draws a tile at px() of the engine's rect. Answers the difference in words, or '' when the tile is where the engine says.
  function Fl-PageVsEngine($sock, [int]$id, $g) {
    $pg = Js $sock ($freeJs + 'const t = tileOf(' + $id + '); if (!t) return null; const p = px({ x: ' + [int]$g.x + ', y: ' + [int]$g.y + ', w: ' + [int]$g.w + ', h: ' + [int]$g.h + ' }); return { wL: parseFloat(p.left), wT: parseFloat(p.top), wW: parseFloat(p.width), wH: parseFloat(p.height), gL: parseFloat(t.style.left), gT: parseFloat(t.style.top), gW: parseFloat(t.style.width), gH: parseFloat(t.style.height) };')
    if (-not $pg) { return "tile $id is not on the board" }
    $dd = [Math]::Max([Math]::Max([Math]::Abs($pg.wL - $pg.gL), [Math]::Abs($pg.wT - $pg.gT)), [Math]::Max([Math]::Abs($pg.wW - $pg.gW), [Math]::Abs($pg.wH - $pg.gH)))
    if ($dd -gt 1) { "tile $id drawn at $($pg.gL),$($pg.gT) $($pg.gW)x$($pg.gH), the engine says $($pg.wL),$($pg.wT) $($pg.wW)x$($pg.wH)" } else { '' }
  }
  # The Monitor section's switch is on and can be used (not disabled), as an expression for WaitFor.
  $swOnCond = '(() => { const h = document.getElementById("monh"); const s = h && h.closest("section"); if (!s) return false; const i = [...s.querySelectorAll("input[role=switch]")].find(x => /Free Layout/.test((x.closest("label") || {}).textContent || "")); return !!i && !i.disabled && i.getAttribute("aria-disabled") !== "true"; })()'
  $lastPath = Join-Path $runDir 'free-last.json'
  $kd = 1 / 48

  foreach ($v in @(@{ tag = 'switch'; route = 'click' }, @{ tag = 'F key'; route = 'key' })) {
    $tag = $v.tag; $route = $v.route; $how = $(if ($route -eq 'key') { 'the F key' } else { 'the switch' })
    Case "free-on ($tag): switching the ultrawide to Free Layout moves no window and sends one POST /layout" {
      # Mutant: the switch's click handler (for the F row, the F keydown handler) is removed, so Free Layout stays off. Or the switch
      # re-lays the board and moves tile 1001 by one cell. Or it drops tile 1014 from the board. Or it saves twice, or writes the config.
      $opened = Fl-Open $ws (Fl-Json (Fl-Board) -grid)
      Check "free-on ($tag): the page opens on Focus with the 5 by 2 grid (control)" $opened 'the page did not open on Focus in time'
      if (-not $opened) { return }
      $before = Fl-Rects $ws $flIds
      $onBoard = @($flIds | ? { $before."$_" }).Count
      Check "free-on ($tag): all ten windows are on the board before the press (scope)" ($onBoard -eq 10) "on the board before: $onBoard of 10"
      if ($onBoard -ne 10) { return }
      $hasSw = Js $ws ($freeJs + 'return !!freeSw();')
      Check "free-on ($tag): the Monitor section has a Free Layout switch" ($hasSw -eq $true) 'no Free Layout switch in the Monitor section of the ultrawide'
      if ($route -eq 'click') { [void](Js $ws ($freeJs + 'const s = freeSw(); if (s) s.click(); return !!s;')) }
      else { [void](Js $ws 'if (document.activeElement) document.activeElement.blur(); return true;'); Press-Key $ws 'f' 70 'f' }
      $s = Fl-Saves $ws
      $after = Fl-Rects $ws $flIds
      $on = Js $ws ($freeJs + 'const s = freeSw(); return !!s && (s.checked === true || s.getAttribute("aria-checked") === "true");')
      Check "free-on ($tag): $how turns Free Layout on" ($on -eq $true) "Free Layout is not on after $how"
      Check "free-on ($tag): one POST /layout was sent" ($s.layout.Count -eq 1) "POST /layout count: $($s.layout.Count)"
      Check "free-on ($tag): no POST /config was sent" ($s.config.Count -eq 0) "POST /config count: $($s.config.Count)"
      $both = @($flIds | ? { $before."$_" -and $after."$_" })
      $mv = @(Fl-Moved $before $after $both)
      Check "free-on ($tag): no window moved on the board" ($mv.Count -eq 0) "moved: $($mv -join ', ')"
      $gone = @($flIds | ? { $before."$_" -and -not $after."$_" })
      Check "free-on ($tag): no window went missing from the board" ($gone.Count -eq 0) "missing: $($gone -join ', ')"
      if ($s.layout.Count -ne 1) { return }
      $L1 = $s.layout[0].layout
      Check "free-on ($tag): the saved layout keeps grids U1 c 5 and r 2" ($L1.grids.U1.c -eq 5 -and $L1.grids.U1.r -eq 2) "c $($L1.grids.U1.c), r $($L1.grids.U1.r)"
      $nAreas = @($L1.grids.U1.free.areas).Count
      Check "free-on ($tag): the saved layout holds one space per cell (10)" ($nAreas -eq 10) "spaces: $nAreas"
      $dd = @(Fl-AreaDiff $L1 @{})
      Check "free-on ($tag): each space is its cell and holds that cell's window" ($dd.Count -eq 0) ($dd -join ' | ')
      $lbl = Js $ws ($freeJs + 'return [...document.querySelectorAll(".num")].some(e => e.textContent.trim() === "Free Layout");')
      Check "free-on ($tag): the monitor label reads Free Layout, in place of 5 $times 2" ($lbl -eq $true) 'no monitor label reads Free Layout'
      $st = Js $ws ($freeJs + 'const sec = monhSec(); if (!sec) return null; const b = [...sec.querySelectorAll("[data-g]")]; return { n: b.length, off: b.length > 0 && b.every(x => x.disabled || x.getAttribute("aria-disabled") === "true"), why: pageText().indexOf("Free Layout is on. Turn it off to change the grid.") >= 0 };')
      Check "free-on ($tag): Columns and Rows are off, with the reason" ($st -and $st.off -and $st.why) "steppers: $(if ($st) { "$($st.n) found, all off $($st.off), reason shown $($st.why)" } else { 'no Monitor section' })"
      $call = Js $ws ($freeJs + 'return pageText().indexOf("Free Layout is on. Nothing moved.") >= 0;')
      Check "free-on ($tag): the callout reads Free Layout is on. Nothing moved." ($call -eq $true) 'no such callout on the page'
    }
  }

  Case 'free-on (1 by 1): a laptop with one window has its switch off, with the reason and a Split Cell button; a split turns it on' {
    # Mutant: the switch stays on over a 1 by 1 monitor, with no reason and no Split Cell button beside it.
    $o = ConvertFrom-Json (Fl-Json (Fl-Board) -grid)
    $o.grids | Add-Member -NotePropertyName L1 -NotePropertyValue ([pscustomobject]@{ c = 1; r = 1 })
    $o.pins = @($o.pins) + [pscustomobject]@{ app = 'Spotify'; match = 'Spotify Free'; mon = 'L1'; slots = @(0) }
    $opened = Fl-Open $ws (ConvertTo-Json -Depth 12 -Compress -InputObject $o)
    Check '1 by 1: the page opens on Focus (control)' $opened 'the page did not open on Focus in time'
    if (-not $opened) { return }
    $selLap = Fl-Select $ws 'Laptop'
    Check '1 by 1: the Laptop is selected (scope)' $selLap 'the Laptop button did not select in time'
    if (-not $selLap) { return }
    $st = Js $ws ($freeJs + 'const s = freeSw(); if (!s) return null; return { off: s.disabled || s.getAttribute("aria-disabled") === "true", why: pageText().indexOf("One window fills this monitor. Split it first.") >= 0, split: !!btnNamed(/^Split Cell$/) };')
    Check '1 by 1: the Free Layout switch is off' ($st -and $st.off) 'no Free Layout switch, or it is on'
    Check '1 by 1: the switch gives its reason, One window fills this monitor. Split it first.' ($st -and $st.why) 'the reason is not on the page'
    Check '1 by 1: a Split Cell button sits beside the switch' ($st -and $st.split) 'no Split Cell button in the Monitor section'
    if (-not ($st -and $st.split)) { return }
    [void](Js $ws ($freeJs + 'const b = btnNamed(/^Split Cell$/); if (b) b.click(); return !!b;'))
    $menu = WaitFor $ws 'document.querySelectorAll("[role=menuitem]").length > 0' 10
    Check '1 by 1: Split Cell opens the split menu' $menu 'no split menu opened in time'
    if (-not $menu) { return }
    [void](Js $ws 'const it = [...document.querySelectorAll("[role=menuitem]")].find(x => x.getClientRects().length > 0); if (it) it.click(); return true;')
    $s = Fl-Saves $ws
    Check '1 by 1: the split sends one POST /layout' ($s.layout.Count -eq 1) "POST /layout count: $($s.layout.Count)"
    $on = WaitFor $ws $swOnCond 15
    Check '1 by 1: after the split the switch is on' $on 'the switch stays off after the split'
  }

  foreach ($v in @(@{ tag = 'top row'; lid = 1001; rid = 1002; oth = @(1008, 1009) }, @{ tag = 'bottom row'; lid = 1008; rid = 1009; oth = @(1001, 1002) })) {
    $tag = $v.tag; $lid = $v.lid; $rid = $v.rid; $oth = $v.oth
    Case "drag-segment ($tag): a plain drag moves that row's part of the line, and no other; no gap opens" {
      # Mutant: a plain drag moves both rows (the Shift move), or the drag leaves a gap between the two spaces, or the save drops the pin fields.
      $opened = Fl-Open $ws (Fl-Json (Fl-Board))
      Check "drag-segment ($tag): the page opens on Focus (control)" $opened 'the page did not open on Focus in time'
      if (-not $opened) { return }
      $r0 = Fl-Rects $ws $flIds
      $okTiles = ($null -ne $r0."$lid") -and ($null -ne $r0."$rid")
      Check "drag-segment ($tag): both windows are on the board (scope)" $okTiles "tile $lid or $rid is not on the board"
      if (-not $okTiles) { return }
      $sp = Fl-SeamV $r0 $lid $rid
      [void](Fl-Drag $ws $sp[0] $sp[1] ($sp[0] + 40) $sp[1])
      $r1 = Fl-Rects $ws $flIds
      $dL = $r1."$lid".w - $r0."$lid".w; $dR = $r1."$rid".w - $r0."$rid".w
      Check "drag-segment ($tag): the left window grows by at least 20 px" ($dL -ge 20) ("grew by " + [Math]::Round($dL, 1) + " px")
      Check "drag-segment ($tag): the right window gives up the same width" ([Math]::Abs($dL + $dR) -le 1.5) ("left " + [Math]::Round($dL, 1) + ", right " + [Math]::Round($dR, 1))
      $mv = @(Fl-Moved $r0 $r1 $oth)
      Check "drag-segment ($tag): the other row keeps its rects" ($mv.Count -eq 0) "moved: $($mv -join ', ')"
      $s = Fl-Saves $ws
      Check "drag-segment ($tag): one POST /layout" ($s.layout.Count -eq 1) "POST /layout count: $($s.layout.Count)"
      if ($s.layout.Count -ne 1) { return }
      $L1 = $s.layout[0].layout
      $wAny = @{}; $wAny[$lid] = 'any'; $wAny[$rid] = 'any'
      $dd = @(Fl-AreaDiff $L1 $wAny)
      Check "drag-segment ($tag): only the two spaces of that row changed" ($dd.Count -eq 0) ($dd -join ' | ')
      $aL = Fl-AreaOf $L1 $lid; $aR = Fl-AreaOf $L1 $rid
      $meet = [bool]($aL -and $aR -and ([Math]::Abs(($aL.rect[0] + $aL.rect[2]) - $aR.rect[0]) -lt 1e-6))
      $tot = 0; foreach ($a in @($L1.grids.U1.free.areas)) { $tot += $a.rect[2] * $a.rect[3] }
      Check "drag-segment ($tag): the two spaces meet, and the spaces still cover the monitor" ($meet -and [Math]::Abs($tot - 1) -lt 1e-6) "meet: $meet, total area: $tot"
      $pinN = @(Fl-Pinned $L1).Count
      Check "drag-segment ($tag): the saved layout holds a pinned space to compare (guard)" ($pinN -ge 1) "pinned spaces in the saved layout: $pinN"
      if ($pinN -lt 1) { return }
      $ed = @(Fl-EngineDiff (Fl-Engine) $L1)
      Check "drag-segment ($tag): tile.ps1 places each window in its saved space" ($ed.Count -eq 0) ($ed -join ' | ')
    }
  }

  foreach ($v in @(@{ tag = 'top row'; lid = 1001; rid = 1002; l2 = 1008; r2 = 1009 }, @{ tag = 'bottom row'; lid = 1008; rid = 1009; l2 = 1001; r2 = 1002 })) {
    $tag = $v.tag; $lid = $v.lid; $rid = $v.rid; $l2 = $v.l2; $r2 = $v.r2
    Case "drag-line ($tag, Shift): a Shift-drag moves the whole line, both rows by the same amount" {
      # Mutant: Shift moves the grabbed row only (the plain drag), or the two rows move by different amounts, or the save drops the pin fields.
      $opened = Fl-Open $ws (Fl-Json (Fl-Board))
      Check "drag-line ($tag): the page opens on Focus (control)" $opened 'the page did not open on Focus in time'
      if (-not $opened) { return }
      $r0 = Fl-Rects $ws $flIds
      $okTiles = ($null -ne $r0."$lid") -and ($null -ne $r0."$rid") -and ($null -ne $r0."$l2") -and ($null -ne $r0."$r2")
      Check "drag-line ($tag): the four windows are on the board (scope)" $okTiles 'a tile of the line is not on the board'
      if (-not $okTiles) { return }
      $sp = Fl-SeamV $r0 $lid $rid
      [void](Fl-Drag $ws $sp[0] $sp[1] ($sp[0] + 40) $sp[1] $true)
      $r1 = Fl-Rects $ws $flIds
      $dA = $r1."$lid".w - $r0."$lid".w; $dB = $r1."$l2".w - $r0."$l2".w
      Check "drag-line ($tag): the left window of the grabbed row grows by at least 20 px" ($dA -ge 20) ("grew by " + [Math]::Round($dA, 1) + " px")
      Check "drag-line ($tag): the left window of the other row grows by the same amount" ([Math]::Abs($dA - $dB) -le 1.5) ("grew by " + [Math]::Round($dB, 1) + " px")
      Check "drag-line ($tag): the right windows of both rows give up that width" ([Math]::Abs(($r1."$rid".w - $r0."$rid".w) + $dA) -le 1.5 -and [Math]::Abs(($r1."$r2".w - $r0."$r2".w) + $dA) -le 1.5) 'a right window did not shrink by the same amount'
      $s = Fl-Saves $ws
      Check "drag-line ($tag): one POST /layout" ($s.layout.Count -eq 1) "POST /layout count: $($s.layout.Count)"
      if ($s.layout.Count -ne 1) { return }
      $L1 = $s.layout[0].layout
      $wAny = @{}; $wAny[$lid] = 'any'; $wAny[$rid] = 'any'; $wAny[$l2] = 'any'; $wAny[$r2] = 'any'
      $dd = @(Fl-AreaDiff $L1 $wAny)
      Check "drag-line ($tag): only the spaces of the line changed" ($dd.Count -eq 0) ($dd -join ' | ')
      $tot = 0; foreach ($a in @($L1.grids.U1.free.areas)) { $tot += $a.rect[2] * $a.rect[3] }
      Check "drag-line ($tag): the spaces still cover the monitor" ([Math]::Abs($tot - 1) -lt 1e-6) "total area: $tot"
      $pinN = @(Fl-Pinned $L1).Count
      Check "drag-line ($tag): the saved layout holds a pinned space to compare (guard)" ($pinN -ge 1) "pinned spaces in the saved layout: $pinN"
      if ($pinN -lt 1) { return }
      $ed = @(Fl-EngineDiff (Fl-Engine) $L1)
      Check "drag-line ($tag): tile.ps1 places each window in its saved space" ($ed.Count -eq 0) ($ed -join ' | ')
    }
  }

  Case "drag-line (Go Around, F5): a Shift-drag across a locked window moves the free part and leaves the locked row; the tip names what stayed" {
    # Mutant: Shift refuses (nothing moves), or Shift moves the locked row's part too, or the tip does not name Terminal.
    $opened = Fl-Open $ws (Fl-Json (Fl-Board @() @(5)))
    Check 'go-around: the page opens on Focus with Terminal locked (control)' $opened 'the page did not open on Focus in time'
    if (-not $opened) { return }
    $r0 = Fl-Rects $ws $flIds
    $okTiles = ($null -ne $r0.'1001') -and ($null -ne $r0.'1002') -and ($null -ne $r0.'1008') -and ($null -ne $r0.'1009')
    Check 'go-around: the four windows are on the board (scope)' $okTiles 'a tile of the line is not on the board'
    if (-not $okTiles) { return }
    $sp = Fl-SeamV $r0 1001 1002
    $pre = Js $ws ($freeJs + 'return pageText();')
    $mid = Fl-Drag $ws $sp[0] $sp[1] ($sp[0] + 40) $sp[1] $true ($freeJs + 'return pageText();')
    $r1 = Fl-Rects $ws $flIds
    $dTop = $r1.'1001'.w - $r0.'1001'.w
    Check 'go-around: the free part moves: the top-left window grows by at least 20 px' ($dTop -ge 20) ("grew by " + [Math]::Round($dTop, 1) + " px")
    $mv = @(Fl-Moved $r0 $r1 @(1008, 1009))
    Check 'go-around: the locked row keeps its rects: Terminal and its neighbour stay' ($mv.Count -eq 0) "moved: $($mv -join ', ')"
    $tipNow = ([regex]::Matches([string]$mid, 'Terminal')).Count -gt ([regex]::Matches([string]$pre, 'Terminal')).Count
    Check 'go-around: the tip or status names Terminal as the part that stayed' $tipNow 'no new word Terminal appears while the drag is held'
    $s = Fl-Saves $ws
    Check 'go-around: one POST /layout' ($s.layout.Count -eq 1) "POST /layout count: $($s.layout.Count)"
    if ($s.layout.Count -eq 1) {
      $wAny = @{}; $wAny[1001] = 'any'; $wAny[1002] = 'any'
      $dd = @(Fl-AreaDiff $s.layout[0].layout $wAny)
      Check 'go-around: the locked row''s spaces are saved as they were' ($dd.Count -eq 0) ($dd -join ' | ')
    }
  }

  foreach ($v in @(
      @{ tag = 'side'; lid = 1001; rid = 1002; dx = -600; dy = 0; min = 400; axis = 2 },
      @{ tag = 'top and bottom'; lid = 1001; rid = 1008; dx = 0; dy = -600; min = 300; axis = 3 })) {
    $tag = $v.tag; $lid = $v.lid; $rid = $v.rid
    Case "drag-floor ($tag): a drag stops at the 400 $times 300 px floor, with its tip, and the space is not smaller" {
      # Mutant: no floor (the space shrinks past 400 or 300 px), or no tip.
      $opened = Fl-Open $ws (Fl-Json (Fl-Board))
      Check "drag-floor ($tag): the page opens on Focus (control)" $opened 'the page did not open on Focus in time'
      if (-not $opened) { return }
      $r0 = Fl-Rects $ws $flIds
      $okTiles = ($null -ne $r0."$lid") -and ($null -ne $r0."$rid")
      Check "drag-floor ($tag): both windows are on the board (scope)" $okTiles "tile $lid or $rid is not on the board"
      if (-not $okTiles) { return }
      $sp = $(if ($v.dx -ne 0) { Fl-SeamV $r0 $lid $rid } else { Fl-SeamH $r0 $lid $rid })
      $mid = Fl-Drag $ws $sp[0] $sp[1] ($sp[0] + $v.dx) ($sp[1] + $v.dy) $false ($freeJs + 'return pageText();')
      $tip = ([string]$mid).Contains('Smallest size') -and ([string]$mid).Contains("400 $times 300 px")
      Check "drag-floor ($tag): the tip reads Smallest size: 400 $times 300 px. The line stops here." $tip 'no floor tip while the drag is held'
      $s = Fl-Saves $ws
      Check "drag-floor ($tag): one POST /layout" ($s.layout.Count -eq 1) "POST /layout count: $($s.layout.Count)"
      if ($s.layout.Count -ne 1) { return }
      $aL = Fl-AreaOf $s.layout[0].layout $lid
      $px = if ($aL) { Fl-AreaPx $aL.rect } else { @(0, 0, 0, 0) }
      $got = $px[$v.axis]
      Check "drag-floor ($tag): the space is not smaller than $($v.min) px on that side" ($got -ge ($v.min - 1) -and $got -le ($v.min + 2)) "space is $got px"
    }
  }

  $kdCases = @(
    @{ tag = 'Shift+Right moves the right edge in its row'; mods = 8; key = 'ArrowRight'; code = 39; sel = 1001; want = @{ 1001 = @(0, 0, (0.2 + $kd), 0.5); 1002 = @((0.2 + $kd), 0, (0.2 - $kd), 0.5) } },
    @{ tag = 'Ctrl+Shift+Left moves the left edge in its row'; mods = 10; key = 'ArrowLeft'; code = 37; sel = 1002; want = @{ 1001 = @(0, 0, (0.2 - $kd), 0.5); 1002 = @((0.2 - $kd), 0, (0.2 + $kd), 0.5) } },
    @{ tag = 'Alt+Shift+Right moves the whole line'; mods = 9; key = 'ArrowRight'; code = 39; sel = 1001; want = @{ 1001 = @(0, 0, (0.2 + $kd), 0.5); 1002 = @((0.2 + $kd), 0, (0.2 - $kd), 0.5); 1008 = @(0, 0.5, (0.2 + $kd), 0.5); 1009 = @((0.2 + $kd), 0.5, (0.2 - $kd), 0.5) } },
    @{ tag = 'a plain Right moves the window to the next space'; mods = 0; key = 'ArrowRight'; code = 39; sel = 1001; want = @{ 1001 = @(0.2, 0, 0.2, 0.5); 1002 = @(0, 0, 0.2, 0.5) } }
  )
  foreach ($v in $kdCases) {
    Case "keys ($($v.tag)): one 48th of the monitor, as the pointer moves it" {
      # Mutant: Shift+arrows move the line in every row, the step is a cell, or a plain arrow resizes instead of moving the window.
      $opened = Fl-Open $ws (Fl-Json (Fl-Board))
      Check "keys ($($v.tag)): the page opens on Focus (control)" $opened 'the page did not open on Focus in time'
      if (-not $opened) { return }
      $r0 = Fl-Rects $ws $flIds
      $c = Fl-Centre $r0 $v.sel
      Fl-Click $ws $c[0] $c[1]
      [void](Js $ws ($freeJs + 'const t = tileOf(' + $v.sel + '); if (t) t.focus({ preventScroll: true }); return true;'))
      $focused = Js $ws ($freeJs + 'const a = document.activeElement; return !!a && !!a.dataset && a.dataset.id === "' + $v.sel + '";')
      Check "keys ($($v.tag)): the window is selected and has focus (scope)" ($focused -eq $true) "window $($v.sel) did not take focus"
      if ($focused -ne $true) { return }
      Press-Key $ws $v.key $v.code '' $v.mods
      $s = Fl-Saves $ws
      Check "keys ($($v.tag)): one POST /layout" ($s.layout.Count -eq 1) "POST /layout count: $($s.layout.Count)"
      if ($s.layout.Count -ne 1) { return }
      $dd = @(Fl-AreaDiff $s.layout[0].layout $v.want)
      Check "keys ($($v.tag)): the spaces move as the pointer would move them" ($dd.Count -eq 0) ($dd -join ' | ')
    }
  }

  Case 'guard (green on main): on a grid monitor Shift+Right still resizes by a cell, with one POST /layout and no free areas' {
    # Mutant: the Free Layout keys reach a grid monitor, so a free area is written.
    $opened = Fl-Open $ws (Fl-Json (Fl-Board) -grid)
    Check 'grid keys: the page opens on the grid (control)' $opened 'the page did not open on Focus in time'
    if (-not $opened) { return }
    $r0 = Fl-Rects $ws $flIds
    $c = Fl-Centre $r0 1001
    Fl-Click $ws $c[0] $c[1]
    [void](Js $ws ($freeJs + 'const t = tileOf(1001); if (t) t.focus({ preventScroll: true }); return true;'))
    Press-Key $ws 'ArrowRight' 39 '' 8
    $s = Fl-Saves $ws
    Check 'grid keys: one POST /layout' ($s.layout.Count -eq 1) "POST /layout count: $($s.layout.Count)"
    Check 'grid keys: no free areas are written on a grid monitor' ($s.layout.Count -eq 1 -and $null -eq $s.layout[0].layout.grids.U1.free) 'a free area was written on a grid monitor'
  }

  Case 'assign-drop: a window dragged from Windows That Stay Put onto an empty space pins it there, and the space says so while the drag is over it' {
    # Mutant: the drop pins nothing, pins the window to another space, or the space does not say where the window goes.
    $opened = Fl-Open $ws (Fl-Json (Fl-Board @(9)) -fillOver @{ off = $true })
    Check 'assign-drop: the page opens on Focus (control)' $opened 'the page did not open on Focus in time'
    if (-not $opened) { return }
    $empty9 = Js $ws ($freeJs + 'const s = spaceOf(9); return !!s && s.classList.contains("empty");')
    Check 'assign-drop: space 9 is drawn empty (scope)' ($empty9 -eq $true) 'space 9 is not drawn as an empty space'
    if ($empty9 -ne $true) { return }
    $from = Js $ws ($freeJs + 'const c = document.querySelector("[data-bay=\"1014\"]"); const r = RR(c); return r ? { x: r.l + r.w / 2, y: r.t + r.h / 2 } : null;')
    $to = Js $ws ($freeJs + 'const r = RR(spaceOf(9)); return r ? { x: r.l + r.w / 2, y: r.t + r.h / 2 } : null;')
    Check 'assign-drop: the window in Windows That Stay Put and space 9 are both on screen (scope)' ($from -and $to) 'the chip or space 9 is not on screen'
    if (-not ($from -and $to)) { return }
    $mid = Fl-Drag $ws $from.x $from.y $to.x $to.y $false ($freeJs + 'return pageText();')
    Check 'assign-drop: while the window is over the space, the space says Notepad goes here' ([string]$mid -match 'Notepad goes here') 'no Notepad goes here while the drag is over space 9'
    $s = Fl-Saves $ws
    Check 'assign-drop: one POST /layout after the drop' ($s.layout.Count -eq 1) "POST /layout count: $($s.layout.Count)"
    if ($s.layout.Count -ne 1) { return }
    $L1 = $s.layout[0].layout
    $a9 = @($L1.grids.U1.free.areas)[9]
    $pin9 = $(if ($a9 -and $null -ne $a9.pin) { @($L1.pins)[[int]$a9.pin] } else { $null })
    Check 'assign-drop: space 9 holds the window: its pin names notepad' ($pin9 -and $pin9.app -eq 'notepad') 'space 9 has no pin for Notepad'
    $inside = Js $ws ($freeJs + 'const t = RR(tileOf(1014)), s = RR(spaceOf(9)); if (!t || !s) return false; const cx = t.l + t.w / 2, cy = t.t + t.h / 2; return cx >= s.l && cx <= s.r && cy >= s.t && cy <= s.b;')
    Check 'assign-drop: Notepad is drawn inside space 9' ($inside -eq $true) 'Notepad is not drawn inside space 9'
  }

  Case "assign-fill (F9): a new window takes the first empty space in reading order, and the next empty space reads Fills next" {
    # Mutant: the fill takes the last empty space, or the page draws the new window where tile.ps1 does not place it.
    # Only the board's windows are open, so the fill has no other unpinned window to take the spaces: 1012 is closed, and 1014 is the new one.
    $none = Fl-Snap @(1012, 1014, 1003, 1004, 1007, 1013, 1015, 1016)
    $fillAll = @{ apps = @('*') }
    $opened = Fl-Open $ws (Fl-Json (Fl-Board @(8, 9)) -fillOver $fillAll) $none
    Check 'assign-fill: the page opens with spaces 8 and 9 empty (control)' $opened 'the page did not open on Focus in time'
    if (-not $opened) { return }
    $two = Js $ws ($freeJs + 'return [8, 9].map(i => { const s = spaceOf(i); return !!s && s.classList.contains("empty"); });')
    Check 'assign-fill: spaces 8 and 9 are drawn empty (scope)' ((@($two) -join ',') -eq 'True,True') "drawn empty: $(@($two) -join ',')"
    $withNp = Fl-Snap @(1012, 1003, 1004, 1007, 1013, 1015, 1016)
    $opened2 = Fl-Open $ws (Fl-Json (Fl-Board @(8, 9)) -fillOver $fillAll) $withNp
    Check 'assign-fill: the page opens with Notepad open (control)' $opened2 'the page did not open in time with Notepad open'
    if (-not $opened2) { return }
    $eng = Fl-Engine
    $np = @($eng.placed | ? { [int64]$_.id -eq 1014 })[0]
    $want8 = Fl-AreaPx (Fl-Cell 8)
    $npTxt = $(if ($np) { "$($np.x),$($np.y) $($np.w)x$($np.h)" } else { 'nowhere' })
    Check 'assign-fill: tile.ps1 places Notepad in space 8, the first empty space in reading order' ($np -and (@([int]$np.x, [int]$np.y, [int]$np.w, [int]$np.h) -join ',') -eq ($want8 -join ',')) "engine places it at $npTxt, space 8 is $($want8 -join ',')"
    $pg = $(if ($np) { Fl-PageVsEngine $ws 1014 $np } else { 'no engine rect for Notepad' })
    Check 'assign-fill: the page draws Notepad where tile.ps1 places it' ($pg -eq '') $pg
    $fills = Js $ws ($freeJs + 'const s = spaceOf(9); return !!s && /Fills next/.test(s.textContent);')
    Check 'assign-fill: space 9 reads Fills next' ($fills -eq $true) 'space 9 does not read Fills next'
  }

  foreach ($kind in @('minimized', 'closed')) {
    Case "gap-lent ($kind, F10): the space of a $kind window is drawn lent, striped by its borrowers; the saved layout does not change" {
      # Mutant: the neighbours grow into the space (Grown Neighbours), the space is drawn plain, or the page saves on open.
      $snap = $(if ($kind -eq 'closed') { Fl-Snap @(1002) } else { Fl-Snap @() @(1002) })
      $opened = Fl-Open $ws (Fl-Json (Fl-Board)) $snap
      Check "gap-lent ($kind): the page opens on Focus (control)" $opened 'the page did not open on Focus in time'
      if (-not $opened) { return }
      $s = Fl-Saves $ws
      Check "gap-lent ($kind): opening the page sends no save" ($s.layout.Count -eq 0 -and $s.config.Count -eq 0) "saves on open: $($s.layout.Count) /layout, $($s.config.Count) /config"
      $a0 = (Fl-AreaPx (Fl-Cell 0)) -join ','; $a1 = (Fl-AreaPx (Fl-Cell 1)) -join ','; $a2 = (Fl-AreaPx (Fl-Cell 2)) -join ','
      $lent = Js $ws ($freeJs + 'const s = spaceOf(1); if (!s) return { has: false }; const parts = [...s.querySelectorAll(":scope > i")]; return { has: s.classList.contains("lent"), near: nearRect(s, spRect([' + $a1 + ']), 2), n: parts.length, fromL: parts.filter(p => p.classList.contains("fromL")).length, fromR: parts.filter(p => p.classList.contains("fromR")).length, striped: parts.length > 0 && parts.every(p => /repeating-linear-gradient/.test(getComputedStyle(p).backgroundImage)), nb: nearRect(tileOf(1001), spRect([' + $a0 + ']), 2) && nearRect(tileOf(1005), spRect([' + $a2 + ']), 2) };')
      Check "gap-lent ($kind): the space of window 1002 is drawn lent" ($lent -and $lent.has -eq $true) 'no lent space at space 1'
      Check "gap-lent ($kind): the lent space sits at its saved place" ($lent -and $lent.near -eq $true) 'the lent space is not at its saved rect'
      Check "gap-lent ($kind): two parts, one from the left neighbour and one from the right" ($lent -and $lent.n -eq 2 -and $lent.fromL -eq 1 -and $lent.fromR -eq 1) "parts: $(if ($lent) { "$($lent.n), fromL $($lent.fromL), fromR $($lent.fromR)" } else { 'none' })"
      Check "gap-lent ($kind): each part is striped" ($lent -and $lent.striped -eq $true) 'a part is not striped'
      Check "gap-lent ($kind): the neighbours keep their saved spaces" ($lent -and $lent.nb -eq $true) 'a neighbour grew into the space'
    }
  }

  Case "gap-stays (F11): with no neighbour able to take a closed window's space, the space stays a dashed gap that says so, and Close Gap is not offered" {
    # Mutant: a neighbour grows into the gap, Close Gap is offered for it, or tile.ps1 moves a window into it.
    $closedSnap = Fl-Snap @(1002)
    $opened = Fl-Open $ws (Fl-Json (Fl-Board @() @(0, 2, 6))) $closedSnap
    Check 'gap-stays: the page opens on Focus (control)' $opened 'the page did not open on Focus in time'
    if (-not $opened) { return }
    $a0 = (Fl-AreaPx (Fl-Cell 0)) -join ','; $a1 = (Fl-AreaPx (Fl-Cell 1)) -join ','; $a2 = (Fl-AreaPx (Fl-Cell 2)) -join ','
    $g = Js $ws ($freeJs + 'const s = spaceOf(1); if (!s) return { has: false }; return { has: s.classList.contains("gap"), near: nearRect(s, spRect([' + $a1 + ']), 2), stays: /Stays empty/.test(s.textContent), nogrow: nearRect(tileOf(1001), spRect([' + $a0 + ']), 2) && nearRect(tileOf(1005), spRect([' + $a2 + ']), 2) };')
    Check 'gap-stays: the space is drawn as a gap at its place' ($g -and $g.has -eq $true -and $g.near -eq $true) 'no gap at space 1'
    Check 'gap-stays: the gap says Stays empty' ($g -and $g.stays -eq $true) 'the gap does not say Stays empty'
    Check 'gap-stays: no neighbour grows into the gap' ($g -and $g.nogrow -eq $true) 'a neighbour grew into the gap'
    $c = Js $ws ($freeJs + 'const r = RR(spaceOf(1)); return r ? { x: r.l + r.w / 2, y: r.t + r.h / 2 } : null;')
    if ($c) { Fl-Click $ws $c.x $c.y }
    $ins = Js $ws ($freeJs + 'return { unlock: !!btnNamed(/^Unlock /), close: !!btnNamed(/^Close Gap$/) };')
    Check 'gap-stays: the inspector offers an Unlock button' ($ins -and $ins.unlock -eq $true) 'no Unlock button for the gap'
    Check 'gap-stays: Close Gap is not offered for the gap' ($ins -and $ins.close -eq $false) 'Close Gap is offered for a gap that stays'
    [IO.File]::WriteAllText($lastPath, '[{"id":1002,"x":819,"y":0,"w":819,"h":840}]', $utf8)
    $gf = Fl-Engine @('-GapFill', '-Absent', '1002', '-Last', "`"$lastPath`"")
    $gfN = $(if ($gf) { @($gf.placed).Count } else { -1 })
    Check 'gap-stays: tile.ps1 moves no window into the gap' ($gfN -eq 0) "placed by the gap-fill run: $gfN"
    Put-Split (Fl-Json (Fl-Board @() @(2, 6)))
    $gf2 = Fl-Engine @('-GapFill', '-Absent', '1002', '-Last', "`"$lastPath`"")
    $gf2Own = @(@($gf2.placed) | ? { [int64]$_.id -eq 1001 }).Count
    Check 'gap-stays (control): with the left window unlocked, tile.ps1 gives it the gap' ($gf2Own -eq 1) "1001 placed by the run: $gf2Own"
  }

  Case 'close-gap (F12): Close Gap on an empty space previews both strips, then shares the space at the middle and saves once' {
    # Mutant: one neighbour takes the whole space (item 17 in full), no strip is previewed, the gap is not removed, or the save drops the pin fields.
    $opened = Fl-Open $ws (Fl-Json (Fl-Board @(6)) -fillOver @{ off = $true })
    Check 'close-gap: the page opens with Free Layout on and space 6 empty (control)' $opened 'the page did not open on Focus in time'
    if (-not $opened) { return }
    $c = Js $ws ($freeJs + 'const r = RR(spaceOf(6)); return r ? { x: r.l + r.w / 2, y: r.t + r.h / 2 } : null;')
    if ($c) { Fl-Click $ws $c.x $c.y }
    $has = Js $ws ($freeJs + 'return !!btnNamed(/^Close Gap$/);')
    Check 'close-gap: the selected empty space offers Close Gap' ($has -eq $true) 'no Close Gap button for the selected empty space'
    if ($has -ne $true) { return }
    $s1 = (Fl-AreaPx @(0.2, 0.5, 0.1, 0.5)) -join ','; $s2 = (Fl-AreaPx @(0.3, 0.5, 0.1, 0.5)) -join ','
    $prev = Js $ws ($freeJs + 'const b = btnNamed(/^Close Gap$/); if (b) b.focus(); const near = s => [...document.querySelectorAll("#stage *")].some(e => nearRect(e, s, 2)); return { left: near(spRect([' + $s1 + '])), right: near(spRect([' + $s2 + '])) };')
    Check 'close-gap: while Close Gap has focus, the left strip is previewed' ($prev -and $prev.left -eq $true) 'no preview of the strip the left neighbour takes'
    Check 'close-gap: while Close Gap has focus, the right strip is previewed' ($prev -and $prev.right -eq $true) 'no preview of the strip the right neighbour takes'
    [void](Js $ws ($freeJs + 'const b = btnNamed(/^Close Gap$/); if (b) b.click(); return !!b;'))
    $s = Fl-Saves $ws
    Check 'close-gap: one POST /layout' ($s.layout.Count -eq 1) "POST /layout count: $($s.layout.Count)"
    if ($s.layout.Count -ne 1) { return }
    $L1 = $s.layout[0].layout
    $n9 = @($L1.grids.U1.free.areas).Count
    Check 'close-gap: the empty space is removed (9 spaces left)' ($n9 -eq 9) "spaces: $n9"
    $wGap = @{}; $wGap[1009] = 'gone'; $wGap[1008] = @(0, 0.5, 0.3, 0.5); $wGap[1011] = @(0.3, 0.5, 0.3, 0.5)
    $dd = @(Fl-AreaDiff $L1 $wGap)
    Check 'close-gap: the neighbours meet at the middle: Terminal takes 0 to 0.3, Downloads 0.3 to 0.6' ($dd.Count -eq 0) ($dd -join ' | ')
    $pinN = @(Fl-Pinned $L1).Count
    Check 'close-gap: the saved layout holds a pinned space to compare (guard)' ($pinN -ge 1) "pinned spaces in the saved layout: $pinN"
    if ($pinN -lt 1) { return }
    $ed = @(Fl-EngineDiff (Fl-Engine) $L1)
    Check 'close-gap: tile.ps1 places each window in its saved space' ($ed.Count -eq 0) ($ed -join ' | ')
  }

  foreach ($v in @(@{ tag = 'side by side'; item = 'Chrome Keeps Left' }, @{ tag = 'stacked'; item = 'Chrome Keeps Top' })) {
    $tag = $v.tag; $item = $v.item
    Case "split-area ($tag): a split in Free Layout adds one line and one empty half; each group says Adds a line" {
      # Mutant: the split doubles the grid, the empty half holds a pin, or the menu does not name the space.
      $opened = Fl-Open $ws (Fl-Json (Fl-Board))
      Check "split-area ($tag): the page opens on Focus (control)" $opened 'the page did not open on Focus in time'
      if (-not $opened) { return }
      $r0 = Fl-Rects $ws $flIds
      if (-not $r0.'1005') { Check "split-area ($tag): Chrome is on the board (scope)" $false 'Chrome is not on the board'; return }
      $c = Fl-Centre $r0 1005
      Click-Right $ws $c[0] $c[1]
      $menu = WaitFor $ws '[...document.querySelectorAll("[role=menu]")].some(m => m.getClientRects().length > 0 && /Keeps/.test(m.textContent))' 10
      Check "split-area ($tag): the right-click opens the split menu" $menu 'no split menu opened in time'
      if (-not $menu) { return }
      $mt = Js $ws ($freeJs + 'const m = [...document.querySelectorAll("[role=menu]")].find(x => x.getClientRects().length > 0 && /Keeps/.test(x.textContent)); return { heading: /Split Chrome.{1,2}s Space/.test(m.textContent), adds: (m.textContent.match(/Adds a line/g) || []).length };')
      Check "split-area ($tag): the menu names Chrome's space" ($mt -and $mt.heading -eq $true) "the menu does not read Split Chrome's Space"
      Check "split-area ($tag): each group says Adds a line" ($mt -and $mt.adds -eq 2) "Adds a line counted: $(if ($mt) { $mt.adds } else { 0 })"
      [void](Js $ws ($freeJs + 'const it = [...document.querySelectorAll("[role=menuitem]")].find(x => x.textContent.replace(/\s+/g, " ").trim() === "' + $item + '"); if (it) it.click(); return !!it;'))
      $s = Fl-Saves $ws
      Check "split-area ($tag): one POST /layout" ($s.layout.Count -eq 1) "POST /layout count: $($s.layout.Count)"
      if ($s.layout.Count -ne 1) { return }
      $L1 = $s.layout[0].layout
      $areas = @($L1.grids.U1.free.areas)
      Check "split-area ($tag): the monitor has 11 spaces, and the grid does not double" ($areas.Count -eq 11 -and $L1.grids.U1.c -eq 5 -and $L1.grids.U1.r -eq 2) "spaces: $($areas.Count), c $($L1.grids.U1.c), r $($L1.grids.U1.r)"
      $ac = Fl-AreaOf $L1 1005
      $half = $(if ($ac) { $ac.rect[2] * $ac.rect[3] } else { 0 })
      Check "split-area ($tag): Chrome keeps one half of its space (0.05 of the monitor)" ([Math]::Abs($half - 0.05) -lt 1e-4) "Chrome's space is $half of the monitor"
      $unp = @($areas | ? { $null -eq $_.pin }).Count
      Check "split-area ($tag): the new half is one empty space, with no pin" ($unp -eq 1) "spaces with no pin: $unp"
      $tot = 0; foreach ($a in $areas) { $tot += $a.rect[2] * $a.rect[3] }
      Check "split-area ($tag): the spaces still cover the monitor" ([Math]::Abs($tot - 1) -lt 1e-6) "total area: $tot"
    }
  }

  foreach ($choice in @('Snap to Cells', 'Restore the Grid Layout')) {
    Case "back ($choice): switching Free Layout off opens Back to the Grid; nothing saves until Back to Grid, which saves once" {
      # Mutant: the switch saves before Back to Grid, Snap is not the default, or Restore does not give the grid back.
      $gridJson = Fl-Json (Fl-Board) -grid
      $opened = Fl-Open $ws (Fl-Json (Fl-Board))
      Check "back ($choice): the page opens on Focus (control)" $opened 'the page did not open on Focus in time'
      if (-not $opened) { return }
      [void](Js $ws ($freeJs + 'const s = freeSw(); if (s) s.click(); return !!s;'))
      $pop = WaitFor $ws '[...document.querySelectorAll("[role=dialog]")].some(d => /Back to the Grid/.test(d.textContent))' 10
      Check "back ($choice): switching off opens Back to the Grid" $pop 'no Back to the Grid popover'
      if (-not $pop) { return }
      $snapDef = Js $ws ($freeJs + 'const r = [...document.querySelectorAll("input[type=radio]")].find(x => /Snap to Cells/.test((x.closest("label") || {}).textContent || "")); return r ? r.checked : null;')
      Check "back ($choice): Snap to Cells is the default" ($snapDef -eq $true) 'Snap to Cells is not checked by default'
      $pre = Fl-Saves $ws
      Check "back ($choice): nothing is saved before Back to Grid" ($pre.layout.Count -eq 0) "saves: $($pre.layout.Count)"
      if ($choice -ne 'Snap to Cells') {
        [void](Js $ws ($freeJs + 'const l = [...document.querySelectorAll("label")].find(x => /Restore the Grid Layout/.test(x.textContent)); const r = l && l.querySelector("input[type=radio]"); if (r) r.click(); return !!r;'))
      }
      [void](Js $ws ($freeJs + 'const b = btnNamed(/^Back to Grid$/); if (b) b.click(); return !!b;'))
      $s = Fl-Saves $ws
      Check "back ($choice): Back to Grid sends one POST /layout" ($s.layout.Count -eq 1) "POST /layout count: $($s.layout.Count)"
      if ($s.layout.Count -ne 1) { return }
      $L1 = $s.layout[0].layout
      Check "back ($choice): the saved layout has no free areas" ($null -eq $L1.grids.U1.free) 'the saved layout still holds free areas'
      if ($choice -eq 'Snap to Cells') {
        $badSnap = @(for ($i = 0; $i -lt 10; $i++) { $got = Split-SlotsOf $L1 $flWins[$i].match; if ($got -ne "$i") { "$($flWins[$i].match) at slot $got" } })
        Check 'back (Snap to Cells): the grid stays 5 by 2, and each window snaps into its own cell' ($L1.grids.U1.c -eq 5 -and $L1.grids.U1.r -eq 2 -and $badSnap.Count -eq 0) ($badSnap -join ' | ')
      } else {
        $g0 = ConvertFrom-Json $gridJson
        Check 'back (Restore): the grid is the one from before Free Layout' ((Canon $L1.grids.U1) -ceq (Canon $g0.grids.U1)) 'the restored grid differs from the grid before Free Layout'
      }
    }
  }

  Case 'empty (F16): a Free Layout monitor with every space empty keeps its lines, reads Empty, and its one control sits under the board' {
    # Mutant: a space is drawn with no Empty word, the sentence is missing, or the control covers a space.
    $opened = Fl-Open $ws (Fl-Json (Fl-Board @(0, 1, 2, 3, 4, 5, 6, 7, 8, 9)) -fillOver @{ off = $true })
    Check 'empty: the page opens with every space empty (control)' $opened 'the page did not open on Focus in time'
    if (-not $opened) { return }
    $e = Js $ws ($freeJs + 'const es = [...document.querySelectorAll(".space.empty")]; const b = btnNamed(/^Turn On Fill Empty Cells$/); const bottom = es.length ? Math.max(...es.map(x => RR(x).b)) : 0; return { n: es.length, allEmpty: es.length > 0 && es.every(x => /Empty/.test(x.textContent)), sentence: pageText().indexOf("No window is placed on the ultrawide. Drag one here from Windows That Stay Put, or let windows fill the spaces.") >= 0, ctl: !!b, under: !!b && RR(b).t >= bottom - 1 };')
    Check 'empty: all ten spaces are drawn empty' ($e -and $e.n -eq 10) "empty spaces drawn: $(if ($e) { $e.n } else { 'none' })"
    Check 'empty: each space reads Empty' ($e -and $e.allEmpty -eq $true) 'a space does not read Empty'
    Check 'empty: one sentence says what fills the spaces' ($e -and $e.sentence -eq $true) 'the sentence about what fills the spaces is not on the page'
    Check 'empty: one control, Turn On Fill Empty Cells, is on the page' ($e -and $e.ctl -eq $true) 'no Turn On Fill Empty Cells control'
    Check 'empty: the control sits under the board, covering no space' ($e -and $e.under -eq $true) 'the control sits on the board'
  }

  Case 'err-save (F14): a plain drag whose save fails turns the setup strip amber, with Not saved, Undo still works, and Try Again' {
    # Mutant: a failed save shows nothing, or the strip drops Undo or Try Again.
    $opened = Fl-Open $ws (Fl-Json (Fl-Board))
    Check 'err-save: the page opens on Focus (control)' $opened 'the page did not open on Focus in time'
    if (-not $opened) { return }
    [void](Js $ws ($freeJs + 'const prev = window.fetch; window.fetch = (u, o) => (String(u) === "layout" && o && String(o.method || "").toUpperCase() === "POST") ? Promise.resolve(new Response("the app server stopped answering", { status: 500 })) : prev(u, o); return true;'))
    $r0 = Fl-Rects $ws $flIds
    if (-not ($r0.'1001' -and $r0.'1002')) { Check 'err-save: Refactor and Pin parser are on the board (scope)' $false 'a tile of the seam is not on the board'; return }
    $sp = Fl-SeamV $r0 1001 1002
    [void](Fl-Drag $ws $sp[0] $sp[1] ($sp[0] + 40) $sp[1])
    [void](WaitFor $ws 'document.getElementById("setbar").classList.contains("warn")' 15)
    $st = Js $ws $stripJs
    Check 'err-save: the setup strip turns amber' ($st -and $st.warn -eq $true) 'the setup strip is not amber after the failed save'
    Check 'err-save: the strip says Not saved.' ($st -and $st.text -match 'Not saved\.') "strip reads: $(if ($st) { $st.text } else { 'nothing' })"
    Check 'err-save: the strip says Undo still works' ($st -and $st.text -match 'Undo still works') 'the strip does not say Undo still works'
    Check 'err-save: Try Again is offered' ($st -and @($st.buttons) -contains 'Try Again') "buttons: $(if ($st) { @($st.buttons) -join ' | ' } else { 'none' })"
  }

  foreach ($v in @(
      @{ tag = 'an app will not fit its space'; note = 'off size: is 410x840, restore rect 410x840, wanted 500x840'; raw = 'off size'; words = 'will not go under 500 px wide' },
      @{ tag = 'a pin no space holds'; note = 'not in a free area'; raw = 'not in a free area'; words = '' })) {
    $tag = $v.tag; $note = $v.note; $raw = $v.raw; $words = $v.words
    Case "err-apply ($tag, F14): the result row says it in words, with a fix button, and the engine's words behind a disclosure" {
      # Mutant: the raw engine text shows on the row, or the row offers no fix.
      $opened = Fl-Open $ws (Fl-Json (Fl-Board))
      Check "err-apply ($tag): the page opens on Focus (control)" $opened 'the page did not open on Focus in time'
      if (-not $opened) { return }
      # The engine's reply to a scene run (POST scene): an app placed off size, or a pin no space holds, as tile.ps1 returns them.
      $reply = if ($words) {
        [ordered]@{ placed = @([ordered]@{ id = 1001; app = 'claude'; title = 'Refactor the grid solver'; ok = $false; note = $note; x = 0; y = 0; w = 410; h = 840; from = [ordered]@{ x = 0; y = 0; w = 819; h = 840 }; pin = 0; zone = -1; slots = @(0) }); missing = @(); left = @() }
      } else {
        [ordered]@{ placed = @(); missing = @([ordered]@{ app = 'claude'; match = 'Refactor the grid solver'; why = $note }); left = @() }
      }
      $replyLit = ConvertTo-Json -Depth 8 -Compress -InputObject $reply
      [void](Js $ws ($freeJs + 'const prev = window.fetch; window.fetch = (u, o) => (String(u) === "scene" && o && String(o.method || "").toUpperCase() === "POST") ? Promise.resolve(new Response(' + (ConvertTo-Json -Compress $replyLit) + ', { status: 200, headers: { "Content-Type": "application/json" } })) : prev(u, o); return true;'))
      [void](Js $ws 'const b = document.getElementById("apply"); if (b) b.click(); return !!b;')
      # The page lists the results in #reslist; the results panel opens from the toast's More control, as a user opens it.
      $listed = WaitFor $ws 'document.querySelectorAll("#reslist li").length > 0' 15
      if ($listed) { [void](Js $ws 'const r = document.getElementById("results"); if (r && r.hidden) { const m = document.getElementById("toastMore"); if (m) m.click(); } return true;') }
      $shown = $listed -and (WaitFor $ws '!!document.getElementById("results") && !document.getElementById("results").hidden' 10)
      Check "err-apply ($tag): the apply results row shows" $shown 'no apply results row in time'
      if (-not $shown) { return }
      $rs = Js $ws ($freeJs + 'const res = document.getElementById("results"); if (!res) return null; const sums = [...res.querySelectorAll("details summary")].map(x => x.textContent.replace(/\s+/g, " ").trim()); const buttons = [...res.querySelectorAll("button")].map(x => x.textContent.replace(/\s+/g, " ").trim()); const det = [...res.querySelectorAll("details")].map(x => x.textContent.replace(/\s+/g, " ")).join(" "); const clone = res.cloneNode(true); clone.querySelectorAll("details").forEach(x => x.remove()); return { visible: clone.textContent.replace(/\s+/g, " "), det: det, sums: sums, buttons: buttons };')
      $vis = $(if ($rs) { [string]$rs.visible } else { '' })
      $det = $(if ($rs) { [string]$rs.det } else { '' })
      Check "err-apply ($tag): the engine's words are not on the row itself" (-not $vis.Contains($raw)) "the row shows: $raw"
      Check "err-apply ($tag): the engine's words sit behind What the server said" ($det.Contains($raw) -and (@($rs.sums) -match 'What the server said').Count -ge 1) 'no disclosure What the server said holds the engine text'
      if ($words) {
        Check "err-apply ($tag): the row says it in words: will not go under 500 px wide" ($vis.Contains($words)) 'the row does not say it in words'
        Check "err-apply ($tag): a Give It 500 px button leads on" (@($rs.buttons) -contains 'Give It 500 px') 'no Give It 500 px button'
      } else {
        Check "err-apply ($tag): the row offers a fix button besides Close" (@(@($rs.buttons) | ? { $_ -ne 'Close' }).Count -ge 1) "buttons: $(@($rs.buttons) -join ' | ')"
      }
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
