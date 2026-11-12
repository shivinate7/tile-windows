# Tile Windows tray agent: an icon in the notification area.
#   Menu: Open Tile Windows, Apply Scene >, Quit. Double-click opens the app.
#   Applies scenes on their trigger: a schedule (days + time), when the monitor set changes, or when a
#   Teams call starts (and, if the scene says so, goes back to the scene before when the call ends).
#   Also runs the per-scene switches in scene.auto (see README, Triggers): desk, window, activity, size, gaps, offer, monitors, noext, grid.
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
# The monitor set as one string: a change in it (a monitor added, removed or moved) fires 'display' scenes.
function Get-MonitorKey($screens) { (@($screens | % { "$($_.DeviceName)=$($_.Bounds.Width)x$($_.Bounds.Height)@$($_.Bounds.X),$($_.Bounds.Y)" }) | Sort-Object) -join ';' }
function Get-DisplayScenes($config) { @($config.scenes | ? { $_.trigger.type -eq 'display' }) }

# Is a Teams call on? $mic: [{name, stop}] from Windows' microphone privacy store (Get-MicUsage); stop = 0
# means the app holds the microphone now. $null means the store could not be read: only then do the
# Teams window titles decide, and only a title in Teams' own meeting-window form counts.
function Test-TeamsCall($mic, $wins) {
  if ($null -ne $mic) { return [bool]@($mic | ? { $_.name -match '(?i)(^|[#\\])(ms-teams|teams)\.exe$|^MSTeams_' -and [int64]$_.stop -eq 0 }).Count }
  [bool]@($wins | ? { $_.app -match '(?i)^(ms-teams|teams)$' -and $_.title -match '(?i)^(meeting|call)( (with|in) [^|]+)? \| Microsoft Teams$' }).Count
}
# ---- Triggers beyond the schedule: each one a pure function of its inputs. Win32 signals feed them in the tick below. ----
# The per-scene switches. Each is off unless the scene's .auto sets it true. The page's trigger editor lists the same names (a test checks).
$TileAutoFlags = @('desk', 'window', 'activity', 'size', 'gaps', 'offer', 'monitors', 'noext', 'grid')
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
  'grid.at' = 20; 'size.at' = 500; 'offer.leadMin' = 30; 'gaps.minutes' = 480; 'monitors.screens' = 8; 'noext.sec' = 600 }
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
function Get-GridSceneJson($sc, $grid) { $full = ConvertFrom-Json (ConvertTo-Json -Depth 8 -Compress $sc); $full.grids.wide = $grid; ConvertTo-Json -Depth 8 -Compress $full }
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
  lastManual = [datetime]::MinValue; lastActive = $null; manualApplyAt = [datetime]::MinValue; autoApplied = ''; displayAt = [datetime]::MinValue; callEndAt = [datetime]::MinValue } }
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
    $n = @($key -split ';').Count
    $d = @(Get-AutoScenes $cfg 'monitors' | ? { (Read-Num $_.screens 0 'monitors.screens') -eq $n })[0]; if (-not $d) { $d = @(Get-DisplayScenes $cfg)[0] }
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
  # A manual move cancels everything that was waiting before it.
  $ma = [datetime]$sig.manualAt
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
      $s.pend = @($s.pend | ? { $_ -ne $pick }); $s.lastAuto = $now; $s.autoApplied = $pick.id; if ($pick.kind -eq 'display') { $s.displayAt = $now }; $out += $pick
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
function Get-TeamsWindows { @(Get-Process ms-teams, Teams -ErrorAction SilentlyContinue | ? { $_.MainWindowTitle } | % { [pscustomobject]@{ app = $_.Name; title = $_.MainWindowTitle } }) }
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
if ($Lib) { return }

$quitName = TrayName 'Quit'; $openName = TrayName 'Open'
$created = $false; $mutex = New-Object Threading.Mutex($true, (TrayName 'Agent'), [ref]$created)
$linkOk = '^tilewindows://(open|undo\?run=[0-9a-f]{1,32}(\.[0-9a-f]{2,300})?)/?$'
if (-not $created) {
  if ($Link -match $linkOk) { Write-TileFile (Join-Path $TileHome 'link.txt') $Link; $e = [Threading.EventWaitHandle]::OpenExisting((TrayName 'Link')); [void]$e.Set() }
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
    try { Send-RunToast $gone } catch {}
  }
  return
}
$quitEv = New-Object Threading.EventWaitHandle($false, 'AutoReset', $quitName)
$openEv = New-Object Threading.EventWaitHandle($false, 'AutoReset', $openName)
$linkEv = New-Object Threading.EventWaitHandle($false, 'AutoReset', (TrayName 'Link'))

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
$tile = Join-Path $PSScriptRoot 'tile.ps1'; $serve = Join-Path $PSScriptRoot 'serve.ps1'
$srv = $null; $url = ''; $state = New-TrayState; $dirtyAt = $null; $tick = 0; $first = $true
$agendaRaw = $null; $offer = $null; $gridMode = @{}

