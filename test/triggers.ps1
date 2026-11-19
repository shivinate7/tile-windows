# Checks for the automatic triggers in tray.ps1: for each, that it fires once, that its debounce holds, that its per-scene switch
# turns it off, that its thresholds come from the scene, and the global guards. One guard per check, so a red check names the guard.
# Pure functions only: no window moves, no real profile.
# Run alone: powershell -NoProfile -ExecutionPolicy Bypass -File test\triggers.ps1 [-Tray <path to a tray.ps1 copy>]
# test\run.ps1 dot-sources this file. test\redproof.ps1 runs it against scratch copies of tray.ps1, each with one guard broken.
param([string]$Tray = (Join-Path (Split-Path $PSScriptRoot) 'tray.ps1'))
$root = Split-Path $PSScriptRoot
# Run folder (test-temp-standard), as setup-plumbing.ps1 keeps it: <TEMP>\tile-windows-test-runs\<pid>-<UUID>, removed at the end.
$runRoot = Join-Path $env:TEMP 'tile-windows-test-runs'; New-Item -ItemType Directory -Force $runRoot | Out-Null
$runDir = Join-Path $runRoot ("$PID-" + [guid]::NewGuid().ToString()); New-Item -ItemType Directory $runDir | Out-Null
$standalone = -not (Get-Command Check -ErrorAction SilentlyContinue)
if ($standalone) {
  $ErrorActionPreference = 'Stop'; $script:fail = 0
  function Check($name, $ok, $detail = '') { if ($ok) { "PASS  $name" } else { $script:fail++; "FAIL  $name  $detail" } }
}
. $Tray -Lib

function Ids($x) { (@($x) | % { $_.id }) -join ',' }
function Sig($o = @{}) {
  $d = @{ idleSec = 0; locked = $false; unlockedAfter = $null; mouseDown = $false; manualAt = [datetime]::MinValue; wins = $null; fg = $null; screens = $null; agenda = $null }
  foreach ($k in $o.Keys) { $d[$k] = $o[$k] }; [pscustomobject]$d
}
# One tick. Returns the ids applied, comma-joined.
function Run($s, [datetime]$t, $cfg, $sig, [string]$active = 'plain', $key = $null, $call = $null) { Ids (Step-Tray $s $t $cfg $key $call $active $sig) }
function Win($id, $app, $w = 900, $h = 700) { [pscustomobject]@{ id = $id; app = $app; title = "$app $id"; w = $w; h = $h } }
function Agenda($events, $date = '2026-10-21') { ConvertFrom-Json (@{ date = $date; events = $events } | ConvertTo-Json -Depth 5) }
function Ev($start, $end, $att = 4, $teams = $true, $showAs = 'busy') { @{ start = "2026-10-21T$start"; end = "2026-10-21T$end"; attendees = $att; teams = $teams; showAs = $showAs } }
function Scene($id, $auto = @{}, $extra = @{}) {
  $o = [ordered]@{ id = $id; name = $id; trigger = @{ type = 'manual' }; auto = $auto; pins = @(@{ app = 'chrome' }); fill = @{ apps = @('claude'); skip = @('outlook') } }
  foreach ($k in $extra.Keys) { $o[$k] = $extra[$k] }; $o
}
function Cfg($scenes) {
  ConvertFrom-Json (ConvertTo-Json -Depth 8 @{ scenes = $scenes; meetingSize = @{ at = 25; big = 'listen'; small = 'meetings' }
    activity = @(@{ app = 'chrome'; title = 'Procore'; scene = 'review' }, @{ app = 'claude'; scene = 'focus' }) })
}
function StdScenes($over = @{}) {
  $a = @{ default = @{ desk = $true }; focus = @{ desk = $true; window = $true }; review = @{ activity = $true }
    meetings = @{ size = $true; offer = $true }; listen = @{ size = $true; offer = $true }; solo = @{ setup = $true; noext = $true }; plain = @{} }
  foreach ($k in $over.Keys) { $a[$k] = $over[$k] }
  @($a.Keys | % { if ($_ -eq 'solo') { Scene $_ $a[$_] @{ setupKey = $k1 } } else { Scene $_ $a[$_] } })
}
# A config in which one scene carries threshold values of its own.
function WithOpt($id, $optJson, $over = @{}) { $c = Cfg (StdScenes $over); @($c.scenes | ? { $_.id -eq $id })[0] | Add-Member -Force opt (ConvertFrom-Json $optJson); $c }
# Setup keys (decision monitor-setups): the plugged-in monitor ids, sorted and joined with '|'. A scene made on a setup carries its key as setupKey.
$k1 = 'LEN3'; $k2 = 'AUO1|LEN3'; $k3 = 'AUO1|DEL2|LEN3'
$cfg = Cfg (StdScenes)
$cfgG = Cfg (StdScenes @{ focus = @{ desk = $true; window = $true; gaps = $true } })  # Focus in gaps on: it would answer any agenda, so only its own checks use it
$t0 = [datetime]'2026-10-21 10:00:00'  # a Wednesday; no scene is scheduled
$day = [datetime]'2026-10-21 08:00:00'
function Joined($x) { $x -join '/' }

# ---- Return to the desk ----
$s = New-TrayState; $r = Run $s $day $cfg (Sig @{ unlockedAfter = 20 }) 'focus'
Check 'desk: the first unlock of the day applies Default' ($r -eq 'default') $r
$s = New-TrayState; $s.deskDay = '2026-10-21'; $r = Run $s $day $cfg (Sig @{ unlockedAfter = 200 }) 'focus'
Check 'desk: a lock under 5 min does nothing' ($r -eq '') $r
$s = New-TrayState; $s.deskDay = '2026-10-21'; $r = Run $s $day $cfg (Sig @{ unlockedAfter = 400 }) 'focus'
Check 'desk: an unlock after 5+ min re-applies the active scene' ($r -eq 'focus') $r
$s = New-TrayState; $s.deskDay = '2026-10-21'; $r = Run $s $day $cfg (Sig @{ unlockedAfter = 400 }) 'plain'
Check 'desk: a scene with the switch off is not re-applied on unlock' ($r -eq '') $r
$s = New-TrayState; $c2 = Cfg (StdScenes @{ default = @{} }); $r = @((Run $s $day $c2 (Sig @{ unlockedAfter = 20 }) 'plain'), (Run $s $day.AddMinutes(30) $c2 (Sig @{ unlockedAfter = 20 }) 'plain'))
Check 'desk: with Default off the first unlock applies nothing, and uses up the day' ((Joined $r) -eq '/') (Joined $r)
$s = New-TrayState; $r = @((Run $s $t0 $cfg (Sig @{ idleSec = 700 }) 'focus'), (Run $s $t0.AddSeconds(5) $cfg (Sig @{ idleSec = 3 }) 'focus'), (Run $s $t0.AddSeconds(60) $cfg (Sig @{ idleSec = 3 }) 'focus'))
Check 'desk: input after 10+ min idle re-applies the active scene, once' ((Joined $r) -eq '/focus/') (Joined $r)
$s = New-TrayState; $r = @((Run $s $t0 $cfg (Sig @{ idleSec = 400 }) 'focus'), (Run $s $t0.AddSeconds(5) $cfg (Sig @{ idleSec = 3 }) 'focus'))
Check 'desk: under 10 min idle does nothing' ((Joined $r) -eq '/') (Joined $r)
$s = New-TrayState; $s.deskDay = '2026-10-21'
$r = @((Run $s $t0 $cfg (Sig @{ idleSec = 700 }) 'focus'), (Run $s $t0.AddSeconds(5) $cfg (Sig @{ idleSec = 705; locked = $true }) 'focus'), (Run $s $t0.AddSeconds(710) $cfg (Sig @{ unlockedAfter = 705 }) 'focus'), (Run $s $t0.AddSeconds(715) $cfg (Sig @{ idleSec = 2 }) 'focus'), (Run $s $t0.AddSeconds(750) $cfg (Sig @{ idleSec = 2 }) 'focus'))
Check 'desk: a lock inside an idle span applies once, not twice' ((Joined $r) -eq '//focus//') (Joined $r)
$s = New-TrayState; $c2 = Cfg (StdScenes @{ focus = @{} }); $r = @((Run $s $t0 $c2 (Sig @{ idleSec = 700 }) 'focus'), (Run $s $t0.AddSeconds(5) $c2 (Sig @{ idleSec = 3 }) 'focus'))
Check 'desk: the off switch on the active scene stops the idle trigger' ((Joined $r) -eq '/') (Joined $r)
$s = New-TrayState; $s.deskDay = '2026-10-21'; $r = Run $s $day (WithOpt 'focus' '{"desk":{"lockMin":1}}' @{ focus = @{ desk = $true } }) (Sig @{ unlockedAfter = 90 }) 'focus'
Check 'threshold: the lock length for return to the desk comes from the scene' ($r -eq 'focus') $r
$s = New-TrayState; $c2 = WithOpt 'focus' '{"desk":{"idleMin":1}}' @{ focus = @{ desk = $true } }; $r = @((Run $s $t0 $c2 (Sig @{ idleSec = 70 }) 'focus'), (Run $s $t0.AddSeconds(5) $c2 (Sig @{ idleSec = 3 }) 'focus'))
Check 'threshold: the idle length for return to the desk comes from the scene' ((Joined $r) -eq '/focus') (Joined $r)

# ---- New window finds its place ----
$w1 = Win 1 claude; $w2 = Win 2 claude
function WinRun($s, $secs, $wins, $cfg = $cfg, $active = 'focus', $o = @{}) { $o.wins = @($wins); Run $s $t0.AddSeconds($secs) $cfg (Sig $o) $active }
$s = New-TrayState; $x = @((WinRun $s 0 @($w1)), (WinRun $s 3 @($w1, $w2)), (WinRun $s 5 @($w1, $w2)), (WinRun $s 6 @($w1, $w2)), (WinRun $s 9 @($w1, $w2)))
Check 'new window: a window of a scene app that holds 3 s re-flows the active scene, once' ((Joined $x) -eq '///focus/') (Joined $x)
$s = New-TrayState; $x = @((WinRun $s 0 @($w1)), (WinRun $s 3 @($w1, $w2)), (WinRun $s 5 @($w1)), (WinRun $s 8 @($w1)))
Check 'new window: a window gone before 3 s does nothing' ((Joined $x) -eq '///') (Joined $x)
$s = New-TrayState; $sm = Win 2 claude 300 200; $x = @((WinRun $s 0 @($w1)), (WinRun $s 3 @($w1, $sm)), (WinRun $s 9 @($w1, $sm)))
Check 'new window: a window under 400x300 does nothing' ((Joined $x) -eq '//') (Joined $x)
$s = New-TrayState; $np = Win 3 notepad; $x = @((WinRun $s 0 @($w1)), (WinRun $s 3 @($w1, $np)), (WinRun $s 9 @($w1, $np)))
Check 'new window: an app the scene does not place does nothing' ((Joined $x) -eq '//') (Joined $x)
$s = New-TrayState; $x = @((WinRun $s 0 @($w1) $cfg 'plain'), (WinRun $s 3 @($w1, $w2) $cfg 'plain'), (WinRun $s 9 @($w1, $w2) $cfg 'plain'))
Check 'new window: a scene with the switch off does nothing' ((Joined $x) -eq '//') (Joined $x)
$s = New-TrayState; $x = @((WinRun $s 0 @($w1)), (WinRun $s 1 @($w1) $cfg 'focus' @{ manualAt = $t0.AddSeconds(1) }), (WinRun $s 3 @($w1, $w2) $cfg 'focus' @{ manualAt = $t0.AddSeconds(1) }), (WinRun $s 6 @($w1, $w2) $cfg 'focus' @{ manualAt = $t0.AddSeconds(1) }), (WinRun $s 12 @($w1, $w2) $cfg 'focus' @{ manualAt = $t0.AddSeconds(1) }))
Check 'new window: a window that opens after a manual move waits until the move is 10 s old' ((Joined $x) -eq '////focus') (Joined $x)
$s = New-TrayState; $x = @((WinRun $s 0 @($w1)), (WinRun $s 3 @($w1, $w2)), (WinRun $s 5 @($w1, $w2) $cfg 'focus' @{ manualAt = $t0.AddSeconds(5) }), (WinRun $s 16 @($w1, $w2) $cfg 'focus' @{ manualAt = $t0.AddSeconds(5) }), (WinRun $s 40 @($w1, $w2) $cfg 'focus' @{ manualAt = $t0.AddSeconds(5) }))
Check 'new window: a manual move cancels a window that was waiting, so the re-flow does not undo it' ((Joined $x) -eq '////') (Joined $x)
$s = New-TrayState; $x = @((WinRun $s 0 @($w1)), (WinRun $s 3 @($w1, $w2)), (WinRun $s 9 @($w1, $w2) $cfg 'focus' @{ mouseDown = $true }), (WinRun $s 10 @($w1, $w2)))
Check 'new window: never while a mouse button is down; it re-flows when the button is up' ((Joined $x) -eq '//' + '/focus') (Joined $x)
$s = New-TrayState; $c2 = WithOpt 'focus' '{"window":{"holdSec":1}}' @{ focus = @{ window = $true } }; $x = @((WinRun $s 0 @($w1) $c2), (WinRun $s 3 @($w1, $w2) $c2), (WinRun $s 5 @($w1, $w2) $c2))
Check 'threshold: how long a new window must hold comes from the scene' ((Joined $x) -eq '//focus') (Joined $x)

