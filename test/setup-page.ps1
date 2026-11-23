# Monitor setups, the page (decision monitor-setups): what the board, the inspector and the scene cards do for the plugged-in setup.
# Plain asserts, one FAIL line per failing check. Its own file, run in a child powershell by test\run.ps1 (its FAIL lines count there).
# Run alone: powershell -NoProfile -ExecutionPolicy Bypass -File test\setup-page.ps1
#
# The page runs in headless Edge, driven over the DevTools protocol. No #selftest hook is used: a hook is app.html code, so a commit
# whose page is not built answers no hook at all, and a case would fail for "no hook", which is not the named cause. Each case writes
# its own config, opens the page on a dry-run server (-From: no window moves), wraps fetch before it acts, and reads what the page sent
# and what it shows. Waits are on page conditions, never on a fixed time.
# The page is shown at a fixed 1440 by 900 viewport. Fix-View sets it once the page is open, and every reset returns to it.
# A case that needs another size sets its own with Set-View.
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
#   Split Cell, empty cells and open halves (layout-free items 2 and 6; split-cell-notes S9 to S13; plan lane L2b, PR B): a still click on a
#     whole empty cell selects it, and the inspector reads Empty Space with Split Cell. A drag across cells, or 8px inside one cell, still draws
#     a zone (controls). Split Cell on an empty cell sends one POST /layout and leaves both halves empty, each named Open half, with no Fills
#     last. A still click on an open half selects it: the Open Half section has Join Halves and Keep This Half Empty. An open half's accessible
#     name reads Open half and Fills last (fill on), Stays empty and Fill is off (fill off), or Kept empty; under 40px it draws no words. Keep
#     This Half Empty sends fill.keepEmpty [{mon, slots}]. A second split remaps keepEmpty like fill.held; Join Halves on a kept half drops its
#     entry; a kept half blocks halving; Clear Board deletes keepEmpty; the Fill Empty Cells switch keeps it (guard). Tab reaches each empty
#     cell. The labels match tile.ps1's fill-last slot in a dry run. Names come from the accessibility tree (Accessibility.getFullAXTree).
#     A free half inside a zone is named Open half and Zone fills last (fill on), and the slot is the one tile.ps1 gives the zone's next
#     window; a zone's whole free block keeps its plain empty name, and an open half outside any zone keeps Fills last (controls).
#     A zone on a monitor that is not the fill monitor names no half Zone fills last (tile.ps1 gives that monitor no unit, so it fills the
#     cell first); the same zone on U1 still does. A zone half offers Keep This Half Empty and no Join Halves, and its Keep line reads
#     No window goes here. A zone half on a [1,2] unit is named as the engine fills it.
#   Kept half wait reason (debt kept-half-wait-reason, decision fill-controls): a window the fill leaves in Windows That Stay Put only because
#     a half is kept empty reads a reason that names the kept half (the words "keep" or "kept", and "half") and does not read No room, since no
#     column is missing. Read from the chip's accessible name, the reason between the title and "Stays put". Controls: with no kept half the open half takes
#     that window (so the kept half is the cause), and on a full board with no half the reason is still No room: add a column.
#   Split Cell, selection and stacks: a selected empty cell is still the cell the user picked after Undo or a Columns change, or it is
#     cleared. Join Halves on an empty half takes the front window of the other half, never a window stacked behind it. A split that doubles
#     nothing is one page-only undo step: Undo sends no POST, names the split in the status, and keeps the saved pins.
#   Free Layout (layout-free items 14-29; free-layout-notes F1-F16; plan lane L4). The page's contract, as the checks at the end of this
#     file read it: the switch is input[role=switch] labelled Free Layout in the Monitor section (the section that holds #monh), and the
#     key F toggles it. A monitor label reads Free Layout. Each tile is .tile[data-id]. Each space carries data-space (its index in reading
#     order): an empty one has class empty, a lent one class lent with one i per borrower (class fromL or fromR), a gap that stays class
#     gap. A save sends one POST /layout whose grids.U1 keeps c and r and holds free.areas (tile.ps1's shape). The page draws each tile at
#     px() of the engine's rect, and tile.ps1 places each pinned window at its area's pixel rect.
#   Free Layout review fixes (PR 58, round 1; F1 to F4): a window dropped on the space of the scene's last pin names that space; an arrow
#     move leaves the target space holding only its pin; Back to the Grid with Snap keeps a locked window's cell and lock, and the unlocked
#     neighbour gives its cell up; Restore keeps a locked window's pin and lock; a drop on a held space says that the window it displaces
#     goes to the list, and the status says the same. A drop on a held space offers Swap and Put Behind (the grid's two targets: the middle
#     swaps, the lower band puts behind); Put Behind adds the window to the pin's behind list, in the grid's form {app, match}.
#   Free Layout review fixes (PR 58, round 2; F6 to F8): a drag from a space onto a space held by an unpinned window swaps, and that window
#     takes the space the dragged one left; Put Behind from a space leaves the space it left naming nothing; Move To onto a space held by a
#     locked pin keeps that pin, its lock and its space.
#   Inert trigger switch (mockup docs/design/mockups/inert-trigger-switch.html): an extra switch that is On and can
#     do nothing for its scene is inert (needNote's three cases: Call Size on a scene that is not Listen or Meetings, Setup with no setup picked,
#     Work Match on a scene the activity map does not name). Rail: a chip is a child of its card's .chips. An inert chip carries a class that names
#     the state, or words past its name; a working chip stays its bare name. The rail line counts the scenes with a working trigger and says how
#     many hold a switch that does nothing; with none working it reads No scene has a trigger on yet. Inspector: an inert On row reads inactive,
#     a working row (a conflict note does not make one inert) keeps a bare On, the Extra Triggers line reads N on, N inactive, N warning, and
#     the callout of a scene with only inert switches reads No working trigger is on. The control checks hold on the page as it stands.
#     On the strip (under 1180 px) an inert chip's reason line is shown, as it is at 1440.
#     Turning a switch On (debt inert-switch-announces-moves): the line it says, in the footer and in the note under the scene, agrees with
#     its row. An inert switch says it is inactive and does not say it moves windows without asking; a working switch still says it moves them,
#     and any switch turned Off still says Save to keep it.
#   Free Layout stacked space: a window put on a space whose pin has a behind stack, by a drop from the list
#     or by Move To, takes the stack: the new pin's behind list is the holder's, as the grid's swapInto hands it on.
#   Draw Zone armed (mockup docs/design/mockups/draw-zone-hard-to-find.html, its notes beside it): #zadd is a toggle. aria-pressed reads false when it is off and
#     true when it is on. A press arms it and opens no dialog; a second press turns it off. While it is on, #hint reads "Draw Zone is on. Drag across cells to draw a
#     zone. Esc cancels.", #msg reads "Draw Zone is on. Drag across cells to draw a zone, or use Pick Cells by Menu. Esc cancels.", and #bbar has a button "Pick Cells by
#     Menu" (not shown when it is off) that opens today's "Draw a Zone on" dialog. A drag from any cell or window draws a zone with no Shift (the New Zone dialog opens
#     on release and the window stays where it was), and a still click picks no cell. It turns off after a zone is added or canceled, on Esc (also in the middle of a
#     draw), on a second press, and on a change of scene. The pressed button is filled in --ink, with --panel text. #keys reads "Draw Zone, then Pick Cells by Menu, picks
#     a zone's cells with the keyboard." and "Esc cancels a drag, a resize, a zone you are drawing, or Draw Zone." Two options have a case each: the board cue (while it is
#     on, a cell's edge is blue and dashed, its tint is blue, and the pointer over a window and over an empty cell is a crosshair) and the idle hint (#hint reads today's
#     live hint and then " Drag across empty cells to draw a zone.").
# Guards: they hold on the page as it stands, and a mutant on a scratch copy turns each red. They are the unplugged, offline, Refresh
# clears Undo, delete, size id, and Could not forget cases.
#
# Shards: -Shard n -Of 3 runs only shard n's cases, so test\run.ps1 can run the file in three processes. The cases are numbered in the
# order they are invoked, and the shards take contiguous ranges of that order (cuts below), so each shard keeps the order of its cases.
# A run with no arguments runs every case. Each shard prints `cases shard n of Of ran R of T, skipped S`, which run.ps1 checks: every case
# ran or was skipped once, T being the gate total the file pins (Shard-Init). A run with no Microsoft Edge skips its cases, and counts them.
param([int]$Shard = 1, [int]$Of = 1)
if (($Of -ne 1 -and $Of -ne 3) -or $Shard -lt 1 -or $Shard -gt $Of) { throw "setup-page shards: -Of is 1 or 3, and -Shard is 1 to -Of (got $Shard of $Of)" }
$shardCuts = @(39, 79)   # shard 1 runs cases 1 to 39, shard 2 runs 40 to 79, shard 3 runs 80 to the last (about a third of the time each)
$ErrorActionPreference = 'Stop'
# A direct run gets a job of its own, so a hard kill of the file also ends its Edge and server (test\direct-run-job.ps1).
. (Join-Path $PSScriptRoot 'direct-run-job.ps1')
Enter-DirectRunJob
$root = Split-Path $PSScriptRoot
$serve = Join-Path $root 'serve.ps1'; $appHtml = Join-Path $root 'app.html'
$fixture = Join-Path $PSScriptRoot 'fixture.json'; $scenesFile = Join-Path $root 'scenes.json'
$utf8 = New-Object Text.UTF8Encoding $false
$script:fail = 0
. (Join-Path $PSScriptRoot 'shard.ps1')
Shard-Init $Shard $Of @($shardCuts | Select-Object -First ($Of - 1)) 186
function Check($name, $ok, $detail = '') { if ($ok) { "PASS  $name" } else { $script:fail++; "FAIL  $name  $detail" } }
# One case. An error inside it is one FAIL line, and the run goes on. A case outside this shard's range is not run; it is counted, so
# every shard counts the same cases.
function Case([string]$name, [scriptblock]$body) {
  if (-not (Shard-Take)) { return }
  try { Revive-Edge $name; & $body } catch { Show-EdgeNote; $script:fail++; "FAIL  $name  threw: $($_.Exception.Message)" }
}

