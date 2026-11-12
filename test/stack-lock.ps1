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
#     locked tile it reads Behind and "Locked, so no Swap" (Locked on narrow cells), with no Swap action. On a spanned block the same split covers the whole block, and it
#     never reads Place here. A drop on the lower band stacks the dragged window behind; a drop on the upper zone swaps.
#     The inspector, for the selected front tile, has a Bring to Front and a Take Out button for each window behind it.
#     A grip drag of 1.4 cells to the right, on a 1x1 tile, makes a 2-column span (whole cells, rounded).
#     Shift+arrow and the Width and Height steppers grow a span the same way as the grip: a covered pin moves with its stack to
#     the first free cell, else to Windows That Stay Put, and growth stops at a locked tile.
#     A stacked tile's badge (.stk) has a hit extension (its ::after inset). At 1024 and 1440 its hit box clears the
#     .rsz grip, the .lk lock and the .stayput Stay Put (the badge-grip overlap debt).
#     With ten or more windows behind, a narrow (1024) badge shows the back app's initial and its aria-label names the true
#     count; at 1440 it reads "Claude +9" (the back app's name, then +1 for each other window behind).
#   Board feedback (decisions/stack-and-lock.md, decisions/fill-controls.md, docs/design/mockups/board-feedback-notes.md):
#     scene fill.off     true turns Fill Empty Cells off: tile.ps1 places only pins (locked or not, with their stacks); zones
#                        place nothing. Absent or false is today's fill.
#     .dnote             Drop Note, role=status, shown after a Put Behind drop. Its text names both apps ("Chrome is behind
#                        Claude"), with a button "Undo" inside .dnote. Undo restores the scene from before the drop. The note
#                        fades on its own (about 6 s); the harness reads it right after the release, never after a settle.
#     .tile.stacked.peeked  a stacked tile carries the layer; .peek (on the stage, not in the tile) names the back app. The 3px
#                        .stkedge is gone. A press on the .peek strip above the front tile is a press on the front tile.
#                        For 1.5 s after a Put Behind drop the strip flashes (.peek.flash, z5) and covers the lock's top edge;
#                        a real press on that edge still toggles the lock.
#     .tile .stk         the badge's visible content. At 1440 the back app's name ("Chrome", "Chrome +1" for two). On a narrow
#                        tile (.tile.narrow, 1024) the back app's initial only. The count is in its title and aria-label.
#     .hdl i             the eight handles of the selected tile, drawn outside it: corners i.c.tl, i.c.tr, i.c.bl, i.c.br;
#                        edges i.e.n, i.e.s, i.e.w, i.e.ea (east is ea). A press at a handle's centre drags a resize in its
#                        direction, snapped to whole cells, as the corner grip does. A pure edge handle (n, s, ea, w) moves only
#                        its own edge, so a lock stops it short and the other dimension stays. A corner keeps the largest span
#                        that stops short of the lock, as the grip does. Hit areas (the mockup's .hit geometry):
#                        corners 10 by 10 and edge bands 7 px, outside the tile border. They never cover the lock, the tag
#                        (the tile's b), the badge, the grip or Stay Put.
#     keys               Ctrl+Shift+ArrowLeft and ArrowUp grow the left or top edge (the origin moves) with Shift+arrow's rules:
#                        covered pins move to free cells with their stacks, else to Windows That Stay Put; a locked tile stops
#                        it ("A locked tile is in the way"). Ctrl+Shift+ArrowRight and ArrowDown shrink that edge.
#     input[role=switch] inside a label whose text is "Fill Empty Cells", in the Monitor section of the monitor that fills.
#                        Checked is on. Turning it off holds each window the fill or a zone placed where it is, in the scene's
#                        held layout (decisions/fill-controls.md, owner ruling 2026-11-12 12:05 CST). It adds no pin, and no pin
#                        mark shows. A freed cell stays empty. A pin for a closed window (no open window) keeps its cell, and its lock if it has one;
#                        nothing is held over its cell, so the window the fill had on that cell goes to
#                        Windows That Stay Put, unpinned. The status line (#msg) names how many it holds: "N windows are held
#                        where they are". The holds come from the newest placement, even while a drop's answer is still pending.
#     scene fill.held    The held layout: an array with one entry per window that fill-off holds where it is. It is apart from
#                        the pins, and empty or absent when nothing is held. Turning fill back on clears it. A window taken off
#                        the board leaves it, so its cell stays empty. Clear Board holds nothing. While fill is off, tile.ps1
#                        -Scene (and -DryRun) places each held window in its cell. An entry is {app, title, mon, slots}, with the
#                        page's handle as id while the page holds it. A held window matches as a pin does: by its app, and by its
#                        title only when its app has several windows: the exact title first, then one that contains it. A stale id holds no window, so no other window takes its
#                        cell. A held cell is never a pin's, locked or not. A pin of one of two windows with one title drops only its hold.
#     #bgrps [data-bay]  the chips of Windows That Stay Put. A chip dragged onto a tile's lower band puts that window behind it,
#                        and the window leaves the list at once: the board, the Behind This Window list and the badge agree with
#                        no other action (a passive wait for the engine's answer, never a settle).
#     button "Clear Board" on the board's action bar. It sets fill.off and holds nothing (fill.held stays empty); the status line
#                        (#msg) reads "Cleared the board. N windows stay put, and Fill Empty Cells is off."; each window the fill
#                        had placed is in prevs[selId].left, and Windows That Stay Put shows "Fill is off" for it.
#                        With fill off, every open window that is not pinned has the reason "fill is off" (engine left[]) and reads
#                        "Fill is off" in its list reason line, whatever its app: an app with a pinned window included.
#                        A tab click on another scene while the switch waits for its scene's preview leaves that scene as it was:
#                        the switch changes the scene it was pressed on.
#     inspector          A narrow pinned tile (its pin mark hidden at 1024) selected: its "Pinned" line is in the inspector's visible area.
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
function SlSceneJson($pins, $fill = '[]', $extra = '', $off = '', $grid = '"c":5,"r":2') {
  '{"id":"sl","name":"Stack and lock","trigger":{"type":"manual","days":[],"time":"09:00"},"grids":{"wide":{' + $grid + '}},"pins":' + $pins + ',"fill":{"mon":"wide","apps":' + $fill + ',"skip":[],"sort":"app"' + $off + '}' + $extra + '}'
}
# A dry-run engine call (no window moves): the scene as tile.ps1 -Scene reads it, placed[] and left[] back. The fixture is the shared one unless a second argument names another.
function SlDry($scene, $from = $fixture) { (& $tile -Scene $scene -From $from -DryRun -Json 3>$null) -join '' | ConvertFrom-Json }
function SlPl($r) { (@($r.placed) | % { "$($_.id)p$($_.pin)z$($_.zone)" }) -join ' ' }
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
$srv = $null; $srvDup = $null; $edgeProc = $null; $script:ws = $null; $script:cdpId = 0; $script:url = ''; $script:udd = Join-Path $run 'edge'

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
function SlViewport($w, $h) { [void](SlSend 'Emulation.setDeviceMetricsOverride' @{ width = $w; height = $h; deviceScaleFactor = 1; mobile = $false }) }
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
function SlLabelShown { SlJs "getComputedStyle(document.getElementById('drop')).display !== 'none'" }
# Focuses a tile and presses one arrow key on it: the keydown the board reads. $mods is the CDP modifier bits (Shift is 8).
function SlKey($id, $key, $vk, $mods = 0) {
  [void](SlJs "(() => { els.get($id).focus({ preventScroll: true }); return true; })()")
  [void](SlSend 'Input.dispatchKeyEvent' @{ type = 'keyDown'; key = $key; code = $key; windowsVirtualKeyCode = $vk; modifiers = $mods })
  [void](SlSend 'Input.dispatchKeyEvent' @{ type = 'keyUp'; key = $key; code = $key; windowsVirtualKeyCode = $vk; modifiers = $mods })
  SlSettle }
# Types a Title contains value into the inspector's field, and fires its change, as a typed value does.
function SlTitle($text) { [void](SlJs "(() => { const i = document.getElementById('match'); if (!i) return false; i.value = '$text'; i.dispatchEvent(new Event('change', { bubbles: true })); return true; })()"); SlSettle }
# Presses the Fewer button of the monitor's Columns (k = c) or Rows (k = r) stepper, when it is enabled.
# Presses an inspector stepper button (data-$key = $val, data-d = $d) and returns what it found: 'pressed', 'disabled' or
# 'no such button', so a case names a miss. SlFewer presses the Fewer button of a monitor's Columns (g = c) or Rows (g = r).
function SlStep($key, $val, $d) {
  $r = SlJs "(() => { const b = [...document.querySelectorAll('button')].find(x => x.dataset.$key === '$val' && x.dataset.d === '$d'); if (!b) return 'no such button'; if (b.disabled) return 'disabled'; b.click(); return 'pressed'; })()"
  SlSettle
  "$r" }
function SlFewer($k) { [void](SlStep 'g' $k '-1') }
# The text of the inspector's Behind This Window list ('' when it is not drawn), and a placed window by id (null when none).
function SlBehindText { SlJs "(() => { const b = document.querySelector('#win .bstack'); return b ? b.textContent : ''; })()" }
function SlPlacedOf($id) { SlGet "prevs[selId].placed.find(p => p.id === $id) || null" }
# Hit boxes for the badge cases: the badge (its box, widened by its ::after inset), the grip, the lock and Stay Put, on the
# board. An element that is not drawn, or has pointer-events none, has no hit box (null). The text point is the centre of the
# badge's visible text; hitAt names what the page would hit there.
function SlHitBoxes($id) {
  SlGet (@(
    "(() => { const t = els.get($id); if (!t) return null;",
    "const box = b => ({ l: b.left, t: b.top, r: b.right, b: b.bottom }), n = v => parseFloat(v) || 0;",
    "const hit = sel => { const e = t.querySelector(sel); if (!e) return null; const cs = getComputedStyle(e);",
    "  if (cs.display === 'none' || cs.visibility === 'hidden' || cs.pointerEvents === 'none' || !e.getClientRects().length) return null;",
    "  const r = e.getBoundingClientRect(), a = getComputedStyle(e, '::after');",
    "  if (a.position !== 'absolute' || a.content === 'none' || a.content === 'normal') return box(r);",
    "  return { l: r.left + n(a.left), t: r.top + n(a.top), r: r.right - n(a.right), b: r.bottom - n(a.bottom) }; };",
    "const sk = t.querySelector('.stk');",
    "let tx = null; if (sk) { const rg = document.createRange(); rg.selectNodeContents(sk); const q = rg.getBoundingClientRect();",
    "  tx = { x: (q.left + q.right) / 2, y: (q.top + q.bottom) / 2, l: q.left, t: q.top, r: q.right, b: q.bottom }; }",
    "const at = tx ? document.elementFromPoint(tx.x, tx.y) : null;",
    "const who = at ? (at.closest('.stk') ? 'badge' : at.closest('.rsz') ? 'grip' : at.closest('.lk') ? 'lock' : at.closest('.stayput') ? 'Stay Put' : 'other') : null;",
    "return { badge: hit('.stk'), grip: hit('.rsz'), lock: hit('.lk'), spt: hit('.stayput'), tag: hit('b'), sel: t.classList.contains('sel'),",
    "  stacked: t.classList.contains('stacked'), narrow: t.classList.contains('narrow'), tile: box(t.getBoundingClientRect()), text: tx, hitAt: who }; })()"
  ) -join ' ')
}
# Two boxes overlap by positive area (touching edges do not count). A missing box never overlaps.
function SlMeets($a, $b) { [bool]($a -and $b -and $a.l -lt $b.r -and $b.l -lt $a.r -and $a.t -lt $b.b -and $b.t -lt $a.b) }
function SlHit($b) { if (-not $b) { 'none' } else { '{0},{1} to {2},{3}' -f [int]$b.l, [int]$b.t, [int]$b.r, [int]$b.b } }
# One state of the badge cases. A fresh scene; the front window is selected, or Quarterly is, so the stack is not. The boxes
# are read after a hover on the badge text. The click on the text runs last, after every read of the state.
# $Pins and $Behind (the windows behind Refactor) pick the scene. Ten or more: the narrow text caps at 9+.
function SlBadgeState($w, $h, [bool]$Selected, $Pins = $pinsBadge, [int]$Behind = 2) {
  $state = 'not selected'; if ($Selected) { $state = 'selected' }
  $pre = ''; $gpre = 'guard: '; if ($w -eq 1440) { $pre = 'control: '; $gpre = $pre }
  $tag = "badge $w, $state, $Behind behind"
  SlViewport $w $h
  SlCase (SlSceneJson $Pins)
  if ($Selected) { SlClick (SlAt (SlBox 1001) 0.5 0.5) } else { SlClick (SlAt (SlBox 1006) 0.5 0.5) }
  $r0 = SlHitBoxes 1001
  if ($r0 -and $r0.text) { SlMouse 'mouseMoved' $r0.text.x $r0.text.y 0; SlFrame }
  $b = SlHitBoxes 1001
  Check "${pre}${tag}: scope, the front window is stacked with its badge drawn, and selected only as the case says" ([bool]($b -and $b.stacked -and $b.badge -and ([bool]$b.sel -eq $Selected))) "stacked: $($b.stacked), badge: $(SlHit $b.badge), selected: $($b.sel)"
  Check "${pre}${tag}: scope, the tile is narrow at 1024 and not at 1440" ([bool]($b -and ([bool]$b.narrow -eq ($w -eq 1024)))) "narrow: $($b.narrow)"
  Check "${pre}${tag}: its badge hit box clears the resize grip" (-not (SlMeets $b.badge $b.grip)) "badge $(SlHit $b.badge), grip $(SlHit $b.grip)"
  Check "${gpre}${tag}: its badge hit box clears the lock" (-not (SlMeets $b.badge $b.lock)) "badge $(SlHit $b.badge), lock $(SlHit $b.lock)"
  if ($Selected) {
    Check "${pre}${tag}: scope, Stay Put is drawn on the selected tile" ([bool]($b -and $b.spt)) "Stay Put: $(SlHit $b.spt)"
    Check "${gpre}${tag}: its badge hit box clears Stay Put" (-not (SlMeets $b.badge $b.spt)) "badge $(SlHit $b.badge), Stay Put $(SlHit $b.spt)"
  }
  $inView = [bool]($b -and $b.text -and $b.tile -and $b.text.x -ge $b.tile.l -and $b.text.x -le $b.tile.r -and $b.text.y -ge $b.tile.t -and $b.text.y -le $b.tile.b -and $b.text.x -ge 0 -and $b.text.x -lt $w -and $b.text.y -ge 0 -and $b.text.y -lt $h)
  Check "${pre}${tag}: scope, the badge text centre is inside the viewport and inside the tile" $inView "text: $(SlShort $b.text), tile: $(SlShort $b.tile)"
  # Ten or more behind: a narrow badge shows the back app's initial, and its aria-label keeps the true count (a guard). At 1440 the text is the back app's name and +9.
  if ($Behind -ge 10) {
    $bt = SlGet "(() => { const s = els.get(1001) && els.get(1001).querySelector('.stk'); return s ? { text: s.textContent.trim(), label: s.getAttribute('aria-label') } : null; })()"
    if ($w -eq 1024) {
      Check "${tag}: the badge text is the back app's initial (C) on a narrow tile" ([bool]($bt -and $bt.text -eq 'C')) "text: $($bt.text)"
      Check "${gpre}${tag}: the badge aria-label names 10 windows behind" ([bool]($bt -and $bt.label -match '(?<![0-9])10 ')) "aria-label: $($bt.label)"
    } else {
      Check "${tag}: the badge text reads Claude +9 at 1440" ([bool]($bt -and $bt.text -eq 'Claude +9')) "text: $($bt.text)"
    }
  }
  Check "${pre}${tag}: a press on the badge text reaches the badge, so no resize starts" ($b.hitAt -eq 'badge') "a press at the text centre lands on: $($b.hitAt)"
  if ($inView) { SlClick @([double]$b.text.x, [double]$b.text.y) }
  $after = SlGet "prevs[selId].placed.map(p => ({ id: p.id, pin: p.pin, behind: !!p.behind }))"
  $front2 = @($after | ? { $_.pin -eq 0 -and -not $_.behind })
  $ref = @($after | ? { $_.id -eq 1001 })[0]
  Check "${pre}${tag}: the click brings the back window to the front, with Refactor behind it" ([bool]($front2.Count -eq 1 -and $front2[0].id -ne 1001 -and $ref -and $ref.behind -eq $true)) "placed: $(SlShort $after)"
}
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
function SlStartServer($from = $fixture, $tileHome = $env:TILE_HOME) {
  $psi = New-Object Diagnostics.ProcessStartInfo 'powershell', "-NoProfile -ExecutionPolicy Bypass -File `"$serve`" -NoBrowser -From `"$from`""
  $psi.UseShellExecute = $false; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true; $psi.CreateNoWindow = $true
  $psi.EnvironmentVariables['USERPROFILE'] = $profile; $psi.EnvironmentVariables['APPDATA'] = Join-Path $profile 'AppData\Roaming'; $psi.EnvironmentVariables['TILE_HOME'] = $tileHome
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
  SlViewport 1440 900
  $proc
}