# ---- Activity snap ----
function FgRun($s, $secs, $app, $title, $cfg = $cfg, $active = 'plain') { Run $s $t0.AddSeconds($secs) $cfg (Sig @{ fg = [pscustomobject]@{ app = $app; title = $title } }) $active }
$s = New-TrayState; $x = @((FgRun $s 0 chrome 'Budget - Procore - Google Chrome'), (FgRun $s 59 chrome 'Budget - Procore - Google Chrome'), (FgRun $s 60 chrome 'Budget - Procore - Google Chrome'), (FgRun $s 120 chrome 'Budget - Procore - Google Chrome'))
Check 'activity: a minute in Procore (Chrome) snaps to Review, once; 59 s does not' ((Joined $x) -eq '//review/') (Joined $x)
$s = New-TrayState; $x = @((FgRun $s 0 chrome 'Procore'), (FgRun $s 50 notepad 'x'), (FgRun $s 60 chrome 'Procore'), (FgRun $s 119 chrome 'Procore'), (FgRun $s 120 chrome 'Procore'))
Check 'activity: leaving the app starts the minute over' ((Joined $x) -eq '////review') (Joined $x)
$s = New-TrayState; $x = @((FgRun $s 0 chrome 'Procore' $cfg 'review'), (FgRun $s 90 chrome 'Procore' $cfg 'review'))
Check 'activity: nothing when the layout already is that scene' ((Joined $x) -eq '/') (Joined $x)
$s = New-TrayState; $x = @((FgRun $s 0 chrome 'Gmail'), (FgRun $s 90 chrome 'Gmail'))
Check 'activity: an app or title not in the map does nothing' ((Joined $x) -eq '/') (Joined $x)
$s = New-TrayState; $x = @((FgRun $s 0 claude 'Claude'), (FgRun $s 90 claude 'Claude'))
Check 'activity: a mapped scene with the switch off does nothing' ((Joined $x) -eq '/') (Joined $x)
$s = New-TrayState; $x = @((FgRun $s 0 chrome 'Procore' $cfg 'plain'), (FgRun $s 10 chrome 'Procore' $cfg 'focus'), (FgRun $s 90 chrome 'Procore' $cfg 'focus'), (FgRun $s (16 * 60 + 10) chrome 'Procore' $cfg 'focus'))
Check 'activity: a scene applied by hand is left alone for 15 minutes, then the snap may happen' ((Joined $x) -eq '///review') (Joined $x)
$s = New-TrayState; $x = @((Run $s $day $cfg (Sig @{ unlockedAfter = 20 }) 'plain'), (FgRun $s 70 chrome 'Procore' $cfg 'default'), (FgRun $s 140 chrome 'Procore' $cfg 'default'))
Check 'activity: a scene the agent applied itself is not taken for one applied by hand' ((Joined $x) -eq 'default//review') (Joined $x)
$s = New-TrayState; $c2 = WithOpt 'review' '{"activity":{"dwellSec":10}}' @{ review = @{ activity = $true } }; $x = @((FgRun $s 0 chrome 'Procore' $c2), (FgRun $s 10 chrome 'Procore' $c2))
Check 'threshold: how long the snap waits comes from the scene' ((Joined $x) -eq '/review') (Joined $x)
$s = New-TrayState; $c2 = WithOpt 'review' '{"activity":{"graceMin":1}}' @{ review = @{ activity = $true } }; $x = @((FgRun $s 0 chrome 'Procore' $c2 'plain'), (FgRun $s 10 chrome 'Procore' $c2 'focus'), (FgRun $s 90 chrome 'Procore' $c2 'focus'))
Check 'threshold: the grace after a hand-applied scene comes from the scene' ((Joined $x) -eq '//review') (Joined $x)
$s = New-TrayState; $sg = @{ fg = [pscustomobject]@{ app = 'chrome'; title = 'Procore' } }
$x = @((Run $s $t0 $cfg (Sig $sg)), (Run $s $t0.AddSeconds(30) $cfg (Sig @{ fg = $sg.fg; manualAt = $t0.AddSeconds(30) })), (Run $s $t0.AddSeconds(80) $cfg (Sig @{ fg = $sg.fg; manualAt = $t0.AddSeconds(30) })), (Run $s $t0.AddSeconds(100) $cfg (Sig @{ fg = $sg.fg; manualAt = $t0.AddSeconds(30) })))
Check 'activity: a manual move restarts the dwell, so a snap does not undo the move' ((Joined $x) -eq '///review') (Joined $x)

# ---- Meeting size picks the call scene; a missing, stale or unreadable agenda does nothing ----
function CallRun($agenda, $cfg = $cfg, $active = 'plain') {
  $s = New-TrayState; $sg = Sig @{ agenda = $agenda }
  Joined @((Run $s $t0 $cfg $sg $active $null $false), (Run $s $t0.AddSeconds(3) $cfg $sg $active $null $true), (Run $s $t0.AddSeconds(6) $cfg $sg $active $null $true), (Run $s $t0.AddSeconds(9) $cfg $sg $active $null $true))
}
$r = CallRun (Agenda @(Ev '09:55' '11:00' 30)); Check 'size: a call with 25+ attendees applies Listen, once' ($r -eq '//listen/') $r
$r = CallRun (Agenda @(Ev '09:55' '11:00' 5)); Check 'size: a smaller call applies Meetings' ($r -eq '//meetings/') $r
$r = CallRun (Agenda @(Ev '13:00' '14:00' 30)); Check 'size: a call outside any meeting does nothing' ($r -eq '///') $r
$r = CallRun (Agenda @(Ev '09:55' '11:00' 30 $true 'free')); Check 'size: a call in a free slot does nothing' ($r -eq '///') $r
$r = CallRun (Agenda @(Ev '09:55' '11:00' 30 $false)); Check 'size: a meeting without Teams does nothing' ($r -eq '///') $r
$r = CallRun (Agenda @(Ev '09:55' '11:00' 30 'no')); Check 'size: "teams": "no" reads as false' ($r -eq '///') $r
$r = CallRun (Agenda @(Ev '09:55' '11:00' 'many')); Check 'size: an event whose attendee count is not a number is dropped' ($r -eq '///') $r
$r = CallRun $null; Check 'size: no agenda does nothing' ($r -eq '///') $r
$r = CallRun (Agenda @(Ev '09:55' '11:00' 30) '2026-10-20'); Check 'size: an agenda for another day does nothing' ($r -eq '///') $r
$c2 = Cfg (StdScenes @{ meetings = @{}; listen = @{} }); $r = CallRun (Agenda @(Ev '09:55' '11:00' 30)) $c2; Check 'size: with the switch off on both scenes it does nothing' ($r -eq '///') $r
$c2 = Cfg (StdScenes @{ listen = @{} }); $r = CallRun (Agenda @(Ev '09:55' '11:00' 30)) $c2; Check 'size: the switch is per scene: Listen off, a big call applies nothing' ($r -eq '///') $r
$r = CallRun (Agenda @(Ev '09:55' '11:00' 12)) (WithOpt 'listen' '{"size":{"at":10}}'); Check 'threshold: the size that counts as a big call comes from Listen' ($r -eq '//listen/') $r

# ---- Focus in gaps ----
function GapRun($agenda, $idle = 30, $cfg = $cfgG, $active = 'plain', $secs = 0) { $s = New-TrayState; Run $s $t0.AddSeconds($secs) $cfg (Sig @{ agenda = $agenda; idleSec = $idle }) $active }
$ag = Agenda @(Ev '11:30' '12:00')
$r = GapRun $ag; Check 'gaps: the next busy meeting 60+ min off and the PC touched lately applies Focus' ($r -eq 'focus') $r
$s = New-TrayState; $x = @((Run $s $t0 $cfgG (Sig @{ agenda = $ag; idleSec = 30 })), (Run $s $t0.AddSeconds(60) $cfgG (Sig @{ agenda = $ag; idleSec = 30 })), (Run $s $t0.AddMinutes(10) $cfgG (Sig @{ agenda = $ag; idleSec = 30 })))
Check 'gaps: once per gap' ((Joined $x) -eq 'focus//') (Joined $x)
$r = GapRun (Agenda @(Ev '10:30' '11:00')); Check 'gaps: not when the next busy meeting is under 60 min off' ($r -eq '') $r
$r = GapRun (Agenda @(Ev '09:30' '10:30') + @(Ev '13:00' '14:00')); Check 'gaps: not while a busy meeting is on' ($r -eq '') $r
$r = GapRun $ag 200; Check 'gaps: not when the last input was 2+ min ago' ($r -eq '') $r
$r = GapRun (Agenda @(Ev '10:20' '10:50' 4 $true 'free')); Check 'gaps: a free slot is not a meeting, so with no busy meeting left it does nothing' ($r -eq '') $r
$r = GapRun (Agenda @(Ev '08:00' '09:00')); Check 'gaps: with no meeting left today it does nothing' ($r -eq '') $r
$r = GapRun $null; Check 'gaps: no agenda does nothing' ($r -eq '') $r
$r = GapRun (Agenda @(Ev '11:30' '12:00') '2026-10-20'); Check 'gaps: an agenda for another day does nothing' ($r -eq '') $r
$r = GapRun $ag 30 $cfg; Check 'gaps: with the switch off it does nothing' ($r -eq '') $r
$r = GapRun $ag 30 $cfgG 'focus'; Check 'gaps: nothing when Focus is already on screen' ($r -eq '') $r
$s = New-TrayState; $cg2 = Cfg (StdScenes @{ focus = @{ gaps = $true }; meetings = @{ size = $true } }); $ga = Agenda @(Ev '11:30' '12:00')
function GSig($idle) { Sig @{ agenda = $ga; idleSec = $idle } }
$x = @((Run $s $t0 $cg2 (GSig 300) 'plain' $null $false), (Run $s $t0.AddSeconds(3) $cg2 (GSig 300) 'plain' $null $true), (Run $s $t0.AddSeconds(6) $cg2 (GSig 300) 'plain' $null $true), (Run $s $t0.AddSeconds(100) $cg2 (GSig 300) 'plain' $null $false), (Run $s $t0.AddSeconds(103) $cg2 (GSig 300) 'plain' $null $false), (Run $s $t0.AddSeconds(110) $cg2 (GSig 30) 'plain'), (Run $s $t0.AddMinutes(13) $cg2 (GSig 30) 'plain'))
Check 'gaps: never within 10 minutes of a call ending' ((Joined $x) -eq '//////focus') (Joined $x)
$r = GapRun (Agenda @(Ev '10:40' '11:00')) 30 (WithOpt 'focus' '{"gaps":{"minutes":30}}' @{ focus = @{ gaps = $true } }); Check 'threshold: the gap length comes from the scene' ($r -eq 'focus') $r

