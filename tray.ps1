# Tile Windows tray agent: an icon in the notification area.
#   Menu: Open Tile Windows, Apply Scene >, Quit. Double-click opens the app.
#   Applies scenes on their trigger: a schedule (days + time), when the plugged-in setup changes, or when a
#   Teams call starts (and, if the scene says so, goes back to the scene before when the call ends).
#   Also runs the per-scene switches in scene.auto (see README, Triggers): desk, window, activity, size, gaps, offer, setup, noext, grid.
# -Open: open the app (starts the agent first if it is not running).
# -NoIcon: run without the icon (tests). -NoApply: every apply is a dry run (tests).
# -Lib: define the functions and return (tests dot-source it).
# -Link <tilewindows://...>: what the link handler passes (install.ps1 registers it). undo?run=<id> puts a run's windows back; open opens the app.
# One agent per profile. Signal the Quit event (as uninstall.ps1 does) to stop it.
param([switch]$Open, [switch]$NoIcon, [switch]$NoApply, [switch]$Lib, [string]$Link = '')
. (Join-Path $PSScriptRoot 'config.ps1')

# Named objects are per profile, so a test profile never talks to the real agent.
function TrayName([string]$kind) {
  $h = [BitConverter]::ToString([Security.Cryptography.MD5]::Create().ComputeHash([Text.Encoding]::UTF8.GetBytes($TileHome.ToLowerInvariant()))).Replace('-', '').Substring(0, 12)
  "Local\TileWindows-$kind-$h"
}
# Scenes due now on a schedule. $fired: scene id -> 'yyyy-MM-dd HH:mm' last fired, so a scene fires once a minute at most.
function Get-DueScenes($config, [datetime]$now, $fired) {
  $stamp = $now.ToString('yyyy-MM-dd HH:mm'); $day = [int]$now.DayOfWeek; $hm = $now.ToString('HH:mm')
  @($config.scenes | ? { $_.trigger.type -eq 'time' -and @($_.trigger.days) -contains $day -and $_.trigger.time -eq $hm -and $fired[$_.id] -ne $stamp })
}
# The monitor set as one string: a change in it fires 'display' scenes. Monitors that carry an id (tile.ps1 -Monitors) give the setup key,
# so a rearranged or rescaled set is the same key (decision monitor-setups, item 4). Objects with no id (a Windows screen list) give the
# bounds string, where a move changes the key.
function Get-MonitorKey($screens) {
  if (-not @($screens | ? { $_ }).Count) { return '' }  # no read (a failed one): no key, so nothing fires
  $k = Get-TileKnownSetupKey $screens; if ($k) { return $k }
  (@($screens | % { "$($_.DeviceName)=$($_.Bounds.Width)x$($_.Bounds.Height)@$($_.Bounds.X),$($_.Bounds.Y)" }) | Sort-Object) -join ';'
}
function Get-DisplayScenes($config) { @($config.scenes | ? { $_.trigger.type -eq 'display' }) }

# Is a Teams call on? $mic: [{name, stop}] from Windows' microphone privacy store (Get-MicUsage); stop = 0
# means the app holds the microphone now. A Teams app holding it is a call. So is a browser (Edge, Chrome) holding
# it while that browser has a window titled in Teams' meeting form plus the browser's own suffix: a mic alone
# is not Teams, and a window alone is not a call. $null means the store could not be read: only then do the
# Teams app's window titles decide, and only a title in Teams' own meeting-window form counts.
$TileMeetingTitle = '(meeting|call)( (with|in) [^|]+)? \| Microsoft Teams'
# Does a browser (or the named exe) hold the microphone now?
function Test-BrowserMic($mic, [string]$app = '') {
  $exe = if ($app) { [regex]::Escape($app) } else { '(msedge|chrome)' }
  [bool]@($mic | ? { $_.name -match "(?i)(^|[#\\])$exe\.exe$" -and [int64]$_.stop -eq 0 }).Count
}
function Test-TeamsCall($mic, $wins) {
  if ($null -ne $mic) {
    if (@($mic | ? { $_.name -match '(?i)(^|[#\\])(ms-teams|teams)\.exe$|^MSTeams_' -and [int64]$_.stop -eq 0 }).Count) { return $true }
    return [bool]@($wins | ? { $_.app -match '(?i)^(msedge|chrome)$' -and $_.title -match "(?i)^$TileMeetingTitle - (Microsoft Edge|Google Chrome)$" -and (Test-BrowserMic $mic $_.app) }).Count
  }
  [bool]@($wins | ? { $_.app -match '(?i)^(ms-teams|teams)$' -and $_.title -match "(?i)^$TileMeetingTitle$" }).Count
}
# ---- Triggers beyond the schedule: each one a pure function of its inputs. Win32 signals feed them in the tick below. ----
# The per-scene switches. Each is off unless the scene's .auto sets it true. The page's trigger editor lists the same names (a test checks).
$TileAutoFlags = @('desk', 'window', 'activity', 'size', 'gaps', 'offer', 'setup', 'noext', 'grid')
function Test-Auto($sc, [string]$flag) { [bool]($sc -and $sc.auto -and $sc.auto.$flag) }
# Does any scene apply itself? Then the tray reads the call state, which the in-call guard needs.
function Test-AnyAuto($cfg) { [bool]@($cfg.scenes | ? { $sc = $_; ($sc.trigger.type -and $sc.trigger.type -ne 'manual') -or @($TileAutoFlags | ? { Test-Auto $sc $_ }).Count }).Count }
function Get-Scene($cfg, [string]$id) { if ($id) { @($cfg.scenes | ? { $_.id -eq $id })[0] } }
function Get-AutoScenes($cfg, [string]$flag) { @($cfg.scenes | ? { Test-Auto $_ $flag }) }
# The activity map, the meeting-size rule and the threshold defaults: the config's own, else the starters' (a config from before they existed has none).
function Get-Tcfg($cfg) {
  if (-not $script:TileStarterCfg) { $script:TileStarterCfg = ConvertFrom-Json ([IO.File]::ReadAllText($TileStarters, $TileUtf8)) }
  $d = $script:TileStarterCfg
  [pscustomobject]@{ activity = @($(if ($cfg.activity) { $cfg.activity } else { $d.activity })); size = $(if ($cfg.meetingSize) { $cfg.meetingSize } else { $d.meetingSize }); optDefaults = $(if ($cfg.optDefaults) { $cfg.optDefaults } else { $d.optDefaults }) }
}
# A threshold the owner can edit: the scene's own value (scene.opt.<switch>.<name>), else the default from optDefaults.
# A value that does not read as a positive number (a hand edit) falls back to the default; a value over its cap is held at the cap.
function Get-Opt($cfg, $sc, [string]$flag, [string]$name) {
  $k = "$flag.$name"; $o = (Get-Tcfg $cfg).optDefaults
  $def = Read-Num $o.$flag.$name ([double]$script:TileStarterCfg.optDefaults.$flag.$name) $k
  $v = $sc.opt.$flag.$name; if ($null -ne $v -and "$v" -ne '') { return (Read-Num $v $def $k) }
  $def
}
# The cap on each threshold. The page's AUTO list caps its boxes at the same values (a test checks).
$TileOptMax = @{ 'desk.lockMin' = 240; 'desk.idleMin' = 240; 'window.holdSec' = 60; 'activity.dwellSec' = 3600; 'activity.graceMin' = 240
  'grid.at' = 20; 'size.at' = 500; 'offer.leadMin' = 30; 'gaps.minutes' = 480; 'noext.sec' = 600 }