# Board feedback helpers. A lookup that finds nothing gives null, so a red case fails on its assert, never on a throw.
# The placed rect of window $id from the engine's last answer (a back window has its front's rect).
function SlPlacedRect($id) { SlGet "(() => { const p = prevs[selId] && prevs[selId].placed.find(q => q.id === $id); return p ? { x: p.x, y: p.y, w: p.w, h: p.h, behind: !!p.behind } : null; })()" }
function SlSameRect($a, $b) { [bool]($a -and $b -and $a.x -eq $b.x -and $a.y -eq $b.y -and $a.w -eq $b.w -and $a.h -eq $b.h) }
# The pins (app, match, monitor, sorted slots, behind, lock) and the bay of the scene, as one string. Read the same before and after an edit.
$SceneNorm = "JSON.stringify([(work[selId].pins || []).map(p => [p.app, p.match || '', p.mon, [...p.slots].sort((a, b) => a - b), (p.behind || []).map(b => [b.app, b.match || '']), !!p.lock]), (work[selId].bay || []).map(b => [b.app, b.title || ''])])"
# The Drop Note's text, read at once after the release: a bounded poll in the page, not a settle, since the note fades on its own.
function SlNoteText { SlJs "new Promise(res => { let n = 0; (function poll() { const e = document.querySelector('.dnote'); if (e) return res(e.textContent.replace(/\s+/g, ' ').trim()); if (++n > 160) return res(null); setTimeout(poll, 25); })(); })" }
# Presses on $from, moves in eight steps to $to, and releases with no settle, so a Drop Note is read before it goes.
function SlDropNoSettle($from, $to) { SlMouse 'mousePressed' $from[0] $from[1] 1; for ($i = 1; $i -le 8; $i++) { SlMouse 'mouseMoved' ($from[0] + ($to[0] - $from[0]) * $i / 8) ($from[1] + ($to[1] - $from[1]) * $i / 8) 1 }; SlFrame; SlMouse 'mouseReleased' $to[0] $to[1] 0 }
# The centre of wide-monitor cell $slot (0-based) in the viewport, from the page's own cell geometry (cellRect, px and the stage).
function SlSlotAt($slot) { SlJs "(() => { const m = snap.monitors.find(q => q.role === 'wide'), g = work[selId].grids.wide, p = px(cellRect(m, g, $slot % g.c, Math.floor($slot / g.c), 1, 1)), sr = stage.getBoundingClientRect(); return [sr.left + parseFloat(p.left) + parseFloat(p.width) / 2, sr.top + parseFloat(p.top) + parseFloat(p.height) / 2]; })()" }
# The inspector's Fill Empty Cells switch: null when it is not drawn, else whether it is checked. -Click presses it first.
function SlSwitch([switch]$Click) {
  $flag = if ($Click) { 'true' } else { 'false' }
  SlJs "(() => { const i = [...document.querySelectorAll('input[role=switch]')].find(x => { const l = x.closest('label'); return !!l && l.textContent.includes('Fill Empty Cells'); }); if (!i) return null; if ($flag) i.click(); return i.checked; })()"
}
# The visible text of the badge (.stk) on window $id, or null when it is not drawn.
function SlBadgeText($id) { SlJs "(() => { const t = els.get($id), s = t && t.querySelector('.stk'); return s ? s.textContent.replace(/\s+/g, ' ').trim() : null; })()" }
# The window ids drawn in Windows That Stay Put, read from the page's chips.
function SlBayIds { @(("$(SlJs "[...document.querySelectorAll('#bgrps [data-bay]')].map(b => b.dataset.bay).join(',')")") -split ',' | ? { $_ } | % { [int]$_ }) }
# Call before the drop: keeps the engine's current answer, so the wait below can tell when a new one has replaced it, and
# records the page's uncaught errors from then on, so a red case names the exception that stopped the redraw.
function SlMarkEngine { [void](SlJs "(window.bfEngine = prevs[selId], window.bfErrs = [], addEventListener('error', e => window.bfErrs.push(String(e.message) + ' at ' + String((e.error && e.error.stack) || '').split('\n')[1].trim())), true)") }
# A passive wait, no action: the page polls until the engine's answer to the drop replaces the marked one (bounded by a count,
# a hang guard only), then two frames. It never calls preview() itself, since a settle would redraw the board and hide a stale screen.
# Returns fresh (an answer came back) and behind (the engine placed window $id behind).
function SlWaitBehind($id) {
  $r = SlJs "new Promise(res => { let n = 0; (function poll() { const fresh = prevs[selId] !== window.bfEngine; const p = fresh && prevs[selId].placed.find(q => q.id === $id); if (fresh || ++n > 1500) return requestAnimationFrame(() => requestAnimationFrame(() => res(JSON.stringify({ fresh: fresh, behind: !!(p && p.behind), errs: (window.bfErrs || []).slice(0, 3) })))); setTimeout(poll, 25); })(); })"
  if ($r) { $r | ConvertFrom-Json } else { [pscustomobject]@{ fresh = $false; behind = $false } }
}
# Window id to its cells (sorted, joined), for a placed list. Pass the same list shape from the page or the engine.
function SlCellMap($list) { $h = @{}; foreach ($p in @($list)) { $h["$($p.id)"] = ((@($p.slots) | Sort-Object) -join ',') }; $h }
# A JSON array from the page, as one array (SlGet hands a JSON array back wrapped, so @(SlGet ...) would nest it). Read its count with @().
function SlList($expr) { $s = SlJs ('JSON.stringify(' + $expr + ')'); if (-not $s) { return ,@() }; return ,($s | ConvertFrom-Json) }
# The handle of each direction, under .hdl: corners tl, tr, bl, br; edges n, s, w and ea (east).
$HandleSel = @{ tl = 'i.c.tl'; tr = 'i.c.tr'; bl = 'i.c.bl'; br = 'i.c.br'; n = 'i.e.n'; s = 'i.e.s'; w = 'i.e.w'; ea = 'i.e.ea' }
# The centre of a handle drawn on the selected tile, or null when it is not drawn.
function SlHandle($dir) {
  $sel = $HandleSel[$dir]
  SlGet "(() => { const h = document.querySelector('.hdl $sel'); if (!h) return null; const r = h.getBoundingClientRect(); return (r.width || r.height) ? { x: r.left + r.width / 2, y: r.top + r.height / 2 } : null; })()"
}
# Presses on a handle's centre and drags in its direction (dx and dy are -1, 0 or 1) by $cells cells (1.4 unless a case says).
# Makes no press when the handle is not drawn.
function SlHandleDrag($dir, $dx, $dy, $cells = 1.4) {
  $hp = SlHandle $dir; $tb = SlBox 1001
  if (-not $hp -or -not $tb) { return $false }
  SlDrag @([double]$hp.x, [double]$hp.y) @([double]($hp.x + $dx * $cells * $tb.w), [double]($hp.y + $dy * $cells * $tb.h))
  $true
}
# The eight hit areas of a tile, from its box (the mockup's geometry: corners 10 by 10, edge bands 7 px, outside the border).
function SlHandleBoxes($tb) {
  $cornerPx = 10; $bandPx = 7
  @{
    tl = @{ l = $tb.l - $cornerPx; t = $tb.t - $cornerPx; r = $tb.l + 1; b = $tb.t + 1 }
    tr = @{ l = $tb.r - 1; t = $tb.t - $cornerPx; r = $tb.r + $cornerPx; b = $tb.t + 1 }
    bl = @{ l = $tb.l - $cornerPx; t = $tb.b - 1; r = $tb.l + 1; b = $tb.b + $cornerPx }
    br = @{ l = $tb.r - 1; t = $tb.b - 1; r = $tb.r + $cornerPx; b = $tb.b + $cornerPx }
    n = @{ l = $tb.l + 1; t = $tb.t - $bandPx; r = $tb.r - 1; b = $tb.t }
    s = @{ l = $tb.l + 1; t = $tb.b; r = $tb.r - 1; b = $tb.b + $bandPx }
    w = @{ l = $tb.l - $bandPx; t = $tb.t + 1; r = $tb.l; b = $tb.b - 1 }
    e = @{ l = $tb.r; t = $tb.t + 1; r = $tb.r + $bandPx; b = $tb.b - 1 }
  }
}
# The handle hit areas that cover a control on the selected tile $id (lock, tag, badge, grip, Stay Put), as "handle over control".
# A tile that is not on the board is named, so the check cannot pass by reading nothing.
function SlClashes($id) {
  $b = SlHitBoxes $id
  if (-not $b -or -not $b.tile) { return @('no tile') }
  $ctl = @{ lock = $b.lock; tag = $b.tag; badge = $b.badge; grip = $b.grip; 'Stay Put' = $b.spt }
  $hb = SlHandleBoxes $b.tile
  @(foreach ($d in @($hb.Keys)) { foreach ($k in @($ctl.Keys)) { if (SlMeets $hb[$d] $ctl[$k]) { "$d over $k" } } })
}

# Scenes for the page cases (pins are JSON; each case wraps them in one scene, id sl). Windows are fixture ids by title.
$pinsCQ = SlPins '{"app":"claude","match":"Refactor","mon":"wide","slots":[0]}' '{"app":"chrome","match":"Quarterly","mon":"wide","slots":[1]}'
$pinsCQLock = SlPins '{"app":"claude","match":"Refactor","mon":"wide","slots":[0],"lock":true}' '{"app":"chrome","match":"Quarterly","mon":"wide","slots":[1]}'
$pinsResizeLock = SlPins '{"app":"claude","match":"Refactor","mon":"wide","slots":[0]}' '{"app":"chrome","match":"Quarterly","mon":"wide","slots":[1],"lock":true}'
$pinsSpan = SlPins '{"app":"chrome","match":"Quarterly","mon":"wide","slots":[0,1,5,6]}' '{"app":"WindowsTerminal","match":"tiler","mon":"wide","slots":[3]}'
$pinsFull = SlPins '{"app":"claude","match":"Refactor","mon":"wide","slots":[0]}' '{"app":"claude","match":"Pin parser","mon":"wide","slots":[1]}' '{"app":"claude","match":"Draft release","mon":"wide","slots":[2]}' '{"app":"chrome","match":"Pull request","mon":"wide","slots":[3]}' '{"app":"chrome","match":"Quarterly","mon":"wide","slots":[4]}' '{"app":"chrome","match":"quoted","mon":"wide","slots":[5]}' '{"app":"WindowsTerminal","match":"tiler","mon":"wide","slots":[6]}' '{"app":"WindowsTerminal","match":"docs watch","mon":"wide","slots":[7]}' '{"app":"explorer","match":"Projects","mon":"wide","slots":[8]}' '{"app":"explorer","match":"Downloads","mon":"wide","slots":[9]}'

$pinsOver = SlPins '{"app":"claude","match":"Refactor","mon":"wide","slots":[0]}' '{"app":"WindowsTerminal","match":"tiler","mon":"wide","slots":[3],"behind":[{"app":"claude","match":"Draft release"}]}'
$pinsSpanOver = SlPins '{"app":"chrome","match":"Quarterly","mon":"wide","slots":[0,1,5,6]}' '{"app":"WindowsTerminal","match":"tiler","mon":"wide","slots":[3],"behind":[{"app":"claude","match":"Draft release"}]}'
$pinsSpanArrow = SlPins '{"app":"chrome","match":"Quarterly","mon":"wide","slots":[0,1,5,6]}' '{"app":"WindowsTerminal","match":"tiler","mon":"wide","slots":[2],"behind":[{"app":"claude","match":"Draft release"}]}'
$pinsOneWin = SlPins '{"app":"claude","match":"Refactor","mon":"wide","slots":[0]}'
$pinsGridLock = SlPins '{"app":"chrome","match":"Quarterly","mon":"wide","slots":[4],"lock":true}'
$pinsGridFree = SlPins '{"app":"chrome","match":"Quarterly","mon":"wide","slots":[4]}'
# A front that is not open. Empty state: the front is the only pin. Full state: the fixture's ten pins, with the Refactor pin's front not open.
$pinsFrontGone = SlPins '{"app":"claude","match":"Nonexistent","mon":"wide","slots":[3],"behind":[{"app":"claude","match":"Draft release"}]}'
$pinsFullFrontGone = $pinsFull.Replace('{"app":"claude","match":"Refactor","mon":"wide","slots":[0]}', '{"app":"claude","match":"Nonexistent","mon":"wide","slots":[0],"behind":[{"app":"claude","match":"Refactor"}]}')
# A front that is not open, with a back window whose entry has no title match (the inspector then prints "Not open").
$pinsNoMatchGone = SlPins '{"app":"claude","match":"Nonexistent","mon":"wide","slots":[3],"behind":[{"app":"notepad"}]}'
# Growth: Refactor (slot 0) grows over Quarterly, which carries Draft release behind it. pinsGrowFree grows wide, over slot 1;
# pinsGrowFreeDown grows tall, over slot 5. Slots are 0-based: the first free cell is slot 2 for a wide grow, slot 1 for a tall one.
$pinsGrowFree = SlPins '{"app":"claude","match":"Refactor","mon":"wide","slots":[0]}' '{"app":"chrome","match":"Quarterly","mon":"wide","slots":[1],"behind":[{"app":"claude","match":"Draft release"}]}'
$pinsGrowFreeDown = SlPins '{"app":"claude","match":"Refactor","mon":"wide","slots":[0]}' '{"app":"chrome","match":"Quarterly","mon":"wide","slots":[5],"behind":[{"app":"claude","match":"Draft release"}]}'
# Full board: no free cell. Pin parser (slot 1) carries Draft release behind it; POWERPNT holds slot 2, so all ten slots are taken.
$pinsFullStack = $pinsFull.Replace('{"app":"claude","match":"Pin parser","mon":"wide","slots":[1]}', '{"app":"claude","match":"Pin parser","mon":"wide","slots":[1],"behind":[{"app":"claude","match":"Draft release"}]}').Replace('{"app":"claude","match":"Draft release","mon":"wide","slots":[2]}', '{"app":"POWERPNT","match":"Deck draft","mon":"wide","slots":[2]}')
# Narrow stacked tile (the badge-grip overlap debt): Refactor in slot 0 with two windows behind it, so its badge reads +2.
# Quarterly in slot 1 is the tile a state selects to leave the stack unselected.
$pinsBadge = SlPins '{"app":"claude","match":"Refactor","mon":"wide","slots":[0],"behind":[{"app":"claude","match":"Pin parser"},{"app":"claude","match":"Draft release"}]}' '{"app":"chrome","match":"Quarterly","mon":"wide","slots":[1]}'
# Ten windows behind the same front, so the badge reads +10 (and 9+ at 1024). They are fixture windows that no other pin here uses.
$pinsBadge10 = SlPins '{"app":"claude","match":"Refactor","mon":"wide","slots":[0],"behind":[{"app":"claude","match":"Pin parser"},{"app":"claude","match":"Draft release"},{"app":"chrome","match":"Pull request"},{"app":"chrome","match":"quoted"},{"app":"WindowsTerminal","match":"tiler"},{"app":"WindowsTerminal","match":"docs watch"},{"app":"explorer","match":"Projects"},{"app":"explorer","match":"Downloads"},{"app":"ms-teams","match":"Design sync"},{"app":"outlook","match":"Inbox"}]}' '{"app":"chrome","match":"Quarterly","mon":"wide","slots":[1]}'
# Board feedback scenes (page cases). Refactor, Pin parser and Draft release are claude; Quarterly is chrome.
$pinsNamed = SlPins '{"app":"claude","match":"Refactor","mon":"wide","slots":[0],"behind":[{"app":"chrome","match":"Quarterly"}]}'
$pinsKeyLeft = SlPins '{"app":"claude","match":"Refactor","mon":"wide","slots":[0],"behind":[{"app":"claude","match":"Draft release"}]}' '{"app":"chrome","match":"Quarterly","mon":"wide","slots":[1]}'
$pinsKeyUp = SlPins '{"app":"claude","match":"Refactor","mon":"wide","slots":[6]}'
$pinsKeySpan = SlPins '{"app":"chrome","match":"Quarterly","mon":"wide","slots":[0,1]}'
$pinsKeyColSpan = SlPins '{"app":"chrome","match":"Quarterly","mon":"wide","slots":[1,6]}'
# Layered strip: Refactor in slot 0 with Draft release behind it, and Quarterly alone in slot 1 (so a press can select Refactor first).
$pinsStrip = SlPins '{"app":"claude","match":"Refactor","mon":"wide","slots":[0],"behind":[{"app":"claude","match":"Draft release"}]}' '{"app":"chrome","match":"Quarterly","mon":"wide","slots":[1]}'
# Top and left handles against a lock. Free: no lock, the control. Lock: Quarterly locked, the one case.
$pinsTopFree = SlPins '{"app":"claude","match":"Refactor","mon":"wide","slots":[5,6,7]}'
$pinsTopLock = SlPins '{"app":"claude","match":"Refactor","mon":"wide","slots":[5,6,7]}' '{"app":"chrome","match":"Quarterly","mon":"wide","slots":[2],"lock":true}'
$pinsLeftFree = SlPins '{"app":"claude","match":"Refactor","mon":"wide","slots":[2,7]}'
$pinsLeftLock = SlPins '{"app":"claude","match":"Refactor","mon":"wide","slots":[2,7]}' '{"app":"chrome","match":"Quarterly","mon":"wide","slots":[6],"lock":true}'

# Engine: the open back window takes the front's cell as the new front, as a window behind a removed front takes its cell on the board.
$eGone = SlPlace (SlSceneJson $pinsFrontGone)
$eGoneBack = @($eGone.placed | ? { $_.id -eq 1003 })[0]
Check 'front gone, empty state: the open back window takes the front''s cell, as the new front' ([bool]$eGoneBack -and ($eGoneBack.slots -join ',') -eq '4' -and $eGoneBack.pin -eq 0 -and $eGoneBack.behind -ne $true) "back: $($eGoneBack | ConvertTo-Json -Compress)"
$eFull = SlPlace (SlSceneJson $pinsFullFrontGone)
$eFullBack = @($eFull.placed | ? { $_.id -eq 1001 })[0]
Check 'front gone, full state: the open back window takes the front''s cell, as the new front' ([bool]$eFullBack -and ($eFullBack.slots -join ',') -eq '1' -and $eFullBack.pin -eq 0 -and $eFullBack.behind -ne $true) "back: $($eFullBack | ConvertTo-Json -Compress)"