# ---- Offer before a meeting ----
function OfferTick($agenda, $secs, $s = (New-TrayState), $cfg = $cfg, $o = @{}) { $o.agenda = $agenda; Step-Tray $s ([datetime]'2026-10-21 10:58:00').AddSeconds($secs) $cfg $null $null 'plain' (Sig $o) }
$ag = Agenda @(Ev '11:00' '12:00' 30)
$s = New-TrayState; $x = @((OfferTick $ag -1 $s), (OfferTick $ag 0 $s), (OfferTick $ag 10 $s), (OfferTick $ag 119 $s))
Check 'offer: 2 min before a busy Teams meeting it offers the scene for its size, once, and moves nothing itself' (@($x[0]).Count -eq 0 -and @($x[1]).Count -eq 1 -and $x[1].id -eq 'listen' -and $x[1].offer -eq $true -and @($x[2]).Count -eq 0 -and @($x[3]).Count -eq 0) (($x | % { Ids $_ }) -join '/')
Check 'offer: a small meeting offers Meetings' ((OfferTick (Agenda @(Ev '11:00' '12:00' 4)) 0).id -eq 'meetings')
Check 'offer: a meeting that is not on Teams is not offered' (@(OfferTick (Agenda @(Ev '11:00' '12:00' 4 $false)) 0).Count -eq 0)
Check 'offer: a meeting that is not busy is not offered' (@(OfferTick (Agenda @(Ev '11:00' '12:00' 4 $true 'free')) 0).Count -eq 0)
Check 'offer: no agenda offers nothing' (@(OfferTick $null 0).Count -eq 0)
Check 'offer: an agenda for another day offers nothing' (@(OfferTick (Agenda @(Ev '11:00' '12:00') '2026-10-20') 0).Count -eq 0)
Check 'offer: with the switch off it offers nothing' (@(OfferTick $ag 0 (New-TrayState) (Cfg (StdScenes @{ meetings = @{ size = $true }; listen = @{ size = $true } }))).Count -eq 0)
Check 'offer: its own switch is enough: size off, offer on, still offers' ((OfferTick $ag 0 (New-TrayState) (Cfg (StdScenes @{ meetings = @{ offer = $true }; listen = @{ offer = $true } }))).id -eq 'listen')
Check 'offer: a held mouse does not hold an offer back' ((OfferTick $ag 0 (New-TrayState) $cfg @{ mouseDown = $true }).offer -eq $true)
Check 'threshold: how far ahead the offer comes is the scene''s' ((OfferTick $ag -150 (New-TrayState) (WithOpt 'listen' '{"offer":{"leadMin":5}}')).id -eq 'listen' -and @(OfferTick $ag -150 (New-TrayState) $cfg).Count -eq 0)
$r = try { Ids (OfferTick $ag 0 (New-TrayState) (WithOpt 'listen' '{"offer":{"leadMin":"soon"}}')) } catch { 'threw' }
Check 'threshold: a value that does not read falls back to the default, and nothing throws' ($r -eq 'listen' -and (Get-Opt $cfg (ConvertFrom-Json '{"opt":{"gaps":{"minutes":"abc"}}}') 'gaps' 'minutes') -eq 60) $r
Check 'threshold: a value over its cap is held at the cap, so a huge offer lead does not offer a meeting 2 h off' (@(OfferTick (Agenda @(Ev '13:00' '14:00' 30)) 0 (New-TrayState) (WithOpt 'listen' '{"offer":{"leadMin":9999}}')).Count -eq 0 -and (Get-Opt $cfg (ConvertFrom-Json '{"opt":{"offer":{"leadMin":9999}}}') 'offer' 'leadMin') -eq 30)
Check 'agenda: an event that ends before it starts is dropped' (@(OfferTick (Agenda @(Ev '11:00' '10:30' 30)) 0).Count -eq 0)


# ---- A scene per monitor set: "Use This Scene on This Setup" (owner ruling Q4 A, 2026-11-17 09:47 CST, replaces the count switch) ----
# No external monitor for 30 s is below. The setup key of the plugged-in monitors is the key the tray reads; a rearrange of the same ids keeps it (setup-plumbing.ps1).
function KeyRun($s, $key, $cfg = $cfg, $secs = 0) { Run $s $t0.AddSeconds($secs) $cfg (Sig) 'plain' $key }
$s = New-TrayState; $x = @((KeyRun $s $k2), (KeyRun $s $k1 $cfg 5), (KeyRun $s $k1 $cfg 10))
Check 'setup: a scene made on a setup applies when that setup is plugged in, once' ((Joined $x) -eq '/solo/') (Joined $x)
$s = New-TrayState; $x = @((KeyRun $s $k1), (KeyRun $s $k2 $cfg 5))
Check 'setup: a setup no scene is made on applies nothing' ((Joined $x) -eq '/') (Joined $x)
$s = New-TrayState; $c2 = Cfg (StdScenes @{ solo = @{ noext = $true } }); $x = @((KeyRun $s $k2 $c2), (KeyRun $s $k1 $c2 5))
Check 'setup: with the switch off it applies nothing' ((Joined $x) -eq '/') (Joined $x)
function ScrRun($s, $secs, $n, $cfg = $cfg, $active = 'plain', $o = @{}) { $o.screens = $n; Run $s $t0.AddSeconds($secs) $cfg (Sig $o) $active }
$s = New-TrayState; $x = @((ScrRun $s 0 2), (ScrRun $s 10 1), (ScrRun $s 39 1), (ScrRun $s 40 1), (ScrRun $s 100 1), (ScrRun $s 110 2), (ScrRun $s 120 1), (ScrRun $s 150 1))
Check 'no external: 30 s with one screen applies the laptop scene, once per absence' ((Joined $x) -eq '///solo////solo') (Joined $x)
$s = New-TrayState; $x = @((ScrRun $s 0 1), (ScrRun $s 60 1))
Check 'no external: starting the agent on one screen applies nothing' ((Joined $x) -eq '/') (Joined $x)
$s = New-TrayState; $c2 = Cfg (StdScenes @{ solo = @{ setup = $true } }); $x = @((ScrRun $s 0 2 $c2), (ScrRun $s 10 1 $c2), (ScrRun $s 50 1 $c2))
Check 'no external: with the switch off it applies nothing' ((Joined $x) -eq '//') (Joined $x)
$s = New-TrayState; $x = @((ScrRun $s 0 2), (ScrRun $s 10 1 $cfg 'plain' @{ locked = $true }), (ScrRun $s 50 1 $cfg 'plain' @{ locked = $true }), (ScrRun $s 60 1), (ScrRun $s 100 1))
Check 'no external: a locked PC does not count (a monitor that sleeps drops out)' ((Joined $x) -eq '////solo') (Joined $x)
$s = New-TrayState; $x = @((ScrRun $s 0 2), (ScrRun $s 10 1 $cfg 'plain' @{ idleSec = 300 }), (ScrRun $s 50 1 $cfg 'plain' @{ idleSec = 340 }), (ScrRun $s 60 1), (ScrRun $s 100 1))
Check 'no external: an idle PC does not count' ((Joined $x) -eq '////solo') (Joined $x)
$s = New-TrayState; $c2 = Cfg (StdScenes); $x = @((Run $s $t0 $c2 (Sig @{ screens = 2 }) 'plain' $k2), (Run $s $t0.AddSeconds(10) $c2 (Sig @{ screens = 1 }) 'plain' $k1), (Run $s $t0.AddSeconds(40) $c2 (Sig @{ screens = 1 }) 'plain' $k1), (Run $s $t0.AddSeconds(100) $c2 (Sig @{ screens = 1 }) 'plain' $k1))
Check 'no external: a setup scene applied a moment ago is the same event, so it does not apply again' ((Joined $x) -eq '/solo//') (Joined $x)
$s = New-TrayState; $x = @((ScrRun $s 0 2 (WithOpt 'solo' '{"noext":{"sec":10}}')), (ScrRun $s 5 1 (WithOpt 'solo' '{"noext":{"sec":10}}')), (ScrRun $s 15 1 (WithOpt 'solo' '{"noext":{"sec":10}}')))
Check 'threshold: how long the monitors must be gone comes from the scene' ((Joined $x) -eq '//solo') (Joined $x)

# ---- Thursday prep and the starters ----
$st = ConvertFrom-Json ([IO.File]::ReadAllText((Join-Path $root 'scenes.json')))
$new = @($st.scenes | ? { $_.id -in 'listen', 'solo', 'thursday-prep' })
Check 'starters: Listen, Solo and Thursday Prep exist' ($new.Count -eq 3)
Check 'starters: every scene lists every trigger switch' (@($st.scenes | ? { (@($_.auto.PSObject.Properties.Name) -join ',') -ne ($TileAutoFlags -join ',') }).Count -eq 0)
Check 'starters: every automatic-trigger switch ships off' (@($st.scenes | ? { @($_.auto.PSObject.Properties | ? { $_.Value -ne $false }).Count }).Count -eq 0)
$th = @($st.scenes | ? { $_.id -eq 'thursday-prep' })[0]
Check 'starters: Thursday Prep is set for Thursday 14:30 and pins Procore in Chrome' ($th -and @($th.trigger.days) -join ',' -eq '4' -and $th.trigger.time -eq '14:30' -and @($th.pins | ? { $_.app -eq 'chrome' -and $_.match -eq 'Procore' }).Count -eq 1)
$tc = ConvertFrom-Json '{"scenes":[{"id":"t","trigger":{"type":"time","days":[4],"time":"14:30"}}]}'
Check 'starters: a Thursday 14:30 schedule is due that minute only' ((Ids (Get-DueScenes $tc ([datetime]'2026-10-22 14:30:10') @{})) -eq 't' -and @(Get-DueScenes $tc ([datetime]'2026-10-21 14:30:10') @{}).Count -eq 0)
Check 'starters: every threshold has a default' (($st.optDefaults.PSObject.Properties | % { $f = $_.Name; $_.Value.PSObject.Properties | % { "$f.$($_.Name)=$($_.Value)" } }) -join ',' -eq 'desk.lockMin=5,desk.idleMin=10,window.holdSec=3,activity.dwellSec=60,activity.graceMin=15,gaps.minutes=60,offer.leadMin=2,noext.sec=30')
$page = [IO.File]::ReadAllText((Join-Path $root 'app.html'))
$off = $page -match '(?s)const AUTO=\[(.*?)\n\];'
$names = if ($off) { @([regex]::Matches($matches[1], '(?m)^\["(\w+)"') | % { $_.Groups[1].Value }) }
Check 'starters: the page edits the same trigger switches as the tray' ($off -and (($names | sort) -join ',') -eq (($TileAutoFlags | sort) -join ',')) ($names -join ',')
# The setup switch replaces the count switch (owner ruling Q4 A, 2026-11-17 09:47 CST): both lists name setup, neither names monitors.
Check 'starters: the tray names the setup switch, not the monitors switch' ($TileAutoFlags -contains 'setup' -and $TileAutoFlags -notcontains 'monitors') ($TileAutoFlags -join ',')
Check 'starters: the page AUTO list names the setup switch, not the monitors switch' (@($names) -contains 'setup' -and @($names) -notcontains 'monitors') ($names -join ',')
Check 'starters: the page labels the setup switch "Use This Scene on This Setup"' ([regex]::IsMatch($page, 'Use This Scene on This Setup') -and -not [regex]::IsMatch($page, 'Use This Scene for This Many Screens')) ''
# Control, green on the old code: the laptop-only switch is not part of the setup change. ([regex]::IsMatch, so $matches of the checks above stays.)
Check 'starters: the laptop-only switch stays: noext in the tray and "Laptop Only" on the page' ($TileAutoFlags -contains 'noext' -and [regex]::IsMatch($page, 'Laptop Only')) ''
$optNames = @([regex]::Matches($page, '\{k:"(\w+)",l:') | % { $_.Groups[1].Value }); $defNames = @($st.optDefaults.PSObject.Properties | % { $_.Value.PSObject.Properties.Name })
Check 'starters: the page edits the same thresholds as the tray reads' (@($defNames | ? { $optNames -notcontains $_ }).Count -eq 0) (($optNames -join ',') + ' vs ' + ($defNames -join ','))
$pageMax = @(if ($off) { $matches[1] -split "`n" | % { if ($_ -match '^\["(\w+)"') { $f = $matches[1]; [regex]::Matches($_, '\{k:"(\w+)",l:[^}]*?max:(\d+)') | % { "$f.$($_.Groups[1].Value)=$($_.Groups[2].Value)" } } } }) | sort
$trayMax = @($TileOptMax.Keys | % { "$_=$($TileOptMax[$_])" }) | sort
Check 'starters: the page caps each threshold box at the same value as the tray' ($pageMax.Count -gt 0 -and ($pageMax -join ',') -eq ($trayMax -join ',')) (($pageMax -join ',') + ' vs ' + ($trayMax -join ','))

