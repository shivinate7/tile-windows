# Tile Windows tray agent: an icon in the notification area.
#   Menu: Open Tile Windows, Apply Scene >, Quit. Double-click opens the app.
#   Applies scenes on their trigger: a schedule (days + time), when the monitor set changes, or when a
#   Teams call starts (and, if the scene says so, goes back to the scene before when the call ends).
#   Also runs the per-scene switches in scene.auto (see README, Triggers): desk, window, activity, size, gaps, offer, monitors, noext, grid.
# -Open: open the app (starts the agent first if it is not running).
# -NoIcon: run without the icon (tests). -NoApply: every apply is a dry run (tests).
# -Lib: define the functions and return (tests dot-source it).
# One agent per profile. Signal the Quit event (as uninstall.ps1 does) to stop it.
param([switch]$Open, [switch]$NoIcon, [switch]$NoApply, [switch]$Lib)
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
# The activity map and the meeting-size rule: the config's own, else the starters' (a config from before they existed has none).
function Get-Tcfg($cfg) {
  if (-not $script:TileStarterCfg) { $script:TileStarterCfg = ConvertFrom-Json ([IO.File]::ReadAllText($TileStarters, $TileUtf8)) }
  [pscustomobject]@{ activity = @($(if ($cfg.activity) { $cfg.activity } else { $script:TileStarterCfg.activity })); size = $(if ($cfg.meetingSize) { $cfg.meetingSize } else { $script:TileStarterCfg.meetingSize }) }
}
# Today's meetings from agenda.json's parsed text: [{start, end, attendees, teams, showAs}], or $null when there is no agenda or it is not
# for today. Every agenda trigger does nothing on $null.
function Get-TodayAgenda($raw, [datetime]$now) {
  if (-not $raw) { return $null }
  $d = if ($raw.date -is [datetime]) { $raw.date.ToString('yyyy-MM-dd') } else { "$($raw.date)" }
  if ($d -ne $now.ToString('yyyy-MM-dd')) { return $null }
  , @(@($raw.events) | % { try { [pscustomobject]@{ start = [datetime]$_.start; end = [datetime]$_.end; attendees = [int]$_.attendees; teams = [bool]$_.teams; showAs = "$($_.showAs)".ToLower() } } catch {} })
}
function Test-Busy($e) { $e.showAs -in 'busy', 'oof' }
# The scene for a meeting of this size: Listen from 'at' attendees up, else Meetings. A call applies it only when that scene's size switch is on;
# the offer needs only the scene's offer switch.
function Get-SizeId($cfg, [int]$attendees) { $t = (Get-Tcfg $cfg).size; if ($attendees -ge [int]$t.at) { $t.big } else { $t.small } }
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