# Fill Empty Cells off (decisions/fill-controls.md), engine: off places only pins (locked or not, with their stacks), and zones place nothing.
$fillOff = ',"off":true'
$offPins = SlPins '{"app":"claude","match":"Refactor","mon":"wide","slots":[0],"lock":true,"behind":[{"app":"claude","match":"Draft release"}]}' '{"app":"chrome","match":"Quarterly","mon":"wide","slots":[1]}'
$offZone = ',"zones":[{"mon":"wide","slots":[5,6],"app":"WindowsTerminal"}]'
$fOff = SlDry (SlSceneJson $offPins '["*"]' $offZone $fillOff)
Check 'fill off: a dry run places no window the fill would place' (@($fOff.placed | ? { $_.pin -lt 0 }).Count -eq 0) (SlPl $fOff)
Check 'fill off: the pins, the locked one and its stack, are placed' (@($fOff.placed | ? { $_.pin -ge 0 }).Count -eq 3) (SlPl $fOff)
Check 'fill off: no zone places a window' (@($fOff.placed | ? { $_.zone -ge 0 }).Count -eq 0) (SlPl $fOff)
$fEmpty = SlDry (SlSceneJson '[]' '["*"]' '' $fillOff)
Check 'fill off, no pins: a dry run places nothing' (@($fEmpty.placed).Count -eq 0) (SlPl $fEmpty)
$fOn = SlDry (SlSceneJson $offPins '["*"]' $offZone)
Check 'control: fill on (no flag) still fills and zones, as today' (@($fOn.placed).Count -gt 3 -and @($fOn.placed | ? { $_.zone -ge 0 }).Count -ge 1) (SlPl $fOn)
$fFull = SlDry (SlSceneJson $pinsFull '["*"]' '' $fillOff)
Check 'guard: fill off on a full board places the ten pins, as today' (@($fFull.placed).Count -eq 10 -and @($fFull.placed | ? { $_.pin -lt 0 }).Count -eq 0) (SlPl $fFull)

# Fill Empty Cells off gives every unpinned window the reason "Fill is off" (decisions/fill-controls.md; board-feedback notes, item 5),
# not only the windows of the fill's apps. A window whose app has a pinned window is unpinned too, so it gets the reason as well.
# Three states: empty, pins in two apps (the other windows of those apps stay unpinned), and a full board. Scope first: the pins are
# placed and some open window is unpinned; then every open window that is not pinned has the reason.
$fxOpen = @((Get-Content -Raw -Encoding UTF8 -LiteralPath $fixture | ConvertFrom-Json).windows | ? { $_.x -gt -20000 } | % { [int64]$_.id })
$offStates = @(
  @('no pins', '[]', 0),
  @('pins in two apps', '[{"app":"WindowsTerminal","match":"docs watch","mon":"wide","slots":[9]},{"app":"explorer","match":"Downloads","mon":"wide","slots":[8]}]', 2),
  @('full board', $pinsFull, 10)
)
foreach ($offState in $offStates) {
  $fo = SlDry (SlSceneJson $offState[1] '["*"]' '' $fillOff)
  $pinned = @($fo.placed | ? { $_.pin -ge 0 } | % { [int64]$_.id })
  $unpinned = @($fxOpen | ? { $pinned -notcontains $_ })
  $noReason = @($unpinned | ? { $id = $_; -not @($fo.left | ? { $_.id -eq $id -and $_.why -eq 'fill is off' }).Count })
  Check "fill off, $($offState[0]), scope: the pins are placed, and some open window is unpinned" ($pinned.Count -eq $offState[2] -and $unpinned.Count -gt 0) "pinned: $($pinned -join ','); unpinned: $($unpinned -join ',')"
  Check "fill off, $($offState[0]): every unpinned window has the reason 'fill is off'" ($noReason.Count -eq 0) "no 'fill is off' reason for: $($noReason -join ', ')"
}