# Solo on a one-monitor desk: the only screen is the wide role, so both Claude and Chrome land.
$one = Join-Path $runDir 'solo.json'
[IO.File]::WriteAllText($one, '{"monitors":[{"name":"D1","role":"wide","x":0,"y":0,"w":1536,"h":912,"bw":1536,"bh":960}],"windows":[{"id":1,"app":"claude","title":"C","x":0,"y":0,"w":800,"h":600},{"id":2,"app":"chrome","title":"G","x":10,"y":10,"w":800,"h":600},{"id":3,"app":"ms-teams","title":"T","x":20,"y":20,"w":800,"h":600}]}')
$solo = @($st.scenes | ? { $_.id -eq 'solo' })[0]; $solo | Add-Member cats $st.cats; $solo | Add-Member categories $st.categories
$sj = Join-Path $runDir 'solo-scene.json'; [IO.File]::WriteAllText($sj, (ConvertTo-Json -Depth 8 $solo))
$real = $env:TILE_HOME; $env:TILE_HOME = Join-Path $runDir 'solo-home'
try { $pl = (& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'tile.ps1') -Scene $sj -From $one -Json 3>$null) -join '' | ConvertFrom-Json } finally { if ($null -eq $real) { Remove-Item env:TILE_HOME } else { $env:TILE_HOME = $real }; Remove-Item $one, $sj -ErrorAction SilentlyContinue }
$mv = @($pl.placed | ? { $_.note -match 'moved|dry' } | % { $_.app }) -join ','
Check 'Solo on one monitor places Chrome and Claude, and leaves Teams' ($pl -and $mv -match 'chrome' -and $mv -match 'claude' -and $mv -notmatch 'teams') (($pl | ConvertTo-Json -Depth 4 -Compress))

# ---- Grid follows the Claude count ----
$gs = ConvertFrom-Json '{"id":"d","auto":{"grid":true},"claudeGrid":{"at":4,"dense":{"c":6,"r":2},"roomy":{"c":4,"r":2}}}'
Check 'grid: 4 or more Claude windows picks the denser grid, 2 or fewer the roomier one' ((Get-ClaudeGrid $gs 4).c -eq 6 -and (Get-ClaudeGrid $gs 9).c -eq 6 -and (Get-ClaudeGrid $gs 2).c -eq 4 -and (Get-ClaudeGrid $gs 0).c -eq 4)
Check 'grid: with no history, 3 windows is roomy' ((Get-ClaudeMode $gs 3) -eq 'roomy')
Check 'grid: at 3 windows the grid stays as it was, so a count that hovers at the line does not flap' ((Get-ClaudeMode $gs 3 'dense') -eq 'dense' -and (Get-ClaudeMode $gs 3 'roomy') -eq 'roomy')
$gs.auto.grid = $false
Check 'grid: with the switch off the scene keeps its own grid' ($null -eq (Get-ClaudeGrid $gs 5) -and $null -eq (Get-ClaudeGrid (ConvertFrom-Json '{"auto":{"grid":true}}') 5))
$gsc = $st.scenes | ? { $_.id -eq 'default' }; $gsc | Add-Member -Force cats $st.cats; $gsc | Add-Member -Force categories $st.categories
$gj = ConvertFrom-Json (Get-GridSceneJson $gsc $gsc.claudeGrid.dense)
Check 'grid: the scene JSON the tray hands tile.ps1 keeps its arrays and categories and swaps only the ultrawide grid' ($gj.grids.wide.c -eq 6 -and $gj.grids.tall.r -eq 2 -and $gj.pins[0].slots -is [array] -and $gj.pins[0].slots[0] -eq 0 -and $gj.categories[0] -is [array] -and $gj.categories[0][1] -eq 'Code' -and $gj.cats.claude -eq 'code' -and $gj.fill.apps.Count -eq 3)

# The grid trigger swaps the ultrawide grid on the wide-role monitor, by id, not on the widest screen (coordinator ruling, 2026-11-17 13:28 CST).
# Seam: the laptop is the widest screen by rank but is the built-in panel, so the wide role goes to the ultrawide (decision monitor-setups item 14).
# The scene JSON is the one the grid trigger builds (Get-GridSceneJson); tile.ps1 runs it on the snapshot as a dry run.
$gsnap = Join-Path $runDir 'grid-snap.json'
[IO.File]::WriteAllText($gsnap, (ConvertTo-Json -Depth 6 -Compress ([ordered]@{
  monitors = @([ordered]@{ name = '\\.\DISPLAY1'; id = 'LEN3'; builtin = $true; x = 0; y = 0; w = 2560; h = 1560; bw = 2560; bh = 1600 },
    [ordered]@{ name = '\\.\DISPLAY2'; id = 'DEL2'; builtin = $false; x = 2560; y = 0; w = 1920; h = 1040; bw = 1920; bh = 1080 })
  windows = @([ordered]@{ id = 1; app = 'claude'; title = 'Claude 1'; x = 0; y = 0; w = 800; h = 600 }, [ordered]@{ id = 2; app = 'claude'; title = 'Claude 2'; x = 0; y = 0; w = 800; h = 600 })
})))
$gscene = Join-Path $runDir 'grid-scene.json'; [IO.File]::WriteAllText($gscene, (Get-GridSceneJson $gsc $gsc.claudeGrid.dense))
$realHome = $env:TILE_HOME; $realSeam = $env:TILE_SCREENS_FILE
$env:TILE_HOME = Join-Path $runDir 'grid-home'; $env:TILE_SCREENS_FILE = $null
try { $gp = (((& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'tile.ps1') -Scene $gscene -From $gsnap -Json 3>$null) | ? { "$_" -notmatch '^WARNING:' }) -join '') | ConvertFrom-Json }
finally { $env:TILE_HOME = $realHome; $env:TILE_SCREENS_FILE = $realSeam }
$gcl = @($gp.placed | ? { $_.app -eq 'claude' })
Check 'grid: the scene run places the two Claude windows (scope)' ($gcl.Count -eq 2) "placed Claude windows: $($gcl.Count)"
Check 'grid: the ultrawide grid lands on the wide-role monitor, by id, not on the widest screen' (@($gcl | ? { $_.x -ge 2560 }).Count -eq $gcl.Count) ("x of the Claude windows: " + (($gcl | % { $_.x }) -join ','))

# ---- Global guards ----
$sched = Scene 'sched' @{} @{ trigger = @{ type = 'time'; days = @(0, 1, 2, 3, 4, 5, 6); time = '10:07' } }
$gc = Cfg (@(StdScenes) + @($sched))
$tS = [datetime]'2026-10-21 10:07:05'
$tP = $tS.AddSeconds(-15)  # the call is confirmed (3 readings) before the minute the schedule is due in
function InCallRun($s) { @((Run $s $tP $gc (Sig) 'plain' $null $false), (Run $s $tP.AddSeconds(3) $gc (Sig) 'plain' $null $true), (Run $s $tP.AddSeconds(6) $gc (Sig) 'plain' $null $true), (Run $s $tS $gc (Sig) 'plain' $null $true)) }
$s = New-TrayState; $x = InCallRun $s
Check 'guard: a scheduled apply is skipped during a call' ((Joined $x) -eq '///' -and $s.inCall) (Joined $x)
$s = New-TrayState; $x = @(InCallRun $s) + @((Run $s $tS.AddSeconds(30) $gc (Sig) 'plain' $null $false), (Run $s $tS.AddSeconds(33) $gc (Sig) 'plain' $null $false))
Check 'guard: a skipped scheduled apply is not kept for after the call' ((Joined $x) -eq '/////') (Joined $x)
$s = New-TrayState; $cg = Cfg (StdScenes); $sg = Sig @{ agenda = (Agenda @(Ev '09:55' '11:00' 30)) }
$x = @((Run $s $t0 $cg $sg 'plain' $null $false), (Run $s $t0.AddSeconds(3) $cg $sg 'plain' $null $true), (Run $s $t0.AddSeconds(6) $cg $sg 'plain' $null $true), (Run $s $t0.AddSeconds(7) $cg (Sig @{ agenda = $sg.agenda; screens = 1 }) 'plain' $k1), (Run $s $t0.AddSeconds(8) $cg (Sig @{ agenda = $sg.agenda; screens = 1 }) 'plain' $k2))
Check 'guard: the call trigger itself applies during a call, and a monitor change in the call does not' ((Joined $x) -eq '//listen//') (Joined $x)
$s = New-TrayState; $x = @((Run $s $tS.AddSeconds(-9) $gc (Sig @{ manualAt = $tS.AddSeconds(-3) })), (Run $s $tS $gc (Sig @{ manualAt = $tS.AddSeconds(-5) })), (Run $s $tS.AddSeconds(6) $gc (Sig @{ manualAt = $tS.AddSeconds(-5) })))
Check 'guard: never within 10 s of a manual move; a scheduled apply that fell inside the hold goes through once the move is 10 s old, in its minute' ((Joined $x) -eq '//sched') (Joined $x)
$s = New-TrayState; $x = @((KeyRun $s $k2 $gc), (Run $s $t0.AddSeconds(5) $gc (Sig @{ mouseDown = $true }) 'plain' $k1), (Run $s $t0.AddSeconds(7) $gc (Sig @{ manualAt = $t0.AddSeconds(6) })), (Run $s $t0.AddSeconds(20) $gc (Sig @{ manualAt = $t0.AddSeconds(6) })))
Check 'guard: a manual move cancels a held one-shot that was waiting before it' ((Joined $x) -eq '///') (Joined $x)
$s = New-TrayState; $x = @((KeyRun $s $k2 $gc), (Run $s $t0.AddSeconds(5) $gc (Sig @{ mouseDown = $true }) 'plain' $k1), (Run $s $t0.AddSeconds(6) $gc (Sig @{ mouseDown = $true })), (Run $s $t0.AddSeconds(7) $gc (Sig)))
Check 'guard: never while a mouse button is down; a monitor change waits for the button and then applies, once' ((Joined $x) -eq '///solo') (Joined $x)
$s = New-TrayState; $x = @((KeyRun $s $k2 $gc), (Run $s $t0.AddSeconds(5) $gc (Sig @{ mouseDown = $true }) 'plain' $k1), (Run $s $t0.AddSeconds(70) $gc (Sig)))
Check 'guard: a held trigger is dropped after 60 s, not applied late' ((Joined $x) -eq '//') (Joined $x)
$s = New-TrayState
$x = @((Run $s $t0 $gc (Sig @{ unlockedAfter = 20 }) 'focus'), (Run $s $t0.AddSeconds(10) $gc (Sig @{ wins = @($w1) }) 'focus'), (Run $s $t0.AddSeconds(13) $gc (Sig @{ wins = @($w1, $w2) }) 'focus'), (Run $s $t0.AddSeconds(20) $gc (Sig @{ wins = @($w1, $w2) }) 'focus'), (Run $s $t0.AddSeconds(29) $gc (Sig @{ wins = @($w1, $w2) }) 'focus'), (Run $s $t0.AddSeconds(31) $gc (Sig @{ wins = @($w1, $w2) }) 'focus'))
Check 'guard: at most one automatic apply per 30 s; the next waits for the cap' ((Joined $x) -eq 'default/////focus') (Joined $x)
$s = New-TrayState; $x = @((Run $s $t0 $gc (Sig @{ unlockedAfter = 20 }) 'focus'), (Run $s $t0.AddSeconds(3) $gc (Sig @{ agenda = $sg.agenda }) 'plain' $null $false), (Run $s $t0.AddSeconds(6) $gc (Sig @{ agenda = $sg.agenda }) 'plain' $null $true), (Run $s $t0.AddSeconds(9) $gc (Sig @{ agenda = $sg.agenda }) 'plain' $null $true))
Check 'guard: the call trigger is not held by the 30 s cap' ((Joined $x) -eq 'default//' + '/listen') (Joined $x)
$bc = Cfg (@(Scene 'work') + @(Scene 'meet' @{} @{ trigger = @{ type = 'call'; back = $true } }))
$s = New-TrayState; $x = @((Run $s $t0 $bc (Sig) 'work' $null $false), (Run $s $t0.AddSeconds(3) $bc (Sig) 'work' $null $true), (Run $s $t0.AddSeconds(6) $bc (Sig) 'work' $null $true), (Run $s $t0.AddSeconds(9) $bc (Sig) 'meet' $null $false), (Run $s $t0.AddSeconds(12) $bc (Sig) 'meet' $null $false))
Check 'guard: with live signals a call scene applies at the start and goes back at the end, even inside the 30 s cap' ((Joined $x) -eq '//meet//work') (Joined $x)
$s = New-TrayState; $x = @((Run $s $tS $gc (Sig) 'plain'), (Run $s $tS.AddSeconds(2) $gc (Sig) 'plain'))
Check 'guard: without live signals only the schedule, display and call triggers run, and a schedule fires once' ((Joined $x) -eq 'sched/') (Joined $x)