# Does a scene place this app? A pin names it, or the fill takes it ('*' = any app not skipped).
function Test-SceneApp($sc, [string]$app) {
  if (@($sc.pins | ? { $app -like $_.app }).Count) { return $true }
  foreach ($a in @($sc.fill.apps)) { if ($a -eq '*') { if (-not @($sc.fill.skip | ? { $app -like $_ }).Count) { return $true } } elseif ($app -like $a) { return $true } }
  $false
}
function New-Cand([string]$id, [string]$why, [string]$kind, $commit = $null) { [pscustomobject]@{ id = $id; why = $why; kind = $kind; offer = $false; commit = $commit; exp = $null } }
# New window finds its place: a window of a scene app, 400x300 or bigger, that appears and holds for 3 s re-flows the active scene.
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
  if (@($s.newSeen.Keys | ? { ($now - $s.newSeen[$_]).TotalSeconds -ge 3 }).Count) { $st = $s; New-Cand $active 'because a new window opened' 'window' ({ $st.newSeen = @{} }.GetNewClosure()) }
}
# Activity snap: one kind of app in front for 60 s, and the layout is not the scene that suits it. $fg: {app, title}, or $null when not read.
function Step-Activity($s, [datetime]$now, $cfg, $fg, [string]$active) {
  if ($null -eq $fg) { return }
  $map = @((Get-Tcfg $cfg).activity); $idx = -1
  for ($i = 0; $i -lt $map.Count; $i++) { if ($fg.app -like $map[$i].app -and (-not $map[$i].title -or $fg.title -match $map[$i].title)) { $idx = $i; break } }
  if (-not $s.act -or $s.act.key -ne "$idx") { $s.act = [pscustomobject]@{ key = "$idx"; since = $now; done = $false } }
  if ($idx -lt 0 -or $s.act.done) { return }
  $to = $map[$idx].scene
  if (-not (Test-Auto (Get-Scene $cfg $to) 'activity')) { return }
  if ($active -eq $to) { $s.act.done = $true; return }
  if (($now - $s.act.since).TotalSeconds -ge 60) { $a = $s.act; New-Cand $to 'because of what you are working in' 'activity' ({ $a.done = $true }.GetNewClosure()) }
}
# Focus in gaps: the next busy meeting is 60+ minutes off (or none is left), none is on now, and input was within 2 minutes. Once per gap.
function Step-Gaps($s, [datetime]$now, $cfg, $ev, [double]$idle, [bool]$locked, [string]$active) {
  $f = @(Get-AutoScenes $cfg 'gaps')[0]
  if ($null -eq $ev -or -not $f -or $locked -or $idle -ge 120) { return }
  $busy = @($ev | ? { Test-Busy $_ })
  if (@($busy | ? { $_.start -le $now -and $now -lt $_.end }).Count) { return }
  $next = @($busy | ? { $_.start -gt $now } | Sort-Object start)[0]
  if ($next -and ($next.start - $now).TotalMinutes -lt 60) { return }
  $k = $(if ($next) { $next.start.ToString('s') } else { 'none' })
  if ($s.gapKey -eq $k) { return }
  if ($active -eq $f.id) { $s.gapKey = $k; return }
  $st = $s; New-Cand $f.id 'because there is a gap before the next meeting' 'gaps' ({ $st.gapKey = $k }.GetNewClosure())
}
# No external monitor for 30 s: one screen left, then the laptop scene. $n: screen count, or $null when not read. The first reading only seeds.
function Step-NoExternal($s, [datetime]$now, $cfg, $n, [string]$active) {
  if ($null -eq $n) { return }
  if ($n -gt 1) { $s.soloSince = $null; $s.soloDone = $false; $s.screensSeen = $true; return }
  if (-not $s.screensSeen) { $s.screensSeen = $true; $s.soloDone = $true }
  if (-not $s.soloSince) { $s.soloSince = $now }
  $sc = @(Get-AutoScenes $cfg 'noext')[0]
  if ($s.soloDone -or -not $sc -or ($now - $s.soloSince).TotalSeconds -lt 30) { return }
  if ($active -eq $sc.id) { $s.soloDone = $true; return }
  $st = $s; New-Cand $sc.id 'because the external monitors are gone' 'noext' ({ $st.soloDone = $true }.GetNewClosure())
}
# The scene (with the config's category map attached, as Get-TileScene gives it) as JSON for tile.ps1 -Scene, its ultrawide grid swapped.
function Get-GridSceneJson($sc, $grid) { $full = ConvertFrom-Json (ConvertTo-Json -Depth 8 -Compress $sc); $full.grids.wide = $grid; ConvertTo-Json -Depth 8 -Compress $full }
# Grid follows the Claude count: the ultrawide grid a scene asks for at this many Claude windows, or $null.
function Get-ClaudeGrid($sc, [int]$n) { if (-not (Test-Auto $sc 'grid') -or -not $sc.claudeGrid) { return }; if ($n -ge [int]$sc.claudeGrid.at) { $sc.claudeGrid.dense } else { $sc.claudeGrid.roomy } }

function New-TrayState { [pscustomobject]@{ fired = @{}; lastKey = $null; inCall = $null; streak = 0; before = ''; callSet = $null
  pend = @(); lastAuto = [datetime]::MinValue; deskDay = ''; idled = $false; known = $null; newSeen = @{}; act = $null; gapKey = $null; offered = @{}; soloSince = $null; soloDone = $false; screensSeen = $false } }