function Read-Num($v, [double]$def, [string]$key) {
  $n = 0.0; if (-not [double]::TryParse("$v", [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$n) -or $n -le 0) { return $def }
  [Math]::Min($n, $TileOptMax[$key])
}
function ConvertTo-Bool($v) { if ($v -is [bool]) { return $v }; if ($v -is [string]) { return $v.Trim().ToLower() -in 'true', 'yes', '1' }; if ($null -eq $v) { return $false }; [bool]($v -is [ValueType] -and $v -ne 0) }
# Today's meetings from agenda.json's parsed text: [{start, end, attendees, teams, showAs}], or $null when there is no agenda or it is not
# for today. Every agenda trigger does nothing on $null. An event with a start, end or attendee count that does not read is dropped.
function Get-TodayAgenda($raw, [datetime]$now) {
  if (-not $raw) { return $null }
  $d = if ($raw.date -is [datetime]) { $raw.date.ToString('yyyy-MM-dd') } else { "$($raw.date)" }
  if ($d -ne $now.ToString('yyyy-MM-dd')) { return $null }
  , @(@($raw.events) | % { try { $e = [pscustomobject]@{ start = [datetime]$_.start; end = [datetime]$_.end; attendees = [int]$_.attendees; teams = ConvertTo-Bool $_.teams; showAs = "$($_.showAs)".ToLower() }; if ($e.end -gt $e.start -and $e.attendees -ge 0) { $e } } catch {} })
}
function Test-Busy($e) { $e.showAs -in 'busy', 'oof' }
# The scene for a meeting of this size: Listen from its 'size' threshold up (the meeting-size rule's, unless Listen sets its own), else Meetings.
# A call applies it only when that scene's size switch is on; the offer needs only the scene's offer switch.
function Get-SizeId($cfg, [int]$attendees) {
  $t = (Get-Tcfg $cfg).size; $big = Get-Scene $cfg $t.big
  $at = Read-Num $big.opt.size.at (Read-Num $t.at ([double]$script:TileStarterCfg.meetingSize.at) 'size.at') 'size.at'
  if ($attendees -ge $at) { $t.big } else { $t.small }
}
function Get-SizeScene($cfg, [int]$attendees) { $id = Get-SizeId $cfg $attendees; if (Test-Auto (Get-Scene $cfg $id) 'size') { $id } else { '' } }
# The Teams meeting on now (up to 10 minutes early); the one that started last wins.
function Get-NowMeeting($ev, [datetime]$now) { @($ev | ? { $_.teams -and (Test-Busy $_) -and $now -ge $_.start.AddMinutes(-10) -and $now -le $_.end } | Sort-Object start)[-1] }

# What a change in call state does. Returns {apply: scene id or '', back: scene id to remember}.
# Call starts: apply $pick (the scene for the meeting's size), else the first 'call' scene, and remember the scene on screen.
# Call ends: if the first 'call' scene has trigger.back, apply the remembered one.
function Step-CallTrigger([bool]$was, [bool]$now, $config, [string]$active, [string]$before, [string]$pick = '') {
  $s = @($config.scenes | ? { $_.trigger.type -eq 'call' })[0]
  if ((-not $s -and -not $pick) -or $was -eq $now) { return [pscustomobject]@{ apply = ''; back = $before } }
  $to = if ($pick) { $pick } else { $s.id }
  if ($now) { return [pscustomobject]@{ apply = $to; back = $(if ($active -ne $to) { $active } else { $before }) } }
  [pscustomobject]@{ apply = $(if ($s.trigger.back -and $before -and @($config.scenes.id) -contains $before) { $before } else { '' }); back = '' }
}

# Does a scene place this app? A pin names it, or the fill takes it unless fill.off is set ('*' = any app not skipped).
function Test-SceneApp($sc, [string]$app) {
  if (@($sc.pins | ? { $app -like $_.app }).Count) { return $true }
  if ($sc.fill.off) { return $false }
  foreach ($a in @($sc.fill.apps)) { if ($a -eq '*') { if (-not @($sc.fill.skip | ? { $app -like $_ }).Count) { return $true } } elseif ($app -like $a) { return $true } }
  $false
}
function New-Cand([string]$id, [string]$why, [string]$kind, $commit = $null) { [pscustomobject]@{ id = $id; why = $why; kind = $kind; offer = $false; commit = $commit; exp = $null; gen = $null } }
# New window finds its place: a window of a scene app, 400x300 or bigger, that appears and holds (3 s unless the scene says) re-flows the active scene.
# $wins: the window list, or $null when not read this tick. The first list only seeds $s.known.
function Step-NewWindow($s, [datetime]$now, $cfg, $wins, [string]$active) {
  if ($null -eq $wins) { return }
  $by = @{}; foreach ($w in $wins) { $by["$($w.id)"] = $w }
  $sc = Get-Scene $cfg $active; $on = Test-Auto $sc 'window'
  $seed = $null -eq $s.known
  if ($seed) { $s.known = @{} }
  foreach ($k in @($by.Keys)) {
    if ($s.known.ContainsKey($k)) { continue }
    $s.known[$k] = $true; $w = $by[$k]
    if (-not $seed -and $on -and (Test-SceneApp $sc $w.app)) { $s.newSeen[$k] = $now }
  }
  foreach ($k in @($s.known.Keys)) { if (-not $by.ContainsKey($k)) { $s.known.Remove($k) } }
  foreach ($k in @($s.newSeen.Keys)) { $w = $by[$k]; if (-not $on -or -not $w -or $w.min -or [int]$w.w -lt 400 -or [int]$w.h -lt 300) { $s.newSeen.Remove($k) } }
  $hold = Get-Opt $cfg $sc 'window' 'holdSec'
  if (@($s.newSeen.Keys | ? { ($now - $s.newSeen[$_]).TotalSeconds -ge $hold }).Count) { $st = $s; New-Cand $active 'because a new window opened' 'window' ({ $st.newSeen = @{} }.GetNewClosure()) }
}
# Activity snap: one kind of app in front for a minute (or the scene's own), and the layout is not the scene that suits it. $fg: {app, title}, or
# $null when not read. Not within 15 minutes (or the scene's own) of a scene you applied by hand.
function Step-Activity($s, [datetime]$now, $cfg, $fg, [string]$active) {
  if ($null -eq $fg) { return }
  $map = @((Get-Tcfg $cfg).activity); $idx = -1
  for ($i = 0; $i -lt $map.Count; $i++) { if ($fg.app -like $map[$i].app -and (-not $map[$i].title -or $fg.title -match $map[$i].title)) { $idx = $i; break } }
  if (-not $s.act -or $s.act.key -ne "$idx") { $s.act = [pscustomobject]@{ key = "$idx"; since = $now; done = $false } }
  if ($idx -lt 0 -or $s.act.done) { return }
  $to = $map[$idx].scene; $sc = Get-Scene $cfg $to
  if (-not (Test-Auto $sc 'activity')) { return }
  if ($active -eq $to) { $s.act.done = $true; return }
  if (($now - $s.manualApplyAt).TotalMinutes -lt (Get-Opt $cfg $sc 'activity' 'graceMin')) { return }
  if (($now - $s.act.since).TotalSeconds -ge (Get-Opt $cfg $sc 'activity' 'dwellSec')) { $a = $s.act; New-Cand $to 'because of what you are working in' 'activity' ({ $a.done = $true }.GetNewClosure()) }
}
# Focus in gaps: a next busy meeting is 60+ minutes off (or the scene's own), none is on now, and input was within 2 minutes. Once per gap.
# With no meeting left it does nothing, and it never follows a call's end within 10 minutes (the call's back scene stays).
function Step-Gaps($s, [datetime]$now, $cfg, $ev, [double]$idle, [bool]$locked, [string]$active) {
  $f = @(Get-AutoScenes $cfg 'gaps')[0]
  if ($null -eq $ev -or -not $f -or $locked -or $idle -ge 120 -or ($now - $s.callEndAt).TotalMinutes -lt 10) { return }
  $busy = @($ev | ? { Test-Busy $_ })
  if (@($busy | ? { $_.start -le $now -and $now -lt $_.end }).Count) { return }
  $next = @($busy | ? { $_.start -gt $now } | Sort-Object start)[0]
  if (-not $next -or ($next.start - $now).TotalMinutes -lt (Get-Opt $cfg $f 'gaps' 'minutes')) { return }
  $k = $next.start.ToString('s')
  if ($s.gapKey -eq $k) { return }
  if ($active -eq $f.id) { $s.gapKey = $k; return }
  $st = $s; New-Cand $f.id 'because there is a gap before the next meeting' 'gaps' ({ $st.gapKey = $k }.GetNewClosure())
}
# No external monitor for 30 s (or the scene's own): one screen left, then the laptop scene. $n: screen count, or $null when not read. The first
# reading only seeds. A locked or idle PC does not count (a sleeping monitor drops out), and a monitor-set scene applied in the last
# minute is the same event, so this does nothing.
function Step-NoExternal($s, [datetime]$now, $cfg, $n, [string]$active, [double]$idle, [bool]$locked) {
  if ($null -eq $n) { return }
  if ($n -gt 1) { $s.soloSince = $null; $s.soloDone = $false; $s.screensSeen = $true; return }
  if (-not $s.screensSeen) { $s.screensSeen = $true; $s.soloDone = $true }
  if ($locked -or $idle -ge 120) { $s.soloSince = $null; return }
  if (-not $s.soloSince) { $s.soloSince = $now }
  $sc = @(Get-AutoScenes $cfg 'noext')[0]
  if ($s.soloDone -or -not $sc -or ($now - $s.soloSince).TotalSeconds -lt (Get-Opt $cfg $sc 'noext' 'sec')) { return }
  if ($active -eq $sc.id -or ($now - $s.displayAt).TotalSeconds -lt 60) { $s.soloDone = $true; return }
  $st = $s; New-Cand $sc.id 'because the external monitors are gone' 'noext' ({ $st.soloDone = $true }.GetNewClosure())
}
# The scene (with the config's category map attached, as Get-TileScene gives it) as JSON for tile.ps1 -Scene, its ultrawide grid swapped.
# The ultrawide is the monitor that holds the wide role (Get-TileRoles over $plugged, the monitors tile.ps1 -Monitors read), not the widest screen.
# The role template always gets the grid (tile.ps1's Pick takes the wide role from the same Get-TileRoles). A scene with its own layout for the plugged-in setup runs
# that layout by monitor id, so the grid goes there too, on the wide-role monitor's id, when the layout has a grid for it.
function Get-GridSceneJson($sc, $grid, $plugged = $null) {
  $full = ConvertFrom-Json (ConvertTo-Json -Depth 8 -Compress $sc); $full.grids.wide = $grid
  $key = Get-TileKnownSetupKey $plugged
  $own = Get-TileLayoutEntry $full $key
  if ($own) {
    $mons = [pscustomobject]@{}
    foreach ($m in @($plugged)) { $mons | Add-Member -NotePropertyName ([string]$m.id) -NotePropertyValue ([pscustomobject]@{ builtin = [bool]$m.builtin; bw = $m.bw; bh = $m.bh; w = $m.w; h = $m.h }) }
    $wide = (Get-TileRoles $mons @($plugged | % { [string]$_.id }))['wide']
    if ($wide -and $own.Value.grids -and $own.Value.grids.PSObject.Properties[$wide]) { $own.Value.grids.$wide = $grid }
  }
  ConvertTo-Json -Depth 8 -Compress $full
}
# Grid follows the Claude count: dense from 'at' Claude windows, roomy again at 'at' minus 2, and in between whatever it was ($prev), so a count
# that hovers at the line does not flap. $null when the scene has no switch or no claudeGrid.
function Get-ClaudeMode($sc, [int]$n, [string]$prev = '') {
  if (-not (Test-Auto $sc 'grid') -or -not $sc.claudeGrid) { return }
  $at = Read-Num $sc.claudeGrid.at 0 'grid.at'; if (-not $at) { return }
  if ($n -ge $at) { 'dense' } elseif ($n -le $at - 2) { 'roomy' } elseif ($prev) { $prev } else { 'roomy' }
}
function Get-ClaudeGrid($sc, [int]$n, [string]$prev = '') { $m = Get-ClaudeMode $sc $n $prev; if ($m) { $sc.claudeGrid.$m } }

function New-TrayState { [pscustomobject]@{ fired = @{}; lastKey = $null; inCall = $null; streak = 0; before = ''; callSet = $null
  pend = @(); lastAuto = [datetime]::MinValue; deskDay = ''; idled = $false; known = $null; newSeen = @{}; act = $null; gapKey = $null; offered = @{}; soloSince = $null; soloDone = $false; screensSeen = $false
  lastManual = [datetime]::MinValue; rects = $null; seenMove = [datetime]::MinValue; skipRead = $false; lastActive = $null; manualApplyAt = [datetime]::MinValue; autoApplied = ''; displayAt = [datetime]::MinValue; callEndAt = [datetime]::MinValue } }
$TileKindRank = @{ call = 0; display = 1; schedule = 2; desk = 3; window = 4; activity = 5; gaps = 6; noext = 7 }
# One tick of the agent, with no side effects but on $s. Returns the scenes to apply: [{id, why, kind, offer}].
# $key: the monitor key once the display has settled, else $null. $call: a call reading, or $null (not polled).
# The first key and the first call reading only seed $s, so starting the agent (or restarting it mid-call)
# applies nothing. A call starts or ends only after 2 readings in a row agree.
# $sig: the live signals {idleSec, locked, unlockedAfter, mouseDown, manualAt, wins, fg, screens, agenda}; $null runs only the
# schedule, display and call triggers, with no guards. With $sig, one pass of guards decides what may apply now:
#   during a call only the call trigger applies; nothing within 10 s of a manual move or while a mouse button is down;
#   at most one automatic apply per 30 s (the call trigger is exempt). A one-shot trigger that a guard holds back waits up to 60 s.
#   A manual move also cancels what was waiting before it (a dwell, a new window, a held one-shot), so nothing undoes the move.
function Step-Tray($s, [datetime]$now, $cfg, $key, $call, [string]$active, $sig = $null) {
  $ev = @(); $agenda = $null
  if ($sig) { $agenda = Get-TodayAgenda $sig.agenda $now }
  foreach ($x in (Get-DueScenes $cfg $now $s.fired)) { $s.fired[$x.id] = $now.ToString('yyyy-MM-dd HH:mm'); $ev += New-Cand $x.id 'on schedule' 'schedule' }
  if ($key) {
    # Use This Scene on This Setup: the scene whose setupKey is the plugged-in key. A key of ids ignores a rearrange, so only a change of monitors fires.
    $d = @(Get-AutoScenes $cfg 'setup' | ? { $_.setupKey -ceq $key })[0]; if (-not $d) { $d = @(Get-DisplayScenes $cfg)[0] }
    if ($s.lastKey -and $key -ne $s.lastKey -and $d) { $ev += New-Cand $d.id 'because the monitors changed' 'display' }
    $s.lastKey = $key
  }
  # A changed set of call scenes starts the call reading over (seed again, no pending streak).
  $set = (@($cfg.scenes | ? { $_.trigger.type -eq 'call' } | % { "$($_.id):$([bool]$_.trigger.back)" }) + @(Get-AutoScenes $cfg 'size' | % { "size:$($_.id)" })) -join ','
  if ($set -ne $s.callSet) { $s.callSet = $set; $s.inCall = $null; $s.streak = 0; $s.before = '' }
  if ($null -ne $call) {
    if ($null -eq $s.inCall) { $s.inCall = [bool]$call }
    elseif ([bool]$call -eq $s.inCall) { $s.streak = 0 }
    elseif (++$s.streak -ge 2) {
      $m = if ($call) { Get-NowMeeting $agenda $now }
      $st = Step-CallTrigger $s.inCall ([bool]$call) $cfg $active $s.before $(if ($m) { Get-SizeScene $cfg $m.attendees } else { '' })
      $s.inCall = [bool]$call; $s.streak = 0; $s.before = $st.back
      if (-not $call) { $s.callEndAt = $now }
      if ($st.apply) { $ev += New-Cand $st.apply $(if ($call) { 'because a Teams call started' } else { 'because the call ended' }) 'call' }
    }
  }
  if (-not $sig) { return @($ev | % { $_.commit = $null; $_ }) }

  # A scene on screen that this agent did not apply was applied by hand: activity snap keeps off it for a while.
  if ($null -eq $s.lastActive) { $s.lastActive = $active }
  elseif ($active -ne $s.lastActive) { if ($active -ne $s.autoApplied) { $s.manualApplyAt = $now }; $s.lastActive = $active }
  # A move the hook misses (keyboard, Win+Arrow, snap assist) shows as a changed rect on a window in two reads: it counts as a manual move at the read
  # that shows it. A window that opens or closes, a minimize or restore, or a list in another order is no move. The first read after an apply is only
  # compared against, never counted: the apply moved the windows (skipRead is set below, and by the tick after a gap-fill run).
  # A rect change also needs input at the read (idle under 10 s, as the desk trigger's back-at-desk test): Windows relocates windows with no input
  # (a monitor unplug, a DPI change, a window restoring its own bounds), and that is no manual move. The rects still update, so it is not counted later.
  if ($null -ne $sig.wins) {
    $rects = @{}; foreach ($w in $sig.wins) { $rects["$($w.id)"] = $w }
    if ($s.skipRead) { $s.skipRead = $false }
    elseif ($s.rects -and [double]$sig.idleSec -lt 10) {
      foreach ($k in @($rects.Keys)) {
        $o = $s.rects[$k]; $w = $rects[$k]
        if ($o -and -not $o.min -and -not $w.min -and ($o.x -ne $w.x -or $o.y -ne $w.y -or $o.w -ne $w.w -or $o.h -ne $w.h)) { $s.seenMove = $now; break }
      }
    }
    $s.rects = $rects
  }
  # A manual move cancels everything that was waiting before it.
  $ma = [datetime]$sig.manualAt; if ($s.seenMove -gt $ma) { $ma = $s.seenMove }
  if ($ma -gt $s.lastManual) { $s.lastManual = $ma; $s.pend = @($s.pend | ? { $_.kind -eq 'call' -or $_.gen -ge $ma }); $s.newSeen = @{}; $s.act = $null }

  # Return to the desk: an unlock after a 5 minute lock (or the scene's own) re-applies the active scene; the day's first unlock applies Default;
  # input after 10 idle minutes with no lock in between re-applies the active scene.
  $day = $now.ToString('yyyy-MM-dd'); $asc = Get-Scene $cfg $active
  if ($null -ne $sig.unlockedAfter) {
    $s.idled = $false; $first = $s.deskDay -ne $day; $s.deskDay = $day
    $to = if ($first -and (Test-Auto (Get-Scene $cfg 'default') 'desk')) { 'default' } elseif ([double]$sig.unlockedAfter -ge 60 * (Get-Opt $cfg $asc 'desk' 'lockMin') -and (Test-Auto $asc 'desk')) { $active }
    if ($to) { $ev += New-Cand $to 'because you are back at your desk' 'desk' }
  } elseif ([double]$sig.idleSec -ge 60 * (Get-Opt $cfg $asc 'desk' 'idleMin')) { $s.idled = $true }
  elseif ($s.idled -and [double]$sig.idleSec -lt 10) {
    $s.idled = $false
    if (Test-Auto $asc 'desk') { $ev += New-Cand $active 'because you are back at your desk' 'desk' }
  }
  # One-shot triggers wait out a guard for up to 60 s, then drop.
  foreach ($e in $ev) { $e.exp = $now.AddSeconds(60); $e.gen = $now }
  $s.pend = @(@($s.pend | ? { $_.exp -gt $now }) + $ev)

  # Offer a few minutes (2 unless the scene says) before a busy Teams meeting; it moves nothing, so no guard holds it. Once per meeting.
  $out = @()
  foreach ($e in @($agenda | ? { $_.teams -and (Test-Busy $_) -and $_.start -gt $now })) {
    $k = $e.start.ToString('s'); if ($s.offered[$k]) { continue }
    $id = Get-SizeId $cfg $e.attendees; $osc = Get-Scene $cfg $id
    if (-not (Test-Auto $osc 'offer') -or $now -lt $e.start.AddMinutes(-(Get-Opt $cfg $osc 'offer' 'leadMin'))) { continue }
    $s.offered[$k] = $true; $o = New-Cand $id 'a meeting starts soon' 'offer'; $o.offer = $true; $out += $o
  }

  $cand = @($s.pend) + @(Step-NewWindow $s $now $cfg $sig.wins $active) + @(Step-Activity $s $now $cfg $sig.fg $active) +
    @(Step-Gaps $s $now $cfg $agenda ([double]$sig.idleSec) ([bool]$sig.locked) $active) + @(Step-NoExternal $s $now $cfg $sig.screens $active ([double]$sig.idleSec) ([bool]$sig.locked))
  $cand = @($cand | ? { $_ })
  if ($s.inCall) { $s.pend = @($s.pend | ? { $_.kind -eq 'call' }); $cand = @($cand | ? { $_.kind -eq 'call' }) }
  $held = $sig.mouseDown -or ($now - $ma).TotalSeconds -lt 10
  if (-not $held) {
    $capped = ($now - $s.lastAuto).TotalSeconds -lt 30
    $pick = @($cand | ? { -not $capped -or $_.kind -eq 'call' } | Sort-Object { $TileKindRank[$_.kind] })[0]
    if ($pick) {
      if ($pick.commit) { & $pick.commit }
      $s.pend = @($s.pend | ? { $_ -ne $pick }); $s.lastAuto = $now; $s.autoApplied = $pick.id; $s.skipRead = $true; if ($pick.kind -eq 'display') { $s.displayAt = $now }; $out += $pick
    }
  }
  @($out | % { $_.commit = $null; $_ })
}
# Microphone use per app, from HKCU ...\CapabilityAccessManager\ConsentStore\microphone: desktop apps under
# NonPackaged (key name = exe path with # for \), Store apps (new Teams: MSTeams_8wekyb3d8bbwe) by package.
# $null when the store cannot be read.
function Get-MicUsage {
  $k = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\microphone'
  if (-not (Test-Path -LiteralPath $k)) { return $null }
  , @(Get-ChildItem -LiteralPath $k, "$k\NonPackaged" -ErrorAction SilentlyContinue | ? { $_.PSChildName -ne 'NonPackaged' } |
    % { $p = Get-ItemProperty -LiteralPath $_.PSPath -ErrorAction SilentlyContinue; if ($p -and $null -ne $p.LastUsedTimeStop) { [pscustomobject]@{ name = $_.PSChildName; stop = [int64]$p.LastUsedTimeStop } } })
}
function Get-TeamsWindows { @(Get-Process ms-teams, Teams, msedge, chrome -ErrorAction SilentlyContinue | ? { $_.MainWindowTitle } | % { [pscustomobject]@{ app = $_.Name; title = $_.MainWindowTitle } }) }
# ---- Run toast and Undo (decision run-undo). A run that moved windows shows one toast with an Undo button; the button opens
# tilewindows://undo?run=<id>, which signals this agent. The newest run only, until the next run or a restart: no timer.
# The AppUserModelID the Start shortcut carries (install.ps1), so the toast header says Tile Windows. Tag and group are one pair for every
# run toast, so a new run replaces the old toast on screen and in the centre.
$TileAppId = 'TileWindows.Tray'; $TileToastTag = 'tw-run'; $TileToastGroup = 'tile-windows'
# Reads and writes the AppUserModelID of a .lnk: install.ps1 sets it, and the tray reads it to know a toast will carry the app's name.
if (-not ('TileShortcut' -as [type])) { Add-Type -TypeDefinition @'
using System; using System.Runtime.InteropServices;
public static class TileShortcut {
  [ComImport, Guid("00021401-0000-0000-C000-000000000046")] class CShellLink {}
  [StructLayout(LayoutKind.Sequential, Pack = 4)] struct PropKey { public Guid fmtid; public uint pid; }
  [StructLayout(LayoutKind.Explicit, Size = 24)] struct PropVar { [FieldOffset(0)] public ushort vt; [FieldOffset(8)] public IntPtr p; }
  [ComImport, InterfaceType(ComInterfaceType.InterfaceIsIUnknown), Guid("886D8EEB-8CF2-4446-8D02-CDBA1DBDCF99")]
  interface IPropertyStore {
    [PreserveSig] int GetCount(out uint c);
    [PreserveSig] int GetAt(uint i, out PropKey k);
    [PreserveSig] int GetValue(ref PropKey k, out PropVar v);
    [PreserveSig] int SetValue(ref PropKey k, ref PropVar v);
    [PreserveSig] int Commit();
  }
  [ComImport, InterfaceType(ComInterfaceType.InterfaceIsIUnknown), Guid("0000010b-0000-0000-C000-000000000046")]
  interface IPersistFile {
    void GetClassID(out Guid g);
    [PreserveSig] int IsDirty();
    void Load([MarshalAs(UnmanagedType.LPWStr)] string f, uint mode);
    void Save([MarshalAs(UnmanagedType.LPWStr)] string f, [MarshalAs(UnmanagedType.Bool)] bool remember);
    void SaveCompleted([MarshalAs(UnmanagedType.LPWStr)] string f);
    void GetCurFile([MarshalAs(UnmanagedType.LPWStr)] out string f);
  }
  public static void SetAppId(string path, string id) {
    object link = new CShellLink();
    ((IPersistFile)link).Load(path, 2);
    var store = (IPropertyStore)link;
    var key = new PropKey { fmtid = new Guid("9F4C2855-9F79-4B39-A8D0-E1D42DE1D5F3"), pid = 5 };
    var v = new PropVar { vt = 31, p = Marshal.StringToCoTaskMemUni(id) };
    try { Marshal.ThrowExceptionForHR(store.SetValue(ref key, ref v)); Marshal.ThrowExceptionForHR(store.Commit()); }
    finally { Marshal.FreeCoTaskMem(v.p); }
    ((IPersistFile)link).Save(path, true);
  }
  public static string GetAppId(string path) {
    object link = new CShellLink();
    ((IPersistFile)link).Load(path, 0);
    var key = new PropKey { fmtid = new Guid("9F4C2855-9F79-4B39-A8D0-E1D42DE1D5F3"), pid = 5 };
    PropVar v; Marshal.ThrowExceptionForHR(((IPropertyStore)link).GetValue(ref key, out v));
    return v.vt == 31 ? Marshal.PtrToStringUni(v.p) : "";
  }
}
'@ }
# A toast shows under the app's own name only when the Start shortcut carries $TileAppId. Without it, Windows names the process, so the run shows the balloon.
function Test-ToastReady {
  try { $f = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Tile Windows.lnk'; (Test-Path -LiteralPath $f) -and ([TileShortcut]::GetAppId($f) -ceq $TileAppId) } catch { $false }
}
# A run's id carries its scene name as hex of its UTF-8 bytes, so a click on an old toast can name the scene after a restart, and the link
# stays in [0-9a-f.] whatever the name holds: <12 hex>.<name hex>.
function New-RunId([string]$name) {
  $n = if ($name.Length -gt 30) { $name.Substring(0, 30) } else { $name }
  [guid]::NewGuid().ToString('n').Substring(0, 12) + '.' + ((([Text.Encoding]::UTF8.GetBytes($n)) | ForEach-Object { $_.ToString('x2') }) -join '')
}
function Get-RunIdName([string]$rid) {
  if ($rid -notmatch '^[0-9a-f]+\.((?:[0-9a-f]{2})+)$') { return '' }
  $h = $matches[1]; try { [Text.Encoding]::UTF8.GetString([byte[]](0..($h.Length / 2 - 1) | ForEach-Object { [Convert]::ToByte($h.Substring(2 * $_, 2), 16) })) } catch { '' }
}
# Starts the tray agent (with $flags) as install.ps1 does. TILE_DRY_START=<file> (tests) writes the command line there and starts nothing.
function Start-TrayAgent([string]$flags) {
  $ps = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
  $a = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$(Join-Path $PSScriptRoot 'tray.ps1')`" $flags"
  if ($env:TILE_DRY_START) { [IO.File]::WriteAllText($env:TILE_DRY_START, "$ps $a"); return }
  Start-Process $ps -WindowStyle Hidden -ArgumentList $a
}
# The registry rows for the tilewindows:// link, as data: install.ps1 writes them and uninstall.ps1 removes the first row's key. Pure.
function Get-UndoProtocolKeys([string]$AppDir = (Join-Path $TileHome 'app')) {
  $ps = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'; $root = 'HKCU:\Software\Classes\tilewindows'
  @([pscustomobject]@{ path = $root; name = '(default)'; value = 'URL:Tile Windows' },
    [pscustomobject]@{ path = $root; name = 'URL Protocol'; value = '' },
    [pscustomobject]@{ path = "$root\shell\open\command"; name = '(default)'; value = "`"$ps`" -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$AppDir\tray.ps1`" -Link `"%1`"" })
}
# The toast as the XML Windows reads. A button opens its link without starting a window (activationType protocol).
function Get-RunToastXml($n) {
  $e = { param($t) [Security.SecurityElement]::Escape([string]$t) }
  $acts = (@($n.actions) | ForEach-Object { "<action content=`"$(& $e $_.label)`" arguments=`"$(& $e $_.launch)`" activationType=`"protocol`"/>" }) -join ''
  "<toast launch=`"tilewindows://open`" activationType=`"protocol`"><visual><binding template=`"ToastGeneric`"><text>$(& $e $n.title)</text><text>$(& $e $n.body)</text>$(if ($n.detail) { "<text>$(& $e $n.detail)</text>" })</binding></visual>$(if ($acts) { "<actions>$acts</actions>" })</toast>"
}
# The one display call for a run toast. $n.quiet puts the toast in the centre without a pop-up (Undo's own answer).
function Send-RunToast($n) {
  [void][Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime]
  [void][Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime]
  $xml = New-Object Windows.Data.Xml.Dom.XmlDocument; $xml.LoadXml((Get-RunToastXml $n))
  $t = New-Object Windows.UI.Notifications.ToastNotification $xml
  $t.Tag = $n.tag; $t.Group = $n.group; if ($n.quiet) { $t.SuppressPopup = $true }
  [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($TileAppId).Show($t)
}
function Clear-RunToasts { try { [void][Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime]; [Windows.UI.Notifications.ToastNotificationManager]::History.Clear($TileAppId) } catch {} }
# $detail is an optional second line under the body (the grid line).
function New-RunToast([string]$title, [string]$body, $actions = @(), [bool]$quiet = $false, [string]$detail = '') {
  $n = [pscustomobject]@{ kind = 'toast'; title = $title; body = $body; actions = @($actions); tag = $TileToastTag; group = $TileToastGroup }
  if ($quiet) { $n | Add-Member quiet $true }
  if ($detail) { $n | Add-Member detail $detail }
  $n
}
# The toast for a click on an Undo that cannot run: the scene's name comes from the link, so it works after a restart.
function New-NoUndoToast([string]$name, [string]$text, $actions) { New-RunToast "$(if ($name) { $name } else { 'This run' }) can't be undone" $text $actions }
$TileOpenAction = @(@{ label = 'Open Tile Windows'; launch = 'tilewindows://open' })
function Join-Names($names) { $a = @($names); if ($a.Count -le 1) { $a -join '' } else { ($a[0..($a.Count - 2)] -join ', ') + ' and ' + $a[-1] } }
# Put a run's windows back. $rec is the newest run's record ($null after a restart); $wins the windows now. A window goes back only when
# every edge is within 4 px of where the run put it (else you moved it since); a window closed since, or minimised before the run, is skipped.
# Places through tile.ps1 -Place, as the board's Undo does. Returns {status, text, scene, manualAt, placed, stayed, closed}.
function Invoke-RunUndo($rec, [string]$runId, $wins, [datetime]$now) {
  $r = [ordered]@{ status = ''; text = ''; scene = ''; manualAt = $null; placed = 0; stayed = @(); closed = @(); refused = @() }
  if (-not $rec) { $r.status = 'gone'; $r.text = 'Tile Windows restarted since, so it lost the old places.'; return [pscustomobject]$r }
  if ($rec.id -ne $runId) { $r.status = 'later'; $r.text = 'A later run replaced this one.'; return [pscustomobject]$r }
  # A run that moved nothing ended this Undo (its record stays, with the id), and an Undo that ran marks it done.
  if ($rec.endedBy) { $r.status = 'ended'; $r.text = "$($rec.endedBy) ran after it and moved no windows, so this Undo has ended."; return [pscustomobject]$r }
  if ($rec.done) { $r.status = 'done'; $r.text = 'Already undone.'; return [pscustomobject]$r }
  $send = @(); $stay = @(); $gone = @(); $eligible = 0
  foreach ($m in @($rec.moved)) {
    if ([double]$m.from.x -le -20000) { continue }
    $eligible++
    $w = @($wins | Where-Object { $_.id -eq $m.id })[0]
    if (-not $w) { $gone += (Get-TileAppName $m.app); continue }
    # Edges: left, top, right, bottom. Numbers are cast, since a rect read from JSON text may hold strings.
    $now4 = @([double]$w.x, [double]$w.y, ([double]$w.x + [double]$w.w), ([double]$w.y + [double]$w.h)); $run4 = @([double]$m.x, [double]$m.y, ([double]$m.x + [double]$m.w), ([double]$m.y + [double]$m.h))
    $far = @(0..3 | Where-Object { [Math]::Abs($now4[$_] - $run4[$_]) -gt 4 })
    if (-not $far.Count) { $send += [pscustomobject]@{ id = $m.id; app = $m.app; title = $m.title; x = $m.from.x; y = $m.from.y; w = $m.from.w; h = $m.from.h } } else { $stay += (Get-TileAppName $m.app) }
  }
  $n = 0; $refused = @()
  if ($send.Count) {
    # One -Place call per window, so each answer is read on its own. ConvertFrom-Json hands a JSON array back as one object
    # (Windows PowerShell 5.1): the second pipe flattens it.
    $res = @(foreach ($one in $send) { ((& $tile -Place (ConvertTo-Json -InputObject @($one) -Compress) -Json -DryRun:$NoApply 3>$null) -join '') | ConvertFrom-Json | ForEach-Object { $_ } })
    # tile.ps1 answers one entry per window sent; an entry that says ok = false (say, no open window) is not counted, and its note says why.
    $refused = @($res | Where-Object { $_.ok -eq $false })
    $n = $send.Count - $refused.Count
  }
  $r.status = 'undone'; $r.placed = $n; $r.stayed = $stay; $r.closed = $gone; $r.refused = @($refused | ForEach-Object { [pscustomobject]@{ app = (Get-TileAppName $_.app); why = [string]$_.note } })
  $r.scene = if ($rec.changed) { [string]$rec.prev } else { '' }
  if ($n) { $r.manualAt = $now }
  $win = { param($c) if ($c -eq 1) { 'window' } else { 'windows' } }
  $t = if ($n -eq $eligible) { "Put back $n $(& $win $n)." } else { "Put back $n of $eligible $(& $win $eligible)." }
  if ($stay.Count) { $t += " You moved $(Join-Names $stay) since, so $(if ($stay.Count -eq 1) { 'it stays' } else { 'they stay' })." }
  if ($gone.Count) { $t += " $(Join-Names $gone) closed." }
  if ($r.refused.Count) { $t += " $(Join-Names @($r.refused | ForEach-Object { $_.app })) could not go back: $((@($r.refused | ForEach-Object { $_.why } | Select-Object -Unique)) -join '; ')." }
  $r.text = $t
  [pscustomobject]$r
}
# ---- Gap watch (decision layout-free, item G): when a tiled window closes or minimizes, the tray asks the engine to fill the gap. ----
# Two pure functions; the hook that feeds them is TileWinWatch1, below the -Lib return. The gap events: destroy 0x8001, show 0x8002,
# hide 0x8003, minimize start 0x0016, minimize end 0x0017. Only the window itself counts (idObject 0, idChild 0), on a tiled handle.
$TileGapHide = @(0x8001, 0x8003, 0x0016)
$TileGapShow = @(0x8002, 0x0017)
function Test-GapEvent($event, $idObject, $idChild, $hwnd, $tiledSet) {
  [bool](($event -in $TileGapHide -or $event -in $TileGapShow) -and $idObject -eq 0 -and $idChild -eq 0 -and @($tiledSet) -contains $hwnd)
}
# One tick's events in, at most one run out. $state: scene, tiled ([{hwnd, mon}]), absent (handles hidden or minimized now), grids
# ({mon: grid}), lastApply (the tray's own last apply, or $null) and quietMs. $events: [{event, idObject, idChild, hwnd, time}].
# The run is { scene; absent }, absent being the set after this tick; nothing when the set did not change. A burst gives one run, the
# last event per handle winning. An event within quietMs after the tray's own apply is ignored (that apply moved those windows).
# Only a monitor whose grid has free.areas (Free Layout on) takes part; a handle on any other monitor stays out of the run.
# $pidOf (optional): a scriptblock that gives the process id that owns a handle now, 0 when the window is gone. A tiled entry that carries procId (taken at apply)
# skips an event when the handle now belongs to another process: Windows reuses a closed window's handle. A gone window reads 0, which is no mismatch.
# A destroy (0x8001) is final: the state keeps those handles in state.destroyed (made here when missing, dropped with the state at the next apply), and every
# later event on one is ignored, so a reused handle from the same process is not taken for the window. Minimize then restore and hide then show are not destroys.
function Step-GapFill($state, $events, [datetime]$now, $pidOf = $null) {
  $mon = @{}; $own = @{}; foreach ($t in @($state.tiled)) { $mon["$($t.hwnd)"] = [string]$t.mon; $own["$($t.hwnd)"] = $t.procId }
  $set = @($state.tiled | % { $_.hwnd })
  $free = @{}
  foreach ($m in @($mon.Values | Select-Object -Unique)) {
    $g = if ($state.grids -is [Collections.IDictionary]) { $state.grids[$m] } elseif ($state.grids -and $state.grids.PSObject.Properties[$m]) { $state.grids.$m }
    $free[$m] = [bool]($g -and $g.free -and @($g.free.areas).Count)
  }
  $last = @{}
  if ($null -eq $state.PSObject.Properties['destroyed']) { $state | Add-Member -NotePropertyName destroyed -NotePropertyValue @{} }
  foreach ($e in @($events | Sort-Object time)) {
    if (-not (Test-GapEvent $e.event $e.idObject $e.idChild $e.hwnd $set)) { continue }
    if ($state.destroyed.ContainsKey("$($e.hwnd)")) { continue }
    if ($state.lastApply -and ($e.time - $state.lastApply).TotalMilliseconds -lt $state.quietMs) { continue }
    if (-not $free[$mon["$($e.hwnd)"]]) { continue }
    if ($pidOf -and $own["$($e.hwnd)"]) { $livePid = [uint32](& $pidOf $e.hwnd); if ($livePid -and $livePid -ne [uint32]$own["$($e.hwnd)"]) { continue } }
    if ($e.event -eq 0x8001) { $state.destroyed["$($e.hwnd)"] = $true }
    $last["$($e.hwnd)"] = [pscustomobject]@{ hwnd = $e.hwnd; gone = ($e.event -in $TileGapHide) }
  }
  $abs = @{}; foreach ($h in @($state.absent)) { $abs["$h"] = $h }
  $changed = $false
  foreach ($k in @($last.Keys)) {
    if ($last[$k].gone -and -not $abs.ContainsKey($k)) { $abs[$k] = $last[$k].hwnd; $changed = $true }
    elseif (-not $last[$k].gone -and $abs.ContainsKey($k)) { $abs.Remove($k); $changed = $true }
  }
  if ($changed) { [pscustomobject]@{ scene = $state.scene; absent = @($abs.Values) } }
}
# What the tray keeps about the scene it applied last, for Step-GapFill and Invoke-GapFill. grids: the grids the run used, by monitor key (role or id).
# The run's own scene is found as the engine finds it: $mode (the grid mode, dense or roomy) swaps the wide grid through Get-GridSceneJson, the same
# function the apply uses; the setup key of $plugged (Get-TileKnownSetupKey) then picks layouts[key] (Get-TileLayoutEntry, the engine's own lookup), whose
# grids are named by monitor id, else the scene's role grids are the run's. With no setup key known (no $plugged) the engine's own monitor read decides,
# which the tray cannot see: each layout's grids count, and a monitor two layouts both give is left out, since it cannot be told which the run used. arg: what Apply-Scene passed to tile.ps1 -Scene. last: handle -> the rect the tray last gave it (for -Last).
function New-GapState($sc, $placed, [datetime]$at, $plugged = $null, [string]$mode = '', $arg = $null) {
  $use = $sc
  if ($mode -and $sc.claudeGrid -and $sc.claudeGrid.$mode) { try { $use = ConvertFrom-Json (Get-GridSceneJson $sc $sc.claudeGrid.$mode $plugged) } catch { Add-TileLog ([string]$sc.id) "Gap-fill kept the scene's own grids: the $mode grid could not be read ($($_.Exception.Message))." } }
  $key = Get-TileKnownSetupKey $plugged
  $own = Get-TileLayoutEntry $use $key
  $srcs = if ($own) { @($own.Value.grids) } elseif ($key) { @($use.grids) } else { @($use.grids) + @(if ($use.layouts) { $use.layouts.PSObject.Properties | % { $_.Value.grids } }) }
  $grids = @{}; $seen = @{}
  foreach ($src in $srcs) { if ($src) { foreach ($p in $src.PSObject.Properties) { $seen[$p.Name] = 1 + [int]$seen[$p.Name]; $grids[$p.Name] = $p.Value } } }
  if (-not $key) { foreach ($k in @($seen.Keys | ? { $seen[$_] -gt 1 })) { $grids.Remove($k) } }
  $last = @{}; foreach ($p in @($placed | ? { $_.id -and $null -ne $_.x })) { $last["$([int64]$p.id)"] = [pscustomobject]@{ id = [int64]$p.id; x = $p.x; y = $p.y; w = $p.w; h = $p.h } }
  [pscustomobject]@{ scene = [string]$sc.id; tiled = @($placed | ? { $_.id -and $_.mon } | % { [pscustomobject]@{ hwnd = [int64]$_.id; mon = [string]$_.mon } }); absent = @(); grids = $grids; lastApply = $at; quietMs = 1500; arg = $arg; last = $last }
}
# The process id that owns a window handle now, 0 when the window is gone or the type is not loaded (a caller that loaded only the functions).
function Get-WinPid($hwnd) {
  if (-not ('TileWinId1' -as [type])) { return 0 }
  try { [uint32][TileWinId1]::Pid([long]$hwnd) } catch { 0 }
}
# The gap watch's tray-side steps. Set-GapWatch runs after each apply: it keeps the scene's tiled windows and hands their handles to the
# hook. Clear-GapWatch drops them, so no event is read against a layout that is no longer on screen. They sit above the -Lib return because
# Apply-Scene calls Set-GapWatch, and a caller that loads only the functions has no TileWinWatch1: there both do nothing.
# $arg, $plugged and $mode are what the apply ran with: the scene text it gave tile.ps1, the monitors read, and the grid mode. Each tiled window keeps
# the process id that owned its handle at apply (procId), so a recycled handle is not taken for it.
function Set-GapWatch($sc, $placed, $arg = $null, $plugged = $null, [string]$mode = '') {
  if (-not ('TileWinWatch1' -as [type])) { return }
  $script:gap = New-GapState $sc $placed (Get-Date) $plugged $mode $arg
  foreach ($t in @($script:gap.tiled)) { $t | Add-Member -NotePropertyName procId -NotePropertyValue ([uint32](Get-WinPid $t.hwnd)) -Force }
  try { [TileWinWatch1]::SetTiled([long[]]@($script:gap.tiled | % { $_.hwnd })) } catch {}
}
function Clear-GapWatch {
  if (-not ('TileWinWatch1' -as [type])) { return }
  $script:gap = $null
  try { [TileWinWatch1]::SetTiled([long[]]@()) } catch {}
}
# The scene on screen now (state.json's active), '' when none or unreadable: the scene a run replaces, for Undo, and the active scene an Undo that moved nothing logs.
function Get-ActiveId { try { [string](ConvertFrom-Json (Get-TileStateText)).active } catch { '' } }
if ($Lib) { return }

$quitName = TrayName 'Quit'; $openName = TrayName 'Open'
$created = $false; $mutex = New-Object Threading.Mutex($true, (TrayName 'Agent'), [ref]$created)
# A link that fails $linkOk gets a visible note from the launcher (the agent never sees it), not a silent exit.
function Show-BadLink { try { Send-RunToast (New-RunToast "Tile Windows can't use that link" 'It is not a link Tile Windows made.' $TileOpenAction) } catch {} }
$linkOk = '^tilewindows://(open|undo/?\?run=[0-9a-f]{1,32}(\.[0-9a-f]{2,300})?)/?$'
if (-not $created) {
  if ($Link -match $linkOk) { Write-TileFile (Join-Path $TileHome 'link.txt') $Link; $e = [Threading.EventWaitHandle]::OpenExisting((TrayName 'Link')); [void]$e.Set() }
  elseif ($Link) { Show-BadLink }
  elseif ($Open) { $e = [Threading.EventWaitHandle]::OpenExisting($openName); [void]$e.Set() }
  return
}
# A link with no agent running: this process is not an agent. An open link starts one (which opens the app), and a stale Undo after a quit says so.
if ($Link) {
  $mutex.ReleaseMutex(); $mutex.Dispose()
  if ($Link -match $linkOk -and $Link -match '^tilewindows://open') { Start-TrayAgent '-Open' }
  elseif ($Link -match $linkOk) {
    $name = Get-RunIdName ($Link -replace '^.*run=', '' -replace '/$', '')
    $gone = New-NoUndoToast $name 'Tile Windows restarted since, so it lost the old places.' $TileOpenAction
    if (-not $NoApply) { Add-TileLog (Get-ActiveId) "Undo of $(if ($name) { $name } else { 'a run' }) did nothing: Tile Windows restarted since, so it lost the old places." }
    try { Send-RunToast $gone } catch {}
  }
  else { Show-BadLink }
  return
}
$quitEv = New-Object Threading.EventWaitHandle($false, 'AutoReset', $quitName)
$openEv = New-Object Threading.EventWaitHandle($false, 'AutoReset', $openName)
$linkEv = New-Object Threading.EventWaitHandle($false, 'AutoReset', (TrayName 'Link'))
# install.ps1 reads this to wait for the agent process to exit (its mutex is released a little before the process ends). Advisory: a failed write does not stop the agent.
$trayPidFile = Join-Path $TileHome 'tray.pid'
try { Write-TileFile $trayPidFile "$PID" } catch {}

Add-Type -AssemblyName System.Windows.Forms, System.Drawing
# The handler only sets a flag: SystemEvents may call it off the PowerShell thread. The timer does the work.
Add-Type @'
public static class TileDisplayWatch {
  public static volatile bool Dirty;
  public static void Start() { Microsoft.Win32.SystemEvents.DisplaySettingsChanged += (s, e) => { Dirty = true; }; }
}
'@
[TileDisplayWatch]::Start()
# The Win32 signals the triggers read, kept thin: idle time, mouse buttons, the foreground window, lock and unlock, and the end of a
# user's own window drag (a hook that does not see MoveWindow calls from this app). The callbacks only set fields.
Add-Type @'
using System; using System.Runtime.InteropServices;
public static class TileInput {
  [StructLayout(LayoutKind.Sequential)] struct LII { public uint cb; public uint t; }
  [DllImport("user32.dll")] static extern bool GetLastInputInfo(ref LII p);
  [DllImport("user32.dll")] static extern short GetAsyncKeyState(int k);
  [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
  delegate void WinEventProc(IntPtr hook, uint ev, IntPtr hwnd, int idObj, int idChild, uint thread, uint time);
  [DllImport("user32.dll")] static extern IntPtr SetWinEventHook(uint min, uint max, IntPtr mod, WinEventProc cb, uint pid, uint tid, uint flags);
  static WinEventProc keep;
  public static volatile bool Locked;
  public static long MoveEndTicks, LockedAtTicks;
  public static double UnlockedAfter = -1;
  public static double IdleSeconds() { LII l = new LII(); l.cb = 8; GetLastInputInfo(ref l); return unchecked((uint)Environment.TickCount - l.t) / 1000.0; }
  public static bool MouseDown() { return (GetAsyncKeyState(1) & 0x8000) != 0 || (GetAsyncKeyState(2) & 0x8000) != 0; }
  public static long Foreground() { return (long)GetForegroundWindow(); }
  public static void Start() {
    keep = delegate(IntPtr hook, uint ev, IntPtr hwnd, int o, int c, uint th, uint tm) { MoveEndTicks = DateTime.UtcNow.Ticks; };
    SetWinEventHook(0x000B, 0x000B, IntPtr.Zero, keep, 0, 0, 2);
    Microsoft.Win32.SystemEvents.SessionSwitch += (s, e) => {
      if (e.Reason == Microsoft.Win32.SessionSwitchReason.SessionLock) { LockedAtTicks = DateTime.UtcNow.Ticks; Locked = true; }
      else if (e.Reason == Microsoft.Win32.SessionSwitchReason.SessionUnlock) { Locked = false; UnlockedAfter = (DateTime.UtcNow.Ticks - LockedAtTicks) / 1e7; }
    };
  }
}
'@
try { [TileInput]::Start() } catch { Write-Warning "Some automatic triggers are off: $($_.Exception.Message)" }
# The gap watch's hook (TileInput's text above stays as it is). Out of context, so Windows posts each event to this thread's message loop;
# the process's own windows are skipped. The callback drops everything but the window itself (idObject 0, idChild 0) on a handle in the
# tiled set, and keeps the last event per handle with its time. The tray's 1 s tick drains it: no timer and no polling here.
# Cost: one call into C# per create, show or hide event in the session (often hundreds a second); each is two compares and one set lookup.
# A second run of this body in one process finds the type loaded and starts nothing: the first run's delegate stays referenced.
if (-not ('TileWinWatch1' -as [type])) { Add-Type @'
using System; using System.Collections.Generic; using System.Runtime.InteropServices;
public static class TileWinWatch1 {
  delegate void WinEventProc(IntPtr hook, uint ev, IntPtr hwnd, int idObj, int idChild, uint thread, uint time);
  [DllImport("user32.dll")] static extern IntPtr SetWinEventHook(uint min, uint max, IntPtr mod, WinEventProc cb, uint pid, uint tid, uint flags);
  static WinEventProc keep;
  static readonly object gate = new object();
  static HashSet<long> tiled = new HashSet<long>();
  static Dictionary<long, long[]> seen = new Dictionary<long, long[]>();
  // Replaces the tiled set (after each apply) and forgets events that came before it.
  public static void SetTiled(long[] handles) { lock (gate) { tiled = new HashSet<long>(handles); seen.Clear(); } }
  // The last event per handle since the last call, flattened as handle, event, UTC ticks.
  public static long[] Drain() {
    lock (gate) {
      long[] r = new long[seen.Count * 3]; int i = 0;
      foreach (KeyValuePair<long, long[]> p in seen) { r[i++] = p.Key; r[i++] = p.Value[0]; r[i++] = p.Value[1]; }
      seen.Clear(); return r;
    }
  }
  static IntPtr hookA, hookB;
  static bool started;
  public static void Start() {
    if (started) return;
    started = true;
    keep = delegate(IntPtr hook, uint ev, IntPtr hwnd, int o, int c, uint th, uint tm) {
      if (o != 0 || c != 0) return;
      long h = (long)hwnd;
      lock (gate) { if (tiled.Contains(h)) seen[h] = new long[] { ev, DateTime.UtcNow.Ticks }; }
    };
    // Flags 2: out of context, skip own process. 0x8001 to 0x8003: destroy, show, hide. 0x0016 and 0x0017: minimize start and end.
    hookA = SetWinEventHook(0x8001, 0x8003, IntPtr.Zero, keep, 0, 0, 2);
    hookB = SetWinEventHook(0x0016, 0x0017, IntPtr.Zero, keep, 0, 0, 2);
  }
}
'@
}
# The owner of a window handle, for the gap watch (a new type: the two above keep their text). 0 when the handle is not a window now.
if (-not ('TileWinId1' -as [type])) { Add-Type @'
using System; using System.Runtime.InteropServices;
public static class TileWinId1 {
  [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  public static uint Pid(long h) { uint p; GetWindowThreadProcessId(new IntPtr(h), out p); return p; }
}
'@
}
try { [TileWinWatch1]::Start() } catch { Write-Warning "The gap watch is off: $($_.Exception.Message)" }
$tile = Join-Path $PSScriptRoot 'tile.ps1'; $serve = Join-Path $PSScriptRoot 'serve.ps1'
$srv = $null; $url = ''; $state = New-TrayState; $dirtyAt = $null; $tick = 0; $first = $true
$agendaRaw = $null; $offer = $null; $gridMode = @{}; $plugged = $null  # plugged: the monitors of the last good read, for the grid trigger
$gap = $null  # the gap watch's view of the last applied scene (New-GapState); $null until a scene has run

# Any balloon replaces a pending offer, so a click on it never arranges.
function Note([string]$text) { $script:offer = $null; if ($icon) { $icon.ShowBalloonTip(4000, 'Tile Windows', $text, 'Info') } }
# The offer: a balloon that moves nothing. Clicking it arranges (for up to 3 minutes, or until another balloon shows).
function Offer-Scene($s, [string]$why) {
  $script:offer = [pscustomobject]@{ scene = $s; exp = (Get-Date).AddMinutes(3) }
  if ($icon) { $icon.ShowBalloonTip(15000, 'Meeting in 2 minutes', "Click to arrange your windows for $($s.name).", 'Info') }
}
# The plugged-in monitors with their ids (tile.ps1 -Monitors); $null when that read fails or gives none. A failed read is not a change:
# Windows' own screen list keys by bounds, a different key for the same monitors, so it is never the fallback.
function Read-Monitors {
  try { $m = @((ConvertFrom-Json ((& $tile -Monitors 3>$null) -join '')) | % { $_ }); if ($m.Count) { return $m } } catch {}
  $null
}
function Read-Windows { try { @((((& $tile -Json 3>$null) -join '') | ConvertFrom-Json).windows) } catch { $null } }
# The gap-fill run: tile.ps1 -GapFill on the scene as the last apply gave it, with the windows that are away and the rect the tray last gave each tiled
# window. The engine moves only a window that still sits where the tray put it; the rects it moves to become the new last rects. Gap-fill acts only on a
# monitor whose layout has Free Layout on (free.areas). No toast, no run-undo record, one log line: a failed run is that line too. -NoApply runs it dry.
function Invoke-GapFill($run) {
  $g = $script:gap
  try {
    $arg = if ($g -and $g.arg) { $g.arg } else { [string]$run.scene }
    $last = ConvertTo-Json -InputObject @(if ($g -and $g.last) { $g.last.Values }) -Depth 4 -Compress
    $r = (& $tile -Scene $arg -GapFill -Absent @($run.absent) -Last $last -Json -DryRun:$NoApply 3>$null) -join '' | ConvertFrom-Json
    $moved = @($r.placed)
    if ($g -and -not $NoApply) { foreach ($p in $moved) { $g.last["$($p.id)"] = [pscustomobject]@{ id = [int64]$p.id; x = $p.x; y = $p.y; w = $p.w; h = $p.h } } }
    $line = "Gap-fill: $(@($run.absent).Count) window(s) away. Moved $($moved.Count)."
  } catch { $line = "Gap-fill failed: $($_.Exception.Message)" }
  if (-not $NoApply) { Add-TileLog $run.scene $line }
}
# $prev: the scene on screen before this run ('' when unknown), so Undo can put it back.
function Apply-Scene($s, [string]$why, [string]$prev = '') {
  try {
    $arg = $s.id; $gridLine = ''; $mode = ''
    # Grid follows the Claude count: the scene runs from its JSON with the ultrawide grid swapped.
    if ((Test-Auto $s 'grid') -and $s.claudeGrid) {
      $cn = @(Read-Windows | ? { $_.app -eq 'claude' -and -not $_.min }).Count
      $mode = Get-ClaudeMode $s $cn $gridMode[$s.id]
      if ($mode) { $gridMode[$s.id] = $mode; $arg = Get-GridSceneJson (Get-TileScene $s.id) $s.claudeGrid.$mode $script:plugged }
      if ($mode -eq 'dense') { $gridLine = "Dense grid: $cn $(Get-TileAppName 'claude') $(if ($cn -eq 1) { 'window' } else { 'windows' })." }
    }
    $r = (& $tile -Scene $arg -Json -DryRun:$NoApply 3>$null) -join '' | ConvertFrom-Json
    # A window counts as moved only when its rect changed: a run that puts every window where it already sits moves nothing.
    $moved = @($r.placed | ? { $_.note -eq 'moved' -and -not ($_.from -and $_.from.x -eq $_.x -and $_.from.y -eq $_.y -and $_.from.w -eq $_.w -and $_.from.h -eq $_.h) })
    Set-GapWatch $s $r.placed $arg $script:plugged $mode
    $n = $moved.Count
    $msg = "$($s.name) applied $why. Moved $n window(s)."
    if (-not $NoApply) { Add-TileLog $s.id $msg }
    if ($n -eq 0) {
      Note $msg
      # A run that moved nothing ends the older run's Undo: its record stays (same id), and a click on it says so.
      if ($script:runUndo -and -not $script:runUndo.endedBy) { $script:runUndo.endedBy = $s.name }
    }
    elseif (-not $NoIcon) {
      # A run that moved windows shows the toast (only when the Start shortcut gives it the app's name) and keeps what Undo needs.
      # A run that moved nothing, a failure and the offer keep the balloon.
      if (-not (Test-ToastReady)) { Note $msg; return }
      $script:offer = $null
      $script:runUndo = [pscustomobject]@{ id = New-RunId $s.name; at = Get-Date; scene = $s.id; name = $s.name; prev = $prev; changed = [bool]($prev -and $prev -ne $s.id); done = $false; endedBy = ''
        moved = @($moved | % { [pscustomobject]@{ id = $_.id; app = $_.app; title = $_.title; x = $_.x; y = $_.y; w = $_.w; h = $_.h; from = $_.from } }) }
      $head = if ($why) { $why.Substring(0, 1).ToUpper() + $why.Substring(1) } else { 'Done' }
      try { Send-RunToast (New-RunToast "$($s.name) applied" "$head. Moved $n $(if ($n -eq 1) { 'window' } else { 'windows' })." @(@{ label = 'Undo'; launch = "tilewindows://undo?run=$($script:runUndo.id)" }) $false $gridLine) }
      catch { Note $msg }
    }
  } catch { Note "$($s.name) failed: $($_.Exception.Message)" }
}
# Shows a toast, or the balloon with the same words when the agent has no icon toast to give (no Start shortcut with the app's name) or the toast throws.
# With -NoIcon the agent shows nothing.
function Show-Toast($n) {
  if ($NoIcon) { return }
  if (Test-ToastReady) { try { Send-RunToast $n; return } catch {} }
  Note "$($n.title). $($n.body)"
}
# A tilewindows:// link the launcher left in link.txt: open the app, or put the newest run back. Undo counts as your own move, so waiting
# triggers cancel and nothing re-applies the run (Step-Tray reads the move time and manualApplyAt).
function Invoke-Link {
  $f = Join-Path $TileHome 'link.txt'
  $l = try { $t = Read-TileFile $f; Remove-Item -LiteralPath $f -Force; $t.Trim() } catch { '' }
  if ($l -notmatch $linkOk) { return }
  if ($l -match '^tilewindows://open') { Open-App; return }
  $rid = $l -replace '^.*run=', '' -replace '/$', ''
  $rec = $script:runUndo
  try {
    $wins = Read-Windows; if ($null -eq $wins) { throw 'Tile Windows could not read the windows.' }
    $res = Invoke-RunUndo $rec $rid @($wins) (Get-Date)
    $name = Get-RunIdName $rid
    if ($res.status -eq 'undone') {
      $rec.done = $true
      if ($res.manualAt) { [TileInput]::MoveEndTicks = $res.manualAt.ToUniversalTime().Ticks; $script:state.manualApplyAt = $res.manualAt }
      Clear-GapWatch
      # A run that left the scene as it was has no scene to name, so the log line names the scene now active.
      if (-not $NoApply) { Add-TileLog $(if ($res.scene) { $res.scene } else { Get-ActiveId }) "Undid $($rec.name): $($res.text)" }
      # A partial Undo (a window stayed, closed or was refused) pops up and says why; a clean one updates quietly.
      $partial = [bool](@($res.stayed).Count -or @($res.closed).Count -or @($res.refused).Count)
      Show-Toast (New-RunToast "$($rec.name) $(if ($partial) { 'partly undone' } else { 'undone' })" $res.text @() (-not $partial -and $res.placed -gt 0))
    } elseif ($res.status -eq 'later') {
      if (-not $NoApply) { Add-TileLog (Get-ActiveId) "Undo of $(if ($name) { $name } else { 'a run' }) did nothing: a later run replaced it." }
      # $rec is the newer run: its record replaced the one this toast was for.
      $newer = $script:runUndo
      if ($newer -and -not $newer.done -and -not $newer.endedBy) { Show-Toast (New-NoUndoToast $name "$($newer.name) ran after it and moved windows. Undo $($newer.name) instead." @(@{ label = "Undo $($newer.name)"; launch = "tilewindows://undo?run=$($newer.id)" })) }
      else { Show-Toast (New-NoUndoToast $name 'A later run replaced it, so its places are out of date.' $TileOpenAction) }
    } elseif ($res.status -eq 'ended') {
      if (-not $NoApply) { Add-TileLog (Get-ActiveId) "Undo of $($rec.name) did nothing: $($res.text)" }
      Show-Toast (New-NoUndoToast $name $res.text $TileOpenAction)
    } elseif ($res.status -eq 'done') {
      if (-not $NoApply) { Add-TileLog (Get-ActiveId) "Undo of $($rec.name) did nothing: it was already undone." }
      Show-Toast (New-RunToast "$($rec.name) undone" $res.text @())
    } else {
      if (-not $NoApply) { Add-TileLog (Get-ActiveId) "Undo of $(if ($name) { $name } else { 'a run' }) did nothing: $($res.text)" }
      Show-Toast (New-NoUndoToast $name $res.text $TileOpenAction)
    }
  } catch {
    $err = $_.Exception.Message
    # The log shows every Undo. A log write that throws must not hide the toast.
    if (-not $NoApply) { try { $n = Get-RunIdName $rid; Add-TileLog (Get-ActiveId) "Undo of $(if ($n) { $n } else { 'a run' }) failed: $err" } catch {} }
    Show-Toast (New-RunToast 'Undo failed' $err)
  }
}
function Open-App {
  if (-not $srv -or $srv.HasExited) {
    $psi = New-Object Diagnostics.ProcessStartInfo 'powershell', "-NoProfile -ExecutionPolicy Bypass -File `"$serve`" -NoBrowser"
    $psi.UseShellExecute = $false; $psi.RedirectStandardOutput = $true; $psi.CreateNoWindow = $true
    $script:srv = [Diagnostics.Process]::Start($psi); $script:url = $srv.StandardOutput.ReadLine()
  }
  if ($url -match '^http://127\.0\.0\.1:') { Start-Process $url } else { Note 'The app server did not start.' }
}
function Stop-App { if ($srv -and -not $srv.HasExited) { try { [void](Invoke-WebRequest -UseBasicParsing "${url}quit" -Method Post -Body 'quit' -TimeoutSec 3) } catch {}; if (-not $srv.WaitForExit(3000)) { $srv.Kill() } } }

$menu = New-Object Windows.Forms.ContextMenuStrip
$openItem = $menu.Items.Add('Open Tile Windows'); $openItem.Font = New-Object Drawing.Font($openItem.Font, [Drawing.FontStyle]::Bold)
$openItem.add_Click({ Open-App })
$scenesItem = New-Object Windows.Forms.ToolStripMenuItem 'Apply Scene'; [void]$menu.Items.Add($scenesItem)
[void]$menu.Items.Add('-')
$quitItem = $menu.Items.Add('Quit'); $quitItem.add_Click({ [Windows.Forms.Application]::Exit() })
# Rebuild the scene list each time the menu opens, so it follows config.json.
$menu.add_Opening({
  $scenesItem.DropDownItems.Clear()
  try { $cfg = ConvertFrom-Json (Get-TileConfigText) } catch { $cfg = $null }
  foreach ($s in @($cfg.scenes)) { $it = $scenesItem.DropDownItems.Add($s.name); $it.Tag = $s; $it.add_Click({ param($o) Apply-Scene $o.Tag 'from the tray' (Get-ActiveId) }) }
})

$icon = $null
if (-not $NoIcon) {
  # A three-pane glyph drawn at run time: no icon file to ship.
  $bmp = New-Object Drawing.Bitmap 16, 16; $g = [Drawing.Graphics]::FromImage($bmp); $g.Clear([Drawing.Color]::Transparent)
  $br = New-Object Drawing.SolidBrush ([Drawing.Color]::FromArgb(31, 107, 255))
  $g.FillRectangle($br, 1, 2, 6, 5); $g.FillRectangle($br, 9, 2, 6, 5); $g.FillRectangle($br, 1, 9, 14, 5); $g.Dispose()
  $icon = New-Object Windows.Forms.NotifyIcon
  $icon.Icon = [Drawing.Icon]::FromHandle($bmp.GetHicon()); $icon.Text = 'Tile Windows'; $icon.ContextMenuStrip = $menu; $icon.Visible = $true
  $icon.add_DoubleClick({ Open-App })
  $icon.add_BalloonTipClicked({ $o = $script:offer; if ($o -and $o.exp -gt (Get-Date)) { $script:offer = $null; Apply-Scene $o.scene 'because you chose to arrange for the meeting' (Get-ActiveId) } })
}

$timer = New-Object Windows.Forms.Timer; $timer.Interval = 1000
$timer.add_Tick({
  if ($quitEv.WaitOne(0)) { [Windows.Forms.Application]::Exit(); return }
  if ($openEv.WaitOne(0)) { Open-App }
  if ($linkEv.WaitOne(0)) { Invoke-Link }
  try { $cfg = ConvertFrom-Json (Get-TileConfigText) } catch { return }
  # The monitor key: on the first tick (seeds), then 2 s after the display last changed.
  if ([TileDisplayWatch]::Dirty) { [TileDisplayWatch]::Dirty = $false; $script:dirtyAt = Get-Date; $script:readFails = 0 }
  $key = $null
  if ($first -or ($dirtyAt -and ((Get-Date) - $dirtyAt).TotalSeconds -ge 2)) { $script:first = $false; $script:dirtyAt = $null; $mons = Read-Monitors
    # A read that gave no monitors reads again on a later tick (the 2 s wait above), at most 5 more times: each is a tile.ps1 run, so a broken read must
    # not loop every 2 s. A good read or a new display change starts the count again.
    if ($mons) { $script:plugged = $mons; $script:readFails = 0 } elseif ([int]$script:readFails -lt 5) { $script:readFails = [int]$script:readFails + 1; $script:dirtyAt = Get-Date }
    $key = Get-MonitorKey $mons }
  # Teams calls: read every tick while any scene applies itself (the in-call guard needs the reading too); the 2-reading debounce in Step-Tray lands a start or end in 2 s.
  # The mic read is a registry read. The window read (Get-Process) runs only when it can decide: the store is unreadable, or a browser holds the mic.
  $call = $null; $any = Test-AnyAuto $cfg; $n = ++$script:tick
  if ($any) { $mic = Get-MicUsage; $call = Test-TeamsCall $mic $(if ($null -eq $mic -or (Test-BrowserMic $mic)) { Get-TeamsWindows } else { @() }) }
  # Windows and the foreground one: every 3 s, only for the triggers that read them. agenda.json: every 30 s.
  $fg = $null; $w = $null
  if (($n % 3) -eq 1 -and @($cfg.scenes | ? { (Test-Auto $_ 'window') -or (Test-Auto $_ 'activity') }).Count) {
    $w = Read-Windows
    if ($null -ne $w) { $h = [TileInput]::Foreground(); $f = @($w | ? { $_.id -eq $h })[0]; $fg = [pscustomobject]@{ app = $(if ($f) { $f.app } else { '' }); title = $(if ($f) { $f.title } else { '' }) } }
  }
  if (($n % 30) -eq 2) { $script:agendaRaw = try { ConvertFrom-Json ([IO.File]::ReadAllText((Join-Path $PSScriptRoot 'agenda.json'), $TileUtf8)) } catch { $null } }
  $ua = [TileInput]::UnlockedAfter; [TileInput]::UnlockedAfter = -1
  $mv = [TileInput]::MoveEndTicks
  $sig = [pscustomobject]@{ idleSec = [TileInput]::IdleSeconds(); locked = [TileInput]::Locked; unlockedAfter = $(if ($ua -ge 0) { $ua }); mouseDown = [TileInput]::MouseDown()
    manualAt = $(if ($mv) { (New-Object DateTime $mv, 'Utc').ToLocalTime() } else { [datetime]::MinValue }); wins = $w; fg = $fg; screens = [Windows.Forms.Screen]::AllScreens.Count; agenda = $agendaRaw }
  $active = Get-ActiveId
  # A read here recovered from a bad file: the page shows the note until dismissed; the tray says it once.
  if ($TileNote) { Note $TileNote; $script:TileNote = '' }
  # The gap watch reads what its hook recorded since the last tick; events of a scene that is no longer the active one are dropped.
  $gw = try { [TileWinWatch1]::Drain() } catch { @() }
  $gapRan = $false
  if ($gap -and $gw.Count -and $active -eq $gap.scene) {
    $ge = for ($i = 0; $i -lt $gw.Count; $i += 3) { [pscustomobject]@{ event = [int]$gw[$i + 1]; idObject = 0; idChild = 0; hwnd = $gw[$i]; time = (New-Object DateTime $gw[$i + 2], 'Utc').ToLocalTime() } }
    $run = Step-GapFill $gap $ge (Get-Date) { param($h) Get-WinPid $h }
    if ($run) { $gap.absent = @($run.absent); Invoke-GapFill $run; $gapRan = $true }
  }
  foreach ($a in (Step-Tray $state (Get-Date) $cfg $key $call $active $sig)) { $sc = @($cfg.scenes | ? { $_.id -eq $a.id })[0]; if ($sc) { if ($a.offer) { Offer-Scene $sc $a.why } else { Apply-Scene $sc $a.why (Get-ActiveId) } } }
  # A gap-fill run moves windows too: the next window read is no manual move.
  if ($gapRan) { $state.skipRead = $true }
})
$timer.Start()
# The undo record lives in memory only, so toasts from an earlier agent (with an Undo button that could not work) are cleared at start and at Quit.
if (-not $NoIcon) { Clear-RunToasts }
if ($Open) { Open-App }
try { [Windows.Forms.Application]::Run() }
finally {
  $timer.Stop(); Stop-App
  if (-not $NoIcon) { Clear-RunToasts }
  if ($icon) { $icon.Visible = $false; $icon.Dispose() }
  # Take back tray.pid only while it still names this process (a newer agent may have written its own).
  try { if ((Test-Path -LiteralPath $trayPidFile) -and ([IO.File]::ReadAllText($trayPidFile).Trim() -eq "$PID")) { Remove-Item -LiteralPath $trayPidFile -Force } } catch {}
  $mutex.ReleaseMutex(); $mutex.Dispose(); $quitEv.Dispose(); $openEv.Dispose(); $linkEv.Dispose()
}