# ---- An older config gains the new starters and the trigger fields, and nothing else changes ----
$mig = Join-Path $runDir 'mig'; New-Item -ItemType Directory $mig | Out-Null
function Migrate($json) {
  [IO.File]::WriteAllText((Join-Path $mig 'config.json'), $json)
  $real = $env:TILE_HOME; $env:TILE_HOME = $mig
  try {
    $cmd = ". '$(Join-Path (Split-Path $Tray) 'config.ps1')'; [void](Get-TileConfigText)"
    & powershell -NoProfile -ExecutionPolicy Bypass -Command $cmd 2>&1 | Out-Null
    $m1 = [IO.File]::ReadAllText((Join-Path $mig 'config.json')); $w1 = (Get-Item (Join-Path $mig 'config.json')).LastWriteTimeUtc
    & powershell -NoProfile -ExecutionPolicy Bypass -Command $cmd 2>&1 | Out-Null
    $note = Join-Path $mig 'note.txt'
    [pscustomobject]@{ text = $m1; again = [IO.File]::ReadAllText((Join-Path $mig 'config.json')); same = ((Get-Item (Join-Path $mig 'config.json')).LastWriteTimeUtc -eq $w1); note = $(if (Test-Path -LiteralPath $note) { [IO.File]::ReadAllText($note) } else { '' }) }
  } finally { if ($null -eq $real) { Remove-Item env:TILE_HOME } else { $env:TILE_HOME = $real } }
}
$cat = '"categories":[["code","Code"],["browse","Browse"],["comms","Comms"],["other","Other"]],"cats":{"claude":"code"}'
$fri = '{"id":"fri","name":"Fri","trigger":{"type":"time","days":[5],"time":"14:00"},"grids":{"wide":{"c":2,"r":1}},"pins":[],"fill":{"mon":"wide","apps":["*"],"skip":[],"sort":"app"}}'
$def = '{"id":"default","name":"Default","builtIn":true,"trigger":{"type":"manual"},"grids":{"wide":{"c":1,"r":1}},"pins":[{"app":"outlook","match":"","mon":"tall","slots":[0]}],"fill":{"mon":"wide","apps":["claude"],"skip":[],"sort":"app"}}'
$mine = '{"id":"mine","name":"Mine","trigger":{"type":"manual"},"grids":{"wide":{"c":2,"r":1}},"pins":[],"fill":{"mon":"wide","apps":["*"],"skip":[],"sort":"app"}}'
$mg = Migrate ('{"version":1,' + $cat + ',"scenes":[' + $fri + ',' + $def + ',' + $mine + ']}')
$mc = ConvertFrom-Json $mg.text; $md = @($mc.scenes | ? { $_.id -eq 'default' })[0]; $mf = @($mc.scenes | ? { $_.id -eq 'fri' })[0]; $mm = @($mc.scenes | ? { $_.id -eq 'mine' })[0]
# The starter config is version 4 (config v4, monitor setups lane C, 2026-11-17).
Check 'migration: an older config gains Listen, Solo, Thursday Prep, the activity map, the meeting-size rule and the threshold defaults, and its own scenes stay' ($mc.version -eq 4 -and (@($mc.scenes.id) -join ',') -eq 'fri,default,mine,listen,solo,thursday-prep' -and $mc.activity.Count -ge 5 -and $mc.meetingSize.at -eq 25 -and $mc.optDefaults.desk.lockMin -eq 5) $mg.text.Substring(0, 200)
Check 'migration: a built-in Default gains screens, claudeGrid and an auto block with every switch off' ($md.screens -eq 3 -and $md.claudeGrid.at -eq 4 -and (@($md.auto.PSObject.Properties | ? { $_.Value -ne $false }).Count -eq 0) -and @($md.auto.PSObject.Properties).Count -eq 9)
Check 'migration: a custom scene gains an auto block with every switch off' ((@($mm.auto.PSObject.Properties).Count -eq 9) -and (@($mf.auto.PSObject.Properties | ? { $_.Value -ne $false }).Count -eq 0))
Check 'migration: nested and one-item arrays survive the rewrite (categories, days)' ($mc.categories.Count -eq 4 -and $mc.categories[0] -is [array] -and $mc.categories[0][1] -eq 'Code' -and $mf.trigger.days -is [array] -and $mf.trigger.days[0] -eq 5 -and $mc.cats.claude -eq 'code' -and $md.pins[0].slots -is [array] -and $md.pins[0].slots[0] -eq 0 -and $mg.text -notmatch '"Count":|"value":')
Check 'migration: a second read changes nothing' ($mg.text -ceq $mg.again -and $mg.same)
$m2 = Migrate ('{"version":2,' + $cat + ',"scenes":[' + $def + ',' + $mine + ']}')
$mc2 = ConvertFrom-Json $m2.text
# The starter config is version 4 (config v4, monitor setups lane C, 2026-11-17).
Check 'migration: a version 2 config gets the trigger fields but no starter scene it does not already have' ($mc2.version -eq 4 -and (@($mc2.scenes.id) -join ',') -eq 'default,mine' -and $mc2.scenes[0].claudeGrid.at -eq 4 -and $mc2.optDefaults.noext.sec -eq 30)
# The count switch an older config carries (owner ruling Q4 A, 2026-11-17 09:47 CST): the scene loads with it off, nothing else in it changes,
# and a note asks the owner to pick a setup for it.
$cnt = '{"id":"stack","name":"Stack","trigger":{"type":"manual"},"screens":2,"grids":{"wide":{"c":2,"r":1}},"pins":[],"fill":{"mon":"wide","apps":["*"],"skip":[],"sort":"app"},"auto":{"desk":false,"window":false,"activity":false,"size":false,"gaps":false,"offer":false,"monitors":true,"noext":false,"grid":false}}'
$cm = Migrate ('{"version":3,' + $cat + ',"scenes":[' + $cnt + ']}')
$cc = ConvertFrom-Json $cm.text; $cs = @($cc.scenes | ? { $_.id -eq 'stack' })[0]; $co = ConvertFrom-Json $cnt
Check 'migration: the scene with the count switch is still in the config (scope)' ($null -ne $cs) (@($cc.scenes.id) -join ',')
Check 'migration: the count switch loads off' ($null -ne $cs -and -not [bool]$cs.auto.monitors) "monitors: $(if ($cs) { $cs.auto.monitors })"
Check 'migration: a note asks the owner to pick a setup for that scene' ([regex]::IsMatch(($cm.text + "`n" + $cm.note), '(?i)(pick|choose)[^"\r\n]{0,40}setup')) "note: $($cm.note)"
$moved = @($co.PSObject.Properties | ? { $_.Name -ne 'auto' } | ? { (ConvertTo-Json -Depth 10 -Compress $_.Value) -ne (ConvertTo-Json -Depth 10 -Compress $cs.($_.Name)) } | % { $_.Name })
$moved += @($co.auto.PSObject.Properties | ? { $_.Name -ne 'monitors' -and [bool]$_.Value -ne [bool]$cs.auto.($_.Name) } | % { "auto.$($_.Name)" })
Check 'migration: nothing else in that scene changes' ($null -ne $cs -and $moved.Count -eq 0) ("changed: " + ($moved -join ','))
# ---- Gap watch (L5b): the tray's close and minimize hook. Two pure functions, defined above tray.ps1's -Lib return. ----
# Contract the builder meets:
#   Test-GapEvent(event, idObject, idChild, hwnd, tiledSet): tiledSet is an array of handles. True only for 0x8001, 0x8002,
#     0x8003, 0x0016, 0x0017 with idObject 0 and idChild 0 on a handle in tiledSet. Otherwise $false.
#   Step-GapFill(state, events, now): state = scene, tiled ([{hwnd, mon}]), absent (handles), grids ({mon: {free: {areas}}}),
#     lastApply (the tray's own last apply, or $null), quietMs. events = [{event, idObject, idChild, hwnd, time}].
#     Returns one run { scene; absent } where absent is the absent set after this tick, or nothing.
# A name that is not defined (the base commit) gives $null through Invoke-IfDefined, so each check fails on its value. run.ps1 stops on
# an error, so a call that throws would hide every later check. Times are synthetic: no check reads the clock.
function Invoke-IfDefined([string]$name, [object[]]$a) { if (Get-Command $name -ErrorAction SilentlyContinue) { & $name @a } }
function Invoke-TestGapEvent($ev, $io, $ic, $hwnd, $set) { Invoke-IfDefined 'Test-GapEvent' @($ev, $io, $ic, $hwnd, $set) }
function Invoke-StepGapFill($state, $events, $now, $pidOf = $null) { Invoke-IfDefined 'Step-GapFill' @($state, $events, $now, $pidOf) }
function GapEvt($ev, $hwnd, [datetime]$t, $io = 0, $ic = 0) { [pscustomobject]@{ event = $ev; idObject = $io; idChild = $ic; hwnd = $hwnd; time = $t } }
function GapTile($hwnd, $mon = 'A', $procId = $null) { [pscustomobject]@{ hwnd = $hwnd; mon = $mon; procId = $procId } }
function GapState($tiled, $absent, $grids, $last) { [pscustomobject]@{ scene = 'work'; tiled = @($tiled); absent = @($absent); grids = $grids; lastApply = $last; quietMs = $gwQuiet } }
function GapDesc($r) { if ($null -eq $r) { 'no run' } else { "run absent=[$(@($r.absent) -join ',')] scene=$($r.scene)" } }
$gwQuiet = 1500; $gwNow = [datetime]'2026-10-21 10:00:00'; $gwLast = $gwNow.AddMinutes(-10)  # the tray's own last apply, long before the events
$gwHide = 0x8003; $gwGapEvents = @(0x8001, 0x8002, 0x8003, 0x0016, 0x0017)
$gwFree = [pscustomobject]@{ free = [pscustomobject]@{ areas = @([pscustomobject]@{ x = 0; y = 0; w = 1; h = 1 }) } }
$gwPlain = [pscustomobject]@{ c = 2; r = 1 }