# Any balloon replaces a pending offer, so a click on it never arranges.
function Note([string]$text) { $script:offer = $null; if ($icon) { $icon.ShowBalloonTip(4000, 'Tile Windows', $text, 'Info') } }
# The offer: a balloon that moves nothing. Clicking it arranges (for up to 3 minutes, or until another balloon shows).
function Offer-Scene($s, [string]$why) {
  $script:offer = [pscustomobject]@{ scene = $s; exp = (Get-Date).AddMinutes(3) }
  if ($icon) { $icon.ShowBalloonTip(15000, 'Meeting in 2 minutes', "Click to arrange your windows for $($s.name).", 'Info') }
}
function Read-Windows { try { @((((& $tile -Json 3>$null) -join '') | ConvertFrom-Json).windows) } catch { $null } }
# $prev: the scene on screen before this run ('' when unknown), so Undo can put it back.
function Apply-Scene($s, [string]$why, [string]$prev = '') {
  try {
    $arg = $s.id; $gridLine = ''
    # Grid follows the Claude count: the scene runs from its JSON with the ultrawide grid swapped.
    if ((Test-Auto $s 'grid') -and $s.claudeGrid) {
      $cn = @(Read-Windows | ? { $_.app -eq 'claude' -and -not $_.min }).Count
      $mode = Get-ClaudeMode $s $cn $gridMode[$s.id]
      if ($mode) { $gridMode[$s.id] = $mode; $arg = Get-GridSceneJson (Get-TileScene $s.id) $s.claudeGrid.$mode }
      if ($mode -eq 'dense') { $gridLine = "Dense grid: $cn $(Get-TileAppName 'claude') $(if ($cn -eq 1) { 'window' } else { 'windows' })." }
    }
    $r = (& $tile -Scene $arg -Json -DryRun:$NoApply 3>$null) -join '' | ConvertFrom-Json
    # A window counts as moved only when its rect changed: a run that puts every window where it already sits moves nothing.
    $moved = @($r.placed | ? { $_.note -eq 'moved' -and -not ($_.from -and $_.from.x -eq $_.x -and $_.from.y -eq $_.y -and $_.from.w -eq $_.w -and $_.from.h -eq $_.h) })
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
# The scene on screen now (state.json's active), '' when none or unreadable: the scene a run replaces, for Undo.
function Get-ActiveId { try { [string](ConvertFrom-Json (Get-TileStateText)).active } catch { '' } }
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
      if ($res.scene -and -not $NoApply) { Add-TileLog $res.scene "Undid $($rec.name): $($res.text)" }
      # A partial Undo (a window stayed, closed or was refused) pops up and says why; a clean one updates quietly.
      $partial = [bool](@($res.stayed).Count -or @($res.closed).Count -or @($res.refused).Count)
      Show-Toast (New-RunToast "$($rec.name) $(if ($partial) { 'partly undone' } else { 'undone' })" $res.text @() (-not $partial -and $res.placed -gt 0))
    } elseif ($res.status -eq 'later') {
      # $rec is the newer run: its record replaced the one this toast was for.
      $newer = $script:runUndo
      if ($newer -and -not $newer.done -and -not $newer.endedBy) { Show-Toast (New-NoUndoToast $name "$($newer.name) ran after it and moved windows. Undo $($newer.name) instead." @(@{ label = "Undo $($newer.name)"; launch = "tilewindows://undo?run=$($newer.id)" })) }
      else { Show-Toast (New-NoUndoToast $name 'A later run replaced it, so its places are out of date.' $TileOpenAction) }
    } elseif ($res.status -eq 'ended') { Show-Toast (New-NoUndoToast $name $res.text $TileOpenAction)
    } elseif ($res.status -eq 'done') { Show-Toast (New-RunToast "$($rec.name) undone" $res.text @())
    } else { Show-Toast (New-NoUndoToast $name $res.text $TileOpenAction) }
  } catch { Show-Toast (New-RunToast 'Undo failed' $_.Exception.Message) }
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
  if ([TileDisplayWatch]::Dirty) { [TileDisplayWatch]::Dirty = $false; $script:dirtyAt = Get-Date }
  $key = $null
  if ($first -or ($dirtyAt -and ((Get-Date) - $dirtyAt).TotalSeconds -ge 2)) { $script:first = $false; $script:dirtyAt = $null; $key = Get-MonitorKey ([Windows.Forms.Screen]::AllScreens) }
  # Teams calls: poll every 3 s while any scene applies itself (the in-call guard needs the reading too).
  $call = $null; $any = Test-AnyAuto $cfg; $n = ++$script:tick
  if (($n % 3) -eq 0 -and $any) { $call = Test-TeamsCall (Get-MicUsage) (Get-TeamsWindows) }
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
  foreach ($a in (Step-Tray $state (Get-Date) $cfg $key $call $active $sig)) { $sc = @($cfg.scenes | ? { $_.id -eq $a.id })[0]; if ($sc) { if ($a.offer) { Offer-Scene $sc $a.why } else { Apply-Scene $sc $a.why (Get-ActiveId) } } }
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
  $mutex.ReleaseMutex(); $mutex.Dispose(); $quitEv.Dispose(); $openEv.Dispose(); $linkEv.Dispose()
}