# Held layout (fill.held, decisions/fill-controls.md), engine. SlHeldFill sets the held layout by hand on a fill-off scene.
# SlSlotsOf gives a window's 1-based cells in a dry run, or 'none'. Each control is green on the head; each subject is the finding.
function SlHeldFill($held) { ',"off":true,"held":' + $held }
function SlSlotsOf($r, $id) { $p = @(@($r.placed) | ? { $_.id -eq $id })[0]; if ($p) { (@($p.slots) | Sort-Object) -join '+' } else { 'none' } }
$fxWins = @((Get-Content -Raw -Encoding UTF8 -LiteralPath $fixture | ConvertFrom-Json).windows)
# A held title that has changed: notepad has one window, so it matches by its app, as a pin does with no title text.
$hSame = SlDry (SlSceneJson '[]' '["*"]' '' (SlHeldFill '[{"app":"notepad","title":"todo.txt - Notepad","mon":"wide","slots":[0]}]'))
Check 'held, control: a held window whose title is unchanged is placed in its held cell' ((SlSlotsOf $hSame 1014) -eq '1') (SlPl $hSame)
$hOld = SlDry (SlSceneJson '[]' '["*"]' '' (SlHeldFill '[{"app":"notepad","title":"Old todo title - Notepad","mon":"wide","slots":[0]}]'))
Check 'held, scope: notepad has one open window, which is not titled as held' (@($fxWins | ? { $_.app -eq 'notepad' }).Count -eq 1 -and @($fxWins | ? { $_.app -eq 'notepad' -and $_.title -eq 'Old todo title - Notepad' }).Count -eq 0) "notepad windows: $(@($fxWins | ? { $_.app -eq 'notepad' }).Count)"
Check 'held: a window whose title changed keeps its hold, as a pin does for the one window of its app' ((SlSlotsOf $hOld 1014) -eq '1') "notepad 1014 cells: $(SlSlotsOf $hOld 1014)"
# A locked pin whose window is closed keeps its cell and its lock: no held window takes that cell.
$hClosedPin = SlPins '{"app":"closedapp","match":"","mon":"wide","slots":[0],"lock":true}'
$hOnPin = SlDry (SlSceneJson $hClosedPin '["*"]' '' (SlHeldFill '[{"app":"notepad","title":"todo.txt - Notepad","mon":"wide","slots":[0]}]'))
Check 'held, scope: the locked pin for a closed window is in the scene and is not placed' ([bool]@($hOnPin.missing | ? { $_.app -eq 'closedapp' }).Count) (SlPl $hOnPin)
Check 'held: no held window takes the cell of a locked pin whose window is closed' (-not @($hOnPin.placed | ? { @($_.slots) -contains 1 }).Count) "placed on slot 1: $(SlShort @($hOnPin.placed | ? { @($_.slots) -contains 1 }))"
$hFreeCell = SlDry (SlSceneJson $hClosedPin '["*"]' '' (SlHeldFill '[{"app":"notepad","title":"todo.txt - Notepad","mon":"wide","slots":[2]}]'))
Check 'held, control: beside the locked pin, a held window on a free cell is placed in it' ((SlSlotsOf $hFreeCell 1014) -eq '3') (SlPl $hFreeCell)
# A stale handle holds no window: the open window with the held title does not take its cell.
$hStale = SlDry (SlSceneJson '[]' '["*"]' '' (SlHeldFill '[{"id":9999,"app":"chrome","title":"Pull request 212 - Example","mon":"wide","slots":[0]}]'))
Check 'held, scope: no open window has handle 9999, and chrome 1005 has the held title' ((@($fxWins | ? { $_.id -eq 9999 }).Count -eq 0) -and (@($fxWins | ? { $_.id -eq 1005 -and $_.title -eq 'Pull request 212 - Example' }).Count -eq 1)) "windows: $($fxWins.Count)"
Check 'held: a stale handle leaves its cell empty, and no other window with its title takes the cell' (-not @($hStale.placed | ? { @($_.slots) -contains 1 }).Count) "placed on slot 1: $(SlShort @($hStale.placed | ? { @($_.slots) -contains 1 }))"
$hValid = SlDry (SlSceneJson '[]' '["*"]' '' (SlHeldFill '[{"id":1005,"app":"chrome","title":"Pull request 212 - Example","mon":"wide","slots":[0]}]'))
Check 'held, control: a held handle that is open places its window in the cell' ((SlSlotsOf $hValid 1005) -eq '1') (SlPl $hValid)
# Empty and full-size held layouts (P8): none holds nothing; ten held windows, one per cell, each keeps its own cell by its exact title.
$hNone = SlDry (SlSceneJson '[]' '["*"]' '' (SlHeldFill '[]'))
Check 'held, control: an empty held layout places no window' (@($hNone.placed).Count -eq 0) (SlPl $hNone)
$hFullRows = @(@(1001, 'claude', 'Refactor the grid solver'), @(1002, 'claude', 'Pin parser edge cases'), @(1003, 'claude', 'Draft release notes'), @(1005, 'chrome', 'Pull request 212 - Example'), @(1006, 'chrome', 'Quarterly roadmap - Example'), @(1008, 'WindowsTerminal', 'pwsh - tiler'), @(1009, 'WindowsTerminal', 'pwsh - docs watch'), @(1010, 'explorer', 'Projects'), @(1011, 'explorer', 'Downloads'), @(1012, 'ms-teams', 'Design sync | Microsoft Teams'))
$hFullJson = '[' + ((0..9 | % { $r = $hFullRows[$_]; '{"app":"' + $r[1] + '","title":"' + $r[2] + '","mon":"wide","slots":[' + $_ + ']}' }) -join ',') + ']'
$hFull = SlDry (SlSceneJson '[]' '["*"]' '' (SlHeldFill $hFullJson))
$hFullBad = @(0..9 | ? { (SlSlotsOf $hFull $hFullRows[$_][0]) -ne [string]($_ + 1) })
Check 'held, control, full board: ten held windows each keep their own cell' ($hFullBad.Count -eq 0 -and @($hFull.placed).Count -eq 10) "not in their cells: $(@($hFullBad | % { $hFullRows[$_][0] }) -join ',')"
# Nested titles (the held match, decisions/fill-controls.md): "Projects" and "Projects archive" are two windows of one app, and the
# archive window is further left, so a sort by position alone hands it to the entry "Projects". Each entry takes the window with its
# exact title first, then one whose title contains it. The fixture is the shared one plus the archive window, in the run folder.
$fxNestDoc = Get-Content -Raw -Encoding UTF8 -LiteralPath $fixture | ConvertFrom-Json
$fxNestDoc.windows = @($fxNestDoc.windows) + [pscustomobject]@{ id = 1018; app = 'explorer'; title = 'Projects archive'; x = 300; y = 200; w = 1000; h = 700 }
$fxNest = Join-Path $run 'fixture-nested.json'
[IO.File]::WriteAllText($fxNest, (ConvertTo-Json -Depth 10 -Compress $fxNestDoc), $utf8)
$nestPA = @($fxNestDoc.windows | ? { $_.title -eq 'Projects' })[0]; $nestPB = @($fxNestDoc.windows | ? { $_.title -eq 'Projects archive' })[0]
Check 'held, nested titles, scope: Projects and Projects archive are open explorer windows, the archive one further left' ([bool]($nestPA -and $nestPB -and $nestPB.app -eq 'explorer' -and $nestPA.app -eq 'explorer' -and $nestPB.x -lt $nestPA.x -and $nestPB.x -gt -20000)) "windows: $(SlShort @($nestPA, $nestPB))"
$hNest = SlDry (SlSceneJson '[]' '["*"]' '' (SlHeldFill '[{"app":"explorer","title":"Projects","mon":"wide","slots":[0]},{"app":"explorer","title":"Projects archive","mon":"wide","slots":[1]}]')) $fxNest
Check 'held, nested titles: the window titled Projects takes its own cell 1' ((SlSlotsOf $hNest 1010) -eq '1') "1010 cells: $(SlSlotsOf $hNest 1010); placed: $(SlPl $hNest)"
Check 'held, nested titles: the window titled Projects archive takes its own cell 2' ((SlSlotsOf $hNest 1018) -eq '2') "1018 cells: $(SlSlotsOf $hNest 1018); placed: $(SlPl $hNest)"
# An unlocked pin for a closed window keeps its cell as a locked one does. The scope is read first; then no held window takes the cell.
$hOpenPin = SlDry (SlSceneJson (SlPins '{"app":"closedapp","match":"","mon":"wide","slots":[0]}') '["*"]' '' (SlHeldFill '[{"app":"notepad","title":"todo.txt - Notepad","mon":"wide","slots":[0]}]'))
Check 'held, unlocked pin, scope: the pin for a closed window is in the scene and is not placed' ([bool]@($hOpenPin.missing | ? { $_.app -eq 'closedapp' }).Count) (SlPl $hOpenPin)
Check 'held, control: no held window takes the cell of an unlocked pin whose window is closed' (-not @($hOpenPin.placed | ? { @($_.slots) -contains 1 }).Count) "placed on slot 1: $(SlShort @($hOpenPin.placed | ? { @($_.slots) -contains 1 }))"

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
  # Placed rects, not boxes: the layered look shortens the front tile by its strip, so the boxes differ at rest.
  $a1 = SlPlacedRect 1001; $c1 = SlPlacedRect 1006; $s1 = SlGet 'work[selId]'
  Check 'stack: a Put Behind drop leaves both windows on the front window''s cell' (SlSameRect $a1 $c1) "claude $(SlShort $a1), chrome $(SlShort $c1)"
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
  $lk0 = SlBox 1001; $lk0p = SlPlacedRect 1001
  SlDrag (SlAt (SlBox 1006) 0.5 0.5) (SlAt $lk0 0.5 0.5)
  $lk1p = SlPlacedRect 1001; $s4 = SlGet 'work[selId]'
  Check 'lock: a drop on a locked tile does not move the locked tile' (SlSameRect $lk1p $lk0p) "before $(SlShort $lk0p), after $(SlShort $lk1p)"
  Check 'lock: a drop on a locked tile stacks the dropped window behind it, not a swap' ([bool]@($s4.pins | ? { "$($_.match)" -like '*Refactor*' } | % { @($_.behind) } | ? { $_.app -eq 'chrome' }).Count) (SlShort $s4.pins)

  SlCase (SlSceneJson $pinsCQLock)
  SlDrag (SlAt (SlBox 1006) 0.5 0.5) (SlAt (SlBox 1001) 0.5 0.5) -Hold
  Check 'scope: the drop label shows over the locked tile' (SlLabelShown) 'the drop label is hidden'
  $lbl = SlLabel
  Check 'lock: over a locked tile the drop label offers Behind' ("$lbl" -match 'Behind') "label: $lbl"
  Check 'lock: over a locked tile the drop label offers no Swap action' ("$lbl" -notmatch 'Swap with') "label: $lbl"
  Check 'lock: over a locked tile the drop label says Locked' ("$lbl" -match 'Locked') "label: $lbl"
  SlRelease (SlAt (SlBox 1001) 0.5 0.5)
  # Lock in a wide cell: the chip reads the approved copy, "Locked, so no Swap". At 1440 the 5-column cells are narrower than
  # 110 px, so this case widens the viewport, then sets it back for the cases after it.
  SlViewport 2560 1440
  SlCase (SlSceneJson $pinsCQLock)
  SlDrag (SlAt (SlBox 1006) 0.5 0.5) (SlAt (SlBox 1001) 0.5 0.5) -Hold
  Check 'scope: the drop label shows over the locked tile, at 110 px or wider' ([bool](SlJs "getComputedStyle(document.getElementById('drop')).display !== 'none' && document.getElementById('drop').offsetWidth >= 110")) "width: $(SlJs "document.getElementById('drop').offsetWidth")"
  $lw = SlLabel
  Check 'lock: over a locked tile in a wide cell the drop label reads "Locked, so no Swap"' ("$lw" -match 'Locked, so no Swap') "label: $lw"
  SlRelease (SlAt (SlBox 1001) 0.5 0.5)
  SlViewport 1440 900

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

  # Lock: Title contains never re-points a locked tile. Control: it re-points an unlocked one.
  SlCase (SlSceneJson $pinsCQ)
  SlClick (SlAt (SlBox 1001) 0.5 0.5)
  SlTitle 'Draft release'
  $tc = SlGet 'work[selId]'
  Check 'control: Title contains re-points an unlocked pin' ([bool](SlPin $tc 'Draft release')) "pins: $(SlShort $tc.pins)"
  SlCase (SlSceneJson $pinsCQLock)
  SlClick (SlAt (SlBox 1001) 0.5 0.5)
  SlTitle 'Draft release'
  $s12 = SlGet 'work[selId]'; $p12 = SlPin $s12 'Refactor'
  Check 'lock: Title contains never re-points a locked tile (its pin keeps its window and cell)' ([bool]$p12 -and $p12.lock -eq $true -and (SlCells $p12) -eq '0') "locked pin: $(SlShort $p12); pins: $(SlShort $s12.pins)"

  # Lock: Columns never cuts off a locked tile. Control: it shrinks the grid when no locked tile is in the way.
  SlCase (SlSceneJson $pinsGridFree)
  SlClick (SlAt (SlBox 1006) 0.5 0.5)
  SlFewer 'c'
  $gc = SlGet 'work[selId].grids.wide.c'
  Check 'control: Fewer Columns shrinks the grid when no locked tile is in the way' ($gc -eq 4) "columns: $gc"
  SlCase (SlSceneJson $pinsGridLock)
  SlClick (SlAt (SlBox 1006) 0.5 0.5)
  SlFewer 'c'
  $s13 = SlGet 'work[selId]'; $g13 = SlPin $s13 'Quarterly'
  Check 'lock: Fewer Columns never cuts off a locked tile (it keeps its cell)' ([bool]$g13 -and $g13.lock -eq $true -and (SlCells $g13) -eq '4') "locked pin: $(SlShort $g13); columns: $($s13.grids.wide.c)"

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

  # Growth by Shift+arrow and by the Width and Height steppers: a covered pinned window moves to the first free cell (rows
  # top to bottom), with the windows stacked behind it. With no free cell it goes to Windows That Stay Put, with its stack.
  # Each case's first check is the growth itself, so a key or stepper that never reaches the page cannot pass.
  SlCase (SlSceneJson $pinsGrowFree)
  SlClick (SlAt (SlBox 1001) 0.5 0.5)
  SlKey 1001 'ArrowRight' 39 8
  $g1 = SlGet 'work[selId]'; $g1r = SlPin $g1 'Refactor'; $g1q = SlPin $g1 'Quarterly'
  Check 'control: Shift+arrow grows a pinned window to a 2-column span' ([bool]$g1r -and (SlCells $g1r) -eq '0,1') "claude pin: $(SlShort $g1r)"
  Check 'resize: Shift+arrow growth moves the covered pinned window to the first free cell' ([bool]$g1q -and (SlCells $g1q) -eq '2') "chrome pin: $(SlShort $g1q)"
  Check 'resize: Shift+arrow growth moves the covered window''s stack with it' ([bool]$g1q -and (SlHasBehind $g1q 'Draft release')) "chrome pin: $(SlShort $g1q)"

  SlCase (SlSceneJson $pinsGrowFree)
  SlClick (SlAt (SlBox 1001) 0.5 0.5)
  $w2 = SlStep 'span' 'cs' '1'
  $w2s = SlGet 'work[selId]'; $w2r = SlPin $w2s 'Refactor'; $w2q = SlPin $w2s 'Quarterly'
  Check 'control: the Width stepper grows a pinned window to a 2-column span' ($w2 -eq 'pressed' -and [bool]$w2r -and (SlCells $w2r) -eq '0,1') "stepper: $w2; claude pin: $(SlShort $w2r)"
  Check 'resize: the Width stepper moves the covered pinned window to the first free cell' ([bool]$w2q -and (SlCells $w2q) -eq '2') "stepper: $w2; chrome pin: $(SlShort $w2q)"
  Check 'resize: the Width stepper moves the covered window''s stack with it' ([bool]$w2q -and (SlHasBehind $w2q 'Draft release')) "chrome pin: $(SlShort $w2q)"

  SlCase (SlSceneJson $pinsGrowFreeDown)
  SlClick (SlAt (SlBox 1001) 0.5 0.5)
  $h2 = SlStep 'span' 'rs' '1'
  $h2s = SlGet 'work[selId]'; $h2r = SlPin $h2s 'Refactor'; $h2q = SlPin $h2s 'Quarterly'
  Check 'control: the Height stepper grows a pinned window to a 2-row span' ($h2 -eq 'pressed' -and [bool]$h2r -and (SlCells $h2r) -eq '0,5') "stepper: $h2; claude pin: $(SlShort $h2r)"
  Check 'resize: the Height stepper moves the covered pinned window to the first free cell' ([bool]$h2q -and (SlCells $h2q) -eq '1') "stepper: $h2; chrome pin: $(SlShort $h2q)"
  Check 'resize: the Height stepper moves the covered window''s stack with it' ([bool]$h2q -and (SlHasBehind $h2q 'Draft release')) "chrome pin: $(SlShort $h2q)"

  SlCase (SlSceneJson $pinsFullStack)
  SlClick (SlAt (SlBox 1001) 0.5 0.5)
  SlKey 1001 'ArrowRight' 39 8
  $b1 = SlGet 'work[selId]'; $b1r = SlPin $b1 'Refactor'
  Check 'control: Shift+arrow grows a pinned window to a 2-column span on a full board' ([bool]$b1r -and (SlCells $b1r) -eq '0,1') "claude pin: $(SlShort $b1r)"
  Check 'resize: with no free cell, Shift+arrow growth sends the covered pinned window to Windows That Stay Put' (SlHasBay $b1 'Pin parser') "bay: $(SlShort $b1.bay)"
  Check 'resize: with no free cell, Shift+arrow growth sends its stack to Windows That Stay Put' (SlHasBay $b1 'Draft release') "bay: $(SlShort $b1.bay)"

  SlCase (SlSceneJson $pinsFullStack)
  SlClick (SlAt (SlBox 1001) 0.5 0.5)
  $w3 = SlStep 'span' 'cs' '1'
  $w3s = SlGet 'work[selId]'; $w3r = SlPin $w3s 'Refactor'
  Check 'control: the Width stepper grows a pinned window to a 2-column span on a full board' ($w3 -eq 'pressed' -and [bool]$w3r -and (SlCells $w3r) -eq '0,1') "stepper: $w3; claude pin: $(SlShort $w3r)"
  Check 'resize: with no free cell, the Width stepper sends the covered pinned window to Windows That Stay Put' (SlHasBay $w3s 'Pin parser') "bay: $(SlShort $w3s.bay)"
  Check 'resize: with no free cell, the Width stepper sends its stack to Windows That Stay Put' (SlHasBay $w3s 'Draft release') "bay: $(SlShort $w3s.bay)"

  SlCase (SlSceneJson $pinsFullStack)
  SlClick (SlAt (SlBox 1001) 0.5 0.5)
  $h3 = SlStep 'span' 'rs' '1'
  $h3s = SlGet 'work[selId]'; $h3r = SlPin $h3s 'Refactor'
  Check 'control: the Height stepper grows a pinned window to a 2-row span on a full board' ($h3 -eq 'pressed' -and [bool]$h3r -and (SlCells $h3r) -eq '0,5') "stepper: $h3; claude pin: $(SlShort $h3r)"
  Check 'resize: with no free cell, the Height stepper sends the covered pinned window to Windows That Stay Put' (SlHasBay $h3s 'quoted') "bay: $(SlShort $h3s.bay)"

  # Guard, not a new claim: Shift+arrow growth toward a locked tile stops. This passes on the old code (pinWin checks lockedHit).
  # The status line names the refusal, so a key that never reached the page cannot pass it; the Shift control above covers the key.
  SlCase (SlSceneJson $pinsResizeLock)
  SlClick (SlAt (SlBox 1001) 0.5 0.5)
  SlKey 1001 'ArrowRight' 39 8
  $lg = SlGet 'work[selId]'; $lgq = SlPin $lg 'Quarterly'; $lgr = SlPin $lg 'Refactor'
  $lgmsg = SlJs "document.getElementById('msg').textContent"
  Check 'guard: Shift+arrow growth toward a locked tile is refused, and says so' ("$lgmsg" -match 'locked tile is in the way') "status: $lgmsg"
  Check 'guard: Shift+arrow growth toward a locked tile leaves the locked tile in its cell' ([bool]$lgq -and $lgq.lock -eq $true -and (SlCells $lgq) -eq '1') "locked pin: $(SlShort $lgq)"
  Check 'guard: Shift+arrow growth toward a locked tile does not grow the window onto it' ([bool]$lgr -and (SlCells $lgr) -eq '0') "claude pin: $(SlShort $lgr)"

  # A back window promoted because its front is not open is the front now (tile.ps1 promotes the first open back window).
  # Control: the promoted window is the front of pin 0 on the board. Red: the inspector's Behind This Window still lists it.
  SlCase (SlSceneJson $pinsFrontGone)
  SlClick (SlAt (SlBox 1003) 0.5 0.5)
  $pe = SlPlacedOf 1003
  Check 'promoted, empty state: the open back window is the front of pin 0 (control)' ([bool]$pe -and $pe.pin -eq 0 -and -not $pe.behind) "placed: $(SlShort $pe)"
  $pet = SlBehindText
  Check 'promoted, empty state: Behind This Window does not list the promoted window' ("$pet" -notlike '*Draft release*') "Behind This Window: $pet"

  SlCase (SlSceneJson $pinsFullFrontGone)
  SlClick (SlAt (SlBox 1001) 0.5 0.5)
  $pf = SlPlacedOf 1001
  Check 'promoted, full state: the open back window is the front of pin 0 (control)' ([bool]$pf -and $pf.pin -eq 0 -and -not $pf.behind) "placed: $(SlShort $pf)"
  $pft = SlBehindText
  Check 'promoted, full state: Behind This Window does not list the promoted window' ("$pft" -notlike '*Refactor*') "Behind This Window: $pft"

  SlCase (SlSceneJson $pinsNoMatchGone)
  SlClick (SlAt (SlBox 1014) 0.5 0.5)
  $pn = SlPlacedOf 1014
  Check 'promoted, no title match: the open back window is the front of pin 0 (control)' ([bool]$pn -and $pn.pin -eq 0 -and -not $pn.behind) "placed: $(SlShort $pn)"
  $pnt = SlBehindText
  Check 'promoted, no title match: Behind This Window does not read "Not open" for the promoted window' ("$pnt" -notlike '*Not open*') "Behind This Window: $pnt"

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

  # Spanned window over a taken 1x1 cell: the split, never Place here, and the occupant keeps its pin and its stack.
  # Control: a one-cell window over the same cell reads the split, as today.
  SlCase (SlSceneJson $pinsOver)
  SlDrag (SlAt (SlBox 1001) 0.5 0.5) (SlAt (SlBox 1008) 0.5 0.5) -Hold
  $lc = SlLabel
  Check 'control: a one-cell window over a taken cell reads Swap and Behind (as today)' (("$lc" -match 'Swap') -and ("$lc" -match 'Behind')) "label: $lc"
  SlRelease (SlAt (SlBox 1008) 0.5 0.5)

  SlCase (SlSceneJson $pinsSpanOver)
  SlDrag (SlAt (SlBox 1006) 0.25 0.25) (SlAt (SlBox 1008) 0.5 0.5) -Hold
  Check 'scope: the drop label shows over the taken cell of a spanned drag' (SlLabelShown) 'the drop label is hidden'
  $l1 = SlLabel
  Check 'split: a spanned window over a taken 1x1 cell reads Swap and Behind' (("$l1" -match 'Swap') -and ("$l1" -match 'Behind')) "label: $l1"
  SlRelease (SlAt (SlBox 1008) 0.5 0.5)

  SlCase (SlSceneJson $pinsSpanOver)
  SlDrag (SlAt (SlBox 1006) 0.25 0.25) (SlAt (SlBox 1008) 0.5 0.85)
  $s14 = SlGet 'work[selId]'; $t14 = SlPin $s14 'tiler'
  Check 'nothing dropped: a Put Behind drop on a taken cell keeps the occupant''s pin' ([bool]$t14) "pins: $(SlShort $s14.pins)"
  Check 'nothing dropped: a Put Behind drop on a taken cell keeps the occupant''s stack' ([bool]$t14 -and (SlHasBehind $t14 'Draft release')) "occupant pin: $(SlShort $t14)"
  Check 'split: a Put Behind drop puts the spanned window behind the occupant' ([bool]$t14 -and (SlHasBehind $t14 'Quarterly')) "occupant pin: $(SlShort $t14)"

  SlCase (SlSceneJson $pinsSpanOver)
  SlDrag (SlAt (SlBox 1006) 0.25 0.25) (SlAt (SlBox 1008) 0.5 0.35)
  $s15 = SlGet 'work[selId]'; $t15 = SlPin $s15 'tiler'
  Check 'nothing dropped: a swap onto a taken cell keeps the occupant''s pin' ([bool]$t15) "pins: $(SlShort $s15.pins)"
  Check 'nothing dropped: a swap onto a taken cell keeps the occupant''s stack' ([bool]$t15 -and (SlHasBehind $t15 'Draft release')) "occupant pin: $(SlShort $t15)"

  # Arrow keys into a taken cell take the same path: the occupant must survive. Control: an arrow key moves a one-cell window into an empty cell.
  SlCase (SlSceneJson $pinsOneWin)
  SlClick (SlAt (SlBox 1001) 0.5 0.5)
  SlKey 1001 'ArrowRight' 39
  $s16 = SlGet 'work[selId]'; $r16 = SlPin $s16 'Refactor'
  Check 'control: an arrow key moves a one-cell window into an empty cell (as today)' ([bool]$r16 -and (SlCells $r16) -eq '1') "pin: $(SlShort $r16)"
  SlCase (SlSceneJson $pinsSpanArrow)
  SlClick (SlAt (SlBox 1006) 0.5 0.5)
  SlKey 1006 'ArrowRight' 39
  $s17 = SlGet 'work[selId]'; $t17 = SlPin $s17 'tiler'
  Check 'nothing dropped: an arrow key into a taken cell keeps the occupant''s pin' ([bool]$t17) "pins: $(SlShort $s17.pins)"
  Check 'nothing dropped: an arrow key into a taken cell keeps the occupant''s stack' ([bool]$t17 -and (SlHasBehind $t17 'Draft release')) "occupant pin: $(SlShort $t17)"
  # Badge and grip (the badge-grip overlap debt): a narrow stacked tile at 1024, selected and not. The same at 1440 is a control.
  SlBadgeState 1024 768 $true
  SlBadgeState 1024 768 $false
  SlBadgeState 1440 900 $true
  SlBadgeState 1440 900 $false
  # Ten behind: the same reads, with the text cap at 1024 and the +10 control at 1440.
  SlBadgeState 1024 768 $true $pinsBadge10 10
  SlBadgeState 1024 768 $false $pinsBadge10 10
  SlBadgeState 1440 900 $true $pinsBadge10 10
  SlBadgeState 1440 900 $false $pinsBadge10 10

  # ---------- Board feedback (decisions/stack-and-lock.md, decisions/fill-controls.md, docs/design/mockups/board-feedback-notes.md) ----------
  # Drop Note. The control comes first: the drop stacks, and the header Undo restores the scene after it, so the scene
  # comparison holds on head before the note's own Undo is judged.
  SlCase (SlSceneJson $pinsCQ)
  [void](SlJs "(window.bfPre = $SceneNorm, true)")
  SlDropNoSettle (SlAt (SlBox 1006) 0.5 0.5) (SlAt (SlBox 1001) 0.5 0.85)
  $dStack = SlGet 'work[selId]'; $dBehind = @($dStack.pins | ? { "$($_.match)" -like '*Refactor*' } | % { @($_.behind) } | ? { $_.app -eq 'chrome' })
  Check 'control: a Put Behind drop still stacks the dropped window behind (as today)' ($dBehind.Count -gt 0) (SlShort $dStack.pins)
  SlSettle
  $hUndo = SlJs "(() => { const b = [...document.querySelectorAll('button')].find(x => x.textContent.trim() === 'Undo' && !x.closest('.dnote')); if (!b) return false; b.click(); return true; })()"
  SlSettle
  $hBack = SlJs "($SceneNorm) === window.bfPre"
  Check 'control: the header Undo restores the scene after the same drop, so the comparison holds' ([bool]$hUndo -and [bool]$hBack) "header Undo pressed: $hUndo; scene restored: $hBack"

  SlCase (SlSceneJson $pinsCQ)
  [void](SlJs "(window.bfPre = $SceneNorm, true)")
  SlDropNoSettle (SlAt (SlBox 1006) 0.5 0.5) (SlAt (SlBox 1001) 0.5 0.85)
  $dNote = SlNoteText
  Check 'drop note: after a Put Behind drop the tile shows a note naming both apps' ("$dNote" -like '*Chrome is behind Claude*') "note: $dNote"
  # A real press on the note's Undo, pressed and released as a mouse does. A JS click skips the pointer path, so it proves nothing here.
  SlSettle
  $dBtn = SlGet "(() => { const b = document.querySelector('.dnote button'); if (!b) return null; const r = b.getBoundingClientRect(); return { l: r.left, t: r.top, w: r.width, h: r.height }; })()"
  if ($dBtn) { SlClick (SlAt $dBtn 0.5 0.5) }
  SlSettle
  $dBack = SlJs "($SceneNorm) === window.bfPre"
  Check 'drop note: a real press on its Undo restores the scene from before the drop' ([bool]$dBtn -and [bool]$dBack) "note Undo button: $(SlFmt $dBtn); scene restored: $dBack"

  # Put Behind from Windows That Stay Put, with a real mouse drag and no other action (owner report, 2026-11-12 09:59 CST).
  # The drop's engine answer is awaited passively (SlWaitBehind), then the screen is read: the window must be gone from the
  # list, shown under Behind This Window, and drawn as a tile and a badge on the front, at once.
  SlViewport 1440 900; SlCase (SlSceneJson $pinsCQ '[]' ',"bay":[{"app":"chrome","title":"Pull request 212 - Example"}]')
  $bayPre = SlBayIds
  Check 'put behind, scope: before the drop, Windows That Stay Put lists the chrome window' ($bayPre -contains 1005) "bay ids: $($bayPre -join ',')"
  $chipAt = SlGet "(() => { const e = [...document.querySelectorAll('#bgrps [data-bay]')].find(b => b.dataset.bay === '1005'); if (!e) return null; const r = e.getBoundingClientRect(); return { l: r.left, t: r.top, w: r.width, h: r.height }; })()"
  SlMarkEngine
  if ($chipAt -and (SlBox 1001)) { SlDropNoSettle (SlAt $chipAt 0.5 0.5) (SlAt (SlBox 1001) 0.5 0.85) }
  $landed = SlWaitBehind 1005
  $bsDrop = SlGet 'work[selId]'
  Check 'put behind, control: the drop asks the engine for a new answer, with no page error' ([bool]$landed.fresh) "no new answer from the engine after the drop; page errors: $(SlShort $landed.errs)"
  Check 'put behind, control: the engine places the dropped window behind Refactor' ([bool]$landed.behind) "placed 1005 behind: $($landed.behind)"
  Check 'put behind, control: the scene stacks the window behind Refactor and drops its bay entry' ([bool]((SlHasBehind (SlPin $bsDrop 'Refactor') 'Pull request') -and -not (SlHasBay $bsDrop 'Pull request'))) "pins: $(SlShort $bsDrop.pins), bay: $(SlShort $bsDrop.bay)"
  $bayPost = SlBayIds
  Check 'put behind, no other action: the window is not listed in Windows That Stay Put' (-not ($bayPost -contains 1005)) "bay ids: $($bayPost -join ',')"
  $bsPost = SlBehindText
  Check 'put behind, no other action: Behind This Window lists the window' ("$bsPost" -like '*Pull request*') "Behind This Window: $bsPost"
  $tilePost = SlGet "(() => { const e = els.get(1005); return e ? { hidden: e.hidden, behind: e.classList.contains('behind') } : null; })()"
  $rect1005 = SlPlacedRect 1005; $rect1001 = SlPlacedRect 1001
  Check 'put behind, no other action: the window is a tile behind the front, on the front''s rect' ([bool]($tilePost -and -not $tilePost.hidden -and $tilePost.behind -and (SlSameRect $rect1005 $rect1001))) "tile: $(SlShort $tilePost), placed 1005: $(SlShort $rect1005), placed 1001: $(SlShort $rect1001)"
  $badgePost = SlBadgeText 1001
  $stackedPost = SlGet "!!els.get(1001) && els.get(1001).classList.contains('stacked')"
  Check 'put behind, no other action: the front badge names the window behind at once' ([bool]($stackedPost -and "$badgePost" -like '*Chrome*')) "stacked: $stackedPost, badge: $badgePost"

  # Flash over the lock. A Put Behind drop flashes the front tile's peek strip for 1.5 s, and the strip (z5) lies over the
  # lock's top edge. The press follows the drop at once, inside the flash (SlDropNoSettle, no settle between). The strip is
  # found by a bounded poll in the page; the press is then a real mouse press on the lock's top 2 px, which the strip covers at rest
  # (the strip ends 2 px into the lock). The drop slides the tile's top for .22 s, so the probe reads the lock once that slide has
  # ended, where it rests: a point read mid-slide, or on the strip's lower edge, misses the lock.
  SlCase (SlSceneJson $pinsCQLock)
  SlDropNoSettle (SlAt (SlBox 1006) 0.5 0.5) (SlAt (SlBox 1001) 0.5 0.85)
  $fl = SlJs "new Promise(res => { let n = 0; (function poll() { const t = els.get(1001), k = t && t.querySelector('.lk'), p = document.querySelector('.peek.flash'); if (!p && ++n < 120) return requestAnimationFrame(poll); if (!k || !p) return res(null); Promise.all(t.getAnimations().map(a => a.finished.catch(() => null))).then(() => { const r = k.getBoundingClientRect(); const x = r.left + r.width / 2, y = r.top + 1; const e = document.elementFromPoint(x, y); res({ x: x, y: y, covered: !!(e && e.closest('.peek.flash')) }); }); })(); })"
  Check 'lock top edge, flash: scope, the flash strip is drawn over the lock''s top edge' ([bool]($fl -and $fl.covered)) "flash probe: $(SlShort $fl)"
  $flPre = SlGet 'work[selId]'; $flPinPre = SlPin $flPre 'Refactor'
  Check 'lock top edge, flash: scope, the locked front window is stacked over the dropped one' ([bool]$flPinPre -and $flPinPre.lock -eq $true -and (SlHasBehind $flPinPre 'Quarterly')) "pin before the press: $(SlShort $flPinPre)"
  if ($fl) { SlClick @([double]$fl.x, [double]$fl.y) }
  $flPost = SlGet 'work[selId]'; $flPinPost = SlPin $flPost 'Refactor'
  Check 'lock top edge, flash: a real press on the lock''s top edge during the flash toggles the lock off' ([bool]$flPinPost -and -not $flPinPost.lock) "pin after the press: $(SlShort $flPinPost)"

  SlCase (SlSceneJson $pinsCQLock)
  $lkc = SlGet "(() => { const k = els.get(1001) && els.get(1001).querySelector('.lk'); if (!k) return null; const r = k.getBoundingClientRect(); return { x: r.left + r.width / 2, y: r.top + 2 }; })()"
  if ($lkc) { SlClick @([double]$lkc.x, [double]$lkc.y) }
  $lcPost = SlGet 'work[selId]'; $lcPin = SlPin $lcPost 'Refactor'
  Check 'control: a real press on the lock''s top edge with no flash toggles the lock off (as today)' ([bool]$lcPin -and -not $lcPin.lock) "pin after the press: $(SlShort $lcPin)"

  # Named Badge. Scope first: the front tile is stacked (and narrow at 1024). The badge text is read from the visible content.
  SlViewport 1440 900; SlCase (SlSceneJson $pinsNamed)
  Check 'named badge, 1440: Refactor is stacked (scope)' ([bool](SlGet "els.get(1001).classList.contains('stacked')")) 'Refactor is not stacked'
  $nb14 = SlBadgeText 1001
  Check 'named badge, 1440: the badge text names the window behind (Chrome)' ("$nb14" -like '*Chrome*') "badge text: $nb14"
  SlViewport 1024 768; SlCase (SlSceneJson $pinsNamed)
  Check 'named badge, 1024: Refactor is a narrow stacked tile (scope)' ([bool](SlGet "els.get(1001).classList.contains('narrow') && els.get(1001).classList.contains('stacked')")) 'Refactor is not a narrow stacked tile'
  $nb10 = SlBadgeText 1001
  Check 'named badge, 1024: the narrow badge shows the back app''s initial (C)' ("$nb10" -eq 'C') "badge text: $nb10"
  Check 'guard: the narrow badge does not name the window behind' ("$nb10" -notlike '*Chrome*') "badge text: $nb10"

  # Layered look. A stacked tile carries the layer (.peeked, with a .peek strip that names the back app); the 3px edge is gone.
  foreach ($vw in @(@(1440, 900), @(1024, 768))) {
    $vwTag = "$($vw[0])"
    SlViewport $vw[0] $vw[1]; SlCase (SlSceneJson $pinsNamed)
    Check "layered, ${vwTag}: Refactor is stacked (scope)" ([bool](SlGet "els.get(1001).classList.contains('stacked')")) 'Refactor is not stacked'
    Check "layered, ${vwTag}: the stacked tile is marked peeked" ([bool](SlGet "els.get(1001).classList.contains('peeked')")) 'Refactor has no peeked class'
    $peekText = SlJs "[...document.querySelectorAll('.peek')].map(p => p.textContent.replace(/\s+/g, ' ').trim()).join('|')"
    Check "layered, ${vwTag}: a .peek strip names the back app (Chrome)" ("$peekText" -like '*Chrome*') "peek strips: $peekText"
    Check "layered, ${vwTag}: the 3px stack edge is gone" ([bool](SlGet "document.querySelectorAll('.stkedge').length === 0")) 'a .stkedge is still drawn'
  }

  # Layered strip: the strip above a stacked tile is the front tile's. A real press there selects the front tile, and a drag
  # from it moves the front tile. Control: the same drag from the tile body moves it, as today.
  SlCase (SlSceneJson $pinsStrip)
  $stripBox = SlGet "(() => { const p = document.querySelector('.peek:not([hidden])'); if (!p) return null; const r = p.getBoundingClientRect(); return { l: r.left, t: r.top, w: r.width, h: r.height }; })()"
  Check 'strip: the front tile has its strip drawn above it (scope)' ([bool]$stripBox -and [bool](SlGet "els.get(1001).classList.contains('peeked')")) "strip: $(SlFmt $stripBox)"
  $selBefore = SlGet "els.get(1001).classList.contains('sel')"
  Check 'strip: the front tile is not selected before the press (scope)' ($selBefore -eq $false) "selected before: $selBefore"
  SlClick @([double]($stripBox.l + $stripBox.w * 0.5), [double]($stripBox.t + 5))
  $selAfter = SlGet "els.get(1001).classList.contains('sel')"
  Check 'strip: a real press in the strip selects the front tile' ($selAfter -eq $true) "selected after the press: $selAfter"

  SlCase (SlSceneJson $pinsStrip)
  $rbC = SlBox 1001; $qbC = SlBox 1006
  $pitchC = ($qbC.l + $qbC.w / 2) - ($rbC.l + $rbC.w / 2)
  SlDrag (SlAt $rbC 0.5 0.5) @([double]($rbC.l + $rbC.w / 2 + 3 * $pitchC), [double]($rbC.t + $rbC.h / 2))
  $ctlS = SlGet 'work[selId]'; $ctlR = SlPin $ctlS 'Refactor'
  Check 'control: a drag from the front tile body moves it to the cell under the pointer (as today)' ([bool]$ctlR -and (SlCells $ctlR) -eq '3') "claude pin: $(SlShort $ctlR)"

  SlCase (SlSceneJson $pinsStrip)
  $rbS = SlBox 1001; $qbS = SlBox 1006
  $pitchS = ($qbS.l + $qbS.w / 2) - ($rbS.l + $rbS.w / 2)
  $skS = SlGet "(() => { const p = document.querySelector('.peek:not([hidden])'); if (!p) return null; const r = p.getBoundingClientRect(); return { l: r.left, t: r.top, w: r.width, h: r.height }; })()"
  SlDrag @([double]($skS.l + $skS.w * 0.5), [double]($skS.t + 5)) @([double]($rbS.l + $rbS.w / 2 + 3 * $pitchS), [double]($rbS.t + $rbS.h / 2))
  $stS = SlGet 'work[selId]'; $stR = SlPin $stS 'Refactor'
  Check 'strip: a real drag from the strip moves the front tile to the cell under the pointer' ([bool]$stR -and (SlCells $stR) -eq '3') "claude pin: $(SlShort $stR)"

  # Handles on every edge. Each case: the front tile is selected (scope), the handle is drawn (its own check), then the
  # drag resizes by whole cells. No press is made when the handle is missing.
  foreach ($vw in @(@(1440, 900), @(1024, 768))) {
    $vwTag = "$($vw[0])"
    SlViewport $vw[0] $vw[1]; SlCase (SlSceneJson $pinsBadge)
    SlClick (SlAt (SlBox 1001) 0.5 0.5)
    Check "edge, ${vwTag}: Refactor is selected and stacked (scope)" ([bool](SlGet "els.get(1001).classList.contains('sel') && els.get(1001).classList.contains('stacked')")) 'Refactor is not selected and stacked'
    $hn = SlGet "document.querySelectorAll('.hdl i').length"
    Check "edge, ${vwTag}: the eight handles are drawn on the selected tile" ($hn -eq 8) "handles drawn: $hn"
    $cl = SlClashes 1001
    Check "edge, ${vwTag}: no handle hit area covers the lock, tag, badge, grip or Stay Put" ($cl.Count -eq 0 -and $hn -eq 8) "clashes: $($cl -join ', ')"
    # The tag (the tile's b) is hidden on a narrow stacked selected tile, so it is read only at 1440.
    $cb = SlHitBoxes 1001; $tagShown = ($vw[0] -eq 1440)
    Check "control, ${vwTag}: the lock, badge, grip and Stay Put are read on the selected tile" ([bool]($cb.lock -and $cb.badge -and $cb.grip -and $cb.spt -and ((-not $tagShown) -or $cb.tag))) "lock $(SlHit $cb.lock), tag $(SlHit $cb.tag), badge $(SlHit $cb.badge), grip $(SlHit $cb.grip), Stay Put $(SlHit $cb.spt)"
  }
  SlViewport 1440 900
  $handleCases = @(
    @{ dir = 'ea'; name = 'east'; dx = 1; dy = 0; start = 0; want = '0,1' },
    @{ dir = 'w'; name = 'west'; dx = -1; dy = 0; start = 1; want = '0,1' },
    @{ dir = 'n'; name = 'north'; dx = 0; dy = -1; start = 6; want = '1,6' },
    @{ dir = 's'; name = 'south'; dx = 0; dy = 1; start = 0; want = '0,5' },
    @{ dir = 'br'; name = 'south-east'; dx = 1; dy = 1; start = 0; want = '0,1,5,6' },
    @{ dir = 'bl'; name = 'south-west'; dx = -1; dy = 1; start = 1; want = '0,1,5,6' },
    @{ dir = 'tr'; name = 'north-east'; dx = 1; dy = -1; start = 5; want = '0,1,5,6' },
    @{ dir = 'tl'; name = 'north-west'; dx = -1; dy = -1; start = 6; want = '0,1,5,6' }
  )
  foreach ($hc in $handleCases) {
    SlCase (SlSceneJson (SlPins ('{"app":"claude","match":"Refactor","mon":"wide","slots":[' + $hc.start + ']}')))
    SlClick (SlAt (SlBox 1001) 0.5 0.5)
    Check "edge: the $($hc.name) handle is drawn on the selected tile" ([bool](SlHandle $hc.dir)) "no $($hc.dir) handle"
    [void](SlHandleDrag $hc.dir $hc.dx $hc.dy)
    $hp = SlPin (SlGet 'work[selId]') 'Refactor'
    Check "edge: the $($hc.name) handle resizes the tile by whole cells, to $($hc.want)" ([bool]$hp -and (SlCells $hp) -eq $hc.want) "claude pin: $(SlShort $hp)"
  }
  # East over a covered window: the window in the way moves to the first free cell, with the span, in one edit.
  SlCase (SlSceneJson $pinsCQ)
  SlClick (SlAt (SlBox 1001) 0.5 0.5)
  [void](SlHandleDrag 'ea' 1 0)
  $ew = SlGet 'work[selId]'; $ewr = SlPin $ew 'Refactor'; $ewq = SlPin $ew 'Quarterly'
  Check 'edge: the east handle moves a covered pinned window to the first free cell' ([bool]$ewr -and (SlCells $ewr) -eq '0,1' -and [bool]$ewq -and (SlCells $ewq) -eq '2') "claude: $(SlShort $ewr); chrome: $(SlShort $ewq)"
  # A lock stops the east handle, as it stops the corner grip. The first check is the handle; the two after it are guards.
  SlCase (SlSceneJson $pinsResizeLock)
  SlClick (SlAt (SlBox 1001) 0.5 0.5)
  Check 'edge: the east handle is drawn on a tile next to a locked one' ([bool](SlHandle 'ea')) 'no ea handle'
  [void](SlHandleDrag 'ea' 1 0)
  $lsc = SlGet 'work[selId]'; $lr = SlPin $lsc 'Refactor'; $lq = SlPin $lsc 'Quarterly'
  Check 'guard: a locked tile stops the east handle, so the tile stays one cell' ([bool]$lr -and (SlCells $lr) -eq '0') "claude pin: $(SlShort $lr)"
  Check 'guard: a locked tile stops the east handle, and keeps its cell and lock' ([bool]$lq -and $lq.lock -eq $true -and (SlCells $lq) -eq '1') "chrome pin: $(SlShort $lq)"

  # A top or left handle moves only its own edge. Toward a lock, the tile stops short of it and keeps the other dimension:
  # the north handle keeps a 3-cell span's width, and the west handle keeps a 2-row tile's height. Control: no lock in the way.
  # Negative drags are parenthesized: a bare -1 after a positional argument is read as the text "-1".
  SlCase (SlSceneJson $pinsTopFree)
  SlClick (SlAt (SlBox 1001) 0.5 0.5)
  Check 'edge: the north handle is drawn on the 3-cell span (control scope)' ([bool](SlHandle 'n')) 'no n handle'
  [void](SlHandleDrag 'n' 0 (-1))
  $tfp = SlPin (SlGet 'work[selId]') 'Refactor'
  Check 'control: the north handle grows the 3-cell span up when no lock is in the way' ([bool]$tfp -and (SlCells $tfp) -eq '0,1,2,5,6,7') "claude pin: $(SlShort $tfp)"

  SlCase (SlSceneJson $pinsTopLock)
  SlClick (SlAt (SlBox 1001) 0.5 0.5)
  Check 'edge: the north handle is drawn on the 3-cell span with a lock above its third cell' ([bool](SlHandle 'n')) 'no n handle'
  [void](SlHandleDrag 'n' 0 (-1))
  $tpS = SlGet 'work[selId]'; $tpR = SlPin $tpS 'Refactor'; $tpQ = SlPin $tpS 'Quarterly'
  Check 'edge: a north handle drag toward the lock stops short of it, keeping the span''s width (cells 5,6,7)' ([bool]$tpR -and (SlCells $tpR) -eq '5,6,7') "claude pin: $(SlShort $tpR)"
  Check 'guard: a north handle drag toward the lock leaves the locked tile in its cell' ([bool]$tpQ -and $tpQ.lock -eq $true -and (SlCells $tpQ) -eq '2') "locked pin: $(SlShort $tpQ)"

  SlCase (SlSceneJson $pinsLeftFree)
  SlClick (SlAt (SlBox 1001) 0.5 0.5)
  Check 'edge: the west handle is drawn on the 2-row tile (control scope)' ([bool](SlHandle 'w')) 'no w handle'
  [void](SlHandleDrag 'w' (-1) 0)
  $lfp = SlPin (SlGet 'work[selId]') 'Refactor'
  Check 'control: the west handle grows the 2-row tile left when no lock is in the way' ([bool]$lfp -and (SlCells $lfp) -eq '1,2,6,7') "claude pin: $(SlShort $lfp)"

  SlCase (SlSceneJson $pinsLeftLock)
  SlClick (SlAt (SlBox 1001) 0.5 0.5)
  Check 'edge: the west handle is drawn on the 2-row tile with a lock beside its lower row' ([bool](SlHandle 'w')) 'no w handle'
  [void](SlHandleDrag 'w' (-1) 0)
  $lpS = SlGet 'work[selId]'; $lpR = SlPin $lpS 'Refactor'; $lpQ = SlPin $lpS 'Quarterly'
  Check 'edge: a west handle drag toward the lock stops short of it, keeping the tile''s height (cells 2,7)' ([bool]$lpR -and (SlCells $lpR) -eq '2,7') "claude pin: $(SlShort $lpR)"
  Check 'guard: a west handle drag toward the lock leaves the locked tile in its cell' ([bool]$lpQ -and $lpQ.lock -eq $true -and (SlCells $lpQ) -eq '6') "locked pin: $(SlShort $lpQ)"

  # Pure edges and corners against a lock. A pure edge handle (east, south) changes only its own dimension
  # and keeps the other, as the north and west handles do. A corner keeps the largest span that stops short of the lock, as
  # the grip does. Each red case has a control first, with no lock in the way, so a drag that never resizes cannot pass.
  $sq33 = '"c":3,"r":3'
  $pinsEastTall = SlPins '{"app":"claude","match":"Refactor","mon":"wide","slots":[0,5]}'
  $pinsEastTallLock = SlPins '{"app":"claude","match":"Refactor","mon":"wide","slots":[0,5]}' '{"app":"chrome","match":"Quarterly","mon":"wide","slots":[7],"lock":true}'
  $pinsSouthWide = SlPins '{"app":"claude","match":"Refactor","mon":"wide","slots":[0,1]}'
  $pinsSouthWideLock = SlPins '{"app":"claude","match":"Refactor","mon":"wide","slots":[0,1]}' '{"app":"chrome","match":"Quarterly","mon":"wide","slots":[4],"lock":true}'
  $pinsCornerNE = SlPins '{"app":"claude","match":"Refactor","mon":"wide","slots":[6]}'
  $pinsCornerNELock = SlPins '{"app":"claude","match":"Refactor","mon":"wide","slots":[6]}' '{"app":"chrome","match":"Quarterly","mon":"wide","slots":[5],"lock":true}'
  $pinsCornerSW = SlPins '{"app":"claude","match":"Refactor","mon":"wide","slots":[2]}'
  $pinsCornerSWLock = SlPins '{"app":"claude","match":"Refactor","mon":"wide","slots":[2]}' '{"app":"chrome","match":"Quarterly","mon":"wide","slots":[7],"lock":true}'

  # East, on the 5 by 2 grid: a 1x2 tile in column 0, both rows. The lock is at column 2, row 1 (slot 7). The drag is 3 cells east.
  SlCase (SlSceneJson $pinsEastTall)
  SlClick (SlAt (SlBox 1001) 0.5 0.5)
  Check 'scope: the east handle is drawn on the 1x2 tile' ([bool](SlHandle 'ea')) 'no ea handle'
  [void](SlHandleDrag 'ea' 1 0 3)
  $ce = SlPin (SlGet 'work[selId]') 'Refactor'
  Check 'control: an east drag with no lock in the way spans 4 columns and keeps 2 rows (as today)' ([bool]$ce -and (SlCells $ce) -eq '0,1,2,3,5,6,7,8') "claude pin: $(SlShort $ce)"
  SlCase (SlSceneJson $pinsEastTallLock)
  SlClick (SlAt (SlBox 1001) 0.5 0.5)
  Check 'scope: the east handle is drawn on the 1x2 tile next to a lock' ([bool](SlHandle 'ea')) 'no ea handle'
  [void](SlHandleDrag 'ea' 1 0 3)
  $ee = SlGet 'work[selId]'; $eeR = SlPin $ee 'Refactor'; $eeQ = SlPin $ee 'Quarterly'
  Check 'edge: an east drag toward a lock keeps the 1x2 tile''s 2 rows, so it stops at 2 columns (cells 0,1,5,6)' ([bool]$eeR -and (SlCells $eeR) -eq '0,1,5,6') "claude pin: $(SlShort $eeR)"
  Check 'guard: an east drag toward a lock leaves the locked tile in its cell' ([bool]$eeQ -and $eeQ.lock -eq $true -and (SlCells $eeQ) -eq '7') "locked pin: $(SlShort $eeQ)"

  # South, on a 3 by 3 grid: a 2x1 tile in row 0, both columns. The lock is at column 1, row 1 (slot 4). The drag is 2 cells south.
  SlCase (SlSceneJson $pinsSouthWide '[]' '' '' $sq33)
  SlClick (SlAt (SlBox 1001) 0.5 0.5)
  Check 'scope: the south handle is drawn on the 2x1 tile' ([bool](SlHandle 's')) 'no s handle'
  [void](SlHandleDrag 's' 0 1 2)
  $cs = SlPin (SlGet 'work[selId]') 'Refactor'
  Check 'control: a south drag with no lock in the way spans 3 rows and keeps 2 columns (as today)' ([bool]$cs -and (SlCells $cs) -eq '0,1,3,4,6,7') "claude pin: $(SlShort $cs)"
  SlCase (SlSceneJson $pinsSouthWideLock '[]' '' '' $sq33)
  SlClick (SlAt (SlBox 1001) 0.5 0.5)
  Check 'scope: the south handle is drawn on the 2x1 tile next to a lock' ([bool](SlHandle 's')) 'no s handle'
  [void](SlHandleDrag 's' 0 1 2)
  $ss = SlPin (SlGet 'work[selId]') 'Refactor'
  Check 'edge: a south drag toward a lock keeps the 2x1 tile''s 2 columns, so it stops at 1 row (cells 0,1)' ([bool]$ss -and (SlCells $ss) -eq '0,1') "claude pin: $(SlShort $ss)"

  # North-east corner, on a 3 by 3 grid: a 1x1 tile at the bottom left (slot 6). The lock is at column 2, row 1 (slot 5).
  # The drag goes to the top right of the grid. The largest span short of the lock is 2 columns by 3 rows.
  SlCase (SlSceneJson $pinsCornerNE '[]' '' '' $sq33)
  SlClick (SlAt (SlBox 1001) 0.5 0.5)
  Check 'scope: the north-east handle is drawn on the 1x1 tile' ([bool](SlHandle 'tr')) 'no tr handle'
  [void](SlHandleDrag 'tr' 1 (-1) 2)
  $ct = SlPin (SlGet 'work[selId]') 'Refactor'
  Check 'control: a north-east drag with no lock in the way spans the whole 3x3 grid (as today)' ([bool]$ct -and (SlCells $ct) -eq '0,1,2,3,4,5,6,7,8') "claude pin: $(SlShort $ct)"
  SlCase (SlSceneJson $pinsCornerNELock '[]' '' '' $sq33)
  SlClick (SlAt (SlBox 1001) 0.5 0.5)
  Check 'scope: the north-east handle is drawn on the 1x1 tile next to a lock' ([bool](SlHandle 'tr')) 'no tr handle'
  [void](SlHandleDrag 'tr' 1 (-1) 2)
  $cn = SlPin (SlGet 'work[selId]') 'Refactor'
  Check 'corner: a north-east drag toward a lock keeps the largest span short of it, 2 columns by 3 rows (cells 0,1,3,4,6,7)' ([bool]$cn -and (SlCells $cn) -eq '0,1,3,4,6,7') "claude pin: $(SlShort $cn)"

  # South-west corner, on a 3 by 3 grid: a 1x1 tile at the top right (slot 2). The lock is at column 1, row 2 (slot 7).
  # The drag goes to the bottom left of the grid. The largest span short of the lock is 3 columns by 2 rows.
  SlCase (SlSceneJson $pinsCornerSW '[]' '' '' $sq33)
  SlClick (SlAt (SlBox 1001) 0.5 0.5)
  Check 'scope: the south-west handle is drawn on the 1x1 tile' ([bool](SlHandle 'bl')) 'no bl handle'
  [void](SlHandleDrag 'bl' (-1) 1 2)
  $cw = SlPin (SlGet 'work[selId]') 'Refactor'
  Check 'control: a south-west drag with no lock in the way spans the whole 3x3 grid (as today)' ([bool]$cw -and (SlCells $cw) -eq '0,1,2,3,4,5,6,7,8') "claude pin: $(SlShort $cw)"
  SlCase (SlSceneJson $pinsCornerSWLock '[]' '' '' $sq33)
  SlClick (SlAt (SlBox 1001) 0.5 0.5)
  Check 'scope: the south-west handle is drawn on the 1x1 tile next to a lock' ([bool](SlHandle 'bl')) 'no bl handle'
  [void](SlHandleDrag 'bl' (-1) 1 2)
  $cbl = SlPin (SlGet 'work[selId]') 'Refactor'
  Check 'corner: a south-west drag toward a lock keeps the largest span short of it, 3 columns by 2 rows (cells 0,1,2,3,4,5)' ([bool]$cbl -and (SlCells $cbl) -eq '0,1,2,3,4,5') "claude pin: $(SlShort $cbl)"

  # Ctrl+Shift+arrows (board-feedback-notes item 12): the Shift+arrow rules, on the top and left edges. Shift+arrows are the
  # green controls beside them, so a key that never reaches the page cannot pass.
  SlCase (SlSceneJson $pinsKeyLeft)
  SlClick (SlAt (SlBox 1006) 0.5 0.5)
  SlKey 1006 'ArrowRight' 39 8
  $kc = SlPin (SlGet 'work[selId]') 'Quarterly'
  Check 'control: Shift+ArrowRight still grows the right edge of a pinned tile' ([bool]$kc -and (SlCells $kc) -eq '1,2') "chrome pin: $(SlShort $kc)"
  SlCase (SlSceneJson $pinsKeyLeft)
  SlClick (SlAt (SlBox 1006) 0.5 0.5)
  SlKey 1006 'ArrowLeft' 37 10
  $kl = SlGet 'work[selId]'; $klq = SlPin $kl 'Quarterly'; $klr = SlPin $kl 'Refactor'
  Check 'keys: Ctrl+Shift+ArrowLeft grows the left edge of a pinned tile to 2 columns' ([bool]$klq -and (SlCells $klq) -eq '0,1') "chrome pin: $(SlShort $klq)"
  Check 'keys: the covered pinned window moves to the first free cell, with its stack' ([bool]$klr -and (SlCells $klr) -eq '2' -and (SlHasBehind $klr 'Draft release')) "claude pin: $(SlShort $klr)"
  SlCase (SlSceneJson $pinsKeyUp)
  SlClick (SlAt (SlBox 1001) 0.5 0.5)
  SlKey 1001 'ArrowUp' 38 10
  $ku = SlPin (SlGet 'work[selId]') 'Refactor'
  Check 'keys: Ctrl+Shift+ArrowUp grows the top edge of a pinned tile to 2 rows' ([bool]$ku -and (SlCells $ku) -eq '1,6') "claude pin: $(SlShort $ku)"
  SlCase (SlSceneJson $pinsKeySpan)
  SlClick (SlAt (SlBox 1006) 0.5 0.5)
  SlKey 1006 'ArrowLeft' 37 8
  $ksc = SlPin (SlGet 'work[selId]') 'Quarterly'
  Check 'control: Shift+ArrowLeft still shrinks the right edge of a 2-column span' ([bool]$ksc -and (SlCells $ksc) -eq '0') "chrome pin: $(SlShort $ksc)"
  SlCase (SlSceneJson $pinsKeySpan)
  SlClick (SlAt (SlBox 1006) 0.5 0.5)
  SlKey 1006 'ArrowRight' 39 10
  $ksh = SlPin (SlGet 'work[selId]') 'Quarterly'
  Check 'keys: Ctrl+Shift+ArrowRight shrinks the left edge of a 2-column span to 1 column' ([bool]$ksh -and (SlCells $ksh) -eq '1') "chrome pin: $(SlShort $ksh)"
  SlCase (SlSceneJson $pinsKeyColSpan)
  SlClick (SlAt (SlBox 1006) 0.5 0.5)
  SlKey 1006 'ArrowUp' 38 8
  $kcs = SlPin (SlGet 'work[selId]') 'Quarterly'
  Check 'control: Shift+ArrowUp still shrinks the bottom edge of a 2-row span' ([bool]$kcs -and (SlCells $kcs) -eq '1') "chrome pin: $(SlShort $kcs)"
  SlCase (SlSceneJson $pinsKeyColSpan)
  SlClick (SlAt (SlBox 1006) 0.5 0.5)
  SlKey 1006 'ArrowDown' 40 10
  $kcd = SlPin (SlGet 'work[selId]') 'Quarterly'
  Check 'keys: Ctrl+Shift+ArrowDown shrinks the top edge of a 2-row span to 1 row' ([bool]$kcd -and (SlCells $kcd) -eq '6') "chrome pin: $(SlShort $kcd)"
  SlCase (SlSceneJson $pinsCQLock)
  SlClick (SlAt (SlBox 1006) 0.5 0.5)
  SlKey 1006 'ArrowLeft' 37 10
  $kk = SlGet 'work[selId]'; $kkq = SlPin $kk 'Quarterly'; $kkr = SlPin $kk 'Refactor'
  $kkmsg = SlJs "document.getElementById('msg').textContent"
  Check 'keys: Ctrl+Shift+ArrowLeft toward a locked tile is refused, and says so' ("$kkmsg" -match 'locked tile is in the way') "status: $kkmsg"
  Check 'guard: Ctrl+Shift+ArrowLeft toward a locked tile leaves the locked tile in its cell' ([bool]$kkr -and $kkr.lock -eq $true -and (SlCells $kkr) -eq '0') "locked pin: $(SlShort $kkr)"
  Check 'guard: Ctrl+Shift+ArrowLeft toward a locked tile does not grow the window onto it' ([bool]$kkq -and (SlCells $kkq) -eq '1') "chrome pin: $(SlShort $kkq)"
  SlCase (SlSceneJson $pinsFullStack)
  SlClick (SlAt (SlBox 1002) 0.5 0.5)
  SlKey 1002 'ArrowLeft' 37 10
  $kf = SlGet 'work[selId]'; $kfp = SlPin $kf 'Pin parser'
  Check 'keys: with no free cell, Ctrl+Shift+ArrowLeft grows the tile onto the covered window''s cell' ([bool]$kfp -and (SlCells $kfp) -eq '0,1') "pin parser: $(SlShort $kfp)"
  Check 'keys: with no free cell, the covered pinned window goes to Windows That Stay Put' (SlHasBay $kf 'Refactor') "bay: $(SlShort $kf.bay)"

  # Fill Empty Cells switch (page). It is on the fill monitor's Monitor section; off writes fill.off, saves, and reloads off.
  SlCase (SlSceneJson $pinsCQ '["*"]')
  Check 'fill switch: the Ultrawide label reads "fills" (scope)' ([bool](SlJs "[...document.querySelectorAll('.mlab .num')].some(n => n.textContent.includes('fills'))")) 'no monitor reads fills'
  $sw0 = SlSwitch
  Check 'fill switch: the inspector shows a Fill Empty Cells switch, checked' ($sw0 -eq $true) "switch: $sw0"
  [void](SlSwitch -Click); SlSettle
  $swOff = SlGet 'work[selId].fill.off'
  Check 'fill switch: turning it off writes fill.off to the scene' ($swOff -eq $true) "fill.off: $swOff"
  [void](SlJs "(() => { const b = document.getElementById('save'); if (b && !b.disabled) { b.click(); return true; } return false; })()")
  SlSettle
  $swSaved = SlSavedScene
  Check 'fill switch: the saved scene keeps fill.off' ([bool]($swSaved -and $swSaved.fill.off -eq $true)) "saved fill: $(SlShort $swSaved.fill)"
  SlLoad
  $swBack = SlSwitch
  Check 'fill switch: after a reload the switch is still off' ($swBack -eq $false) "switch after reload: $swBack"

  # Clear Board (page). It sends each unpinned window to Windows That Stay Put and turns Fill Empty Cells off; the switch refills.
  SlCase (SlSceneJson $pinsCQ '["*"]')
  # Ids are joined in the page, so each comes back as one string, not as an array to unpack.
  $placedIds = "prevs[selId].placed.map(p => p.id).sort((a, b) => a - b).join(',')"
  $cbWas = "$(SlJs $placedIds)"
  $cbPinsWasList = SlList 'work[selId].pins'; $cbPinsWas = @($cbPinsWasList).Count
  $cbPress = SlJs "(() => { const b = [...document.querySelectorAll('button')].find(x => x.textContent.trim() === 'Clear Board'); if (!b) return 'no such button'; if (b.disabled) return 'disabled'; b.click(); return 'pressed'; })()"
  SlSettle
  $cbAfter = "$(SlJs $placedIds)"
  $cbPinsNowList = SlList 'work[selId].pins'; $cbPinsNow = @($cbPinsNowList).Count
  $cbLeft = @("$(SlJs "prevs[selId].left.map(p => p.id).join(',')")" -split ',' | ? { $_ } | % { [int]$_ })
  $cbScene = SlGet 'work[selId].fill.off'
  $cbMsg = SlJs "document.getElementById('msg').textContent"
  $cbList = SlJs "document.body.innerText.includes('Fill is off')"
  Check 'clear board: the board has a Clear Board button, and it presses' ($cbPress -eq 'pressed') "button: $cbPress"
  Check 'clear board: it turns Fill Empty Cells off in the scene' ($cbScene -eq $true) "fill.off: $cbScene"
  # Clear Board is unchanged by the switch's pins (decisions/fill-controls.md): it adds no pin, so the windows it clears stay unpinned.
  Check 'clear board: it adds no pins to the scene' ($cbPinsNow -eq $cbPinsWas) "pins before: $cbPinsWas, after: $cbPinsNow"
  # Clear Board holds nothing (decisions/fill-controls.md): no held layout, so every cleared window is listed, not kept in its cell.
  $cbHeld = SlList 'work[selId].fill.held'
  Check 'clear board: it holds no windows (fill.held stays empty)' (@($cbHeld).Count -eq 0) "fill.held: $(SlShort $cbHeld)"
  Check 'clear board: only the pinned windows stay on the board' ($cbAfter -eq '1001,1006') "placed: $cbAfter"
  # The windows the fill placed before the press, minus the two pins (1001 Refactor, 1006 Quarterly). With '*' the fill skips
  # apps that have a pin (claude, chrome), so those windows were never on the board and are not in this set.
  $cbFilled = @("$cbWas" -split ',' | ? { $_ -and $_ -ne '1001' -and $_ -ne '1006' } | % { [int]$_ })
  Check 'clear board: every window the fill had placed is in Windows That Stay Put' ($cbFilled.Count -gt 0 -and @($cbFilled | ? { $cbLeft -notcontains $_ }).Count -eq 0) "filled before: $($cbFilled -join ','); left: $($cbLeft -join ',')"
  Check 'clear board: the status line says what it did' ("$cbMsg" -like '*Cleared the board*') "status: $cbMsg"
  Check 'clear board: the list gives the reason "Fill is off"' ([bool]$cbList) 'no "Fill is off" on the board'
  $cbOff = SlSwitch
  [void](SlSwitch -Click); SlSettle
  $cbOn = "$(SlJs $placedIds)"
  Check 'clear board: turning Fill Empty Cells back on refills the board to the same windows' ($cbOff -eq $false -and $cbWas -ne '' -and $cbOn -eq $cbWas) "switch was: $cbOff; placed before: $cbWas; after: $cbOn"

  # Fill Empty Cells off holds the windows the fill or a zone placed, each where it is (decisions/fill-controls.md, owner ruling
  # 2026-11-12 12:05 CST). The scene keeps them in fill.held, apart from its pins: the switch adds no pin, no pin mark shows, and
  # every held window keeps its cell on the board and in a dry run. The owner's pins and locks are not touched.
  SlViewport 1440 900; SlCase (SlSceneJson $pinsCQLock '["*"]' ',"zones":[{"mon":"wide","slots":[5,6],"app":"WindowsTerminal"}]')
  $pinsWas = SlList 'work[selId].pins'
  $offBefore = SlList "prevs[selId].placed.filter(p => p.pin < 0).map(p => ({ id: p.id, app: p.app, slots: p.slots, zone: p.zone }))"
  Check 'switch off, scope: before the switch, the fill and a zone have placed windows' ($offBefore.Count -gt 0 -and @($offBefore | ? { $_.zone -ge 0 }).Count -ge 1) "placed by fill or zone: $(SlShort $offBefore)"
  [void](SlSwitch -Click); SlSettle
  $offAfter = SlList "prevs[selId].placed.map(p => ({ id: p.id, pin: p.pin, slots: p.slots }))"
  $offPins = SlList 'work[selId].pins'
  $held = SlList 'work[selId].fill.held'
  $moved = @()
  foreach ($b in $offBefore) {
    $a = @($offAfter | ? { $_.id -eq $b.id })[0]
    if (-not $a -or ((@($a.slots) | Sort-Object) -join ',') -ne ((@($b.slots) | Sort-Object) -join ',')) { $moved += "$($b.id)" }
  }
  Check 'switch off: every window the fill or a zone placed keeps its cell' ($moved.Count -eq 0 -and $offBefore.Count -gt 0) "not kept in place: $($moved -join ','); placed after: $(SlShort $offAfter)"
  Check 'switch off: fill.held has one entry per window the fill or a zone placed' (@($held).Count -eq $offBefore.Count -and $offBefore.Count -gt 0) "fill.held: $(SlShort $held); placed: $(SlShort $offBefore)"
  Check 'switch off: the switch adds no pin, so the scene''s pins are as they were' ((ConvertTo-Json -Depth 12 -Compress @($offPins)) -ceq (ConvertTo-Json -Depth 12 -Compress @($pinsWas))) "pins before: $(SlShort $pinsWas); after: $(SlShort $offPins)"
  $offIdsJs = '[' + ((@($offBefore) | % { [int]$_.id }) -join ',') + ']'
  $pmShown = SlList "prevs[selId].placed.filter(p => $offIdsJs.includes(p.id)).map(p => p.id).filter(id => { const t = els.get(id); return !!t && (t.classList.contains('pin') || !!t.querySelector('.pinmark')); })"
  Check 'switch off: no pin mark shows on a held window' ($offBefore.Count -gt 0 -and @($pmShown).Count -eq 0) "pin mark on: $(SlShort $pmShown)"

  # A held window's cell stays empty when the window is sent to Windows That Stay Put, and a dry-run Apply places the same windows
  # in the same cells as the board shows (tile.ps1 -DryRun, through SlDry).
  $sendWin = @($offBefore | ? { $_.zone -lt 0 })[0]
  $sendId = if ($sendWin) { [int]$sendWin.id } else { 0 }
  $freedSlots = if ($sendWin) { @($sendWin.slots) } else { @() }
  # One named cause when the switch did not hold it: the steps below need that window held in its cell, so they wait on this check.
  $sendHeld = @($offAfter | ? { $_.id -eq $sendId -and $_.pin -lt 0 -and ((@($_.slots) | Sort-Object) -join ',') -eq ((@($freedSlots) | Sort-Object) -join ',') }).Count -gt 0
  Check 'switch off, precondition: a window the fill placed is held in its cell, unpinned, to send to Windows That Stay Put' $sendHeld "no held window in its cell; placed windows: $(SlShort $offAfter)"
  if ($sendHeld) {
  if (SlBox $sendId) { SlKey $sendId 'k' 75 }
  $bayAfterSend = SlBayIds
  Check 'send to bay: the window is listed in Windows That Stay Put' ($sendId -gt 0 -and ($bayAfterSend -contains $sendId)) "window: $sendId; bay ids: $($bayAfterSend -join ',')"
  $sentPlaced = SlList "prevs[selId].placed.map(p => ({ id: p.id, pin: p.pin, zone: p.zone, slots: p.slots }))"
  $intoFreed = @($sentPlaced | ? { $_.id -ne $sendId -and @($_.slots | ? { $freedSlots -contains $_ }).Count -gt 0 })
  Check 'send to bay: its cell stays empty, since fill is off' ($sendId -gt 0 -and $freedSlots.Count -gt 0 -and $intoFreed.Count -eq 0) "freed cell $($freedSlots -join ','); taken by: $(SlShort $intoFreed)"
  $heldNow = SlList 'work[selId].fill.held'
  Check 'send to bay: the window leaves fill.held' (@($heldNow).Count -eq (@($held).Count - 1)) "fill.held before: $(@($held).Count); after: $(@($heldNow).Count)"
  $sceneNow = SlGet 'work[selId]'
  $dryNow = if ($sceneNow) { SlDry (ConvertTo-Json -Depth 12 -Compress $sceneNow) } else { $null }
  $pageMap = SlCellMap $sentPlaced
  $dryMap = SlCellMap @($dryNow.placed)
  $diffs = @()
  foreach ($k in (@($pageMap.Keys) + @($dryMap.Keys) | Select-Object -Unique)) { if ($pageMap[$k] -ne $dryMap[$k]) { $diffs += $k } }
  Check 'send to bay: a dry-run Apply places the same windows in the same cells' ($pageMap.Count -gt 0 -and $diffs.Count -eq 0) "differ: $($diffs -join ','); board: $($pageMap.Count) windows, dry run: $($dryMap.Count)"

  # A window the scene does not hold (one opened after the switch) goes to Windows That Stay Put, and takes no freed cell. The
  # fixture copy below adds one open window; the dry run is the page's own scene, so the held layout is whatever the page wrote.
  $fxNew = Join-Path $run 'fixture-new.json'
  $fxDoc = Get-Content -Raw -Encoding UTF8 -LiteralPath $fixture | ConvertFrom-Json
  $fxDoc.windows = @($fxDoc.windows) + [pscustomobject]@{ id = 1020; app = 'claude'; title = 'Opened after the switch'; x = 3000; y = 100; w = 800; h = 600 }
  [IO.File]::WriteAllText($fxNew, (ConvertTo-Json -Depth 10 -Compress $fxDoc), $utf8)
  $newRes = (& $tile -Scene (ConvertTo-Json -Depth 12 -Compress $sceneNow) -From $fxNew -DryRun -Json 3>$null) -join '' | ConvertFrom-Json
  $newIn = @(@($newRes.placed) + @($newRes.left) | ? { $_.id -eq 1020 }).Count
  Check 'new window, scope: the dry run answers for the open window 1020 once, and places the held windows' ($newIn -eq 1 -and @($newRes.placed | ? { $_.id -ne 1020 }).Count -gt 0) "answers for 1020: $newIn; placed: $(SlShort @($newRes.placed))"
  $newBay = @($newRes.left | ? { $_.id -eq 1020 -and $_.why -eq 'fill is off' }).Count
  $newTakes = @($newRes.placed | ? { $_.id -eq 1020 -or @($_.slots | ? { $freedSlots -contains $_ }).Count -gt 0 }).Count
  Check 'new window: it goes to Windows That Stay Put with "fill is off", and takes no freed cell' ($newBay -eq 1 -and $newTakes -eq 0) "left as fill is off: $newBay; placed in the freed cell or as 1020: $newTakes"

  # Turning Fill Empty Cells back on clears the held layout and fills the empty cells as usual. The owner's pins and locks stay as they were.
  Check 'fill on, scope: the scene holds windows in fill.held before the switch is turned on' (@($heldNow).Count -gt 0) "fill.held: $(SlShort $heldNow)"
  [void](SlSwitch -Click); SlSettle
  $onPins = SlList 'work[selId].pins'
  $onHeld = SlList 'work[selId].fill.held'
  $onPlaced = SlList "prevs[selId].placed.map(p => ({ id: p.id, pin: p.pin, zone: p.zone, slots: p.slots }))"
  Check 'fill on: the owner''s pins and locks are as they were before the switch' ((ConvertTo-Json -Depth 12 -Compress @($onPins)) -ceq (ConvertTo-Json -Depth 12 -Compress @($pinsWas))) "pins before: $(SlShort $pinsWas); after: $(SlShort $onPins)"
  Check 'fill on: it clears fill.held' (@($onHeld).Count -eq 0) "fill.held after: $(SlShort $onHeld)"
  $refilled = @($onPlaced | ? { $_.pin -lt 0 -and $_.zone -lt 0 -and $_.id -ne $sendId -and @($_.slots | ? { $freedSlots -contains $_ }).Count -gt 0 })
  Check 'fill on: the freed cell is filled by a window, not left empty' ($freedSlots.Count -gt 0 -and $refilled.Count -ge 1) "freed cell $($freedSlots -join ','); placed: $(SlShort $onPlaced)"
  Check 'fill on: the window sent to Windows That Stay Put stays there' ($sendId -gt 0 -and ((SlBayIds) -contains $sendId)) "window: $sendId"
  }
  # A locked pin for a closed window holds no cell in the engine, so the fill puts an open window on that cell. Turning the
  # switch off keeps the locked pin and its lock, and that window goes to Windows That Stay Put unpinned: nothing is placed
  # over a locked tile (decisions/stack-and-lock.md, a locked tile never moves).
  SlCase (SlSceneJson '[{"app":"closedapp","match":"","mon":"wide","slots":[0],"lock":true}]' '["*"]')
  $lkOn = SlList "prevs[selId].placed.filter(p => p.slots.includes(1)).map(p => ({ id: p.id, app: p.app, pin: p.pin }))"
  $lkWin = @($lkOn)[0]
  Check 'closed locked pin, scope: the fill has put an open window on the locked pin cell' ([bool]($lkWin -and [int]$lkWin.pin -lt 0)) "placed on slot 1: $(SlShort $lkOn)"
  [void](SlSwitch -Click); SlSettle
  $lkPins = SlList 'work[selId].pins'
  $lkLock = @($lkPins | ? { "$($_.app)" -eq 'closedapp' })[0]
  Check 'closed locked pin: turning the switch off keeps the locked pin in its cell, with its lock' ([bool]($lkLock -and $lkLock.lock -eq $true -and (SlCells $lkLock) -eq '0')) "locked pin: $(SlShort $lkLock)"
  $lkOver = @($lkPins | ? { "$($_.app)" -eq "$($lkWin.app)" -and (SlCells $_) -eq '0' })
  $lkBay = SlBayIds
  Check 'closed locked pin: the window the fill had on that cell goes to Windows That Stay Put, unpinned' ([bool]($lkWin -and $lkOver.Count -eq 0 -and ($lkBay -contains [int]$lkWin.id))) "pins on slot 0: $(SlShort $lkOver); bay ids: $($lkBay -join ',')"
  # Nothing is held over a locked cell: no window is placed on that cell as a held one (no unpinned placement on slot 1).
  $lkCell = SlList "prevs[selId].placed.filter(p => p.slots.includes(1)).map(p => ({ id: p.id, pin: p.pin }))"
  Check 'closed locked pin: no window is held over the locked cell' (@($lkCell | ? { $_.pin -lt 0 }).Count -eq 0) "placed on the locked cell: $(SlShort $lkCell)"
  # Fill on again: the window the switch sent to Windows That Stay Put is filled as usual. The bay entry the hold left must not outlive it.
  $lkId = if ($lkWin) { [int]$lkWin.id } else { 0 }
  [void](SlSwitch -Click); SlSettle
  $lkBackPlaced = SlList "prevs[selId].placed.filter(p => p.id === $lkId).map(p => ({ id: p.id, pin: p.pin, slots: p.slots }))"
  $lkBackBay = SlBayIds
  Check 'closed locked pin, fill on again: the window is filled as usual and is not in Windows That Stay Put' ([bool]($lkId -gt 0 -and @($lkBackPlaced).Count -eq 1 -and $lkBackPlaced[0].pin -lt 0 -and -not ($lkBackBay -contains $lkId))) "placed: $(SlShort $lkBackPlaced); bay ids: $($lkBackBay -join ',')"
  # An unlocked pin for a closed window holds its cell as a locked one does: nothing is held onto that cell (decisions/fill-controls.md).
  # The fill puts an open window on the cell while the switch is on. Turning the switch off must not hold that window there: it goes to
  # Windows That Stay Put, and the status line counts the windows held without it.
  SlCase (SlSceneJson '[{"app":"closedapp","match":"","mon":"wide","slots":[0]}]' '["*"]')
  $ucOn = SlList "prevs[selId].placed.filter(p => p.slots.includes(1)).map(p => ({ id: p.id, app: p.app, pin: p.pin }))"
  $ucWin = @($ucOn)[0]
  $ucId = if ($ucWin) { [int]$ucWin.id } else { 0 }
  $ucPins = SlList 'work[selId].pins'
  $ucPin = @($ucPins | ? { "$($_.app)" -eq 'closedapp' })[0]
  $ucIds = SlList "prevs[selId].placed.filter(p => p.pin < 0 && !p.behind).map(p => p.id)"
  $ucFill = @($ucIds).Count
  Check 'unlocked closed pin, scope: the pin has no lock, and the fill has put an open window on its cell among three or more placed' ([bool]($ucPin -and -not $ucPin.lock -and $ucId -gt 0 -and $ucFill -ge 3)) "pin: $(SlShort $ucPin); on slot 1: $(SlShort $ucOn); fill-placed: $ucFill"
  [void](SlSwitch -Click); SlSettle
  $ucHeld = SlList 'work[selId].fill.held'
  Check 'unlocked closed pin: the window the fill had on its cell is not held over it' (-not @($ucHeld | ? { [int]$_.id -eq $ucId }).Count) "fill.held: $(SlShort $ucHeld)"
  $ucBay = SlBayIds
  Check 'unlocked closed pin: that window goes to Windows That Stay Put' ([bool]($ucId -gt 0 -and ($ucBay -contains $ucId))) "bay ids: $($ucBay -join ',')"
  $ucMsg = SlJs "document.getElementById('msg').textContent"
  $ucWant = $ucFill - 1
  Check "unlocked closed pin: the status line counts $ucWant windows held, one fewer than the fill placed" ([bool]("$ucMsg" -like "*$ucWant windows are held where they are.*")) "status: $ucMsg"

  # The status line names how many windows the switch holds. The count is the windows the fill or a zone had placed before
  # the switch (each is held in its cell), so the scope is read first and the line after the switch.
  SlCase (SlSceneJson $pinsCQ '["*"]')
  $kpIds = SlList "prevs[selId].placed.filter(p => p.pin < 0 && !p.behind).map(p => p.id)"
  $kpN = @($kpIds).Count
  Check 'switch off status, scope: the fill has placed at least two windows the switch holds' ($kpN -ge 2) "fill-placed windows: $kpN"
  [void](SlSwitch -Click); SlSettle
  $kpMsg = SlJs "document.getElementById('msg').textContent"
  Check 'switch off status: the status line gives the count of windows held where they are' ([bool]("$kpMsg" -like "*$kpN windows are held where they are.*")) "status: $kpMsg"

  # A drop moves a window, and the switch is pressed before the drop's engine answer comes back. The switch must keep the window
  # where it was dropped (the holds come from the newest placement). The answer it reads is still the one from before the drop, so the old code pins the window back in
  # its old cell. The scope says the answer is still pending (the switch is pressed while it is in flight).
  SlCase (SlSceneJson '[]' '["claude"]')
  $dpFrom = SlAt (SlBox 1002) 0.5 0.5
  $dpTo = SlSlotAt 5
  SlMarkEngine
  SlDropNoSettle $dpFrom $dpTo
  $dpMoved = SlPin (SlGet 'work[selId]') 'Pin parser'
  $dpPending = SlJs "prevs[selId] === window.bfEngine"
  Check 'switch during a drop, scope: the drop pins Pin parser in the cell it was dropped on, and its engine answer is still pending' ([bool]($dpMoved -and (SlCells $dpMoved) -eq '5' -and $dpPending)) "pin: $(SlShort $dpMoved); answer still pending: $dpPending"
  [void](SlSwitch -Click); SlSettle
  $dpAfter = SlPin (SlGet 'work[selId]') 'Pin parser'
  Check 'switch during a drop: Pin parser stays pinned where it was dropped, not in its old cell' ([bool]($dpAfter -and (SlCells $dpAfter) -eq '5')) "pin: $(SlShort $dpAfter)"
  # Fill Empty Cells off, on the board. The owner's pins (Refactor in claude, Quarterly in chrome) give their apps a pinned window. Each
  # open window still unpinned in Windows That Stay Put must read "Fill is off" in its reason line, not "Not in this scene". The switch
  # holds the windows the fill placed and adds no pin. The control is the same board before the switch: no window reads "Fill is off".
  SlViewport 1440 900; SlCase (SlSceneJson $pinsCQ '["*"]')
  $n1Before = SlList "[...document.querySelectorAll('#bgrps [data-bay]')].map(b => b.getAttribute('aria-label'))"
  Check 'control, fill on, board: no window in Windows That Stay Put reads "Fill is off"' (@($n1Before | ? { "$_" -like '*Fill is off*' }).Count -eq 0) "labels: $(SlShort $n1Before)"
  $n1PinsWas = SlList 'work[selId].pins'
  [void](SlSwitch -Click); SlSettle
  $n1PinsNow = SlList 'work[selId].pins'
  Check 'fill off, board: the switch adds no pin' ((ConvertTo-Json -Depth 12 -Compress @($n1PinsNow)) -ceq (ConvertTo-Json -Depth 12 -Compress @($n1PinsWas))) "pins before: $(SlShort $n1PinsWas); after: $(SlShort $n1PinsNow)"
  $n1Scope = SlList "(() => { const pinned = new Set(work[selId].pins.map(p => p.app)); return [...document.querySelectorAll('#bgrps [data-bay]')].map(b => snap.windows.find(w => w.id === +b.dataset.bay)).filter(w => w && !w.min && pinned.has(w.app)).map(w => w.id); })()"
  Check 'fill off, board, scope: an unpinned window is in Windows That Stay Put, and its app has a pinned window' ($n1Scope.Count -ge 1) "windows: $($n1Scope -join ',')"
  $n1Chips = SlList "[...document.querySelectorAll('#bgrps [data-bay]')].map(b => ({ id: +b.dataset.bay, min: !!(snap.windows.find(w => w.id === +b.dataset.bay) || {}).min, reason: (b.querySelector('small') || { textContent: null }).textContent }))"
  $n1Open = @($n1Chips | ? { -not $_.min })
  $n1Bad = @($n1Open | ? { $_.reason -ne 'Fill is off' })
  Check 'fill off, board: every unpinned window in Windows That Stay Put has the reason line "Fill is off"' ($n1Open.Count -gt 0 -and $n1Bad.Count -eq 0) "open: $($n1Open.Count); not 'Fill is off': $(@($n1Bad | % { "$($_.id) (reason line: $(if ($_.reason) { $_.reason } else { 'none' }))" }) -join ', ')"
  # The inspector says the same for one of them: Draft release notes (1003, unpinned, its app Claude has pinned windows).
  SlJs 'document.querySelector("[data-bay=\"1003\"]").click(); true'
  $n1Insp = SlGet '(() => { const m = document.querySelector("#win .m"); return m ? m.textContent.replace(/\s+/g, " ").trim() : null; })()'
  Check 'fill off, board: the inspector gives "fill is off" as the reason for Draft release notes' ([bool]("$n1Insp" -like '*fill is off*')) "inspector line: $n1Insp"

  # A narrow pinned tile loses its pin mark, so the inspector's "Pinned" line is the only cue left. Selecting it scrolls the inspector
  # so that line is in its visible area. At 1440 the mark stays: that is the control.
  $pinnedLine = { SlGet '(() => { const t = els.get(1001), ins = document.querySelector(".insp"), m = [...document.querySelectorAll("#win .m")].find(e => e.textContent.trim().startsWith("Pinned")), pmk = t.querySelector(".pinmark"); const q = ins.getBoundingClientRect(), r = m ? m.getBoundingClientRect() : null; return { narrow: t.classList.contains("narrow"), pin: t.classList.contains("pin"), sel: t.classList.contains("sel"), pinmark: pmk ? getComputedStyle(pmk).display : "absent", line: !!m, lineTop: r ? r.top : null, lineBottom: r ? r.bottom : null, insTop: q.top, insBottom: q.bottom }; })()' }
  SlViewport 1440 900; SlCase (SlSceneJson $pinsCQ '["*"]')
  SlClick (SlAt (SlBox 1001) 0.5 0.5)
  $n3c = & $pinnedLine
  Check 'control, 1440: the selected pinned tile keeps its pin mark' ([bool]($n3c.pin -and $n3c.sel -and $n3c.pinmark -eq 'block')) "pin: $($n3c.pin), selected: $($n3c.sel), pin mark: $($n3c.pinmark)"
  SlViewport 1024 768; SlCase (SlSceneJson $pinsCQ '["*"]')
  SlClick (SlAt (SlBox 1001) 0.5 0.5)
  $n3 = & $pinnedLine
  Check 'narrow pinned tile, 1024, scope: the selected pinned tile is narrow and its pin mark is hidden' ([bool]($n3.narrow -and $n3.pin -and $n3.sel -and $n3.pinmark -eq 'none')) "narrow: $($n3.narrow), pin: $($n3.pin), selected: $($n3.sel), pin mark: $($n3.pinmark)"
  Check 'narrow pinned tile, 1024: the inspector''s Pinned line is in the inspector''s visible area' ([bool]($n3.line -and $n3.lineTop -ge $n3.insTop -and $n3.lineBottom -le $n3.insBottom)) "line $($n3.lineTop) to $($n3.lineBottom); inspector $($n3.insTop) to $($n3.insBottom)"

  # A scene tab click while the switch waits for a preview in flight. The switch reads the answer of the scene it was pressed on, so it
  # changes that scene, and the scene clicked second stays as it was. The first preview is held in the page (a fetch wrapper), so the
  # wait is real, and it ends only when the case releases it.
  SlViewport 1440 900
  $sceneA = SlSceneJson (SlPins '{"app":"claude","match":"Refactor","mon":"wide","slots":[0]}' '{"app":"chrome","match":"Quarterly","mon":"wide","slots":[1]}') '["*"]'
  $sceneB = $sceneA.Replace('"id":"sl","name":"Stack and lock"', '"id":"sl2","name":"Second scene"').Replace('"match":"Refactor"', '"match":"Pin parser"')
  $cfgTwo = (Invoke-WebRequest -UseBasicParsing "$($script:url)config").Content | ConvertFrom-Json
  $cfgTwo.scenes = @((ConvertFrom-Json $sceneA), (ConvertFrom-Json $sceneB))
  $bodyTwo = ConvertTo-Json -Depth 12 -Compress $cfgTwo
  if ((Invoke-WebRequest -UseBasicParsing "$($script:url)config" -Method Post -ContentType 'application/json; charset=utf-8' -Body ($utf8.GetBytes($bodyTwo))).Content -ne 'Saved') { throw 'the two-scene config was not saved' }
  SlLoad
  SlJs 'previewAll().then(() => true)'
  SlJs 'document.querySelector("[data-pick=sl]").click(); true'
  SlJs 'window.__hold = false; if (!window.__origFetch) { window.__origFetch = window.fetch; window.fetch = (u, o) => (window.__hold && String(u).endsWith("preview")) ? new Promise(res => { window.__release = () => res(window.__origFetch(u, o)); }) : window.__origFetch(u, o); } true'
  SlJs 'window.__bSecond = JSON.stringify(work["sl2"]); true'
  # Control: no preview in flight. The switch writes fill.off to the scene it was pressed on, and the second scene does not change.
  [void](SlSwitch -Click); SlSettle
  $ctlOff = SlGet 'work["sl"].fill.off'
  $ctlSecond = SlJs 'JSON.stringify(work["sl2"]) === window.__bSecond'
  Check 'control, no preview in flight: the switch writes fill.off to the scene it was pressed on, and the other scene is unchanged' ([bool]($ctlOff -eq $true -and $ctlSecond -eq $true)) "fill.off on the first: $ctlOff; second unchanged: $ctlSecond"
  [void](SlSwitch -Click); SlSettle
  SlJs 'window.__bSecond = JSON.stringify(work["sl2"]); true'
  # The wait: the switch is pressed while the first scene's preview is held, then the second scene is clicked, then the answer comes back.
  SlJs 'window.__hold = true; preview("sl"); true'
  [void](SlSwitch -Click)
  $scopeA = SlGet '({ inflight: !!inflight["sl"], sel: selId })'
  Check 'scene tab click during the wait, scope: the switch on Scene A waits for A''s preview, and Scene A is the selected scene' ([bool]($scopeA.inflight -and $scopeA.sel -eq 'sl')) "in flight: $($scopeA.inflight), selected: $($scopeA.sel)"
  SlJs 'document.querySelector("[data-pick=sl2]").click(); true'
  SlJs 'window.__hold = false; window.__release(); true'
  SlJs 'newestPrev("sl").then(() => true)'
  SlSettle
  $secondNow = SlJs 'JSON.stringify(work["sl2"]) === window.__bSecond'
  $firstNow = SlGet 'work["sl"].fill.off'
  Check 'scene tab click during the wait: the scene clicked second is unchanged' ([bool]($secondNow -eq $true)) "second scene unchanged: $secondNow; its fill.off: $(SlGet 'work["sl2"].fill.off')"
  Check 'scene tab click during the wait: the switch lands on the scene it was pressed on' ([bool]($firstNow -eq $true)) "first scene fill.off: $(if ($null -eq $firstNow) { 'none' } else { $firstNow })"

  # Held title changed (decisions/fill-controls.md): notepad has one window, so its held title does not decide the match, as with a pin.
  # The page places it in its held cell; a save keeps the entry, and a dry run from the saved scene places it in the same cell.
  SlViewport 1440 900; SlCase (SlSceneJson '[]' '["*"]' '' (SlHeldFill '[{"app":"notepad","title":"Old todo title - Notepad","mon":"wide","slots":[0]}]'))
  $tcHeld = SlList 'work[selId].fill.held'
  Check 'held title changed, scope: the scene holds the notepad window under its old title' ($tcHeld.Count -eq 1 -and "$($tcHeld[0].app)" -eq 'notepad') "fill.held: $(SlShort $tcHeld)"
  $tcPage = SlPlacedOf 1014
  Check 'held title changed: the page places the window in its held cell' ([bool]($tcPage -and @($tcPage.slots) -contains 1)) "page cells of 1014: $(if ($tcPage) { (@($tcPage.slots) | Sort-Object) -join '+' } else { 'none' })"
  [void](SlJs 'saveScene().then(() => true)'); SlSettle
  $tcSaved = SlSavedScene
  $tcSavedHeld = @($tcSaved.fill.held | ? { $_ })
  Check 'held title changed: a save keeps the held window' ($tcSavedHeld.Count -eq 1 -and "$($tcSavedHeld[0].app)" -eq 'notepad') "saved fill.held entries: $($tcSavedHeld.Count)"
  $tcDry = SlDry (ConvertTo-Json -Depth 12 -Compress $tcSaved)
  Check 'held title changed: a dry run from the saved scene places the window in its held cell' ((SlSlotsOf $tcDry 1014) -eq '1') "saved held entries: $($tcSavedHeld.Count); 1014 cells: $(SlSlotsOf $tcDry 1014)"

  # A grid change keeps a held window on its column and row, as it keeps a pin (setGrid remaps the held layout as it remaps the pins).
  SlViewport 1440 900; SlCase (SlSceneJson '[]' '["*"]' '' (SlHeldFill '[{"app":"claude","title":"Draft release notes","mon":"wide","slots":[5]},{"app":"notepad","title":"todo.txt - Notepad","mon":"wide","slots":[1]}]'))
  $gScope = SlPlacedOf 1003
  Check 'grid, scope: the held window 1003 is placed in its held cell, column 1 of row 2' ([bool]($gScope -and @($gScope.slots) -contains 6)) "placed: $(SlShort $gScope)"
  SlJs "(() => { curMon = snap.monitors.find(m => m.role === 'wide'); setGrid('c', 1); return true; })()"; SlSettle
  $gHeld = SlList 'work[selId].fill.held'
  $gClaude = @($gHeld | ? { "$($_.app)" -eq 'claude' })[0]
  $gNotepad = @($gHeld | ? { "$($_.app)" -eq 'notepad' })[0]
  Check 'grid: a column added to the right keeps the held window of row 2, column 1 in that column and row' ([bool]($gClaude -and (SlCells $gClaude) -eq '6')) "claude held slots: $(if ($gClaude) { SlCells $gClaude } else { 'none' }); fill.held: $(SlShort $gHeld)"
  Check 'grid, control: the held window in row 1, column 2 stays in its cell' ([bool]($gNotepad -and (SlCells $gNotepad) -eq '1')) "notepad held slots: $(if ($gNotepad) { SlCells $gNotepad } else { 'none' })"

  # Two windows with one title (1006 and 1017, a copy of the fixture with 1017 added). Pinning 1017 drops its own hold, and only its own:
  # the hold of 1006, the other window with that title, stays in its cell. The copy is served by a second dry-run server.
  $fxDup = Join-Path $run 'fixture-dup.json'
  $fxDupDoc = Get-Content -Raw -Encoding UTF8 -LiteralPath $fixture | ConvertFrom-Json
  $fxDupDoc.windows = @($fxDupDoc.windows) + [pscustomobject]@{ id = 1017; app = 'chrome'; title = 'Quarterly roadmap - Example'; x = 300; y = 200; w = 1400; h = 1000 }
  [IO.File]::WriteAllText($fxDup, (ConvertTo-Json -Depth 10 -Compress $fxDupDoc), $utf8)
  $dupPair = SlStartServer $fxDup (Join-Path $run 'home-dup'); $srvDup = $dupPair[0]; $urlMain = $script:url; $script:url = $dupPair[1]
  SlCase (SlSceneJson '[]' '["*"]' '' (SlHeldFill '[{"id":1006,"app":"chrome","title":"Quarterly roadmap - Example","mon":"wide","slots":[2]},{"id":1017,"app":"chrome","title":"Quarterly roadmap - Example","mon":"wide","slots":[3]}]'))
  $dScope = SlList 'work[selId].fill.held'
  Check 'same title, scope: both windows with the title are held, one entry each' (@($dScope | ? { "$($_.app)" -eq 'chrome' }).Count -eq 2) "fill.held: $(SlShort $dScope)"
  SlJs "(() => { pinWin(1017, snap.monitors.find(m => m.role === 'wide'), 8); return true; })()"; SlSettle
  $dAfter = SlList 'work[selId].fill.held'
  $dIds = @($dAfter | % { [int]$_.id }) -join ','; if (-not $dIds) { $dIds = 'none' }
  Check 'same title: pinning 1017 drops its own hold' (-not @($dAfter | ? { [int]$_.id -eq 1017 }).Count) "held ids after the pin: $dIds"
  Check 'same title: pinning 1017 keeps the hold of 1006, the other window with that title' (@($dAfter | ? { [int]$_.id -eq 1006 }).Count -eq 1) "held ids after the pin: $dIds"
  [void](Invoke-WebRequest -UseBasicParsing "$($script:url)quit" -Method Post -Body 'quit'); [void]$srvDup.WaitForExit(5000)
  $script:url = $urlMain
  SlViewport 1440 900
} catch {
  $script:fail++; "FAIL  run stopped: $_ (line $($_.InvocationInfo.ScriptLineNumber))"
} finally {
  # Only the browsers this run started: each one's command line names this run's profile folder.
  Get-CimInstance Win32_Process -Filter "Name='msedge.exe'" | ? { $_.CommandLine -like "*$($script:udd)*" } | % { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
  if ($script:ws) { $script:ws.Dispose() }
  if ($srv -and -not $srv.HasExited) { $srv.Kill() }
  if ($srvDup -and -not $srvDup.HasExited) { $srvDup.Kill() }
  foreach ($k in $savedEnv.Keys) { if ($null -eq $savedEnv[$k]) { Remove-Item "env:$k" -ErrorAction SilentlyContinue } else { Set-Item "env:$k" $savedEnv[$k] } }
  if (Test-Path -LiteralPath $run) { Remove-Item -LiteralPath $run -Recurse -Force -ErrorAction SilentlyContinue }
}
if ($script:fail) { "$($script:fail) check(s) failed."; exit 1 } else { 'All checks passed.' }