# Test-GapEvent. Each check compares with the strict boolean, so an undefined name ($null) fails it.
$gwTiled = @(1001, 1002)
$gwMissed = @($gwGapEvents | ? { (Invoke-TestGapEvent $_ 0 0 1001 $gwTiled) -ne $true })
Check 'gap-watch: the five gap events on a tiled handle (object 0, child 0) pass' ($gwMissed.Count -eq 0) "not accepted: $($gwMissed -join ' ')"
$gwWrong = @(@(0x800B, 0x8000, 0x0003) | ? { (Invoke-TestGapEvent $_ 0 0 1001 $gwTiled) -ne $false })
Check 'gap-watch: location change, create and foreground events do not pass, even on a tiled handle' ($gwWrong.Count -eq 0) "not false for: $($gwWrong -join ' ')"
Check 'gap-watch: a gap event on an untiled handle does not pass' ((Invoke-TestGapEvent $gwHide 0 0 9999 $gwTiled) -eq $false) 'accepted a handle that is not tiled'
Check 'gap-watch: a gap event on a non-window object (idObject -4) does not pass' ((Invoke-TestGapEvent $gwHide (-4) 0 1001 $gwTiled) -eq $false) 'accepted idObject -4'
Check 'gap-watch: a gap event on a child element (idChild 1) does not pass' ((Invoke-TestGapEvent $gwHide 0 1 1001 $gwTiled) -eq $false) 'accepted idChild 1'
Check 'gap-watch: with no tiled handles, no gap event passes' ((Invoke-TestGapEvent $gwHide 0 0 1001 @()) -eq $false) 'accepted with an empty tiled set'
$gwFull = @(1001..1040)
Check 'gap-watch: the last of 40 tiled handles passes' ((Invoke-TestGapEvent $gwHide 0 0 1040 $gwFull) -eq $true) 'not accepted for handle 1040 in a 40-handle set'

# Step-GapFill. Each "nothing" check sits with a tiled or Free Layout handle that must act, so it cannot pass on an empty result.
$r = Invoke-StepGapFill (GapState @((GapTile 1001 'A')) @() @{ A = $gwFree } $gwLast) @((GapEvt $gwHide 9999 $gwNow), (GapEvt $gwHide 1001 $gwNow)) $gwNow
Check 'gap-watch: an untiled handle does nothing; the tiled handle in the same tick goes absent alone' ($null -ne $r -and (@($r.absent) -join ',') -eq '1001') (GapDesc $r)
$gwBurst = @(1001..1040)
$r = Invoke-StepGapFill (GapState @($gwBurst | % { GapTile $_ 'A' }) @() @{ A = $gwFree } $gwLast) @($gwBurst | % { GapEvt $gwHide $_ $gwNow }) $gwNow
Check 'gap-watch: a burst of 40 hides in one tick gives one run' ($null -ne $r -and @($r).Count -eq 1) (GapDesc $r)
Check 'gap-watch: that one run holds all 40 absent handles and no others' ($null -ne $r -and ((@($r.absent) | Sort-Object) -join ',') -eq ($gwBurst -join ',')) (GapDesc $r)
# One event lands 1000 ms after the tray's own apply (inside quietMs), one 2000 ms after (outside it).
$r = Invoke-StepGapFill (GapState @((GapTile 1001 'A'), (GapTile 1002 'A')) @() @{ A = $gwFree } $gwNow) @((GapEvt $gwHide 1001 $gwNow.AddMilliseconds($gwQuiet - 500)), (GapEvt $gwHide 1002 $gwNow.AddMilliseconds($gwQuiet + 500))) $gwNow.AddMilliseconds($gwQuiet + 500)
Check 'gap-watch: an event inside quietMs after the tray''s own apply is ignored; one outside it is not' ($null -ne $r -and (@($r.absent) -join ',') -eq '1002') (GapDesc $r)
$r = Invoke-StepGapFill (GapState @((GapTile 1001 'A')) @(1001) @{ A = $gwFree } $gwLast) @((GapEvt 0x0017 1001 $gwNow)) $gwNow
Check 'gap-watch: a restore (0x0017) of an absent handle gives a run with it no longer absent' ($null -ne $r -and -not (@($r.absent) -contains 1001)) (GapDesc $r)
$r = Invoke-StepGapFill (GapState @((GapTile 1001 'A')) @(1001) @{ A = $gwFree } $gwLast) @((GapEvt 0x8002 1001 $gwNow)) $gwNow
Check 'gap-watch: a show (0x8002) of an absent handle gives a run with it no longer absent' ($null -ne $r -and -not (@($r.absent) -contains 1001)) (GapDesc $r)
# Scope first: the Free Layout monitor's run is for the active scene, then the monitor with no free.areas is checked.
$r = Invoke-StepGapFill (GapState @((GapTile 1001 'A'), (GapTile 2001 'B')) @() @{ A = $gwFree; B = $gwPlain } $gwLast) @((GapEvt $gwHide 1001 $gwNow), (GapEvt $gwHide 2001 $gwNow)) $gwNow
Check 'gap-watch: a hide on a Free Layout monitor gives a run for the active scene (scope)' ($null -ne $r -and $r.scene -eq 'work') (GapDesc $r)
Check 'gap-watch: a monitor whose layout has no free.areas stays out of the run' ((@($r.absent) -join ',') -eq '1001') (GapDesc $r)
# No tiled handles, then one: the same tick gives no run, and gives one once a handle is tiled.
$rNone = Invoke-StepGapFill (GapState @() @() @{} $gwLast) @((GapEvt $gwHide 1001 $gwNow)) $gwNow
$rOne = Invoke-StepGapFill (GapState @((GapTile 1001 'A')) @() @{ A = $gwFree } $gwLast) @((GapEvt $gwHide 1001 $gwNow)) $gwNow
Check 'gap-watch: with no tiled handles a tick gives no run; with one tiled handle it gives one' ($null -eq $rNone -and $null -ne $rOne) "no tiled: $(GapDesc $rNone); one tiled: $(GapDesc $rOne)"

# Step-GapFill's process-id check (procId taken at apply): a handle whose owner changed is a recycled window, so its event is skipped.
# The recycled handle sits beside a same-pid one, in each order, so the absent set is exactly the same-pid handle whatever the order.
$gwPidRecycled = { param($h) if ($h -eq 1001) { [uint32]3333 } else { [uint32]2222 } }
foreach ($ord in @(@(1001, 1002), @(1002, 1001))) {
  $tiledOrd = @($ord | % { GapTile $_ 'A' $(if ($_ -eq 1001) { 1111 } else { 2222 }) })
  $evOrd = @($ord | % { GapEvt $gwHide $_ $gwNow })
  $rp = Invoke-StepGapFill (GapState $tiledOrd @() @{ A = $gwFree } $gwLast) $evOrd $gwNow $gwPidRecycled
  Check "gap-watch pid: a recycled handle (its process id changed) is skipped; the same-pid handle goes absent (order $($ord -join ','))" ($null -ne $rp -and (@($rp.absent) -join ',') -eq '1002') (GapDesc $rp)
}
$gwPidSame = { param($h) [uint32]1111 }
$rs = Invoke-StepGapFill (GapState @((GapTile 1001 'A' 1111)) @() @{ A = $gwFree } $gwLast) @((GapEvt $gwHide 1001 $gwNow)) $gwNow $gwPidSame
Check 'gap-watch pid: a handle whose process id is unchanged acts (control)' ($null -ne $rs -and (@($rs.absent) -join ',') -eq '1001') (GapDesc $rs)
$gwPidGone = { param($h) [uint32]0 }
$rg = Invoke-StepGapFill (GapState @((GapTile 1002 'A' 2222)) @() @{ A = $gwFree } $gwLast) @((GapEvt $gwHide 1002 $gwNow)) $gwNow $gwPidGone
Check 'gap-watch pid: a gone window (process id 0) is no mismatch, so its hide still goes absent' ($null -ne $rg -and (@($rg.absent) -join ',') -eq '1002') (GapDesc $rg)

# Destroy is final (the ruling: a destroyed window never comes back). After a destroy (0x8001) of a tiled handle, every later event on that
# handle is ignored until the next apply resets the tiled set. A minimize then restore of the same window still restores (control).
# A multi-tick case copies each run's absent set back into its state, as the tray does, so a later tick reads what the earlier one left.
$gdState = GapState @((GapTile 1001 'A' 1111)) @() @{ A = $gwFree } $gwLast
$gdDestroy = Invoke-StepGapFill $gdState @((GapEvt 0x8001 1001 $gwNow)) $gwNow $gwPidSame
Check 'gap-watch destroy: a destroy of a tiled handle gives a run with it absent (scope, before the show)' ($null -ne $gdDestroy -and $gdDestroy.scene -eq 'work' -and (@($gdDestroy.absent) -join ',') -eq '1001') (GapDesc $gdDestroy)
$gdState.absent = @($gdDestroy.absent)
$gdShow = Invoke-StepGapFill $gdState @((GapEvt 0x8002 1001 $gwNow.AddSeconds(5))) $gwNow.AddSeconds(5) $gwPidSame
Check 'gap-watch destroy: a show of that handle from the same pid gives no gap run' ($null -ne $gdDestroy -and $null -eq $gdShow) (GapDesc $gdShow)
$gdAfter = if ($null -eq $gdShow) { @($gdState.absent) } else { @($gdShow.absent) }
Check 'gap-watch destroy: after that show the absent set still holds the destroyed handle' (($gdAfter -join ',') -eq '1001') "absent: [$($gdAfter -join ',')]"
$gdSameTick = Invoke-StepGapFill (GapState @((GapTile 1001 'A' 1111)) @() @{ A = $gwFree } $gwLast) @((GapEvt 0x8001 1001 $gwNow), (GapEvt 0x8002 1001 $gwNow.AddMilliseconds(200))) $gwNow $gwPidSame
Check 'gap-watch destroy: a destroy and a show of one handle in the same tick leave it absent (the show is later, so ignored)' ($null -ne $gdSameTick -and (@($gdSameTick.absent) -join ',') -eq '1001') (GapDesc $gdSameTick)
$gdOtherPid = { param($h) [uint32]3333 }  # the handle now belongs to another process: a window that reused it
$gdOtherState = GapState @((GapTile 1001 'A' 1111)) @() @{ A = $gwFree } $gwLast
$gdOtherRun = Invoke-StepGapFill $gdOtherState @((GapEvt 0x8001 1001 $gwNow)) $gwNow $gwPidSame
Check 'gap-watch destroy: a destroy from the owning pid gives a run with the handle absent (scope, before the other pid''s show)' ($null -ne $gdOtherRun -and (@($gdOtherRun.absent) -join ',') -eq '1001') (GapDesc $gdOtherRun)
$gdOtherState.absent = @($gdOtherRun.absent)
$gdOtherShow = Invoke-StepGapFill $gdOtherState @((GapEvt 0x8002 1001 $gwNow.AddSeconds(5))) $gwNow.AddSeconds(5) $gdOtherPid
Check 'gap-watch destroy: a show of that handle from another pid gives no gap run (control: the process-id check already skips it)' ($null -ne $gdOtherRun -and $null -eq $gdOtherShow) (GapDesc $gdOtherShow)
$gmState = GapState @((GapTile 1001 'A' 1111)) @() @{ A = $gwFree } $gwLast
$gmMin = Invoke-StepGapFill $gmState @((GapEvt 0x0016 1001 $gwNow)) $gwNow $gwPidSame
Check 'gap-watch minimize: a minimize start of a tiled handle gives a run with it absent (scope, before the restore)' ($null -ne $gmMin -and (@($gmMin.absent) -join ',') -eq '1001') (GapDesc $gmMin)
$gmState.absent = @($gmMin.absent)
$gmRest = Invoke-StepGapFill $gmState @((GapEvt 0x0017 1001 $gwNow.AddSeconds(5))) $gwNow.AddSeconds(5) $gwPidSame
Check 'gap-watch minimize: a restore of that window from the same pid gives a run with it back (control)' ($null -ne $gmRest -and -not (@($gmRest.absent) -contains 1001)) (GapDesc $gmRest)
$gnState = GapState @((GapTile 1001 'A' 1111)) @() @{ A = $gwFree } $gwLast
$gnFirst = Invoke-StepGapFill $gnState @((GapEvt 0x8001 1001 $gwNow)) $gwNow $gwPidSame
Check 'gap-watch destroy: a destroy before a new apply gives a run with the handle absent (scope)' ($null -ne $gnFirst -and (@($gnFirst.absent) -join ',') -eq '1001') (GapDesc $gnFirst)
# The new apply makes a new state: the same handle is tiled again, and nothing is absent yet.
$gnApplied = GapState @((GapTile 1001 'A' 1111)) @() @{ A = $gwFree } ($gwNow.AddSeconds(10))
$gnAgain = Invoke-StepGapFill $gnApplied @((GapEvt 0x8001 1001 $gwNow.AddSeconds(20))) $gwNow.AddSeconds(20) $gwPidSame
Check 'gap-watch destroy: after a new apply the handle is tracked again, so its destroy gives a run with it absent (control)' ($null -ne $gnAgain -and (@($gnAgain.absent) -join ',') -eq '1001') (GapDesc $gnAgain)
# Full-size: all 40 tiled handles destroyed in one tick, then all 40 shown again from the same pid.
$gbState = GapState @($gwBurst | % { GapTile $_ 'A' 1111 }) @() @{ A = $gwFree } $gwLast
$gbDestroy = Invoke-StepGapFill $gbState @($gwBurst | % { GapEvt 0x8001 $_ $gwNow }) $gwNow $gwPidSame
Check 'gap-watch destroy: the destroy of all 40 tiled handles gives one run with all 40 absent (scope)' ($null -ne $gbDestroy -and ((@($gbDestroy.absent) | % { [int64]$_ } | Sort-Object) -join ',') -eq ($gwBurst -join ',')) (GapDesc $gbDestroy)
$gbState.absent = @($gbDestroy.absent)
$gbShow = Invoke-StepGapFill $gbState @($gwBurst | % { GapEvt 0x8002 $_ $gwNow.AddSeconds(5) }) $gwNow.AddSeconds(5) $gwPidSame
Check 'gap-watch destroy: the show of all 40 destroyed handles from the same pid gives no gap run' ($null -ne $gbDestroy -and $null -eq $gbShow) (GapDesc $gbShow)

