# Checks for stack (Put Behind, Bring to Front, Take Out), lock, resize by the corner grip, and the drop on a spanned block.
# Engine cases run tile.ps1 -Scene on the fixture. Page cases drive the real board with pointer events, in headless Edge
# over the DevTools protocol, on a dry-run server (nothing moves), then read the scene and the tile boxes back. A red
# case fails on its outcome: the scene or the boxes end up wrong. A missing control only makes the drag do nothing.
# Page load (before the Sora cases): one dropped snapshot fetch must not leave the board empty.
# Preview POST (after the page load cases): previewRun sends its POST again once, after a short wait, when the first is a dropped
# connection (a TypeError). A 500 reply and an unreadable 200 reply are not sent again. The cases call preview(id) and read prevs, selId and #msg.
# Run alone: powershell -NoProfile -ExecutionPolicy Bypass -File test\stack-lock.ps1
# test\run.ps1 runs this file in a child powershell and counts its FAIL lines.
#
# Shards: -Shard n -Of 3 runs one third of the cases (test\shard.ps1). test\run.ps1 runs the three in three processes, each with its
# own page session, Edge and server. With no arguments every case runs in one process.
# Interface the builder must meet (what these cases read and drive):
#   Scene JSON (config.json scenes, the page's work[id], tile.ps1 -Scene):
#     pins[i].lock    true on a locked tile. It never moves on a swap, a zone, the fill, or a resize that would cover it.
#     pins[i].behind  [{app, match}]: windows stacked behind pins[i]. match reads as on a pin: text in the window title.
#                     They share pins[i]'s rect and are never in the fill.
#     pins[i].slots   a span is the whole block of cells, as today.
#     bay             [{app, title}], as today. Take Out writes here, and so does a resize: every window its span covers goes
#                     here with its stack, whether or not a cell is free (ruling 2026-11-16, decisions/stack-and-lock.md).
#   tile.ps1 -Scene -From <fixture> -Json, placed[]: a stacked window has behind = true, pin = its front pin's index,
#     and slots, x, y, w, h equal to the front's. A minimized stacked window is placed too (Apply restores it).
#   app.html, names read by the harness (keep them): work, selId, prevs, preview(id), els (window id -> its tile element,
#     dataset.id), snap, stage, cellRect(mon, grid, c, r, cs, rs) with px(rect) (a cell's rect, as the drop label uses it),
#     and the Save button with id save.
#   app.html DOM the harness drives:
#     Every window is a .tile. A locked tile's lock button is .tile .lk. The resize grip is .tile .rsz, bottom-right.
#     #drop holds the drop label. On a taken block (a cell or a span) it draws one Swap circle, #drop .swc, centred on the
#     block, with diameter half the block's short side, rounded down, from 28 to 64 px. A drop inside the circle (distance
#     from the block's centre) swaps; anywhere else on the block it puts behind. Nothing else is a zone (ruling 2026-11-16).
#     A span is one block: its circle sits at the centre of the whole span and it never reads Place here.
#     On a locked tile the whole cell is Put Behind: it reads Behind and "Locked, so no Swap" (Locked on narrow cells),
#     with no circle and no Swap action.
#     The inspector, for the selected front tile, has a Bring to Front and a Take Out button for each window behind it.
#     A grip drag of 1.4 cells to the right, on a 1x1 tile, makes a 2-column span (whole cells, rounded).
#     Shift+arrow and the Width and Height steppers grow a span the same way as the grip: every covered pin goes to Windows
#     That Stay Put with its stack, its chip's aria-label reads "Covered by a resize" (ruling 2026-11-16), and growth stops at
#     a locked tile. A resize that covers windows also writes a Drop Note: .dnote, role=status, text "<A> and <B> went to
#     Windows That Stay Put", with a button Undo inside it.
#     .tile .lk (the padlock). Shown only on hover, on focus inside the tile (:focus-within) and on a selected tile, and
#     always on a locked tile. Hidden, it is visibility:hidden, so elementFromPoint at its centre is not the padlock.
#     [role=alertdialog] (a locked tile dragged and released: an in-page confirm). Its buttons: "Cancel" (the tile stays put,
#     still locked) and "Move It" (the tile moves to the cell it was released on, still locked). Nothing moves before Move It.
#     While that warning is open over a taken cell, the pending tile (.pendtile, pointer-events none) waits in that cell, and
#     only one title in the cell reads: the taken tile's title is hidden, or the pending tile is opaque. The warning sits outside the cell.
#     Ctrl+click (ctrlKey) picks a tile or an empty cell. Two or more picks draw .mbar (role=group, aria-label "Picked
#     cells"), with buttons "Merge", "Cancel" and "Fill to Rectangle". A rectangle's Merge makes a span kept by the first
#     picked window; the other picked windows go to Windows That Stay Put. A non-rectangle disables Merge (disabled
#     attribute), with its reason in the bar's text, and Fill to Rectangle adds the missing cells to the pick. Picks made
#     only of empty cells disable Merge too, with its reason in the bar's text.
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
#                        covered pins go to Windows That Stay Put with their stacks (ruling 2026-11-16); a locked tile stops
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
#                        With fill off, every open window that is not pinned has the reason "fill is off" (engine left[]) and is shown
#                        as "Fill is off" in the list, on its own line or in its category heading, whatever its app: an app with a pinned window included.
#                        A tab click on another scene while the switch waits for its scene's preview leaves that scene as it was:
#                        the switch changes the scene it was pressed on.
#     inspector          A narrow pinned tile (its pin mark hidden at 1024) selected: its "Pinned" line is in the inspector's visible area.
#   Ruling 2026-11-16 (lock correction 10:20; coordinator picks 10:53), review findings on 1ff9835:
#     a locked window dragged to Windows That Stay Put, or put behind, loses its lock; the window that takes its pin is not locked.
#     A covered pin whose window is closed (no open window) is removed by a resize or a Merge, a Drop Note names its app, and
#     Undo restores the pin. Merge refuses a pick that holds a closed locked pin, as a resize stops at a lock; the pin keeps its lock.
#     A Merge's bay entries carry why "Moved by a merge" (a resize's carry "Covered by a resize").
#     Two windows of one app are named apart in the Drop Note, the status line (#msg), the locked-drag warning (#lcp) and the
#     Merge bar: by title ("Refactor", "Pin parser") or as "2 Claude windows", never "Claude moves to Claude".
#     On a 2x1 span at 1024 the Put Behind label's text box (#drop > span) does not meet the Swap circle, and its chip is not
#     clipped: scrollWidth is within clientWidth (the chip's words fit it).
#     The Put Behind label takes the longest form that fits clear of the Swap circle: beside it, else the bottom right corner with
#     the word Behind, else the icon alone. Never under or over the circle. With Google Fonts loaded (Sora in use), on a 2x1 span and
#     a 1x1 cell at 1024 and 1440, its box does not meet the circle's box and it is not clipped (the Sora cases at the end).
#     Forced colours (forced-colors: active): a missing cell (.miss) keeps a visible border, and the disabled Merge button reads as
#     disabled (forced-color-adjust: none, or the computed colour is GrayText).
#     Ruling 2026-11-16 13:29 CST: a block with no room clear of the Swap circle, even for the icon at 8 px or more, shows no Put
#     Behind label. Its solid border and the circle carry the cue. Forced colours drops box-shadow, so the icon-alone chip has a border.
#   Run folders: one per run, under <TEMP>\tile-windows-test-runs, named <pid>-<UUID>. A run removes siblings older than a day.

param([int]$Shard = 1, [int]$Of = 1)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
$tile = Join-Path $root 'tile.ps1'; $serve = Join-Path $root 'serve.ps1'; $fixture = Join-Path $PSScriptRoot 'fixture.json'
$utf8 = New-Object Text.UTF8Encoding $false
$script:fail = 0
# Shards (test\shard.ps1): each case is one Shard-Take gate, numbered in file order, and the file pins its gate total (253). Shard 1 runs
# gates 1 to 67 (the cases before the Board feedback section), shard 2 gates 68 to 171 (before the stack tweaks ruling section), shard 3
# the rest. Each shard starts its own page session.
$shardCuts = @(67, 171)
. (Join-Path $PSScriptRoot 'shard.ps1')
Shard-Init $Shard $Of @($shardCuts | Select-Object -First ($Of - 1)) 253
function Check($name, $ok, $detail = '') { if ($ok) { "PASS  $name" } else { $script:fail++; "FAIL  $name  $detail" } }

# Run folders (test-temp-standard): one folder per run, <pid>-<UUID>, under one temp root. The first request of a run
# removes sibling run folders older than one day, and keeps newer ones.
$SlTempRoot = Join-Path $env:TEMP 'tile-windows-test-runs'
$SlRunName = '^\d+-[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
. (Join-Path $PSScriptRoot 'run-folders.ps1')
function SlSweep($dir, $olderThan) { Invoke-RunFolderSweep $dir $SlRunName $olderThan }
# The sweep, proven on its own folder: an old run folder goes, a new one stays.
$proof = Join-Path $env:TEMP ('tile-windows-sweep-proof-' + [guid]::NewGuid().ToString())
New-Item -ItemType Directory $proof | Out-Null
$oldRun = Join-Path $proof ('1-' + [guid]::NewGuid().ToString()); $newRun = Join-Path $proof ('2-' + [guid]::NewGuid().ToString())
New-Item -ItemType Directory $oldRun | Out-Null; New-Item -ItemType Directory $newRun | Out-Null
(Get-Item -LiteralPath $oldRun).LastWriteTime = (Get-Date).AddDays(-2)
SlSweep $proof ([TimeSpan]::FromDays(1))
  if (Shard-Take) {
Check 'run folders: the sweep removes a run folder older than a day' (-not (Test-Path -LiteralPath $oldRun))
Check 'run folders: the sweep keeps a run folder newer than a day' (Test-Path -LiteralPath $newRun)
  }