$edge = @("${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe", "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe") | ? { Test-Path -LiteralPath $_ } | Select-Object -First 1
if (-not $edge) { 'SKIP  page cases: Microsoft Edge not found in either Program Files folder.'; Shard-Skip 'no Microsoft Edge'; Shard-Report 'setup-page'; if ($script:fail) { "$($script:fail) check(s) failed."; exit 1 } else { exit 0 } }

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
$edgeLaunches = 0; $edgeDropped = $false; $reviveFailed = $false; $keepDir = $null; $edgeNote = $null

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
# Parks the page on about:blank before a config write. The page's own autosave is a timer (app.html saveLayout) and POSTs /layout, and
# a previous case's page can still hold one: it would write config.json while this write runs. The page first settles the POSTs it has
# sent, then navigates, which drops its timers. Every write here is followed by a page open, so nothing needs the old page.
function Park-Page {
  if (-not $script:ws) { return }
  [void](Js $script:ws 'if (window.__h) { await window.__h.settle(); } return true')
  [void](Cdp $script:ws 'Page.navigate' @{ url = 'about:blank' })
  [void](WaitFor $script:ws 'location.href === "about:blank"' 20)
}
# config.ps1 is dot-sourced for its Retry-TileIO, the product's one home for the retry a reader holding config.json needs: the server reads
# the file on every request, and a write that meets that read fails for a moment. The test's home is the one set just before.
$env:TILE_HOME = $tileHome; try { . (Join-Path $root 'config.ps1') } finally { $env:TILE_HOME = $null }
function Put-Config($cfg) {
  Park-Page
  $text = ConvertTo-Json -Depth 20 -Compress -InputObject $cfg
  Retry-TileIO { [IO.File]::WriteAllText((Join-Path $tileHome 'config.json'), $text, $utf8) }
}
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
  try {
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
  } catch {
    # A socket that is not Open means Edge dropped. Note-EdgeDrop prints the FAIL line once per launch. A protocol error leaves the socket Open.
    if ($sock.State -ne [Net.WebSockets.WebSocketState]::Open) { Note-EdgeDrop $sock "during $method" }
    throw
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
# The viewport. Set-View sets the page's size in CSS pixels at one device pixel each. Fix-View sets the default, 1440 by 900. A reset uses
# Fix-View and never a clear: a cleared override falls back to the headless window's own size, which is too small for the page.
function Set-View($sock, [int]$w, [int]$h) { [void](Cdp $sock 'Emulation.setDeviceMetricsOverride' @{ width = $w; height = $h; deviceScaleFactor = 1; mobile = $false }) }
function Fix-View($sock) { Set-View $sock 1440 900 }
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

# ---- Edge: one launch, the drop it can have, and the relaunch ----------------------------------------------------------------------
# Each launch has a profile and a log of its own in the run folder: edge-profile and edge.log, then edge-profile-r1 and edge-r1.log for
# the first relaunch. So a relaunch never reads a dead Edge's DevToolsActivePort, and never overwrites the log or Crashpad a drop needs.
# --enable-logging --v=0 --log-file keeps Edge's own log. Edge starts with the real user folders, as bay.ps1 and stack-lock.ps1 do: under
# a temp USERPROFILE it does not reliably open its DevTools port. The server child keeps the temp profile and its own TILE_HOME.
function Start-Edge {
  $script:edgeLaunches++
  $n = $script:edgeLaunches - 1
  $profDir = Join-Path $runDir $(if ($n -eq 0) { 'edge-profile' } else { "edge-profile-r$n" })
  $logFile = Join-Path $runDir $(if ($n -eq 0) { 'edge.log' } else { "edge-r$n.log" })
  if ($script:ws) { try { $script:ws.Dispose() } catch { } }
  $env:USERPROFILE = [Environment]::GetFolderPath('UserProfile'); $env:APPDATA = [Environment]::GetFolderPath('ApplicationData')
  try { $script:edgeProc = Start-Process $edge -PassThru -WindowStyle Hidden -ArgumentList '--headless', '--disable-gpu', '--no-first-run', '--remote-debugging-port=0', "--user-data-dir=$profDir", '--enable-logging', '--v=0', "--log-file=$logFile", '--host-resolver-rules="MAP fonts.googleapis.com 0.0.0.0, MAP fonts.gstatic.com 0.0.0.0"', 'about:blank' } finally { $env:USERPROFILE = $prof; $env:APPDATA = Join-Path $prof 'AppData\Roaming' }
  $null = $script:edgeProc.Handle   # PowerShell 5.1 reads ExitCode after an exit only when the handle was opened while the process ran
  # Port 0: Edge picks a free port and writes it to DevToolsActivePort in its profile. A port picked here and freed before Edge starts
  # can be taken by another file running at the same time, which is how a page used to fail to open. So the port is read from Edge.
  $dtFile = Join-Path $profDir 'DevToolsActivePort'; $portWait = Get-Date; $port = $null
  while (-not $port) {
    if (Test-Path -LiteralPath $dtFile) { $first = @(Get-Content -LiteralPath $dtFile -ErrorAction SilentlyContinue)[0]; if ("$first" -match '^\d+$') { $port = "$first" } }
    if (-not $port) { if (((Get-Date) - $portWait).TotalSeconds -gt 60) { throw 'Edge did not write its DevTools port within 60 s' }; Start-Sleep -Milliseconds 100 }
  }
  # The page target: DevTools answers once Edge is up. A wait on that answer, not a sleep.
  $targets = @(); $t0 = Get-Date; $lastErr = ''
  while (-not $targets.Count -and ((Get-Date) - $t0).TotalSeconds -lt 60) {
    try { $raw = (Invoke-WebRequest -UseBasicParsing "http://127.0.0.1:$port/json/list").Content; $targets = @(($raw | ConvertFrom-Json) | ? { $_.type -eq 'page' }) } catch { $lastErr = $_.Exception.Message }
    if (-not $targets.Count) { Start-Sleep -Milliseconds 250 }
  }
  if (-not $targets.Count) { throw "DevTools listed no page on port $port within 60 s: $lastErr" }
  $sock = New-Object Net.WebSockets.ClientWebSocket
  [void]$sock.ConnectAsync([Uri]$targets[0].webSocketDebuggerUrl, [Threading.CancellationToken]::None).GetAwaiter().GetResult()
  $script:ws = $sock
  # The default viewport, set before the first navigation. The override stays on this page target across every Page.navigate.
  Fix-View $sock
}
# Ends every msedge process of this run, and waits up to 30 s for each to exit, so its logs and Crashpad are closed before Keep-EdgeLogs
# copies them. The run folder is in each one's command line, and each run has its own. A process that is still there after the wait is no
# FAIL here: Keep-EdgeLogs prints its own FAIL if it cannot copy a log, and a normal run keeps no logs.
function Stop-Edge {
  try {
    $ids = @(Get-CimInstance Win32_Process -Filter "Name='msedge.exe'" | ? { $_.CommandLine -like "*$runDir*" } | % { $_.ProcessId })
    foreach ($id in $ids) { Stop-Process -Id $id -Force -ErrorAction SilentlyContinue }
    if ($ids) { Wait-Process -Id $ids -Timeout 30 -ErrorAction SilentlyContinue }
  }
  catch { $script:fail++; "FAIL  Edge processes were not all stopped: $($_.Exception.Message)" }
}
# The first drop of a launch prints one FAIL line: the socket's state, and whether Edge is still running, with its exit code once it has
# exited. The kept folder for the run's Edge logs is named here, and Keep-EdgeLogs fills it before the run folder is removed.
function Note-EdgeDrop($sock, [string]$where) {
  if ($script:edgeDropped) { return }
  $script:edgeDropped = $true
  $state = if ($sock) { [string]$sock.State } else { 'no socket' }
  $exited = 'unknown'; $code = 'n/a'
  try { $script:edgeProc.Refresh(); $exited = $script:edgeProc.HasExited; if ($exited) { $code = $script:edgeProc.ExitCode } } catch { }
  # A sibling of the run folders, named <pid>-<UUID> like one: the sweep removes it by age, and this run's teardown leaves it.
  if (-not $script:keepDir) { $script:keepDir = Join-Path $runRoot ("$PID-" + [guid]::NewGuid().ToString()) }
  $script:fail++
  $script:edgeNote = "FAIL  Edge DevTools socket not open ($where): socket $state, Edge HasExited $exited, ExitCode $code. Edge logs kept in $($script:keepDir)"
}
# Prints the drop's FAIL line, once. Note-EdgeDrop runs inside Cdp, whose output the caller would take instead of printing it, so the line
# waits here until a case, a relaunch or the outer finally prints it. The finally is the last stop, so no drop goes unprinted.
function Show-EdgeNote {
  if ($script:edgeNote) { $script:edgeNote; $script:edgeNote = $null }
}
# Keeps the log and the Crashpad folder of every launch, once a drop was seen. It runs after Stop-Edge has waited for Edge to exit, so the
# logs are closed and the crash dumps are written. The folder is a sibling of the run folder, so the run's cleanup does not remove it.
function Keep-EdgeLogs {
  if (-not $script:keepDir) { return }
  try {
    New-Item -ItemType Directory -Force $script:keepDir | Out-Null
    Set-Content -LiteralPath (Join-Path $script:keepDir 'drop.txt') -Value "shard $Shard of $Of, $(Get-Date -Format s), pid $PID"
    foreach ($f in @(Get-ChildItem -LiteralPath $runDir -Filter 'edge*.log' -File)) { Copy-Item -LiteralPath $f.FullName -Destination $script:keepDir -Force }
    foreach ($d in @(Get-ChildItem -LiteralPath $runDir -Directory -Filter 'edge-profile*')) {
      $cp = Join-Path $d.FullName 'Crashpad'
      if (Test-Path -LiteralPath $cp) { Copy-Item -LiteralPath $cp -Destination (Join-Path $script:keepDir "$($d.Name)-Crashpad") -Recurse -Force }
    }
  } catch { $script:fail++; "FAIL  Edge logs were not all kept in $($script:keepDir): $($_.Exception.Message)" }
}
# Bandaid: a case that starts on a socket that is not Open gets one relaunch of Edge, on a new profile and log, so the case that hit the drop
# fails and the later cases run. Each drop gets one relaunch. The run stays red: the drop and the relaunch each print a FAIL line. After a
# relaunch that fails, no more are tried, so the later cases fail at once instead of each waiting out the 60 s port wait. Remove it once the
# cause of the drop is fixed.
function Revive-Edge([string]$name) {
  if (-not $script:ws -or $script:ws.State -eq [Net.WebSockets.WebSocketState]::Open) { return }
  if ($script:reviveFailed) { throw 'Edge did not relaunch after an earlier drop' }
  Note-EdgeDrop $script:ws "before '$name'"
  Show-EdgeNote
  $script:fail++
  "FAIL  Edge relaunched before '$name', on a new profile and log"
  Stop-Edge
  # The drop is cleared only by a launch that works, so a failed relaunch never notes the same drop twice.
  try { Start-Edge; $script:edgeDropped = $false } catch { $script:reviveFailed = $true; throw }
}

try {
  $srv = Start-Child "-File `"$serve`" -NoBrowser -From `"$snapPath`""
  $url = $srv.StandardOutput.ReadLine()
  # Its state lives in the run folder (--user-data-dir); the server child keeps the temp profile and its own TILE_HOME.
  Start-Edge

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
    Set-View $ws 1440 $height
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
    } finally { Fix-View $ws }
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
      Set-View $ws $w 900
      try {
        $opened = Open-Kind-Rail $ws
        Check "${w}: the kind rail opens on Focus (control)" $opened 'the page did not draw the rail in time'
        if (-not $opened) { continue }
        $m = Js $ws ($kindJs + $cutJs)
        Check "${w}: every card is drawn (scope)" ([int]$m.cards -eq $expectKind.Count) "cards drawn: $($m.cards) of $($expectKind.Count)"
        Check "${w}: the Solo card's bottom row is measured (control)" ([bool]$m.soloRow) 'no bottom row on the Solo card'
        Check "${w}: no card's bottom-row label is cut" (@($m.cut).Count -eq 0) (@($m.cut) -join ' | ')
        if ($w -eq 1024) { Check '1024: every card has one height' (@(@($m.heights) | Sort-Object -Unique).Count -eq 1) "card heights: $(@($m.heights) -join ', ')" }
      } finally { Fix-View $ws }
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
  # The pin of window $i (an index into $splitWins) on these slots of monitor $mon (U1 unless given). $behind lists the windows stacked behind it.
  function Split-Pin([int]$i, $slots, [bool]$lock = $false, $behind = $null, [string]$mon = 'U1') {
    $p = [pscustomobject]@{ app = $splitWins[$i][0]; match = $splitWins[$i][1]; mon = $mon; slots = @($slots) }
    if ($lock) { $p | Add-Member -NotePropertyName lock -NotePropertyValue $true }
    if ($behind) { $p | Add-Member -NotePropertyName behind -NotePropertyValue @($behind) }
    $p
  }
  # The Focus scene's layout on the plugged setup, as JSON: the U1 grid (c by r, with mult and fill.unit when given), the pins, the zones,
  # and a fill on U1 that places nothing. $fillOver merges into the fill (held entries, off). $more adds the grids of other monitors (id to grid).
  function Split-Json([int]$c, [int]$r, $pins, $mult = $null, $unit = $null, $zones = @(), $fillOver = @{}, $more = @{}) {
    $g = [ordered]@{ c = $c; r = $r }
    if ($mult) { $g['mult'] = @(@($mult) -split ',' | % { [int]$_ }) }
    $f = [ordered]@{ mon = 'U1'; apps = @(); skip = @(); sort = 'app' }
    if ($unit) { $f['unit'] = @(@($unit) -split ',' | % { [int]$_ }) }
    foreach ($k in $fillOver.Keys) { $f[$k] = $fillOver[$k] }
    $grids = [ordered]@{ U1 = $g }; foreach ($k in $more.Keys) { $grids[$k] = $more[$k] }
    ConvertTo-Json -Depth 12 -Compress -InputObject ([ordered]@{ grids = $grids; pins = @($pins); zones = @($zones); fill = $f; bay = @() })
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
  # The page's own theme, set as its theme control sets it; nothing is stored.
  function Set-Theme($sock, [string]$t) { [void](Js $sock ("setTheme('" + $t + "'); return true")) }
  function Reset-Look($sock) {
    try { Fix-View $sock } catch { }
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
  # $behind: window i -> the windows stacked behind its pin, as {app, match}. A stacked window has no pin of its own, so its cell is empty.
  function Fl-Board([int[]]$noPin = @(), [int[]]$lock = @(), [hashtable]$behind = @{}) {
    $pins = @(); $map = @{}
    $stacked = @($behind.Values | % { $_ })
    for ($i = 0; $i -lt 10; $i++) {
      if ($noPin -contains $i -or $stacked -contains $i) { continue }
      $p = [pscustomobject]@{ app = $flWins[$i].app; match = $flWins[$i].match; mon = 'U1'; slots = @($i) }
      if ($lock -contains $i) { $p | Add-Member -NotePropertyName lock -NotePropertyValue $true }
      if ($behind.ContainsKey($i)) { $p | Add-Member -NotePropertyName behind -NotePropertyValue @($behind[$i] | % { [pscustomobject]@{ app = $flWins[$_].app; match = $flWins[$_].match } }) }
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
  # The windows the board does not hold, closed: with them shut, the only open windows are the board's, so a fill with an app has no other
  # unpinned window to take the empty spaces.
  $flOffBoard = @(1012, 1014, 1003, 1004, 1007, 1013, 1015, 1016)
  # The aligned snapshot without some windows (closed), or with some minimized.
  function Fl-Snap([int[]]$closed = @(), [int[]]$minimized = @()) {
    $o = ConvertFrom-Json $flSnap
    $o.windows = @($o.windows | ? { $closed -notcontains [int]$_.id })
    foreach ($w in @($o.windows | ? { $minimized -contains [int]$_.id })) { $w | Add-Member -Force -NotePropertyName min -NotePropertyValue $true }
    ConvertTo-Json -Depth 10 -Compress -InputObject $o
  }
  # Saves $layoutJson for the plugged setup, opens the page on Focus with $snapText, selects the ultrawide, and waits for the board to settle
  # (Fl-Still), so each read after it sees the board the page drew, not one mid-slide. Answers whether it opened.
  function Fl-Open($sock, [string]$layoutJson, [string]$snapText = $flSnap) {
    Put-Split $layoutJson
    $ok = Open-Page $sock $url 'focus' $snapText
    if ($ok) { [void](Fl-Select $sock 'Ultrawide'); Fl-Still $sock }
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
  # The board's settle, in the page. Each step waits two frames (or 1 s when no frame comes), then reads every tile rect. The board is still when
  # the page's POSTs have settled, no relayout is queued (rlay), no preview is in flight (inflight), no CSS transition runs, and the rects read
  # the same on two steps. A tile moves for 0.22 s after a monitor switch, a save or a drop (the tile transition in app.html), so a read taken at
  # once reads a move. Wait-Tile-Rest waits for one tile in the split section; this waits for the whole board and its preview, so it keeps its own.
  $flStillJs = @'
const rects = () => [...document.querySelectorAll(".tile")].map(t => { const r = t.getBoundingClientRect(); return [r.left, r.top, r.width, r.height].join(","); }).join("|");
const moving = () => rlay !== 0 || Object.keys(inflight).length > 0 || document.getAnimations().some(a => a.playState === "running");
const frames = () => Promise.race([new Promise(r => requestAnimationFrame(() => requestAnimationFrame(r))), new Promise(r => setTimeout(r, 1000))]);
await window.__h.settle();
let last = null, still = 0; const t0 = performance.now();
while (performance.now() - t0 < 10000 && still < 2) { await frames(); const g = rects(); still = (!moving() && g === last) ? still + 1 : 0; last = g; }
return still >= 2;
'@
  # Waits until the board is still before its rects are read. A board still moving after 10 s throws, so the case that asked for the wait
  # fails with that one cause and reads nothing from a moving board.
  function Fl-Still($sock) {
    if ((Js $sock $flStillJs) -ne $true) { throw 'the board did not settle within 10 s' }
  }
  # Slows the tile transition (app.html: .tile, .peek and .hdl) to $ms, as a mutant of the page would. A rule on the same selectors, later in
  # the sheet, sets only the duration, so the page's own transition: none rules (a tile held by the pointer, the still frames of a layout)
  # still win. Answers the duration a tile computes now, or null when no tile is drawn.
  function Fl-Slow($sock, [int]$ms) {
    Js $sock ('const s = document.createElement("style"); s.textContent = ".tile,.peek,.hdl{transition-duration:' + $ms + 'ms}"; document.head.appendChild(s); const t = document.querySelector(".tile"); return t ? getComputedStyle(t).transitionDuration : null;')
  }
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
  # The panel text of space $n after a click on it: the words the page shows for that space. $null when space $n is not on screen.
  function Fl-PanelOf($sock, [int]$n) {
    $c = Js $sock ($freeJs + 'const r = RR(spaceOf(' + $n + ')); return r ? { x: r.l + r.w / 2, y: r.t + r.h / 2 } : null;')
    if (-not $c) { return $null }
    Fl-Click $sock $c.x $c.y
    [string](Js $sock ($freeJs + 'return pageText();'))
  }
  # A pointer drag as a mouse makes it: a press at (x0, y0), ten moves to (x1, y1), a release. Shift is held when $shift. $probe, a page
  # expression, is read while the button is still down, and its value is returned. After the release it waits for the page's POSTs and then for
  # the board to be still (Fl-Still): the tiles slide to the drop's rects for the length of the tile transition, so a rect read at once reads a move.
  function Fl-Drag($sock, [double]$x0, [double]$y0, [double]$x1, [double]$y1, [bool]$shift = $false, [string]$probe = '') {
    $m = $(if ($shift) { 8 } else { 0 })
    [void](Cdp $sock 'Input.dispatchMouseEvent' @{ type = 'mouseMoved'; x = $x0; y = $y0; modifiers = $m })
    [void](Cdp $sock 'Input.dispatchMouseEvent' @{ type = 'mousePressed'; x = $x0; y = $y0; button = 'left'; buttons = 1; clickCount = 1; modifiers = $m })
    for ($s = 1; $s -le 10; $s++) { [void](Cdp $sock 'Input.dispatchMouseEvent' @{ type = 'mouseMoved'; x = $x0 + ($x1 - $x0) * $s / 10; y = $y0 + ($y1 - $y0) * $s / 10; button = 'left'; buttons = 1; modifiers = $m }) }
    $mid = $(if ($probe) { Js $sock $probe } else { $null })
    [void](Cdp $sock 'Input.dispatchMouseEvent' @{ type = 'mouseReleased'; x = $x1; y = $y1; button = 'left'; buttons = 0; clickCount = 1; modifiers = $m })
    [void](Js $sock 'await window.__h.settle(); return true')
    Fl-Still $sock
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
      Fl-Still $ws
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
    $none = Fl-Snap $flOffBoard
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
    $gf2Own = @(@($gf2.placed) | ? { $_.title -eq 'Refactor the grid solver' }).Count
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
      @{ tag = 'an app will not fit its space'; note = 'off size: is 410x840, restore rect 410x840'; raw = 'off size'; words = 'will not go under' },
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
        Check "err-apply ($tag): the row says it in words: will not go under" ($vis.Contains($words)) 'the row does not say it in words'
        Check "err-apply ($tag): a Give It N px button leads on" (@(@($rs.buttons) | ? { $_ -match '^Give It \d+ px$' }).Count -ge 1) 'no Give It N px button'
      } else {
        Check "err-apply ($tag): the row offers a fix button besides Close" (@(@($rs.buttons) | ? { $_ -ne 'Close' }).Count -ge 1) "buttons: $(@($rs.buttons) -join ' | ')"
      }
    }
  }

  # ---- Free Layout, PR 58 round 1 (F1 to F4), and the Put Behind drop on a held space ---------------------------------------------
  # Each case is red on 297f9cb by its named cause. A green control sits in the same case where the old code already does the act.
  # The drop label is read from #drop: each leaf's text and each title in it. Put Behind is the grid's word for a stacked window.
  $dropJs = @'
const dropInfo = () => { const d = document.getElementById("drop"); if (!d || !(d.style.display === "block" || d.style.display === "grid")) return null; const txt = [d, ...d.querySelectorAll("*")].map(e => (e.getAttribute("title") || "") + " " + (e.children.length ? "" : (e.textContent || ""))).join(" ").replace(/\s+/g, " "); return { put: /Put Behind/.test(txt), swap: /Swap/.test(txt), swapWith: /Swap with/.test(txt), list: /goes to the list/.test(txt), txt: txt }; };
const bayCentre = id => { const r = RR(document.querySelector('[data-bay="' + id + '"]')); return r ? { x: r.l + r.w / 2, y: r.t + r.h / 2 } : null; };
const spaceAt = (i, where) => { const r = RR(spaceOf(i)); if (!r) return null; return where === "bottom" ? { x: r.l + r.w / 2, y: r.b - 6 } : { x: r.l + r.w / 2, y: r.t + r.h / 2 }; };
'@
  # A window from Windows That Stay Put dragged onto a space. Answers the drop label read while the button is still down, or $null.
  function Fl-BayDrop($sock, [int]$bayId, [int]$space, [string]$where = 'centre') {
    [void](WaitFor $sock ('!!document.querySelector(''[data-bay="' + $bayId + '"]'')') 10)
    [void](Js $sock 'await window.__h.settle(); return true')
    $from = Js $sock ($freeJs + $dropJs + "return bayCentre($bayId);")
    $to = Js $sock ($freeJs + $dropJs + "return spaceAt($space, '$where');")
    if (-not ($from -and $to)) { return $null }
    Fl-Drag $sock $from.x $from.y $to.x $to.y $false ($freeJs + $dropJs + 'return dropInfo();')
  }
  # Chooses Space $n in the Move To list of the selected window. Answers whether the list and the option were there.
  function Fl-PickMoveTo($sock, [int]$n) {
    Js $sock ($freeJs + 'const s = document.getElementById("moveto"); if (!s) return false; const o = [...s.options].find(x => /Space ' + $n + '$/.test(x.textContent.trim())); if (!o) return false; s.value = o.value; s.dispatchEvent(new Event("change", { bubbles: true })); return true;')
  }
  # Switches Free Layout off and presses Back to Grid in the mode given (snap or restore). Answers whether the popover opened.
  function Fl-BackGo($sock, [string]$mode) {
    [void](Js $sock ($freeJs + 'const s = freeSw(); if (s) s.click(); return !!s;'))
    if (-not (WaitFor $sock '[...document.querySelectorAll("[role=dialog]")].some(d => /Back to the Grid/.test(d.textContent))' 10)) { return $false }
    if ($mode -eq 'restore') { [void](Js $sock ($freeJs + 'const l = [...document.querySelectorAll("label")].find(x => /Restore the Grid Layout/.test(x.textContent)); const r = l && l.querySelector("input[type=radio]"); if (r) r.click(); return !!r;')) }
    [void](Js $sock ($freeJs + 'const b = btnNamed(/^Back to Grid$/); if (b) b.click(); return !!b;'))
    $true
  }

  Case 'drop-last (F1): a window dropped on the space of the last pin names that space in the saved layout' {
    # Mutant: freeRelink reads a pin by its index, so the new pin takes the removed pin's index and is then unlinked from its space.
    $opened = Fl-Open $ws (Fl-Json (Fl-Board @(9)) -fillOver @{ off = $true })
    Check 'drop-last (F1): the page opens on Focus with space 8 held by the last pin (control)' $opened 'the page did not open on Focus in time'
    if (-not $opened) { return }
    $held = Js $ws ($freeJs + 'const s = spaceOf(8); return !!s && !s.classList.contains("empty");')
    Check 'drop-last (F1): space 8 is held (scope)' ($held -eq $true) 'space 8 is not held'
    if ($held -ne $true) { return }
    [void](Fl-BayDrop $ws 1014 8)
    $s = Fl-Saves $ws
    Check 'drop-last (F1): one POST /layout after the drop' ($s.layout.Count -eq 1) "POST /layout count: $($s.layout.Count)"
    if ($s.layout.Count -ne 1) { return }
    $L1 = $s.layout[0].layout
    $a8 = @($L1.grids.U1.free.areas)[8]
    $p8 = $(if ($a8 -and $null -ne $a8.pin) { @($L1.pins)[[int]$a8.pin] } else { $null })
    Check 'drop-last (F1): space 8 names the dropped Notepad pin' ($p8 -and $p8.app -eq 'notepad') "space 8 names: $(if ($p8) { $p8.app } else { 'no pin' })"
    Check 'drop-last (control): the window that held space 8 goes to Windows That Stay Put' (@(@($L1.bay) | ? { $_ -and $_.app -eq 'ms-teams' }).Count -eq 1) 'Design sync is not in Windows That Stay Put'
  }

  Case 'step-fill (F2): an arrow moves a pinned window onto a space that holds an app and a title, and the space keeps only its pin' {
    # Mutant: freeStep copies the pin into the space and leaves the space's old app and title beside it.
    $board = Fl-Board @(1)
    $board.areas[1]['app'] = 'claude'; $board.areas[1]['title'] = 'Pin parser edge cases'
    $opened = Fl-Open $ws (Fl-Json $board -fillOver @{ off = $true })
    Check 'step-fill (F2): the page opens on Focus (control)' $opened 'the page did not open on Focus in time'
    if (-not $opened) { return }
    $c = Fl-Centre (Fl-Rects $ws @(1001)) 1001
    Fl-Click $ws $c[0] $c[1]
    [void](Js $ws ($freeJs + 'const t = tileOf(1001); if (t) t.focus({ preventScroll: true }); return true;'))
    $focused = Js $ws ($freeJs + 'const a = document.activeElement; return !!a && !!a.dataset && a.dataset.id === "1001";')
    Check 'step-fill (F2): window 1001 is selected and has focus (scope)' ($focused -eq $true) 'window 1001 did not take focus'
    if ($focused -ne $true) { return }
    Press-Key $ws 'ArrowRight' 39
    $s = Fl-Saves $ws
    Check 'step-fill (F2): one POST /layout after the arrow' ($s.layout.Count -eq 1) "POST /layout count: $($s.layout.Count)"
    if ($s.layout.Count -ne 1) { return }
    $areas = @($s.layout[0].layout.grids.U1.free.areas); $pins = @($s.layout[0].layout.pins)
    $a0 = $areas[0]; $a1 = $areas[1]
    $p1 = $(if ($a1 -and $null -ne $a1.pin) { $pins[[int]$a1.pin] } else { $null })
    Check 'step-fill (F2): the window moved to space 1, and its pin names it (control)' ($p1 -and $p1.match -ceq 'Refactor the grid solver') "space 1 names: $(if ($p1) { $p1.match } else { 'no pin' })"
    Check 'step-fill (F2): the space it left holds no pin (control)' ($null -eq $a0.pin) "space 0 pin: $($a0.pin)"
    Check 'step-fill (F2): space 1 holds only its pin: no app and no title beside it' ($null -eq $a1.app -and $null -eq $a1.title) "space 1 app: $($a1.app), title: $($a1.title)"
  }

  foreach ($v in @(@{ tag = 'locked later'; lockedFirst = $false }, @{ tag = 'locked first, control'; lockedFirst = $true })) {
    Case "snap-lock ($($v.tag)): Back to the Grid with Snap to Cells keeps a locked window's cell and lock, and the unlocked neighbour gives its cell up" {
      # Mutant: a window whose snapped cells collide goes to the bay with its pin and lock deleted, whether or not it is the locked one.
      $freeM = 'Refactor the grid solver'; $lockM = 'Pin parser edge cases'
      $pinFree = [pscustomobject]@{ app = 'claude'; match = $freeM; mon = 'U1'; slots = @(0) }
      $pinLock = [pscustomobject]@{ app = 'claude'; match = $lockM; mon = 'U1'; slots = @(1); lock = $true }
      $fx = $(if ($v.lockedFirst) { 400 } else { 0 }); $lx = $(if ($v.lockedFirst) { 0 } else { 400 })
      $aFree = [ordered]@{ rect = @([double]($fx / 4096), [double]0, [double](300 / 4096), [double]0.5); pin = 0 }
      $aLock = [ordered]@{ rect = @([double]($lx / 4096), [double]0, [double](540 / 4096), [double]0.5); pin = 1 }
      $board = [pscustomobject]@{ areas = $(if ($v.lockedFirst) { @($aLock, $aFree) } else { @($aFree, $aLock) }); pins = @($pinFree, $pinLock) }
      $opened = Fl-Open $ws (Fl-Json $board -fillOver @{ off = $true })
      Check "snap-lock ($($v.tag)): the page opens on Focus with the two spaces (control)" $opened 'the page did not open on Focus in time'
      if (-not $opened) { return }
      if (-not (Fl-BackGo $ws 'snap')) { Check "snap-lock ($($v.tag)): switching Free Layout off opens Back to the Grid (scope)" $false 'no Back to the Grid popover'; return }
      $s = Fl-Saves $ws
      Check "snap-lock ($($v.tag)): one POST /layout after Back to Grid" ($s.layout.Count -eq 1) "POST /layout count: $($s.layout.Count)"
      if ($s.layout.Count -ne 1) { return }
      $L1 = $s.layout[0].layout
      $lp = @(@($L1.pins) | ? { $_ -and $_.match -ceq $lockM })[0]
      Check "snap-lock ($($v.tag)): the locked window keeps its pin and its lock" ($lp -and $lp.lock -eq $true) "pin: $(if ($lp) { "lock $($lp.lock)" } else { 'gone' })"
      Check "snap-lock ($($v.tag)): the locked window keeps cell 0" ((Split-SlotsOf $L1 $lockM) -eq '0') "cells: $(Split-SlotsOf $L1 $lockM)"
      $fp = @(@($L1.pins) | ? { $_ -and $_.match -ceq $freeM }).Count
      $inBay = @(@($L1.bay) | ? { $_ -and $_.title -eq 'Refactor the grid solver' }).Count
      Check "snap-lock ($($v.tag)): the unlocked neighbour gives its cell up: no pin, and it is in Windows That Stay Put" ($fp -eq 0 -and $inBay -eq 1) "pins: $fp, in Windows That Stay Put: $inBay"
    }
  }

  foreach ($v in @(@{ tag = 'locked'; lock = $true }, @{ tag = 'unlocked, control'; lock = $false })) {
    Case "restore-lock ($($v.tag)): Back to the Grid with Restore the Grid Layout keeps a locked window's pin and lock" {
      # Mutant: Restore drops a pin that has no cells, and its lock with it. Item 27 of the notes is silent on locks; item 24 keeps a pin's lock.
      $freeM = 'Refactor the grid solver'
      $pinNew = [pscustomobject]@{ app = 'claude'; match = $freeM; mon = 'U1'; slots = @() }
      if ($v.lock) { $pinNew | Add-Member -NotePropertyName lock -NotePropertyValue $true }
      $board = [pscustomobject]@{ areas = @([ordered]@{ rect = @([double]0, [double]0, [double](1000 / 4096), [double]0.5); pin = 0 }); pins = @($pinNew) }
      $opened = Fl-Open $ws (Fl-Json $board -fillOver @{ off = $true })
      Check "restore-lock ($($v.tag)): the page opens on Focus with the window pinned to a space (control)" $opened 'the page did not open on Focus in time'
      if (-not $opened) { return }
      if (-not (Fl-BackGo $ws 'restore')) { Check "restore-lock ($($v.tag)): switching Free Layout off opens Back to the Grid (scope)" $false 'no Back to the Grid popover'; return }
      $s = Fl-Saves $ws
      Check "restore-lock ($($v.tag)): one POST /layout after Back to Grid" ($s.layout.Count -eq 1) "POST /layout count: $($s.layout.Count)"
      if ($s.layout.Count -ne 1) { return }
      $L1 = $s.layout[0].layout
      $rp = @(@($L1.pins) | ? { $_ -and $_.match -ceq $freeM })[0]
      if ($v.lock) {
        Check 'restore-lock (locked): the window keeps a pin, and the pin keeps its lock' ($rp -and $rp.lock -eq $true) "pin: $(if ($rp) { "lock $($rp.lock)" } else { 'gone' })"
      } else {
        $inBay = @(@($L1.bay) | ? { $_ -and $_.title -eq 'Refactor the grid solver' }).Count
        Check 'restore-lock (unlocked, control): the window with no cell has no pin and is in Windows That Stay Put' (-not $rp -and $inBay -eq 1) "pin: $(if ($rp) { 'kept' } else { 'none' }), in Windows That Stay Put: $inBay"
      }
    }
  }

  Case 'drop-words (F4): a window dropped on a held space says that the window it displaces goes to the list, and the status agrees' {
    # Mutant: the label reads Swap with X and the status says X stays where it is, while X moves to Windows That Stay Put (freeAssign).
    $opened = Fl-Open $ws (Fl-Json (Fl-Board @(9)) -fillOver @{ off = $true })
    Check 'drop-words (F4): the page opens on Focus (control)' $opened 'the page did not open on Focus in time'
    if (-not $opened) { return }
    $held = Js $ws ($freeJs + 'const s = spaceOf(1); return !!s && !s.classList.contains("empty");')
    Check 'drop-words (F4): space 1 is held (scope)' ($held -eq $true) 'space 1 is not held'
    if ($held -ne $true) { return }
    $mid = Fl-BayDrop $ws 1014 1 'centre'
    Check 'drop-words (F4): over the held space the drop offers a Swap (control)' ([bool]($mid -and $mid.swap)) "label: $(if ($mid) { $mid.txt } else { 'none' })"
    Check 'drop-words (F4): the label says the window it displaces goes to the list, and does not say Swap with it' ([bool]($mid -and $mid.list -and -not $mid.swapWith)) "label: $(if ($mid) { $mid.txt } else { 'none' })"
    $msg = [string](Js $ws ($freeJs + 'return document.getElementById("msg").textContent.replace(/\s+/g, " ").trim();'))
    Check 'drop-words (F4): the status says the window it displaces goes to the list' ($msg -match 'goes to the list') "status: $msg"
    Check 'drop-words (F4): the status does not say the window it displaces stays where it is' ($msg -notmatch 'stays where it is') "status: $msg"
  }

  Case 'behind-choice (Put Behind): a window dropped on a held space is offered Swap and Put Behind' {
    # Mutant: a held space offers Swap alone, the label freeDropShow draws today, with no Put Behind target.
    $opened = Fl-Open $ws (Fl-Json (Fl-Board @(9)) -fillOver @{ off = $true })
    Check 'behind-choice: the page opens on Focus (control)' $opened 'the page did not open on Focus in time'
    if (-not $opened) { return }
    $mid = Fl-BayDrop $ws 1014 1 'centre'
    Check 'behind-choice: over a held space the drop offers a Swap (control)' ([bool]($mid -and $mid.swap)) "label: $(if ($mid) { $mid.txt } else { 'none' })"
    Check 'behind-choice: over a held space the drop also offers Put Behind' ([bool]($mid -and $mid.put)) "label: $(if ($mid) { $mid.txt } else { 'none' })"
  }

  Case 'behind-drop (Put Behind): a window dropped on the lower band of a held space stacks behind the window that holds it, in the grid form' {
    # Mutant: the lower band swaps like the middle, so the window takes the space and the held window goes to Windows That Stay Put.
    $opened = Fl-Open $ws (Fl-Json (Fl-Board @(9)) -fillOver @{ off = $true })
    Check 'behind-drop: the page opens on Focus (control)' $opened 'the page did not open on Focus in time'
    if (-not $opened) { return }
    $mid = Fl-BayDrop $ws 1014 1 'bottom'
    Check 'behind-drop: over the lower band the drop offers Put Behind (scope)' ([bool]($mid -and $mid.put)) "label: $(if ($mid) { $mid.txt } else { 'none' })"
    $s = Fl-Saves $ws
    Check 'behind-drop: one POST /layout after the drop' ($s.layout.Count -eq 1) "POST /layout count: $($s.layout.Count)"
    if ($s.layout.Count -ne 1) { return }
    $L1 = $s.layout[0].layout
    $a1 = @($L1.grids.U1.free.areas)[1]
    $p1 = $(if ($a1 -and $null -ne $a1.pin) { @($L1.pins)[[int]$a1.pin] } else { $null })
    $beh = @($(if ($p1) { $p1.behind } else { $null }) | ? { $_ -and $_.app -eq 'notepad' })
    Check 'behind-drop: Notepad is stacked behind the window space 1 holds, as one behind entry' ($beh.Count -eq 1) "behind entries for Notepad: $($beh.Count)"
    Check 'behind-drop: the behind entry has the grid form, with an app and a match' ($beh.Count -eq 1 -and $beh[0].PSObject.Properties.Name -contains 'match') 'the behind entry has no match'
    $ownPin = @(@($L1.pins) | ? { $_ -and $_.app -eq 'notepad' }).Count
    $inBay = @(@($L1.bay) | ? { $_ -and $_.app -eq 'notepad' }).Count
    Check 'behind-drop: Notepad has no pin of its own and is not in Windows That Stay Put' ($ownPin -eq 0 -and $inBay -eq 0) "own pins: $ownPin, in Windows That Stay Put: $inBay"
  }

  Case 'swap-bay (control): a window dropped on the middle of a held space takes the space, and the window it displaces goes to Windows That Stay Put' {
    # Mutant: the middle of a held space stacks the window, or the displaced window stays on the board.
    $opened = Fl-Open $ws (Fl-Json (Fl-Board @(9)) -fillOver @{ off = $true })
    Check 'swap-bay: the page opens on Focus (control)' $opened 'the page did not open on Focus in time'
    if (-not $opened) { return }
    $mid = Fl-BayDrop $ws 1014 1 'centre'
    Check 'swap-bay: over the middle of a held space the drop offers a Swap (control)' ([bool]($mid -and $mid.swap)) "label: $(if ($mid) { $mid.txt } else { 'none' })"
    $s = Fl-Saves $ws
    Check 'swap-bay: one POST /layout after the drop (control)' ($s.layout.Count -eq 1) "POST /layout count: $($s.layout.Count)"
    if ($s.layout.Count -ne 1) { return }
    $L1 = $s.layout[0].layout
    $a1 = @($L1.grids.U1.free.areas)[1]
    $p1 = $(if ($a1 -and $null -ne $a1.pin) { @($L1.pins)[[int]$a1.pin] } else { $null })
    Check 'swap-bay: Notepad takes space 1 (control)' ($p1 -and $p1.app -eq 'notepad') "space 1 names: $(if ($p1) { $p1.app } else { 'no pin' })"
    $bayHas = @(@($L1.bay) | ? { $_ -and $_.title -eq 'Pin parser edge cases' }).Count
    Check 'swap-bay: Pin parser edge cases goes to Windows That Stay Put (control)' ($bayHas -eq 1) "Windows That Stay Put: $(@($L1.bay) | ConvertTo-Json -Compress -Depth 4)"
  }

  Case 'swap-space (control): a window dragged from one held space onto the middle of another trades places with it' {
    # Mutant: a drop between two held spaces leaves one window without a space, or stacks it.
    $opened = Fl-Open $ws (Fl-Json (Fl-Board @(9)) -fillOver @{ off = $true })
    Check 'swap-space: the page opens on Focus (control)' $opened 'the page did not open on Focus in time'
    if (-not $opened) { return }
    $r0 = Fl-Rects $ws @(1001, 1002)
    $from = Fl-Centre $r0 1001; $to = Fl-Centre $r0 1002
    [void](Fl-Drag $ws $from[0] $from[1] $to[0] $to[1])
    $s = Fl-Saves $ws
    Check 'swap-space: one POST /layout after the drag (control)' ($s.layout.Count -eq 1) "POST /layout count: $($s.layout.Count)"
    if ($s.layout.Count -ne 1) { return }
    $L1 = $s.layout[0].layout
    $pinAt = { param($i) $a = @($L1.grids.U1.free.areas)[$i]; $(if ($a -and $null -ne $a.pin) { @($L1.pins)[[int]$a.pin] } else { $null }) }
    $p0 = & $pinAt 0; $p1 = & $pinAt 1
    Check 'swap-space: Pin parser edge cases takes space 0 (control)' ($p0 -and $p0.match -ceq 'Pin parser edge cases') "space 0 names: $(if ($p0) { $p0.match } else { 'no pin' })"
    Check 'swap-space: Refactor the grid solver takes space 1 (control)' ($p1 -and $p1.match -ceq 'Refactor the grid solver') "space 1 names: $(if ($p1) { $p1.match } else { 'no pin' })"
  }

  # ---- Free Layout, design-review findings (PR 58, round 1, the second review): wording, the panel of a space, focus, a split's status.
  Case 'fill-next (review): with Fill Empty Cells on, the panel of a space that is not next does not say the next new window fills it' {
    # Mutant: the panel says the next new window fills every empty space, not only the one first in reading order.
    # The fill has an app, so Fill Empty Cells fills: the first open space is next, and the others say so.
    $fillAll = @{ apps = @('*') }
    $opened = Fl-Open $ws (Fl-Json (Fl-Board @(8, 9)) -fillOver $fillAll) (Fl-Snap $flOffBoard)
    Check 'fill-next: the page opens with spaces 8 and 9 empty and Fill Empty Cells on (control)' $opened 'the page did not open on Focus in time'
    if (-not $opened) { return }
    $t9 = Fl-PanelOf $ws 9
    if ($null -eq $t9) { Check 'fill-next: space 9 is on screen (scope)' $false 'space 9 is not on screen'; return }
    Check 'fill-next: space 9, which is not next, does not say the next new window fills it' ($t9 -notmatch 'the next new window fills it') 'the panel says the next new window fills it'
    $t8 = Fl-PanelOf $ws 8
    if ($null -eq $t8) { Check 'fill-next: space 8 is on screen (scope)' $false 'space 8 is not on screen'; return }
    Check 'fill-next: space 8, which is next, says the next new window fills it (control)' ($t8 -match 'the next new window fills it') 'the panel does not say the next new window fills it'
  }

  Case 'fill-next (review), no fill app: with Fill Empty Cells on and no app to fill with, the panel of the next space says nothing fills it' {
    # Mutant: the panel says the next new window fills it whatever the fill apps are, as it did before the panel read the apps.
    $opened = Fl-Open $ws (Fl-Json (Fl-Board @(8, 9))) (Fl-Snap $flOffBoard)
    Check 'fill-next, no fill app: the page opens with spaces 8 and 9 empty and Fill Empty Cells on, with no app (control)' $opened 'the page did not open on Focus in time'
    if (-not $opened) { return }
    $t8 = Fl-PanelOf $ws 8
    if ($null -eq $t8) { Check 'fill-next, no fill app: space 8 is on screen (scope)' $false 'space 8 is not on screen'; return }
    Check 'fill-next, no fill app: space 8, which is next, says nothing fills it' ($t8 -match 'Nothing fills it') 'the panel does not say nothing fills it'
  }

  Case 'free-words (review): in Free Layout the board hint says space, names the Shift move of the whole line, and Move To reads Choose a Space' {
    # Mutant: the Free Layout hint is the grid's hint (it says cell), and Move To's first line reads Choose a Cell.
    $opened = Fl-Open $ws (Fl-Json (Fl-Board))
    Check 'free-words: the page opens on Focus (control)' $opened 'the page did not open on Focus in time'
    if (-not $opened) { return }
    $hint = [string](Js $ws ($freeJs + 'return document.getElementById("hint").textContent.replace(/\s+/g, " ").trim();'))
    Check 'free-words: the board hint is on the page (control)' ($hint.Length -gt 0) 'the board hint is empty'
    Check 'free-words: the board hint says a space, not a cell' ($hint -notmatch '\bcells?\b') "hint: $hint"
    Check 'free-words: the board hint names the Shift move of the whole line' ($hint -match 'Shift' -and $hint -match 'whole line') "hint: $hint"
    $c = Fl-Centre (Fl-Rects $ws @(1001)) 1001
    Fl-Click $ws $c[0] $c[1]
    $mt = [string](Js $ws ($freeJs + 'const s = document.getElementById("moveto"); if (!s || !s.options.length) return ""; return s.options[0].textContent.trim();'))
    Check 'free-words: Move To is in the inspector of the selected window (scope)' ($mt -ne '') 'no Move To list in the inspector'
    Check 'free-words: Move To first line says Choose a Space, not Choose a Cell' ($mt -eq 'Choose a Space') "first line: $mt"
  }

  Case 'back-words (review): the Back to the Grid popover says Restore moves pinned windows to Windows That Stay Put, and its cancel reads Keep Free Layout' {
    # Mutant: Restore promises cells only, and the cancel button reads Cancel.
    $opened = Fl-Open $ws (Fl-Json (Fl-Board))
    Check 'back-words: the page opens on Focus (control)' $opened 'the page did not open on Focus in time'
    if (-not $opened) { return }
    [void](Js $ws ($freeJs + 'const s = freeSw(); if (s) s.click(); return !!s;'))
    $pop = WaitFor $ws '[...document.querySelectorAll("[role=dialog]")].some(d => /Back to the Grid/.test(d.textContent))' 10
    Check 'back-words: switching off opens Back to the Grid (scope)' $pop 'no Back to the Grid popover'
    if (-not $pop) { return }
    $restore = [string](Js $ws ($freeJs + 'const l = [...document.querySelectorAll("label")].find(x => /Restore the Grid Layout/.test(x.textContent)); return l ? l.textContent.replace(/\s+/g, " ").trim() : "";'))
    Check 'back-words: Restore the Grid Layout says pinned windows go to Windows That Stay Put' ($restore -match 'Windows That Stay Put') "restore: $restore"
    $btns = Js $ws ($freeJs + 'return [...document.querySelectorAll("#backpop button")].map(b => b.textContent.replace(/\s+/g, " ").trim());')
    Check 'back-words: the cancel button reads Keep Free Layout' (@($btns) -contains 'Keep Free Layout') "buttons: $((@($btns) | % { [string]$_ }) -join ' | ')"
  }

  # ---- Free Layout, PR 58 round 2 (F6 to F8): a drag from a space onto an unpinned holder, Put Behind from a space, Move To onto a locked space.
  # Each case is red on d56c3b0 by its named cause. A green control sits in the same case where the old code already does the act.
  Case 'swap-held (F6): a window dragged from a space onto a space held by an unpinned window takes that space, and the window it held takes the space it left' {
    # Mutant: freeAssign swaps only with a pinned holder, so an unpinned holder's name is deleted and it takes no space. The label still says Swap with it.
    $board = Fl-Board @(1)
    $board.areas[1]['app'] = 'claude'; $board.areas[1]['title'] = 'Pin parser edge cases'
    $opened = Fl-Open $ws (Fl-Json $board -fillOver @{ off = $true })
    Check 'swap-held (F6): the page opens on Focus (control)' $opened 'the page did not open on Focus in time'
    if (-not $opened) { return }
    $held = Js $ws ($freeJs + 'const s = spaceOf(1); return !!s && !s.classList.contains("empty");')
    Check 'swap-held (F6): space 1 is held by the unpinned window (scope)' ($held -eq $true) 'space 1 is not held'
    if ($held -ne $true) { return }
    $from = Fl-Centre (Fl-Rects $ws @(1001)) 1001
    $to = Js $ws ($freeJs + $dropJs + "return spaceAt(1, 'centre');")
    $mid = Fl-Drag $ws $from[0] $from[1] $to.x $to.y $false ($freeJs + $dropJs + 'return dropInfo();')
    Check 'swap-held (F6): over the held space the drop offers Swap with the window it holds (control)' ([bool]($mid -and $mid.swapWith)) "label: $(if ($mid) { $mid.txt } else { 'none' })"
    $s = Fl-Saves $ws
    Check 'swap-held (F6): one POST /layout after the drop' ($s.layout.Count -eq 1) "POST /layout count: $($s.layout.Count)"
    if ($s.layout.Count -ne 1) { return }
    $L1 = $s.layout[0].layout
    $areas = @($L1.grids.U1.free.areas); $pins = @($L1.pins)
    $a0 = $areas[0]; $a1 = $areas[1]
    $p0 = $(if ($a0 -and $null -ne $a0.pin) { $pins[[int]$a0.pin] } else { $null })
    $p1 = $(if ($a1 -and $null -ne $a1.pin) { $pins[[int]$a1.pin] } else { $null })
    Check 'swap-held (F6): Refactor the grid solver takes space 1 (control)' ($p1 -and $p1.match -ceq 'Refactor the grid solver') "space 1 names: $(if ($p1) { $p1.match } else { 'no pin' })"
    $bNamed = [bool]($a0 -and (($a0.title -ceq 'Pin parser edge cases') -or ($p0 -and $p0.match -ceq 'Pin parser edge cases')))
    Check 'swap-held (F6): the window space 1 held takes the space the dragged window left (space 0 names it)' $bNamed "space 0 names: app $($a0.app), title $($a0.title), pin $(if ($p0) { $p0.match } else { 'none' })"
  }

  Case 'behind-from (F7): Put Behind from a space leaves the space the window held naming nothing' {
    # Mutant: freePutBehind gets no from, so the space the window left keeps its app and title, and still names the window that went behind.
    $board = Fl-Board @(0)
    $board.areas[0]['app'] = 'claude'; $board.areas[0]['title'] = 'Refactor the grid solver'
    $opened = Fl-Open $ws (Fl-Json $board -fillOver @{ off = $true })
    Check 'behind-from (F7): the page opens on Focus (control)' $opened 'the page did not open on Focus in time'
    if (-not $opened) { return }
    $held = Js $ws ($freeJs + 'const s = spaceOf(0); return !!s && !s.classList.contains("empty");')
    Check 'behind-from (F7): space 0 is held by the unpinned window (scope)' ($held -eq $true) 'space 0 is not held'
    if ($held -ne $true) { return }
    $from = Fl-Centre (Fl-Rects $ws @(1001)) 1001
    $to = Js $ws ($freeJs + $dropJs + "return spaceAt(1, 'bottom');")
    $mid = Fl-Drag $ws $from[0] $from[1] $to.x $to.y $false ($freeJs + $dropJs + 'return dropInfo();')
    Check 'behind-from (F7): over the lower band of the held space the drop offers Put Behind (control)' ([bool]($mid -and $mid.put)) "label: $(if ($mid) { $mid.txt } else { 'none' })"
    $s = Fl-Saves $ws
    Check 'behind-from (F7): one POST /layout after the drop' ($s.layout.Count -eq 1) "POST /layout count: $($s.layout.Count)"
    if ($s.layout.Count -ne 1) { return }
    $L1 = $s.layout[0].layout
    $areas = @($L1.grids.U1.free.areas); $pins = @($L1.pins)
    $a0 = $areas[0]; $a1 = $areas[1]
    $p1 = $(if ($a1 -and $null -ne $a1.pin) { $pins[[int]$a1.pin] } else { $null })
    $beh = @($(if ($p1) { $p1.behind } else { $null }) | ? { $_ -and $_.match -ceq 'Refactor the grid solver' })
    Check 'behind-from (F7): Refactor the grid solver is stacked behind the window space 1 holds (control)' ($beh.Count -eq 1) "behind entries for it: $($beh.Count)"
    $p0 = $(if ($a0 -and $null -ne $a0.pin) { $pins[[int]$a0.pin] } else { $null })
    $namesA = [bool]($a0 -and (($a0.title -ceq 'Refactor the grid solver') -or ($p0 -and $p0.match -ceq 'Refactor the grid solver')))
    Check 'behind-from (F7): the space the window left no longer names it' (-not $namesA) "space 0 still names it: title $($a0.title), pin $(if ($p0) { $p0.match } else { 'none' })"
  }

  foreach ($v in @(@{ tag = 'from the list'; pick = 'list' }, @{ tag = 'from a space'; pick = 'space' })) {
    Case "move-lock ($($v.tag), F8): Move To onto a space held by a locked pin keeps that pin, its lock and its space" {
      # Mutant: Move To calls freeAssign with no lock check (the drop and the grid's Move To both check the lock), so the locked pin is removed
      # (from the list) or swapped off its space (from a space). A Move To that saves nothing leaves the board as the seed layout has it.
      $seed = Fl-Json (Fl-Board @(9) @(0)) -fillOver @{ off = $true }
      $opened = Fl-Open $ws $seed
      Check "move-lock ($($v.tag), F8): the page opens on Focus with space 0 held by a locked pin (control)" $opened 'the page did not open on Focus in time'
      if (-not $opened) { return }
      $held = Js $ws ($freeJs + 'const s = spaceOf(0); return !!s && !s.classList.contains("empty");')
      Check "move-lock ($($v.tag), F8): space 0 is held (scope)" ($held -eq $true) 'space 0 is not held'
      if ($held -ne $true) { return }
      if ($v.pick -eq 'list') {
        $c = Js $ws ($freeJs + $dropJs + 'return bayCentre(1014);')
        if (-not $c) { Check "move-lock ($($v.tag), F8): window 1014 is in Windows That Stay Put (scope)" $false 'no entry for 1014 in Windows That Stay Put'; return }
        Fl-Click $ws $c.x $c.y
      } else {
        $c = Fl-Centre (Fl-Rects $ws @(1002)) 1002
        Fl-Click $ws $c[0] $c[1]
      }
      $picked = Fl-PickMoveTo $ws 1
      Check "move-lock ($($v.tag), F8): Move To offers Space 1, the space the locked pin holds (scope)" ($picked -eq $true) 'no Move To list for the selected window, or no Space 1 option'
      if ($picked -ne $true) { return }
      $s = Fl-Saves $ws
      $L1 = $(if ($s.layout.Count -gt 0) { $s.layout[$s.layout.Count - 1].layout } else { ConvertFrom-Json $seed })
      $lp = @(@($L1.pins) | ? { $_ -and $_.match -ceq 'Refactor the grid solver' })[0]
      Check "move-lock ($($v.tag), F8): the locked pin is still there, and keeps its lock" ($lp -and $lp.lock -eq $true) "pin: $(if ($lp) { "lock $($lp.lock)" } else { 'gone' })"
      $a0 = @($L1.grids.U1.free.areas)[0]
      $p0 = $(if ($a0 -and $null -ne $a0.pin) { @($L1.pins)[[int]$a0.pin] } else { $null })
      Check "move-lock ($($v.tag), F8): the locked pin keeps space 0" ($p0 -and $p0.match -ceq 'Refactor the grid solver') "space 0 names: $(if ($p0) { $p0.match } else { 'no pin' })"
    }
  }

  # ---- Free Layout: a window put on a stacked space takes the stack -----------------------------------
  # Space 1 is held by Pin parser edge cases (1002), with Quarterly roadmap (1006) and Projects (1010) stacked behind it in the grid's
  # behind form. The grid's swapInto hands the holder's behind list to the window that takes its cell. freeAssign must do the same, so the
  # windows behind the holder stay in the layout. The seed's stack is $flStack (Fl-Board -behind); $flStackWant is its list, sorted.
  $flStack = @{ 1 = @(3, 4) }
  $flStackWant = 'Projects|Quarterly roadmap'
  # The windows the page draws as stacked behind a front window, sorted: '1006,1010' for the seed above.
  $stackedJs = 'return prev().placed.filter(x => x.behind).map(x => x.id).sort((a, b) => a - b).join(",")'
  # The behind list of the pin that space $i names in a saved layout, as match texts sorted and joined by |. $null when the space names no pin.
  function Fl-BehindOf($layout, [int]$i) {
    $a = @($layout.grids.U1.free.areas)[$i]
    if (-not ($a -and $null -ne $a.pin)) { return $null }
    $p = @($layout.pins)[[int]$a.pin]
    (@(@($p.behind) | ? { $_ } | % { [string]$_.match } | Sort-Object) -join '|')
  }
  foreach ($v in @(@{ tag = 'drop from the list'; pick = 'drop' }, @{ tag = 'Move To from the list'; pick = 'moveto' })) {
    Case "stack-take ($($v.tag)): a window put on a space whose pin has a stack takes the stack with it" {
      # Mutant: freeAssign removes the holder's pin and its behind list with it and gives the new pin none, so the two windows stacked behind
      # the holder are in neither the pins nor the list (each leaves the layout).
      $opened = Fl-Open $ws (Fl-Json (Fl-Board @(9) -behind $flStack) -fillOver @{ off = $true })
      Check "stack-take ($($v.tag)): the page opens on Focus (control)" $opened 'the page did not open on Focus in time'
      if (-not $opened) { return }
      $held = Js $ws ($freeJs + 'const s = spaceOf(1); return !!s && !s.classList.contains("empty");')
      Check "stack-take ($($v.tag)): space 1 is held (scope)" ($held -eq $true) 'space 1 is not held'
      if ($held -ne $true) { return }
      $stk = Js $ws $stackedJs
      Check "stack-take ($($v.tag)): the page draws Quarterly roadmap and Projects stacked behind the holder (scope)" ($stk -eq '1006,1010') "windows drawn as stacked: '$stk'"
      if ($stk -ne '1006,1010') { return }
      if ($v.pick -eq 'drop') {
        $mid = Fl-BayDrop $ws 1014 1 'centre'
        Check "stack-take ($($v.tag)): over the middle of the stacked space the drop offers a Swap (scope)" ([bool]($mid -and $mid.swap)) "label: $(if ($mid) { $mid.txt } else { 'none' })"
      } else {
        $c = Js $ws ($freeJs + $dropJs + 'return bayCentre(1014);')
        if (-not $c) { Check "stack-take ($($v.tag)): window 1014 is in Windows That Stay Put (scope)" $false 'no entry for 1014 in Windows That Stay Put'; return }
        Fl-Click $ws $c.x $c.y
        $picked = Fl-PickMoveTo $ws 2
        Check "stack-take ($($v.tag)): Move To offers Space 2, the space the stacked pin holds (scope)" ($picked -eq $true) 'no Move To list for the selected window, or no Space 2 option'
        if ($picked -ne $true) { return }
      }
      $s = Fl-Saves $ws
      Check "stack-take ($($v.tag)): one POST /layout after the move (control)" ($s.layout.Count -eq 1) "POST /layout count: $($s.layout.Count)"
      if ($s.layout.Count -ne 1) { return }
      $L1 = $s.layout[0].layout
      $got = Fl-BehindOf $L1 1
      $a1 = @($L1.grids.U1.free.areas)[1]
      $p1 = $(if ($a1 -and $null -ne $a1.pin) { @($L1.pins)[[int]$a1.pin] } else { $null })
      Check "stack-take ($($v.tag)): Notepad takes space 1 (control)" ($p1 -and $p1.app -eq 'notepad') "space 1 names: $(if ($p1) { $p1.app } else { 'no pin' })"
      $bayHas = @(@($L1.bay) | ? { $_ -and $_.title -eq 'Pin parser edge cases' }).Count
      Check "stack-take ($($v.tag)): Pin parser edge cases, the front window, goes to Windows That Stay Put (control)" ($bayHas -eq 1) "Windows That Stay Put: $(@($L1.bay) | ConvertTo-Json -Compress -Depth 4)"
      if (-not $p1) { return }
      Check "stack-take ($($v.tag)): the Notepad pin carries the holder's stack, Projects and Quarterly roadmap" ($got -ceq $flStackWant) "behind list of the pin on space 1: '$got', the holder's was '$flStackWant'"
    }
  }

  Case 'stack-swap (control): a window dragged from a space onto a stacked space leaves the stack with the pin that moves' {
    # Mutant: the swap relinks the holder's pin to the space the dragged window left without its behind list, or the list goes with the old pin.
    $opened = Fl-Open $ws (Fl-Json (Fl-Board @(9) -behind $flStack) -fillOver @{ off = $true })
    Check 'stack-swap: the page opens on Focus (control)' $opened 'the page did not open on Focus in time'
    if (-not $opened) { return }
    $stk = Js $ws $stackedJs
    Check 'stack-swap: the page draws Quarterly roadmap and Projects stacked behind the holder (scope)' ($stk -eq '1006,1010') "windows drawn as stacked: '$stk'"
    if ($stk -ne '1006,1010') { return }
    $r0 = Fl-Rects $ws @(1001, 1002)
    $from = Fl-Centre $r0 1001; $to = Fl-Centre $r0 1002
    [void](Fl-Drag $ws $from[0] $from[1] $to[0] $to[1])
    $s = Fl-Saves $ws
    Check 'stack-swap: one POST /layout after the drag (control)' ($s.layout.Count -eq 1) "POST /layout count: $($s.layout.Count)"
    if ($s.layout.Count -ne 1) { return }
    $L1 = $s.layout[0].layout
    $a0 = @($L1.grids.U1.free.areas)[0]
    $p0 = $(if ($a0 -and $null -ne $a0.pin) { @($L1.pins)[[int]$a0.pin] } else { $null })
    Check 'stack-swap: Pin parser edge cases takes space 0 (control)' ($p0 -and $p0.match -ceq 'Pin parser edge cases') "space 0 names: $(if ($p0) { $p0.match } else { 'no pin' })"
    if (-not $p0) { return }
    $got = Fl-BehindOf $L1 0
    Check 'stack-swap: the stack, Projects and Quarterly roadmap, moves with Pin parser edge cases (control)' ($got -ceq $flStackWant) "behind list of the pin on space 0: '$got', the holder's was '$flStackWant'"
  }

  Case 'drag-settle (guard): with the tile transition slowed to 2 s, no tile is still moving when Fl-Drag returns' {
    # Mutant: Fl-Drag returns once the page's POSTs settle, with the tiles still sliding to their new rects (the tile transition, app.html
    # .tile). The cases that read rects after a drag (drag-segment, drag-line, Go Around) then read a half-grown tile. At 0.22 s that is a
    # flake; at 2 s it is a miss every run.
    $opened = Fl-Open $ws (Fl-Json (Fl-Board))
    Check 'drag-settle: the page opens on Focus (control)' $opened 'the page did not open on Focus in time'
    if (-not $opened) { return }
    $dur = Fl-Slow $ws 2000
    Check 'drag-settle: a tile now computes a 2 s transition (scope)' ([string]$dur -match '^2s(, 2s)*$') "tile transition duration: '$dur'"
    if ([string]$dur -notmatch '^2s(, 2s)*$') { return }
    $r0 = Fl-Rects $ws $flIds
    $okTiles = ($null -ne $r0.'1001') -and ($null -ne $r0.'1002')
    Check 'drag-settle: both windows are on the board (scope)' $okTiles 'tile 1001 or 1002 is not on the board'
    if (-not $okTiles) { return }
    $sp = Fl-SeamV $r0 1001 1002
    [void](Fl-Drag $ws $sp[0] $sp[1] ($sp[0] + 40) $sp[1])
    $r1 = Fl-Rects $ws $flIds
    $rest = WaitFor $ws 'document.getAnimations().every(a => a.playState !== "running")' 15
    Check 'drag-settle: the board comes to rest within 15 s (scope)' $rest 'a tile was still animating 15 s after the drop'
    if (-not $rest) { return }
    $r2 = Fl-Rects $ws $flIds
    $grew = $r2.'1001'.w - $r0.'1001'.w
    Check 'drag-settle: the drag grew the left window by at least 20 px once the board rested (scope)' ($grew -ge 20) ("grew by " + [Math]::Round($grew, 1) + " px")
    if ($grew -lt 20) { return }
    $mv = @(Fl-Moved $r1 $r2 $flIds)
    Check 'drag-settle: no tile moves after Fl-Drag returns' ($mv.Count -eq 0) "moved after the drag returned: $($mv -join ', ')"
  }

  # ---- Split Cell: empty cells and open halves (layout-free items 2 and 6; split-cell-notes S9 to S13; plan lane L2b, PR B) ---------
  # A still click on a whole empty cell selects it: the inspector reads Empty Space, with Split Cell. A split of an empty cell leaves both
  # halves empty, each named Open half. An open half of a part-taken cell is named Open half and Fills last with fill on, Stays empty and
  # Fill is off with fill off, and Kept empty under Keep This Half Empty (fill.keepEmpty). Names are read from the accessibility tree
  # (Accessibility.getFullAXTree), the name a screen reader gets. $oneWinSnap holds window 1001 only; $tenWinSnap holds the ten windows of
  # halfSeed, all pinned, so a board with one open half has no window left that the fill could take.
  $oneWinSnap = ConvertTo-Json -Depth 10 -Compress -InputObject ([pscustomobject]@{ monitors = @($snapObj.monitors); windows = @($snapObj.windows | ? { [int]$_.id -eq 1001 }) })
  # The ids of the ten splitWins windows, in the fixture: Refactor, Pin parser, Pull request, Quarterly roadmap, pwsh tiler, pwsh docs watch,
  # Projects, Design sync, Downloads, todo.txt.
  $splitWinIds = @(1001, 1002, 1005, 1006, 1008, 1009, 1010, 1011, 1012, 1014)
  $tenWinSnap = ConvertTo-Json -Depth 10 -Compress -InputObject ([pscustomobject]@{ monitors = @($snapObj.monitors); windows = @($snapObj.windows | ? { $splitWinIds -contains [int]$_.id }) })
  # A number as the page reads it in its script: a decimal point, whatever the culture.
  function Num($v) { ([double]$v).ToString('R', [Globalization.CultureInfo]::InvariantCulture) }
  # The centre of fine cell $slot of the ultrawide, from the page's own cell boxes (one per fine cell, in reading order). Null when not drawn.
  function Cell-Point($sock, [int]$slot) {
    Js $sock ('const m = snap.monitors.find(q => q.role === "wide"); const c = m && m.el ? m.el.querySelectorAll(".cell")[__S__] : null; if (!c) return null; const r = c.getBoundingClientRect(); return { x: r.left + r.width / 2, y: r.top + r.height / 2 };'.Replace('__S__', "$slot"))
  }
  # A still press and release at a point, as a mouse makes them. $mods holds the modifier bits the events carry (8 is Shift).
  function Click-At($sock, [double]$x, [double]$y, [int]$mods = 0) {
    [void](Cdp $sock 'Input.dispatchMouseEvent' @{ type = 'mouseMoved'; x = $x; y = $y; modifiers = $mods })
    [void](Cdp $sock 'Input.dispatchMouseEvent' @{ type = 'mousePressed'; x = $x; y = $y; button = 'left'; buttons = 1; clickCount = 1; modifiers = $mods })
    [void](Cdp $sock 'Input.dispatchMouseEvent' @{ type = 'mouseReleased'; x = $x; y = $y; button = 'left'; buttons = 0; clickCount = 1; modifiers = $mods })
  }
  # A drag from one point to another, as a mouse makes it: pressed, moved in four steps with the button held, released at the end.
  function Drag-At($sock, [double]$x1, [double]$y1, [double]$x2, [double]$y2) {
    [void](Cdp $sock 'Input.dispatchMouseEvent' @{ type = 'mouseMoved'; x = $x1; y = $y1 })
    [void](Cdp $sock 'Input.dispatchMouseEvent' @{ type = 'mousePressed'; x = $x1; y = $y1; button = 'left'; buttons = 1; clickCount = 1 })
    foreach ($f in 0.25, 0.5, 0.75, 1.0) { [void](Cdp $sock 'Input.dispatchMouseEvent' @{ type = 'mouseMoved'; x = $x1 + ($x2 - $x1) * $f; y = $y1 + ($y2 - $y1) * $f; button = 'left'; buttons = 1 }) }
    [void](Cdp $sock 'Input.dispatchMouseEvent' @{ type = 'mouseReleased'; x = $x2; y = $y2; button = 'left'; buttons = 0; clickCount = 1 })
  }
  # A still click on fine cell $slot, as a user makes it. Answers the cell's point, whether the press lands on the cell and not on a window or
  # a button, and the layout POST count before the press.
  function Cell-Click($sock, [int]$slot) {
    $pt = Cell-Point $sock $slot
    if ($null -eq $pt) { return $null }
    $hit = Js $sock ('const e = document.elementFromPoint(' + (Num $pt.x) + ', ' + (Num $pt.y) + '); return { tag: e ? e.tagName : "none", cls: e ? String(typeof e.className === "string" ? e.className : (e.getAttribute("class") || "")) : "", tile: !!e && !!e.closest(".tile"), btn: !!e && !!e.closest("button") };')
    $on = ($hit.tag -ne 'none') -and (-not $hit.tile) -and (-not $hit.btn)
    # Settled first: a POST the page sends after it loads is counted before the press, not as the press's own.
    $before = [int](Js $sock 'await window.__h.settle(); return window.__h.posts("layout").length')
    if ($on) { Click-At $sock $pt.x $pt.y }
    [pscustomobject]@{ on = $on; before = $before; pt = $pt; hit = "$($hit.tag) class '$($hit.cls)', on a tile $($hit.tile), on a button $($hit.btn)" }
  }
  $headEmptyCond = '(() => { const h = document.getElementById("winh"); return !!h && h.textContent.trim() === "Empty Space"; })()'
  $headOpenCond = '(() => { const h = document.getElementById("winh"); return !!h && /open half/i.test(h.textContent); })()'
  $winhJs = 'const h = document.getElementById("winh"); return h ? h.textContent.replace(/\s+/g, " ").trim() : null;'
  # A control of the Window section (a switch or a button) found by the words its label, aria-label or text holds. $act is run on it:
  # '' to only find it, 'el.click()' to press it. Answers whether it was found.
  function Win-Control-Js([string]$words, [string]$act) {
    'const w = document.getElementById("win"); if (!w) return false; const el = [...w.querySelectorAll("input, button")].find(x => ((x.labels ? [...x.labels].map(l => l.textContent).join(" ") : "") + " " + (x.getAttribute("aria-label") || "") + " " + (x.textContent || "")).includes("__W__")); if (!el) return false; __A__; return true;'.Replace('__W__', $words).Replace('__A__', $act)
  }
  # The Empty Space split menu's item for one direction ("Side by Side" or "Stacked"), clicked. Answers whether an enabled item was there.
  $emptyItemJs = @'
const menu = [...document.querySelectorAll("[role=menu]")].find(m => m.getClientRects().length > 0 && /Split Cell/.test(m.textContent));
if (!menu) return false;
const it = [...menu.querySelectorAll("[role=menuitem]")].find(x => x.textContent.replace(/\s+/g, " ").trim().startsWith("__DIR__"));
if (!it || it.getAttribute("aria-disabled") === "true") return false;
it.click(); return true;
'@
  function Empty-Item-Js([string]$dir) { $emptyItemJs.Replace('__DIR__', $dir) }
  # Run in the page on each named node: its visible words (text a user can see, not hidden or 1 px clipped), its centre, its width, and the
  # fine cell its centre falls in (-1 when none). Read through Runtime.callFunctionOn, so it sees the node the accessibility tree named.
  $axInfoFn = @'
function () {
  const r = this.getBoundingClientRect(), cx = r.left + r.width / 2, cy = r.top + r.height / 2;
  const mon = snap.monitors.find(q => q.role === "wide");
  const cells = mon && mon.el ? [...mon.el.querySelectorAll(".cell")] : [];
  let slot = -1;
  cells.forEach((c, i) => { const q = c.getBoundingClientRect(); if (cx >= q.left && cx <= q.right && cy >= q.top && cy <= q.bottom) slot = i; });
  const words = [], walk = document.createTreeWalker(this, NodeFilter.SHOW_TEXT);
  while (walk.nextNode()) {
    const t = walk.currentNode.textContent.trim(), p = walk.currentNode.parentElement;
    if (!t || !p) continue;
    const s = getComputedStyle(p), b = p.getBoundingClientRect();
    if (s.display === "none" || s.visibility === "hidden" || parseFloat(s.opacity) === 0 || b.width < 2 || b.height < 2) continue;
    words.push(t);
  }
  return { words: words.join(" "), cx: cx, cy: cy, w: r.width, slot: slot };
}
'@
  # The named nodes of the accessibility tree whose accessible name matches $rx (case-sensitive). Text and ignored nodes are not named boxes.
  # One object per named node, emitted flat: a caller takes the list with @(...), and an empty list is zero objects.
  function Ax-Named($sock, [string]$rx, [string]$board = 'wide') {
    [void](Cdp $sock 'DOM.enable' @{})
    $ax = Cdp $sock 'Accessibility.getFullAXTree' @{}
    $named = @(@($ax.result.nodes) | ? { -not $_.ignored -and $_.backendDOMNodeId -and ([string]$_.role.value) -notmatch '^(StaticText|InlineTextBox|LineBreak)$' -and ([string]$_.name.value) -cmatch $rx })
    $out = @()
    foreach ($n in $named) {
      try {
        $ro = Cdp $sock 'DOM.resolveNode' @{ backendNodeId = [int]$n.backendDOMNodeId }
        $oid = [string]$ro.result.object.objectId
        if (-not $oid) { continue }
        $cr = Cdp $sock 'Runtime.callFunctionOn' @{ objectId = $oid; functionDeclaration = $axInfoFn.Replace('"wide"', '"' + $board + '"'); returnByValue = $true }
        $info = $cr.result.result.value
        $out += [pscustomobject]@{ name = [string]$n.name.value; role = [string]$n.role.value; words = [string]$info.words; w = [double]$info.w; slot = [int]$info.slot }
      } catch { }
    }
    $out
  }
  # The named nodes drawn on the board of monitor role $board (the ultrawide, wide, unless given), polled until $want of them are named or
  # $seconds pass (a page update lands after its POST). The first read waits for no preview in flight: until it lands, the board still
  # names the old preview's places, and a half the new one draws would be missed. Emitted flat, one object per half: a caller takes the
  # list with @(...).
  function Wait-Halves($sock, [string]$rx = 'Open half|Stays empty|Kept empty', [int]$want = 1, [int]$seconds = 10, [string]$board = 'wide') {
    $t0 = Get-Date
    # The same wait as Empty-Select, out of the same $seconds as the poll below, so the cap does not double. The poll reads at least once.
    [void](WaitFor $sock 'Object.keys(inflight).length === 0' $seconds)
    do {
      $found = @(Ax-Named $sock $rx $board | ? { $_.slot -ge 0 })
      if ($found.Count -ge $want) { break }
      Start-Sleep -Milliseconds 250
    } while (((Get-Date) - $t0).TotalSeconds -lt $seconds)
    $found
  }
  # The named halves as one line for a failure detail: name and slot of each, or none.
  function Half-Text($halves) { if (@($halves).Count -eq 0) { return 'none' }; (@($halves | % { "'$($_.name)' on slot $($_.slot)" })) -join '; ' }
  # The POST /layout bodies a case saw, as text for a failure detail: the setup key and the start of each body, or none.
  function Post-Text($posts) { $p = @($posts | ? { $_ }); if ($p.Count -eq 0) { return 'none' }; (@($p | % { $b = [string]$_.body; "key $(try { (ConvertFrom-Json $b).key } catch { '?' }): " + $b.Substring(0, [Math]::Min(200, $b.Length)) })) -join ' | ' }
  # The fill.keepEmpty entries of a layout as one line for a failure detail, or none.
  function Kept-Text($ke) { if (@($ke).Count -eq 0) { return 'none' }; (@($ke | % { "$($_.mon) " + ((Split-Ints $_.slots) -join ',') })) -join '; ' }
  # The slots of the zones in the one POST /layout a case sent, sorted, as one line; none when there is no POST or no zone.
  function Posted-Zones($posts) {
    $p = @($posts | ? { $_ })
    if ($p.Count -ne 1) { return 'none' }
    $z = @(@((ConvertFrom-Json $p[0].body).layout.zones) | ? { $_ })
    if ($z.Count -eq 0) { return 'none' }
    ((@($z | % { Split-Ints $_.slots })) | Sort-Object) -join ','
  }

  # Wait-Halves called while a preview is in flight (debt wait-halves-first-poll). A page edit starts a preview, and until it lands the
  # board still names the places the old preview drew; a half the new preview draws is missed by a read taken before. Here Hold-Js holds
  # the preview of the edit, so it is in flight when the helper is called. The gate opens at the second read of the page's in-flight table
  # (a wait that polls reads it again; one glance at it does not wait) and, as a hang guard that sits well above the run of a read, after
  # 8 s. A helper that reads the board first returns the old board, and the gate is still shut at its return. The helper's own cap is
  # 20 s here, above the guard.
  $gateArmJs = @'
const keys = Object.keys;
window.__pvOpened = false; window.__pvReads = 0;
window.__pvOpenNow = () => { window.__pvOpened = true; window.__pvOpen(); };
window.__pvUnhook = () => { Object.keys = keys; };
Object.keys = function (o) { if (o === inflight && ++window.__pvReads >= 2) { window.__pvUnhook(); window.__pvOpenNow(); } return keys.apply(this, arguments); };
window.__pvTimer = setTimeout(window.__pvOpenNow, 8000);
return true;
'@
  $gateDisarmJs = 'clearTimeout(window.__pvTimer); if (window.__pvUnhook) window.__pvUnhook(); if (window.__pvOpen) window.__pvOpen(); return true'
  Case 'wait halves: a half the preview in flight draws is waited for: Wait-Halves returns the board once the preview has landed, not the old one' {
    Put-Split (Split-Json 5 2 $halfSeed '2,1' '2,1')
    $opened = Open-Page $ws $url 'focus' $tenWinSnap
    Check 'wait halves: the page opens on Focus with ten windows pinned, one open half (control)' $opened 'the page did not open on Focus in time'
    if (-not $opened) { return }
    [void](WaitFor $ws 'Object.keys(inflight).length === 0' 20)
    $first = @(Ax-Named $ws 'Open half' | ? { $_.slot -ge 0 })
    Check 'wait halves: before the edit the board names one open half, on slot 1 (control)' ((($first | % { $_.slot }) -join ',') -eq '1') "named halves: $(Half-Text $first)"
    if ((($first | % { $_.slot }) -join ',') -ne '1') { return }
    [void](Js $ws (Hold-Js 'preview' 'pv' 'answer'))
    try {
      # Window 1002 holds cells 2 and 3 (slots 2 and 3); pinned to slot 2 alone, the new preview leaves slot 3 as an open half.
      [void](Js $ws 'pinWin(1002, snap.monitors.find(m => m.role === "wide"), 2); return true')
      $flying = WaitFor $ws '!!inflight.focus' 20
      $held = WaitFor $ws 'window.__pvAnswered === true' 20
      Check 'wait halves: the edit starts a preview of Focus, and its answer is held by the gate (scope)' ($flying -and $held) "preview in flight: $flying, answer held: $held"
      if (-not ($flying -and $held)) { return }
      $old = @(Ax-Named $ws 'Open half' | ? { $_.slot -ge 0 })
      Check 'wait halves: while the preview is in flight the board still names only slot 1, the old preview''s half (scope)' ((($old | % { $_.slot }) -join ',') -eq '1') "named halves: $(Half-Text $old)"
      if ((($old | % { $_.slot }) -join ',') -ne '1') { return }
      [void](Js $ws $gateArmJs)
      $halves = @(Wait-Halves $ws 'Open half' 1 20)
      $gateOpen = Js $ws 'return window.__pvOpened === true'
      [void](Js $ws $gateDisarmJs)
      [void](WaitFor $ws 'Object.keys(inflight).length === 0' 20)
      $settled = @(Ax-Named $ws 'Open half' | ? { $_.slot -ge 0 })
      $want = (($settled | % { $_.slot } | Sort-Object) -join ',')
      Check 'wait halves: once the preview has landed the board names open halves on slots 1 and 3 (scope)' ($want -eq '1,3') "named halves: $(Half-Text $settled)"
      if ($want -ne '1,3') { return }
      $got = (($halves | % { $_.slot } | Sort-Object) -join ',')
      Check 'wait halves: Wait-Halves, called while the preview is in flight, returns the open halves on slots 1 and 3' ($got -eq '1,3') "returned: $(Half-Text $halves); the page names $(Half-Text $settled) once the preview lands; the gate had opened by its return: $gateOpen"
    } finally {
      [void](Js $ws $gateDisarmJs)
    }
  }

  Case 'split open: a still click on a whole empty cell selects it: the inspector reads Empty Space, with Split Cell, and sends no POST /layout' {
    Put-Split (Split-Json 5 2 @(Split-Pin 0 @(0)))
    $opened = Open-Page $ws $url 'focus' $oneWinSnap
    Check 'split open: the page opens on Focus with window 1001 pinned (control)' $opened 'the page did not open on Focus in time'
    if (-not $opened) { return }
    $c = Cell-Click $ws 9
    Check 'split open: empty cell 9 is drawn, and the press lands on it, not on a window or a button (scope)' ($null -ne $c -and $c.on) "cell 9 is not drawn, or the press hits: $($c.hit)"
    if ($null -eq $c -or -not $c.on) { return }
    [void](WaitFor $ws $headEmptyCond 10)
    $head = Js $ws $winhJs
    Check 'split open: a still click on empty cell 9 selects it: the inspector heading reads Empty Space' ($head -ceq 'Empty Space') "the inspector heading reads: '$head'"
    Check 'split open: the Empty Space section has a Split Cell button' ((Js $ws ('return ' + $splitInspHasJs)) -eq $true) 'no Split Cell button in the inspector'
    $sent = Layout-Posts-After $ws $c.before
    Check 'split open: the still click sends no POST /layout' ($sent.Count -eq 0) "POST /layout count: $($sent.Count), bodies: $(Post-Text $sent)"
  }

  Case 'split open: a drag across three empty cells still draws a zone: the New Zone dialog, then one POST /layout with its cells (control)' {
    Put-Split (Split-Json 5 2 @(Split-Pin 0 @(0)))
    $opened = Open-Page $ws $url 'focus' $oneWinSnap
    Check 'split open: the page opens on Focus (control)' $opened 'the page did not open on Focus in time'
    if (-not $opened) { return }
    $a = Cell-Point $ws 2; $b = Cell-Point $ws 4
    Check 'split open: cells 2 and 4 are drawn (scope)' ($null -ne $a -and $null -ne $b) 'a cell is not drawn on the ultrawide'
    if ($null -eq $a -or $null -eq $b) { return }
    Drag-At $ws $a.x $a.y $b.x $b.y
    $dlg = WaitFor $ws '/New Zone: 3 Columns/.test((document.getElementById("dlgform") || {}).textContent || "")' 10
    Check 'split open: a drag across cells 2 to 4 opens the New Zone dialog for 3 columns (control)' $dlg 'no New Zone dialog after the drag'
    if (-not $dlg) { return }
    $before = [int](Js $ws 'return window.__h.posts("layout").length')
    Confirm-Ask $ws
    [void](WaitFor $ws ('window.__h.posts("layout").length > ' + $before) 10)
    $sent = Layout-Posts-After $ws $before
    $zs = Posted-Zones $sent
    Check 'split open: Add Zone sends one POST /layout with the zone on cells 2, 3 and 4 (control)' ($sent.Count -eq 1 -and $zs -eq '2,3,4') "POST /layout count: $($sent.Count), zone slots: $zs"
  }

  Case 'split open: an 8px drag inside empty cell 9 still draws a one-cell zone (control)' {
    Put-Split (Split-Json 5 2 @(Split-Pin 0 @(0)))
    $opened = Open-Page $ws $url 'focus' $oneWinSnap
    Check 'split open: the page opens on Focus (control)' $opened 'the page did not open on Focus in time'
    if (-not $opened) { return }
    $a = Cell-Point $ws 9
    Check 'split open: empty cell 9 is drawn (scope)' ($null -ne $a) 'no empty cell 9 on the ultrawide'
    if ($null -eq $a) { return }
    Drag-At $ws $a.x $a.y ($a.x + 8) $a.y
    $dlg = WaitFor $ws '/New Zone: 1 Column/.test((document.getElementById("dlgform") || {}).textContent || "")' 10
    Check 'split open: an 8px drag inside cell 9 opens the New Zone dialog for one cell (control)' $dlg 'no New Zone dialog after the drag'
    if (-not $dlg) { return }
    $before = [int](Js $ws 'return window.__h.posts("layout").length')
    Confirm-Ask $ws
    [void](WaitFor $ws ('window.__h.posts("layout").length > ' + $before) 10)
    $sent = Layout-Posts-After $ws $before
    $zs = Posted-Zones $sent
    Check 'split open: Add Zone sends one POST /layout with the zone on cell 9 alone (control)' ($sent.Count -eq 1 -and $zs -eq '9') "POST /layout count: $($sent.Count), zone slots: $zs"
  }

  Case 'split open: Split Cell from empty cell 9, in its inspector: both halves stay empty and read Open half, with no Fills last, and one POST /layout' {
    Put-Split (Split-Json 5 2 @(Split-Pin 0 @(0)) $null $null @() @{ apps = @('*') })
    $opened = Open-Page $ws $url 'focus' $oneWinSnap
    Check 'split open: the page opens on Focus with fill on (control)' $opened 'the page did not open on Focus in time'
    if (-not $opened) { return }
    $c = Cell-Click $ws 9
    Check 'split open: empty cell 9 is drawn and free of windows (scope)' ($null -ne $c -and $c.on) 'no empty cell 9 on the ultrawide'
    if ($null -eq $c -or -not $c.on) { return }
    [void](WaitFor $ws $headEmptyCond 10)
    $selected = (Js $ws $winhJs) -ceq 'Empty Space'
    Check 'split open: empty cell 9 is selected, the inspector reads Empty Space (scope)' $selected 'the inspector does not read Empty Space, so there is no empty cell to split'
    if (-not $selected) { return }
    $hasBtn = WaitFor $ws $splitInspHasJs 10
    Check 'split open: the Empty Space section has a Split Cell button (scope)' $hasBtn 'no Split Cell button in the inspector'
    if (-not $hasBtn) { return }
    [void](Js $ws $splitInspJs)
    $open = WaitFor $ws $splitMenuJs 10
    Check 'split open: Split Cell opens the split menu of the empty cell (scope)' $open 'no split menu after Split Cell'
    if (-not $open) { return }
    $before = [int](Js $ws 'return window.__h.posts("layout").length')
    $item = Js $ws (Empty-Item-Js 'Side by Side')
    Check 'split open: the empty cell menu has an enabled Side by Side item (scope)' ($item -eq $true) 'no enabled Side by Side item in the split menu'
    if ($item -ne $true) { return }
    [void](WaitFor $ws ('window.__h.posts("layout").length > ' + $before) 10)
    $sent = Layout-Posts-After $ws $before
    Check 'split open: the split of the empty cell sends one POST /layout' ($sent.Count -eq 1) "POST /layout count: $($sent.Count)"
    $lay = if ($sent.Count -eq 1) { (ConvertFrom-Json $sent[0].body).layout } else { $null }
    if (-not $lay) { return }
    Check 'split open: the split doubles the grid to 10 by 2 (mult 2,1)' ((Split-Axis $lay.grids.U1.mult) -eq '2,1') "mult: '$(Split-Axis $lay.grids.U1.mult)'"
    Check 'split open: the pin in cell 0 keeps its cell and takes both halves, slots 0 and 1 (every other pin doubles)' ((Split-SlotsOf $lay 'Refactor the grid solver') -eq '0,1') "its pin holds: $(Split-SlotsOf $lay 'Refactor the grid solver')"
    Check 'split open: no pin, zone or held entry holds the new half at slot 18' (-not (Split-HasSlot $lay 18)) 'a pin, zone or hold names slot 18'
    Check 'split open: no pin, zone or held entry holds the new half at slot 19' (-not (Split-HasSlot $lay 19)) 'a pin, zone or hold names slot 19'
    $halves = @(Wait-Halves $ws 'Open half' 2)
    $slots = ((@($halves | % { $_.slot }) | Sort-Object) -join ',')
    Check 'split open: both new halves, slots 18 and 19, are named Open half (scope)' ($slots -eq '18,19') "named halves: $(Half-Text $halves)"
    if ($slots -ne '18,19') { return }
    Check 'split open: neither half reads Fills last, since no window holds either (S12)' (@($halves | ? { $_.name -match 'Fills last' }).Count -eq 0) "names: $(Half-Text $halves)"
  }

  Case 'split open: a still click on an open half of a part-taken cell selects it: the Open Half section has Join Halves and Keep This Half Empty' {
    Put-Split (Split-Json 5 2 $halfSeed '2,1' '2,1')
    $opened = Open-Page $ws $url 'focus' $tenWinSnap
    Check 'split open: the page opens on Focus with one open half (control)' $opened 'the page did not open on Focus in time'
    if (-not $opened) { return }
    # Wait for the half's name before the press: until the preview lands, a tile can still sit on cell 1.
    $named = @(Wait-Halves $ws)
    Check 'split open: the open half is named on cell 1 before the press (scope)' (@($named | ? { $_.slot -eq 1 }).Count -eq 1) "named halves: $(Half-Text $named)"
    if (@($named | ? { $_.slot -eq 1 }).Count -ne 1) { return }
    $c = Cell-Click $ws 1
    Check 'split open: open half cell 1 is drawn and free of windows (scope)' ($null -ne $c -and $c.on) "cell 1 is not drawn, or the press hits: $($c.hit)"
    if ($null -eq $c -or -not $c.on) { return }
    [void](WaitFor $ws $headOpenCond 10)
    $head = Js $ws $winhJs
    Check 'split open: a still click on the open half selects it: the inspector heading reads Open Half' ([string]$head -match '(?i)open half') "the inspector heading reads: '$head'"
    Check 'split open: the Open Half section has a Join Halves button' ((Js $ws (Win-Control-Js 'Join Halves' '')) -eq $true) 'no Join Halves button in the Window section'
    Check 'split open: the Open Half section has a Keep This Half Empty control' ((Js $ws (Win-Control-Js 'Keep This Half Empty' '')) -eq $true) 'no Keep This Half Empty control in the Window section'
    $sent = Layout-Posts-After $ws $c.before
    Check 'split open: the still click sends no POST /layout (control)' ($sent.Count -eq 0) "POST /layout count: $($sent.Count), bodies: $(Post-Text $sent)"
  }

  Case 'split open: an open half of a part-taken cell is named Open half and Fills last with fill on' {
    Put-Split (Split-Json 5 2 $halfSeed '2,1' '2,1' @() @{ apps = @('*') })
    $opened = Open-Page $ws $url 'focus' $tenWinSnap
    Check 'split open: the page opens on Focus with fill on (control)' $opened 'the page did not open on Focus in time'
    if (-not $opened) { return }
    $probe = @(Ax-Named $ws 'Refactor the grid solver')
    Check 'split open: the accessibility tree names the window 1001 tile (reader control)' ($probe.Count -ge 1) 'the accessibility tree names no tile for window 1001: the reader does not see the board'
    $h = @(Wait-Halves $ws)
    Check 'split open: the board names one open half, on cell 1 (scope)' ($h.Count -eq 1 -and $h[0].slot -eq 1) "named halves: $(Half-Text $h)"
    if ($h.Count -ne 1 -or $h[0].slot -ne 1) { return }
    Check 'split open: the open half is named "Open half" and "Fills last" (fill on)' ($h[0].name -cmatch 'Open half' -and $h[0].name -match 'Fills last') "name: '$($h[0].name)'"
  }

  Case 'split open: an open half of a part-taken cell is named Stays empty and Fill is off with fill off' {
    Put-Split (Split-Json 5 2 $halfSeed '2,1' '2,1' @() @{ apps = @('*'); off = $true })
    $opened = Open-Page $ws $url 'focus' $tenWinSnap
    Check 'split open: the page opens on Focus with fill off (control)' $opened 'the page did not open on Focus in time'
    if (-not $opened) { return }
    $h = @(Wait-Halves $ws)
    Check 'split open: the board names one open half, on cell 1 (scope)' ($h.Count -eq 1 -and $h[0].slot -eq 1) "named halves: $(Half-Text $h)"
    if ($h.Count -ne 1 -or $h[0].slot -ne 1) { return }
    Check 'split open: the open half is named "Stays empty" and "Fill is off" (fill off)' ($h[0].name -cmatch 'Stays empty' -and $h[0].name -match 'Fill is off') "name: '$($h[0].name)'"
  }

  Case 'split open: at 1024 an open half under 40px draws no words, and its name still reads Open half and Fills last' {
    Put-Split (Split-Json 5 2 $halfSeed '2,1' '2,1' @() @{ apps = @('*') })
    Set-View $ws 1024 768
    try {
      $opened = Open-Page $ws $url 'focus' $tenWinSnap
      Check 'split open: the page opens on Focus with fill on, at 1024 (control)' $opened 'the page did not open on Focus in time'
      if (-not $opened) { return }
      $h = @(Wait-Halves $ws)
      Check 'split open: at 1024 the board names one open half, on cell 1 (scope)' ($h.Count -eq 1 -and $h[0].slot -eq 1) "named halves: $(Half-Text $h)"
      if ($h.Count -ne 1 -or $h[0].slot -ne 1) { return }
      Check 'split open: at 1024 the open half is under 40px wide (scope)' ($h[0].w -gt 0 -and $h[0].w -lt 40) "width: $($h[0].w)"
      # The no-words checks below are only about a half under 40px: on a wider half they do not run.
      if (-not ($h[0].w -gt 0 -and $h[0].w -lt 40)) { return }
      Check 'split open: under 40px the open half draws no words, the dashed box alone' ($h[0].words -eq '') "words drawn: '$($h[0].words)'"
      Check 'split open: under 40px the open half keeps its name, Open half and Fills last' ($h[0].name -cmatch 'Open half' -and $h[0].name -match 'Fills last') "name: '$($h[0].name)'"
    } finally { Reset-Look $ws }
  }

  Case 'split open: Keep This Half Empty sends one POST /layout with fill.keepEmpty on that half, and the half reads Kept empty' {
    Put-Split (Split-Json 5 2 $halfSeed '2,1' '2,1')
    $opened = Open-Page $ws $url 'focus' $tenWinSnap
    Check 'split open: the page opens on Focus with one open half (control)' $opened 'the page did not open on Focus in time'
    if (-not $opened) { return }
    # Wait for the half's name before the press (see the still-click case above).
    $named = @(Wait-Halves $ws)
    Check 'split open: the open half is named on cell 1 before the press (scope)' (@($named | ? { $_.slot -eq 1 }).Count -eq 1) "named halves: $(Half-Text $named)"
    if (@($named | ? { $_.slot -eq 1 }).Count -ne 1) { return }
    $c = Cell-Click $ws 1
    Check 'split open: open half cell 1 is drawn and free of windows (scope)' ($null -ne $c -and $c.on) "cell 1 is not drawn, or the press hits: $($c.hit)"
    if ($null -eq $c -or -not $c.on) { return }
    [void](WaitFor $ws $headOpenCond 10)
    $hasKeep = Js $ws (Win-Control-Js 'Keep This Half Empty' '')
    Check 'split open: the open half is selected, and its section has Keep This Half Empty (scope)' ($hasKeep -eq $true) 'no Keep This Half Empty control: the open half is not selected'
    if ($hasKeep -ne $true) { return }
    $before = [int](Js $ws 'return window.__h.posts("layout").length')
    [void](Js $ws (Win-Control-Js 'Keep This Half Empty' 'el.click()'))
    [void](WaitFor $ws ('window.__h.posts("layout").length > ' + $before) 10)
    $sent = Layout-Posts-After $ws $before
    Check 'split open: Keep This Half Empty sends one POST /layout' ($sent.Count -eq 1) "POST /layout count: $($sent.Count)"
    $lay = if ($sent.Count -eq 1) { (ConvertFrom-Json $sent[0].body).layout } else { $null }
    $ke = @(if ($lay) { @($lay.fill.keepEmpty) | ? { $_ } })
    Check 'split open: the POST carries fill.keepEmpty [{mon U1, slots [1]}] and no other entry' ($ke.Count -eq 1 -and [string]$ke[0].mon -ceq 'U1' -and ((Split-Ints $ke[0].slots) -join ',') -eq '1') "fill.keepEmpty: $(Kept-Text $ke)"
    $kept = @(Wait-Halves $ws 'Kept empty')
    Check 'split open: the half reads Kept empty, on slot 1' ($kept.Count -eq 1 -and $kept[0].slot -eq 1) "named halves: $(Half-Text $kept)"
  }

  Case 'split open: a second split remaps fill.keepEmpty like fill.held: the kept half at slot 1 goes to slots 1 and 11 after a stacked split' {
    Put-Split (Split-Json 5 2 $halfSeed '2,1' '2,1' @() @{ keepEmpty = @([pscustomobject]@{ mon = 'U1'; slots = @(1) }) })
    $opened = Open-Page $ws $url 'focus' $tenWinSnap
    Check 'split open: the page opens on Focus with one kept half (control)' $opened 'the page did not open on Focus in time'
    if (-not $opened) { return }
    Split-Route $ws 1001 'key' 'Stacked' 'Top' 'second split of the kept layout'; $r = $script:splitLast
    $sent = @($r.sent | ? { $_ })
    Check 'split open: the stacked split sends one POST /layout (scope)' ($sent.Count -eq 1) "POST /layout count: $($sent.Count)"
    if ($sent.Count -ne 1) { return }
    $lay = (ConvertFrom-Json $sent[0].body).layout
    Check 'split open: the stacked split makes the grid 10 by 4, mult 2,2 (scope)' ((Split-Axis $lay.grids.U1.mult) -eq '2,2') "mult: '$(Split-Axis $lay.grids.U1.mult)'"
    $ke = @(@($lay.fill.keepEmpty) | ? { $_ })
    Check 'split open: fill.keepEmpty holds the kept half at slots 1 and 11, its row doubled as fill.held is' ($ke.Count -eq 1 -and ((Split-Ints $ke[0].slots | Sort-Object) -join ',') -eq '1,11') "fill.keepEmpty: $(Kept-Text $ke)"
  }

  Case 'split open: Join Halves on a kept open half sends one POST /layout that drops its keepEmpty entry, and the grid halves back to 5 by 2' {
    Put-Split (Split-Json 5 2 @() '2,1' '2,1' @() @{ keepEmpty = @([pscustomobject]@{ mon = 'U1'; slots = @(1) }) })
    $opened = Open-Page $ws $url 'focus' $oneWinSnap
    Check 'split open: the page opens on Focus with an empty split and one kept half (control)' $opened 'the page did not open on Focus in time'
    if (-not $opened) { return }
    # Wait for the kept half's name before the press (see the still-click case above).
    $named = @(Wait-Halves $ws)
    Check 'split open: the kept half is named on cell 1 before the press (scope)' (@($named | ? { $_.slot -eq 1 }).Count -eq 1) "named halves: $(Half-Text $named)"
    if (@($named | ? { $_.slot -eq 1 }).Count -ne 1) { return }
    $c = Cell-Click $ws 1
    Check 'split open: the kept half at cell 1 is drawn and free of windows (scope)' ($null -ne $c -and $c.on) "cell 1 is not drawn, or the press hits: $($c.hit)"
    if ($null -eq $c -or -not $c.on) { return }
    [void](WaitFor $ws $headOpenCond 10)
    $hasJoin = Js $ws (Win-Control-Js 'Join Halves' '')
    Check 'split open: the kept half is selected, and its section has Join Halves (scope)' ($hasJoin -eq $true) 'no Join Halves button: the kept half is not selected'
    if ($hasJoin -ne $true) { return }
    $before = [int](Js $ws 'return window.__h.posts("layout").length')
    [void](Js $ws (Win-Control-Js 'Join Halves' 'el.click()'))
    [void](WaitFor $ws ('window.__h.posts("layout").length > ' + $before) 10)
    $sent = Layout-Posts-After $ws $before
    Check 'split open: Join Halves on the kept half sends one POST /layout' ($sent.Count -eq 1) "POST /layout count: $($sent.Count)"
    if ($sent.Count -ne 1) { return }
    $lay = (ConvertFrom-Json $sent[0].body).layout
    $ke = @(@($lay.fill.keepEmpty) | ? { $_ })
    Check 'split open: the join drops the keepEmpty entry on slot 1' ($ke.Count -eq 0) "fill.keepEmpty: $(Kept-Text $ke)"
    Check 'split open: the grid halves back, 5 by 2 (mult absent or 1,1)' ((Split-Axis $lay.grids.U1.mult) -eq '1,1') "mult: '$(Split-Axis $lay.grids.U1.mult)'"
  }

  Case 'split open: a kept half blocks halving: Join Halves on the window in the left half sends one POST /layout, and the grid stays 10 by 2' {
    Put-Split (Split-Json 5 2 $halfSeed '2,1' '2,1' @() @{ keepEmpty = @([pscustomobject]@{ mon = 'U1'; slots = @(1) }) })
    $opened = Open-Page $ws $url 'focus' $tenWinSnap
    Check 'split open: the page opens on Focus with one kept half (control)' $opened 'the page did not open on Focus in time'
    if (-not $opened) { return }
    $sel = Split-Select $ws 1001
    Check 'split open: window 1001, in the left half, is selected (scope)' $sel 'no tile 1001, or Enter did not select it'
    if (-not $sel) { return }
    $before = [int](Js $ws 'return window.__h.posts("layout").length')
    Press-Key $ws 'j' 74 'j'
    [void](WaitFor $ws ('window.__h.posts("layout").length > ' + $before) 10)
    $sent = Layout-Posts-After $ws $before
    Check 'split open: J on the left half sends one POST /layout (scope)' ($sent.Count -eq 1) "POST /layout count: $($sent.Count)"
    if ($sent.Count -ne 1) { return }
    $lay = (ConvertFrom-Json $sent[0].body).layout
    Check 'split open: the kept right half blocks halving, so the grid stays 10 by 2 (mult 2,1)' ((Split-Axis $lay.grids.U1.mult) -eq '2,1') "mult after J: '$(Split-Axis $lay.grids.U1.mult)'"
  }

  Case 'split open: Clear Board deletes fill.keepEmpty, and turns Fill Empty Cells off' {
    Put-Split (Split-Json 5 2 @(Split-Pin 0 @(0)) $null $null @() @{ apps = @('*'); keepEmpty = @([pscustomobject]@{ mon = 'U1'; slots = @(9) }) })
    $opened = Open-Page $ws $url 'focus'
    Check 'split open: the page opens on Focus with a kept cell (control)' $opened 'the page did not open on Focus in time'
    if (-not $opened) { return }
    $cb = Js $ws 'const b = document.getElementById("clearbd"); return !!b && !b.hidden && !b.disabled;'
    Check 'split open: Clear Board is shown and enabled, with unpinned windows to send (scope)' ($cb -eq $true) 'Clear Board is hidden or disabled'
    if ($cb -ne $true) { return }
    $before = [int](Js $ws 'return window.__h.posts("layout").length')
    [void](Js $ws 'document.getElementById("clearbd").click(); return true;')
    [void](WaitFor $ws ('window.__h.posts("layout").length > ' + $before) 10)
    $sent = Layout-Posts-After $ws $before
    Check 'split open: Clear Board sends one POST /layout (scope)' ($sent.Count -eq 1) "POST /layout count: $($sent.Count)"
    if ($sent.Count -ne 1) { return }
    $lay = (ConvertFrom-Json $sent[0].body).layout
    Check 'split open: Clear Board turns Fill Empty Cells off (control)' ($lay.fill.off -eq $true) 'fill.off is not true after Clear Board'
    $ke = @(@($lay.fill.keepEmpty) | ? { $_ })
    Check 'split open: Clear Board deletes fill.keepEmpty' ($ke.Count -eq 0) "fill.keepEmpty: $(Kept-Text $ke)"
  }

  Case 'split open: Fill Empty Cells off, then on again, keeps fill.keepEmpty (guard: green on main)' {
    Put-Split (Split-Json 5 2 @(Split-Pin 0 @(0)) $null $null @() @{ keepEmpty = @([pscustomobject]@{ mon = 'U1'; slots = @(9) }) })
    $opened = Open-Page $ws $url 'focus' $oneWinSnap
    Check 'split open: the page opens on Focus with a kept cell (control)' $opened 'the page did not open on Focus in time'
    if (-not $opened) { return }
    [void](Js $ws 'const i = snap.monitors.findIndex(q => q.role === "wide"); const b = document.querySelector("[role=group][aria-label=Monitor] button[data-mon=\"" + i + "\"]"); if (b) b.click(); return true;')
    $sw = Js $ws 'return !!document.getElementById("fillSw");'
    Check 'split open: the ultrawide shows its Fill Empty Cells switch (scope)' ($sw -eq $true) 'no Fill Empty Cells switch on the ultrawide'
    if ($sw -ne $true) { return }
    $before = [int](Js $ws 'return window.__h.posts("layout").length')
    [void](Js $ws 'document.getElementById("fillSw").click(); return true;')
    [void](WaitFor $ws ('window.__h.posts("layout").length > ' + $before) 10)
    $off = Layout-Posts-After $ws $before
    Check 'split open: Fill Empty Cells off sends one POST /layout (scope)' ($off.Count -eq 1) "POST /layout count: $($off.Count)"
    if ($off.Count -ne 1) { return }
    $lo = (ConvertFrom-Json $off[0].body).layout
    $keOff = @(@($lo.fill.keepEmpty) | ? { $_ })
    Check 'split open: Fill Empty Cells off keeps fill.keepEmpty on slot 9' ($lo.fill.off -eq $true -and $keOff.Count -eq 1 -and ((Split-Ints $keOff[0].slots) -join ',') -eq '9') "fill.off: $($lo.fill.off), fill.keepEmpty: $(Kept-Text $keOff)"
    $before2 = [int](Js $ws 'return window.__h.posts("layout").length')
    [void](Js $ws 'document.getElementById("fillSw").click(); return true;')
    [void](WaitFor $ws ('window.__h.posts("layout").length > ' + $before2) 10)
    $on = Layout-Posts-After $ws $before2
    Check 'split open: Fill Empty Cells on again sends one POST /layout (scope)' ($on.Count -eq 1) "POST /layout count: $($on.Count)"
    if ($on.Count -ne 1) { return }
    $lon = (ConvertFrom-Json $on[0].body).layout
    $keOn = @(@($lon.fill.keepEmpty) | ? { $_ })
    Check 'split open: Fill Empty Cells on again keeps fill.keepEmpty on slot 9' ($lon.fill.off -ne $true -and $keOn.Count -eq 1 -and ((Split-Ints $keOn[0].slots) -join ',') -eq '9') "fill.off: $($lon.fill.off), fill.keepEmpty: $(Kept-Text $keOn)"
  }

  Case 'split open: Tab reaches each empty cell after the windows, one stop per empty cell (S13)' {
    Put-Split (Split-Json 5 2 @(Split-Pin 0 @(0)))
    $opened = Open-Page $ws $url 'focus' $oneWinSnap
    Check 'split open: the page opens on Focus with window 1001 pinned (control)' $opened 'the page did not open on Focus in time'
    if (-not $opened) { return }
    $focused = Js $ws (Split-FocusJs 1001)
    Check 'split open: window 1001 takes keyboard focus, so Tab starts from the board (scope)' ($focused -eq $true) 'window 1001 does not take focus'
    if ($focused -ne $true) { return }
    # One lap of Tab stops: from window 1001 until focus comes back to it. Each stop is read as the element that holds focus.
    $descJs = 'const e = document.activeElement; if (!e) return null; return { inStage: !!e.closest("#stage"), tile: e.classList.contains("tile"), did: e.getAttribute("data-id") || "", name: ((e.getAttribute("aria-label") || e.textContent || "").replace(/\s+/g, " ").trim()).slice(0, 80), tag: e.tagName };'
    $start = Js $ws $descJs
    $startKey = "$($start.inStage)|$($start.did)|$($start.name)|$($start.tag)"
    $stops = @()
    for ($i = 0; $i -lt 200; $i++) {
      Press-Key $ws 'Tab' 9
      $f = Js $ws $descJs
      if ($null -eq $f) { break }
      if ("$($f.inStage)|$($f.did)|$($f.name)|$($f.tag)" -eq $startKey) { break }
      $stops += $f
    }
    $empty = @($stops | ? { $_.inStage -and -not $_.tile -and [string]$_.name -match 'Open half|Empty' })
    Check 'split open: Tab reaches each of the 9 empty cells, one stop each (S13)' ($empty.Count -eq 9) "stops on empty cells: $($empty.Count); stops in one lap: $($stops.Count); names: $((@($stops | % { $_.name }) | Select-Object -First 12) -join ' | ')"
  }

  Case 'split open: the open half the page names Fills last is the slot tile.ps1 fills last in a dry run (labels match the engine)' {
    $fillScene = ConvertTo-Json -Depth 12 -Compress -InputObject ([pscustomobject]@{ id = 'half'; name = 'Half'; grids = [pscustomobject]@{ U1 = [pscustomobject]@{ c = 5; r = 2; mult = @(2, 1) } }; pins = @($halfSeed); zones = @(); fill = [pscustomobject]@{ mon = 'U1'; apps = @('*'); skip = @(); sort = 'app'; unit = @(2, 1) } })
    # The same board with one more window, 1016, that no pin holds: the dry run places it, and it is the window that fills last.
    $engSnap = ConvertTo-Json -Depth 10 -Compress -InputObject ([pscustomobject]@{ monitors = @($snapObj.monitors); windows = @($snapObj.windows | ? { $splitWinIds -contains [int]$_.id -or [int]$_.id -eq 1016 }) })
    $se = Split-Engine $fillScene $engSnap
    $extra = @(@($se.placed) | ? { $_ -and [int64]$_.id -eq 1016 })
    Check 'split open: tile.ps1 places the extra window 1016 in a dry run (scope)' ($extra.Count -eq 1) "placed: $(@($se.placed).Count), 1016 placed: $($extra.Count)"
    if ($extra.Count -ne 1) { return }
    $engine = ((@(Split-Ints $extra[0].slots | % { $_ - 1 })) | Sort-Object) -join ','
    Check 'split open: tile.ps1 fills 1016 last, in the open half at slot 1 (control)' ($engine -eq '1') "engine fills slot(s) (0-based): '$engine'"
    Put-Split (Split-Json 5 2 $halfSeed '2,1' '2,1' @() @{ apps = @('*') })
    $opened = Open-Page $ws $url 'focus' $tenWinSnap
    Check 'split open: the page opens on Focus with the same layout (control)' $opened 'the page did not open on Focus in time'
    if (-not $opened) { return }
    $h = @(Wait-Halves $ws)
    $page = ((@($h | ? { $_.name -match 'Fills last' } | % { $_.slot })) | Sort-Object) -join ','
    Check 'split open: the page names Fills last on the open half the engine fills last (labels match tile.ps1)' ($page -ne '' -and $page -eq $engine) "page names Fills last on slot(s): '$page'; engine: '$engine'; named halves: $(Half-Text $h)"
  }

  # ---- Split Cell: a free half inside a zone reads Open half and Zone fills last, with fill on; an open half outside every zone reads Fills last ----
  # Cell 0 holds window 0 and the zone holds cells 0 and 1, so cell 1 is the zone's free half. The zone's app is POWERPNT, which no pin
  # holds, so the dry run's extra window 1016 (POWERPNT) is the one the zone takes. Cell 3 is an open half outside every zone (cell 2 is
  # window 1's), so it still reads Fills last.
  $zoneHalf = [pscustomobject]@{ mon = 'U1'; app = 'POWERPNT'; slots = @(0, 1) }
  $zoneHalfSeed = @(Split-Pin 0 @(0)) + @(Split-Pin 1 @(2)) + @(2..9 | % { Split-Pin $_ @((2 * $_), (2 * $_ + 1)) })
  $zoneHalfLayout = Split-Json 5 2 $zoneHalfSeed '2,1' '2,1' @($zoneHalf) @{ apps = @('*') }
  # A zone's whole free block: cells 18 and 19 hold no window, and cell 1 is an open half outside the zone. Nine windows, so the fill has none to place.
  $zoneWholeZone = [pscustomobject]@{ mon = 'U1'; app = 'POWERPNT'; slots = @(18, 19) }
  $zoneWholeSeed = @(Split-Pin 0 @(0)) + @(1..8 | % { Split-Pin $_ @((2 * $_), (2 * $_ + 1)) })
  $zoneWholeLayout = Split-Json 5 2 $zoneWholeSeed '2,1' '2,1' @($zoneWholeZone) @{ apps = @('*') }
  $nineWinSnap = ConvertTo-Json -Depth 10 -Compress -InputObject ([pscustomobject]@{ monitors = @($snapObj.monitors); windows = @($snapObj.windows | ? { $splitWinIds[0..8] -contains [int]$_.id }) })
  # The board with one more window, 1016, that no pin holds: a dry run places it through a zone (zone index 0), not the fill.
  $zoneEngSnap = ConvertTo-Json -Depth 10 -Compress -InputObject ([pscustomobject]@{ monitors = @($snapObj.monitors); windows = @($snapObj.windows | ? { $splitWinIds -contains [int]$_.id -or [int]$_.id -eq 1016 }) })
  # F1: a zone on P1, which is not the fill monitor (U1 fills). P1's first cell is halved, window 1001 holds slot 0, so slot 1 is the zone's free half.
  $zoneP1 = [pscustomobject]@{ mon = 'P1'; app = 'POWERPNT'; slots = @(0, 1) }
  $p1Layout = Split-Json 5 2 @(Split-Pin 0 @(0) $false $null 'P1') $null $null @($zoneP1) @{ apps = @('*') } @{ P1 = [ordered]@{ c = 5; r = 2; mult = @(2, 1) } }
  $p1Scene = ConvertTo-Json -Depth 12 -Compress -InputObject ([pscustomobject]@{ id = 'zonep1'; name = 'Zone on P1'; grids = [pscustomobject]@{ U1 = [pscustomobject]@{ c = 5; r = 2 }; P1 = [pscustomobject]@{ c = 5; r = 2; mult = @(2, 1) } }; pins = @(Split-Pin 0 @(0) $false $null 'P1'); zones = @($zoneP1); fill = [pscustomobject]@{ mon = 'U1'; apps = @('*'); skip = @(); sort = 'app' } })
  # F3: a [1,2] unit (a vertical split). U1's first cell is halved top and bottom; window 1001 holds the top, so slot 5 (the bottom) is the zone's free half.
  $zoneV = [pscustomobject]@{ mon = 'U1'; app = 'POWERPNT'; slots = @(0, 5) }
  $zoneVSeed = @(Split-Pin 0 @(0))
  $zoneVLayout = Split-Json 5 1 $zoneVSeed '1,2' '1,2' @($zoneV) @{ apps = @('*') }
  $zoneVScene = ConvertTo-Json -Depth 12 -Compress -InputObject ([pscustomobject]@{ id = 'zonev'; name = 'Zone vertical'; grids = [pscustomobject]@{ U1 = [pscustomobject]@{ c = 5; r = 1; mult = @(1, 2) } }; pins = @($zoneVSeed); zones = @($zoneV); fill = [pscustomobject]@{ mon = 'U1'; apps = @('*'); skip = @(); sort = 'app'; unit = @(1, 2) } })
  # F4: the small line under the Keep This Half Empty switch in the Window section, read from the page (null when not drawn).
  $keepLineJs = 'const w = document.getElementById("win"); if (!w) return null; const l = [...w.querySelectorAll("label.switch")].find(x => x.textContent.includes("Keep This Half Empty")); const s = l ? l.querySelector("small") : null; return s ? s.textContent.trim() : null;'

  # ---- Kept half: why a window waits (debt kept-half-wait-reason; decision fill-controls) ------------------------------------------------
  # The halfSeed board plus window 1016, which no pin holds, with Keep This Half Empty on the open half (slot 1, 1-based slot 2): the fill
  # never uses the half, so 1016 waits in Windows That Stay Put. The engine hands back why 'no free cell' for it and BAYWHY words that
  # "No room: add a column", though no column is missing. The reason is read from the chip's accessible name: the text between the window's
  # title and ". Stays put.". Builder interface: a kept-half reason that holds the words "keep" or "kept", and "half" (the mockup's fill-keep
  # state, split-cell.html, draws the waiting chip with the engine's "No free cell" and names no kept-half reason, so the debt's own words rule).
  $keptWhyJs = 'const e = document.querySelector("[data-bay=\"1016\"]"); if (!e) return null; const l = e.getAttribute("aria-label") || ""; const t = (snap.windows.find(w => w.id === 1016) || {}).title || ""; const i = l.indexOf(t + ". "), j = l.indexOf(". Stays put."); return i >= 0 && j > i ? l.slice(i + t.length + 2, j) : l;'
  $keptChipCond = '!!document.querySelector("[data-bay=\"1016\"]")'
  $keptChipJs = 'return ' + $keptChipCond + ';'
  $keptPlacedJs = 'const p = ((prevs[selId] || {}).placed || []).find(x => x.id === 1016); return p ? (p.slots || []) : null;'
  $keptOnHalfJs = 'return ((prevs[selId] || {}).placed || []).filter(x => (x.slots || []).includes(2)).map(x => x.id);'
  $keptSceneJs = 'const k = ((scene() || {}).fill || {}).keepEmpty || []; return k.map(x => x.mon + ":" + (x.slots || []).join(",")).join(";");'
  $fullSeed = @(Split-Pin 0 @(0, 1)) + @(1..9 | % { Split-Pin $_ @((2 * $_), (2 * $_ + 1)) })

  Case 'kept half wait reason: a window the fill leaves waiting only because a half is kept empty reads a reason that names the kept half, not No room' {
    Put-Split (Split-Json 5 2 $halfSeed '2,1' '2,1' @() @{ apps = @('*'); keepEmpty = @([pscustomobject]@{ mon = 'U1'; slots = @(1) }) })
    $opened = Open-Page $ws $url 'focus' $zoneEngSnap
    Check 'kept half wait reason: the page opens on Focus with one kept half and fill on (control)' $opened 'the page did not open on Focus in time'
    if (-not $opened) { return }
    $waits = WaitFor $ws $keptChipCond 10
    Check 'kept half wait reason: window 1016 waits in Windows That Stay Put (scope)' $waits 'no entry for window 1016 in Windows That Stay Put'
    if (-not $waits) { return }
    $keptScene = [string](Js $ws $keptSceneJs)
    Check 'kept half wait reason: the scene keeps slot 1 of U1 empty (scope)' ($keptScene -ceq 'U1:1') "fill.keepEmpty: '$keptScene'"
    $onHalf = @(Split-Ints (Js $ws $keptOnHalfJs))
    Check 'kept half wait reason: no window is placed on the kept half, slot 2 (scope)' ($onHalf.Count -eq 0) "windows on slot 2: $($onHalf -join ', ')"
    if ($keptScene -cne 'U1:1' -or $onHalf.Count -ne 0) { return }
    $why = [string](Js $ws $keptWhyJs)
    Check 'kept half wait reason: the reason does not read No room, since no column is missing' ($why -notlike '*No room*') "reason read: '$why'"
    Check 'kept half wait reason: the reason names the kept half (the words keep or kept, and half)' (($why -match '(?i)\b(keep|kept)\b') -and ($why -match '(?i)\bhalf\b')) "reason read: '$why'"
  }

  Case 'kept half wait reason: control: with no kept half the open half takes window 1016, and on a full board its reason is still No room: add a column' {
    Put-Split (Split-Json 5 2 $halfSeed '2,1' '2,1' @() @{ apps = @('*') })
    $opened = Open-Page $ws $url 'focus' $zoneEngSnap
    Check 'kept half wait reason: the page opens on Focus with the open half not kept (control)' $opened 'the page did not open on Focus in time'
    if (-not $opened) { return }
    $took = WaitFor $ws '((prevs[selId] || {}).placed || []).some(x => x.id === 1016)' 10
    Check 'kept half wait reason: with no kept half the fill places window 1016 (scope)' $took 'window 1016 is not placed: the board has no cell for it'
    if (-not $took) { return }
    $slots = (Split-Ints (Js $ws $keptPlacedJs)) -join ','
    Check 'kept half wait reason: with no kept half window 1016 takes the open half, slot 2 (control)' ($slots -eq '2') "window 1016 slots: '$slots'"
    Check 'kept half wait reason: with no kept half window 1016 is not in Windows That Stay Put (control)' ((Js $ws $keptChipJs) -eq $false) 'window 1016 has an entry in Windows That Stay Put'
    Put-Split (Split-Json 5 2 $fullSeed '2,1' '2,1' @() @{ apps = @('*') })
    $opened = Open-Page $ws $url 'focus' $zoneEngSnap
    Check 'kept half wait reason: the page opens on Focus with a full board (control)' $opened 'the page did not open on Focus in time'
    if (-not $opened) { return }
    $waits = WaitFor $ws $keptChipCond 10
    Check 'kept half wait reason: on a full board window 1016 waits in Windows That Stay Put (scope)' $waits 'no entry for window 1016 in Windows That Stay Put'
    if (-not $waits) { return }
    $why = [string](Js $ws $keptWhyJs)
    Check 'kept half wait reason: on a full board the reason still reads No room: add a column (control)' ($why -like '*No room*') "reason read: '$why'"
  }

  Case 'split open: a free half inside a zone is named Open half and Zone fills last, with fill on' {
    Put-Split $zoneHalfLayout
    $opened = Open-Page $ws $url 'focus' $tenWinSnap
    Check 'split open: the page opens on Focus with a zone on a free half, fill on (control)' $opened 'the page did not open on Focus in time'
    if (-not $opened) { return }
    $named = @(Wait-Halves $ws '(?i)empty|open half' 2)
    $z = @($named | ? { $_.slot -eq 1 })
    Check 'split open: the zone half, cell 2 (slot 1), is named on the board (scope)' ($z.Count -eq 1) "named halves: $(Half-Text $named)"
    if ($z.Count -ne 1) { return }
    Check 'split open: the zone half is named "Open half" and "Zone fills last", not as a whole empty cell' ($z[0].name -cmatch 'Open half' -and $z[0].name -match 'Zone fills last') "name: '$($z[0].name)'"
  }

  Case 'split open: an open half outside the zone, on the same board, is named Open half and Fills last, not Zone fills last (control)' {
    Put-Split $zoneHalfLayout
    $opened = Open-Page $ws $url 'focus' $tenWinSnap
    Check 'split open: the page opens on Focus with a zone beside an open half, fill on (control)' $opened 'the page did not open on Focus in time'
    if (-not $opened) { return }
    $named = @(Wait-Halves $ws '(?i)empty|open half' 2)
    $out = @($named | ? { $_.slot -eq 3 })
    Check 'split open: the open half outside the zone, cell 4 (slot 3), is named on the board (scope)' ($out.Count -eq 1) "named halves: $(Half-Text $named)"
    if ($out.Count -ne 1) { return }
    Check 'split open: the open half outside any zone is named "Open half" and "Fills last", not "Zone fills last" (control)' ($out[0].name -cmatch 'Open half' -and $out[0].name -match 'Fills last' -and $out[0].name -notmatch 'zone fills last') "name: '$($out[0].name)'"
  }

  Case 'split open: the zone half the page names Zone fills last is the slot tile.ps1 gives the zone window in a dry run (labels match the engine)' {
    $zoneScene = ConvertTo-Json -Depth 12 -Compress -InputObject ([pscustomobject]@{ id = 'zonehalf'; name = 'Zone half'; grids = [pscustomobject]@{ U1 = [pscustomobject]@{ c = 5; r = 2; mult = @(2, 1) } }; pins = @($zoneHalfSeed); zones = @($zoneHalf); fill = [pscustomobject]@{ mon = 'U1'; apps = @('*'); skip = @(); sort = 'app'; unit = @(2, 1) } })
    # The same board with one more window, 1016, that no pin holds: the dry run places it through the zone (zone index 0), not the fill.
    $se = Split-Engine $zoneScene $zoneEngSnap
    $extra = @(@($se.placed) | ? { $_ -and [int64]$_.id -eq 1016 })
    Check 'split open: tile.ps1 places the extra window 1016 in a dry run (scope)' ($extra.Count -eq 1) "placed: $(@($se.placed).Count), 1016 placed: $($extra.Count)"
    if ($extra.Count -ne 1) { return }
    Check 'split open: tile.ps1 places 1016 through the zone, zone index 0 (scope)' ([int]$extra[0].zone -eq 0) "zone index: $($extra[0].zone)"
    if ([int]$extra[0].zone -ne 0) { return }
    $engine = ((@(Split-Ints $extra[0].slots | % { $_ - 1 })) | Sort-Object) -join ','
    Check 'split open: tile.ps1 gives the zone window cell 2 (slot 1), the zone half (control)' ($engine -eq '1') "engine slot(s) (0-based): '$engine'"
    Put-Split $zoneHalfLayout
    $opened = Open-Page $ws $url 'focus' $tenWinSnap
    Check 'split open: the page opens on Focus with the same layout (control)' $opened 'the page did not open on Focus in time'
    if (-not $opened) { return }
    $h = @(Wait-Halves $ws '(?i)empty|open half' 2)
    $page = ((@($h | ? { $_.name -match 'Zone fills last' } | % { $_.slot })) | Sort-Object) -join ','
    Check 'split open: the page names Zone fills last on the slot tile.ps1 gives the zone window (labels match the engine)' ($page -ne '' -and $page -eq $engine) "page names Zone fills last on slot(s): '$page'; engine: '$engine'; named halves: $(Half-Text $h)"
  }

  Case 'split open: at 1024 a zone half under 40px draws no words, and its name still reads Open half and Zone fills last' {
    Put-Split $zoneHalfLayout
    Set-View $ws 1024 768
    try {
      $opened = Open-Page $ws $url 'focus' $tenWinSnap
      Check 'split open: the page opens on Focus with the zone half, at 1024 (control)' $opened 'the page did not open on Focus in time'
      if (-not $opened) { return }
      $named = @(Wait-Halves $ws '(?i)empty|open half' 2)
      $z = @($named | ? { $_.slot -eq 1 })
      Check 'split open: at 1024 the zone half, cell 2 (slot 1), is named on the board (scope)' ($z.Count -eq 1) "named halves: $(Half-Text $named)"
      if ($z.Count -ne 1) { return }
      Check 'split open: at 1024 the zone half is under 40px wide (scope)' ($z[0].w -gt 0 -and $z[0].w -lt 40) "width: $($z[0].w)"
      if (-not ($z[0].w -gt 0 -and $z[0].w -lt 40)) { return }
      Check 'split open: under 40px the zone half draws no words, the dashed box alone' ($z[0].words -eq '') "words drawn: '$($z[0].words)'"
      Check 'split open: under 40px the zone half keeps its name, Open half and Zone fills last' ($z[0].name -cmatch 'Open half' -and $z[0].name -match 'Zone fills last') "name: '$($z[0].name)'"
    } finally { Reset-Look $ws }
  }

  Case 'split open: a zone whose free block holds no open half names its cells as today, with no Open half label (control)' {
    Put-Split $zoneWholeLayout
    $opened = Open-Page $ws $url 'focus' $nineWinSnap
    Check 'split open: the page opens on Focus with a zone on a whole free block (control)' $opened 'the page did not open on Focus in time'
    if (-not $opened) { return }
    $named = @(Wait-Halves $ws '(?i)empty|open half' 3)
    $block = @($named | ? { $_.slot -eq 18 -or $_.slot -eq 19 })
    Check 'split open: the zone whole block, slots 18 and 19, is named on the board (scope)' ($block.Count -eq 2) "named: $(Half-Text $named)"
    if ($block.Count -ne 2) { return }
    Check 'split open: the zone whole block reads as empty cells, with no Open half or Zone fills last (control)' (@($block | ? { $_.name -match 'empty' -and $_.name -notmatch 'Open half|zone fills last' }).Count -eq 2) "names: $(Half-Text $block)"
  }

  # F1 (PR 74 review): a zone on a monitor that is not the fill monitor. tile.ps1 gives that monitor no unit, so the zone fills its free cell as a
  # whole cell, first, and the page must not name that cell Zone fills last. The control is the same zone on U1, the fill monitor.
  Case 'split open: a zone on a monitor that is not the fill monitor names no half Zone fills last, and the cell tile.ps1 fills first is not labelled so' {
    Put-Split $p1Layout
    $opened = Open-Page $ws $url 'focus' $tenWinSnap
    Check 'split open: the page opens on Focus with a zone on P1, which is not the fill monitor (control)' $opened 'the page did not open on Focus in time'
    if (-not $opened) { return }
    $p1 = @(Wait-Halves $ws '(?i)empty|open half|zone fills last' 2 10 'tall')
    $cell = @($p1 | ? { $_.slot -eq 1 })
    Check 'split open: the P1 zone cell, slot 1, is named on the P1 board (scope)' ($cell.Count -eq 1) "named on P1: $(Half-Text $p1)"
    if ($cell.Count -ne 1) { return }
    $zl = @($p1 | ? { $_.name -match 'Zone fills last' })
    Check 'split open: no half on P1 is named Zone fills last, since P1 is not the fill monitor' ($zl.Count -eq 0) "named Zone fills last on P1: $(Half-Text $zl)"
    $se = Split-Engine $p1Scene $zoneEngSnap
    $extra = @(@($se.placed) | ? { $_ -and [int64]$_.id -eq 1016 })
    Check 'split open: tile.ps1 places the extra window 1016 in a dry run (scope)' ($extra.Count -eq 1) "placed: $(@($se.placed).Count), 1016 placed: $($extra.Count)"
    if ($extra.Count -ne 1) { return }
    Check 'split open: tile.ps1 places 1016 through the P1 zone, zone index 0 (scope)' ([int]$extra[0].zone -eq 0) "zone index: $($extra[0].zone)"
    if ([int]$extra[0].zone -ne 0) { return }
    $engine = ((@(Split-Ints $extra[0].slots | % { $_ - 1 })) | Sort-Object) -join ','
    $page = ((@($p1 | ? { $_.slot -in @($zoneP1.slots) -and $_.name -notmatch 'Zone fills last' } | % { $_.slot })) | Sort-Object) -join ','
    Check 'split open: the cell tile.ps1 fills first in the P1 zone is the one the page leaves without Zone fills last (engine vs page)' ($engine -ne '' -and $page -eq $engine) "engine fills first (0-based slot): '$engine'; page leaves unlabelled: '$page'; named on P1: $(Half-Text $p1)"
    Put-Split $zoneHalfLayout
    $opened = Open-Page $ws $url 'focus' $tenWinSnap
    Check 'split open: the page opens on Focus with the same zone on U1, the fill monitor (control)' $opened 'the page did not open on Focus in time'
    if (-not $opened) { return }
    $u1 = @(Wait-Halves $ws '(?i)empty|open half' 2)
    Check 'split open: the same zone on U1 still names its free half, slot 1, Zone fills last (control)' (@($u1 | ? { $_.slot -eq 1 -and $_.name -match 'Zone fills last' }).Count -eq 1) "named halves: $(Half-Text $u1)"
  }

  # F2 and F4 (PR 74 review): a zone half keeps its cell, so its inspector offers Keep This Half Empty and no Join Halves, and its Keep line
  # reads No window goes here (the zone and the fill both skip a kept half). The controls are an open half outside the zone, which still
  # offers Join Halves and keeps its own Keep line.
  Case 'split open: a zone half offers Keep This Half Empty and no Join Halves, and its Keep line reads No window goes here (controls: an open half outside the zone keeps Join Halves)' {
    Put-Split $zoneHalfLayout
    $opened = Open-Page $ws $url 'focus' $tenWinSnap
    Check 'split open: the page opens on Focus with a zone half and an open half (control)' $opened 'the page did not open on Focus in time'
    if (-not $opened) { return }
    $named = @(Wait-Halves $ws '(?i)empty|open half' 2)
    Check 'split open: the zone half is named on cell 2 before the press (scope)' (@($named | ? { $_.slot -eq 1 }).Count -eq 1) "named halves: $(Half-Text $named)"
    if (@($named | ? { $_.slot -eq 1 }).Count -ne 1) { return }
    $c = Cell-Click $ws 1
    Check 'split open: zone half cell 2 is drawn and free of windows (scope)' ($null -ne $c -and $c.on) "cell 2 is not drawn, or the press hits: $($c.hit)"
    if ($null -eq $c -or -not $c.on) { return }
    [void](WaitFor $ws $headOpenCond 10)
    Check 'split open: the selected zone half has a Keep This Half Empty control (scope)' ((Js $ws (Win-Control-Js 'Keep This Half Empty' '')) -eq $true) 'no Keep This Half Empty control on the selected zone half'
    Check 'split open: the zone half has no Join Halves button, since the zone keeps the half' ((Js $ws (Win-Control-Js 'Join Halves' '')) -eq $false) 'a Join Halves button on the zone half'
    $zoneKeep = Js $ws $keepLineJs
    Check 'split open: the Keep line on the zone half reads "No window goes here."' ([string]$zoneKeep -ceq 'No window goes here.') "Keep line: '$zoneKeep'"
    $o = Cell-Click $ws 3
    Check 'split open: the open half outside the zone, cell 4, is drawn and free of windows (scope)' ($null -ne $o -and $o.on) "cell 4 is not drawn, or the press hits: $($o.hit)"
    if ($null -eq $o -or -not $o.on) { return }
    [void](WaitFor $ws $headOpenCond 10)
    Check 'split open: the open half outside any zone still has a Join Halves button (control)' ((Js $ws (Win-Control-Js 'Join Halves' '')) -eq $true) 'no Join Halves button on the open half outside the zone'
    $openKeep = Js $ws $keepLineJs
    Check 'split open: the open half outside any zone keeps its Keep line, "The fill never puts a window here." (control)' ([string]$openKeep -ceq 'The fill never puts a window here.') "Keep line: '$openKeep'"
  }

  # F3 (PR 74 review): the zone half rule on a [1,2] unit, a vertical split. The bottom half of U1's first cell is the zone's free half.
  Case 'split open: a zone half on a vertical split (unit 1 by 2) is named Open half and Zone fills last, and it is the slot tile.ps1 gives the zone window' {
    Put-Split $zoneVLayout
    $opened = Open-Page $ws $url 'focus' $tenWinSnap
    Check 'split open: the page opens on Focus with a vertical zone half (control)' $opened 'the page did not open on Focus in time'
    if (-not $opened) { return }
    $h = @(Wait-Halves $ws '(?i)empty|open half' 1)
    $z = @($h | ? { $_.slot -eq 5 })
    Check 'split open: the vertical zone half, cell 6 (slot 5), is named on the board (scope)' ($z.Count -eq 1) "named halves: $(Half-Text $h)"
    if ($z.Count -ne 1) { return }
    Check 'split open: the vertical zone half is named "Open half" and "Zone fills last"' ($z[0].name -cmatch 'Open half' -and $z[0].name -match 'Zone fills last') "name: '$($z[0].name)'"
    $se = Split-Engine $zoneVScene $zoneEngSnap
    $extra = @(@($se.placed) | ? { $_ -and [int64]$_.id -eq 1016 })
    Check 'split open: tile.ps1 places the extra window 1016 in a dry run (scope)' ($extra.Count -eq 1) "placed: $(@($se.placed).Count), 1016 placed: $($extra.Count)"
    if ($extra.Count -ne 1) { return }
    Check 'split open: tile.ps1 places 1016 through the zone, zone index 0 (scope)' ([int]$extra[0].zone -eq 0) "zone index: $($extra[0].zone)"
    if ([int]$extra[0].zone -ne 0) { return }
    $engine = ((@(Split-Ints $extra[0].slots | % { $_ - 1 })) | Sort-Object) -join ','
    $page = ((@($h | ? { $_.name -match 'Zone fills last' } | % { $_.slot })) | Sort-Object) -join ','
    Check 'split open: the page names Zone fills last on the slot tile.ps1 gives the vertical zone window (labels match the engine)' ($page -ne '' -and $page -eq $engine) "page names Zone fills last on slot(s): '$page'; engine: '$engine'; named halves: $(Half-Text $h)"
  }

  # A zone half keeps its cell, so J on it joins nothing: the keyboard path must match the inspector, which offers no Join Halves there.
  # Nothing is sent, no "Joined cell N." status is set, and both halves stay. The control is the next case.
  Case 'split open: J on a focused zone half joins nothing: no POST /layout, no "Joined cell N." status, and both halves stay' {
    Put-Split $zoneHalfLayout
    $opened = Open-Page $ws $url 'focus' $tenWinSnap
    Check 'split open: the page opens on Focus with a zone half and an open half (control)' $opened 'the page did not open on Focus in time'
    if (-not $opened) { return }
    $named = @(Wait-Halves $ws '(?i)empty|open half' 2)
    Check 'split open: the zone half is named on cell 2 before the press (scope)' (@($named | ? { $_.slot -eq 1 }).Count -eq 1) "named halves: $(Half-Text $named)"
    if (@($named | ? { $_.slot -eq 1 }).Count -ne 1) { return }
    $c = Cell-Click $ws 1
    Check 'split open: zone half cell 2 is drawn and free of windows (scope)' ($null -ne $c -and $c.on) "cell 2 is not drawn, or the press hits: $($c.hit)"
    if ($null -eq $c -or -not $c.on) { return }
    [void](WaitFor $ws $headOpenCond 10)
    $focused = Js $ws 'const e = document.activeElement; return !!e && e.classList.contains("cellbox") && Number(e.dataset.slot) === 1;'
    Check 'split open: the selected zone half holds keyboard focus, so J reaches it (scope)' ($focused -eq $true) 'focus is not on the zone half'
    if ($focused -ne $true) { return }
    Press-Key $ws 'j' 74 'j'
    $sent = Layout-Posts-After $ws $c.before
    Check 'split open: J on the zone half sends no POST /layout' ($sent.Count -eq 0) "POST /layout count: $($sent.Count), bodies: $(Post-Text $sent)"
    $said = [string](Js $ws 'return document.getElementById("msg").textContent;')
    Check 'split open: J on the zone half does not report "Joined cell N." (status: see detail)' ($said -notmatch '^Joined cell \d+\.') "status: '$said'"
    # tile.ps1 numbers slots from 1 (its -Json slots are $_ + 1), and the page's placed list uses the same numbers. Window 1001 on its own half, cell 1, reads 1.
    $held = Js $ws 'const q = prev() && prev().placed.find(x => x.id === 1001 && !x.behind); return q ? q.slots : null'
    Check 'split open: window 1001 still holds its own half, slot 1 in the 1-based numbering (both halves stay)' (((Split-Ints $held) -join ',') -eq '1') "window 1001 holds slot(s) (1-based): '$((Split-Ints $held) -join ',')'"
    $halves = @(Ax-Named $ws '(?i)empty|open half')
    $stays = @($halves | ? { $_.slot -eq 1 -and $_.name -match 'Zone fills last' })
    Check 'split open: the zone half still reads "Zone fills last" on slot 1 (both halves stay)' ($stays.Count -eq 1) "named halves: $(Half-Text $halves)"
  }

  # The control for the case above: J on an open half outside the zone (cell 4) still joins, with one POST /layout and the joined status.
  Case 'split open: J on an open half outside the zone still joins (control): one POST /layout, and the status reads "Joined cell N."' {
    Put-Split $zoneHalfLayout
    $opened = Open-Page $ws $url 'focus' $tenWinSnap
    Check 'split open: the page opens on Focus with a zone half and an open half (control)' $opened 'the page did not open on Focus in time'
    if (-not $opened) { return }
    $named = @(Wait-Halves $ws '(?i)empty|open half' 2)
    Check 'split open: the open half outside the zone is named on cell 4 before the press (scope)' (@($named | ? { $_.slot -eq 3 }).Count -eq 1) "named halves: $(Half-Text $named)"
    if (@($named | ? { $_.slot -eq 3 }).Count -ne 1) { return }
    $c = Cell-Click $ws 3
    Check 'split open: open half cell 4 is drawn and free of windows (scope)' ($null -ne $c -and $c.on) "cell 4 is not drawn, or the press hits: $($c.hit)"
    if ($null -eq $c -or -not $c.on) { return }
    [void](WaitFor $ws $headOpenCond 10)
    Press-Key $ws 'j' 74 'j'
    [void](WaitFor $ws ('window.__h.posts("layout").length > ' + $c.before) 10)
    $sent = Layout-Posts-After $ws $c.before
    Check 'split open: J on the open half outside the zone sends one POST /layout (control)' ($sent.Count -eq 1) "POST /layout count: $($sent.Count), bodies: $(Post-Text $sent)"
    $said = [string](Js $ws 'return document.getElementById("msg").textContent;')
    Check 'split open: J on the open half outside the zone reports "Joined cell N." (control)' ($said -match '^Joined cell \d+\.') "status: '$said'"
  }

  # A kept zone half stays a zone half in the inspector: after Keep This Half Empty it offers no Join Halves, and its Keep line still reads
  # "No window goes here." (the zone keeps the half either way).
  Case 'split open: after Keep This Half Empty on a zone half, the inspector offers no Join Halves and its Keep line still reads "No window goes here."' {
    Put-Split $zoneHalfLayout
    $opened = Open-Page $ws $url 'focus' $tenWinSnap
    Check 'split open: the page opens on Focus with a zone half and an open half (control)' $opened 'the page did not open on Focus in time'
    if (-not $opened) { return }
    $named = @(Wait-Halves $ws '(?i)empty|open half' 2)
    Check 'split open: the zone half is named on cell 2 before the press (scope)' (@($named | ? { $_.slot -eq 1 }).Count -eq 1) "named halves: $(Half-Text $named)"
    if (@($named | ? { $_.slot -eq 1 }).Count -ne 1) { return }
    $c = Cell-Click $ws 1
    Check 'split open: zone half cell 2 is drawn and free of windows (scope)' ($null -ne $c -and $c.on) "cell 2 is not drawn, or the press hits: $($c.hit)"
    if ($null -eq $c -or -not $c.on) { return }
    [void](WaitFor $ws $headOpenCond 10)
    $hasKeep = Js $ws (Win-Control-Js 'Keep This Half Empty' '')
    Check 'split open: the selected zone half has a Keep This Half Empty control (scope)' ($hasKeep -eq $true) 'no Keep This Half Empty control on the selected zone half'
    if ($hasKeep -ne $true) { return }
    [void](Js $ws (Win-Control-Js 'Keep This Half Empty' 'el.click()'))
    $sent = Layout-Posts-After $ws $c.before
    Check 'split open: Keep This Half Empty on the zone half sends one POST /layout (scope)' ($sent.Count -eq 1) "POST /layout count: $($sent.Count), bodies: $(Post-Text $sent)"
    if ($sent.Count -ne 1) { return }
    [void](Js $ws $splitFrameJs)
    $keepStill = Js $ws (Win-Control-Js 'Keep This Half Empty' '')
    Check 'split open: the Keep This Half Empty control is still in the inspector after the keep (scope)' ($keepStill -eq $true) 'no Keep This Half Empty control after the keep'
    Check 'split open: after the keep, the inspector offers no Join Halves on the zone half' ((Js $ws (Win-Control-Js 'Join Halves' '')) -eq $false) 'a Join Halves button after Keep This Half Empty on the zone half'
    $keepLine = Js $ws $keepLineJs
    Check 'split open: after the keep, the Keep line on the zone half still reads "No window goes here."' ([string]$keepLine -ceq 'No window goes here.') "Keep line: '$keepLine'"
  }

  # The control for the case above: after Keep This Half Empty on an open half outside the zone, the inspector offers Join Halves and keeps
  # its fill line, so the zone case's state is the one a zone half alone takes.
  Case 'split open: after Keep This Half Empty on an open half outside the zone, the inspector offers Join Halves and its fill line (control)' {
    Put-Split $zoneHalfLayout
    $opened = Open-Page $ws $url 'focus' $tenWinSnap
    Check 'split open: the page opens on Focus with a zone half and an open half (control)' $opened 'the page did not open on Focus in time'
    if (-not $opened) { return }
    $named = @(Wait-Halves $ws '(?i)empty|open half' 2)
    Check 'split open: the open half outside the zone is named on cell 4 before the press (scope)' (@($named | ? { $_.slot -eq 3 }).Count -eq 1) "named halves: $(Half-Text $named)"
    if (@($named | ? { $_.slot -eq 3 }).Count -ne 1) { return }
    $c = Cell-Click $ws 3
    Check 'split open: open half cell 4 is drawn and free of windows (scope)' ($null -ne $c -and $c.on) "cell 4 is not drawn, or the press hits: $($c.hit)"
    if ($null -eq $c -or -not $c.on) { return }
    [void](WaitFor $ws $headOpenCond 10)
    $hasKeep = Js $ws (Win-Control-Js 'Keep This Half Empty' '')
    Check 'split open: the open half outside the zone has a Keep This Half Empty control (scope)' ($hasKeep -eq $true) 'no Keep This Half Empty control on the open half'
    if ($hasKeep -ne $true) { return }
    [void](Js $ws (Win-Control-Js 'Keep This Half Empty' 'el.click()'))
    $sent = Layout-Posts-After $ws $c.before
    Check 'split open: Keep This Half Empty on the open half sends one POST /layout (scope)' ($sent.Count -eq 1) "POST /layout count: $($sent.Count), bodies: $(Post-Text $sent)"
    if ($sent.Count -ne 1) { return }
    [void](Js $ws $splitFrameJs)
    Check 'split open: after the keep, the inspector offers Join Halves on the kept open half (control)' ((Js $ws (Win-Control-Js 'Join Halves' '')) -eq $true) 'no Join Halves button after Keep This Half Empty on the open half'
    $keepLine = Js $ws $keepLineJs
    Check 'split open: after the keep, the Keep line on the open half reads "The fill never puts a window here." (control)' ([string]$keepLine -ceq 'The fill never puts a window here.') "Keep line: '$keepLine'"
  }

  # ---- Split Cell: the selection after a grid change, the stack behind a half, and a split that doubles nothing ----------------------
  # A still click on an empty cell selects it. $script:emptySel is $true when the inspector then reads Empty Space.
  function Empty-Select($sock, [int]$slot, [string]$label) {
    $script:emptySel = $false
    $c = Cell-Click $sock $slot
    $drawn = ($null -ne $c -and $c.on)
    Check "split open: $label is drawn and free of windows (scope)" $drawn ('not drawn, or the press hits: ' + $(if ($c) { $c.hit } else { 'no cell' }))
    if (-not $drawn) { return }
    [void](WaitFor $sock $headEmptyCond 10)
    $head = Js $sock $winhJs
    $selected = ($head -ceq 'Empty Space')
    Check "split open: $label is selected, the inspector reads Empty Space (scope)" $selected "the inspector heading reads: '$head'"
    # A preview still in flight redraws the board and scrolls the stage; a scroll closes a split menu opened before it. Wait for rest first.
    [void](WaitFor $sock 'Object.keys(inflight).length === 0' 10)
    [void](Js $sock $splitFrameJs)
    $script:emptySel = $selected
  }
  # Selects empty cell $slot, then opens its split menu from the inspector's Split Cell button. $script:emptyMenu is $true when the menu is open.
  function Empty-Menu-Open($sock, [int]$slot, [string]$label) {
    $script:emptyMenu = $false
    Empty-Select $sock $slot $label
    if (-not $script:emptySel) { return }
    $hasBtn = WaitFor $sock $splitInspHasJs 10
    Check "split open: $label has a Split Cell button in its inspector (scope)" $hasBtn 'no Split Cell button in the inspector'
    if (-not $hasBtn) { return }
    [void](Js $sock $splitFrameJs)
    [void](Js $sock $splitInspJs)
    $open = WaitFor $sock $splitMenuJs 10
    Check "split open: Split Cell opens the split menu of $label (scope)" $open 'no split menu after Split Cell'
    $script:emptyMenu = [bool]$open
  }
  # The fine slots of the cells the page shows as selected (aria-pressed on a free place), sorted. Settled first, so a redraw is read.
  function Selected-Cells($sock) {
    $v = Js $sock 'await window.__h.settle(); return [...document.querySelectorAll(".cellbox[aria-pressed=\"true\"]")].map(e => Number(e.dataset.slot)).sort((a, b) => a - b);'
    @(@($v) | ? { $null -ne $_ } | % { [int]$_ })
  }
  # The slots of the one pin of this app on the ultrawide, sorted and joined. A pin Board-Edit makes carries no title match, so the app is the key.
  function App-Slots($layout, [string]$app) {
    $p = @(@($layout.pins) | ? { $_ -and ([string]$_.app -ceq $app) -and ([string]$_.mon -ceq 'U1') })
    if ($p.Count -ne 1) { return "no single $app pin" }
    ((Split-Ints $p[0].slots | Sort-Object) -join ',')
  }
  # The Undo button of the header, pressed.
  $undoJs = 'document.getElementById("undo").click(); return true;'
  # Window 1008 (pwsh - tiler, Windows Terminal) with window 1001 (Refactor the grid solver): the pair a half stacks.
  $claudeTermSnap = ConvertTo-Json -Depth 10 -Compress -InputObject ([pscustomobject]@{ monitors = @($snapObj.monitors); windows = @($snapObj.windows | ? { [int]$_.id -eq 1001 -or [int]$_.id -eq 1008 }) })
  $termBehind = [pscustomobject]@{ app = 'WindowsTerminal'; match = 'pwsh - tiler' }

  Case 'split open: Undo after a side split of cell 5 selects no other cell: the selection is cleared, or it stays on cell 5' {
    Put-Split (Split-Json 5 2 @(Split-Pin 0 @(0)))
    $opened = Open-Page $ws $url 'focus' $oneWinSnap
    Check 'split open: the page opens on Focus with window 1001 pinned (control)' $opened 'the page did not open on Focus in time'
    if (-not $opened) { return }
    Empty-Menu-Open $ws 4 'cell 5 (slot 4)'
    if (-not $script:emptyMenu) { return }
    $before = [int](Js $ws 'return window.__h.posts("layout").length')
    $item = Js $ws (Empty-Item-Js 'Side by Side')
    Check 'split open: the Side by Side item of cell 5 is enabled (scope)' ($item -eq $true) 'no enabled Side by Side item in the split menu'
    if ($item -ne $true) { return }
    [void](WaitFor $ws ('window.__h.posts("layout").length > ' + $before) 10)
    $sent = Layout-Posts-After $ws $before
    Check 'split open: the split of cell 5 sends one POST /layout (scope)' ($sent.Count -eq 1) "POST /layout count: $($sent.Count)"
    if ($sent.Count -ne 1) { return }
    $lay = (ConvertFrom-Json $sent[0].body).layout
    Check 'split open: the split of cell 5 doubles the grid to 10 by 2 (scope)' ((Split-Axis $lay.grids.U1.mult) -eq '2,1') "mult: '$(Split-Axis $lay.grids.U1.mult)'"
    $selSplit = Selected-Cells $ws
    Check 'split open: after the split the left half, slot 8, is selected (scope)' ($selSplit.Count -eq 1 -and $selSplit[0] -eq 8) "selected slot(s): $(@($selSplit) -join ',')"
    $beforeUndo = [int](Js $ws 'return window.__h.posts("layout").length')
    [void](Js $ws $undoJs)
    [void](WaitFor $ws ('window.__h.posts("layout").length > ' + $beforeUndo) 10)
    $undone = Layout-Posts-After $ws $beforeUndo
    Check 'split open: Undo sends one POST /layout that restores the 5 by 2 grid (scope)' ($undone.Count -eq 1 -and -not ((ConvertFrom-Json $undone[0].body).layout.grids.U1.mult)) "POST /layout count: $($undone.Count), bodies: $(Post-Text $undone)"
    $sel = Selected-Cells $ws
    Check 'split open: after Undo no cell is selected, or cell 5 (slot 4) is; cell 9 (slot 8) is not, the cell the stale selection named' ($sel.Count -eq 0 -or ($sel.Count -eq 1 -and $sel[0] -eq 4)) "selected slot(s) after Undo: $(@($sel) -join ',')"
  }

  Case 'split open: More Columns with cell 6 selected selects no other cell: the selection is cleared, or it stays on cell 6 (row 2, column 1)' {
    Put-Split (Split-Json 5 2 @(Split-Pin 0 @(0)))
    $opened = Open-Page $ws $url 'focus' $oneWinSnap
    Check 'split open: the page opens on Focus with window 1001 pinned (control)' $opened 'the page did not open on Focus in time'
    if (-not $opened) { return }
    Empty-Select $ws 5 'cell 6 (slot 5, row 2 column 1)'
    if (-not $script:emptySel) { return }
    $picked = Selected-Cells $ws
    Check 'split open: cell 6 is the one selected before the Columns change (scope)' ($picked.Count -eq 1 -and $picked[0] -eq 5) "selected slot(s): $(@($picked) -join ',')"
    if ($picked.Count -ne 1) { return }
    $more = Js $ws 'const b = document.querySelector("#mon button[data-g=\"c\"][data-d=\"1\"]"); return !!b && !b.disabled;'
    Check 'split open: the Columns More button is enabled in the Monitor section (scope)' ($more -eq $true) 'no enabled More Columns button in the Monitor section'
    if ($more -ne $true) { return }
    [void](Js $ws 'document.querySelector("#mon button[data-g=\"c\"][data-d=\"1\"]").click(); return true;')
    $grown = WaitFor $ws 'snap.monitors.find(q => q.role === "wide").el.querySelectorAll(".cell").length === 12' 10
    Check 'split open: More Columns makes the ultrawide grid 6 by 2 (scope)' $grown 'the ultrawide does not show 12 fine cells after More Columns'
    if (-not $grown) { return }
    $sel = Selected-Cells $ws
    Check 'split open: after More Columns no cell is selected, or the cell the user picked is (slot 6, row 2 column 1); slot 5 is a different place' ($sel.Count -eq 0 -or ($sel.Count -eq 1 -and $sel[0] -eq 6)) "selected slot(s) after More Columns: $(@($sel) -join ',') (slot 5 is row 1, column 6)"
  }

  Case 'split open: scene switch then More Columns keeps scene A''s selection' {
    # Focus (5 by 2) has window 1001 pinned, and cell 6 (slot 5) is picked on it. Meetings is a second scene on the same monitor, 5 by 2 too.
    # More Columns is pressed while Meetings is shown, so Focus's grid does not change: its selection must stay on slot 5, not move to slot 6.
    $cfg = New-Config; Add-Layout $cfg 'focus' $plugKey (Split-Json 5 2 @(Split-Pin 0 @(0))); Add-Layout $cfg 'meetings' $plugKey (Split-Json 5 2 @()); Put-Config $cfg
    $opened = Open-Page $ws $url 'focus' $oneWinSnap
    Check 'split open: the page opens on Focus with window 1001 pinned (control)' $opened 'the page did not open on Focus in time'
    if (-not $opened) { return }
    Empty-Select $ws 5 'cell 6 (slot 5, row 2 column 1)'
    if (-not $script:emptySel) { return }
    $picked = Selected-Cells $ws
    Check 'split open: cell 6 is the one selected on Focus before the scene switch (scope)' ($picked.Count -eq 1 -and $picked[0] -eq 5) "selected slot(s): $(@($picked) -join ',')"
    if ($picked.Count -ne 1) { return }
    [void](Select-Scene $ws 'meetings' 'Meetings')
    $more = Js $ws 'const b = document.querySelector("#mon button[data-g=\"c\"][data-d=\"1\"]"); return !!b && !b.disabled;'
    Check 'split open: the Columns More button is enabled for Meetings on the same monitor (scope)' ($more -eq $true) 'no enabled More Columns button in the Monitor section'
    if ($more -ne $true) { return }
    [void](Js $ws 'document.querySelector("#mon button[data-g=\"c\"][data-d=\"1\"]").click(); return true;')
    $grown = WaitFor $ws 'snap.monitors.find(q => q.role === "wide").el.querySelectorAll(".cell").length === 12' 10
    Check 'split open: More Columns in Meetings makes its ultrawide grid 6 by 2 (scope)' $grown 'the ultrawide does not show 12 fine cells after More Columns in Meetings'
    if (-not $grown) { return }
    [void](Select-Scene $ws 'focus' 'Focus')
    $fine = WaitFor $ws 'snap.monitors.find(q => q.role === "wide").el.querySelectorAll(".cell").length === 10' 10
    Check 'split open: back on Focus the ultrawide shows its 5 by 2 grid, 10 cells (scope)' $fine 'Focus does not show 10 fine cells'
    if (-not $fine) { return }
    $sel = Selected-Cells $ws
    Check 'split open: Focus keeps cell 6 (slot 5) selected after More Columns in Meetings, and the selection does not move to cell 7 (slot 6)' ($sel.Count -eq 1 -and $sel[0] -eq 5) "selected slot(s) on Focus: $(@($sel) -join ',') (slot 5 is cell 6, slot 6 is cell 7)"
  }

  Case 'split open: scene switch, More Columns in Meetings, then Undo there keeps scene A''s selection' {
    # The same setup, then Undo of the More Columns in Meetings. Undo changes Meetings' grid back and must not clear Focus's selection.
    $cfg = New-Config; Add-Layout $cfg 'focus' $plugKey (Split-Json 5 2 @(Split-Pin 0 @(0))); Add-Layout $cfg 'meetings' $plugKey (Split-Json 5 2 @()); Put-Config $cfg
    $opened = Open-Page $ws $url 'focus' $oneWinSnap
    Check 'split open: the page opens on Focus with window 1001 pinned, for the Undo variant (control)' $opened 'the page did not open on Focus in time'
    if (-not $opened) { return }
    Empty-Select $ws 5 'cell 6 (slot 5, row 2 column 1), for the Undo variant'
    if (-not $script:emptySel) { return }
    $picked = Selected-Cells $ws
    Check 'split open: cell 6 is the one selected on Focus before the scene switch, for the Undo variant (scope)' ($picked.Count -eq 1 -and $picked[0] -eq 5) "selected slot(s): $(@($picked) -join ',')"
    if ($picked.Count -ne 1) { return }
    [void](Select-Scene $ws 'meetings' 'Meetings')
    $more = Js $ws 'const b = document.querySelector("#mon button[data-g=\"c\"][data-d=\"1\"]"); return !!b && !b.disabled;'
    Check 'split open: the Columns More button is enabled for Meetings, for the Undo variant (scope)' ($more -eq $true) 'no enabled More Columns button in the Monitor section'
    if ($more -ne $true) { return }
    [void](Js $ws 'document.querySelector("#mon button[data-g=\"c\"][data-d=\"1\"]").click(); return true;')
    $grown = WaitFor $ws 'snap.monitors.find(q => q.role === "wide").el.querySelectorAll(".cell").length === 12' 10
    Check 'split open: More Columns in Meetings makes its ultrawide grid 6 by 2, for the Undo variant (scope)' $grown 'the ultrawide does not show 12 fine cells after More Columns in Meetings'
    if (-not $grown) { return }
    [void](Js $ws 'await window.__h.settle(); return true')
    $beforeUndo = [int](Js $ws 'return window.__h.posts("layout").length')
    [void](Js $ws $undoJs)
    [void](WaitFor $ws ('window.__h.posts("layout").length > ' + $beforeUndo) 10)
    $undone = Layout-Posts-After $ws $beforeUndo
    Check 'split open: Undo sends one POST /layout that restores Meetings to its 5 by 2 grid (scope)' ($undone.Count -eq 1 -and -not ((ConvertFrom-Json $undone[0].body).layout.grids.U1.mult)) "POST /layout count: $($undone.Count), bodies: $(Post-Text $undone)"
    if ($undone.Count -ne 1) { return }
    [void](Select-Scene $ws 'focus' 'Focus')
    $fine = WaitFor $ws 'snap.monitors.find(q => q.role === "wide").el.querySelectorAll(".cell").length === 10' 10
    Check 'split open: back on Focus after the Undo the ultrawide shows its 5 by 2 grid, 10 cells (scope)' $fine 'Focus does not show 10 fine cells'
    if (-not $fine) { return }
    $sel = Selected-Cells $ws
    Check 'split open: after Undo in Meetings, Focus keeps cell 6 (slot 5) selected: it is not cleared, and it does not move to cell 7 (slot 6)' ($sel.Count -eq 1 -and $sel[0] -eq 5) "selected slot(s) on Focus after Undo: $(@($sel) -join ',') (slot 5 is cell 6, slot 6 is cell 7)"
  }

  Case 'split open: Join Halves on an empty half whose other half holds Claude with Terminal stacked behind takes Claude, not the back window' {
    Put-Split (Split-Json 5 2 @(Split-Pin 0 @(1) $false @($termBehind)) '2,1' '2,1' @() @{ apps = @('*') })
    $opened = Open-Page $ws $url 'focus' $claudeTermSnap
    Check 'split open: the page opens on Focus with Claude in half 2 and Terminal behind it (control)' $opened 'the page did not open on Focus in time'
    if (-not $opened) { return }
    # The name is read once the page draws it.
    [void](WaitFor $ws ('[...document.querySelectorAll(".cellbox")].some(e => e.dataset.slot === "0" && /Open half/.test(e.getAttribute("aria-label") || ""))') 10)
    $named = @(Ax-Named $ws 'Open half|Stays empty|Kept empty')
    $onZero = @(@($named) | ? { $_.slot -eq 0 })
    Check 'split open: the empty half, cell 1 (slot 0), is named Open half before the press (scope)' ($onZero.Count -eq 1 -and $onZero[0].name -cmatch 'Open half') "named halves: $(Half-Text $named)"
    if ($onZero.Count -ne 1) { return }
    $c = Cell-Click $ws 0
    Check 'split open: the empty half, slot 0, is drawn and free of windows (scope)' ($null -ne $c -and $c.on) "not drawn, or the press hits: $(if ($c) { $c.hit } else { 'no cell' })"
    if ($null -eq $c -or -not $c.on) { return }
    [void](WaitFor $ws $headOpenCond 10)
    $claude = [string](Js $ws 'return appName("claude");')
    $term = [string](Js $ws 'return appName("WindowsTerminal");')
    $winText = [string](Js $ws 'const w = document.getElementById("win"); return w ? w.textContent.replace(/\s+/g, " ").trim() : "";')
    Check "split open: the inspector names $claude, the front window of the other half, and not $term" ($claude -ne '' -and $winText.Contains($claude) -and -not $winText.Contains($term)) "the Window section reads: '$winText'"
    $before = [int](Js $ws 'return window.__h.posts("layout").length')
    [void](Js $ws 'document.getElementById("joinbtn").click(); return true;')
    [void](WaitFor $ws ('window.__h.posts("layout").length > ' + $before) 10)
    $sent = Layout-Posts-After $ws $before
    $joinStatus = [string](Js $ws 'return document.getElementById("msg").textContent;')
    Check 'split open: Join Halves on the empty half sends one POST /layout (status reads: see detail)' ($sent.Count -eq 1) "POST /layout count: $($sent.Count); status: '$joinStatus'"
    if ($sent.Count -ne 1) { return }
    $lay = (ConvertFrom-Json $sent[0].body).layout
    Check 'split open: Claude takes the whole cell: its pin holds slot 0 alone, and the grid is 5 by 2 again' ((App-Slots $lay 'claude') -eq '0' -and (Split-Axis $lay.grids.U1.mult) -eq '1,1') "its pin holds: $(App-Slots $lay 'claude'); mult: '$(Split-Axis $lay.grids.U1.mult)'"
  }

  Case 'split open: Split Cell on an even empty block, which doubles nothing, is one page-only undo step: Undo sends no POST, names the split, and keeps the pin saved before it' {
    Put-Split (Split-Json 5 2 @() '2,1' '2,1')
    $opened = Open-Page $ws $url 'focus' $oneWinSnap
    Check 'split open: the page opens on Focus with no pin (control)' $opened 'the page did not open on Focus in time'
    if (-not $opened) { return }
    $pinned = Board-Edit $ws 1001 0
    $pin = @($pinned.layout)
    $pinLay = if ($pin.Count -eq 1) { (ConvertFrom-Json $pin[0].body).layout } else { $null }
    Check 'split open: pinning window 1001 to cell 1 (slot 0) sends one POST /layout (control: the change saved before the split)' ($pin.Count -eq 1 -and (App-Slots $pinLay 'claude') -eq '0') "POST /layout count: $($pin.Count), its pin holds: $(if ($pinLay) { App-Slots $pinLay 'claude' } else { 'no layout' }), bodies: $(Post-Text $pin)"
    if ($pin.Count -ne 1) { return }
    Empty-Menu-Open $ws 2 'the empty block of cells 2 and 3 (slots 2 and 3)'
    if (-not $script:emptyMenu) { return }
    $before = [int](Js $ws 'return window.__h.posts("layout").length')
    $item = Js $ws (Empty-Item-Js 'Side by Side')
    Check 'split open: the block of cells 2 and 3 has an enabled Side by Side item (scope)' ($item -eq $true) 'no enabled Side by Side item in the split menu'
    if ($item -ne $true) { return }
    $afterSplit = Layout-Posts-After $ws $before
    Check 'split open: a split that doubles nothing sends no POST /layout (control)' ($afterSplit.Count -eq 0) "POST /layout count: $($afterSplit.Count), bodies: $(Post-Text $afterSplit)"
    [void](WaitFor $ws '["2", "3"].every(s => [...document.querySelectorAll(".cellbox")].some(e => e.dataset.slot === s && /Open half/.test(e.getAttribute("aria-label") || "")))' 10)
    $marks = @(Ax-Named $ws 'Open half|Stays empty|Kept empty')
    $markOn23 = @(@($marks) | ? { $_.slot -eq 2 -or $_.slot -eq 3 })
    Check 'split open: the split marks cells 2 and 3 as Open half before Undo (scope)' ($markOn23.Count -eq 2) "named halves: $(Half-Text $marks)"
    if ($markOn23.Count -ne 2) { return }
    $beforeUndo = [int](Js $ws 'return window.__h.posts("layout").length')
    [void](Js $ws $undoJs)
    $undone = Layout-Posts-After $ws $beforeUndo
    Check 'split open: Undo of the split sends no POST /layout, since the step is page-only' ($undone.Count -eq 0) "POST /layout count: $($undone.Count), bodies: $(Post-Text $undone)"
    $said = [string](Js $ws 'return [document.getElementById("msg").textContent, document.getElementById("toastText").textContent].join(" | ");')
    Check 'split open: Undo names the split in the status, "Undid the split." (not an earlier change)' ($said -match '(?i)undid the split') "status and toast read: '$said'"
    $pinsNow = Js $ws 'return { pins: (typeof work !== "undefined" && work[selId]) ? work[selId].pins : [] };'
    Check 'split open: Undo keeps the pin saved before the split: window 1001 stays on slot 0 (control)' ((App-Slots $pinsNow 'claude') -eq '0') "its pin holds: $(App-Slots $pinsNow 'claude')"
    $left = @(Ax-Named $ws 'Open half|Stays empty|Kept empty')
    $leftOn23 = @(@($left) | ? { $_.slot -eq 2 -or $_.slot -eq 3 })
    Check 'split open: after Undo cells 2 and 3 are no longer named Open half (the split marks are reverted)' ($leftOn23.Count -eq 0) "named halves: $(Half-Text $leftOn23)"
  }

  # Inert trigger switch (mockup docs/design/mockups/inert-trigger-switch.html). A switch is inert when it is On and can do
  # nothing for its scene. needNote in app.html names three such cases, and each is drawn here: Call Size on a scene that is neither Listen nor
  # Meetings, Setup with no setup picked, and Work Match on a scene no entry of the activity map points at (the starters map Focus and Review).
  # Every main trigger stays manual, so only the extra switches decide what the rail and the inspector say.
  function Inert-Config([hashtable]$on, [hashtable]$setupKey = @{}) {
    $cfg = New-Config
    foreach ($id in $on.Keys) {
      $sc = @($cfg.scenes | ? { $_.id -eq $id })[0]
      foreach ($k in $on[$id]) { $sc.auto.$k = $true }
      if ($setupKey.ContainsKey($id)) { $sc | Add-Member -Force -NotePropertyName setupKey -NotePropertyValue $setupKey[$id] }
    }
    $cfg
  }
  # Mixed: four scenes have a working switch (Default, Focus, Meetings, Listen), and three hold an inert one (Focus, Review, Solo). Focus holds both
  # kinds: its Gap is shared with Default, which is a conflict note and not inertness. Listen's Call Size is the working twin of Focus's inert one.
  $inertMixed = @{ default = @('gaps'); focus = @('size', 'gaps', 'activity'); meetings = @('setup'); review = @('setup'); solo = @('activity'); listen = @('size') }
  # Nothing working: two scenes hold only an inert switch (Review's Setup with no setup picked, Solo's Work Match).
  $inertOnly = @{ review = @('setup'); solo = @('activity') }
  # The chips of the mixed rail: scene, chip name, and whether its switch is inert.
  $inertChips = @(
    [pscustomobject]@{ scene = 'focus'; label = 'Call Size'; inert = $true }, [pscustomobject]@{ scene = 'review'; label = 'Setup'; inert = $true }
    [pscustomobject]@{ scene = 'solo'; label = 'Work Match'; inert = $true }, [pscustomobject]@{ scene = 'default'; label = 'Gap'; inert = $false }
    [pscustomobject]@{ scene = 'focus'; label = 'Gap'; inert = $false }, [pscustomobject]@{ scene = 'focus'; label = 'Work Match'; inert = $false }
    [pscustomobject]@{ scene = 'meetings'; label = 'Setup'; inert = $false }, [pscustomobject]@{ scene = 'listen'; label = 'Call Size'; inert = $false }
  )
  # A chip is a child of its card's .chips. It is found by its name at the start of its words, past any hidden "Warning: " lead, so a chip that
  # gains a reason line is still found. `extra` is the letters its words (text, aria-label, title) hold once its name is taken out.
  $inertChipsJs = @'
const want = __WANT__;
const bare = e => e.textContent.replace(/\s+/g, " ").trim().replace(/^Warning:\s*/i, "");
return { chips: want.map(([scene, label]) => {
  const b = [...document.querySelectorAll("[data-pick]")].find(x => x.dataset.pick === scene);
  const card = b ? b.closest("article.card") : null;
  const c = card ? [...card.querySelectorAll(".chips > *")].find(x => bare(x).startsWith(label)) : null;
  if (!c) return { scene: scene, label: label, found: false };
  const all = [c.getAttribute("aria-label") || "", c.getAttribute("title") || "", c.textContent].join(" ");
  return { scene: scene, label: label, found: true, cls: c.getAttribute("class") || "", text: c.textContent.replace(/\s+/g, " ").trim(), extra: all.split(label).join(" ").replace(/Warning:/gi, "").replace(/[^A-Za-z]/g, "") };
}) };
'@
  # The rail's line and how many scene cards it sits over.
  $inertRailJs = 'return { sum: document.getElementById("railsum").textContent.replace(/\s+/g, " ").trim(), cards: document.querySelectorAll("#cards article.card").length }'
  # The callout of the open scene, as a person reads it: the text that is not hidden (the two texts share one cell, and the other is visibility:hidden).
  $inertCalloutJs = 'const c = document.querySelector("#scenebox .callout"); if (!c) return null; return [...c.children].filter(e => getComputedStyle(e).visibility !== "hidden").map(e => e.textContent).join(" ").replace(/\s+/g, " ").trim()'
  # A switch row of the inspector, by its data-auto key: the words it shows without its note and its thresholds, and whether a bare "On" is among them.
  $inertRowsJs = @'
const row = k => { const i = document.querySelector('#scenebox input[data-auto="' + k + '"]'); return i ? i.closest(".xrow") : null };
const stat = k => { const r = row(k); if (!r) return null; const c = r.cloneNode(true); c.querySelectorAll(".xwarn, .xopt").forEach(n => n.remove());
  return { checked: r.querySelector("input").checked, text: c.textContent.replace(/\s+/g, " ").trim(), bareOn: [...c.querySelectorAll("*")].some(e => e.children.length === 0 && e.textContent.trim() === "On") } };
const s = document.querySelector("#scenebox .xsum");
return { size: stat("size"), gaps: stat("gaps"), activity: stat("activity"), setup: stat("setup"), sum: s ? s.textContent.replace(/\s+/g, " ").trim() : null };
'@
  # Picks a scene's card, as a user does, and waits for its inspector.
  function Inert-Select($sock, [string]$scene) {
    [void](Js $sock ('document.querySelector("[data-pick=__S__]").click(); return true'.Replace('__S__', $scene)))
    WaitFor $sock ('selId === "__S__" && !!document.querySelector("#scenebox .callout")'.Replace('__S__', $scene))
  }
  # Flips one extra switch of the open scene, as the page's own change handler hears it, and reads the two lines it says in the same turn: the
  # footer (#msg) and the note under the scene (#smsg). The handler runs inside the dispatch, so nothing later can have replaced the words.
  # Then reads the switch's row (the shared $inertRowsJs) for what it shows after the flip.
  $inertFlipJs = @'
const i = document.querySelector('#scenebox input[data-auto="__K__"]');
if (!i) return { found: false };
i.checked = __ON__; i.dispatchEvent(new Event("change", { bubbles: true }));
const words = id => { const e = document.getElementById(id); return e ? e.textContent.replace(/\s+/g, " ").trim() : "" };
return { found: true, footer: words("msg"), note: words("smsg") };
'@
  function Inert-Flip($sock, [string]$key, [bool]$on) {
    $said = Js $sock ($inertFlipJs.Replace('__K__', $key).Replace('__ON__', $(if ($on) { 'true' } else { 'false' })))
    $rows = Js $sock $inertRowsJs
    [pscustomobject]@{ found = [bool]$said.found; footer = [string]$said.footer; note = [string]$said.note; row = $rows.$key }
  }

  Case 'inert switch, rail: the chip of a switch that does nothing is marked apart from a working chip, and the rail counts only scenes with a working trigger' {
    Put-Config (Inert-Config $inertMixed @{ meetings = $plugKey })
    $opened = Open-Page $ws $url 'focus'
    Check 'inert switch: the page opens on Focus (control)' $opened 'the page did not open on Focus in time'
    if (-not $opened) { return }
    $rail = Js $ws $inertRailJs
    Check 'inert switch: the rail draws the 7 scenes (scope)' ($rail.cards -eq 7) "scene cards: $($rail.cards)"
    $want = '[' + (($inertChips | % { '["' + $_.scene + '","' + $_.label + '"]' }) -join ',') + ']'
    $got = @((Js $ws ($inertChipsJs.Replace('__WANT__', $want))).chips)
    $lost = @($got | ? { -not $_.found } | % { "$($_.label) on $($_.scene)" })
    Check 'inert switch: each of the 8 switches that are on shows a chip on its card (scope)' ($got.Count -eq 8 -and $lost.Count -eq 0) "no chip for: $($lost -join ', ')"
    if ($lost.Count -gt 0) { return }
    for ($i = 0; $i -lt $inertChips.Count; $i++) {
      $t = $inertChips[$i]; $c = $got[$i]
      # Marked: a class that names the state, or words past the chip's name. Neither is on a chip today.
      $marked = ($c.cls -match 'inert|inactive') -or ($c.extra.Length -gt 0)
      $seen = "class '$($c.cls)', words '$($c.text)'"
      if ($t.inert) { Check "inert switch: the $($t.label) chip of $($t.scene), a switch that does nothing, is marked apart from a working chip" $marked $seen }
      else { Check "inert switch: the $($t.label) chip of $($t.scene), a working switch, is unchanged (control)" (-not $marked -and $c.text -ceq $t.label) $seen }
    }
    Check 'inert switch: the rail line counts the 4 scenes with a working trigger, and not the 2 that hold only an inert switch' ($rail.sum -match '^4 of 7 scenes have triggers on') "rail line: '$($rail.sum)'"
    Check 'inert switch: the rail line says that 3 scenes hold a switch that does nothing' ($rail.sum -match '\b3\b[^.]*does nothing') "rail line: '$($rail.sum)'"
  }

  Case 'inert switch, nothing working: the rail says no scene has a trigger on, and the callout of a scene with only inert switches says no working trigger is on' {
    Put-Config (Inert-Config $inertOnly)
    $opened = Open-Page $ws $url 'solo'
    Check 'inert switch: the page opens on Solo (control)' $opened 'the page did not open on Solo in time'
    if (-not $opened) { return }
    $rail = Js $ws $inertRailJs
    Check 'inert switch: the rail draws the 7 scenes (scope)' ($rail.cards -eq 7) "scene cards: $($rail.cards)"
    Check 'inert switch: with only inert switches on, the rail says no scene has a trigger on yet' ($rail.sum -match '^No scene has a trigger on yet') "rail line: '$($rail.sum)'"
    Check 'inert switch: with only inert switches on, the rail line says that 2 scenes hold a switch that does nothing' ($rail.sum -match '\b2\b[^.]*does nothing') "rail line: '$($rail.sum)'"
    $say = Js $ws $inertCalloutJs
    Check 'inert switch: the inspector of Solo shows a callout (scope)' ($null -ne $say) 'no callout in the inspector'
    Check 'inert switch: the callout of Solo, which holds only an inert switch, says no working trigger is on' ([string]$say -match 'No working trigger is on') "callout reads: '$say'"
    Check 'inert switch: that callout does not say triggers move windows without asking' ([string]$say -notmatch 'move your windows without asking') "callout reads: '$say'"
    # Control: a scene with no switch on keeps its callout.
    $sel = Inert-Select $ws 'meetings'
    Check 'inert switch: Meetings opens in the inspector (control)' $sel 'the inspector did not open on Meetings in time'
    if (-not $sel) { return }
    $none = Js $ws $inertCalloutJs
    Check 'inert switch: a scene with no switch on still reads that no trigger is on (control)' ([string]$none -match '^No trigger is on') "callout reads: '$none'"
  }

  Case 'inert switch, inspector: the switch that does nothing reads On, inactive, and the line of extra triggers counts it apart from a conflict warning' {
    Put-Config (Inert-Config $inertMixed @{ meetings = $plugKey })
    $opened = Open-Page $ws $url 'focus'
    Check 'inert switch: the page opens on Focus (control)' $opened 'the page did not open on Focus in time'
    if (-not $opened) { return }
    $r = Js $ws $inertRowsJs
    $onAll = $r.size -and $r.gaps -and $r.activity -and $r.size.checked -and $r.gaps.checked -and $r.activity.checked
    Check 'inert switch: Focus shows its Call Size, Gap and Work Match switches, all On (scope)' ([bool]$onAll) "rows: $(ConvertTo-Json -Compress -InputObject $r)"
    if (-not $onAll) { return }
    Check 'inert switch: the Call Size switch of Focus, which does nothing there, reads inactive' ($r.size.text -match 'inactive') "row reads: '$($r.size.text)'"
    Check 'inert switch: the Gap switch of Focus, which has a conflict note only, still reads a bare On and not inactive (control)' ($r.gaps.bareOn -and $r.gaps.text -notmatch 'inactive') "row reads: '$($r.gaps.text)'"
    Check 'inert switch: the Work Match switch of Focus, which the activity map points at, still reads a bare On and not inactive (control)' ($r.activity.bareOn -and $r.activity.text -notmatch 'inactive') "row reads: '$($r.activity.text)'"
    Check 'inert switch: the line of extra triggers counts the 3 switches that are On (control)' ([string]$r.sum -match '^3 on\b') "line reads: '$($r.sum)'"
    Check 'inert switch: the line of extra triggers says 1 inactive' ([string]$r.sum -match '\b1 inactive\b') "line reads: '$($r.sum)'"
    Check 'inert switch: the line of extra triggers still counts the conflict as 1 warning, apart from the inactive switch' ([string]$r.sum -match '\b1 warning\b' -and [string]$r.sum -notmatch '\b2 warnings\b') "line reads: '$($r.sum)'"
    # Control: a scene with a working trigger keeps its callout.
    $sel = Inert-Select $ws 'default'
    Check 'inert switch: Default opens in the inspector (control)' $sel 'the inspector did not open on Default in time'
    if (-not $sel) { return }
    $live = Js $ws $inertCalloutJs
    Check 'inert switch: a scene with a working trigger still reads that triggers move windows without asking (control)' ([string]$live -match 'Triggers that are on move your windows without asking') "callout reads: '$live'"
  }

  # The strip under 1180 px (app.html's max-width rule): the card's pick hides every small line in it, and an inert chip's reason is one. The
  # reason is read as drawn (its display and a height), not as text, since a hidden line keeps its words. At 1440 the same line is the control.
  Case 'inert switch, 1024: the reason line of each chip that does nothing is shown on the strip, as it is at 1440' {
    Put-Config (Inert-Config $inertMixed @{ meetings = $plugKey })
    Set-View $ws 1024 900
    try {
      $opened = Open-Page $ws $url 'focus'
      Check 'inert switch, 1024: the page opens on Focus at 1024 (control)' $opened 'the page did not open on Focus in time'
      if (-not $opened) { return }
      $reasonJs = @'
const want = __WANT__;
const bare = e => e.textContent.replace(/\s+/g, " ").trim().replace(/^Warning:\s*/i, "");
return { chips: want.map(([scene, label]) => {
  const b = [...document.querySelectorAll("[data-pick]")].find(x => x.dataset.pick === scene);
  const card = b ? b.closest("article.card") : null;
  const c = card ? [...card.querySelectorAll(".chips > *")].find(x => bare(x).startsWith(label)) : null;
  if (!c) return { scene: scene, label: label, found: false };
  const s = c.querySelector("small");
  const h = s ? s.getBoundingClientRect().height : 0;
  return { scene: scene, label: label, found: true, display: s ? getComputedStyle(s).display : "no reason line", height: Math.round(h), shown: !!s && getComputedStyle(s).display !== "none" && h > 0 };
}) };
'@
      $want = '[' + (($inertChips | ? { $_.inert } | % { '["' + $_.scene + '","' + $_.label + '"]' }) -join ',') + ']'
      $at1024 = @((Js $ws ($reasonJs.Replace('__WANT__', $want))).chips)
      $lost = @($at1024 | ? { -not $_.found } | % { "$($_.label) on $($_.scene)" })
      Check 'inert switch, 1024: each of the 3 chips that do nothing is on its card (scope)' ($at1024.Count -eq 3 -and $lost.Count -eq 0) "no chip for: $($lost -join ', ')"
      foreach ($c in @($at1024 | ? { $_.found })) {
        Check "inert switch, 1024: the reason line of the $($c.label) chip of $($c.scene), a switch that does nothing, is shown" ([bool]$c.shown) "display $($c.display), height $($c.height) px"
      }
      Set-View $ws 1440 900
      $at1440 = @((Js $ws ($reasonJs.Replace('__WANT__', $want))).chips)
      Check 'inert switch, 1024: at 1440 the reason line of each of those 3 chips is shown (control)' (@($at1440 | ? { $_.shown }).Count -eq 3) "shown at 1440: $(@($at1440 | ? { $_.shown } | % { $_.label }) -join ', ')"
    } finally { Fix-View $ws }
  }

  # Turning a switch On (debt inert-switch-announces-moves). The page's change handler words the line itself, and it words it for every switch
  # the same way, so an inert switch is told that it moves windows while its own row reads On, inactive. The probes turn one switch On in
  # each of the three kinds of inert switch (needNote's cases) and, for each kind, a working switch of the same key as a control. The line
  # lives in two places, the footer and the note under the scene, and the same words fill both. $flipWarn is the move claim's own words;
  # $flipInactive is the two ways the page already says a switch does nothing (the row's "inactive", the reason sentences' "does nothing").
  $flipWarn = 'without asking|moves windows'
  $flipInactive = 'inactive|does nothing|do nothing'
  Case 'inert switch, turning On: a switch that does nothing says it is inactive and not that it moves windows, and a working switch and an Off switch say what they did' {
    # Every switch is off. Meetings carries a setup key (Inert-Config sets it for the scenes it is asked about, so Meetings is named with no switch).
    Put-Config (Inert-Config @{ meetings = @() } @{ meetings = $plugKey })
    $opened = Open-Page $ws $url 'focus'
    Check 'inert switch, turn On: the page opens on Focus (control)' $opened 'the page did not open on Focus in time'
    if (-not $opened) { return }
    $probes = @(
      [pscustomobject]@{ scene = 'focus'; key = 'size'; name = 'Call Size on Focus'; inert = $true }          # Focus is neither Listen nor Meetings
      [pscustomobject]@{ scene = 'focus'; key = 'setup'; name = 'Setup on Focus'; inert = $true }             # no setup is picked for Focus
      [pscustomobject]@{ scene = 'solo'; key = 'activity'; name = 'Work Match on Solo'; inert = $true }       # no entry of the activity map points at Solo
      [pscustomobject]@{ scene = 'listen'; key = 'size'; name = 'Call Size on Listen'; inert = $false }       # Listen is the meeting rule's big-call scene
      [pscustomobject]@{ scene = 'meetings'; key = 'setup'; name = 'Setup on Meetings'; inert = $false }      # Meetings has the Desk setup picked
      [pscustomobject]@{ scene = 'focus'; key = 'activity'; name = 'Work Match on Focus'; inert = $false }    # the activity map points Claude at Focus
    )
    foreach ($p in $probes) {
      $sel = Inert-Select $ws $p.scene
      Check "inert switch, turn On: $($p.scene) opens in the inspector for $($p.name) (control)" $sel "the inspector did not open on $($p.scene) in time"
      if (-not $sel) { continue }
      $r = Inert-Flip $ws $p.key $true
      Check "inert switch, turn On: $($p.name) has a switch to turn On (scope)" $r.found "no data-auto=$($p.key) switch in the inspector of $($p.scene)"
      if (-not $r.found) { continue }
      $rowSays = if ($r.row) { "row reads: '$($r.row.text)', checked $($r.row.checked)" } else { 'no row' }
      $lines = "footer reads: '$($r.footer)'; note reads: '$($r.note)'"
      if ($p.inert) {
        Check "inert switch, turn On: $($p.name), turned On, reads On, inactive (scope)" ([bool]($r.row -and $r.row.checked -and $r.row.text -match 'inactive')) $rowSays
        Check "inert switch, turn On: $($p.name), turned On, says something in the footer and in the note (scope)" ($r.footer.Length -gt 0 -and $r.note.Length -gt 0) $lines
        if (-not ($r.row -and $r.row.checked -and $r.row.text -match 'inactive') -or $r.footer.Length -eq 0 -or $r.note.Length -eq 0) { continue }
        Check "inert switch, turn On: $($p.name), which does nothing there, does not say it moves windows" (-not ($r.footer -match $flipWarn) -and -not ($r.note -match $flipWarn)) $lines
        Check "inert switch, turn On: $($p.name), which does nothing there, says it is inactive" ($r.footer -match $flipInactive -and $r.note -match $flipInactive) $lines
      } else {
        Check "inert switch, turn On: $($p.name), turned On, reads a bare On and not inactive (scope)" ([bool]($r.row -and $r.row.checked -and $r.row.bareOn -and $r.row.text -notmatch 'inactive')) $rowSays
        Check "inert switch, turn On: $($p.name), a working switch, still says it moves windows without asking (control)" ($r.footer -match 'moves windows without asking' -and $r.note -match 'moves windows without asking') $lines
      }
    }
    # Control: a switch turned Off keeps its line. Focus's Call Size was turned On, and is inert, in the first probe; its work copy is still On.
    $sel = Inert-Select $ws 'focus'
    Check 'inert switch, turn Off: focus opens again in the inspector (control)' $sel 'the inspector did not open on focus in time'
    if (-not $sel) { return }
    $r = Inert-Flip $ws 'size' $false
    Check 'inert switch, turn Off: Call Size on Focus has a switch to turn Off (scope)' ($r.found -and $r.row -and -not $r.row.checked) "found $($r.found), row: $(ConvertTo-Json -Compress -InputObject $r.row)"
    if (-not ($r.found -and $r.row -and -not $r.row.checked)) { return }
    Check 'inert switch, turn Off: Call Size on Focus, turned Off, still says Save to keep it (control)' ($r.footer -match 'Save to keep it' -and $r.note -match 'Save to keep it') "footer reads: '$($r.footer)'; note reads: '$($r.note)'"
  }

  # ---- Draw Zone armed (mockup docs/design/mockups/draw-zone-hard-to-find.html, its notes beside it) -----------------------------------
  # Every case here is new, except the ones marked control, which pass on main. On main a press on Draw Zone opens the "Draw a Zone on" dialog at once
  # and the button has no pressed state, so a case that needs the armed board fails on main for that cause. No lookup throws: a missing button,
  # hint or dialog reads null or false, and the check on it fails. The two option cases (the board cue and the idle hint) stand alone, so an owner
  # who declines one removes one case and lowers the gate total by one.
  $dzIdleHint = 'Drag to a cell to pin it, or to the list to make it stay put. On a taken cell, the circle swaps and the rest puts it behind. Right-click a window to split its cell.'
  $dzArmedHint = 'Draw Zone is on. Drag across cells to draw a zone. Esc cancels.'
  $dzArmedStatus = 'Draw Zone is on. Drag across cells to draw a zone, or use Pick Cells by Menu. Esc cancels.'
  # All ten windows of the fixture, each pinned to its own cell of the 5 by 2 board: no cell is empty.
  $dzPins = @(0..9 | % { Split-Pin $_ @($_) })
  # Colours as the page computes them: rgb() or color(srgb). Blue is a clear lead of the blue channel over red and green.
  $cueJs = @'
const rgb = s => { let m = /^rgba?\(([^)]*)\)$/.exec(s); if (m) { const p = m[1].split(/[ ,\/]+/).filter(Boolean).map(Number); return { r: p[0], g: p[1], b: p[2] }; }
  m = /^color\(srgb ([^)]*)\)$/.exec(s); if (m) { const p = m[1].split(/[ \/]+/).filter(Boolean).map(Number); return { r: p[0] * 255, g: p[1] * 255, b: p[2] * 255 }; } return null; };
const blue = s => { const c = rgb(s); return !!c && c.b - c.r >= 100 && c.b - c.g >= 60; };
const mon = snap.monitors.find(q => q.role === "wide"), cells = mon && mon.el ? mon.el.querySelectorAll(".cell") : [], cell = cells[9], tile = els.get(1001);
if (!cell || !tile) return null;
const r = cell.getBoundingClientRect(), hit = document.elementFromPoint(r.left + r.width / 2, r.top + r.height / 2), cs = getComputedStyle(cell);
return { edgeStyle: cs.borderTopStyle, edge: cs.borderTopColor, edgeBlue: blue(cs.borderTopColor), tintBlue: blue(cs.backgroundColor), tileCursor: getComputedStyle(tile).cursor, cellCursor: hit ? getComputedStyle(hit).cursor : null, hitCell: !!hit && !!hit.closest(".cell") };
'@

  # What the cases read, in one page call: the Draw Zone button, the hint, the status line, the key list, the dialog, and the menu button.
  $dzReadJs = @'
const norm = e => e ? e.textContent.replace(/\s+/g, " ").trim() : null;
const z = document.getElementById("zadd"), d = document.getElementById("dlg");
const menu = [...document.querySelectorAll("#bbar button")].find(b => b.textContent.trim() === "Pick Cells by Menu");
return { shown: !!z && !z.hidden && z.getClientRects().length > 0, disabled: !!z && z.disabled, pressed: z ? z.getAttribute("aria-pressed") : null,
  hint: norm(document.getElementById("hint")), msg: norm(document.getElementById("msg")), keys: norm(document.getElementById("keys")),
  dlg: !!d && d.open, dlgTitle: d && d.open ? norm(d.querySelector("h2")) : null,
  menuShown: !!menu && !menu.hidden && menu.getClientRects().length > 0 };
'@
  # The centre of the Pick Cells by Menu button on the board bar, or null when it is not shown.
  $dzMenuJs = 'const b = [...document.querySelectorAll("#bbar button")].find(x => x.textContent.trim() === "Pick Cells by Menu"); if (!b || b.hidden || b.getClientRects().length === 0) return null; const r = b.getBoundingClientRect(); return { x: r.left + r.width / 2, y: r.top + r.height / 2 };'
  function Dz-Read($sock) { Js $sock $dzReadJs }
  # Opens Focus on a snapshot and waits for the page to rest, so no preview's status line lands after a press.
  function Dz-Open($sock, [string]$snapText) {
    $ok = Open-Page $sock $url 'focus' $snapText
    if ($ok) { [void](WaitFor $sock 'Object.keys(inflight).length === 0' 10) }
    $ok
  }
  # One press on Draw Zone, then the wait for what a press does. $want 'on' waits until the button reads pressed or a dialog is open (main opens
  # one); 'off' waits until it no longer reads pressed. Answers the page read, or null when the press found no enabled button.
  function Dz-Press($sock, [string]$want) {
    $hit = Js $sock 'const z = document.getElementById("zadd"); if (!z || z.disabled) return false; z.click(); return true'
    if ($hit -ne $true) { return $null }
    $cond = if ($want -eq 'on') { '(() => { const z = document.getElementById("zadd"); return (!!z && z.getAttribute("aria-pressed") === "true") || document.getElementById("dlg").open; })()' } else { '(() => { const z = document.getElementById("zadd"); return !!z && z.getAttribute("aria-pressed") !== "true"; })()' }
    [void](WaitFor $sock $cond 5)
    Dz-Read $sock
  }
  # Whether a read shows the button pressed.
  function Dz-On($r) { [bool]($r -and $r.pressed -ceq 'true') }
  # Forced colors on or off, as the OS sets them, through DevTools media emulation. Off sends an empty feature list, which clears it.
  function Set-Forced($sock, [bool]$on) {
    $features = @(); if ($on) { $features = @(@{ name = 'forced-colors'; value = 'active' }) }
    [void](Cdp $sock 'Emulation.setEmulatedMedia' @{ features = $features })
  }
  # Closes the open dialog with its Cancel button. Answers whether it is closed.
  function Dz-CloseDialog($sock) {
    [void](Js $sock 'const d = document.getElementById("dlg"), b = document.getElementById("dlgCancel"); if (d && d.open && b) b.click(); return true')
    WaitFor $sock '!document.getElementById("dlg").open' 10
  }
  # The New Zone dialog for three columns is open now (the old text of a closed dialog does not count).
  $dzNewZoneCond = 'document.getElementById("dlg").open && /New Zone: 3 Columns/.test((document.getElementById("dlgform") || {}).textContent || "")'
  # The layout POST count, once the page has settled.
  function Dz-Posts($sock) { [int](Js $sock 'await window.__h.settle(); return window.__h.posts("layout").length') }

  Case 'draw zone: a press arms it, so the button reads pressed and no dialog opens, and a second press turns it off' {
    Put-Split (Split-Json 5 2 @(Split-Pin 0 @(0)))
    $opened = Dz-Open $ws $oneWinSnap
    Check 'draw zone: the page opens on Focus with one window pinned (control)' $opened 'the page did not open on Focus in time'
    if (-not $opened) { return }
    $idle = Dz-Read $ws
    $ready = [bool]($idle -and $idle.shown -and -not $idle.disabled)
    Check 'draw zone: the Draw Zone button is shown and enabled before a press (scope)' $ready "shown $($idle.shown), disabled $($idle.disabled)"
    if (-not $ready) { return }
    Check 'draw zone: before a press the button reads not pressed (aria-pressed false)' ($idle.pressed -ceq 'false') "aria-pressed reads: '$($idle.pressed)'"
    $on = Dz-Press $ws 'on'
    Check 'draw zone: a press leaves the button pressed (aria-pressed true)' (Dz-On $on) "aria-pressed reads: '$($on.pressed)'"
    Check 'draw zone: a press opens no dialog' ($on -and -not $on.dlg) "a dialog is open: '$($on.dlgTitle)'"
    if (-not (Dz-On $on)) { return }
    $off = Dz-Press $ws 'off'
    Check 'draw zone: a second press turns it off (aria-pressed false)' ($off -and $off.pressed -ceq 'false') "aria-pressed reads: '$($off.pressed)'"
  }

  Case 'draw zone: while it is on, the hint and the status bar name zones, and the key list names the menu path' {
    Put-Split (Split-Json 5 2 @(Split-Pin 0 @(0)))
    $opened = Dz-Open $ws $oneWinSnap
    Check 'draw zone: the page opens on Focus with one window pinned (control)' $opened 'the page did not open on Focus in time'
    if (-not $opened) { return }
    $idle = Dz-Read $ws
    Check 'draw zone: before a press the hint starts with the live hint of today (control)' ($idle -and ([string]$idle.hint).StartsWith($dzIdleHint)) "hint reads: '$($idle.hint)'"
    $on = Dz-Press $ws 'on'
    Check 'draw zone: while it is on, the hint reads: Draw Zone is on. Drag across cells to draw a zone. Esc cancels.' ($on -and $on.hint -ceq $dzArmedHint) "hint reads: '$($on.hint)'"
    Check 'draw zone: while it is on, the status bar names the menu path as well' ($on -and $on.msg -ceq $dzArmedStatus) "status reads: '$($on.msg)'"
    Check 'draw zone: the key list line for Draw Zone names Pick Cells by Menu' ($on -and ([string]$on.keys).Contains("Draw Zone, then Pick Cells by Menu, picks a zone's cells with the keyboard.")) "key list reads: '$($on.keys)'"
    Check 'draw zone: the key list line for Esc adds Draw Zone' ($on -and ([string]$on.keys).Contains('Esc cancels a drag, a resize, a zone you are drawing, or Draw Zone.')) "key list reads: '$($on.keys)'"
  }

  Case 'draw zone: while it is on, a drag from a window with no Shift draws a zone and moves no window' {
    Put-Split (Split-Json 5 2 $dzPins)
    $opened = Dz-Open $ws $tenWinSnap
    Check 'draw zone: the page opens on Focus with ten windows on ten cells (control)' $opened 'the page did not open on Focus in time'
    if (-not $opened) { return }
    $on = Dz-Press $ws 'on'
    # Main opens the corner dialog on this press. It is closed here so the drag reaches the board and the checks below read what the drag does.
    if ($on -and $on.dlg) { [void](Dz-CloseDialog $ws) }
    $a = Tile-Centre $ws 1001; $b = Tile-Centre $ws 1005
    $reach = [bool]($a -and $a.hit -and $b -and $b.hit)
    Check 'draw zone: windows 1001 and 1005 are drawn, and a press lands on each tile (scope)' $reach 'a tile is not drawn, or the press hits a button in it'
    if (-not $reach) { return }
    $before = Dz-Posts $ws
    Drag-At $ws $a.x $a.y $b.x $b.y
    [void](WaitFor $ws ($dzNewZoneCond + ' || window.__h.posts("layout").length > ' + $before) 10)
    $sent = Layout-Posts-After $ws $before
    $dlg = (Js $ws ('return !!(' + $dzNewZoneCond + ')')) -eq $true
    Check 'draw zone: a drag from window 1001 across window 1005 opens the New Zone dialog for 3 columns' $dlg 'no New Zone dialog after the drag'
    Check 'draw zone: the drag moves no window (no POST /layout before Add Zone)' ($sent.Count -eq 0) "POST /layout count: $($sent.Count), bodies: $(Post-Text $sent)"
    if (-not $dlg) { return }
    Confirm-Ask $ws
    [void](WaitFor $ws ('window.__h.posts("layout").length > ' + $before) 10)
    $sent = Layout-Posts-After $ws $before
    $zs = Posted-Zones $sent
    Check 'draw zone: Add Zone sends one POST /layout with the zone on cells 0, 1 and 2' ($sent.Count -eq 1 -and $zs -eq '0,1,2') "POST /layout count: $($sent.Count), zone slots: $zs"
    if ($sent.Count -ne 1) { return }
    $own = Split-SlotsOf (ConvertFrom-Json $sent[0].body).layout 'Refactor the grid solver'
    Check 'draw zone: window 1001 keeps its pin on cell 0' ($own -ceq '0') "its pin holds: $own"
  }

  Case 'draw zone: with it off, a drag from a window moves it and opens no zone dialog (control)' {
    Put-Split (Split-Json 5 2 $dzPins)
    $opened = Dz-Open $ws $tenWinSnap
    Check 'draw zone: the page opens on Focus with ten windows on ten cells (control)' $opened 'the page did not open on Focus in time'
    if (-not $opened) { return }
    $a = Tile-Centre $ws 1001; $b = Tile-Centre $ws 1005
    $reach = [bool]($a -and $a.hit -and $b -and $b.hit)
    Check 'draw zone: windows 1001 and 1005 are drawn, and a press lands on each tile (scope)' $reach 'a tile is not drawn, or the press hits a button in it'
    if (-not $reach) { return }
    $before = Dz-Posts $ws
    Drag-At $ws $a.x $a.y $b.x $b.y
    [void](WaitFor $ws ($dzNewZoneCond + ' || window.__h.posts("layout").length > ' + $before) 10)
    $sent = Layout-Posts-After $ws $before
    Check 'draw zone: a plain drag from window 1001 onto window 1005 sends a POST /layout, so the window moved (scope)' ($sent.Count -ge 1) 'no POST /layout after the drag'
    $dlg = (Js $ws ('return !!(' + $dzNewZoneCond + ')')) -eq $true
    Check 'draw zone: a plain drag opens no New Zone dialog (control)' (-not $dlg) 'a New Zone dialog is open after a plain drag'
  }

  Case 'draw zone: it turns off after a zone is canceled, and after a zone is added' {
    Put-Split (Split-Json 5 2 @(Split-Pin 0 @(0)))
    $opened = Dz-Open $ws $oneWinSnap
    Check 'draw zone: the page opens on Focus with one window pinned (control)' $opened 'the page did not open on Focus in time'
    if (-not $opened) { return }
    $on = Dz-Press $ws 'on'
    Check 'draw zone: a press arms it before the zone is drawn (scope)' (Dz-On $on) "aria-pressed reads: '$($on.pressed)'"
    if (-not (Dz-On $on)) { return }
    $a = Cell-Point $ws 2; $b = Cell-Point $ws 4
    Check 'draw zone: cells 2 and 4 are drawn (scope)' ($null -ne $a -and $null -ne $b) 'a cell is not drawn on the ultrawide'
    if ($null -eq $a -or $null -eq $b) { return }
    Drag-At $ws $a.x $a.y $b.x $b.y
    $dlg = WaitFor $ws $dzNewZoneCond 10
    Check 'draw zone: a drag across cells 2 to 4 while it is on opens the New Zone dialog (scope)' $dlg 'no New Zone dialog after the drag'
    if (-not $dlg) { return }
    [void](Dz-CloseDialog $ws)
    $r = Dz-Read $ws
    Check 'draw zone: after the zone dialog is canceled the button reads not pressed' ($r.pressed -ceq 'false') "aria-pressed reads: '$($r.pressed)'"
    $on = Dz-Press $ws 'on'
    Check 'draw zone: a press arms it again (scope)' (Dz-On $on) "aria-pressed reads: '$($on.pressed)'"
    if (-not (Dz-On $on)) { return }
    Drag-At $ws $a.x $a.y $b.x $b.y
    $dlg = WaitFor $ws $dzNewZoneCond 10
    Check 'draw zone: a second drag across cells 2 to 4 opens the New Zone dialog (scope)' $dlg 'no New Zone dialog after the second drag'
    if (-not $dlg) { return }
    $before = Dz-Posts $ws
    Confirm-Ask $ws
    [void](WaitFor $ws ('window.__h.posts("layout").length > ' + $before) 10)
    $r = Dz-Read $ws
    Check 'draw zone: after the zone is added the button reads not pressed' ($r.pressed -ceq 'false') "aria-pressed reads: '$($r.pressed)'"
  }

  Case 'draw zone: Esc turns it off, in the middle of a draw too, and so does a change of scene' {
    Put-Split (Split-Json 5 2 @(Split-Pin 0 @(0)))
    $opened = Dz-Open $ws $oneWinSnap
    Check 'draw zone: the page opens on Focus with one window pinned (control)' $opened 'the page did not open on Focus in time'
    if (-not $opened) { return }
    $on = Dz-Press $ws 'on'
    Check 'draw zone: a press arms it before Esc (scope)' (Dz-On $on) "aria-pressed reads: '$($on.pressed)'"
    if (-not (Dz-On $on)) { return }
    Press-Key $ws 'Escape' 27
    [void](WaitFor $ws '(document.getElementById("zadd") || {}).getAttribute("aria-pressed") !== "true"' 5)
    $r = Dz-Read $ws
    Check 'draw zone: Esc turns it off (aria-pressed false)' ($r.pressed -ceq 'false') "aria-pressed reads: '$($r.pressed)'"
    Check 'draw zone: after Esc the hint is the live hint of today again' (([string]$r.hint).StartsWith($dzIdleHint)) "hint reads: '$($r.hint)'"
    # Esc in the middle of a draw: the outline is up, Esc cancels it, and the release after it draws no zone.
    $on = Dz-Press $ws 'on'
    $a = Cell-Point $ws 2; $b = Cell-Point $ws 4
    $ready = [bool]((Dz-On $on) -and $null -ne $a -and $null -ne $b)
    Check 'draw zone: a press arms it again, and cells 2 and 4 are drawn (scope)' $ready "aria-pressed reads: '$($on.pressed)'"
    if (-not $ready) { return }
    [void](Cdp $ws 'Input.dispatchMouseEvent' @{ type = 'mouseMoved'; x = $a.x; y = $a.y })
    [void](Cdp $ws 'Input.dispatchMouseEvent' @{ type = 'mousePressed'; x = $a.x; y = $a.y; button = 'left'; buttons = 1; clickCount = 1 })
    foreach ($f in 0.5, 1.0) { [void](Cdp $ws 'Input.dispatchMouseEvent' @{ type = 'mouseMoved'; x = $a.x + ($b.x - $a.x) * $f; y = $a.y + ($b.y - $a.y) * $f; button = 'left'; buttons = 1 }) }
    $drawing = WaitFor $ws 'getComputedStyle(document.getElementById("zdraw")).display !== "none"' 5
    Check 'draw zone: the outline is up in the middle of the draw (scope)' $drawing 'no zone outline while the button is held'
    Press-Key $ws 'Escape' 27
    [void](Cdp $ws 'Input.dispatchMouseEvent' @{ type = 'mouseReleased'; x = $b.x; y = $b.y; button = 'left'; buttons = 0; clickCount = 1 })
    $r = Dz-Read $ws
    Check 'draw zone: Esc in the middle of a draw turns it off' ($r.pressed -ceq 'false') "aria-pressed reads: '$($r.pressed)'"
    Check 'draw zone: Esc in the middle of a draw opens no New Zone dialog' (-not $r.dlg) "a dialog is open: '$($r.dlgTitle)'"
    # A change of scene: it ends the draw mode, which belongs to the scene on the board.
    $on = Dz-Press $ws 'on'
    Check 'draw zone: a press arms it a third time (scope)' (Dz-On $on) "aria-pressed reads: '$($on.pressed)'"
    if (-not (Dz-On $on)) { return }
    [void](Js $ws 'document.querySelector("[data-pick=default]").click(); return true')
    $moved = WaitFor $ws 'selId === "default"' 10
    Check 'draw zone: the Default card opens that scene (scope)' $moved 'the page did not switch to Default'
    if (-not $moved) { return }
    $r = Dz-Read $ws
    Check 'draw zone: a change of scene turns it off' ($r.pressed -ceq 'false') "aria-pressed reads: '$($r.pressed)'"
  }

  Case 'draw zone: while it is on, a still click on an empty cell stays armed and picks no cell' {
    Put-Split (Split-Json 5 2 @(Split-Pin 0 @(0)))
    $opened = Dz-Open $ws $oneWinSnap
    Check 'draw zone: the page opens on Focus with one window pinned (control)' $opened 'the page did not open on Focus in time'
    if (-not $opened) { return }
    # Control: with it off, a still click on cell 8 picks it.
    $c = Cell-Click $ws 8
    Check 'draw zone: empty cell 8 is drawn, and the press lands on it (scope)' ($null -ne $c -and $c.on) "cell 8 is not drawn, or the press hits: $($c.hit)"
    if ($null -eq $c -or -not $c.on) { return }
    [void](WaitFor $ws $headEmptyCond 10)
    $sel = @(Selected-Cells $ws)
    Check 'draw zone: with it off, a still click on cell 8 picks it (control)' ($sel -contains 8) "picked cells: $($sel -join ',')"
    $on = Dz-Press $ws 'on'
    Check 'draw zone: a press arms it before the click (scope)' (Dz-On $on) "aria-pressed reads: '$($on.pressed)'"
    if (-not (Dz-On $on)) { return }
    $c = Cell-Click $ws 9
    Check 'draw zone: empty cell 9 is drawn, and the press lands on it (scope)' ($null -ne $c -and $c.on) "cell 9 is not drawn, or the press hits: $($c.hit)"
    if ($null -eq $c -or -not $c.on) { return }
    $sel = @(Selected-Cells $ws)
    Check 'draw zone: while it is on, a still click on cell 9 picks no cell' (-not ($sel -contains 9)) "picked cells: $($sel -join ',')"
    $r = Dz-Read $ws
    Check 'draw zone: a still click leaves it on' ($r.pressed -ceq 'true') "aria-pressed reads: '$($r.pressed)'"
  }

  Case 'draw zone: Pick Cells by Menu is on the board bar only while it is on, and opens the corner dialog' {
    Put-Split (Split-Json 5 2 @(Split-Pin 0 @(0)))
    $opened = Dz-Open $ws $oneWinSnap
    Check 'draw zone: the page opens on Focus with one window pinned (control)' $opened 'the page did not open on Focus in time'
    if (-not $opened) { return }
    $idle = Dz-Read $ws
    Check 'draw zone: with it off, the board bar has no Pick Cells by Menu button (control)' ($idle -and -not $idle.menuShown) 'a Pick Cells by Menu button is shown while it is off'
    $on = Dz-Press $ws 'on'
    if ($on -and $on.dlg) { [void](Dz-CloseDialog $ws) }
    $shown = [bool]($on -and $on.menuShown)
    Check 'draw zone: while it is on, the board bar has a Pick Cells by Menu button' $shown 'no Pick Cells by Menu button on the board bar'
    if (-not $shown) { return }
    [void](Js $ws '[...document.querySelectorAll("#bbar button")].find(b => b.textContent.trim() === "Pick Cells by Menu").click(); return true')
    $opens = WaitFor $ws 'document.getElementById("dlg").open && /Draw a Zone on/.test((document.getElementById("dlgform") || {}).textContent || "")' 10
    Check 'draw zone: Pick Cells by Menu opens the Draw a Zone dialog' $opens 'no Draw a Zone dialog after the press'
    if (-not $opens) { return }
    $pickers = Js $ws 'return document.querySelectorAll("#dlgform select[name=za], #dlgform select[name=zb]").length'
    Check 'draw zone: that dialog still has its From and To corner menus (control)' ($pickers -eq 2) "corner menus in the dialog: $pickers"
  }

  Case 'draw zone: the pressed button takes the ink fill, in light and dark, at 1440 and 1024' {
    Put-Split (Split-Json 5 2 @(Split-Pin 0 @(0)))
    $opened = Dz-Open $ws $oneWinSnap
    Check 'draw zone: the page opens on Focus with one window pinned (control)' $opened 'the page did not open on Focus in time'
    if (-not $opened) { return }
    # The page's own --ink and --panel, as a probe element resolves them in the current theme.
    $fillJs = @'
const z = document.getElementById("zadd"); if (!z) return null;
const p = document.createElement("i"); p.style.cssText = "position:fixed;background-color:var(--ink);color:var(--panel)"; document.body.append(p);
const q = getComputedStyle(p), c = getComputedStyle(z), out = { ink: q.backgroundColor, panel: q.color, bg: c.backgroundColor, fg: c.color }; p.remove(); return out;
'@
    try {
      foreach ($theme in 'light', 'dark') {
        foreach ($w in 1440, 1024) {
          $tag = "$theme at $w"
          Set-View $ws $w 900; Set-Theme $ws $theme
          $on = Dz-Press $ws 'on'
          if ($on -and $on.dlg) { [void](Dz-CloseDialog $ws) }
          Check "draw zone: a press arms it in $tag (scope)" (Dz-On $on) "aria-pressed reads: '$($on.pressed)'"
          if (-not (Dz-On $on)) { continue }
          $look = Js $ws $fillJs
          Check "draw zone: the pressed button's fill is the ink colour in $tag" ($look -and $look.bg -ceq $look.ink) "fill $($look.bg), ink $($look.ink)"
          Check "draw zone: the pressed button's label is the panel colour in $tag" ($look -and $look.fg -ceq $look.panel) "label $($look.fg), panel $($look.panel)"
          [void](Dz-Press $ws 'off')
        }
      }
    } finally { Reset-Look $ws }
  }

  # Option, the board cue (item 4 of the notes): a cell's edge and tint are blue and dashed while it is on, and the pointer over the board is a crosshair.
  Case 'draw zone, board cue: while it is on, cells have a blue dashed edge and tint and the pointer is a crosshair' {
    Put-Split (Split-Json 5 2 @(Split-Pin 0 @(0)))
    $opened = Dz-Open $ws $oneWinSnap
    Check 'draw zone, board cue: the page opens on Focus with one window pinned (control)' $opened 'the page did not open on Focus in time'
    if (-not $opened) { return }
    $idle = Js $ws $cueJs
    Check 'draw zone, board cue: before a press the cells are drawn and a press on cell 9 lands on a cell (scope)' ($idle -and $idle.hitCell) 'no cell 9, or the point is not on a cell'
    if (-not ($idle -and $idle.hitCell)) { return }
    Check 'draw zone, board cue: before a press the cell edge is dashed and not blue (control)' ($idle.edgeStyle -ceq 'dashed' -and -not $idle.edgeBlue) "edge $($idle.edgeStyle) $($idle.edge)"
    Check 'draw zone, board cue: before a press a window shows the grab pointer (control)' ($idle.tileCursor -ceq 'grab') "tile pointer: $($idle.tileCursor)"
    try {
      foreach ($theme in 'light', 'dark') {
        Set-Theme $ws $theme
        $on = Dz-Press $ws 'on'
        if ($on -and $on.dlg) { [void](Dz-CloseDialog $ws) }
        $look = Js $ws $cueJs
        Check "draw zone, board cue: while it is on the cell edge is blue and dashed in $theme" ($look -and $look.edgeStyle -ceq 'dashed' -and $look.edgeBlue) "edge $($look.edgeStyle) $($look.edge)"
        Check "draw zone, board cue: while it is on the cell tint is blue in $theme" ($look -and $look.tintBlue) 'the cell fill is not blue'
        Check "draw zone, board cue: while it is on the pointer over a window is a crosshair in $theme" ($look -and $look.tileCursor -ceq 'crosshair') "tile pointer: $($look.tileCursor)"
        Check "draw zone, board cue: while it is on the pointer over an empty cell is a crosshair in $theme" ($look -and $look.cellCursor -ceq 'crosshair') "cell pointer: $($look.cellCursor)"
        if (Dz-On $on) { [void](Dz-Press $ws 'off') }
      }
    } finally { Reset-Look $ws }
  }

  # Option, the idle hint (item 5 of the notes): one sentence added to the hint a user reads before pressing anything.
  Case 'draw zone, idle hint: the hint also says to drag across empty cells to draw a zone' {
    Put-Split (Split-Json 5 2 @(Split-Pin 0 @(0)))
    $opened = Dz-Open $ws $oneWinSnap
    Check 'draw zone, idle hint: the page opens on Focus with one window pinned (control)' $opened 'the page did not open on Focus in time'
    if (-not $opened) { return }
    $r = Dz-Read $ws
    Check 'draw zone, idle hint: the hint starts with the live hint of today (control)' ($r -and ([string]$r.hint).StartsWith($dzIdleHint)) "hint reads: '$($r.hint)'"
    Check 'draw zone, idle hint: the hint ends with: Drag across empty cells to draw a zone.' ($r -and $r.hint -ceq ($dzIdleHint + ' Drag across empty cells to draw a zone.')) "hint reads: '$($r.hint)'"
  }

  # Shift+click two-corner path, with Draw Zone armed (the notes' item 1: the drag path is the main path, and the Shift path stays). A control
  # first, with Draw Zone off: a Shift+click on cell 2 sets the first corner and a Shift+click on cell 4 opens the New Zone dialog for 3 columns.
  # Then the subject: the same two corners with Draw Zone armed, and after the zone is added Draw Zone reads not pressed, with no armed hint,
  # no armed status line and no armed cue on an empty cell.
  Case 'draw zone, Shift path: with it armed, two Shift+clicks draw a zone, and after it Draw Zone reads not pressed, with no armed hint or cue' {
    Put-Split (Split-Json 5 2 @(Split-Pin 0 @(0)))
    $opened = Dz-Open $ws $oneWinSnap
    Check 'draw zone, Shift path: the page opens on Focus with one window pinned (control)' $opened 'the page did not open on Focus in time'
    if (-not $opened) { return }
    $a = Cell-Point $ws 2; $b = Cell-Point $ws 4
    $drawn = [bool]($null -ne $a -and $null -ne $b)
    Check 'draw zone, Shift path: cells 2 and 4 are drawn (scope)' $drawn 'a cell is not drawn on the ultrawide'
    if (-not $drawn) { return }
    Click-At $ws $a.x $a.y 8
    $corner = WaitFor $ws 'document.getElementById("msg").textContent.includes("Zone corner at")' 10
    Check 'draw zone, Shift path: with it off, a Shift+click on cell 2 sets the first corner (control)' $corner 'no "Zone corner at" status after the first Shift+click'
    Click-At $ws $b.x $b.y 8
    $dlg = WaitFor $ws $dzNewZoneCond 10
    Check 'draw zone, Shift path: with it off, a Shift+click on cell 4 opens the New Zone dialog for 3 columns (control)' $dlg 'no New Zone dialog after the second Shift+click'
    if (-not $dlg) { return }
    [void](Dz-CloseDialog $ws)
    # The subject: Draw Zone armed, then the same two Shift+clicks.
    $on = Dz-Press $ws 'on'
    Check 'draw zone, Shift path: a press arms it before the corners are picked (scope)' (Dz-On $on) "aria-pressed reads: '$($on.pressed)'"
    if (-not (Dz-On $on)) { return }
    Click-At $ws $a.x $a.y 8
    Click-At $ws $b.x $b.y 8
    $dlg = WaitFor $ws $dzNewZoneCond 10
    Check 'draw zone, Shift path: with it armed, the two Shift+clicks open the New Zone dialog for 3 columns (scope)' $dlg 'no New Zone dialog after the two Shift+clicks'
    if (-not $dlg) { return }
    $before = Dz-Posts $ws
    Confirm-Ask $ws
    [void](WaitFor $ws ('window.__h.posts("layout").length > ' + $before) 10)
    $sent = Layout-Posts-After $ws $before
    Check 'draw zone, Shift path: Add Zone sends one POST /layout (scope)' ($sent.Count -eq 1) "POST /layout count: $($sent.Count)"
    $r = Dz-Read $ws
    Check 'draw zone, Shift path: after the zone is added Draw Zone reads not pressed (aria-pressed false)' ($r.pressed -ceq 'false') "aria-pressed reads: '$($r.pressed)'"
    Check 'draw zone, Shift path: after the zone is added the hint is not the armed hint, and starts with the idle hint' ($r.hint -cne $dzArmedHint -and ([string]$r.hint).StartsWith($dzIdleHint)) "hint reads: '$($r.hint)'"
    Check 'draw zone, Shift path: after the zone is added the status line is not the armed status' ($r.msg -cne $dzArmedStatus) "status reads: '$($r.msg)'"
    Check 'draw zone, Shift path: after the zone is added Pick Cells by Menu is not shown' (-not $r.menuShown) 'a Pick Cells by Menu button is shown after the zone is added'
    $cue = Js $ws $cueJs
    Check 'draw zone, Shift path: after the zone is added an empty cell has no armed cue (no blue edge, no blue tint, no crosshair)' ($cue -and -not $cue.edgeBlue -and -not $cue.tintBlue -and $cue.cellCursor -cne 'crosshair') "edge $($cue.edgeStyle) $($cue.edge), tint blue $($cue.tintBlue), cell pointer $($cue.cellCursor)"
  }

  # Pick Cells by Menu, pressed as a mouse presses it: it opens the corner dialog, Draw Zone reads not pressed while the dialog is open, and
  # when the dialog closes focus is on the Draw Zone button.
  Case 'draw zone, menu: Pick Cells by Menu turns Draw Zone off, and focus returns to Draw Zone when the dialog closes' {
    Put-Split (Split-Json 5 2 @(Split-Pin 0 @(0)))
    $opened = Dz-Open $ws $oneWinSnap
    Check 'draw zone, menu: the page opens on Focus with one window pinned (control)' $opened 'the page did not open on Focus in time'
    if (-not $opened) { return }
    $on = Dz-Press $ws 'on'
    Check 'draw zone, menu: a press arms it before the menu is used (scope)' (Dz-On $on) "aria-pressed reads: '$($on.pressed)'"
    if (-not (Dz-On $on)) { return }
    Check 'draw zone, menu: while it is on, Pick Cells by Menu is shown on the board bar (scope)' ([bool]$on.menuShown) 'no Pick Cells by Menu button on the board bar'
    if (-not $on.menuShown) { return }
    $at = Js $ws $dzMenuJs
    Click-At $ws $at.x $at.y
    $opens = WaitFor $ws 'document.getElementById("dlg").open && /Draw a Zone on/.test((document.getElementById("dlgform") || {}).textContent || "")' 10
    Check 'draw zone, menu: Pick Cells by Menu opens the Draw a Zone dialog (scope)' $opens 'no Draw a Zone dialog after the press'
    if (-not $opens) { return }
    $during = Dz-Read $ws
    Check 'draw zone, menu: Pick Cells by Menu turns Draw Zone off (aria-pressed false while the dialog is open)' ($during.pressed -ceq 'false') "aria-pressed reads: '$($during.pressed)'"
    [void](Dz-CloseDialog $ws)
    $focused = WaitFor $ws 'document.activeElement !== null && document.activeElement.id === "zadd"' 10
    Check 'draw zone, menu: after the dialog closes, focus is on the Draw Zone button' $focused "focus is on: $(Js $ws 'return document.activeElement ? (document.activeElement.id || document.activeElement.tagName) : null')"
    $after = Dz-Read $ws
    Check 'draw zone, menu: after the dialog closes Draw Zone still reads not pressed, with the idle hint' ($after.pressed -ceq 'false' -and ([string]$after.hint).StartsWith($dzIdleHint)) "aria-pressed reads: '$($after.pressed)', hint reads: '$($after.hint)'"
  }

  # Status line, a canceled New Zone dialog. The turn-off is checked first (scope), so a failure on the status line is not a failure to turn off.
  Case 'draw zone, status: after a canceled New Zone dialog turns it off, the status line no longer says Draw Zone is on' {
    Put-Split (Split-Json 5 2 @(Split-Pin 0 @(0)))
    $opened = Dz-Open $ws $oneWinSnap
    Check 'draw zone, status: the page opens on Focus with one window pinned (control)' $opened 'the page did not open on Focus in time'
    if (-not $opened) { return }
    $on = Dz-Press $ws 'on'
    Check 'draw zone, status: a press arms it before the zone is drawn (scope)' (Dz-On $on) "aria-pressed reads: '$($on.pressed)'"
    if (-not (Dz-On $on)) { return }
    Check 'draw zone, status: while it is on the status line reads the armed status (scope)' ($on.msg -ceq $dzArmedStatus) "status reads: '$($on.msg)'"
    $a = Cell-Point $ws 2; $b = Cell-Point $ws 4
    Check 'draw zone, status: cells 2 and 4 are drawn (scope)' ($null -ne $a -and $null -ne $b) 'a cell is not drawn on the ultrawide'
    if ($null -eq $a -or $null -eq $b) { return }
    Drag-At $ws $a.x $a.y $b.x $b.y
    $dlg = WaitFor $ws $dzNewZoneCond 10
    Check 'draw zone, status: a drag across cells 2 to 4 while it is on opens the New Zone dialog (scope)' $dlg 'no New Zone dialog after the drag'
    if (-not $dlg) { return }
    [void](Dz-CloseDialog $ws)
    $r = Dz-Read $ws
    Check 'draw zone, status: after the zone dialog is canceled Draw Zone reads not pressed (scope)' ($r.pressed -ceq 'false') "aria-pressed reads: '$($r.pressed)'"
    if ($r.pressed -cne 'false') { return }
    Check 'draw zone, status: after the zone dialog is canceled the status line does not say Draw Zone is on' (-not ([string]$r.msg).Contains('Draw Zone is on')) "status reads: '$($r.msg)'"
  }

  # Status line, Pick Cells by Menu. Its dialog is closed with Cancel, and then the status line is read.
  Case 'draw zone, status: after Pick Cells by Menu turns it off and its dialog closes, the status line no longer says Draw Zone is on' {
    Put-Split (Split-Json 5 2 @(Split-Pin 0 @(0)))
    $opened = Dz-Open $ws $oneWinSnap
    Check 'draw zone, status, menu: the page opens on Focus with one window pinned (control)' $opened 'the page did not open on Focus in time'
    if (-not $opened) { return }
    $on = Dz-Press $ws 'on'
    Check 'draw zone, status, menu: a press arms it before the menu is used (scope)' (Dz-On $on) "aria-pressed reads: '$($on.pressed)'"
    if (-not (Dz-On $on)) { return }
    Check 'draw zone, status, menu: while it is on, Pick Cells by Menu is shown on the board bar (scope)' ([bool]$on.menuShown) 'no Pick Cells by Menu button on the board bar'
    if (-not $on.menuShown) { return }
    $at = Js $ws $dzMenuJs
    Click-At $ws $at.x $at.y
    $opens = WaitFor $ws 'document.getElementById("dlg").open && /Draw a Zone on/.test((document.getElementById("dlgform") || {}).textContent || "")' 10
    Check 'draw zone, status, menu: Pick Cells by Menu opens the Draw a Zone dialog (scope)' $opens 'no Draw a Zone dialog after the press'
    if (-not $opens) { return }
    [void](Dz-CloseDialog $ws)
    $after = Dz-Read $ws
    Check 'draw zone, status, menu: after the dialog closes Draw Zone reads not pressed (scope)' ($after.pressed -ceq 'false') "aria-pressed reads: '$($after.pressed)'"
    if ($after.pressed -cne 'false') { return }
    Check 'draw zone, status, menu: after the dialog closes the status line does not say Draw Zone is on' (-not ([string]$after.msg).Contains('Draw Zone is on')) "status reads: '$($after.msg)'"
  }

  # Bar height, 1024 and 1440. The bar keeps its idle height while Draw Zone is on, so the board does not rescale.
  Case 'draw zone, bar height: while it is on, the board bar is as tall as it is idle, at 1024 and at 1440' {
    Put-Split (Split-Json 5 2 @(Split-Pin 0 @(0)))
    $opened = Dz-Open $ws $oneWinSnap
    Check 'draw zone, bar height: the page opens on Focus with one window pinned (control)' $opened 'the page did not open on Focus in time'
    if (-not $opened) { return }
    try {
      foreach ($w in 1024, 1440) {
        Set-View $ws $w 900
        [void](Js $ws 'await window.__h.settle(); return true')
        $idle = Dz-Read $ws
        $idleH = Js $ws 'return document.getElementById("bbar").offsetHeight'
        Check "draw zone, bar height: at $w the Draw Zone button is shown and not pressed before a press (scope)" ($idle -and $idle.shown -and $idle.pressed -ceq 'false') "shown $($idle.shown), aria-pressed $($idle.pressed)"
        $on = Dz-Press $ws 'on'
        Check "draw zone, bar height: at $w a press arms it (scope)" (Dz-On $on) "aria-pressed reads: '$($on.pressed)'"
        if (Dz-On $on) {
          $armedH = Js $ws 'return document.getElementById("bbar").offsetHeight'
          Check "draw zone, bar height: at $w the armed board bar is as tall as the idle one" ($armedH -eq $idleH) "idle $idleH px, armed $armedH px"
          [void](Dz-Press $ws 'off')
        }
      }
    } finally { Fix-View $ws }
  }

  # Window click while armed. A still click on a window selects that window, and Draw Zone stays on: the click is a window's, not a cell's.
  Case 'draw zone, window click: while it is on, a still click on a window selects it and leaves Draw Zone on' {
    Put-Split (Split-Json 5 2 $dzPins)
    $opened = Dz-Open $ws $tenWinSnap
    Check 'draw zone, window click: the page opens on Focus with ten windows on ten cells (control)' $opened 'the page did not open on Focus in time'
    if (-not $opened) { return }
    $on = Dz-Press $ws 'on'
    Check 'draw zone, window click: a press arms it before the click (scope)' (Dz-On $on) "aria-pressed reads: '$($on.pressed)'"
    if (-not (Dz-On $on)) { return }
    $t = Tile-Centre $ws 1001
    $reach = [bool]($t -and $t.hit)
    Check 'draw zone, window click: window 1001 is drawn, and a press lands on its tile (scope)' $reach 'a tile is not drawn, or the press hits a button in it'
    if (-not $reach) { return }
    Click-At $ws $t.x $t.y
    $selected = WaitFor $ws 'selWin === 1001' 10
    Check 'draw zone, window click: a still click on window 1001 while it is on selects window 1001' $selected "selected window: $(Js $ws 'return typeof selWin === "undefined" ? null : selWin')"
    $r = Dz-Read $ws
    Check 'draw zone, window click: after the click Draw Zone still reads pressed (aria-pressed true)' (Dz-On $r) "aria-pressed reads: '$($r.pressed)'"
  }

  # Forced colors. The pressed button's label must differ from its fill, or the label does not show. The page is read with forced colors on.
  Case 'draw zone, forced colors: while it is on, the pressed button label is not the same colour as its fill' {
    Put-Split (Split-Json 5 2 @(Split-Pin 0 @(0)))
    $opened = Dz-Open $ws $oneWinSnap
    Check 'draw zone, forced colors: the page opens on Focus with one window pinned (control)' $opened 'the page did not open on Focus in time'
    if (-not $opened) { return }
    $on = Dz-Press $ws 'on'
    Check 'draw zone, forced colors: a press arms it before forced colors are on (scope)' (Dz-On $on) "aria-pressed reads: '$($on.pressed)'"
    if (-not (Dz-On $on)) { return }
    $lookJs = 'const z = document.getElementById("zadd"); if (!z) return null; const c = getComputedStyle(z); return { forced: matchMedia("(forced-colors: active)").matches, pressed: z.getAttribute("aria-pressed"), label: c.color, fill: c.backgroundColor };'
    try {
      Set-Forced $ws $true
      $look = Js $ws $lookJs
      Check 'draw zone, forced colors: the page reads forced colors as active (scope)' ($look -and $look.forced -eq $true) "forced-colors active: $($look.forced)"
      if (-not ($look -and $look.forced -eq $true)) { return }
      Check 'draw zone, forced colors: the pressed Draw Zone button still reads pressed (scope)' ($look.pressed -ceq 'true') "aria-pressed reads: '$($look.pressed)'"
      Check 'draw zone, forced colors: the pressed Draw Zone label is not the same colour as its fill' ($look.label -cne $look.fill) "label $($look.label), fill $($look.fill)"
    } finally { Set-Forced $ws $false }
  }

  # Phone width, 390 (the phone layout is 760 px and under). The bar is no taller while Draw Zone is on, so the board does not rescale.
  Case 'draw zone, phone: at 390 wide the board bar is no taller while it is on than it is idle' {
    Put-Split (Split-Json 5 2 @(Split-Pin 0 @(0)))
    $opened = Dz-Open $ws $oneWinSnap
    Check 'draw zone, phone: the page opens on Focus with one window pinned (control)' $opened 'the page did not open on Focus in time'
    if (-not $opened) { return }
    try {
      Set-View $ws 390 844
      [void](Js $ws 'await window.__h.settle(); return true')
      $idle = Dz-Read $ws
      $ready = [bool]($idle -and $idle.shown -and -not $idle.disabled)
      Check 'draw zone, phone: at 390 Draw Zone is shown and enabled before a press (scope)' $ready "shown $($idle.shown), disabled $($idle.disabled)"
      if (-not $ready) { return }
      $idleH = Js $ws 'return document.getElementById("bbar").offsetHeight'
      $on = Dz-Press $ws 'on'
      Check 'draw zone, phone: at 390 a press arms it (scope)' (Dz-On $on) "aria-pressed reads: '$($on.pressed)'"
      if (-not (Dz-On $on)) { return }
      $armedH = Js $ws 'return document.getElementById("bbar").offsetHeight'
      Check 'draw zone, phone: at 390 the armed board bar is no taller than the idle one' ($armedH -le $idleH) "idle $idleH px, armed $armedH px"
    } finally { Fix-View $ws }
  }

} catch {
  $script:fail++; "FAIL  page cases stopped: $($_.Exception.Message)"
  # A throw with the socket still Open is no drop, so only a socket that is not Open is noted here.
  if ($edgeLaunches -and $ws -and $ws.State -ne [Net.WebSockets.WebSocketState]::Open) { Note-EdgeDrop $ws 'outside a case' }
} finally {
  try { if ($ws) { $ws.Dispose() } } catch { }
  Show-EdgeNote
  Stop-Edge
  if ($srv -and -not $srv.HasExited) {
    try { [void](Invoke-WebRequest -UseBasicParsing "$($url)quit" -Method Post -Body 'quit') } catch { }
    if (-not $srv.WaitForExit(5000)) { $srv.Kill() }
  }
  foreach ($k in $saved.Keys) { if ($null -eq $saved[$k]) { Remove-Item "env:$k" -ErrorAction SilentlyContinue } else { Set-Item "env:$k" $saved[$k] } }
  Keep-EdgeLogs
  Remove-Item -LiteralPath $runDir -Recurse -Force -ErrorAction SilentlyContinue
}
Shard-Report 'setup-page'
if ($script:fail) { "$($script:fail) check(s) failed."; exit 1 } else { 'All checks passed.' }