$TileKindRank = @{ call = 0; display = 1; schedule = 2; desk = 3; window = 4; activity = 5; gaps = 6; noext = 7 }
# One tick of the agent, with no side effects but on $s. Returns the scenes to apply: [{id, why, kind, offer}].
# $key: the monitor key once the display has settled, else $null. $call: a call reading, or $null (not polled).
# The first key and the first call reading only seed $s, so starting the agent (or restarting it mid-call)
# applies nothing. A call starts or ends only after 2 readings in a row agree.
# $sig: the live signals {idleSec, locked, unlockedAfter, mouseDown, manualAt, wins, fg, screens, agenda}; $null runs only the
# schedule, display and call triggers, with no guards. With $sig, one pass of guards decides what may apply now:
#   during a call only the call trigger applies; nothing within 10 s of a manual move or while a mouse button is down;
#   at most one automatic apply per 30 s (the call trigger is exempt). A one-shot trigger that a guard holds back waits up to 60 s.
function Step-Tray($s, [datetime]$now, $cfg, $key, $call, [string]$active, $sig = $null) {
  $ev = @(); $agenda = $null
  if ($sig) { $agenda = Get-TodayAgenda $sig.agenda $now }
  foreach ($x in (Get-DueScenes $cfg $now $s.fired)) { $s.fired[$x.id] = $now.ToString('yyyy-MM-dd HH:mm'); $ev += New-Cand $x.id 'on schedule' 'schedule' }
  if ($key) {
    $n = @($key -split ';').Count
    $d = @(Get-AutoScenes $cfg 'monitors' | ? { [int]$_.screens -eq $n })[0]; if (-not $d) { $d = @(Get-DisplayScenes $cfg)[0] }
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
      if ($st.apply) { $ev += New-Cand $st.apply $(if ($call) { 'because a Teams call started' } else { 'because the call ended' }) 'call' }
    }
  }
  if (-not $sig) { return @($ev | % { $_.commit = $null; $_ }) }

  # Return to the desk: an unlock after 5+ minutes locked re-applies the active scene; the day's first unlock applies Default;
  # input after 10+ minutes idle with no lock in between re-applies the active scene.
  $day = $now.ToString('yyyy-MM-dd')
  if ($null -ne $sig.unlockedAfter) {
    $s.idled = $false; $first = $s.deskDay -ne $day; $s.deskDay = $day
    $to = if ($first -and (Test-Auto (Get-Scene $cfg 'default') 'desk')) { 'default' } elseif ([double]$sig.unlockedAfter -ge 300 -and (Test-Auto (Get-Scene $cfg $active) 'desk')) { $active }
    if ($to) { $ev += New-Cand $to 'because you are back at your desk' 'desk' }
  } elseif ([double]$sig.idleSec -ge 600) { $s.idled = $true }
  elseif ($s.idled -and [double]$sig.idleSec -lt 10) {
    $s.idled = $false
    if (Test-Auto (Get-Scene $cfg $active) 'desk') { $ev += New-Cand $active 'because you are back at your desk' 'desk' }
  }
  # One-shot triggers wait out a guard for up to 60 s, then drop.
  foreach ($e in $ev) { $e.exp = $now.AddSeconds(60) }
  $s.pend = @(@($s.pend | ? { $_.exp -gt $now }) + $ev)

  # Offer 2 minutes before a busy Teams meeting; it moves nothing, so no guard holds it. Once per meeting.
  $out = @()
  foreach ($e in @($agenda | ? { $_.teams -and (Test-Busy $_) -and $now -ge $_.start.AddMinutes(-2) -and $now -lt $_.start })) {
    $k = $e.start.ToString('s'); if ($s.offered[$k]) { continue }
    $s.offered[$k] = $true; $id = Get-SizeId $cfg $e.attendees
    if ($id -and (Test-Auto (Get-Scene $cfg $id) 'offer')) { $o = New-Cand $id 'a meeting starts in 2 minutes' 'offer'; $o.offer = $true; $out += $o }
  }

  $cand = @($s.pend) + @(Step-NewWindow $s $now $cfg $sig.wins $active) + @(Step-Activity $s $now $cfg $sig.fg $active) +
    @(Step-Gaps $s $now $cfg $agenda ([double]$sig.idleSec) ([bool]$sig.locked) $active) + @(Step-NoExternal $s $now $cfg $sig.screens $active)
  $cand = @($cand | ? { $_ })
  if ($s.inCall) { $s.pend = @($s.pend | ? { $_.kind -eq 'call' }); $cand = @($cand | ? { $_.kind -eq 'call' }) }
  $held = $sig.mouseDown -or ($now - [datetime]$sig.manualAt).TotalSeconds -lt 10
  if (-not $held) {
    $capped = ($now - $s.lastAuto).TotalSeconds -lt 30
    $pick = @($cand | ? { -not $capped -or $_.kind -eq 'call' } | Sort-Object { $TileKindRank[$_.kind] })[0]
    if ($pick) {
      if ($pick.commit) { & $pick.commit }
      $s.pend = @($s.pend | ? { $_ -ne $pick }); $s.lastAuto = $now; $out += $pick
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
if ($Lib) { return }

$quitName = TrayName 'Quit'; $openName = TrayName 'Open'
$created = $false; $mutex = New-Object Threading.Mutex($true, (TrayName 'Agent'), [ref]$created)
if (-not $created) { if ($Open) { $e = [Threading.EventWaitHandle]::OpenExisting($openName); [void]$e.Set() }; return }
$quitEv = New-Object Threading.EventWaitHandle($false, 'AutoReset', $quitName)
$openEv = New-Object Threading.EventWaitHandle($false, 'AutoReset', $openName)

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
$agendaRaw = $null; $offer = $null

# Any balloon replaces a pending offer, so a click on it never arranges.
function Note([string]$text) { $script:offer = $null; if ($icon) { $icon.ShowBalloonTip(4000, 'Tile Windows', $text, 'Info') } }
# The offer: a balloon that moves nothing. Clicking it arranges (for up to 3 minutes, or until another balloon shows).
function Offer-Scene($s, [string]$why) {
  $script:offer = [pscustomobject]@{ scene = $s; exp = (Get-Date).AddMinutes(3) }
  if ($icon) { $icon.ShowBalloonTip(15000, 'Meeting in 2 minutes', "Click to arrange your windows for $($s.name).", 'Info') }
}
function Read-Windows { try { @((((& $tile -Json 3>$null) -join '') | ConvertFrom-Json).windows) } catch { $null } }
function Apply-Scene($s, [string]$why) {
  try {
    $arg = $s.id
    # Grid follows the Claude count: the scene runs from its JSON with the ultrawide grid swapped.
    if ((Test-Auto $s 'grid') -and $s.claudeGrid) {
      $g = Get-ClaudeGrid $s @(Read-Windows | ? { $_.app -eq 'claude' -and -not $_.min }).Count
      if ($g) { $arg = Get-GridSceneJson (Get-TileScene $s.id) $g }
    }
    $r = (& $tile -Scene $arg -Json -DryRun:$NoApply 3>$null) -join '' | ConvertFrom-Json
    $n = @($r.placed | ? { $_.note -eq 'moved' }).Count
    $msg = "$($s.name) applied $why. Moved $n window(s)."
    if (-not $NoApply) { Add-TileLog $s.id $msg }
    Note $msg
  } catch { Note "$($s.name) failed: $($_.Exception.Message)" }
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
  foreach ($s in @($cfg.scenes)) { $it = $scenesItem.DropDownItems.Add($s.name); $it.Tag = $s; $it.add_Click({ param($o) Apply-Scene $o.Tag 'from the tray' }) }
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
  $icon.add_BalloonTipClicked({ $o = $script:offer; if ($o -and $o.exp -gt (Get-Date)) { $script:offer = $null; Apply-Scene $o.scene 'because you chose to arrange for the meeting' } })
}

$timer = New-Object Windows.Forms.Timer; $timer.Interval = 1000
$timer.add_Tick({
  if ($quitEv.WaitOne(0)) { [Windows.Forms.Application]::Exit(); return }
  if ($openEv.WaitOne(0)) { Open-App }
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
  $active = try { (ConvertFrom-Json (Get-TileStateText)).active } catch { '' }
  # A read here recovered from a bad file: the page shows the note until dismissed; the tray says it once.
  if ($TileNote) { Note $TileNote; $script:TileNote = '' }
  foreach ($a in (Step-Tray $state (Get-Date) $cfg $key $call $active $sig)) { $sc = @($cfg.scenes | ? { $_.id -eq $a.id })[0]; if ($sc) { if ($a.offer) { Offer-Scene $sc $a.why } else { Apply-Scene $sc $a.why } } }
})
$timer.Start()
if ($Open) { Open-App }
try { [Windows.Forms.Application]::Run() }
finally {
  $timer.Stop(); Stop-App
  if ($icon) { $icon.Visible = $false; $icon.Dispose() }
  $mutex.ReleaseMutex(); $mutex.Dispose(); $quitEv.Dispose(); $openEv.Dispose()
}