# A run folder whose path is past 260 characters (an Edge profile nests that deep): the sweep removes it too.
$longRun = Join-Path $proof ('3-' + [guid]::NewGuid().ToString()); New-Item -ItemType Directory $longRun | Out-Null
$longDeep = $longRun; for ($i = 0; $i -lt 6; $i++) { $longDeep = Join-Path $longDeep ('d' * 60) }
[IO.Directory]::CreateDirectory('\\?\' + $longDeep) | Out-Null
(Get-Item -LiteralPath $longRun).LastWriteTime = (Get-Date).AddDays(-2)
SlSweep $proof ([TimeSpan]::FromDays(1))
  if (Shard-Take) {
Check 'run folders: the sweep removes an old run folder whose path is past 260 characters' (-not [IO.Directory]::Exists('\\?\' + $longRun)) "path length $($longDeep.Length)"
  }
Remove-RunFolder $proof

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
  if (Shard-Take) {
Check 'stack: a back window is placed on its front window''s rect, marked behind, in the front pin' ($eSame -and $eBack.behind -eq $true -and $eBack.pin -eq 0) "front: $($eFront | ConvertTo-Json -Compress) back: $($eBack | ConvertTo-Json -Compress)"
Check 'stack: Apply places a minimized back window (it is restored, not left minimized)' ([bool]($eBack -and $eBack.from.x -le -20000)) "back: $($eBack | ConvertTo-Json -Compress)"
  }

$eOnce = SlPlace (SlSceneJson (SlPins '{"app":"chrome","match":"Quarterly","mon":"wide","slots":[3],"behind":[{"app":"claude","match":"Refactor"}]}') '["*"]')
$eCl = @($eOnce.placed | ? { $_.id -eq 1001 })
  if (Shard-Take) {
Check 'stack: a stacked window is placed once, on its front window''s cell, and the fill does not take it' ($eCl.Count -eq 1 -and $eCl[0].behind -eq $true -and ($eCl[0].slots -join ',') -eq '4') "claude placements: $($eCl | ConvertTo-Json -Compress)"
  }

$eSpan = SlPlace (SlSceneJson (SlPins '{"app":"chrome","match":"Quarterly","mon":"wide","slots":[0,1,5,6]}'))
$eSpanCh = @($eSpan.placed | ? { $_.id -eq 1006 })[0]
  if (Shard-Take) {
Check 'control: a span pin places its whole 2x2 block (as today)' ([bool]($eSpanCh -and ($eSpanCh.slots -join ',') -eq '1,2,6,7')) "chrome: $($eSpanCh | ConvertTo-Json -Compress)"
  }

# ---------- Page: headless Edge over DevTools, on a dry-run server ----------
$edgeExe = @("${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe", "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe") | ? { Test-Path -LiteralPath $_ } | Select-Object -First 1
if (-not $edgeExe) { 'SKIP  page cases: Microsoft Edge not found in either Program Files folder.'; Shard-Skip 'no Microsoft Edge'; Shard-Report 'stack-lock'; if ($script:fail) { "$($script:fail) check(s) failed."; exit 1 } else { exit 0 } }

# One run folder, and a temp profile for every child: the real profile is never named.
[void](New-Item -ItemType Directory -Force $SlTempRoot)
# Shard 1 only: the shards would race to remove the same old run folders.
if ($script:shardNo -eq 1) { SlSweep $SlTempRoot ([TimeSpan]::FromDays(1)) }
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
# Ruling 2026-11-16 helpers (stack tweaks). Ctrl+click: CDP modifier Ctrl is 2, so the pointer events carry ctrlKey.
function SlCtrlClick($at) {
  [void](SlSend 'Input.dispatchMouseEvent' @{ type = 'mousePressed'; x = [double]$at[0]; y = [double]$at[1]; button = 'left'; buttons = 1; clickCount = 1; modifiers = 2 })
  [void](SlSend 'Input.dispatchMouseEvent' @{ type = 'mouseReleased'; x = [double]$at[0]; y = [double]$at[1]; button = 'left'; buttons = 0; clickCount = 1; modifiers = 2 })
  SlSettle }
# A block of wide-monitor cells, cs by rs from cell $slot (0-based), in the viewport: the rect the drop label is drawn on.
function SlBlock($slot, $cs = 1, $rs = 1) { SlGet "(() => { const m = snap.monitors.find(q => q.role === 'wide'), g = work[selId].grids.wide, p = px(cellRect(m, g, $slot % g.c, Math.floor($slot / g.c), $cs, $rs)), sr = stage.getBoundingClientRect(); return { l: sr.left + parseFloat(p.left), t: sr.top + parseFloat(p.top), w: parseFloat(p.width), h: parseFloat(p.height) }; })()" }
# Moves the pointer to the page's top-left corner, where no tile is, so no hover is left on a window.
function SlPark { SlMouse 'mouseMoved' 1 1 0; SlFrame }
# Whether window $id's padlock is drawn and visible: not display none, not visibility hidden, opacity above 0. Null when no padlock.
function SlLkShown($id) { SlGet "(() => { const t = els.get($id), k = t && t.querySelector('.lk'); if (!k) return null; const cs = getComputedStyle(k), r = k.getBoundingClientRect(); return cs.display !== 'none' && cs.visibility === 'visible' && parseFloat(cs.opacity) > 0 && r.width > 0; })()" }
# Whether the element the page hits at window $id's padlock centre is that padlock. A hidden padlock is not hit.
function SlLkHit($id) { SlGet "(() => { const t = els.get($id), k = t && t.querySelector('.lk'); if (!k) return null; const r = k.getBoundingClientRect(), e = document.elementFromPoint(r.left + r.width / 2, r.top + r.height / 2); return !!(e && e.closest('.lk') === k); })()" }
# The centre of window $id's padlock, as [x, y] in the viewport (null when none).
function SlLkCentre($id) { SlGet "(() => { const t = els.get($id), k = t && t.querySelector('.lk'); if (!k) return null; const r = k.getBoundingClientRect(); return [r.left + r.width / 2, r.top + r.height / 2]; })()" }
# A button's state inside $scope, found by its text: 'no such button', 'disabled' or 'enabled'.
function SlBtnState($scope, $text) { SlJs "(() => { const b = [...document.querySelectorAll('$scope button')].find(x => x.textContent.trim() === '$text'); if (!b) return 'no such button'; return b.disabled ? 'disabled' : 'enabled'; })()" }
# A real press on a button inside $scope, found by its text. False when it is missing or disabled (nothing is pressed).
function SlBtnPress($scope, $text) {
  $c = SlGet "(() => { const b = [...document.querySelectorAll('$scope button')].find(x => x.textContent.trim() === '$text'); if (!b || b.disabled) return null; const r = b.getBoundingClientRect(); return [r.left + r.width / 2, r.top + r.height / 2]; })()"
  if (-not $c) { return $false }
  SlClick @([double]$c[0], [double]$c[1]); $true }
# One press on a taken block: the window $fromId is pressed at its centre and held over the point ($ox, $oy) from the block's
# centre, as fractions of the block's width and height, then released there. Reads the Swap circle and the drop label while held.
# -Sora also reads whether Sora is in use (SlSoraState) while the label is held.
# -Chip also reads the drop's state and its chip (SlDropState) while held. -fx and -fy move the press point on the source window.
function SlCircleDrop($fromId, $slot, $cs, $rs, $ox, $oy, [switch]$Sora, [double]$fx = 0.5, [double]$fy = 0.5, [switch]$Chip) {
  $bk = SlBlock $slot $cs $rs
  $to = @([double]($bk.l + $bk.w * (0.5 + $ox)), [double]($bk.t + $bk.h * (0.5 + $oy)))
  SlDrag (SlAt (SlBox $fromId) $fx $fy) $to -Hold
  $ci = SlGet "(() => { const c = document.querySelector('#drop .swc'); if (!c) return null; const r = c.getBoundingClientRect(); return { w: r.width, h: r.height, x: r.left + r.width / 2, y: r.top + r.height / 2 }; })()"
  $shown = SlLabelShown
  # The label's text box (its span's contents), read while held: the Put Behind or Swap label the drop shows.
  $lb = SlGet "(() => { const s = document.querySelector('#drop > span'); if (!s) return null; const r = document.createRange(); r.selectNodeContents(s); const b = r.getBoundingClientRect(); return { l: b.left, t: b.top, r: b.right, b: b.bottom, text: s.textContent.trim() }; })()"
  # The label's chip, read while held: its content width against the width it is drawn in. A chip narrower than its words clips them.
  $clip = SlGet "(() => { const s = document.querySelector('#drop > span'); if (!s) return null; const b = s.getBoundingClientRect(); return { sw: s.scrollWidth, cw: s.clientWidth, title: s.getAttribute('title') || '', text: s.textContent.trim(), icon: !!s.querySelector('svg'), box: { l: b.left, t: b.top, r: b.right, b: b.bottom } }; })()"
  $soraNow = $null; if ($Sora) { $soraNow = SlSoraState }
  $dropNow = $null; if ($Chip) { $dropNow = SlDropState }
  SlRelease $to
  [pscustomobject]@{ block = $bk; circle = $ci; shown = $shown; to = $to; label = $lb; clip = $clip; sora = $soraNow; drop = $dropNow } }
# The drop, read while held: #drop's class and border (the Put Behind zone is class "on", with a 3px border), forced colours, and
# the chip inside it when one is drawn: its box, its border, its text and whether it holds an icon. A chip is shown only when #drop is.
function SlDropState {
  SlGet "(() => { const d = document.getElementById('drop'), dc = getComputedStyle(d), s = d.querySelector(':scope > span'); const out = { shown: dc.display !== 'none', cls: d.className, bw: parseFloat(dc.borderTopWidth), fc: matchMedia('(forced-colors: active)').matches, chip: null }; if (s) { const cs = getComputedStyle(s), r = s.getBoundingClientRect(); out.chip = { shown: out.shown && cs.display !== 'none' && cs.visibility !== 'hidden' && parseFloat(cs.opacity) > 0 && r.width > 0 && r.height > 0, bs: cs.borderTopStyle, bw: parseFloat(cs.borderTopWidth), box: { l: r.left, t: r.top, r: r.right, b: r.bottom }, text: s.textContent.trim(), icon: !!s.querySelector('svg') }; } return out; })()"
}
# Whether Sora is in use for the drop label, read while it is held. The label's font stack starts with Sora, a Sora face has
# loaded (read after document.fonts.ready, so a face still downloading is not read as missing), and the 600 weight the label sets
# is available. A page on its fallback font reads on = false, so the case that asks fails its scope.
function SlSoraState {
  $r = SlJs "(async () => { await document.fonts.ready; const lab = document.querySelector('#drop > span'); const faces = [...document.fonts].filter(f => /sora/i.test(f.family)); return JSON.stringify({ stack: lab ? getComputedStyle(lab).fontFamily : '', loaded: faces.filter(f => f.status === 'loaded').map(f => f.weight), check: document.fonts.check('600 12px Sora') }); })()"
  if (-not $r) { return [pscustomobject]@{ on = $false; stack = ''; loaded = @(); check = $false } }
  $o = $r | ConvertFrom-Json
  $loaded = @($o.loaded)
  [pscustomobject]@{ on = [bool](("$($o.stack)" -match '^\s*"?Sora') -and $loaded.Count -gt 0 -and $o.check -eq $true); stack = "$($o.stack)"; loaded = $loaded; check = $o.check }
}
# One Put Behind drop on a taken block, with Sora loaded. Scope first: Sora is in use, and the label and the Swap circle are drawn,
# in a form with the word Behind or as the icon alone. Then the label's box must not meet the circle's box, and the label must not clip.
function SlSoraCase($w, $h, $shape, $fromId, $cs, $pins) {
  SlViewport $w $h; SlCase (SlSceneJson $pins)
  $d = SlCircleDrop $fromId 0 $cs 1 0 (-0.35) -Sora
  $tag = "label, Sora, $w $shape"
  $ci = $d.circle
  $cb = if ($ci) { @{ l = $ci.x - $ci.w / 2; t = $ci.y - $ci.h / 2; r = $ci.x + $ci.w / 2; b = $ci.y + $ci.h / 2 } } else { $null }
  $lb = if ($d.clip) { $d.clip.box } else { $null }
  $text = if ($d.label) { "$($d.label.text)" } else { '' }
  $form = [bool]($text -match 'Behind' -or ($text -eq '' -and $d.clip -and $d.clip.icon))
  Check "$tag, scope: Sora is in use, and the Put Behind label and the Swap circle are drawn, as a form with Behind or the icon alone" ([bool]($d.sora -and $d.sora.on -and $d.shown -and $cb -and $lb -and $form)) "sora: $(SlShort $d.sora); shown: $($d.shown); label: $(SlShort $d.label); text: '$text'"
  Check "$tag, red: the label's box does not meet the Swap circle's box" ([bool]($cb -and $lb -and -not (SlMeets $lb $cb))) "label box: $(SlHit $lb); circle box: $(SlHit $cb)"
  Check "$tag, red: the label is not clipped (scrollWidth within clientWidth)" ([bool]($d.clip -and $d.clip.sw -le $d.clip.cw)) "scrollWidth: $($d.clip.sw); clientWidth: $($d.clip.cw); text: '$text'"
}
# One Put Behind drop with forced colours on, under Sora. Ruling 2026-11-16 12:45 CST accepts the icon alone, and in forced colours
# the browser drops box-shadow, so the icon-alone chip needs a real border to read as a chip. Scope first: forced colours is on, Sora
# is in use, and the label is drawn as the icon alone. Then the chip has a border: a style other than none, at least 1 px wide.
function SlForcedCase($w, $h, $shape, $fromId, $cs, $pins) {
  SlSend 'Emulation.setEmulatedMedia' @{ features = @(@{ name = 'forced-colors'; value = 'active' }) }
  SlViewport $w $h; SlCase (SlSceneJson $pins)
  $d = SlCircleDrop $fromId 0 $cs 1 0 (-0.35) -Sora -Chip
  $ch = $d.drop.chip
  $tag = "label, forced colours, Sora, $w $shape"
  $icon = [bool]($ch -and $ch.icon -and $ch.text -eq '')
  Check "$tag, scope: forced colours is on, Sora is in use, and the Put Behind label is drawn as the icon alone" ([bool]($d.drop.fc -eq $true -and $d.sora -and $d.sora.on -and $ch -and $ch.shown -and $icon)) "forced: $($d.drop.fc); sora: $(SlShort $d.sora); chip: $(SlShort $ch)"
  Check "$tag, red: the icon-alone chip has a visible edge (a border not none, at least 1 px), since box-shadow is dropped in forced colours" ([bool]($ch -and $ch.bs -ne 'none' -and $ch.bw -ge 1)) "chip border: $($ch.bs) $($ch.bw)px"
  SlSend 'Emulation.setEmulatedMedia' @{ features = @() }
}
# The Swap circle is half the block's short side, rounded down, from 28 to 64 px, and centred on the block (tolerance 2 px).
function SlCircleFits($c, $bk) {
  if (-not $c -or -not $bk) { return $false }
  $want = [Math]::Max(28, [Math]::Min(64, [Math]::Floor([Math]::Min($bk.w, $bk.h) / 2)))
  [bool]([Math]::Abs($c.w - $want) -le 2 -and [Math]::Abs($c.h - $want) -le 2 -and [Math]::Abs($c.x - ($bk.l + $bk.w / 2)) -le 2 -and [Math]::Abs($c.y - ($bk.t + $bk.h / 2)) -le 2) }
# Whether the Swap circle (centre x, y, diameter w) and a label's text box (l, t, r, b) share a point: the distance from the
# circle's centre to the nearest point of the box is under its radius. The bounding square is not the test.
function SlCircleMeets($c, $r) {
  if (-not $c -or -not $r) { return $false }
  $nx = [Math]::Max($r.l, [Math]::Min($c.x, $r.r)); $ny = [Math]::Max($r.t, [Math]::Min($c.y, $r.b))
  [bool]([Math]::Sqrt(($c.x - $nx) * ($c.x - $nx) + ($c.y - $ny) * ($c.y - $ny)) -lt ($c.w / 2)) }
# The titles in one cell, as a reader sees them: the pending tile's title and the taken tile's title ($takenId's element). A title
# reads when it is drawn (not display:none, not visibility:hidden, not opacity 0) and some point of its box has no opaque layer
# above it. A translucent layer over a title does not hide it: the title shows through. The pending tile is pointer-events:none, so
# it is switched on for each hit test, then put back. Returns the readable count and both boxes (l, t, r, b), or null for a missing one.
function SlTitles($takenId) {
  $js = @'
(() => {
  const num = (s) => { const v = parseFloat(s); return isNaN(v) ? 0 : v; };
  const parseA = (p) => (p.endsWith('%') ? parseFloat(p) / 100 : parseFloat(p));
  const alphaOf = (s) => {
    if (!s || s === 'transparent') return 0;
    const m = /^(rgba?|color)\((.*)\)$/.exec(s);
    if (!m) return 1;
    const parts = m[2].replace(/^srgb\s+/, '').replace(/,/g, ' ').split(/\s*\/\s*|\s+/).filter(Boolean);
    return parts.length > 3 ? parseA(parts[3]) : 1;
  };
  const effOpacity = (e) => { let o = 1; for (let n = e; n && n.nodeType === 1; n = n.parentElement) o *= num(getComputedStyle(n).opacity); return o; };
  const opaque = (e) => effOpacity(e) >= 0.999 && alphaOf(getComputedStyle(e).backgroundColor) >= 0.999;
  const pends = [...document.querySelectorAll('.pendtile')];
  const coveredAt = (e, x, y) => {
    pends.forEach((p) => { p.style.pointerEvents = 'auto'; });
    const list = document.elementsFromPoint(x, y);
    pends.forEach((p) => { p.style.pointerEvents = ''; });
    const i = list.indexOf(e);
    if (i < 0) return false;
    for (let k = 0; k < i; k++) {
      const o = list[k];
      if (o.contains(e) || e.contains(o)) continue;
      if (opaque(o)) return true;
    }
    return false;
  };
  const readable = (e) => {
    if (!e || getComputedStyle(e).visibility !== 'visible' || effOpacity(e) <= 0) return false;
    const r = e.getBoundingClientRect();
    if (r.width <= 0 || r.height <= 0) return false;
    const pts = [[r.left + r.width / 2, r.top + r.height / 2], [r.left + 1, r.top + 1], [r.right - 1, r.top + 1], [r.left + 1, r.bottom - 1], [r.right - 1, r.bottom - 1]];
    return pts.some(([x, y]) => !coveredAt(e, x, y));
  };
  const box = (e) => { if (!e) return null; const r = e.getBoundingClientRect(); return { l: r.left, t: r.top, r: r.right, b: r.bottom, w: r.width, h: r.height }; };
  const taken = els.get(__ID__), tt = taken ? taken.querySelector(':scope > span') : null;
  const pend = document.querySelector('.pendtile'), pt = pend ? pend.querySelector(':scope > span') : null;
  const dlg = document.querySelector('[role=alertdialog]');
  const pr = readable(pt), tr = readable(tt);
  return { pendText: pt ? pt.textContent : null, takenText: tt ? tt.textContent : null, pendReadable: pr, takenReadable: tr, n: (pr ? 1 : 0) + (tr ? 1 : 0), pendOpacity: pend ? effOpacity(pend) : null, pendBox: box(pend), takenBox: box(taken), dlgBox: box(dlg), dlgOpen: !!dlg };
})()
'@
  SlGet ($js.Replace('__ID__', "$takenId"))
}
# Two windows of one app are named apart: both titles' words (Refactor, Pin parser), or "2 Claude windows". Either form passes.
function SlDistinct($text) { $t = "$text"; [bool](($t -match 'Refactor' -and $t -match 'Pin parser') -or $t -match '2 Claude windows') }
# What a drop of window $dragText on window $occText did, read from the scene: 'behind' when the dropped window is stacked
# behind it, 'swap:<dropped cells>/<occupant cells>' when they traded cells, else 'other'.
function SlZoneOutcome($dragText, $occText) {
  $s = SlGet 'work[selId]'; $d = SlPin $s $dragText; $o = SlPin $s $occText
  if ($o -and (SlHasBehind $o $dragText)) { return 'behind' }
  if ($d -and $o) { return "swap:$(SlCells $d)/$(SlCells $o)" }
  'other' }
# A press on handle $dir of the selected tile, released with no settle, so the Drop Note is read before it fades. $dx, $dy and $cells as SlHandleDrag.
function SlHandleDropNoSettle($dir, $dx, $dy, $cells = 1.4) {
  $hp = SlHandle $dir; $tb = SlBox 1001
  if (-not $hp -or -not $tb) { return $false }
  SlDropNoSettle @([double]$hp.x, [double]$hp.y) @([double]($hp.x + $dx * $cells * $tb.w), [double]($hp.y + $dy * $cells * $tb.h))
  $true }
# The bay chips of Windows That Stay Put as {id, label}: label is the chip's aria-label, which carries the reason.
function SlBayChips { SlList "[...document.querySelectorAll('#bgrps [data-bay]')].map(b => ({ id: +b.dataset.bay, label: b.getAttribute('aria-label') }))" }
# The number of tiles on the board (not hidden) whose padlock is drawn and visible.
function SlShownLocks { SlGet "[...document.querySelectorAll('.tile:not([hidden])')].filter(t => { const k = t.querySelector('.lk'); if (!k) return false; const cs = getComputedStyle(k); return cs.display !== 'none' && cs.visibility === 'visible' && parseFloat(cs.opacity) > 0; }).length" }
# The number of tiles on the board (not hidden).
function SlBoardTiles { SlGet "document.querySelectorAll('.tile:not([hidden])').length" }
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
# Sets the config to one scene (id sl), then loads the page on it. -Soft and -Polls pass through to SlLoad.
function SlCase($sceneJson, [switch]$Soft, [int]$Polls = 3) {
  $cfg = (Invoke-WebRequest -UseBasicParsing "$($script:url)config").Content | ConvertFrom-Json
  $cfg.scenes = @((ConvertFrom-Json $sceneJson))
  $body = ConvertTo-Json -Depth 12 -Compress $cfg
  if ((Invoke-WebRequest -UseBasicParsing "$($script:url)config" -Method Post -ContentType 'application/json; charset=utf-8' -Body ($utf8.GetBytes($body))).Content -ne 'Saved') { throw 'the config was not saved' }
  SlLoad -Soft:$Soft -Polls $Polls
}
# Loads (or reloads) the page from the server's config, and waits (in the page) until the scene is drawn and settled.
# -Soft returns { ready, diag } instead of throwing when no scene comes, so a case checks it as a result. -Polls is the number of 30 s waits.
function SlLoad([switch]$Soft, [int]$Polls = 3) {
  $before = SlJs 'String(performance.timeOrigin)'
  [void](SlSend 'Page.navigate' @{ url = $script:url })
  $ready = $null; $tries = 0; $script:jsErr = ''
  while (-not $ready -and $tries -lt $Polls) {
    $tries++
    $ready = SlJs "new Promise((res, rej) => { const t0 = Date.now(); (function poll() { if (String(performance.timeOrigin) !== '$before' && typeof snap === 'object' && snap && selId && prevs[selId] && document.querySelectorAll('.tile').length) return res(true); if (Date.now() - t0 > 30000) return rej(new Error('no scene after 30 s')); setTimeout(poll, 100); })(); })"
  }
  if (-not $ready) {
    $diag = SlJs "JSON.stringify({ snap: typeof snap === 'object' && !!snap, selId: typeof selId === 'string' ? selId : null, drawn: typeof prevs === 'object' && !!selId && !!prevs[selId], tiles: document.querySelectorAll('.tile').length, url: location.href, msg: (document.getElementById('msg') || {}).textContent })"
    if ($Soft) { return [pscustomobject]@{ ready = $false; diag = "$script:jsErr $diag" } }
    throw "the page did not draw the scene: $script:jsErr $diag"
  }
  SlSettle
  if ($Soft) { [pscustomobject]@{ ready = $true; diag = '' } }
}
# Page load fault (app.html loadAll): a fetch wrapper, registered before the page's own scripts run, that fails the snapshot request.
# -mode 'once' fails the first one only, counted in sessionStorage under $key; 'always' fails every one. Returns the id to remove it with.
function PlFaultOn([string]$mode, [string]$key) {
  $src = @'
(() => {
  const KEY = '__KEY__', MODE = '__MODE__', orig = window.fetch;
  window.fetch = function (input, init) {
    const u = String(typeof input === 'string' ? input : (input && input.url) || input);
    if (/(^|\/)snapshot(\?|$)/.test(u)) {
      let n = 0;
      try { n = Number(sessionStorage.getItem(KEY) || 0); } catch (e) {}
      if (MODE === 'always' || n === 0) {
        try { sessionStorage.setItem(KEY, String(n + 1)); } catch (e) {}
        return Promise.reject(new TypeError('Failed to fetch'));
      }
    }
    return orig.apply(this, arguments);
  };
})();
'@
  $src = $src.Replace('__KEY__', $key).Replace('__MODE__', $mode)
  # The Page domain must be on for the session to run new-document scripts; without it the wrapper never reaches the page.
  [void](SlSend 'Page.enable' @{})
  $r = SlSend 'Page.addScriptToEvaluateOnNewDocument' @{ source = $src }
  "$($r.result.identifier)"
}
function PlFaultOff($id) { if ($id) { [void](SlSend 'Page.removeScriptToEvaluateOnNewDocument' @{ identifier = $id }); [void](SlSend 'Page.disable' @{}) } }
# Preview POST fault (app.html previewRun): loads the one-scene page, then wraps fetch in the page so the scene's POSTs to /preview
# meet -mode, and runs one preview(id) of it. The wrapper is armed after the load, so the page's own previews are neither failed nor
# counted (PlFaultOn is a new-document script for the snapshot request, set before the load, and counts failures, not every POST; it
# cannot arm late, answer with a status or a body, or count the POSTs the cases here compare). Modes: 'drop-once' (the first POST is a
# TypeError, as a dropped connection gives; later ones go on to the server), 'drop-always', 'status500' (a 500 reply with a text) and
# 'badbody' (a 200 reply that is not JSON). The call is capped at 20 s in the page. Returns the page's read; ok is the scope: the page
# held the scene's preview with none in flight, the wrapper saw a POST, and the call finished.
function PvDrive([string]$mode) {
  $ld = SlCase (SlSceneJson '[]' '["*"]') -Soft
  if (-not $ld.ready) { return [pscustomobject]@{ ready = $false; ok = $false; diag = "the page did not draw the scene: $($ld.diag)" } }
  $arm = @'
(() => {
  const MODE = '__MODE__', ID = selId, orig = window.fetch;
  window.__pvOrig = orig;
  window.__pv = { id: ID, posts: 0, before: !!prevs[ID], idle: !inflight[ID], old: prevs[ID] };
  window.fetch = function (input, init) {
    const u = String(typeof input === 'string' ? input : (input && input.url) || input);
    let bid = null;
    try { bid = JSON.parse(init.body).id; } catch (e) {}
    if (/(^|\/)preview(\?|$)/.test(u) && init && init.method === 'POST' && bid === ID) {
      const n = ++window.__pv.posts;
      if (MODE === 'drop-always' || (MODE === 'drop-once' && n === 1)) return Promise.reject(new TypeError('Failed to fetch'));
      if (MODE === 'status500') return Promise.resolve(new Response('Server out of order.', { status: 500 }));
      if (MODE === 'badbody') return Promise.resolve(new Response('not json', { status: 200 }));
    }
    return orig.apply(this, arguments);
  };
  return true;
})()
'@
  $drive = @'
(async () => {
  const p = window.__pv;
  const done = await Promise.race([preview(p.id).then(() => 'done'), new Promise(r => setTimeout(() => r('hung'), 20000))]);
  const now = prevs[p.id];
  return JSON.stringify({ done: done, posts: p.posts, before: p.before, idle: p.idle, drawn: !!now, fresh: !!now && now !== p.old && Array.isArray(now.placed), msg: document.getElementById('msg').textContent.trim() });
})()
'@
  try {
    $script:jsErr = ''
    $armed = SlJs ($arm.Replace('__MODE__', $mode))
    if (-not $armed) { return [pscustomobject]@{ ready = $false; ok = $false; diag = "the fault did not arm: $script:jsErr" } }
    $text = SlJs $drive
    if (-not $text) { return [pscustomobject]@{ ready = $false; ok = $false; diag = "the page read failed: $script:jsErr" } }
    $r = $text | ConvertFrom-Json
    [pscustomobject]@{ ready = $true; ok = [bool]($r.before -and $r.idle -and $r.posts -ge 1 -and $r.done -eq 'done'); diag = ''; done = $r.done; posts = $r.posts; before = $r.before; idle = $r.idle; drawn = $r.drawn; fresh = $r.fresh; msg = $r.msg }
  } finally {
    [void](SlJs "(() => { if (window.__pvOrig) { window.fetch = window.__pvOrig; delete window.__pvOrig; } return true; })()")
  }
}
# The detail line of a PvDrive scope check: each part of the scope on its own, so a failure names which one broke.
function PvWhy($pv) { "page drew the scene: $($pv.ready) $($pv.diag); had a preview: $($pv.before); none in flight: $($pv.idle); POSTs seen: $($pv.posts); call: $($pv.done)" }
function SlStartServer($from = $fixture, $tileHome = $env:TILE_HOME) {
  $psi = New-Object Diagnostics.ProcessStartInfo 'powershell', "-NoProfile -ExecutionPolicy Bypass -File `"$serve`" -NoBrowser -From `"$from`""
  $psi.UseShellExecute = $false; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true; $psi.CreateNoWindow = $true
  $psi.EnvironmentVariables['USERPROFILE'] = $profile; $psi.EnvironmentVariables['APPDATA'] = Join-Path $profile 'AppData\Roaming'; $psi.EnvironmentVariables['TILE_HOME'] = $tileHome
  $p = [Diagnostics.Process]::Start($psi)
  $line = $p.StandardOutput.ReadLineAsync(); if (-not $line.Wait(60000)) { throw 'the server did not print its URL' }
  @($p, $line.Result)
}
# -AllowFonts leaves Google Fonts reachable, so the page loads Sora. Without it the fonts are blocked, and the page runs on its fallback font.
function SlStartBrowser([switch]$AllowFonts) {
  New-Item -ItemType Directory -Force $script:udd | Out-Null
  $args2 = @('--headless', '--disable-gpu', '--no-first-run', '--remote-debugging-port=0', "--user-data-dir=$($script:udd)", '--window-size=1440,900')
  if (-not $AllowFonts) { $args2 += '--host-resolver-rules="MAP fonts.googleapis.com 0.0.0.0, MAP fonts.gstatic.com 0.0.0.0"' }
  $args2 += 'about:blank'
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
  if (Shard-Take) {
Check 'front gone, empty state: the open back window takes the front''s cell, as the new front' ([bool]$eGoneBack -and ($eGoneBack.slots -join ',') -eq '4' -and $eGoneBack.pin -eq 0 -and $eGoneBack.behind -ne $true) "back: $($eGoneBack | ConvertTo-Json -Compress)"
  }
$eFull = SlPlace (SlSceneJson $pinsFullFrontGone)
$eFullBack = @($eFull.placed | ? { $_.id -eq 1001 })[0]
  if (Shard-Take) {
Check 'front gone, full state: the open back window takes the front''s cell, as the new front' ([bool]$eFullBack -and ($eFullBack.slots -join ',') -eq '1' -and $eFullBack.pin -eq 0 -and $eFullBack.behind -ne $true) "back: $($eFullBack | ConvertTo-Json -Compress)"
  }

# Fill Empty Cells off (decisions/fill-controls.md), engine: off places only pins (locked or not, with their stacks), and zones place nothing.
$fillOff = ',"off":true'
$offPins = SlPins '{"app":"claude","match":"Refactor","mon":"wide","slots":[0],"lock":true,"behind":[{"app":"claude","match":"Draft release"}]}' '{"app":"chrome","match":"Quarterly","mon":"wide","slots":[1]}'
$offZone = ',"zones":[{"mon":"wide","slots":[5,6],"app":"WindowsTerminal"}]'
$fOff = SlDry (SlSceneJson $offPins '["*"]' $offZone $fillOff)
  if (Shard-Take) {
Check 'fill off: a dry run places no window the fill would place' (@($fOff.placed | ? { $_.pin -lt 0 }).Count -eq 0) (SlPl $fOff)
Check 'fill off: the pins, the locked one and its stack, are placed' (@($fOff.placed | ? { $_.pin -ge 0 }).Count -eq 3) (SlPl $fOff)
Check 'fill off: no zone places a window' (@($fOff.placed | ? { $_.zone -ge 0 }).Count -eq 0) (SlPl $fOff)
  }
$fEmpty = SlDry (SlSceneJson '[]' '["*"]' '' $fillOff)
  if (Shard-Take) {
Check 'fill off, no pins: a dry run places nothing' (@($fEmpty.placed).Count -eq 0) (SlPl $fEmpty)
  }
$fOn = SlDry (SlSceneJson $offPins '["*"]' $offZone)
  if (Shard-Take) {
Check 'control: fill on (no flag) still fills and zones, as today' (@($fOn.placed).Count -gt 3 -and @($fOn.placed | ? { $_.zone -ge 0 }).Count -ge 1) (SlPl $fOn)
  }
$fFull = SlDry (SlSceneJson $pinsFull '["*"]' '' $fillOff)
  if (Shard-Take) {
Check 'guard: fill off on a full board places the ten pins, as today' (@($fFull.placed).Count -eq 10 -and @($fFull.placed | ? { $_.pin -lt 0 }).Count -eq 0) (SlPl $fFull)
  }

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
  if (Shard-Take) {
foreach ($offState in $offStates) {
  $fo = SlDry (SlSceneJson $offState[1] '["*"]' '' $fillOff)
  $pinned = @($fo.placed | ? { $_.pin -ge 0 } | % { [int64]$_.id })
  $unpinned = @($fxOpen | ? { $pinned -notcontains $_ })
  $noReason = @($unpinned | ? { $id = $_; -not @($fo.left | ? { $_.id -eq $id -and $_.why -eq 'fill is off' }).Count })
  Check "fill off, $($offState[0]), scope: the pins are placed, and some open window is unpinned" ($pinned.Count -eq $offState[2] -and $unpinned.Count -gt 0) "pinned: $($pinned -join ','); unpinned: $($unpinned -join ',')"
  Check "fill off, $($offState[0]): every unpinned window has the reason 'fill is off'" ($noReason.Count -eq 0) "no 'fill is off' reason for: $($noReason -join ', ')"
}
  }

# Held layout (fill.held, decisions/fill-controls.md), engine. SlHeldFill sets the held layout by hand on a fill-off scene.
# SlSlotsOf gives a window's 1-based cells in a dry run, or 'none'. Each control is green on the head; each subject is the finding.
function SlHeldFill($held) { ',"off":true,"held":' + $held }
function SlSlotsOf($r, $id) { $p = @(@($r.placed) | ? { $_.id -eq $id })[0]; if ($p) { (@($p.slots) | Sort-Object) -join '+' } else { 'none' } }
$fxWins = @((Get-Content -Raw -Encoding UTF8 -LiteralPath $fixture | ConvertFrom-Json).windows)
# A held title that has changed: notepad has one window, so it matches by its app, as a pin does with no title text.
$hSame = SlDry (SlSceneJson '[]' '["*"]' '' (SlHeldFill '[{"app":"notepad","title":"todo.txt - Notepad","mon":"wide","slots":[0]}]'))
  if (Shard-Take) {
Check 'held, control: a held window whose title is unchanged is placed in its held cell' ((SlSlotsOf $hSame 1014) -eq '1') (SlPl $hSame)
  }
$hOld = SlDry (SlSceneJson '[]' '["*"]' '' (SlHeldFill '[{"app":"notepad","title":"Old todo title - Notepad","mon":"wide","slots":[0]}]'))
  if (Shard-Take) {
Check 'held, scope: notepad has one open window, which is not titled as held' (@($fxWins | ? { $_.app -eq 'notepad' }).Count -eq 1 -and @($fxWins | ? { $_.app -eq 'notepad' -and $_.title -eq 'Old todo title - Notepad' }).Count -eq 0) "notepad windows: $(@($fxWins | ? { $_.app -eq 'notepad' }).Count)"
Check 'held: a window whose title changed keeps its hold, as a pin does for the one window of its app' ((SlSlotsOf $hOld 1014) -eq '1') "notepad 1014 cells: $(SlSlotsOf $hOld 1014)"
  }
# A locked pin whose window is closed keeps its cell and its lock: no held window takes that cell.
$hClosedPin = SlPins '{"app":"closedapp","match":"","mon":"wide","slots":[0],"lock":true}'
$hOnPin = SlDry (SlSceneJson $hClosedPin '["*"]' '' (SlHeldFill '[{"app":"notepad","title":"todo.txt - Notepad","mon":"wide","slots":[0]}]'))
  if (Shard-Take) {
Check 'held, scope: the locked pin for a closed window is in the scene and is not placed' ([bool]@($hOnPin.missing | ? { $_.app -eq 'closedapp' }).Count) (SlPl $hOnPin)
Check 'held: no held window takes the cell of a locked pin whose window is closed' (-not @($hOnPin.placed | ? { @($_.slots) -contains 1 }).Count) "placed on slot 1: $(SlShort @($hOnPin.placed | ? { @($_.slots) -contains 1 }))"
  }
$hFreeCell = SlDry (SlSceneJson $hClosedPin '["*"]' '' (SlHeldFill '[{"app":"notepad","title":"todo.txt - Notepad","mon":"wide","slots":[2]}]'))
  if (Shard-Take) {
Check 'held, control: beside the locked pin, a held window on a free cell is placed in it' ((SlSlotsOf $hFreeCell 1014) -eq '3') (SlPl $hFreeCell)
  }
# A stale handle holds no window: the open window with the held title does not take its cell.
$hStale = SlDry (SlSceneJson '[]' '["*"]' '' (SlHeldFill '[{"id":9999,"app":"chrome","title":"Pull request 212 - Example","mon":"wide","slots":[0]}]'))
  if (Shard-Take) {
Check 'held, scope: no open window has handle 9999, and chrome 1005 has the held title' ((@($fxWins | ? { $_.id -eq 9999 }).Count -eq 0) -and (@($fxWins | ? { $_.id -eq 1005 -and $_.title -eq 'Pull request 212 - Example' }).Count -eq 1)) "windows: $($fxWins.Count)"
Check 'held: a stale handle leaves its cell empty, and no other window with its title takes the cell' (-not @($hStale.placed | ? { @($_.slots) -contains 1 }).Count) "placed on slot 1: $(SlShort @($hStale.placed | ? { @($_.slots) -contains 1 }))"
  }
$hValid = SlDry (SlSceneJson '[]' '["*"]' '' (SlHeldFill '[{"id":1005,"app":"chrome","title":"Pull request 212 - Example","mon":"wide","slots":[0]}]'))
  if (Shard-Take) {
Check 'held, control: a held handle that is open places its window in the cell' ((SlSlotsOf $hValid 1005) -eq '1') (SlPl $hValid)
  }
# Empty and full-size held layouts (P8): none holds nothing; ten held windows, one per cell, each keeps its own cell by its exact title.
$hNone = SlDry (SlSceneJson '[]' '["*"]' '' (SlHeldFill '[]'))
  if (Shard-Take) {
Check 'held, control: an empty held layout places no window' (@($hNone.placed).Count -eq 0) (SlPl $hNone)
  }
$hFullRows = @(@(1001, 'claude', 'Refactor the grid solver'), @(1002, 'claude', 'Pin parser edge cases'), @(1003, 'claude', 'Draft release notes'), @(1005, 'chrome', 'Pull request 212 - Example'), @(1006, 'chrome', 'Quarterly roadmap - Example'), @(1008, 'WindowsTerminal', 'pwsh - tiler'), @(1009, 'WindowsTerminal', 'pwsh - docs watch'), @(1010, 'explorer', 'Projects'), @(1011, 'explorer', 'Downloads'), @(1012, 'ms-teams', 'Design sync | Microsoft Teams'))
$hFullJson = '[' + ((0..9 | % { $r = $hFullRows[$_]; '{"app":"' + $r[1] + '","title":"' + $r[2] + '","mon":"wide","slots":[' + $_ + ']}' }) -join ',') + ']'
$hFull = SlDry (SlSceneJson '[]' '["*"]' '' (SlHeldFill $hFullJson))
$hFullBad = @(0..9 | ? { (SlSlotsOf $hFull $hFullRows[$_][0]) -ne [string]($_ + 1) })
  if (Shard-Take) {
Check 'held, control, full board: ten held windows each keep their own cell' ($hFullBad.Count -eq 0 -and @($hFull.placed).Count -eq 10) "not in their cells: $(@($hFullBad | % { $hFullRows[$_][0] }) -join ',')"
  }
# Nested titles (the held match, decisions/fill-controls.md): "Projects" and "Projects archive" are two windows of one app, and the
# archive window is further left, so a sort by position alone hands it to the entry "Projects". Each entry takes the window with its
# exact title first, then one whose title contains it. The fixture is the shared one plus the archive window, in the run folder.
$fxNestDoc = Get-Content -Raw -Encoding UTF8 -LiteralPath $fixture | ConvertFrom-Json
$fxNestDoc.windows = @($fxNestDoc.windows) + [pscustomobject]@{ id = 1018; app = 'explorer'; title = 'Projects archive'; x = 300; y = 200; w = 1000; h = 700 }
$fxNest = Join-Path $run 'fixture-nested.json'
[IO.File]::WriteAllText($fxNest, (ConvertTo-Json -Depth 10 -Compress $fxNestDoc), $utf8)
$nestPA = @($fxNestDoc.windows | ? { $_.title -eq 'Projects' })[0]; $nestPB = @($fxNestDoc.windows | ? { $_.title -eq 'Projects archive' })[0]
  if (Shard-Take) {
Check 'held, nested titles, scope: Projects and Projects archive are open explorer windows, the archive one further left' ([bool]($nestPA -and $nestPB -and $nestPB.app -eq 'explorer' -and $nestPA.app -eq 'explorer' -and $nestPB.x -lt $nestPA.x -and $nestPB.x -gt -20000)) "windows: $(SlShort @($nestPA, $nestPB))"
  }
$hNest = SlDry (SlSceneJson '[]' '["*"]' '' (SlHeldFill '[{"app":"explorer","title":"Projects","mon":"wide","slots":[0]},{"app":"explorer","title":"Projects archive","mon":"wide","slots":[1]}]')) $fxNest
  if (Shard-Take) {
Check 'held, nested titles: the window titled Projects takes its own cell 1' ((SlSlotsOf $hNest 1010) -eq '1') "1010 cells: $(SlSlotsOf $hNest 1010); placed: $(SlPl $hNest)"
Check 'held, nested titles: the window titled Projects archive takes its own cell 2' ((SlSlotsOf $hNest 1018) -eq '2') "1018 cells: $(SlSlotsOf $hNest 1018); placed: $(SlPl $hNest)"
  }
# An unlocked pin for a closed window keeps its cell as a locked one does. The scope is read first; then no held window takes the cell.
$hOpenPin = SlDry (SlSceneJson (SlPins '{"app":"closedapp","match":"","mon":"wide","slots":[0]}') '["*"]' '' (SlHeldFill '[{"app":"notepad","title":"todo.txt - Notepad","mon":"wide","slots":[0]}]'))
  if (Shard-Take) {
Check 'held, unlocked pin, scope: the pin for a closed window is in the scene and is not placed' ([bool]@($hOpenPin.missing | ? { $_.app -eq 'closedapp' }).Count) (SlPl $hOpenPin)
Check 'held, control: no held window takes the cell of an unlocked pin whose window is closed' (-not @($hOpenPin.placed | ? { @($_.slots) -contains 1 }).Count) "placed on slot 1: $(SlShort @($hOpenPin.placed | ? { @($_.slots) -contains 1 }))"
  }

try {
  $srvPair = SlStartServer; $srv = $srvPair[0]; $script:url = $srvPair[1]
  $edgeProc = SlStartBrowser

  # Harness control: the page draws a two-pin scene (a green case, so a red below is a real outcome).
  SlCase (SlSceneJson $pinsCQ)
  $ctl = SlGet 'prevs[selId].placed.length'
  if (Shard-Take) {
  Check 'harness: the page draws the two pinned windows (control)' ($ctl -eq 2) "placed: $ctl"
  }

  # Stack: a drop on the lower band of a taken cell stacks the dragged window behind; the upper zone swaps (control).
  SlCase (SlSceneJson $pinsCQ)
  $from = SlAt (SlBox 1006) 0.5 0.5; SlDrag $from (SlAt (SlBox 1001) 0.5 0.85)
  # Placed rects, not boxes: the layered look shortens the front tile by its strip, so the boxes differ at rest.
  $a1 = SlPlacedRect 1001; $c1 = SlPlacedRect 1006; $s1 = SlGet 'work[selId]'
  if (Shard-Take) {
  Check 'stack: a Put Behind drop leaves both windows on the front window''s cell' (SlSameRect $a1 $c1) "claude $(SlShort $a1), chrome $(SlShort $c1)"
  Check 'stack: the scene keeps the dropped window behind the front window' ([bool]@($s1.pins | % { @($_.behind) } | ? { $_.app -eq 'chrome' }).Count) (SlShort $s1.pins)
  }

  SlCase (SlSceneJson $pinsCQ)
  $a0 = SlBox 1001; $c0 = SlBox 1006
  SlDrag (SlAt (SlBox 1006) 0.5 0.5) (SlAt (SlBox 1001) 0.5 0.5)
  $a2 = SlBox 1001; $c2 = SlBox 1006
  if (Shard-Take) {
  Check 'control: a drop on the centre of a taken cell, inside the Swap circle, still swaps' ((SlSame $a2 $c0) -and (SlSame $c2 $a0)) "claude $(SlFmt $a2), chrome $(SlFmt $c2)"
  }

  # Stack: Bring to Front swaps the front with the window behind; Take Out sends the window to the bay.
  $pinsStack = SlPins '{"app":"claude","match":"Refactor","mon":"wide","slots":[0],"behind":[{"app":"claude","match":"Draft release"}]}'
  SlCase (SlSceneJson $pinsStack)
  SlClick (SlAt (SlBox 1001) 0.5 0.5)
  $bf = SlJs "(() => { const b = [...document.querySelectorAll('button')].find(x => x.textContent.trim() === 'Bring to Front'); if (!b) return false; b.click(); return true; })()"
  SlSettle
  $s2 = SlGet 'work[selId]'; $front2 = SlPin $s2 'Draft release'
  if (Shard-Take) {
  Check 'stack: Bring to Front makes the window behind the front window' ([bool]$front2 -and $front2.app -eq 'claude') "button found: $bf; pins: $(SlShort $s2.pins)"
  Check 'stack: Bring to Front keeps the old front window behind' ([bool]$front2 -and (SlHasBehind $front2 'Refactor')) "pins: $(SlShort $s2.pins)"
  }

  SlCase (SlSceneJson $pinsStack)
  SlClick (SlAt (SlBox 1001) 0.5 0.5)
  $tk = SlJs "(() => { const b = [...document.querySelectorAll('button')].find(x => x.textContent.trim() === 'Take Out'); if (!b) return false; b.click(); return true; })()"
  SlSettle
  $s3 = SlGet 'work[selId]'; $front3 = SlPin $s3 'Refactor'
  if (Shard-Take) {
  Check 'stack: Take Out removes the window from the stack' ([bool]$front3 -and -not (SlHasBehind $front3 'Draft')) "button found: $tk; pins: $(SlShort $s3.pins)"
  Check 'stack: Take Out sends the window to Windows That Stay Put (the bay)' (SlHasBay $s3 'Draft release') "bay: $(SlShort $s3.bay)"
  }

  # Lock: a drop on a locked tile stacks behind it and never moves it; the label offers Put Behind, not Swap.
  SlCase (SlSceneJson $pinsCQLock)
  $lk0 = SlBox 1001; $lk0p = SlPlacedRect 1001
  SlDrag (SlAt (SlBox 1006) 0.5 0.5) (SlAt $lk0 0.5 0.5)
  $lk1p = SlPlacedRect 1001; $s4 = SlGet 'work[selId]'
  if (Shard-Take) {
  Check 'lock: a drop on a locked tile does not move the locked tile' (SlSameRect $lk1p $lk0p) "before $(SlShort $lk0p), after $(SlShort $lk1p)"
  Check 'lock: a drop on a locked tile stacks the dropped window behind it, not a swap' ([bool]@($s4.pins | ? { "$($_.match)" -like '*Refactor*' } | % { @($_.behind) } | ? { $_.app -eq 'chrome' }).Count) (SlShort $s4.pins)
  }

  SlCase (SlSceneJson $pinsCQLock)
  SlDrag (SlAt (SlBox 1006) 0.5 0.5) (SlAt (SlBox 1001) 0.5 0.5) -Hold
  if (Shard-Take) {
  Check 'scope: the drop label shows over the locked tile' (SlLabelShown) 'the drop label is hidden'
  }
  $lbl = SlLabel
  if (Shard-Take) {
  Check 'lock: over a locked tile the drop label offers Behind' ("$lbl" -match 'Behind') "label: $lbl"
  Check 'lock: over a locked tile the drop label offers no Swap action' ("$lbl" -notmatch 'Swap with') "label: $lbl"
  Check 'lock: over a locked tile the drop label says Locked' ("$lbl" -match 'Locked') "label: $lbl"
  }
  SlRelease (SlAt (SlBox 1001) 0.5 0.5)
  # Lock in a wide cell: the chip reads the approved copy, "Locked, so no Swap". At 1440 the 5-column cells are narrower than
  # 110 px, so this case widens the viewport, then sets it back for the cases after it.
  SlViewport 2560 1440
  SlCase (SlSceneJson $pinsCQLock)
  SlDrag (SlAt (SlBox 1006) 0.5 0.5) (SlAt (SlBox 1001) 0.5 0.5) -Hold
  if (Shard-Take) {
  Check 'scope: the drop label shows over the locked tile, at 110 px or wider' ([bool](SlJs "getComputedStyle(document.getElementById('drop')).display !== 'none' && document.getElementById('drop').offsetWidth >= 110")) "width: $(SlJs "document.getElementById('drop').offsetWidth")"
  }
  $lw = SlLabel
  if (Shard-Take) {
  Check 'lock: over a locked tile in a wide cell the drop label reads "Locked, so no Swap"' ("$lw" -match 'Locked, so no Swap') "label: $lw"
  }
  SlRelease (SlAt (SlBox 1001) 0.5 0.5)
  SlViewport 1440 900

  # Lock: the lock control locks the tile, and Save keeps the lock in the scene. The padlock shows on a selected tile
  # (ruling 2026-11-16), so the tile is selected first; a press on a hidden padlock would land on the tile instead.
  SlCase (SlSceneJson $pinsCQ)
  SlClick (SlAt (SlBox 1001) 0.5 0.5)
  $lockAt =SlGet "(() => { const e = els.get(1001); const k = e.querySelector('.lk'); const r = (k || e).getBoundingClientRect(); return k ? [r.left + r.width / 2, r.top + r.height / 2] : [r.right - 8, r.top + 8]; })()"
  SlClick @([double]$lockAt[0], [double]$lockAt[1])
  [void](SlJs "(() => { const b = document.getElementById('save'); if (b && !b.disabled) { b.click(); return true; } return false; })()")
  SlSettle
  $saved = SlSavedScene; $savedPin = SlPin $saved 'Refactor'
  if (Shard-Take) {
  Check 'lock: the lock control locks the tile, and Save keeps the lock in the scene' ([bool]($savedPin -and $savedPin.lock -eq $true)) "saved pin: $(SlShort $savedPin)"
  }
  SlLoad
  $reloaded = SlPin (SlGet 'work[selId]') 'Refactor'
  if (Shard-Take) {
  Check 'lock: the saved lock is still on the tile after the page reloads' ([bool]($reloaded -and $reloaded.lock -eq $true)) "reloaded pin: $(SlShort $reloaded)"
  }

  # Lock: Title contains never re-points a locked tile. Control: it re-points an unlocked one.
  SlCase (SlSceneJson $pinsCQ)
  SlClick (SlAt (SlBox 1001) 0.5 0.5)
  SlTitle 'Draft release'
  $tc = SlGet 'work[selId]'
  if (Shard-Take) {
  Check 'control: Title contains re-points an unlocked pin' ([bool](SlPin $tc 'Draft release')) "pins: $(SlShort $tc.pins)"
  }
  SlCase (SlSceneJson $pinsCQLock)
  SlClick (SlAt (SlBox 1001) 0.5 0.5)
  SlTitle 'Draft release'
  $s12 = SlGet 'work[selId]'; $p12 = SlPin $s12 'Refactor'
  if (Shard-Take) {
  Check 'lock: Title contains never re-points a locked tile (its pin keeps its window and cell)' ([bool]$p12 -and $p12.lock -eq $true -and (SlCells $p12) -eq '0') "locked pin: $(SlShort $p12); pins: $(SlShort $s12.pins)"
  }

  # Lock: Columns never cuts off a locked tile. Control: it shrinks the grid when no locked tile is in the way.
  SlCase (SlSceneJson $pinsGridFree)
  SlClick (SlAt (SlBox 1006) 0.5 0.5)
  SlFewer 'c'
  $gc = SlGet 'work[selId].grids.wide.c'
  if (Shard-Take) {
  Check 'control: Fewer Columns shrinks the grid when no locked tile is in the way' ($gc -eq 4) "columns: $gc"
  }
  SlCase (SlSceneJson $pinsGridLock)
  SlClick (SlAt (SlBox 1006) 0.5 0.5)
  SlFewer 'c'
  $s13 = SlGet 'work[selId]'; $g13 = SlPin $s13 'Quarterly'
  if (Shard-Take) {
  Check 'lock: Fewer Columns never cuts off a locked tile (it keeps its cell)' ([bool]$g13 -and $g13.lock -eq $true -and (SlCells $g13) -eq '4') "locked pin: $(SlShort $g13); columns: $($s13.grids.wide.c)"
  }

  # Resize: a span drag by the corner grip snaps to whole cells; a covered window goes to the bay, whether or not a cell is
  # free (ruling 2026-11-16); a resize stops at a locked tile.
  SlCase (SlSceneJson $pinsCQ)
  $b5 = SlBox 1001; SlDrag (SlAt $b5 (($b5.w - 6) / $b5.w) (($b5.h - 6) / $b5.h)) (SlAt $b5 ((($b5.w - 6) + 1.4 * $b5.w) / $b5.w) (($b5.h - 6) / $b5.h))
  $s5 = SlGet 'work[selId]'; $p5 = SlPin $s5 'Refactor'
  if (Shard-Take) {
  Check 'resize: a corner drag of 1.4 cells snaps to a 2-column span' ([bool]$p5 -and (SlCells $p5) -eq '0,1') "claude pin: $(SlShort $p5)"
  }

  SlCase (SlSceneJson $pinsCQ)
  $b6 = SlBox 1001; SlDrag (SlAt $b6 (($b6.w - 6) / $b6.w) (($b6.h - 6) / $b6.h)) (SlAt $b6 ((($b6.w - 6) + 1.4 * $b6.w) / $b6.w) (($b6.h - 6) / $b6.h))
  $s6 = SlGet 'work[selId]'; $q6 = SlPin $s6 'Quarterly'; $p6 = SlPin $s6 'Refactor'
  if (Shard-Take) {
  Check 'resize: a covered window goes to Windows That Stay Put, not to a free cell (ruling 2026-11-16)' ([bool](-not $q6 -and (SlHasBay $s6 'Quarterly') -and (SlCells $p6) -eq '0,1')) "chrome pin: $(SlShort $q6); bay: $(SlShort $s6.bay); claude pin: $(SlShort $p6)"
  }

  SlCase (SlSceneJson $pinsFull)
  $b7 = SlBox 1001; SlDrag (SlAt $b7 (($b7.w - 6) / $b7.w) (($b7.h - 6) / $b7.h)) (SlAt $b7 ((($b7.w - 6) + 1.4 * $b7.w) / $b7.w) (($b7.h - 6) / $b7.h))
  $s7 = SlGet 'work[selId]'
  if (Shard-Take) {
  Check 'resize: with no free cell, the covered window goes to Windows That Stay Put' (SlHasBay $s7 'Pin parser') "bay: $(SlShort $s7.bay)"
  }

  # The grip ends over the locked cell (cell 2), so a span over it must stop short. A 1x1 window that moves rather than
  # resizes would land on the locked cell and swap with it.
  SlCase (SlSceneJson $pinsResizeLock)
  $b8 = SlBox 1001; SlDrag (SlAt $b8 (($b8.w - 6) / $b8.w) (($b8.h - 6) / $b8.h)) (SlAt $b8 ((($b8.w - 6) + 0.6 * $b8.w) / $b8.w) (($b8.h - 6) / $b8.h))
  $s8 = SlGet 'work[selId]'; $l8 = SlPin $s8 'Quarterly'; $c8 = SlPin $s8 'Refactor'
  if (Shard-Take) {
  Check 'resize: a resize stops at a locked tile, which keeps its cell' ([bool]$l8 -and $l8.lock -eq $true -and (SlCells $l8) -eq '1') "locked pin: $(SlShort $l8)"
  }

  # Growth by Shift+arrow and by the Width and Height steppers: a covered pinned window goes to Windows That Stay Put, with
  # the windows stacked behind it, whether or not a cell is free (ruling 2026-11-16).
  # Each case's first check is the growth itself, so a key or stepper that never reaches the page cannot pass.
  SlCase (SlSceneJson $pinsGrowFree)
  SlClick (SlAt (SlBox 1001) 0.5 0.5)
  SlKey 1001 'ArrowRight' 39 8
  $g1 = SlGet 'work[selId]'; $g1r = SlPin $g1 'Refactor'; $g1q = SlPin $g1 'Quarterly'
  if (Shard-Take) {
  Check 'control: Shift+arrow grows a pinned window to a 2-column span' ([bool]$g1r -and (SlCells $g1r) -eq '0,1') "claude pin: $(SlShort $g1r)"
  Check 'resize: Shift+arrow growth sends the covered pinned window to Windows That Stay Put' ([bool](-not $g1q -and (SlHasBay $g1 'Quarterly'))) "chrome pin: $(SlShort $g1q); bay: $(SlShort $g1.bay)"
  Check 'resize: Shift+arrow growth sends the covered window''s stack to Windows That Stay Put' ([bool](SlHasBay $g1 'Draft release')) "bay: $(SlShort $g1.bay)"
  }

  SlCase (SlSceneJson $pinsGrowFree)
  SlClick (SlAt (SlBox 1001) 0.5 0.5)
  $w2 = SlStep 'span' 'cs' '1'
  $w2s = SlGet 'work[selId]'; $w2r = SlPin $w2s 'Refactor'; $w2q = SlPin $w2s 'Quarterly'
  if (Shard-Take) {
  Check 'control: the Width stepper grows a pinned window to a 2-column span' ($w2 -eq 'pressed' -and [bool]$w2r -and (SlCells $w2r) -eq '0,1') "stepper: $w2; claude pin: $(SlShort $w2r)"
  Check 'resize: the Width stepper sends the covered pinned window to Windows That Stay Put' ([bool](-not $w2q -and (SlHasBay $w2s 'Quarterly'))) "stepper: $w2; bay: $(SlShort $w2s.bay)"
  Check 'resize: the Width stepper sends the covered window''s stack to Windows That Stay Put' ([bool](SlHasBay $w2s 'Draft release')) "bay: $(SlShort $w2s.bay)"
  }

  SlCase (SlSceneJson $pinsGrowFreeDown)
  SlClick (SlAt (SlBox 1001) 0.5 0.5)
  $h2 = SlStep 'span' 'rs' '1'
  $h2s = SlGet 'work[selId]'; $h2r = SlPin $h2s 'Refactor'; $h2q = SlPin $h2s 'Quarterly'
  if (Shard-Take) {
  Check 'control: the Height stepper grows a pinned window to a 2-row span' ($h2 -eq 'pressed' -and [bool]$h2r -and (SlCells $h2r) -eq '0,5') "stepper: $h2; claude pin: $(SlShort $h2r)"
  Check 'resize: the Height stepper sends the covered pinned window to Windows That Stay Put' ([bool](-not $h2q -and (SlHasBay $h2s 'Quarterly'))) "stepper: $h2; bay: $(SlShort $h2s.bay)"
  Check 'resize: the Height stepper sends the covered window''s stack to Windows That Stay Put' ([bool](SlHasBay $h2s 'Draft release')) "bay: $(SlShort $h2s.bay)"
  }

  SlCase (SlSceneJson $pinsFullStack)
  SlClick (SlAt (SlBox 1001) 0.5 0.5)
  SlKey 1001 'ArrowRight' 39 8
  $b1 = SlGet 'work[selId]'; $b1r = SlPin $b1 'Refactor'
  if (Shard-Take) {
  Check 'control: Shift+arrow grows a pinned window to a 2-column span on a full board' ([bool]$b1r -and (SlCells $b1r) -eq '0,1') "claude pin: $(SlShort $b1r)"
  Check 'resize: with no free cell, Shift+arrow growth sends the covered pinned window to Windows That Stay Put' (SlHasBay $b1 'Pin parser') "bay: $(SlShort $b1.bay)"
  Check 'resize: with no free cell, Shift+arrow growth sends its stack to Windows That Stay Put' (SlHasBay $b1 'Draft release') "bay: $(SlShort $b1.bay)"
  }

  SlCase (SlSceneJson $pinsFullStack)
  SlClick (SlAt (SlBox 1001) 0.5 0.5)
  $w3 = SlStep 'span' 'cs' '1'
  $w3s = SlGet 'work[selId]'; $w3r = SlPin $w3s 'Refactor'
  if (Shard-Take) {
  Check 'control: the Width stepper grows a pinned window to a 2-column span on a full board' ($w3 -eq 'pressed' -and [bool]$w3r -and (SlCells $w3r) -eq '0,1') "stepper: $w3; claude pin: $(SlShort $w3r)"
  Check 'resize: with no free cell, the Width stepper sends the covered pinned window to Windows That Stay Put' (SlHasBay $w3s 'Pin parser') "bay: $(SlShort $w3s.bay)"
  Check 'resize: with no free cell, the Width stepper sends its stack to Windows That Stay Put' (SlHasBay $w3s 'Draft release') "bay: $(SlShort $w3s.bay)"
  }

  SlCase (SlSceneJson $pinsFullStack)
  SlClick (SlAt (SlBox 1001) 0.5 0.5)
  $h3 = SlStep 'span' 'rs' '1'
  $h3s = SlGet 'work[selId]'; $h3r = SlPin $h3s 'Refactor'
  if (Shard-Take) {
  Check 'control: the Height stepper grows a pinned window to a 2-row span on a full board' ($h3 -eq 'pressed' -and [bool]$h3r -and (SlCells $h3r) -eq '0,5') "stepper: $h3; claude pin: $(SlShort $h3r)"
  Check 'resize: with no free cell, the Height stepper sends the covered pinned window to Windows That Stay Put' (SlHasBay $h3s 'quoted') "bay: $(SlShort $h3s.bay)"
  }

  # Guard, not a new claim: Shift+arrow growth toward a locked tile stops. This passes on the old code (pinWin checks lockedHit).
  # The status line names the refusal, so a key that never reached the page cannot pass it; the Shift control above covers the key.
  SlCase (SlSceneJson $pinsResizeLock)
  SlClick (SlAt (SlBox 1001) 0.5 0.5)
  SlKey 1001 'ArrowRight' 39 8
  $lg = SlGet 'work[selId]'; $lgq = SlPin $lg 'Quarterly'; $lgr = SlPin $lg 'Refactor'
  $lgmsg = SlJs "document.getElementById('msg').textContent"
  if (Shard-Take) {
  Check 'guard: Shift+arrow growth toward a locked tile is refused, and says so' ("$lgmsg" -match 'locked tile is in the way') "status: $lgmsg"
  Check 'guard: Shift+arrow growth toward a locked tile leaves the locked tile in its cell' ([bool]$lgq -and $lgq.lock -eq $true -and (SlCells $lgq) -eq '1') "locked pin: $(SlShort $lgq)"
  Check 'guard: Shift+arrow growth toward a locked tile does not grow the window onto it' ([bool]$lgr -and (SlCells $lgr) -eq '0') "claude pin: $(SlShort $lgr)"
  }

  # A back window promoted because its front is not open is the front now (tile.ps1 promotes the first open back window).
  # Control: the promoted window is the front of pin 0 on the board. Red: the inspector's Behind This Window still lists it.
  SlCase (SlSceneJson $pinsFrontGone)
  SlClick (SlAt (SlBox 1003) 0.5 0.5)
  $pe = SlPlacedOf 1003
  if (Shard-Take) {
  Check 'promoted, empty state: the open back window is the front of pin 0 (control)' ([bool]$pe -and $pe.pin -eq 0 -and -not $pe.behind) "placed: $(SlShort $pe)"
  }
  $pet = SlBehindText
  if (Shard-Take) {
  Check 'promoted, empty state: Behind This Window does not list the promoted window' ("$pet" -notlike '*Draft release*') "Behind This Window: $pet"
  }

  SlCase (SlSceneJson $pinsFullFrontGone)
  SlClick (SlAt (SlBox 1001) 0.5 0.5)
  $pf = SlPlacedOf 1001
  if (Shard-Take) {
  Check 'promoted, full state: the open back window is the front of pin 0 (control)' ([bool]$pf -and $pf.pin -eq 0 -and -not $pf.behind) "placed: $(SlShort $pf)"
  }
  $pft = SlBehindText
  if (Shard-Take) {
  Check 'promoted, full state: Behind This Window does not list the promoted window' ("$pft" -notlike '*Refactor*') "Behind This Window: $pft"
  }

  SlCase (SlSceneJson $pinsNoMatchGone)
  SlClick (SlAt (SlBox 1014) 0.5 0.5)
  $pn = SlPlacedOf 1014
  if (Shard-Take) {
  Check 'promoted, no title match: the open back window is the front of pin 0 (control)' ([bool]$pn -and $pn.pin -eq 0 -and -not $pn.behind) "placed: $(SlShort $pn)"
  }
  $pnt = SlBehindText
  if (Shard-Take) {
  Check 'promoted, no title match: Behind This Window does not read "Not open" for the promoted window' ("$pnt" -notlike '*Not open*') "Behind This Window: $pnt"
  }

  # Spanned drop: the whole 2x2 block is the target. Put Behind stacks behind it and keeps its span. Swap gives the block
  # to the dropped window and moves the spanned window to the dropped window's old 1x1 cell.
  SlCase (SlSceneJson $pinsSpan)
  $blk = SlBox 1006; $term = SlBox 1008
  SlDrag (SlAt $term 0.5 0.5) (SlAt $blk 0.5 0.85) -Hold
  $lbl2 = SlLabel
  if (Shard-Take) {
  Check 'span: a drop on a spanned block labels the whole block Put Behind' ("$lbl2" -match 'Behind') "label: $lbl2"
  Check 'span: a drop on a spanned block never labels one cell (Place here, or Here on a narrow cell)' ("$lbl2" -notmatch '(?i)place here|^here$') "label: $lbl2"
  }
  SlRelease (SlAt $blk 0.5 0.85)

  SlCase (SlSceneJson $pinsSpan)
  $blk3 = SlBox 1006; $term3 = SlBox 1008
  SlDrag (SlAt $term3 0.5 0.5) (SlAt $blk3 0.5 0.85)
  $s9 = SlGet 'work[selId]'; $ch9 = SlPin $s9 'Quarterly'; $tm9 = SlPin $s9 'tiler'
  if (Shard-Take) {
  Check 'span: Put Behind on a spanned block keeps the block''s 2x2 span' ([bool]$ch9 -and (SlCells $ch9) -eq '0,1,5,6') "chrome pin: $(SlShort $ch9)"
  Check 'span: Put Behind on a spanned block stacks the dropped window behind it' ([bool]$ch9 -and (SlHasBehind $ch9 'tiler')) "chrome pin: $(SlShort $ch9)"
  }

  SlCase (SlSceneJson $pinsSpan)
  $blk4 = SlBox 1006; $term4 = SlBox 1008
  SlDrag (SlAt $term4 0.5 0.5) (SlAt $blk4 0.5 0.5)
  $s10 = SlGet 'work[selId]'; $tm10 = SlPin $s10 'tiler'; $ch10 = SlPin $s10 'Quarterly'
  if (Shard-Take) {
  Check 'span: a swap on a spanned block gives the dropped window the whole 2x2 block' ([bool]$tm10 -and (SlCells $tm10) -eq '0,1,5,6') "terminal pin: $(SlShort $tm10)"
  Check 'span: a swap on a spanned block moves the spanned window to the dropped window''s old 1x1 cell' ([bool]$ch10 -and (SlCells $ch10) -eq '3') "chrome pin: $(SlShort $ch10)"
  }
  $placed10 = @((SlGet 'prevs[selId].placed') | ? { -not $_.behind })
  $cellsUsed = @($placed10 | % { $_.slots }); $dupCells = @($cellsUsed | Group-Object | ? { $_.Count -gt 1 }).Count
  if (Shard-Take) {
  Check 'span: after a swap on a spanned block, the spanned window keeps a cell' ([bool]@($placed10 | ? { $_.app -eq 'chrome' }).Count) "placed: $(SlShort $placed10)"
  # A guard, not a new claim: a swap that drops the spanned window still shows no overlap, so this one passes on the old code.
  Check 'span: after a swap on a spanned block, no two windows share a cell (no tile overlaps)' ($placed10.Count -gt 0 -and $dupCells -eq 0) "duplicate cells: $dupCells"
  }

  # Spanned window over a taken 1x1 cell: the split, never Place here, and the occupant keeps its pin and its stack.
  # Control: a one-cell window over the same cell reads the split, as today.
  SlCase (SlSceneJson $pinsOver)
  SlDrag (SlAt (SlBox 1001) 0.5 0.5) (SlAt (SlBox 1008) 0.5 0.5) -Hold
  $lc = SlLabel
  if (Shard-Take) {
  Check 'control: a one-cell window over a taken cell reads Swap and Behind (as today)' (("$lc" -match 'Swap') -and ("$lc" -match 'Behind')) "label: $lc"
  }
  SlRelease (SlAt (SlBox 1008) 0.5 0.5)

  SlCase (SlSceneJson $pinsSpanOver)
  SlDrag (SlAt (SlBox 1006) 0.25 0.25) (SlAt (SlBox 1008) 0.5 0.5) -Hold
  if (Shard-Take) {
  Check 'scope: the drop label shows over the taken cell of a spanned drag' (SlLabelShown) 'the drop label is hidden'
  }
  $l1 = SlLabel
  if (Shard-Take) {
  Check 'split: a spanned window over a taken 1x1 cell reads Swap and Behind' (("$l1" -match 'Swap') -and ("$l1" -match 'Behind')) "label: $l1"
  }
  SlRelease (SlAt (SlBox 1008) 0.5 0.5)

  SlCase (SlSceneJson $pinsSpanOver)
  SlDrag (SlAt (SlBox 1006) 0.25 0.25) (SlAt (SlBox 1008) 0.5 0.85)
  $s14 = SlGet 'work[selId]'; $t14 = SlPin $s14 'tiler'
  if (Shard-Take) {
  Check 'nothing dropped: a Put Behind drop on a taken cell keeps the occupant''s pin' ([bool]$t14) "pins: $(SlShort $s14.pins)"
  Check 'nothing dropped: a Put Behind drop on a taken cell keeps the occupant''s stack' ([bool]$t14 -and (SlHasBehind $t14 'Draft release')) "occupant pin: $(SlShort $t14)"
  Check 'split: a Put Behind drop puts the spanned window behind the occupant' ([bool]$t14 -and (SlHasBehind $t14 'Quarterly')) "occupant pin: $(SlShort $t14)"
  }

  SlCase (SlSceneJson $pinsSpanOver)
  SlDrag (SlAt (SlBox 1006) 0.25 0.25) (SlAt (SlBox 1008) 0.5 0.5)
  $s15 = SlGet 'work[selId]'; $t15 = SlPin $s15 'tiler'
  if (Shard-Take) {
  Check 'nothing dropped: a swap onto a taken cell keeps the occupant''s pin' ([bool]$t15) "pins: $(SlShort $s15.pins)"
  Check 'nothing dropped: a swap onto a taken cell keeps the occupant''s stack' ([bool]$t15 -and (SlHasBehind $t15 'Draft release')) "occupant pin: $(SlShort $t15)"
  }

  # Arrow keys into a taken cell take the same path: the occupant must survive. Control: an arrow key moves a one-cell window into an empty cell.
  SlCase (SlSceneJson $pinsOneWin)
  SlClick (SlAt (SlBox 1001) 0.5 0.5)
  SlKey 1001 'ArrowRight' 39
  $s16 = SlGet 'work[selId]'; $r16 = SlPin $s16 'Refactor'
  if (Shard-Take) {
  Check 'control: an arrow key moves a one-cell window into an empty cell (as today)' ([bool]$r16 -and (SlCells $r16) -eq '1') "pin: $(SlShort $r16)"
  }
  SlCase (SlSceneJson $pinsSpanArrow)
  SlClick (SlAt (SlBox 1006) 0.5 0.5)
  SlKey 1006 'ArrowRight' 39
  $s17 = SlGet 'work[selId]'; $t17 = SlPin $s17 'tiler'
  if (Shard-Take) {
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
  }

  # ---------- Board feedback (decisions/stack-and-lock.md, decisions/fill-controls.md, docs/design/mockups/board-feedback-notes.md) ----------
  # Drop Note. The control comes first: the drop stacks, and the header Undo restores the scene after it, so the scene
  # comparison holds on head before the note's own Undo is judged.
  SlCase (SlSceneJson $pinsCQ)
  [void](SlJs "(window.bfPre = $SceneNorm, true)")
  SlDropNoSettle (SlAt (SlBox 1006) 0.5 0.5) (SlAt (SlBox 1001) 0.5 0.85)
  $dStack = SlGet 'work[selId]'; $dBehind = @($dStack.pins | ? { "$($_.match)" -like '*Refactor*' } | % { @($_.behind) } | ? { $_.app -eq 'chrome' })
  if (Shard-Take) {
  Check 'control: a Put Behind drop still stacks the dropped window behind (as today)' ($dBehind.Count -gt 0) (SlShort $dStack.pins)
  }
  SlSettle
  $hUndo = SlJs "(() => { const b = [...document.querySelectorAll('button')].find(x => x.textContent.trim() === 'Undo' && !x.closest('.dnote')); if (!b) return false; b.click(); return true; })()"
  SlSettle
  $hBack = SlJs "($SceneNorm) === window.bfPre"
  if (Shard-Take) {
  Check 'control: the header Undo restores the scene after the same drop, so the comparison holds' ([bool]$hUndo -and [bool]$hBack) "header Undo pressed: $hUndo; scene restored: $hBack"
  }

  SlCase (SlSceneJson $pinsCQ)
  [void](SlJs "(window.bfPre = $SceneNorm, true)")
  SlDropNoSettle (SlAt (SlBox 1006) 0.5 0.5) (SlAt (SlBox 1001) 0.5 0.85)
  $dNote = SlNoteText
  if (Shard-Take) {
  Check 'drop note: after a Put Behind drop the tile shows a note naming both apps' ("$dNote" -like '*Chrome is behind Claude*') "note: $dNote"
  }
  # A real press on the note's Undo, pressed and released as a mouse does. A JS click skips the pointer path, so it proves nothing here.
  SlSettle
  $dBtn = SlGet "(() => { const b = document.querySelector('.dnote button'); if (!b) return null; const r = b.getBoundingClientRect(); return { l: r.left, t: r.top, w: r.width, h: r.height }; })()"
  if ($dBtn) { SlClick (SlAt $dBtn 0.5 0.5) }
  SlSettle
  $dBack = SlJs "($SceneNorm) === window.bfPre"
  if (Shard-Take) {
  Check 'drop note: a real press on its Undo restores the scene from before the drop' ([bool]$dBtn -and [bool]$dBack) "note Undo button: $(SlFmt $dBtn); scene restored: $dBack"
  }

  # Put Behind from Windows That Stay Put, with a real mouse drag and no other action (owner report, 2026-11-12 09:59 CST).
  # The drop's engine answer is awaited passively (SlWaitBehind), then the screen is read: the window must be gone from the
  # list, shown under Behind This Window, and drawn as a tile and a badge on the front, at once.
  SlViewport 1440 900; SlCase (SlSceneJson $pinsCQ '[]' ',"bay":[{"app":"chrome","title":"Pull request 212 - Example"}]')
  $bayPre = SlBayIds
  if (Shard-Take) {
  Check 'put behind, scope: before the drop, Windows That Stay Put lists the chrome window' ($bayPre -contains 1005) "bay ids: $($bayPre -join ',')"
  }
  $chipAt = SlGet "(() => { const e = [...document.querySelectorAll('#bgrps [data-bay]')].find(b => b.dataset.bay === '1005'); if (!e) return null; const r = e.getBoundingClientRect(); return { l: r.left, t: r.top, w: r.width, h: r.height }; })()"
  SlMarkEngine
  if ($chipAt -and (SlBox 1001)) { SlDropNoSettle (SlAt $chipAt 0.5 0.5) (SlAt (SlBox 1001) 0.5 0.85) }
  $landed = SlWaitBehind 1005
  $bsDrop = SlGet 'work[selId]'
  if (Shard-Take) {
  Check 'put behind, control: the drop asks the engine for a new answer, with no page error' ([bool]$landed.fresh) "no new answer from the engine after the drop; page errors: $(SlShort $landed.errs)"
  Check 'put behind, control: the engine places the dropped window behind Refactor' ([bool]$landed.behind) "placed 1005 behind: $($landed.behind)"
  Check 'put behind, control: the scene stacks the window behind Refactor and drops its bay entry' ([bool]((SlHasBehind (SlPin $bsDrop 'Refactor') 'Pull request') -and -not (SlHasBay $bsDrop 'Pull request'))) "pins: $(SlShort $bsDrop.pins), bay: $(SlShort $bsDrop.bay)"
  }
  $bayPost = SlBayIds
  if (Shard-Take) {
  Check 'put behind, no other action: the window is not listed in Windows That Stay Put' (-not ($bayPost -contains 1005)) "bay ids: $($bayPost -join ',')"
  }
  $bsPost = SlBehindText
  if (Shard-Take) {
  Check 'put behind, no other action: Behind This Window lists the window' ("$bsPost" -like '*Pull request*') "Behind This Window: $bsPost"
  }
  $tilePost = SlGet "(() => { const e = els.get(1005); return e ? { hidden: e.hidden, behind: e.classList.contains('behind') } : null; })()"
  $rect1005 = SlPlacedRect 1005; $rect1001 = SlPlacedRect 1001
  if (Shard-Take) {
  Check 'put behind, no other action: the window is a tile behind the front, on the front''s rect' ([bool]($tilePost -and -not $tilePost.hidden -and $tilePost.behind -and (SlSameRect $rect1005 $rect1001))) "tile: $(SlShort $tilePost), placed 1005: $(SlShort $rect1005), placed 1001: $(SlShort $rect1001)"
  }
  $badgePost = SlBadgeText 1001
  $stackedPost = SlGet "!!els.get(1001) && els.get(1001).classList.contains('stacked')"
  if (Shard-Take) {
  Check 'put behind, no other action: the front badge names the window behind at once' ([bool]($stackedPost -and "$badgePost" -like '*Chrome*')) "stacked: $stackedPost, badge: $badgePost"
  }

  # Flash over the lock. A Put Behind drop flashes the front tile's peek strip for 1.5 s, and the strip (z5) lies over the
  # lock's top edge. The press follows the drop at once, inside the flash (SlDropNoSettle, no settle between). The strip is
  # found by a bounded poll in the page; the press is then a real mouse press on the lock's top 2 px, which the strip covers at rest
  # (the strip ends 2 px into the lock). The drop slides the tile's top for .22 s, so the probe reads the lock once that slide has
  # ended, where it rests: a point read mid-slide, or on the strip's lower edge, misses the lock.
  SlCase (SlSceneJson $pinsCQLock)
  SlDropNoSettle (SlAt (SlBox 1006) 0.5 0.5) (SlAt (SlBox 1001) 0.5 0.85)
  $fl = SlJs "new Promise(res => { let n = 0; (function poll() { const t = els.get(1001), k = t && t.querySelector('.lk'), p = document.querySelector('.peek.flash'); if (!p && ++n < 120) return requestAnimationFrame(poll); if (!k || !p) return res(null); Promise.all(t.getAnimations().map(a => a.finished.catch(() => null))).then(() => { const r = k.getBoundingClientRect(); const x = r.left + r.width / 2, y = r.top + 1; const e = document.elementFromPoint(x, y); res({ x: x, y: y, covered: !!(e && e.closest('.peek.flash')) }); }); })(); })"
  if (Shard-Take) {
  Check 'lock top edge, flash: scope, the flash strip is drawn over the lock''s top edge' ([bool]($fl -and $fl.covered)) "flash probe: $(SlShort $fl)"
  }
  $flPre = SlGet 'work[selId]'; $flPinPre = SlPin $flPre 'Refactor'
  if (Shard-Take) {
  Check 'lock top edge, flash: scope, the locked front window is stacked over the dropped one' ([bool]$flPinPre -and $flPinPre.lock -eq $true -and (SlHasBehind $flPinPre 'Quarterly')) "pin before the press: $(SlShort $flPinPre)"
  }
  if ($fl) { SlClick @([double]$fl.x, [double]$fl.y) }
  $flPost = SlGet 'work[selId]'; $flPinPost = SlPin $flPost 'Refactor'
  if (Shard-Take) {
  Check 'lock top edge, flash: a real press on the lock''s top edge during the flash toggles the lock off' ([bool]$flPinPost -and -not $flPinPost.lock) "pin after the press: $(SlShort $flPinPost)"
  }

  SlCase (SlSceneJson $pinsCQLock)
  $lkc = SlGet "(() => { const k = els.get(1001) && els.get(1001).querySelector('.lk'); if (!k) return null; const r = k.getBoundingClientRect(); return { x: r.left + r.width / 2, y: r.top + 2 }; })()"
  if ($lkc) { SlClick @([double]$lkc.x, [double]$lkc.y) }
  $lcPost = SlGet 'work[selId]'; $lcPin = SlPin $lcPost 'Refactor'
  if (Shard-Take) {
  Check 'control: a real press on the lock''s top edge with no flash toggles the lock off (as today)' ([bool]$lcPin -and -not $lcPin.lock) "pin after the press: $(SlShort $lcPin)"
  }

  # Named Badge. Scope first: the front tile is stacked (and narrow at 1024). The badge text is read from the visible content.
  SlViewport 1440 900; SlCase (SlSceneJson $pinsNamed)
  if (Shard-Take) {
  Check 'named badge, 1440: Refactor is stacked (scope)' ([bool](SlGet "els.get(1001).classList.contains('stacked')")) 'Refactor is not stacked'
  }
  $nb14 = SlBadgeText 1001
  if (Shard-Take) {
  Check 'named badge, 1440: the badge text names the window behind (Chrome)' ("$nb14" -like '*Chrome*') "badge text: $nb14"
  }
  SlViewport 1024 768; SlCase (SlSceneJson $pinsNamed)
  if (Shard-Take) {
  Check 'named badge, 1024: Refactor is a narrow stacked tile (scope)' ([bool](SlGet "els.get(1001).classList.contains('narrow') && els.get(1001).classList.contains('stacked')")) 'Refactor is not a narrow stacked tile'
  }
  $nb10 = SlBadgeText 1001
  if (Shard-Take) {
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
  }

  # Layered strip: the strip above a stacked tile is the front tile's. A real press there selects the front tile, and a drag
  # from it moves the front tile. Control: the same drag from the tile body moves it, as today.
  SlCase (SlSceneJson $pinsStrip)
  $stripBox = SlGet "(() => { const p = document.querySelector('.peek:not([hidden])'); if (!p) return null; const r = p.getBoundingClientRect(); return { l: r.left, t: r.top, w: r.width, h: r.height }; })()"
  if (Shard-Take) {
  Check 'strip: the front tile has its strip drawn above it (scope)' ([bool]$stripBox -and [bool](SlGet "els.get(1001).classList.contains('peeked')")) "strip: $(SlFmt $stripBox)"
  }
  $selBefore = SlGet "els.get(1001).classList.contains('sel')"
  if (Shard-Take) {
  Check 'strip: the front tile is not selected before the press (scope)' ($selBefore -eq $false) "selected before: $selBefore"
  }
  SlClick @([double]($stripBox.l + $stripBox.w * 0.5), [double]($stripBox.t + 5))
  $selAfter = SlGet "els.get(1001).classList.contains('sel')"
  if (Shard-Take) {
  Check 'strip: a real press in the strip selects the front tile' ($selAfter -eq $true) "selected after the press: $selAfter"
  }

  SlCase (SlSceneJson $pinsStrip)
  $rbC = SlBox 1001; $qbC = SlBox 1006
  $pitchC = ($qbC.l + $qbC.w / 2) - ($rbC.l + $rbC.w / 2)
  SlDrag (SlAt $rbC 0.5 0.5) @([double]($rbC.l + $rbC.w / 2 + 3 * $pitchC), [double]($rbC.t + $rbC.h / 2))
  $ctlS = SlGet 'work[selId]'; $ctlR = SlPin $ctlS 'Refactor'
  if (Shard-Take) {
  Check 'control: a drag from the front tile body moves it to the cell under the pointer (as today)' ([bool]$ctlR -and (SlCells $ctlR) -eq '3') "claude pin: $(SlShort $ctlR)"
  }

  SlCase (SlSceneJson $pinsStrip)
  $rbS = SlBox 1001; $qbS = SlBox 1006
  $pitchS = ($qbS.l + $qbS.w / 2) - ($rbS.l + $rbS.w / 2)
  $skS = SlGet "(() => { const p = document.querySelector('.peek:not([hidden])'); if (!p) return null; const r = p.getBoundingClientRect(); return { l: r.left, t: r.top, w: r.width, h: r.height }; })()"
  SlDrag @([double]($skS.l + $skS.w * 0.5), [double]($skS.t + 5)) @([double]($rbS.l + $rbS.w / 2 + 3 * $pitchS), [double]($rbS.t + $rbS.h / 2))
  $stS = SlGet 'work[selId]'; $stR = SlPin $stS 'Refactor'
  if (Shard-Take) {
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
  if (Shard-Take) {
  foreach ($hc in $handleCases) {
    SlCase (SlSceneJson (SlPins ('{"app":"claude","match":"Refactor","mon":"wide","slots":[' + $hc.start + ']}')))
    SlClick (SlAt (SlBox 1001) 0.5 0.5)
    Check "edge: the $($hc.name) handle is drawn on the selected tile" ([bool](SlHandle $hc.dir)) "no $($hc.dir) handle"
    [void](SlHandleDrag $hc.dir $hc.dx $hc.dy)
    $hp = SlPin (SlGet 'work[selId]') 'Refactor'
    Check "edge: the $($hc.name) handle resizes the tile by whole cells, to $($hc.want)" ([bool]$hp -and (SlCells $hp) -eq $hc.want) "claude pin: $(SlShort $hp)"
  }
  }
  # East over a covered window: the window in the way moves to the first free cell, with the span, in one edit.
  SlCase (SlSceneJson $pinsCQ)
  SlClick (SlAt (SlBox 1001) 0.5 0.5)
  [void](SlHandleDrag 'ea' 1 0)
  $ew = SlGet 'work[selId]'; $ewr = SlPin $ew 'Refactor'; $ewq = SlPin $ew 'Quarterly'
  if (Shard-Take) {
  Check 'edge: the east handle sends a covered pinned window to Windows That Stay Put' ([bool]$ewr -and (SlCells $ewr) -eq '0,1' -and -not $ewq -and (SlHasBay $ew 'Quarterly')) "claude: $(SlShort $ewr); chrome: $(SlShort $ewq); bay: $(SlShort $ew.bay)"
  }
  # A lock stops the east handle, as it stops the corner grip. The first check is the handle; the two after it are guards.
  SlCase (SlSceneJson $pinsResizeLock)
  SlClick (SlAt (SlBox 1001) 0.5 0.5)
  if (Shard-Take) {
  Check 'edge: the east handle is drawn on a tile next to a locked one' ([bool](SlHandle 'ea')) 'no ea handle'
  }
  [void](SlHandleDrag 'ea' 1 0)
  $lsc = SlGet 'work[selId]'; $lr = SlPin $lsc 'Refactor'; $lq = SlPin $lsc 'Quarterly'
  if (Shard-Take) {
  Check 'guard: a locked tile stops the east handle, so the tile stays one cell' ([bool]$lr -and (SlCells $lr) -eq '0') "claude pin: $(SlShort $lr)"
  Check 'guard: a locked tile stops the east handle, and keeps its cell and lock' ([bool]$lq -and $lq.lock -eq $true -and (SlCells $lq) -eq '1') "chrome pin: $(SlShort $lq)"
  }

  # A top or left handle moves only its own edge. Toward a lock, the tile stops short of it and keeps the other dimension:
  # the north handle keeps a 3-cell span's width, and the west handle keeps a 2-row tile's height. Control: no lock in the way.
  # Negative drags are parenthesized: a bare -1 after a positional argument is read as the text "-1".
  SlCase (SlSceneJson $pinsTopFree)
  SlClick (SlAt (SlBox 1001) 0.5 0.5)
  if (Shard-Take) {
  Check 'edge: the north handle is drawn on the 3-cell span (control scope)' ([bool](SlHandle 'n')) 'no n handle'
  }
  [void](SlHandleDrag 'n' 0 (-1))
  $tfp = SlPin (SlGet 'work[selId]') 'Refactor'
  if (Shard-Take) {
  Check 'control: the north handle grows the 3-cell span up when no lock is in the way' ([bool]$tfp -and (SlCells $tfp) -eq '0,1,2,5,6,7') "claude pin: $(SlShort $tfp)"
  }

  SlCase (SlSceneJson $pinsTopLock)
  SlClick (SlAt (SlBox 1001) 0.5 0.5)
  if (Shard-Take) {
  Check 'edge: the north handle is drawn on the 3-cell span with a lock above its third cell' ([bool](SlHandle 'n')) 'no n handle'
  }
  [void](SlHandleDrag 'n' 0 (-1))
  $tpS = SlGet 'work[selId]'; $tpR = SlPin $tpS 'Refactor'; $tpQ = SlPin $tpS 'Quarterly'
  if (Shard-Take) {
  Check 'edge: a north handle drag toward the lock stops short of it, keeping the span''s width (cells 5,6,7)' ([bool]$tpR -and (SlCells $tpR) -eq '5,6,7') "claude pin: $(SlShort $tpR)"
  Check 'guard: a north handle drag toward the lock leaves the locked tile in its cell' ([bool]$tpQ -and $tpQ.lock -eq $true -and (SlCells $tpQ) -eq '2') "locked pin: $(SlShort $tpQ)"
  }

  SlCase (SlSceneJson $pinsLeftFree)
  SlClick (SlAt (SlBox 1001) 0.5 0.5)
  if (Shard-Take) {
  Check 'edge: the west handle is drawn on the 2-row tile (control scope)' ([bool](SlHandle 'w')) 'no w handle'
  }
  [void](SlHandleDrag 'w' (-1) 0)
  $lfp = SlPin (SlGet 'work[selId]') 'Refactor'
  if (Shard-Take) {
  Check 'control: the west handle grows the 2-row tile left when no lock is in the way' ([bool]$lfp -and (SlCells $lfp) -eq '1,2,6,7') "claude pin: $(SlShort $lfp)"
  }

  SlCase (SlSceneJson $pinsLeftLock)
  SlClick (SlAt (SlBox 1001) 0.5 0.5)
  if (Shard-Take) {
  Check 'edge: the west handle is drawn on the 2-row tile with a lock beside its lower row' ([bool](SlHandle 'w')) 'no w handle'
  }
  [void](SlHandleDrag 'w' (-1) 0)
  $lpS = SlGet 'work[selId]'; $lpR = SlPin $lpS 'Refactor'; $lpQ = SlPin $lpS 'Quarterly'
  if (Shard-Take) {
  Check 'edge: a west handle drag toward the lock stops short of it, keeping the tile''s height (cells 2,7)' ([bool]$lpR -and (SlCells $lpR) -eq '2,7') "claude pin: $(SlShort $lpR)"
  Check 'guard: a west handle drag toward the lock leaves the locked tile in its cell' ([bool]$lpQ -and $lpQ.lock -eq $true -and (SlCells $lpQ) -eq '6') "locked pin: $(SlShort $lpQ)"
  }

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
  if (Shard-Take) {
  Check 'scope: the east handle is drawn on the 1x2 tile' ([bool](SlHandle 'ea')) 'no ea handle'
  }
  [void](SlHandleDrag 'ea' 1 0 3)
  $ce = SlPin (SlGet 'work[selId]') 'Refactor'
  if (Shard-Take) {
  Check 'control: an east drag with no lock in the way spans 4 columns and keeps 2 rows (as today)' ([bool]$ce -and (SlCells $ce) -eq '0,1,2,3,5,6,7,8') "claude pin: $(SlShort $ce)"
  }
  SlCase (SlSceneJson $pinsEastTallLock)
  SlClick (SlAt (SlBox 1001) 0.5 0.5)
  if (Shard-Take) {
  Check 'scope: the east handle is drawn on the 1x2 tile next to a lock' ([bool](SlHandle 'ea')) 'no ea handle'
  }
  [void](SlHandleDrag 'ea' 1 0 3)
  $ee = SlGet 'work[selId]'; $eeR = SlPin $ee 'Refactor'; $eeQ = SlPin $ee 'Quarterly'
  if (Shard-Take) {
  Check 'edge: an east drag toward a lock keeps the 1x2 tile''s 2 rows, so it stops at 2 columns (cells 0,1,5,6)' ([bool]$eeR -and (SlCells $eeR) -eq '0,1,5,6') "claude pin: $(SlShort $eeR)"
  Check 'guard: an east drag toward a lock leaves the locked tile in its cell' ([bool]$eeQ -and $eeQ.lock -eq $true -and (SlCells $eeQ) -eq '7') "locked pin: $(SlShort $eeQ)"
  }

  # South, on a 3 by 3 grid: a 2x1 tile in row 0, both columns. The lock is at column 1, row 1 (slot 4). The drag is 2 cells south.
  SlCase (SlSceneJson $pinsSouthWide '[]' '' '' $sq33)
  SlClick (SlAt (SlBox 1001) 0.5 0.5)
  if (Shard-Take) {
  Check 'scope: the south handle is drawn on the 2x1 tile' ([bool](SlHandle 's')) 'no s handle'
  }
  [void](SlHandleDrag 's' 0 1 2)
  $cs = SlPin (SlGet 'work[selId]') 'Refactor'
  if (Shard-Take) {
  Check 'control: a south drag with no lock in the way spans 3 rows and keeps 2 columns (as today)' ([bool]$cs -and (SlCells $cs) -eq '0,1,3,4,6,7') "claude pin: $(SlShort $cs)"
  }
  SlCase (SlSceneJson $pinsSouthWideLock '[]' '' '' $sq33)
  SlClick (SlAt (SlBox 1001) 0.5 0.5)
  if (Shard-Take) {
  Check 'scope: the south handle is drawn on the 2x1 tile next to a lock' ([bool](SlHandle 's')) 'no s handle'
  }
  [void](SlHandleDrag 's' 0 1 2)
  $ss = SlPin (SlGet 'work[selId]') 'Refactor'
  if (Shard-Take) {
  Check 'edge: a south drag toward a lock keeps the 2x1 tile''s 2 columns, so it stops at 1 row (cells 0,1)' ([bool]$ss -and (SlCells $ss) -eq '0,1') "claude pin: $(SlShort $ss)"
  }

  # North-east corner, on a 3 by 3 grid: a 1x1 tile at the bottom left (slot 6). The lock is at column 2, row 1 (slot 5).
  # The drag goes to the top right of the grid. The largest span short of the lock is 2 columns by 3 rows.
  SlCase (SlSceneJson $pinsCornerNE '[]' '' '' $sq33)
  SlClick (SlAt (SlBox 1001) 0.5 0.5)
  if (Shard-Take) {
  Check 'scope: the north-east handle is drawn on the 1x1 tile' ([bool](SlHandle 'tr')) 'no tr handle'
  }
  [void](SlHandleDrag 'tr' 1 (-1) 2)
  $ct = SlPin (SlGet 'work[selId]') 'Refactor'
  if (Shard-Take) {
  Check 'control: a north-east drag with no lock in the way spans the whole 3x3 grid (as today)' ([bool]$ct -and (SlCells $ct) -eq '0,1,2,3,4,5,6,7,8') "claude pin: $(SlShort $ct)"
  }
  SlCase (SlSceneJson $pinsCornerNELock '[]' '' '' $sq33)
  SlClick (SlAt (SlBox 1001) 0.5 0.5)
  if (Shard-Take) {
  Check 'scope: the north-east handle is drawn on the 1x1 tile next to a lock' ([bool](SlHandle 'tr')) 'no tr handle'
  }
  [void](SlHandleDrag 'tr' 1 (-1) 2)
  $cn = SlPin (SlGet 'work[selId]') 'Refactor'
  if (Shard-Take) {
  Check 'corner: a north-east drag toward a lock keeps the largest span short of it, 2 columns by 3 rows (cells 0,1,3,4,6,7)' ([bool]$cn -and (SlCells $cn) -eq '0,1,3,4,6,7') "claude pin: $(SlShort $cn)"
  }

  # South-west corner, on a 3 by 3 grid: a 1x1 tile at the top right (slot 2). The lock is at column 1, row 2 (slot 7).
  # The drag goes to the bottom left of the grid. The largest span short of the lock is 3 columns by 2 rows.
  SlCase (SlSceneJson $pinsCornerSW '[]' '' '' $sq33)
  SlClick (SlAt (SlBox 1001) 0.5 0.5)
  if (Shard-Take) {
  Check 'scope: the south-west handle is drawn on the 1x1 tile' ([bool](SlHandle 'bl')) 'no bl handle'
  }
  [void](SlHandleDrag 'bl' (-1) 1 2)
  $cw = SlPin (SlGet 'work[selId]') 'Refactor'
  if (Shard-Take) {
  Check 'control: a south-west drag with no lock in the way spans the whole 3x3 grid (as today)' ([bool]$cw -and (SlCells $cw) -eq '0,1,2,3,4,5,6,7,8') "claude pin: $(SlShort $cw)"
  }
  SlCase (SlSceneJson $pinsCornerSWLock '[]' '' '' $sq33)
  SlClick (SlAt (SlBox 1001) 0.5 0.5)
  if (Shard-Take) {
  Check 'scope: the south-west handle is drawn on the 1x1 tile next to a lock' ([bool](SlHandle 'bl')) 'no bl handle'
  }
  [void](SlHandleDrag 'bl' (-1) 1 2)
  $cbl = SlPin (SlGet 'work[selId]') 'Refactor'
  if (Shard-Take) {
  Check 'corner: a south-west drag toward a lock keeps the largest span short of it, 3 columns by 2 rows (cells 0,1,2,3,4,5)' ([bool]$cbl -and (SlCells $cbl) -eq '0,1,2,3,4,5') "claude pin: $(SlShort $cbl)"
  }

  # Ctrl+Shift+arrows (board-feedback-notes item 12): the Shift+arrow rules, on the top and left edges. Shift+arrows are the
  # green controls beside them, so a key that never reaches the page cannot pass.
  SlCase (SlSceneJson $pinsKeyLeft)
  SlClick (SlAt (SlBox 1006) 0.5 0.5)
  SlKey 1006 'ArrowRight' 39 8
  $kc = SlPin (SlGet 'work[selId]') 'Quarterly'
  if (Shard-Take) {
  Check 'control: Shift+ArrowRight still grows the right edge of a pinned tile' ([bool]$kc -and (SlCells $kc) -eq '1,2') "chrome pin: $(SlShort $kc)"
  }
  SlCase (SlSceneJson $pinsKeyLeft)
  SlClick (SlAt (SlBox 1006) 0.5 0.5)
  SlKey 1006 'ArrowLeft' 37 10
  $kl = SlGet 'work[selId]'; $klq = SlPin $kl 'Quarterly'; $klr = SlPin $kl 'Refactor'
  if (Shard-Take) {
  Check 'keys: Ctrl+Shift+ArrowLeft grows the left edge of a pinned tile to 2 columns' ([bool]$klq -and (SlCells $klq) -eq '0,1') "chrome pin: $(SlShort $klq)"
  Check 'keys: the covered pinned window goes to Windows That Stay Put, with its stack' ([bool](-not $klr -and (SlHasBay $kl 'Refactor') -and (SlHasBay $kl 'Draft release'))) "claude pin: $(SlShort $klr); bay: $(SlShort $kl.bay)"
  }
  SlCase (SlSceneJson $pinsKeyUp)
  SlClick (SlAt (SlBox 1001) 0.5 0.5)
  SlKey 1001 'ArrowUp' 38 10
  $ku = SlPin (SlGet 'work[selId]') 'Refactor'
  if (Shard-Take) {
  Check 'keys: Ctrl+Shift+ArrowUp grows the top edge of a pinned tile to 2 rows' ([bool]$ku -and (SlCells $ku) -eq '1,6') "claude pin: $(SlShort $ku)"
  }
  SlCase (SlSceneJson $pinsKeySpan)
  SlClick (SlAt (SlBox 1006) 0.5 0.5)
  SlKey 1006 'ArrowLeft' 37 8
  $ksc = SlPin (SlGet 'work[selId]') 'Quarterly'
  if (Shard-Take) {
  Check 'control: Shift+ArrowLeft still shrinks the right edge of a 2-column span' ([bool]$ksc -and (SlCells $ksc) -eq '0') "chrome pin: $(SlShort $ksc)"
  }
  SlCase (SlSceneJson $pinsKeySpan)
  SlClick (SlAt (SlBox 1006) 0.5 0.5)
  SlKey 1006 'ArrowRight' 39 10
  $ksh = SlPin (SlGet 'work[selId]') 'Quarterly'
  if (Shard-Take) {
  Check 'keys: Ctrl+Shift+ArrowRight shrinks the left edge of a 2-column span to 1 column' ([bool]$ksh -and (SlCells $ksh) -eq '1') "chrome pin: $(SlShort $ksh)"
  }
  SlCase (SlSceneJson $pinsKeyColSpan)
  SlClick (SlAt (SlBox 1006) 0.5 0.5)
  SlKey 1006 'ArrowUp' 38 8
  $kcs = SlPin (SlGet 'work[selId]') 'Quarterly'
  if (Shard-Take) {
  Check 'control: Shift+ArrowUp still shrinks the bottom edge of a 2-row span' ([bool]$kcs -and (SlCells $kcs) -eq '1') "chrome pin: $(SlShort $kcs)"
  }
  SlCase (SlSceneJson $pinsKeyColSpan)
  SlClick (SlAt (SlBox 1006) 0.5 0.5)
  SlKey 1006 'ArrowDown' 40 10
  $kcd = SlPin (SlGet 'work[selId]') 'Quarterly'
  if (Shard-Take) {
  Check 'keys: Ctrl+Shift+ArrowDown shrinks the top edge of a 2-row span to 1 row' ([bool]$kcd -and (SlCells $kcd) -eq '6') "chrome pin: $(SlShort $kcd)"
  }
  SlCase (SlSceneJson $pinsCQLock)
  SlClick (SlAt (SlBox 1006) 0.5 0.5)
  SlKey 1006 'ArrowLeft' 37 10
  $kk = SlGet 'work[selId]'; $kkq = SlPin $kk 'Quarterly'; $kkr = SlPin $kk 'Refactor'
  $kkmsg = SlJs "document.getElementById('msg').textContent"
  if (Shard-Take) {
  Check 'keys: Ctrl+Shift+ArrowLeft toward a locked tile is refused, and says so' ("$kkmsg" -match 'locked tile is in the way') "status: $kkmsg"
  Check 'guard: Ctrl+Shift+ArrowLeft toward a locked tile leaves the locked tile in its cell' ([bool]$kkr -and $kkr.lock -eq $true -and (SlCells $kkr) -eq '0') "locked pin: $(SlShort $kkr)"
  Check 'guard: Ctrl+Shift+ArrowLeft toward a locked tile does not grow the window onto it' ([bool]$kkq -and (SlCells $kkq) -eq '1') "chrome pin: $(SlShort $kkq)"
  }
  SlCase (SlSceneJson $pinsFullStack)
  SlClick (SlAt (SlBox 1002) 0.5 0.5)
  SlKey 1002 'ArrowLeft' 37 10
  $kf = SlGet 'work[selId]'; $kfp = SlPin $kf 'Pin parser'
  if (Shard-Take) {
  Check 'keys: with no free cell, Ctrl+Shift+ArrowLeft grows the tile onto the covered window''s cell' ([bool]$kfp -and (SlCells $kfp) -eq '0,1') "pin parser: $(SlShort $kfp)"
  Check 'keys: with no free cell, the covered pinned window goes to Windows That Stay Put' (SlHasBay $kf 'Refactor') "bay: $(SlShort $kf.bay)"
  }

  # Fill Empty Cells switch (page). It is on the fill monitor's Monitor section; off writes fill.off, saves, and reloads off.
  SlCase (SlSceneJson $pinsCQ '["*"]')
  if (Shard-Take) {
  Check 'fill switch: the Ultrawide label reads "fills" (scope)' ([bool](SlJs "[...document.querySelectorAll('.mlab .num')].some(n => n.textContent.includes('fills'))")) 'no monitor reads fills'
  }
  $sw0 = SlSwitch
  if (Shard-Take) {
  Check 'fill switch: the inspector shows a Fill Empty Cells switch, checked' ($sw0 -eq $true) "switch: $sw0"
  }
  [void](SlSwitch -Click); SlSettle
  $swOff = SlGet 'work[selId].fill.off'
  if (Shard-Take) {
  Check 'fill switch: turning it off writes fill.off to the scene' ($swOff -eq $true) "fill.off: $swOff"
  }
  [void](SlJs "(() => { const b = document.getElementById('save'); if (b && !b.disabled) { b.click(); return true; } return false; })()")
  SlSettle
  $swSaved = SlSavedScene
  if (Shard-Take) {
  Check 'fill switch: the saved scene keeps fill.off' ([bool]($swSaved -and $swSaved.fill.off -eq $true)) "saved fill: $(SlShort $swSaved.fill)"
  }
  SlLoad
  $swBack = SlSwitch
  if (Shard-Take) {
  Check 'fill switch: after a reload the switch is still off' ($swBack -eq $false) "switch after reload: $swBack"
  }

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
  if (Shard-Take) {
  Check 'clear board: the board has a Clear Board button, and it presses' ($cbPress -eq 'pressed') "button: $cbPress"
  Check 'clear board: it turns Fill Empty Cells off in the scene' ($cbScene -eq $true) "fill.off: $cbScene"
  # Clear Board is unchanged by the switch's pins (decisions/fill-controls.md): it adds no pin, so the windows it clears stay unpinned.
  Check 'clear board: it adds no pins to the scene' ($cbPinsNow -eq $cbPinsWas) "pins before: $cbPinsWas, after: $cbPinsNow"
  }
  # Clear Board holds nothing (decisions/fill-controls.md): no held layout, so every cleared window is listed, not kept in its cell.
  $cbHeld = SlList 'work[selId].fill.held'
  if (Shard-Take) {
  Check 'clear board: it holds no windows (fill.held stays empty)' (@($cbHeld).Count -eq 0) "fill.held: $(SlShort $cbHeld)"
  Check 'clear board: only the pinned windows stay on the board' ($cbAfter -eq '1001,1006') "placed: $cbAfter"
  }
  # The windows the fill placed before the press, minus the two pins (1001 Refactor, 1006 Quarterly). With '*' the fill skips
  # apps that have a pin (claude, chrome), so those windows were never on the board and are not in this set.
  $cbFilled = @("$cbWas" -split ',' | ? { $_ -and $_ -ne '1001' -and $_ -ne '1006' } | % { [int]$_ })
  if (Shard-Take) {
  Check 'clear board: every window the fill had placed is in Windows That Stay Put' ($cbFilled.Count -gt 0 -and @($cbFilled | ? { $cbLeft -notcontains $_ }).Count -eq 0) "filled before: $($cbFilled -join ','); left: $($cbLeft -join ',')"
  Check 'clear board: the status line says what it did' ("$cbMsg" -like '*Cleared the board*') "status: $cbMsg"
  Check 'clear board: the list gives the reason "Fill is off"' ([bool]$cbList) 'no "Fill is off" on the board'
  }
  $cbOff = SlSwitch
  [void](SlSwitch -Click); SlSettle
  $cbOn = "$(SlJs $placedIds)"
  if (Shard-Take) {
  Check 'clear board: turning Fill Empty Cells back on refills the board to the same windows' ($cbOff -eq $false -and $cbWas -ne '' -and $cbOn -eq $cbWas) "switch was: $cbOff; placed before: $cbWas; after: $cbOn"
  }

  # Fill Empty Cells off holds the windows the fill or a zone placed, each where it is (decisions/fill-controls.md, owner ruling
  # 2026-11-12 12:05 CST). The scene keeps them in fill.held, apart from its pins: the switch adds no pin, no pin mark shows, and
  # every held window keeps its cell on the board and in a dry run. The owner's pins and locks are not touched.
  SlViewport 1440 900; SlCase (SlSceneJson $pinsCQLock '["*"]' ',"zones":[{"mon":"wide","slots":[5,6],"app":"WindowsTerminal"}]')
  $pinsWas = SlList 'work[selId].pins'
  $offBefore = SlList "prevs[selId].placed.filter(p => p.pin < 0).map(p => ({ id: p.id, app: p.app, slots: p.slots, zone: p.zone }))"
  if (Shard-Take) {
  Check 'switch off, scope: before the switch, the fill and a zone have placed windows' ($offBefore.Count -gt 0 -and @($offBefore | ? { $_.zone -ge 0 }).Count -ge 1) "placed by fill or zone: $(SlShort $offBefore)"
  }
  [void](SlSwitch -Click); SlSettle
  $offAfter = SlList "prevs[selId].placed.map(p => ({ id: p.id, pin: p.pin, slots: p.slots }))"
  $offPins = SlList 'work[selId].pins'
  $held = SlList 'work[selId].fill.held'
  $moved = @()
  foreach ($b in $offBefore) {
    $a = @($offAfter | ? { $_.id -eq $b.id })[0]
    if (-not $a -or ((@($a.slots) | Sort-Object) -join ',') -ne ((@($b.slots) | Sort-Object) -join ',')) { $moved += "$($b.id)" }
  }
  if (Shard-Take) {
  Check 'switch off: every window the fill or a zone placed keeps its cell' ($moved.Count -eq 0 -and $offBefore.Count -gt 0) "not kept in place: $($moved -join ','); placed after: $(SlShort $offAfter)"
  Check 'switch off: fill.held has one entry per window the fill or a zone placed' (@($held).Count -eq $offBefore.Count -and $offBefore.Count -gt 0) "fill.held: $(SlShort $held); placed: $(SlShort $offBefore)"
  Check 'switch off: the switch adds no pin, so the scene''s pins are as they were' ((ConvertTo-Json -Depth 12 -Compress @($offPins)) -ceq (ConvertTo-Json -Depth 12 -Compress @($pinsWas))) "pins before: $(SlShort $pinsWas); after: $(SlShort $offPins)"
  }
  $offIdsJs = '[' + ((@($offBefore) | % { [int]$_.id }) -join ',') + ']'
  $pmShown = SlList "prevs[selId].placed.filter(p => $offIdsJs.includes(p.id)).map(p => p.id).filter(id => { const t = els.get(id); return !!t && (t.classList.contains('pin') || !!t.querySelector('.pinmark')); })"
  if (Shard-Take) {
  Check 'switch off: no pin mark shows on a held window' ($offBefore.Count -gt 0 -and @($pmShown).Count -eq 0) "pin mark on: $(SlShort $pmShown)"
  }

  # A held window's cell stays empty when the window is sent to Windows That Stay Put, and a dry-run Apply places the same windows
  # in the same cells as the board shows (tile.ps1 -DryRun, through SlDry).
  $sendWin = @($offBefore | ? { $_.zone -lt 0 })[0]
  $sendId = if ($sendWin) { [int]$sendWin.id } else { 0 }
  $freedSlots = if ($sendWin) { @($sendWin.slots) } else { @() }
  # One named cause when the switch did not hold it: the steps below need that window held in its cell, so they wait on this check.
  $sendHeld = @($offAfter | ? { $_.id -eq $sendId -and $_.pin -lt 0 -and ((@($_.slots) | Sort-Object) -join ',') -eq ((@($freedSlots) | Sort-Object) -join ',') }).Count -gt 0
  if (Shard-Take) {
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
  }
  # A locked pin for a closed window holds no cell in the engine, so the fill puts an open window on that cell. Turning the
  # switch off keeps the locked pin and its lock, and that window goes to Windows That Stay Put unpinned: nothing is placed
  # over a locked tile (decisions/stack-and-lock.md, a locked tile never moves).
  SlCase (SlSceneJson '[{"app":"closedapp","match":"","mon":"wide","slots":[0],"lock":true}]' '["*"]')
  $lkOn = SlList "prevs[selId].placed.filter(p => p.slots.includes(1)).map(p => ({ id: p.id, app: p.app, pin: p.pin }))"
  $lkWin = @($lkOn)[0]
  if (Shard-Take) {
  Check 'closed locked pin, scope: the fill has put an open window on the locked pin cell' ([bool]($lkWin -and [int]$lkWin.pin -lt 0)) "placed on slot 1: $(SlShort $lkOn)"
  }
  [void](SlSwitch -Click); SlSettle
  $lkPins = SlList 'work[selId].pins'
  $lkLock = @($lkPins | ? { "$($_.app)" -eq 'closedapp' })[0]
  if (Shard-Take) {
  Check 'closed locked pin: turning the switch off keeps the locked pin in its cell, with its lock' ([bool]($lkLock -and $lkLock.lock -eq $true -and (SlCells $lkLock) -eq '0')) "locked pin: $(SlShort $lkLock)"
  }
  $lkOver = @($lkPins | ? { "$($_.app)" -eq "$($lkWin.app)" -and (SlCells $_) -eq '0' })
  $lkBay = SlBayIds
  if (Shard-Take) {
  Check 'closed locked pin: the window the fill had on that cell goes to Windows That Stay Put, unpinned' ([bool]($lkWin -and $lkOver.Count -eq 0 -and ($lkBay -contains [int]$lkWin.id))) "pins on slot 0: $(SlShort $lkOver); bay ids: $($lkBay -join ',')"
  }
  # Nothing is held over a locked cell: no window is placed on that cell as a held one (no unpinned placement on slot 1).
  $lkCell = SlList "prevs[selId].placed.filter(p => p.slots.includes(1)).map(p => ({ id: p.id, pin: p.pin }))"
  if (Shard-Take) {
  Check 'closed locked pin: no window is held over the locked cell' (@($lkCell | ? { $_.pin -lt 0 }).Count -eq 0) "placed on the locked cell: $(SlShort $lkCell)"
  }
  # Fill on again: the window the switch sent to Windows That Stay Put is filled as usual. The bay entry the hold left must not outlive it.
  $lkId = if ($lkWin) { [int]$lkWin.id } else { 0 }
  [void](SlSwitch -Click); SlSettle
  $lkBackPlaced = SlList "prevs[selId].placed.filter(p => p.id === $lkId).map(p => ({ id: p.id, pin: p.pin, slots: p.slots }))"
  $lkBackBay = SlBayIds
  if (Shard-Take) {
  Check 'closed locked pin, fill on again: the window is filled as usual and is not in Windows That Stay Put' ([bool]($lkId -gt 0 -and @($lkBackPlaced).Count -eq 1 -and $lkBackPlaced[0].pin -lt 0 -and -not ($lkBackBay -contains $lkId))) "placed: $(SlShort $lkBackPlaced); bay ids: $($lkBackBay -join ',')"
  }
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
  if (Shard-Take) {
  Check 'unlocked closed pin, scope: the pin has no lock, and the fill has put an open window on its cell among three or more placed' ([bool]($ucPin -and -not $ucPin.lock -and $ucId -gt 0 -and $ucFill -ge 3)) "pin: $(SlShort $ucPin); on slot 1: $(SlShort $ucOn); fill-placed: $ucFill"
  }
  [void](SlSwitch -Click); SlSettle
  $ucHeld = SlList 'work[selId].fill.held'
  if (Shard-Take) {
  Check 'unlocked closed pin: the window the fill had on its cell is not held over it' (-not @($ucHeld | ? { [int]$_.id -eq $ucId }).Count) "fill.held: $(SlShort $ucHeld)"
  }
  $ucBay = SlBayIds
  if (Shard-Take) {
  Check 'unlocked closed pin: that window goes to Windows That Stay Put' ([bool]($ucId -gt 0 -and ($ucBay -contains $ucId))) "bay ids: $($ucBay -join ',')"
  }
  $ucMsg = SlJs "document.getElementById('msg').textContent"
  $ucWant = $ucFill - 1
  if (Shard-Take) {
  Check "unlocked closed pin: the status line counts $ucWant windows held, one fewer than the fill placed" ([bool]("$ucMsg" -like "*$ucWant windows are held where they are.*")) "status: $ucMsg"
  }

  # The status line names how many windows the switch holds. The count is the windows the fill or a zone had placed before
  # the switch (each is held in its cell), so the scope is read first and the line after the switch.
  SlCase (SlSceneJson $pinsCQ '["*"]')
  $kpIds = SlList "prevs[selId].placed.filter(p => p.pin < 0 && !p.behind).map(p => p.id)"
  $kpN = @($kpIds).Count
  if (Shard-Take) {
  Check 'switch off status, scope: the fill has placed at least two windows the switch holds' ($kpN -ge 2) "fill-placed windows: $kpN"
  }
  [void](SlSwitch -Click); SlSettle
  $kpMsg = SlJs "document.getElementById('msg').textContent"
  if (Shard-Take) {
  Check 'switch off status: the status line gives the count of windows held where they are' ([bool]("$kpMsg" -like "*$kpN windows are held where they are.*")) "status: $kpMsg"
  }

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
  if (Shard-Take) {
  Check 'switch during a drop, scope: the drop pins Pin parser in the cell it was dropped on, and its engine answer is still pending' ([bool]($dpMoved -and (SlCells $dpMoved) -eq '5' -and $dpPending)) "pin: $(SlShort $dpMoved); answer still pending: $dpPending"
  }
  [void](SlSwitch -Click); SlSettle
  $dpAfter = SlPin (SlGet 'work[selId]') 'Pin parser'
  if (Shard-Take) {
  Check 'switch during a drop: Pin parser stays pinned where it was dropped, not in its old cell' ([bool]($dpAfter -and (SlCells $dpAfter) -eq '5')) "pin: $(SlShort $dpAfter)"
  }
  # Fill Empty Cells off, on the board. The owner's pins (Refactor in claude, Quarterly in chrome) give their apps a pinned window. Each
  # open window still unpinned in Windows That Stay Put must be shown as "Fill is off", not "Not in this scene". The switch
  # holds the windows the fill placed and adds no pin. The control is the same board before the switch: no window reads "Fill is off".
  SlViewport 1440 900; SlCase (SlSceneJson $pinsCQ '["*"]')
  $n1Before = SlList "[...document.querySelectorAll('#bgrps [data-bay]')].map(b => b.getAttribute('aria-label'))"
  if (Shard-Take) {
  Check 'control, fill on, board: no window in Windows That Stay Put reads "Fill is off"' (@($n1Before | ? { "$_" -like '*Fill is off*' }).Count -eq 0) "labels: $(SlShort $n1Before)"
  }
  $n1PinsWas = SlList 'work[selId].pins'
  [void](SlSwitch -Click); SlSettle
  $n1PinsNow = SlList 'work[selId].pins'
  if (Shard-Take) {
  Check 'fill off, board: the switch adds no pin' ((ConvertTo-Json -Depth 12 -Compress @($n1PinsNow)) -ceq (ConvertTo-Json -Depth 12 -Compress @($n1PinsWas))) "pins before: $(SlShort $n1PinsWas); after: $(SlShort $n1PinsNow)"
  }
  $n1Scope = SlList "(() => { const pinned = new Set(work[selId].pins.map(p => p.app)); return [...document.querySelectorAll('#bgrps [data-bay]')].map(b => snap.windows.find(w => w.id === +b.dataset.bay)).filter(w => w && !w.min && pinned.has(w.app)).map(w => w.id); })()"
  if (Shard-Take) {
  Check 'fill off, board, scope: an unpinned window is in Windows That Stay Put, and its app has a pinned window' ($n1Scope.Count -ge 1) "windows: $($n1Scope -join ',')"
  }
  # A chip's reason is its own line when it has one. A reason its category's windows share is in the heading instead (Reason Said Once).
  $n1Chips = SlList "[...document.querySelectorAll('#bgrps [data-bay]')].map(b => { const cat = (b.className.match(/cat-([a-z]+)/) || [])[1]; const h = [...document.querySelectorAll('#bgrps h3')].find(e => e.classList.contains('cat-' + cat) && e.querySelector('.why')); const small = b.querySelector('small'); return { id: +b.dataset.bay, min: !!(snap.windows.find(w => w.id === +b.dataset.bay) || {}).min, reason: small ? small.textContent.trim() : (h ? h.querySelector('.why').textContent.trim() : null) }; })"
  $n1Open = @($n1Chips | ? { -not $_.min })
  $n1Bad = @($n1Open | ? { $_.reason -ne 'Fill is off' })
  if (Shard-Take) {
  Check 'fill off, board: every unpinned window in Windows That Stay Put is shown as "Fill is off" (its line, or its heading''s shared reason)' ($n1Open.Count -gt 0 -and $n1Bad.Count -eq 0) "open: $($n1Open.Count); not 'Fill is off': $(@($n1Bad | % { "$($_.id) (shown as: $(if ($_.reason) { $_.reason } else { 'none' }))" }) -join ', ')"
  }
  # The inspector says the same for one of them: Draft release notes (1003, unpinned, its app Claude has pinned windows).
  SlJs 'document.querySelector("[data-bay=\"1003\"]").click(); true'
  $n1Insp = SlGet '(() => { const m = document.querySelector("#win .m"); return m ? m.textContent.replace(/\s+/g, " ").trim() : null; })()'
  if (Shard-Take) {
  Check 'fill off, board: the inspector gives "fill is off" as the reason for Draft release notes' ([bool]("$n1Insp" -like '*fill is off*')) "inspector line: $n1Insp"
  }

  # A narrow pinned tile loses its pin mark, so the inspector's "Pinned" line is the only cue left. Selecting it scrolls the inspector
  # so that line is in its visible area. At 1440 the mark stays: that is the control.
  $pinnedLine = { SlGet '(() => { const t = els.get(1001), ins = document.querySelector(".insp"), m = [...document.querySelectorAll("#win .m")].find(e => e.textContent.trim().startsWith("Pinned")), pmk = t.querySelector(".pinmark"); const q = ins.getBoundingClientRect(), r = m ? m.getBoundingClientRect() : null; return { narrow: t.classList.contains("narrow"), pin: t.classList.contains("pin"), sel: t.classList.contains("sel"), pinmark: pmk ? getComputedStyle(pmk).display : "absent", line: !!m, lineTop: r ? r.top : null, lineBottom: r ? r.bottom : null, insTop: q.top, insBottom: q.bottom }; })()' }
  SlViewport 1440 900; SlCase (SlSceneJson $pinsCQ '["*"]')
  SlClick (SlAt (SlBox 1001) 0.5 0.5)
  $n3c = & $pinnedLine
  if (Shard-Take) {
  Check 'control, 1440: the selected pinned tile keeps its pin mark' ([bool]($n3c.pin -and $n3c.sel -and $n3c.pinmark -eq 'block')) "pin: $($n3c.pin), selected: $($n3c.sel), pin mark: $($n3c.pinmark)"
  }
  SlViewport 1024 768; SlCase (SlSceneJson $pinsCQ '["*"]')
  SlClick (SlAt (SlBox 1001) 0.5 0.5)
  $n3 = & $pinnedLine
  if (Shard-Take) {
  Check 'narrow pinned tile, 1024, scope: the selected pinned tile is narrow and its pin mark is hidden' ([bool]($n3.narrow -and $n3.pin -and $n3.sel -and $n3.pinmark -eq 'none')) "narrow: $($n3.narrow), pin: $($n3.pin), selected: $($n3.sel), pin mark: $($n3.pinmark)"
  Check 'narrow pinned tile, 1024: the inspector''s Pinned line is in the inspector''s visible area' ([bool]($n3.line -and $n3.lineTop -ge $n3.insTop -and $n3.lineBottom -le $n3.insBottom)) "line $($n3.lineTop) to $($n3.lineBottom); inspector $($n3.insTop) to $($n3.insBottom)"
  }

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
  if (Shard-Take) {
  Check 'control, no preview in flight: the switch writes fill.off to the scene it was pressed on, and the other scene is unchanged' ([bool]($ctlOff -eq $true -and $ctlSecond -eq $true)) "fill.off on the first: $ctlOff; second unchanged: $ctlSecond"
  }
  [void](SlSwitch -Click); SlSettle
  SlJs 'window.__bSecond = JSON.stringify(work["sl2"]); true'
  # The wait: the switch is pressed while the first scene's preview is held, then the second scene is clicked, then the answer comes back.
  SlJs 'window.__hold = true; preview("sl"); true'
  [void](SlSwitch -Click)
  $scopeA = SlGet '({ inflight: !!inflight["sl"], sel: selId })'
  if (Shard-Take) {
  Check 'scene tab click during the wait, scope: the switch on Scene A waits for A''s preview, and Scene A is the selected scene' ([bool]($scopeA.inflight -and $scopeA.sel -eq 'sl')) "in flight: $($scopeA.inflight), selected: $($scopeA.sel)"
  }
  SlJs 'document.querySelector("[data-pick=sl2]").click(); true'
  SlJs 'window.__hold = false; window.__release(); true'
  SlJs 'newestPrev("sl").then(() => true)'
  SlSettle
  $secondNow = SlJs 'JSON.stringify(work["sl2"]) === window.__bSecond'
  $firstNow = SlGet 'work["sl"].fill.off'
  if (Shard-Take) {
  Check 'scene tab click during the wait: the scene clicked second is unchanged' ([bool]($secondNow -eq $true)) "second scene unchanged: $secondNow; its fill.off: $(SlGet 'work["sl2"].fill.off')"
  Check 'scene tab click during the wait: the switch lands on the scene it was pressed on' ([bool]($firstNow -eq $true)) "first scene fill.off: $(if ($null -eq $firstNow) { 'none' } else { $firstNow })"
  }

  # Held title changed (decisions/fill-controls.md): notepad has one window, so its held title does not decide the match, as with a pin.
  # The page places it in its held cell; a save keeps the entry, and a dry run from the saved scene places it in the same cell.
  SlViewport 1440 900; SlCase (SlSceneJson '[]' '["*"]' '' (SlHeldFill '[{"app":"notepad","title":"Old todo title - Notepad","mon":"wide","slots":[0]}]'))
  $tcHeld = SlList 'work[selId].fill.held'
  if (Shard-Take) {
  Check 'held title changed, scope: the scene holds the notepad window under its old title' ($tcHeld.Count -eq 1 -and "$($tcHeld[0].app)" -eq 'notepad') "fill.held: $(SlShort $tcHeld)"
  }
  $tcPage = SlPlacedOf 1014
  if (Shard-Take) {
  Check 'held title changed: the page places the window in its held cell' ([bool]($tcPage -and @($tcPage.slots) -contains 1)) "page cells of 1014: $(if ($tcPage) { (@($tcPage.slots) | Sort-Object) -join '+' } else { 'none' })"
  }
  [void](SlJs 'saveScene().then(() => true)'); SlSettle
  $tcSaved = SlSavedScene
  $tcSavedHeld = @($tcSaved.fill.held | ? { $_ })
  if (Shard-Take) {
  Check 'held title changed: a save keeps the held window' ($tcSavedHeld.Count -eq 1 -and "$($tcSavedHeld[0].app)" -eq 'notepad') "saved fill.held entries: $($tcSavedHeld.Count)"
  }
  $tcDry = SlDry (ConvertTo-Json -Depth 12 -Compress $tcSaved)
  if (Shard-Take) {
  Check 'held title changed: a dry run from the saved scene places the window in its held cell' ((SlSlotsOf $tcDry 1014) -eq '1') "saved held entries: $($tcSavedHeld.Count); 1014 cells: $(SlSlotsOf $tcDry 1014)"
  }

  # A grid change keeps a held window on its column and row, as it keeps a pin (setGrid remaps the held layout as it remaps the pins).
  SlViewport 1440 900; SlCase (SlSceneJson '[]' '["*"]' '' (SlHeldFill '[{"app":"claude","title":"Draft release notes","mon":"wide","slots":[5]},{"app":"notepad","title":"todo.txt - Notepad","mon":"wide","slots":[1]}]'))
  $gScope = SlPlacedOf 1003
  if (Shard-Take) {
  Check 'grid, scope: the held window 1003 is placed in its held cell, column 1 of row 2' ([bool]($gScope -and @($gScope.slots) -contains 6)) "placed: $(SlShort $gScope)"
  }
  SlJs "(() => { curMon = snap.monitors.find(m => m.role === 'wide'); setGrid('c', 1); return true; })()"; SlSettle
  $gHeld = SlList 'work[selId].fill.held'
  $gClaude = @($gHeld | ? { "$($_.app)" -eq 'claude' })[0]
  $gNotepad = @($gHeld | ? { "$($_.app)" -eq 'notepad' })[0]
  if (Shard-Take) {
  Check 'grid: a column added to the right keeps the held window of row 2, column 1 in that column and row' ([bool]($gClaude -and (SlCells $gClaude) -eq '6')) "claude held slots: $(if ($gClaude) { SlCells $gClaude } else { 'none' }); fill.held: $(SlShort $gHeld)"
  Check 'grid, control: the held window in row 1, column 2 stays in its cell' ([bool]($gNotepad -and (SlCells $gNotepad) -eq '1')) "notepad held slots: $(if ($gNotepad) { SlCells $gNotepad } else { 'none' })"
  }

  # Two windows with one title (1006 and 1017, a copy of the fixture with 1017 added). Pinning 1017 drops its own hold, and only its own:
  # the hold of 1006, the other window with that title, stays in its cell. The copy is served by a second dry-run server.
  $fxDup = Join-Path $run 'fixture-dup.json'
  $fxDupDoc = Get-Content -Raw -Encoding UTF8 -LiteralPath $fixture | ConvertFrom-Json
  $fxDupDoc.windows = @($fxDupDoc.windows) + [pscustomobject]@{ id = 1017; app = 'chrome'; title = 'Quarterly roadmap - Example'; x = 300; y = 200; w = 1400; h = 1000 }
  [IO.File]::WriteAllText($fxDup, (ConvertTo-Json -Depth 10 -Compress $fxDupDoc), $utf8)
  # The duplicate-title server writes its config into this folder. Make it first, so its first save does not depend on the server.
  New-Item -ItemType Directory -Force (Join-Path $run 'home-dup') | Out-Null
  $dupPair = SlStartServer $fxDup (Join-Path $run 'home-dup'); $srvDup = $dupPair[0]; $urlMain = $script:url; $script:url = $dupPair[1]
  SlCase (SlSceneJson '[]' '["*"]' '' (SlHeldFill '[{"id":1006,"app":"chrome","title":"Quarterly roadmap - Example","mon":"wide","slots":[2]},{"id":1017,"app":"chrome","title":"Quarterly roadmap - Example","mon":"wide","slots":[3]}]'))
  $dScope = SlList 'work[selId].fill.held'
  if (Shard-Take) {
  Check 'same title, scope: both windows with the title are held, one entry each' (@($dScope | ? { "$($_.app)" -eq 'chrome' }).Count -eq 2) "fill.held: $(SlShort $dScope)"
  }
  SlJs "(() => { pinWin(1017, snap.monitors.find(m => m.role === 'wide'), 8); return true; })()"; SlSettle
  $dAfter = SlList 'work[selId].fill.held'
  $dIds = @($dAfter | % { [int]$_.id }) -join ','; if (-not $dIds) { $dIds = 'none' }
  if (Shard-Take) {
  Check 'same title: pinning 1017 drops its own hold' (-not @($dAfter | ? { [int]$_.id -eq 1017 }).Count) "held ids after the pin: $dIds"
  Check 'same title: pinning 1017 keeps the hold of 1006, the other window with that title' (@($dAfter | ? { [int]$_.id -eq 1006 }).Count -eq 1) "held ids after the pin: $dIds"
  }
  [void](Invoke-WebRequest -UseBasicParsing "$($script:url)quit" -Method Post -Body 'quit'); [void]$srvDup.WaitForExit(5000)
  $script:url = $urlMain
  SlViewport 1440 900

  # ---------- Ruling 2026-11-16 (decisions/stack-and-lock.md, stack tweaks): circle, padlock, locked drag, covered windows, Merge ----------
  # Each claim is red on the head where it is new; a control or guard is green on the head beside it, and says so in its name.
  # Scenes. Refactor (claude, 1001) and Quarterly (chrome, 1006) are the pair; Pull request (chrome, 1005) is the locked window.
  $pinsCircleSpan = SlPins '{"app":"chrome","match":"Quarterly","mon":"wide","slots":[0,1]}' '{"app":"claude","match":"Refactor","mon":"wide","slots":[3]}'
  $pinsTwoCovered = SlPins '{"app":"claude","match":"Refactor","mon":"wide","slots":[0,5]}' '{"app":"chrome","match":"Quarterly","mon":"wide","slots":[1]}' '{"app":"claude","match":"Pin parser","mon":"wide","slots":[6]}' '{"app":"chrome","match":"Pull request","mon":"wide","slots":[2],"lock":true}'

  # 1. Swap circle (item 1). A drop on a taken block swaps inside the circle (half its short side, 28 to 64 px, centred on the
  #    block) and puts behind anywhere else on the block. Probes sit well clear of the circle's edge.
  SlViewport 1440 900; SlCase (SlSceneJson $pinsCQ)
  $c1 = SlCircleDrop 1006 0 1 1 0 0
  if (Shard-Take) {
  Check 'circle, 1x1 at 1440: the Swap circle is drawn at the cell''s centre, half its short side' (SlCircleFits $c1.circle $c1.block) "circle: $(SlShort $c1.circle); cell: $(SlShort $c1.block)"
  Check 'circle, 1x1 at 1440, scope: the drop label is drawn over the taken cell while the pointer is held' ($c1.shown -eq $true) "label shown: $($c1.shown)"
  }
  $o1 = SlZoneOutcome 'Quarterly' 'Refactor'
  if (Shard-Take) {
  Check 'circle, 1x1 at 1440: a drop at the circle''s centre swaps (control)' ($o1 -eq 'swap:0/1') "outcome: $o1"
  }

  SlViewport 1440 900; SlCase (SlSceneJson $pinsCQ)
  $c2 = SlCircleDrop 1006 0 1 1 0 (-0.35)
  $o2 = SlZoneOutcome 'Quarterly' 'Refactor'
  if (Shard-Take) {
  Check 'circle, 1x1 at 1440: a drop above the circle, still on the cell, puts behind' ($o2 -eq 'behind') "outcome: $o2"
  }

  SlViewport 1440 900; SlCase (SlSceneJson $pinsCQ)
  $c3 = SlCircleDrop 1006 0 1 1 (-0.22) (-0.22)
  $o3 = SlZoneOutcome 'Quarterly' 'Refactor'
  if (Shard-Take) {
  Check 'circle, 1x1 at 1440: a drop in the bounding square''s corner, outside the circle, puts behind (the hit test is the distance)' ($o3 -eq 'behind') "outcome: $o3"
  }

  SlViewport 1440 900; SlCase (SlSceneJson $pinsCQ)
  $c4 = SlCircleDrop 1006 0 1 1 0 0.35
  $o4 = SlZoneOutcome 'Quarterly' 'Refactor'
  if (Shard-Take) {
  Check 'circle, 1x1 at 1440: a drop on the lower part of the cell puts behind (control)' ($o4 -eq 'behind') "outcome: $o4"
  }

  SlViewport 1440 900; SlCase (SlSceneJson $pinsCircleSpan)
  $cs1 = SlCircleDrop 1001 0 2 1 0 0
  if (Shard-Take) {
  Check 'circle, 2x1 span at 1440: the Swap circle is centred on the whole span, not on one cell' (SlCircleFits $cs1.circle $cs1.block) "circle: $(SlShort $cs1.circle); span: $(SlShort $cs1.block)"
  }
  $os1 = SlZoneOutcome 'Refactor' 'Quarterly'
  if (Shard-Take) {
  Check 'circle, 2x1 span at 1440: a drop at the circle''s centre swaps, and the span keeps its place (control)' ($os1 -eq 'swap:0,1/3') "outcome: $os1"
  }

  SlViewport 1440 900; SlCase (SlSceneJson $pinsCircleSpan)
  $cs2 = SlCircleDrop 1001 0 2 1 (-0.25) 0
  $os2 = SlZoneOutcome 'Refactor' 'Quarterly'
  if (Shard-Take) {
  Check 'circle, 2x1 span at 1440: a drop left of the circle, inside the span, puts behind' ($os2 -eq 'behind') "outcome: $os2"
  }

  SlViewport 1440 900; SlCase (SlSceneJson $pinsCircleSpan)
  $cs3 = SlCircleDrop 1001 0 2 1 0 (-0.35)
  $os3 = SlZoneOutcome 'Refactor' 'Quarterly'
  if (Shard-Take) {
  Check 'circle, 2x1 span at 1440: a drop above the circle, inside the span, puts behind' ($os3 -eq 'behind') "outcome: $os3"
  }

  SlViewport 1024 768; SlCase (SlSceneJson $pinsCQ)
  $c5 = SlCircleDrop 1006 0 1 1 0 0
  if (Shard-Take) {
  Check 'circle, 1x1 at 1024: the Swap circle is drawn at the cell''s centre, 28 px at least (the 28 px floor)' (SlCircleFits $c5.circle $c5.block) "circle: $(SlShort $c5.circle); cell: $(SlShort $c5.block)"
  }
  $o5 = SlZoneOutcome 'Quarterly' 'Refactor'
  if (Shard-Take) {
  Check 'circle, 1x1 at 1024: a drop at the circle''s centre swaps (control)' ($o5 -eq 'swap:0/1') "outcome: $o5"
  }

  SlViewport 1024 768; SlCase (SlSceneJson $pinsCQ)
  $c6 = SlCircleDrop 1006 0 1 1 0 (-0.35)
  $o6 = SlZoneOutcome 'Quarterly' 'Refactor'
  if (Shard-Take) {
  Check 'circle, 1x1 at 1024: a drop above the circle, still on the cell, puts behind' ($o6 -eq 'behind') "outcome: $o6"
  }

  # 2. Padlock (item 2). Hidden at rest on an unlocked tile; shown on hover, focus and selection; always shown on a locked tile.
  #    A hidden padlock takes no click: the page hits the tile, not the padlock, at its centre.
  SlViewport 1440 900; SlCase (SlSceneJson $pinsCQ); SlPark
  $pkScope = SlGet "({ hov: els.get(1001).matches(':hover'), sel: els.get(1001).classList.contains('sel'), foc: els.get(1001).matches(':focus-within') })"
  if (Shard-Take) {
  Check 'padlock, scope: at rest Refactor is not hovered, selected or focused' ([bool]($pkScope -and -not $pkScope.hov -and -not $pkScope.sel -and -not $pkScope.foc)) "scope: $(SlShort $pkScope)"
  }
  $pkRest = SlLkShown 1001
  if (Shard-Take) {
  Check 'padlock: an unlocked tile at rest hides its padlock' ($pkRest -eq $false) "padlock shown at rest: $pkRest"
  }
  $pkHit = SlLkHit 1001
  if (Shard-Take) {
  Check 'padlock: a hidden padlock takes no hit, so the page does not hit it at its centre' ($pkHit -eq $false) "padlock is hit at its centre: $pkHit"
  }

  SlViewport 1440 900; SlCase (SlSceneJson $pinsCQ); SlPark
  $pkC = SlLkCentre 1001
  if ($pkC) { SlClick @([double]$pkC[0], [double]$pkC[1]) }
  $pkPin = SlPin (SlGet 'work[selId]') 'Refactor'
  if (Shard-Take) {
  Check 'padlock: a press where a hidden padlock sits does not lock the tile' ([bool]($pkPin -and $pkPin.lock -ne $true)) "pin after the press: $(SlShort $pkPin)"
  }

  SlViewport 1440 900; SlCase (SlSceneJson $pinsCQ); SlPark
  SlMouse 'mouseMoved' ([double](SlAt (SlBox 1001) 0.5 0.5)[0]) ([double](SlAt (SlBox 1001) 0.5 0.5)[1]) 0; SlFrame
  $pkHov = SlLkShown 1001
  if (Shard-Take) {
  Check 'padlock, control: hovering an unlocked tile shows its padlock' ($pkHov -eq $true) "shown on hover: $pkHov"
  }

  SlViewport 1440 900; SlCase (SlSceneJson $pinsCQ); SlPark
  [void](SlJs "(() => { els.get(1001).focus({ preventScroll: true }); return true; })()"); SlFrame
  $pkFoc = SlLkShown 1001
  if (Shard-Take) {
  Check 'padlock, control: keyboard focus inside an unlocked tile shows its padlock' ($pkFoc -eq $true) "shown on focus: $pkFoc"
  }

  SlViewport 1440 900; SlCase (SlSceneJson $pinsCQ)
  SlClick (SlAt (SlBox 1001) 0.5 0.5); SlPark
  $pkSelScope = SlGet "els.get(1001).classList.contains('sel')"
  $pkSel = SlLkShown 1001
  if (Shard-Take) {
  Check 'padlock, control: a selected unlocked tile, away from the pointer, shows its padlock' ([bool]$pkSelScope -and $pkSel -eq $true) "selected: $pkSelScope; shown: $pkSel"
  }

  SlViewport 1440 900; SlCase (SlSceneJson $pinsCQLock); SlPark
  $pkLk = SlLkShown 1001
  if (Shard-Take) {
  Check 'padlock, control: a locked tile at rest always shows its padlock' ($pkLk -eq $true) "shown at rest: $pkLk"
  }

  SlViewport 1440 900; SlCase (SlSceneJson $pinsFull); SlPark
  $pkTiles = SlBoardTiles
  if (Shard-Take) {
  Check 'padlock, full board, scope: ten windows are on the board' ($pkTiles -eq 10) "tiles: $pkTiles"
  }
  $pkCount = SlShownLocks
  if (Shard-Take) {
  Check 'padlock, full board: no unlocked tile shows a padlock at rest' ($pkCount -eq 0) "padlocks shown at rest: $pkCount"
  }

  # 3. A locked tile moves after an in-page confirm (item 3). Releasing it opens the confirm; nothing moves before "Move It".
  #    Cancel leaves it where it was, still locked. Move It moves it to the cell it was released on, and it stays locked.
  SlViewport 1440 900; SlCase (SlSceneJson $pinsCQLock)
  SlDrag (SlAt (SlBox 1001) 0.5 0.5) (SlSlotAt 3)
  $ldOpen = SlJs "!!document.querySelector('[role=alertdialog]')"
  if (Shard-Take) {
  Check 'locked drag: releasing a locked tile on an empty cell opens an in-page confirm (role alertdialog)' ([bool]$ldOpen) "status: $(SlJs "document.getElementById('msg').textContent")"
  }
  $ldPin = SlPin (SlGet 'work[selId]') 'Refactor'
  if (Shard-Take) {
  Check 'locked drag, guard: releasing a locked tile does not move it, and it stays locked, before the confirm is answered' ([bool]($ldPin -and (SlCells $ldPin) -eq '0' -and $ldPin.lock -eq $true)) "pin: $(SlShort $ldPin)"
  }

  SlViewport 1440 900; SlCase (SlSceneJson $pinsCQLock)
  SlDrag (SlAt (SlBox 1001) 0.5 0.5) (SlSlotAt 3)
  $ldCancel = SlBtnPress '[role=alertdialog]' 'Cancel'
  $ldGone = SlJs "!document.querySelector('[role=alertdialog]')"
  $ldCP = SlPin (SlGet 'work[selId]') 'Refactor'
  if (Shard-Take) {
  Check 'locked drag, Cancel: the confirm closes, and the tile stays in its cell, still locked' ([bool]($ldCancel -and $ldGone -and $ldCP -and (SlCells $ldCP) -eq '0' -and $ldCP.lock -eq $true)) "Cancel pressed: $ldCancel; confirm closed: $ldGone; pin: $(SlShort $ldCP)"
  }

  SlViewport 1440 900; SlCase (SlSceneJson $pinsCQLock)
  SlDrag (SlAt (SlBox 1001) 0.5 0.5) (SlSlotAt 3)
  $mvPress = SlBtnPress '[role=alertdialog]' 'Move It'
  $mvPin = SlPin (SlGet 'work[selId]') 'Refactor'
  if (Shard-Take) {
  Check 'locked drag, Move It: the locked tile moves to the cell it was released on, and stays locked' ([bool]($mvPress -and $mvPin -and (SlCells $mvPin) -eq '3' -and $mvPin.lock -eq $true)) "Move It pressed: $mvPress; pin: $(SlShort $mvPin)"
  }

  SlViewport 1440 900; SlCase (SlSceneJson $pinsCQLock '["*"]')
  SlDrag (SlAt (SlBox 1001) 0.5 0.5) (SlSlotAt 9)
  [void](SlBtnPress '[role=alertdialog]' 'Move It')
  $fzPin = SlPin (SlGet 'work[selId]') 'Refactor'
  $fzFill = SlList "prevs[selId].placed.filter(p => p.pin < 0 && !p.behind).map(p => p.id)"
  $fzOn = SlList "prevs[selId].placed.filter(p => p.pin < 0 && p.slots.includes(10)).map(p => p.id)"
  if (Shard-Take) {
  Check 'locked drag, Move It with a fill: the fill places windows, and none takes the locked tile''s new cell' ([bool]($fzPin -and (SlCells $fzPin) -eq '9' -and @($fzFill).Count -ge 1 -and @($fzOn).Count -eq 0)) "pin: $(SlShort $fzPin); fill-placed: $(SlShort $fzFill); on cell 9: $(SlShort $fzOn)"
  }

  SlViewport 1440 900; SlCase (SlSceneJson $pinsCQ)
  SlDrag (SlAt (SlBox 1001) 0.5 0.5) (SlSlotAt 3)
  $ctlDlg = SlJs "!!document.querySelector('[role=alertdialog]')"
  $ctlPin = SlPin (SlGet 'work[selId]') 'Refactor'
  if (Shard-Take) {
  Check 'locked drag, control: an unlocked tile dragged to an empty cell moves, with no confirm' ([bool]($ctlPin -and (SlCells $ctlPin) -eq '3' -and -not $ctlDlg)) "pin: $(SlShort $ctlPin); confirm open: $ctlDlg"
  }

  # 4. A resize that covers two windows sends both to Windows That Stay Put, reason "Covered by a resize", with a Drop Note
  #    and Undo. It still stops at a locked tile: Pull request, in column 2, is not covered and keeps its cell and lock.
  SlViewport 1440 900; SlCase (SlSceneJson $pinsTwoCovered)
  SlClick (SlAt (SlBox 1001) 0.5 0.5)
  if (Shard-Take) {
  Check 'covered, scope: the east handle is drawn on Refactor''s 1x2 tile' ([bool](SlHandle 'ea')) 'no ea handle'
  }
  [void](SlJs "(window.bfPre = $SceneNorm, true)")
  [void](SlHandleDropNoSettle 'ea' 1 0 3)
  $cvNote = SlNoteText
  $cv = SlGet 'work[selId]'; $cvR = SlPin $cv 'Refactor'; $cvL = SlPin $cv 'Pull request'
  if (Shard-Take) {
  Check 'covered, control: the span stops at the locked tile, so Refactor takes cells 0, 1, 5 and 6' ([bool]($cvR -and (SlCells $cvR) -eq '0,1,5,6')) "claude pin: $(SlShort $cvR)"
  Check 'covered, guard: the locked tile keeps its cell and its lock' ([bool]($cvL -and $cvL.lock -eq $true -and (SlCells $cvL) -eq '2')) "locked pin: $(SlShort $cvL)"
  }
  $cvBay = SlBayIds
  if (Shard-Take) {
  Check 'covered: Quarterly, which the span covers, goes to Windows That Stay Put' ($cvBay -contains 1006) "bay ids: $($cvBay -join ',')"
  Check 'covered: Pin parser, which the span covers, goes to Windows That Stay Put' ($cvBay -contains 1002) "bay ids: $($cvBay -join ',')"
  }
  $cvPlaced = SlList "prevs[selId].placed.map(p => p.id)"
  if (Shard-Take) {
  Check 'covered: neither covered window is placed on a free cell' ((@($cvPlaced) -notcontains 1006) -and (@($cvPlaced) -notcontains 1002)) "placed ids: $(@($cvPlaced) -join ',')"
  }
  $cvChips = SlBayChips
  $cvQ = @($cvChips | ? { $_.id -eq 1006 })[0]; $cvP = @($cvChips | ? { $_.id -eq 1002 })[0]
  if (Shard-Take) {
  Check 'covered: both chips read "Covered by a resize"' ([bool]($cvQ -and $cvP -and "$($cvQ.label)" -like '*Covered by a resize*' -and "$($cvP.label)" -like '*Covered by a resize*')) "chips: $(SlShort $cvChips)"
  Check 'covered: a Drop Note says the windows went to Windows That Stay Put' ("$cvNote" -like '*went to Windows That Stay Put*') "note: $cvNote"
  Check 'covered: the Drop Note names both covered windows (Chrome and Claude)' ("$cvNote" -like '*Chrome*' -and "$cvNote" -like '*Claude*') "note: $cvNote"
  }
  SlSettle
  $cvUndo = SlBtnPress '.dnote' 'Undo'
  SlSettle
  $cvBack = SlJs "($SceneNorm) === window.bfPre"
  if (Shard-Take) {
  Check 'covered: a real press on the Drop Note''s Undo restores the scene from before the resize' ([bool]($cvUndo -and $cvBack)) "Undo pressed: $cvUndo; scene restored: $cvBack"
  }

  # The same covering on a full board (P8): no cell is free, so the reason must still be the covering, not "No room".
  SlViewport 1440 900; SlCase (SlSceneJson $pinsFull)
  SlClick (SlAt (SlBox 1001) 0.5 0.5)
  [void](SlHandleDrag 'ea' 1 0)
  $fbBay = SlBayIds
  if (Shard-Take) {
  Check 'covered, full board, scope: Pin parser, which the east handle covers, is in Windows That Stay Put' ($fbBay -contains 1002) "bay ids: $($fbBay -join ',')"
  }
  $fbChips = SlBayChips
  $fbP = @($fbChips | ? { $_.id -eq 1002 })[0]
  if (Shard-Take) {
  Check 'covered, full board: the Pin parser chip reads "Covered by a resize", not "No room"' ([bool]($fbP -and "$($fbP.label)" -like '*Covered by a resize*')) "chip: $(SlShort $fbP)"
  }

  # 5. Ctrl+click picks cells, then Merge (item 5). The bar is .mbar, with Merge, Cancel and Fill to Rectangle.
  SlViewport 1440 900; SlCase (SlSceneJson $pinsCQ)
  SlCtrlClick (SlAt (SlBox 1006) 0.5 0.5)
  SlCtrlClick (SlSlotAt 2)
  $m1State = SlBtnState '.mbar' 'Merge'
  if (Shard-Take) {
  Check 'merge, a window and an empty cell: Ctrl+click draws the Merge bar, with Merge enabled' ($m1State -eq 'enabled') "Merge: $m1State"
  }
  $m1Press = SlBtnPress '.mbar' 'Merge'
  $m1Pin = SlPin (SlGet 'work[selId]') 'Quarterly'
  if (Shard-Take) {
  Check 'merge, a window and an empty cell: Merge makes the window and the empty cell one 2x1 span' ([bool]($m1Press -and $m1Pin -and (SlCells $m1Pin) -eq '1,2')) "Merge pressed: $m1Press; pin: $(SlShort $m1Pin)"
  }

  SlViewport 1440 900; SlCase (SlSceneJson $pinsCQ)
  SlCtrlClick (SlAt (SlBox 1006) 0.5 0.5)
  SlCtrlClick (SlAt (SlBox 1001) 0.5 0.5)
  $m2State = SlBtnState '.mbar' 'Merge'
  if (Shard-Take) {
  Check 'merge, two windows: the bar shows Merge enabled for a rectangle of two picks' ($m2State -eq 'enabled') "Merge: $m2State"
  }
  $m2Press = SlBtnPress '.mbar' 'Merge'
  $m2s = SlGet 'work[selId]'; $m2Q = SlPin $m2s 'Quarterly'
  if (Shard-Take) {
  Check 'merge, two windows: the first window picked (Quarterly) keeps the span, on cells 0 and 1' ([bool]($m2Press -and $m2Q -and (SlCells $m2Q) -eq '0,1')) "Merge pressed: $m2Press; pin: $(SlShort $m2Q)"
  Check 'merge, two windows: the other picked window (Refactor) goes to Windows That Stay Put' ([bool]($m2Press -and (SlHasBay $m2s 'Refactor'))) "Merge pressed: $m2Press; bay: $(SlShort $m2s.bay)"
  }
  # Ruling 2026-11-16: a window a Merge sends to the list reads "Moved by a merge", not the resize's "Covered by a resize".
  $m2Chips = SlBayChips; $m2Chip = @($m2Chips | ? { $_.id -eq 1001 })[0]
  if (Shard-Take) {
  Check 'merge, two windows: the window Merge sends to Windows That Stay Put reads "Moved by a merge", not "Covered by a resize"' ([bool]($m2Press -and $m2Chip -and "$($m2Chip.label)" -like '*Moved by a merge*' -and "$($m2Chip.label)" -notlike '*Covered by a resize*')) "chip: $(SlShort $m2Chip)"
  }

  SlViewport 1440 900; SlCase (SlSceneJson $pinsCQ)
  SlCtrlClick (SlAt (SlBox 1001) 0.5 0.5)
  SlCtrlClick (SlSlotAt 2)
  $m3State = SlBtnState '.mbar' 'Merge'
  if (Shard-Take) {
  Check 'merge, not a rectangle: Merge is disabled' ($m3State -eq 'disabled') "Merge: $m3State"
  }
  $m3Bar = SlJs "(() => { const b = document.querySelector('.mbar'); return b ? b.textContent.replace(/\s+/g, ' ').trim() : null; })()"
  if (Shard-Take) {
  Check 'merge, not a rectangle: the bar says the picks are not a rectangle' ("$m3Bar" -match '(?i)rectangle') "bar: $m3Bar"
  }
  $m3Fill = SlBtnState '.mbar' 'Fill to Rectangle'
  if (Shard-Take) {
  Check 'merge, not a rectangle: Fill to Rectangle is offered' ($m3Fill -eq 'enabled') "Fill to Rectangle: $m3Fill"
  }
  [void](SlBtnPress '.mbar' 'Fill to Rectangle')
  $m3After = SlBtnState '.mbar' 'Merge'
  if (Shard-Take) {
  Check 'merge, not a rectangle: Fill to Rectangle adds the missing cell, and Merge is enabled' ($m3After -eq 'enabled') "Merge after Fill to Rectangle: $m3After"
  }

  SlViewport 1440 900; SlCase (SlSceneJson $pinsCQ)
  SlCtrlClick (SlSlotAt 3)
  SlCtrlClick (SlSlotAt 4)
  $m4State = SlBtnState '.mbar' 'Merge'
  if (Shard-Take) {
  Check 'merge, empty cells only: Merge is disabled' ($m4State -eq 'disabled') "Merge: $m4State"
  }
  $m4Bar = SlJs "(() => { const b = document.querySelector('.mbar'); return b ? b.textContent.replace(/\s+/g, ' ').trim() : null; })()"
  if (Shard-Take) {
  Check 'merge, empty cells only: the bar says a span belongs to a window' ("$m4Bar" -match '(?i)belongs to a window') "bar: $m4Bar"
  }
  $m4Before = SlJs "JSON.stringify([work[selId].pins, work[selId].zones || []])"
  $m4Press = SlBtnPress '.mbar' 'Merge'
  $m4After = SlJs "JSON.stringify([work[selId].pins, work[selId].zones || []])"
  if (Shard-Take) {
  Check 'merge, empty cells only, guard: a press on Merge makes no span and no pin' ((-not $m4Press) -and $m4Before -eq $m4After) "Merge pressed: $m4Press; scene changed: $($m4Before -ne $m4After)"
  }
  # ---------- Review findings on 1ff9835 (ruling 2026-11-16: lock correction 10:20, coordinator picks 10:53). Each claim is red on
  # the head it names; a control or guard beside it is green there and says so in its name. ----------
  $pinsLockedFront = SlPins '{"app":"claude","match":"Refactor","mon":"wide","slots":[0],"lock":true,"behind":[{"app":"claude","match":"Pin parser"}]}' '{"app":"chrome","match":"Quarterly","mon":"wide","slots":[1]}'
  $pinsLockedRef = SlPins '{"app":"claude","match":"Refactor","mon":"wide","slots":[0],"lock":true}'
  $pinsClosedLock = SlPins '{"app":"chrome","match":"Quarterly","mon":"wide","slots":[0]}' '{"app":"closedapp","match":"","mon":"wide","slots":[1],"lock":true}'
  $pinsClosedFree = SlPins '{"app":"claude","match":"Refactor","mon":"wide","slots":[0]}' '{"app":"closedapp","match":"","mon":"wide","slots":[1]}'
  $pinsClosedMerge = SlPins '{"app":"chrome","match":"Quarterly","mon":"wide","slots":[0]}' '{"app":"closedapp","match":"","mon":"wide","slots":[1]}'
  $pinsTwoClaude = SlPins '{"app":"claude","match":"Refactor","mon":"wide","slots":[0]}' '{"app":"claude","match":"Pin parser","mon":"wide","slots":[1]}'
  $pinsTwoClaudeLock = SlPins '{"app":"claude","match":"Refactor","mon":"wide","slots":[0],"lock":true}' '{"app":"claude","match":"Pin parser","mon":"wide","slots":[1]}'

  # F1. A locked front dragged to Windows That Stay Put loses its lock (ruling: "dragged to Windows That Stay Put, loses its lock").
  #     The window behind it becomes the front, and takes Refactor's pin: that pin must not be locked.
  SlViewport 1440 900; SlCase (SlSceneJson $pinsLockedFront); SlPark
  $lfPre = SlPin (SlGet 'work[selId]') 'Refactor'
  if (Shard-Take) {
  Check 'locked front, scope: Refactor is locked, with Pin parser stacked behind it' ([bool]($lfPre -and $lfPre.lock -eq $true -and (SlHasBehind $lfPre 'Pin parser'))) "pin: $(SlShort $lfPre)"
  }
  $lfBayPt = SlJs "(() => { const r = document.getElementById('bay').getBoundingClientRect(); return [r.left + r.width / 2, r.top + r.height / 2]; })()"
  SlDrag (SlAt (SlBox 1001) 0.5 0.5) $lfBayPt
  $lfAsk = SlJs "(() => { const d = document.querySelector('[role=alertdialog]'); return d ? d.textContent.replace(/\s+/g, ' ').trim() : null; })()"
  if (Shard-Take) {
  Check 'locked front, scope: dropping the locked tile on Windows That Stay Put opens its warning' ([bool]("$lfAsk" -like '*Windows That Stay Put*')) "warning: $lfAsk"
  }
  $lfMove = SlBtnPress '[role=alertdialog]' 'Move It'
  $lfScene = SlGet 'work[selId]'
  if (Shard-Take) {
  Check 'locked front, control: Refactor is in Windows That Stay Put once Move It is pressed' ([bool]($lfMove -and (SlHasBay $lfScene 'Refactor'))) "Move It pressed: $lfMove; bay: $(SlShort $lfScene.bay)"
  }
  $lfNext = SlPin $lfScene 'Pin parser'
  if (Shard-Take) {
  Check 'locked front, red: the window that takes the locked pin (Pin parser) is not locked' ([bool]($lfNext -and $lfNext.lock -ne $true)) "Pin parser pin: $(SlShort $lfNext)"
  }

  # F2. Merge over a closed locked pin is refused, as a resize stops at a lock. The pin and its lock survive.
  #     Control: a locked window in the pick disables Merge (already so on head).
  SlViewport 1440 900; SlCase (SlSceneJson $pinsLockedRef)
  SlCtrlClick (SlAt (SlBox 1001) 0.5 0.5)
  SlCtrlClick (SlSlotAt 1)
  $mcCtl = SlBtnState '.mbar' 'Merge'
  if (Shard-Take) {
  Check 'merge, locked window in the pick, control: Merge is disabled' ($mcCtl -eq 'disabled') "Merge: $mcCtl"
  }

  SlViewport 1440 900; SlCase (SlSceneJson $pinsClosedLock)
  SlCtrlClick (SlAt (SlBox 1006) 0.5 0.5)
  SlCtrlClick (SlSlotAt 1)
  $mcMiss = SlGet "(prevs[selId].missing || []).some(m => m.app === 'closedapp')"
  $mcPin0 = SlGet "work[selId].pins.find(p => p.app === 'closedapp' && p.lock === true) || null"
  if (Shard-Take) {
  Check 'merge, closed locked pin, scope: its window is not open, and the locked pin is in the scene on cell 1' ($mcMiss -eq $true -and [bool]$mcPin0 -and (SlCells $mcPin0) -eq '1') "missing: $mcMiss; pin: $(SlShort $mcPin0)"
  }
  $mcPress = SlBtnPress '.mbar' 'Merge'
  $mcScene = SlGet 'work[selId]'
  $mcPin = @($mcScene.pins | ? { $_.app -eq 'closedapp' })[0]
  $mcQ = SlPin $mcScene 'Quarterly'
  if (Shard-Take) {
  Check 'merge, closed locked pin, red: the pin keeps its lock and its cell after a Merge over it' ([bool]($mcPin -and $mcPin.lock -eq $true -and (SlCells $mcPin) -eq '1')) "Merge pressed: $mcPress; pin: $(SlShort $mcPin)"
  Check 'merge, closed locked pin, red: Merge is refused, so Quarterly keeps cell 0' ([bool]($mcQ -and (SlCells $mcQ) -eq '0')) "Merge pressed: $mcPress; Quarterly: $(SlShort $mcQ)"
  }

  # F3. A closed window's pin covered by a resize, then by a Merge: the pin is removed (guard), a Drop Note names the app (red),
  #     and Undo in the note restores the pin (red). A resize or Merge that covers no closed pin keeps its note as today.
  SlViewport 1440 900; SlCase (SlSceneJson $pinsClosedFree); SlClick (SlAt (SlBox 1001) 0.5 0.5)
  $crPin0 = SlGet "work[selId].pins.find(p => p.app === 'closedapp') || null"
  if (Shard-Take) {
  Check 'closed pin, resize, scope: Refactor is selected with its east handle drawn, and the closed window''s pin is in the scene' ([bool]((SlHandle 'ea') -and $crPin0)) "handle: $(SlShort (SlHandle 'ea')); pin: $(SlShort $crPin0)"
  }
  $crDrop = SlHandleDropNoSettle 'ea' 1 0
  $crNote = SlNoteText
  SlSettle
  $crScene = SlGet 'work[selId]'
  $crRef = SlPin $crScene 'Refactor'
  $crPin1 = @($crScene.pins | ? { $_.app -eq 'closedapp' })[0]
  if (Shard-Take) {
  Check 'closed pin, resize, guard: Refactor spans cells 0 and 1, and the closed window''s pin is removed' ([bool]($crDrop -and $crRef -and (SlCells $crRef) -eq '0,1' -and -not $crPin1)) "drop: $crDrop; Refactor: $(SlShort $crRef); pin left: $(SlShort $crPin1)"
  Check 'closed pin, resize, red: a Drop Note names the closed window''s app' ("$crNote" -like '*closedapp*') "note: $crNote"
  }
  $crUndo = SlBtnPress '.dnote' 'Undo'
  $crBack = SlGet "work[selId].pins.find(p => p.app === 'closedapp') || null"
  if (Shard-Take) {
  Check 'closed pin, resize, red: Undo in the Drop Note restores the closed window''s pin on cell 1' ([bool]($crUndo -and $crBack -and (SlCells $crBack) -eq '1')) $(if (-not $crNote) { 'no Drop Note, so no Undo to press' } else { "Undo pressed: $crUndo; pin: $(SlShort $crBack)" })
  }

  SlViewport 1440 900; SlCase (SlSceneJson $pinsClosedMerge)
  SlCtrlClick (SlAt (SlBox 1006) 0.5 0.5)
  SlCtrlClick (SlSlotAt 1)
  $cmState = SlBtnState '.mbar' 'Merge'
  $cmPin0 = SlGet "work[selId].pins.find(p => p.app === 'closedapp') || null"
  if (Shard-Take) {
  Check 'closed pin, Merge, scope: Merge is enabled over the closed window''s cell, and its pin is in the scene' ([bool]($cmState -eq 'enabled' -and $cmPin0)) "Merge: $cmState; pin: $(SlShort $cmPin0)"
  }
  # The press is raw, with no settle: the note fades about 6 s after it is drawn, and a settle can outlast that.
  $cmBtn = SlGet "(() => { const b = [...document.querySelectorAll('.mbar button')].find(x => x.textContent.trim() === 'Merge' && !x.disabled); if (!b) return null; const r = b.getBoundingClientRect(); return [r.left + r.width / 2, r.top + r.height / 2]; })()"
  if ($cmBtn) { SlMouse 'mousePressed' $cmBtn[0] $cmBtn[1] 1; SlMouse 'mouseReleased' $cmBtn[0] $cmBtn[1] 0 }
  $cmNote = SlNoteText
  SlSettle
  $cmScene = SlGet 'work[selId]'
  $cmQ = SlPin $cmScene 'Quarterly'
  $cmPin1 = @($cmScene.pins | ? { $_.app -eq 'closedapp' })[0]
  if (Shard-Take) {
  Check 'closed pin, Merge, guard: Quarterly spans cells 0 and 1, and the closed window''s pin is removed' ([bool]($cmBtn -and $cmQ -and (SlCells $cmQ) -eq '0,1' -and -not $cmPin1)) "Merge pressed: $([bool]$cmBtn); Quarterly: $(SlShort $cmQ); pin left: $(SlShort $cmPin1)"
  Check 'closed pin, Merge, red: a Drop Note names the closed window''s app' ("$cmNote" -like '*closedapp*') "note: $cmNote"
  }
  $cmUndo = SlBtnPress '.dnote' 'Undo'
  $cmBack = SlGet "work[selId].pins.find(p => p.app === 'closedapp') || null"
  if (Shard-Take) {
  Check 'closed pin, Merge, red: Undo in the Drop Note restores the closed window''s pin on cell 1' ([bool]($cmUndo -and $cmBack -and (SlCells $cmBack) -eq '1')) $(if (-not $cmNote) { 'no Drop Note, so no Undo to press' } else { "Undo pressed: $cmUndo; pin: $(SlShort $cmBack)" })
  }

  # F4. Two windows of one app (Refactor on cell 0, Pin parser on cell 1) are named apart in every surface. Each surface is its own
  #     check: the Drop Note, the status line, the locked-drag warning, and the Merge bar. "Chrome is behind Claude" (above) is the control.
  SlViewport 1440 900; SlCase (SlSceneJson $pinsTwoClaude)
  SlDropNoSettle (SlAt (SlBox 1002) 0.5 0.5) (SlAt (SlBox 1001) 0.5 0.85)
  $tnNote = SlNoteText
  SlSettle
  $tnPin = SlPin (SlGet 'work[selId]') 'Refactor'
  if (Shard-Take) {
  Check 'two Claude windows, scope: a Put Behind drop stacks Pin parser behind Refactor' ([bool](SlHasBehind $tnPin 'Pin parser')) "pin: $(SlShort $tnPin)"
  Check 'two Claude windows, red: the Drop Note names each window, by title or as "2 Claude windows"' (SlDistinct $tnNote) "note: $tnNote"
  }

  SlViewport 1440 900; SlCase (SlSceneJson $pinsTwoClaude)
  $tsCircle = SlCircleDrop 1002 0 1 1 0 0
  $tsOut = SlZoneOutcome 'Pin parser' 'Refactor'
  $tsMsg = SlJs "document.getElementById('msg').textContent"
  if (Shard-Take) {
  Check 'two Claude windows, scope: a drop inside the Swap circle swaps the two windows' ($tsOut -eq 'swap:0/1') "outcome: $tsOut; circle drawn: $(SlShort $tsCircle.circle)"
  Check 'two Claude windows, red: the status line names each window, by title or as "2 Claude windows"' (SlDistinct $tsMsg) "status: $tsMsg"
  }

  SlViewport 1440 900; SlCase (SlSceneJson $pinsTwoClaudeLock)
  SlDrag (SlAt (SlBox 1001) 0.5 0.5) (SlSlotAt 1)
  $tlDlg = SlJs "!!document.querySelector('[role=alertdialog]')"
  $tlWarn = SlJs "(() => { const p = document.getElementById('lcp'); return p ? p.textContent.replace(/\s+/g, ' ').trim() : null; })()"
  if (Shard-Take) {
  Check 'two Claude windows, locked drag, scope: dragging the locked Refactor onto Pin parser opens the swap warning' ([bool]($tlDlg -and "$tlWarn" -match '(?i)swap')) "warning: $tlWarn"
  Check 'two Claude windows, red: the warning names each window, by title or as "2 Claude windows", and never reads "Claude moves to Claude"' ((SlDistinct $tlWarn) -and "$tlWarn" -notlike '*Claude moves to Claude*') "warning: $tlWarn"
  }
  [void](SlBtnPress '[role=alertdialog]' 'Cancel')

  SlViewport 1440 900; SlCase (SlSceneJson $pinsTwoClaude)
  SlCtrlClick (SlAt (SlBox 1001) 0.5 0.5)
  SlCtrlClick (SlAt (SlBox 1002) 0.5 0.5)
  $tmState = SlBtnState '.mbar' 'Merge'
  $tmBar = SlJs "(() => { const b = document.querySelector('.mbar'); return b ? b.textContent.replace(/\s+/g, ' ').trim() : null; })()"
  if (Shard-Take) {
  Check 'two Claude windows, Merge bar, scope: Merge is enabled for the two picked windows' ($tmState -eq 'enabled') "Merge: $tmState; bar: $tmBar"
  Check 'two Claude windows, red: the Merge bar names each window, by title or as "2 Claude windows"' (SlDistinct $tmBar) "bar: $tmBar"
  }

  # F6. A 2x1 span at 1024: the Put Behind label's text box must not meet the Swap circle. Control: the same at 1440.
  SlViewport 1024 768; SlCase (SlSceneJson $pinsCircleSpan)
  $sl1 = SlCircleDrop 1001 0 2 1 0 (-0.35)
  # The scope takes a form with the word Behind, or the icon alone (the last fallback, clear of the circle; ruling 2026-11-16 12:45 CST).
  # The overlap and clip asserts stay.
  if (Shard-Take) {
  Check 'circle and label, 2x1 span at 1024, scope: the Swap circle is drawn, and the Put Behind label is drawn with Behind or as the icon alone' ([bool]($sl1.circle -and $sl1.shown -and $sl1.label -and ("$($sl1.label.text)" -match 'Behind' -or ("$($sl1.label.text)" -eq '' -and $sl1.clip -and $sl1.clip.icon)))) "circle: $(SlShort $sl1.circle); label: $(SlShort $sl1.label); icon: $($sl1.clip.icon)"
  Check 'circle and label, 2x1 span at 1024, red: the label''s text box does not meet the Swap circle' ([bool]($sl1.label -and -not (SlCircleMeets $sl1.circle $sl1.label))) "circle: $(SlShort $sl1.circle); label: $(SlShort $sl1.label)"
  }
  SlViewport 1440 900; SlCase (SlSceneJson $pinsCircleSpan)
  $sl2 = SlCircleDrop 1001 0 2 1 0 (-0.35)
  if (Shard-Take) {
  Check 'circle and label, 2x1 span at 1440, control: the label''s text box does not meet the Swap circle' ([bool]($sl2.label -and $sl2.circle -and -not (SlCircleMeets $sl2.circle $sl2.label))) "circle: $(SlShort $sl2.circle); label: $(SlShort $sl2.label)"
  }

  # F6b. The Put Behind label on a 2x1 span at 1024 is not clipped (review finding on 22253d0: the chip reads "Behi"). F6 measures
  #      the words, not the chip, so it passes with the clip. Scope first: the label is drawn on the span, with its Put Behind title.
  SlViewport 1024 768; SlCase (SlSceneJson $pinsCircleSpan)
  $cl1 = SlCircleDrop 1001 0 2 1 0 (-0.35)
  if (Shard-Take) {
  Check 'label clip, 2x1 span at 1024, scope: the Put Behind label is drawn on the span' ([bool]($cl1.shown -and $cl1.clip -and "$($cl1.clip.title)" -match 'Behind')) "label: $(SlShort $cl1.clip)"
  Check 'label clip, 2x1 span at 1024, red: the Put Behind label is not clipped (its content fits its width)' ([bool]($cl1.clip -and $cl1.clip.sw -le ($cl1.clip.cw + 1))) "label: $(SlShort $cl1.clip)"
  }
  SlViewport 1440 900; SlCase (SlSceneJson $pinsCircleSpan)
  $cl2 = SlCircleDrop 1001 0 2 1 0 (-0.35)
  if (Shard-Take) {
  Check 'label clip, 2x1 span at 1440, control: the Put Behind label is not clipped' ([bool]($cl2.clip -and $cl2.clip.sw -le ($cl2.clip.cw + 1))) "label: $(SlShort $cl2.clip)"

  # F6c. A locked tile released on a taken cell opens the warning, and its pending tile waits in that cell over the taken tile
  #      (review finding on 22253d0: at 1440 and 1024 both titles read). Only one title may read in the cell: the taken title is
  #      hidden, or the pending tile is opaque. Control: with no warning open, the taken title is the one that reads.
  foreach ($vw in @(@(1440, 900), @(1024, 768))) {
    $wz = "$($vw[0])"
    SlViewport $vw[0] $vw[1]; SlCase (SlSceneJson $pinsTwoClaudeLock)
    $tw0 = SlTitles 1002
    Check "warning over a taken cell, $wz, control: with no warning, the taken title is the one title that reads" ([bool]($tw0 -and $tw0.n -eq 1 -and $tw0.takenReadable -and -not $tw0.pendText)) "titles: $(SlShort $tw0)"
    SlDrag (SlAt (SlBox 1001) 0.5 0.5) (SlSlotAt 1)
    $tw = SlTitles 1002; $pb = $tw.pendBox; $tb = $tw.takenBox
    $inCell = [bool]($tw -and $pb -and $tb -and (($pb.l + $pb.r) / 2) -gt $tb.l -and (($pb.l + $pb.r) / 2) -lt $tb.r -and (($pb.t + $pb.b) / 2) -gt $tb.t -and (($pb.t + $pb.b) / 2) -lt $tb.b)
    $inView = [bool]($tb -and $tb.l -ge 0 -and $tb.t -ge 0 -and $tb.r -le $vw[0] -and $tb.b -le $vw[1])
    $apart = [bool]($tw -and $tw.dlgBox -and $tb -and -not (SlMeets $tw.dlgBox $tb))
    Check "warning over a taken cell, $wz, scope: the warning is open, its pending tile waits over the taken cell in view, and the warning sits outside that cell" ([bool]($tw -and $tw.dlgOpen -and $inCell -and $inView -and $apart)) "warning: $(SlShort $tw.dlgBox); pending: $(SlShort $pb); taken: $(SlShort $tb)"
    Check "warning over a taken cell, $wz, red: only one title reads in the taken cell" ([bool]($tw -and $tw.n -eq 1)) "readable: $($tw.n); pending '$($tw.pendText)' reads $($tw.pendReadable); taken '$($tw.takenText)' reads $($tw.takenReadable)"
  }
  }

  # Tiny block, ruling 2026-11-16 13:29 CST (label fallback). A block with no room clear of the Swap circle, even for the icon at 8 px
  #      or more, shows no Put Behind label: its solid border and the circle carry the cue. An interior cell of a 13 by 6 grid at 1440
  #      is about 40 by 35 px, with a 28 px circle. The old code draws a 6 px icon chip in the block's corner, over the circle.
  $pinsTiny = SlPins '{"app":"claude","match":"Refactor","mon":"wide","slots":[32]}' '{"app":"chrome","match":"Quarterly","mon":"wide","slots":[33]}'
  SlViewport 1440 900; SlCase (SlSceneJson $pinsTiny '[]' '' '' '"c":13,"r":6')
  $tn = SlCircleDrop 1006 32 1 1 (-0.4) (-0.4) -Chip -fx 0.3 -fy 0.5
  $tnB = $tn.block; $tnC = $tn.circle; $tnD = $tn.drop; $tnChip = $tnD.chip
  $tnCb = if ($tnC) { @{ l = $tnC.x - $tnC.w / 2; t = $tnC.y - $tnC.h / 2; r = $tnC.x + $tnC.w / 2; b = $tnC.y + $tnC.h / 2 } } else { $null }
  $tnSize = [bool]($tnB -and $tnB.w -ge 36 -and $tnB.w -le 44 -and $tnB.h -ge 30 -and $tnB.h -le 38)
  if (Shard-Take) {
  Check 'tiny block, 1440, scope: the block is about 40 by 34 px, its Swap circle is drawn at the 28 px floor, and the Put Behind zone is under the pointer (3 px border)' ([bool]($tnSize -and (SlCircleFits $tnC $tnB) -and $tnD.shown -and "$($tnD.cls)" -match '\bon\b' -and $tnD.bw -eq 3)) "block: $(SlShort $tnB); circle: $(SlShort $tnC); drop: $(SlShort $tnD)"
  }
  $tnClear = [bool]($tnC -and (-not $tnChip -or -not $tnChip.shown -or (-not (SlMeets $tnChip.box $tnCb) -and -not (SlCircleMeets $tnC $tnChip.box))))
  if (Shard-Take) {
  Check "tiny block, 1440, red: the Put Behind chip is not drawn, or it meets neither the Swap circle's box nor its disc" $tnClear "chip: $(SlShort $tnChip); circle box: $(SlHit $tnCb)"
  }
  # Control: the same corner drop on a roomy 1x1 cell at 1440, where the chip is drawn clear of the circle. Green on d9834c7.
  SlViewport 1440 900; SlCase (SlSceneJson $pinsCQ)
  $tc = SlCircleDrop 1006 0 1 1 (-0.4) (-0.4) -Chip
  $tcCb = if ($tc.circle) { @{ l = $tc.circle.x - $tc.circle.w / 2; t = $tc.circle.y - $tc.circle.h / 2; r = $tc.circle.x + $tc.circle.w / 2; b = $tc.circle.y + $tc.circle.h / 2 } } else { $null }
  if (Shard-Take) {
  Check 'tiny block control, 1x1 cell at 1440, scope: the Swap circle is drawn, and the Put Behind zone is under the pointer with its chip drawn' ([bool]($tc.circle -and $tc.drop.shown -and "$($tc.drop.cls)" -match '\bon\b' -and $tc.drop.bw -eq 3 -and $tc.drop.chip -and $tc.drop.chip.shown)) "circle: $(SlShort $tc.circle); drop: $(SlShort $tc.drop)"
  Check "tiny block control, 1x1 cell at 1440: the Put Behind chip meets neither the Swap circle's box nor its disc" ([bool]($tcCb -and $tc.drop.chip -and -not (SlMeets $tc.drop.chip.box $tcCb) -and -not (SlCircleMeets $tc.circle $tc.drop.chip.box))) "chip: $(SlShort $tc.drop.chip); circle box: $(SlHit $tcCb)"
  }

  # F7. Forced colours (review finding on 1ff9835). A guard, green on head: in headless Edge's forced-colors emulation a missing
  #     cell keeps its dashed border on top, and a disabled Merge computes to GrayText. The claim did not reproduce on b9643c3,
  #     so no red is claimed here (see the report's Input Needed). It is the last case: it sets the emulation, and resets it.
  SlSend 'Emulation.setEmulatedMedia' @{ features = @(@{ name = 'forced-colors'; value = 'active' }) }
  SlViewport 1440 900; SlCase (SlSceneJson $pinsCQ)
  SlCtrlClick (SlAt (SlBox 1001) 0.5 0.5)
  SlCtrlClick (SlSlotAt 2)
  $fcOn = SlGet "matchMedia('(forced-colors: active)').matches"
  # The pointer-events switch is put back at once; .miss has pointer-events none, so the hit test needs it on for the one read.
  $fcMiss = SlGet "(() => { const m = document.querySelector('.miss'); if (!m) return null; m.style.pointerEvents = 'auto'; const r = m.getBoundingClientRect(); const e = document.elementFromPoint(r.left + r.width / 2, r.top + r.height / 2); m.style.pointerEvents = ''; const cs = getComputedStyle(m); return { onTop: e === m, bs: cs.borderTopStyle, bw: parseFloat(cs.borderTopWidth), bc: cs.borderTopColor }; })()"
  if (Shard-Take) {
  Check 'forced colours, scope: the emulation is on, and a non-rectangle pick draws a missing cell' ([bool]($fcOn -eq $true -and $fcMiss)) "forced-colors: $fcOn; miss: $(SlShort $fcMiss)"
  Check 'forced colours, guard: a missing cell on an occupied cell is drawn on top, with a visible dashed border' ([bool]($fcMiss.onTop -eq $true -and $fcMiss.bs -eq 'dashed' -and $fcMiss.bw -gt 0 -and "$($fcMiss.bc)" -notmatch 'rgba\(0, 0, 0, 0\)')) "miss: $(SlShort $fcMiss)"
  }
  $fcMergeState = SlBtnState '.mbar' 'Merge'
  $fcMerge = SlGet "(() => { const b = [...document.querySelectorAll('.mbar button')].find(x => x.textContent.trim() === 'Merge'); if (!b) return null; const p = document.createElement('span'); p.style.cssText = 'forced-color-adjust:none;color:GrayText;position:absolute'; document.body.appendChild(p); const gray = getComputedStyle(p).color; p.remove(); const cs = getComputedStyle(b); return { disabled: b.disabled, color: cs.color, gray: gray, fca: cs.forcedColorAdjust, bs: cs.borderTopStyle }; })()"
  if (Shard-Take) {
  Check 'forced colours, guard: a disabled Merge reads as disabled (its text is GrayText, or it opts out of forced colours)' ([bool]($fcMergeState -eq 'disabled' -and $fcMerge -and ($fcMerge.color -eq $fcMerge.gray -or $fcMerge.fca -eq 'none'))) "Merge: $(SlShort $fcMerge)"
  }
  SlSend 'Emulation.setEmulatedMedia' @{ features = @() }

  # ---------- Page load: the first data fetch fails once ----------
  # app.html loadAll fetches the snapshot once, so one dropped fetch (a TypeError, as a dropped connection gives) must not leave the
  # board empty. The fault goes into the page before its scripts run, so it reaches loadAll's first call. Each fault counts its
  # failures in sessionStorage under a key of its own, so a reload of the page is not failed again. The control and the always-
  # failing case pass on the old code: they hold the page to a drawn scene with no fault, and to a plain error in the footer.
  # Each group is one gate: its page drive and its Checks run in one shard, and a fault is set only inside its own gate.
  if (Shard-Take) {
  SlViewport 1440 900
  $plCtl = SlCase (SlSceneJson '[]' '["*"]') -Soft
  $plCtlTiles = SlGet "document.querySelectorAll('.tile').length"
  Check 'page load, control, no fault: the page draws the scene' ([bool]($plCtl.ready -and $plCtlTiles -gt 0)) "tiles: $plCtlTiles; $($plCtl.diag)"
  }

  if (Shard-Take) {
  $plKey = 'tilePageLoad-' + [guid]::NewGuid().ToString('N')
  $plId = PlFaultOn 'once' $plKey
  try {
    $plRed = SlCase (SlSceneJson '[]' '["*"]') -Soft
    $plFired = SlJs "sessionStorage.getItem('$plKey')"
    $plFooter = SlJs "document.getElementById('msg').textContent.trim()"
    $plScope = ($plFired -eq '1')
    Check 'page load, scope: the first snapshot fetch was failed once' $plScope "failed fetches counted: $plFired"
    # Scope first: without the fault the page draws the scene anyway, so the red needs the fault to have fired.
    Check 'page load, red: after one dropped snapshot fetch, the page still draws the scene' ([bool]($plScope -and $plRed.ready)) "the page stopped at its one fetch and drew no scene; footer: '$plFooter'"
  } finally {
    PlFaultOff $plId
    [void](SlJs "(() => { try { sessionStorage.removeItem('$plKey'); } catch (e) {} return true; })()")
  }
  }

  if (Shard-Take) {
  $plKeyAll = 'tilePageLoad-' + [guid]::NewGuid().ToString('N')
  $plAll = PlFaultOn 'always' $plKeyAll
  try {
    $plDown = SlCase (SlSceneJson '[]' '["*"]') -Soft -Polls 1
    $plDownFired = SlJs "sessionStorage.getItem('$plKeyAll')"
    $plDownMsg = SlJs "document.getElementById('msg').textContent.trim()"
    Check 'page load, scope: every snapshot fetch is failed, and the page made one' ([bool]$plDownFired) "failed fetches counted: $plDownFired"
    Check 'page load, control, every fetch fails: the footer names the failure in plain words, not a blank board' ([bool]($plDownMsg -match 'could not' -and $plDownMsg -notmatch 'TypeError|undefined|null')) "footer: '$plDownMsg'; ready: $($plDown.ready)"
  } finally {
    PlFaultOff $plAll
    [void](SlJs "(() => { try { sessionStorage.removeItem('$plKeyAll'); } catch (e) {} return true; })()")
  }
  }

  # ---------- Preview POST: the first POST of a preview is dropped ----------
  # app.html previewRun posts once. A dropped connection (fetch throws a TypeError) fails the scene's preview at once, though the
  # server is fine. loadAll already tries a dropped fetch again (PR 65); previewRun does not. The target: previewRun sends the POST
  # again once, after a short wait, and only on a TypeError; then it fails as today. A 500 reply and an unreadable 200 reply are not sent again. PvDrive
  # arms the fault after the load and runs one preview of the scene, so each group counts the POSTs of that one call. Each group is one
  # gate. Its scope Check goes first: the page held the scene's preview, the fault met a POST, and the call finished.
  if (Shard-Take) {
  $pvOnce = PvDrive 'drop-once'
  Check 'preview POST, dropped once, scope: the fault dropped a POST of the scene''s preview and the call finished' ([bool]$pvOnce.ok) (PvWhy $pvOnce)
  Check 'preview POST, dropped once, red: the POST is sent again after the drop (two POSTs)' ([bool]($pvOnce.ok -and $pvOnce.posts -eq 2)) "POSTs seen: $($pvOnce.posts); the page gave up at the first drop"
  Check 'preview POST, dropped once, red: the scene''s preview is drawn from the second answer, with no Preview failed line' ([bool]($pvOnce.ok -and $pvOnce.fresh -and $pvOnce.msg -notlike 'Preview failed*')) "fresh preview: $($pvOnce.fresh); status: '$($pvOnce.msg)'"
  }

  if (Shard-Take) {
  $pvDown = PvDrive 'drop-always'
  Check 'preview POST, every POST dropped, scope: the fault dropped a POST of the scene''s preview and the call finished' ([bool]$pvDown.ok) (PvWhy $pvDown)
  Check 'preview POST, every POST dropped, red: the POST is sent once more, then the page gives up (two POSTs)' ([bool]($pvDown.ok -and $pvDown.posts -eq 2)) "POSTs seen: $($pvDown.posts)"
  Check 'preview POST, every POST dropped, control: it fails as today (the status line names the scene and the stopped server, and no preview is kept)' ([bool]($pvDown.ok -and $pvDown.msg -ceq 'Preview failed for Stack and lock: The app server stopped answering' -and -not $pvDown.drawn)) "status: '$($pvDown.msg)'; preview kept: $($pvDown.drawn)"
  }

  if (Shard-Take) {
  $pv500 = PvDrive 'status500'
  Check 'preview POST, 500 reply, scope: the fault answered a POST of the scene''s preview with a 500 and the call finished' ([bool]$pv500.ok) (PvWhy $pv500)
  Check 'preview POST, 500 reply, control: the POST is not sent again (one POST)' ([bool]($pv500.ok -and $pv500.posts -eq 1)) "POSTs seen: $($pv500.posts)"
  Check 'preview POST, 500 reply, control: it fails as today (the status line names the scene and the server''s words, and no preview is kept)' ([bool]($pv500.ok -and $pv500.msg -ceq 'Preview failed for Stack and lock: Server out of order' -and -not $pv500.drawn)) "status: '$($pv500.msg)'; preview kept: $($pv500.drawn)"
  }

  if (Shard-Take) {
  $pvBad = PvDrive 'badbody'
  Check 'preview POST, unreadable 200 reply, scope: the fault answered a POST of the scene''s preview with a body that is not JSON and the call finished' ([bool]$pvBad.ok) (PvWhy $pvBad)
  Check 'preview POST, unreadable 200 reply, control: the POST is not sent again (one POST)' ([bool]($pvBad.ok -and $pvBad.posts -eq 1)) "POSTs seen: $($pvBad.posts)"
  Check 'preview POST, unreadable 200 reply, control: it fails as today (the status line names the scene and says the server gave no layout, and no preview is kept)' ([bool]($pvBad.ok -and $pvBad.msg -ceq 'Preview failed for Stack and lock: The server gave no layout' -and -not $pvBad.drawn)) "status: '$($pvBad.msg)'; preview kept: $($pvBad.drawn)"
  }

  # ---------- Ruling 2026-11-16 (label fallback): the Put Behind label with Sora loaded ----------
  # The fonts-blocked cases above prove only the fallback font, so these run in a browser that allows Google Fonts. The label takes
  # the longest form that fits clear of the Swap circle: beside it, else the bottom right corner with the word Behind, else the icon
  # alone. It is never under or over the circle. The fonts-blocked browser is stopped first; this one starts on its own profile folder.
  $script:ws.Dispose(); $script:ws = $null
  Get-CimInstance Win32_Process -Filter "Name='msedge.exe'" | ? { $_.CommandLine -like "*$($script:udd)*" } | % { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
  $script:udd = Join-Path $run 'edge-sora'
  $edgeProc = SlStartBrowser -AllowFonts
  if (Shard-Take) {
  SlSoraCase 1024 768 '2x1 span' 1001 2 $pinsCircleSpan
  SlSoraCase 1440 900 '2x1 span' 1001 2 $pinsCircleSpan
  SlSoraCase 1024 768 '1x1 cell' 1006 1 $pinsCQ
  SlSoraCase 1440 900 '1x1 cell' 1006 1 $pinsCQ
  # Forced colours on the icon-alone chip, under Sora: the 1024 2x1 span and the 1024 1x1 cell (ruling 2026-11-16 12:45 CST).
  SlForcedCase 1024 768 '2x1 span' 1001 2 $pinsCircleSpan
  SlForcedCase 1024 768 '1x1 cell' 1006 1 $pinsCQ
  }
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
Shard-Report 'stack-lock'
if ($script:fail) { "$($script:fail) check(s) failed."; exit 1 } else { 'All checks passed.' }