# ---- L5b cases: the gap-fill run (the stub until L5a) and New-GapState on a real scene shape. ----
# Invoke-GapFill is the log-only stub. It is defined below tray.ps1's -Lib return, so -Lib does not define it. The case reads its definition
# from tray.ps1 with the PowerShell parser and defines it here, so the case runs the file's own text on either side of the return.
$gwTok = $null; $gwErr = $null
$gwFn = [Management.Automation.Language.Parser]::ParseFile($Tray, [ref]$gwTok, [ref]$gwErr).FindAll({ param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Invoke-GapFill' }, $true) | Select-Object -First 1
if ($gwFn) { Invoke-Expression $gwFn.Extent.Text }
# GapFillRun calls Invoke-GapFill with the toast and log functions replaced by counters, and with the run-undo record set to $rec for the
# call, then restored. So no toast shows and no log file is written. Ran is false when the name is not defined, and each check reads it.
# The engine is a stub unless $opts.tile names another: it records each call (calls) and answers with $opts.placed as its moves, so no window moves.
# $opts also sets the gap state the call sees ($opts.gap, restored after) and the dry-run flag ($opts.noApply).
function GapFillRun($run, $rec, $opts = @{}) {
  $toasts = @{ n = 0 }; $logs = [Collections.Generic.List[string]]::new(); $calls = [Collections.Generic.List[object]]::new()
  $placed = @($opts['placed'] | ? { $null -ne $_ })
  $stub = { param([string]$Scene, [switch]$GapFill, [string[]]$Absent = @(), [string]$Last = '', [switch]$Json, [switch]$DryRun)
    $calls.Add([pscustomobject]@{ Scene = $Scene; GapFill = [bool]$GapFill; Absent = @($Absent); Last = $Last; Json = [bool]$Json; DryRun = [bool]$DryRun })
    ConvertTo-Json -InputObject ([pscustomobject]@{ placed = $placed; missing = @(); left = @() }) -Depth 5 -Compress }.GetNewClosure()
  $tile = if ($null -ne $opts['tile']) { $opts['tile'] } else { $stub }
  function Show-Toast($n) { $toasts['n'] += 1 }
  function Send-RunToast($n) { $toasts['n'] += 1 }
  function New-RunToast($t, $b, $a, $q, $d) { $toasts['n'] += 1 }
  function Note($text) { $toasts['n'] += 1 }
  function Offer-Scene($s, $why) { $toasts['n'] += 1 }
  function Add-TileLog([string]$active, [string]$text) { $logs.Add($text) }
  $NoApply = [bool]$opts['noApply']; $keep = $script:runUndo; $keepGap = $script:gap; $err = ''
  $ran = [bool](Get-Command Invoke-GapFill -ErrorAction SilentlyContinue)
  try {
    $script:runUndo = $rec; $script:gap = $opts['gap']
    $before = ConvertTo-Json -InputObject $rec -Depth 6 -Compress
    try { Invoke-IfDefined 'Invoke-GapFill' @($run) } catch { $err = $_.Exception.Message }
    $after = ConvertTo-Json -InputObject $script:runUndo -Depth 6 -Compress
    $same = [object]::ReferenceEquals($rec, $script:runUndo) -and $before -eq $after
    $afterNull = $null -eq $script:runUndo
  } finally { $script:runUndo = $keep; $script:gap = $keepGap }
  [pscustomobject]@{ ran = $ran; err = $err; same = $same; after = $after; afterNull = $afterNull; toasts = $toasts['n']; logs = $logs.Count; logLines = @($logs); calls = @($calls) }
}
$gwRec = [pscustomobject]@{ id = 'a1b2c3d4e5f6.7365'; at = $gwLast; scene = 'work'; name = 'Work'; prev = 'plain'; changed = $true; done = $false; endedBy = ''; moved = @() }
$gfFull = GapFillRun ([pscustomobject]@{ scene = 'work'; absent = @($gwBurst) }) $gwRec
Check 'gap-fill: a run that takes 40 windows away raises no toast' ($gfFull.ran -and $gfFull.toasts -eq 0) "ran: $($gfFull.ran), toast calls: $($gfFull.toasts)"
Check 'gap-fill: the 40-window run leaves the run-undo record the same object with the same content' ($gfFull.ran -and $gfFull.same) "record after: $($gfFull.after)"
Check 'gap-fill: the 40-window run writes exactly one log line' ($gfFull.ran -and $gfFull.logs -eq 1) "log lines: $($gfFull.logs)"
Check 'gap-fill: the 40-window run completes without an error' ($gfFull.ran -and $gfFull.err -eq '') "error: $($gfFull.err)"
$gfEmpty = GapFillRun ([pscustomobject]@{ scene = 'work'; absent = @() }) $null
Check 'gap-fill: a run with no window away raises no toast' ($gfEmpty.ran -and $gfEmpty.toasts -eq 0) "ran: $($gfEmpty.ran), toast calls: $($gfEmpty.toasts)"
Check 'gap-fill: with no undo record yet, the empty run leaves it null' ($gfEmpty.ran -and $gfEmpty.same -and $gfEmpty.afterNull) "record after: $($gfEmpty.after)"
Check 'gap-fill: the empty run writes exactly one log line' ($gfEmpty.ran -and $gfEmpty.logs -eq 1) "log lines: $($gfEmpty.logs)"
Check 'gap-fill: each stub run calls the engine once, so the checks above read one run' ($gfFull.calls.Count -eq 1 -and $gfEmpty.calls.Count -eq 1) "calls: $($gfFull.calls.Count), $($gfEmpty.calls.Count)"

# The stub cases: the run passes its arguments, applies the moves the engine reports, and a dry run moves and logs nothing. Each case's
# first check is that the stub ran once, so no real engine did. -Absent and -Last compare sorted: fixture order is not the contract.
function GapIds($xs) { (@($xs) | % { [int64]$_ } | Sort-Object) -join ',' }
$gfArgs = GapFillRun ([pscustomobject]@{ scene = 'work'; absent = @(1002, 1001) }) $gwRec @{ gap = @{ arg = 'work-json'; last = @{ '1001' = [pscustomobject]@{ id = 1001; x = 0; y = 0; w = 960; h = 1080 }; '1002' = [pscustomobject]@{ id = 1002; x = 960; y = 0; w = 960; h = 1080 } } } }
$gfA = if ($gfArgs.calls.Count -eq 1) { $gfArgs.calls[0] } else { $null }
$gfALast = if ($gfA) { @(ConvertFrom-Json $gfA.Last) } else { @() }
Check 'gap-fill args: the stub engine runs once, as a live -GapFill -Json run' ($null -ne $gfA -and $gfA.GapFill -and $gfA.Json -and -not $gfA.DryRun) "calls: $($gfArgs.calls.Count)"
Check 'gap-fill args: the scene passed is the gap state''s arg, not the run''s scene name' ($null -ne $gfA -and $gfA.Scene -ceq 'work-json') "scene: $(if ($gfA) { $gfA.Scene })"
Check 'gap-fill args: -Absent carries the away handles' ($null -ne $gfA -and (GapIds $gfA.Absent) -eq '1001,1002') "absent: $(if ($gfA) { GapIds $gfA.Absent })"
Check 'gap-fill args: -Last carries the rect the tray last gave each tiled window' ($null -ne $gfA -and (GapIds @($gfALast | % { $_.id })) -eq '1001,1002' -and @($gfALast | ? { $_.id -eq 1002 })[0].x -eq 960) "last: $(if ($gfA) { $gfA.Last })"
$gfNoGap = GapFillRun ([pscustomobject]@{ scene = 'focus'; absent = @() }) $null
Check 'gap-fill args: with no gap state the scene passed is the run''s scene name' ($gfNoGap.calls.Count -eq 1 -and $gfNoGap.calls[0].Scene -ceq 'focus') "calls: $($gfNoGap.calls.Count)"
$gapMove = @{ arg = 'work-json'; last = @{ '1001' = [pscustomobject]@{ id = 1001; x = 0; y = 0; w = 960; h = 1080 } } }
$gfMove = GapFillRun ([pscustomobject]@{ scene = 'work'; absent = @(1001) }) $gwRec @{ gap = $gapMove; placed = @([pscustomobject]@{ id = 1001; x = 10; y = 20; w = 300; h = 400 }) }
Check 'gap-fill moves: the stub engine runs once' ($gfMove.calls.Count -eq 1) "calls: $($gfMove.calls.Count)"
Check 'gap-fill moves: the rect the engine moved a window to becomes its last rect' ($gapMove.last['1001'].x -eq 10 -and $gapMove.last['1001'].y -eq 20 -and $gapMove.last['1001'].w -eq 300 -and $gapMove.last['1001'].h -eq 400) "last: $(ConvertTo-Json -InputObject $gapMove.last['1001'] -Compress)"
Check 'gap-fill moves: the log line counts the windows away and the moves' (@($gfMove.logLines) -ccontains 'Gap-fill: 1 window(s) away. Moved 1.') "log: $(@($gfMove.logLines) -join ' | ')"
$gapDry = @{ arg = 'work-json'; last = @{ '1001' = [pscustomobject]@{ id = 1001; x = 0; y = 0; w = 960; h = 1080 } } }
$gfDry = GapFillRun ([pscustomobject]@{ scene = 'work'; absent = @(1001) }) $gwRec @{ gap = $gapDry; placed = @([pscustomobject]@{ id = 1001; x = 10; y = 20; w = 300; h = 400 }); noApply = $true }
Check 'gap-fill dry run: the stub engine runs once, with -DryRun' ($gfDry.calls.Count -eq 1 -and $gfDry.calls[0].DryRun) "calls: $($gfDry.calls.Count)"
Check 'gap-fill dry run: no log line is written' ($gfDry.logs -eq 0) "log lines: $($gfDry.logs)"
Check 'gap-fill dry run: the tray''s last rects stay as they were' ($gapDry.last['1001'].x -eq 0 -and $gapDry.last['1001'].w -eq 960) "last: $(ConvertTo-Json -InputObject $gapDry.last['1001'] -Compress)"
# The guard refusal: the real engine, under the suite, refuses a live -GapFill run, and the tray logs the refusal's reason. This is the one case
# that runs the real tile.ps1. The suite flag is set here (a standalone run has none), the live switch is removed, and the profile is a temp one.
$c4Saved = @{ TILE_TEST_SUITE = $env:TILE_TEST_SUITE; TILE_TEST_ALLOW_LIVE = $env:TILE_TEST_ALLOW_LIVE; USERPROFILE = $env:USERPROFILE; APPDATA = $env:APPDATA; TILE_HOME = $env:TILE_HOME }
$c4Prof = Join-Path $runDir 'gapfill-refusal'; New-Item -ItemType Directory -Force (Join-Path $c4Prof 'AppData\Roaming') | Out-Null
try {
  $env:TILE_TEST_SUITE = '1'; $env:TILE_TEST_ALLOW_LIVE = $null; $env:USERPROFILE = $c4Prof; $env:APPDATA = Join-Path $c4Prof 'AppData\Roaming'; $env:TILE_HOME = Join-Path $c4Prof '.tile-windows'
  $c4 = GapFillRun ([pscustomobject]@{ scene = 'work'; absent = @(1001) }) $gwRec @{ tile = (Join-Path $root 'tile.ps1') }
} finally { foreach ($k in $c4Saved.Keys) { if ($null -eq $c4Saved[$k]) { Remove-Item "env:$k" -ErrorAction SilentlyContinue } else { Set-Item "env:$k" $c4Saved[$k] } } }
Check 'gap-fill guard: the real engine refuses a live -GapFill run under the suite, and the tray logs the refusal naming TILE_TEST_ALLOW_LIVE' (@($c4.logLines).Count -eq 1 -and @($c4.logLines)[0] -like 'Gap-fill failed:*TILE_TEST_ALLOW_LIVE*') "log: $(@($c4.logLines) -join ' | ')"

# The real scene shape (config v4): role grids, then layouts keyed by setup, each with grids keyed by monitor id. A Free Layout monitor
# carries free.areas; the other monitor in the setup carries none. GapSceneNoFree is the same scene with no free.areas anywhere.
function GapSceneFree { ConvertFrom-Json '{"id":"work","name":"Work","trigger":{"type":"manual"},"grids":{"tall":{"c":1,"r":2},"laptop":{"c":1,"r":1},"wide":{"c":3,"r":1}},"layouts":{"LEN3|AUO1":{"grids":{"AUO1":{"c":3,"r":1,"free":{"areas":[{"x":0,"y":0,"w":0.5,"h":1},{"x":0.5,"y":0,"w":0.5,"h":1}]}},"LEN3":{"c":1,"r":1}}}}}' }
function GapSceneNoFree { ConvertFrom-Json '{"id":"plain","name":"Plain","trigger":{"type":"manual"},"grids":{"tall":{"c":1,"r":2},"laptop":{"c":1,"r":1},"wide":{"c":3,"r":1}},"layouts":{"LEN3|AUO1":{"grids":{"AUO1":{"c":3,"r":1},"LEN3":{"c":1,"r":1}}}}}' }
function Invoke-NewGapState($sc, $placed, [datetime]$at, $plugged = $null, [string]$mode = '') { Invoke-IfDefined 'New-GapState' @($sc, $placed, $at, $plugged, $mode) }
# The monitors whose grid carries at least one free area, sorted and joined. Empty when the state is missing.
function GapFreeIds($gs) { if ($null -eq $gs) { return '' }; @($gs.grids.Keys | ? { $g = $gs.grids[$_]; $g -and $g.free -and @($g.free.areas).Count } | Sort-Object) -join ',' }
$gsFree = Invoke-NewGapState (GapSceneFree) @([pscustomobject]@{ id = 1001; mon = 'AUO1' }) $gwNow
Check 'gap-watch: New-GapState reads a grid for each monitor in layouts[setup].grids, AUO1 and LEN3 (scope)' ($null -ne $gsFree -and $gsFree.grids.ContainsKey('AUO1') -and $gsFree.grids.ContainsKey('LEN3')) "grids: $(if ($gsFree) { @($gsFree.grids.Keys) -join ',' })"
Check 'gap-watch: the Free Layout monitor AUO1 keeps its two free.areas from layouts[setup].grids' ($null -ne $gsFree -and $gsFree.grids.ContainsKey('AUO1') -and $null -ne $gsFree.grids['AUO1'].free -and @($gsFree.grids['AUO1'].free.areas).Count -eq 2) "AUO1: $(if ($gsFree -and $gsFree.grids.ContainsKey('AUO1')) { ConvertTo-Json -InputObject $gsFree.grids['AUO1'] -Depth 5 -Compress } else { 'not in grids' })"
Check 'gap-watch: on that scene only AUO1 is a Free Layout monitor (LEN3 has no free.areas)' ((GapFreeIds $gsFree) -eq 'AUO1') "Free Layout monitors: [$(GapFreeIds $gsFree)]"
$gsPlain = Invoke-NewGapState (GapSceneNoFree) @([pscustomobject]@{ id = 1001; mon = 'AUO1' }) $gwNow
Check 'gap-watch: a scene with no free.areas yields no Free Layout monitor' ($null -ne $gsPlain -and (GapFreeIds $gsPlain) -eq '') "Free Layout monitors: [$(GapFreeIds $gsPlain)]"

# New-GapState with a known setup key (the key of the plugged monitors, read through Get-TileKnownSetupKey) and with a grid mode. The layouts keys
# are the product's key for these monitors, so the known-key branch is the one that runs. The own layout is listed first and last (order independence).
$gwLen = [pscustomobject]@{ id = 'LEN3'; name = 'Panel A'; builtin = $true; x = 0; y = 1200; w = 1920; h = 1200; bw = 1920; bh = 1200 }
$gwAuo = [pscustomobject]@{ id = 'AUO1'; name = 'Panel B'; builtin = $false; x = 1920; y = 0; w = 3440; h = 1440; bw = 3440; bh = 1440 }
$gwPlug = @($gwLen, $gwAuo); $gwSetKey = Get-TileKnownSetupKey $gwPlug
$gwOwnJson = '{"grids":{"AUO1":{"c":3,"r":1,"free":{"areas":[{"x":0,"y":0,"w":0.5,"h":1},{"x":0.5,"y":0,"w":0.5,"h":1}]}},"LEN3":{"c":1,"r":1}}}'
$gwOtherJson = '{"grids":{"AUO1":{"c":2,"r":2}}}'
# A scene in the real shape (role grids, then layouts keyed by setup), its layouts the entries given in the order given.
function GapSceneKeyed($entries) {
  $sc = ConvertFrom-Json '{"id":"work","name":"Work","trigger":{"type":"manual"},"grids":{"tall":{"c":1,"r":2},"laptop":{"c":1,"r":1},"wide":{"c":3,"r":1}}}'
  $lay = [pscustomobject]@{}
  foreach ($e in $entries) { $lay | Add-Member -NotePropertyName $e.k -NotePropertyValue (ConvertFrom-Json $e.j) }
  $sc | Add-Member -NotePropertyName layouts -NotePropertyValue $lay
  $sc
}
$gwAt = @([pscustomobject]@{ id = 1001; mon = 'AUO1' })
foreach ($ownFirst in @($true, $false)) {
  $ents = if ($ownFirst) { @(@{ k = $gwSetKey; j = $gwOwnJson }, @{ k = 'AUO1'; j = $gwOtherJson }) } else { @(@{ k = 'AUO1'; j = $gwOtherJson }, @{ k = $gwSetKey; j = $gwOwnJson }) }
  $ord = if ($ownFirst) { 'own layout listed first' } else { 'own layout listed last' }
  $gsB1 = Invoke-NewGapState (GapSceneKeyed $ents) $gwAt $gwNow $gwPlug
  Check "gap-watch key: with the plugged setup's key, AUO1 takes that layout's grid (cell and free areas), not the other layout's ($ord)" ($null -ne $gsB1 -and $gsB1.grids.ContainsKey('AUO1') -and $gsB1.grids['AUO1'].c -eq 3 -and @($gsB1.grids['AUO1'].free.areas).Count -eq 2) "AUO1: $(if ($gsB1 -and $gsB1.grids.ContainsKey('AUO1')) { ConvertTo-Json -InputObject $gsB1.grids['AUO1'] -Depth 5 -Compress } else { 'not in grids' })"
}
$gsNoOwn = Invoke-NewGapState (GapSceneKeyed @(@{ k = 'AUO1'; j = $gwOtherJson })) $gwAt $gwNow $gwPlug
Check 'gap-watch key: a known setup key with no layout of its own takes the scene''s role grids, not another layout''s' ($null -ne $gsNoOwn -and -not $gsNoOwn.grids.ContainsKey('AUO1') -and (@($gsNoOwn.grids.Keys | Sort-Object) -join ',') -eq 'laptop,tall,wide') "grids: $(if ($gsNoOwn) { @($gsNoOwn.grids.Keys | Sort-Object) -join ',' })"
$scMode = GapSceneKeyed @(@{ k = $gwSetKey; j = $gwOwnJson })
$scMode | Add-Member -NotePropertyName claudeGrid -NotePropertyValue (ConvertFrom-Json '{"dense":{"c":4,"r":1},"roomy":{"c":3,"r":1}}')
$swapped = ConvertFrom-Json (Get-GridSceneJson $scMode $scMode.claudeGrid.dense $gwPlug)
Check 'gap-watch mode: the grid swap puts the dense grid on AUO1, the wide monitor, in the setup''s own layout (precondition)' ($swapped.layouts.$gwSetKey.grids.AUO1.c -eq 4) "AUO1 in own layout: $(ConvertTo-Json -InputObject $swapped.layouts.$gwSetKey.grids.AUO1 -Compress)"
$gsDense = Invoke-NewGapState $scMode $gwAt $gwNow $gwPlug 'dense'
Check 'gap-watch mode: with the dense mode, New-GapState takes AUO1''s dense grid from the setup''s own layout' ($null -ne $gsDense -and $gsDense.grids.ContainsKey('AUO1') -and $gsDense.grids['AUO1'].c -eq 4 -and $gsDense.grids['AUO1'].r -eq 1) "AUO1: $(if ($gsDense -and $gsDense.grids.ContainsKey('AUO1')) { ConvertTo-Json -InputObject $gsDense.grids['AUO1'] -Compress } else { 'not in grids' })"
$gsRoomy = Invoke-NewGapState $scMode $gwAt $gwNow $gwPlug ''
Check 'gap-watch mode: with no mode, AUO1 keeps the own layout''s grid (control)' ($null -ne $gsRoomy -and $gsRoomy.grids.ContainsKey('AUO1') -and $gsRoomy.grids['AUO1'].c -eq 3) "AUO1 c: $(if ($gsRoomy -and $gsRoomy.grids.ContainsKey('AUO1')) { $gsRoomy.grids['AUO1'].c })"

Remove-Item -Recurse -Force $runDir -ErrorAction SilentlyContinue

if ($standalone) { if ($script:fail) { "$($script:fail) check(s) failed."; exit 1 } else { 'All trigger checks passed.' } }
