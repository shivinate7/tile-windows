# Checks for the automatic triggers in tray.ps1: for each, that it fires once, that its debounce holds, that its per-scene switch
# turns it off, that its thresholds come from the scene, and the global guards. One guard per check, so a red check names the guard.
# Pure functions only: no window moves, no real profile.
# Run alone: powershell -NoProfile -ExecutionPolicy Bypass -File test\triggers.ps1 [-Tray <path to a tray.ps1 copy>]
# test\run.ps1 dot-sources this file. test\redproof.ps1 runs it against scratch copies of tray.ps1, each with one guard broken.
param([string]$Tray = (Join-Path (Split-Path $PSScriptRoot) 'tray.ps1'))
$root = Split-Path $PSScriptRoot
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
    meetings = @{ size = $true; offer = $true }; listen = @{ size = $true; offer = $true }; solo = @{ monitors = $true; noext = $true }; plain = @{} }
  foreach ($k in $over.Keys) { $a[$k] = $over[$k] }
  @($a.Keys | % { if ($_ -eq 'solo') { Scene $_ $a[$_] @{ screens = 1 } } else { Scene $_ $a[$_] } })
}
# A config in which one scene carries threshold values of its own.
function WithOpt($id, $optJson, $over = @{}) { $c = Cfg (StdScenes $over); @($c.scenes | ? { $_.id -eq $id })[0] | Add-Member -Force opt (ConvertFrom-Json $optJson); $c }
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

# ---- A scene per monitor set; no external monitor for 30 s ----
function KeyRun($s, $key, $cfg = $cfg, $secs = 0) { Run $s $t0.AddSeconds($secs) $cfg (Sig) 'plain' $key }
$k1 = 'A=1x1@0,0'; $k2 = 'A=1x1@0,0;B=2x2@1,0'
$s = New-TrayState; $x = @((KeyRun $s $k2), (KeyRun $s $k1 $cfg 5), (KeyRun $s $k1 $cfg 10))
Check 'monitors: going to one screen applies the scene made for one screen, once' ((Joined $x) -eq '/solo/') (Joined $x)
$s = New-TrayState; $x = @((KeyRun $s $k1), (KeyRun $s $k2 $cfg 5))
Check 'monitors: a set no scene is made for applies nothing' ((Joined $x) -eq '/') (Joined $x)
$s = New-TrayState; $c2 = Cfg (StdScenes @{ solo = @{ noext = $true } }); $x = @((KeyRun $s $k2 $c2), (KeyRun $s $k1 $c2 5))
Check 'monitors: with the switch off it applies nothing' ((Joined $x) -eq '/') (Joined $x)
function ScrRun($s, $secs, $n, $cfg = $cfg, $active = 'plain', $o = @{}) { $o.screens = $n; Run $s $t0.AddSeconds($secs) $cfg (Sig $o) $active }
$s = New-TrayState; $x = @((ScrRun $s 0 2), (ScrRun $s 10 1), (ScrRun $s 39 1), (ScrRun $s 40 1), (ScrRun $s 100 1), (ScrRun $s 110 2), (ScrRun $s 120 1), (ScrRun $s 150 1))
Check 'no external: 30 s with one screen applies the laptop scene, once per absence' ((Joined $x) -eq '///solo////solo') (Joined $x)
$s = New-TrayState; $x = @((ScrRun $s 0 1), (ScrRun $s 60 1))
Check 'no external: starting the agent on one screen applies nothing' ((Joined $x) -eq '/') (Joined $x)
$s = New-TrayState; $c2 = Cfg (StdScenes @{ solo = @{ monitors = $true } }); $x = @((ScrRun $s 0 2 $c2), (ScrRun $s 10 1 $c2), (ScrRun $s 50 1 $c2))
Check 'no external: with the switch off it applies nothing' ((Joined $x) -eq '//') (Joined $x)
$s = New-TrayState; $x = @((ScrRun $s 0 2), (ScrRun $s 10 1 $cfg 'plain' @{ locked = $true }), (ScrRun $s 50 1 $cfg 'plain' @{ locked = $true }), (ScrRun $s 60 1), (ScrRun $s 100 1))
Check 'no external: a locked PC does not count (a monitor that sleeps drops out)' ((Joined $x) -eq '////solo') (Joined $x)
$s = New-TrayState; $x = @((ScrRun $s 0 2), (ScrRun $s 10 1 $cfg 'plain' @{ idleSec = 300 }), (ScrRun $s 50 1 $cfg 'plain' @{ idleSec = 340 }), (ScrRun $s 60 1), (ScrRun $s 100 1))
Check 'no external: an idle PC does not count' ((Joined $x) -eq '////solo') (Joined $x)
$s = New-TrayState; $c2 = Cfg (StdScenes); $x = @((Run $s $t0 $c2 (Sig @{ screens = 2 }) 'plain' $k2), (Run $s $t0.AddSeconds(10) $c2 (Sig @{ screens = 1 }) 'plain' $k1), (Run $s $t0.AddSeconds(40) $c2 (Sig @{ screens = 1 }) 'plain' $k1), (Run $s $t0.AddSeconds(100) $c2 (Sig @{ screens = 1 }) 'plain' $k1))
Check 'no external: a monitor-set scene applied a moment ago is the same event, so it does not apply again' ((Joined $x) -eq '/solo//') (Joined $x)
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
$optNames = @([regex]::Matches($page, '\{k:"(\w+)",l:') | % { $_.Groups[1].Value }); $defNames = @($st.optDefaults.PSObject.Properties | % { $_.Value.PSObject.Properties.Name })
Check 'starters: the page edits the same thresholds as the tray reads' (@($defNames | ? { $optNames -notcontains $_ }).Count -eq 0) (($optNames -join ',') + ' vs ' + ($defNames -join ','))
# Solo on a one-monitor desk: the only screen is the wide role, so both Claude and Chrome land.
$one = Join-Path $env:TEMP "tile-solo-$PID.json"
[IO.File]::WriteAllText($one, '{"monitors":[{"name":"D1","role":"wide","x":0,"y":0,"w":1536,"h":912,"bw":1536,"bh":960}],"windows":[{"id":1,"app":"claude","title":"C","x":0,"y":0,"w":800,"h":600},{"id":2,"app":"chrome","title":"G","x":10,"y":10,"w":800,"h":600},{"id":3,"app":"ms-teams","title":"T","x":20,"y":20,"w":800,"h":600}]}')
$solo = @($st.scenes | ? { $_.id -eq 'solo' })[0]; $solo | Add-Member cats $st.cats; $solo | Add-Member categories $st.categories
$sj = Join-Path $env:TEMP "tile-solo-scene-$PID.json"; [IO.File]::WriteAllText($sj, (ConvertTo-Json -Depth 8 $solo))
$real = $env:TILE_HOME; $env:TILE_HOME = Join-Path $env:TEMP "tile-solo-home-$PID"
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
$mig = Join-Path $env:TEMP "tile-mig-$PID"; New-Item -ItemType Directory $mig | Out-Null
function Migrate($json) {
  [IO.File]::WriteAllText((Join-Path $mig 'config.json'), $json)
  $real = $env:TILE_HOME; $env:TILE_HOME = $mig
  try {
    $cmd = ". '$(Join-Path (Split-Path $Tray) 'config.ps1')'; [void](Get-TileConfigText)"
    & powershell -NoProfile -ExecutionPolicy Bypass -Command $cmd 2>&1 | Out-Null
    $m1 = [IO.File]::ReadAllText((Join-Path $mig 'config.json')); $w1 = (Get-Item (Join-Path $mig 'config.json')).LastWriteTimeUtc
    & powershell -NoProfile -ExecutionPolicy Bypass -Command $cmd 2>&1 | Out-Null
    [pscustomobject]@{ text = $m1; again = [IO.File]::ReadAllText((Join-Path $mig 'config.json')); same = ((Get-Item (Join-Path $mig 'config.json')).LastWriteTimeUtc -eq $w1) }
  } finally { if ($null -eq $real) { Remove-Item env:TILE_HOME } else { $env:TILE_HOME = $real } }
}
$cat = '"categories":[["code","Code"],["browse","Browse"],["comms","Comms"],["other","Other"]],"cats":{"claude":"code"}'
$fri = '{"id":"fri","name":"Fri","trigger":{"type":"time","days":[5],"time":"14:00"},"grids":{"wide":{"c":2,"r":1}},"pins":[],"fill":{"mon":"wide","apps":["*"],"skip":[],"sort":"app"}}'
$def = '{"id":"default","name":"Default","builtIn":true,"trigger":{"type":"manual"},"grids":{"wide":{"c":1,"r":1}},"pins":[{"app":"outlook","match":"","mon":"tall","slots":[0]}],"fill":{"mon":"wide","apps":["claude"],"skip":[],"sort":"app"}}'
$mine = '{"id":"mine","name":"Mine","trigger":{"type":"manual"},"grids":{"wide":{"c":2,"r":1}},"pins":[],"fill":{"mon":"wide","apps":["*"],"skip":[],"sort":"app"}}'
$mg = Migrate ('{"version":1,' + $cat + ',"scenes":[' + $fri + ',' + $def + ',' + $mine + ']}')
$mc = ConvertFrom-Json $mg.text; $md = @($mc.scenes | ? { $_.id -eq 'default' })[0]; $mf = @($mc.scenes | ? { $_.id -eq 'fri' })[0]; $mm = @($mc.scenes | ? { $_.id -eq 'mine' })[0]
Check 'migration: an older config gains Listen, Solo, Thursday Prep, the activity map, the meeting-size rule and the threshold defaults, and its own scenes stay' ($mc.version -eq 3 -and (@($mc.scenes.id) -join ',') -eq 'fri,default,mine,listen,solo,thursday-prep' -and $mc.activity.Count -ge 5 -and $mc.meetingSize.at -eq 25 -and $mc.optDefaults.desk.lockMin -eq 5) $mg.text.Substring(0, 200)
Check 'migration: a built-in Default gains screens, claudeGrid and an auto block with every switch off' ($md.screens -eq 3 -and $md.claudeGrid.at -eq 4 -and (@($md.auto.PSObject.Properties | ? { $_.Value -ne $false }).Count -eq 0) -and @($md.auto.PSObject.Properties).Count -eq 9)
Check 'migration: a custom scene gains an auto block with every switch off' ((@($mm.auto.PSObject.Properties).Count -eq 9) -and (@($mf.auto.PSObject.Properties | ? { $_.Value -ne $false }).Count -eq 0))
Check 'migration: nested and one-item arrays survive the rewrite (categories, days)' ($mc.categories.Count -eq 4 -and $mc.categories[0] -is [array] -and $mc.categories[0][1] -eq 'Code' -and $mf.trigger.days -is [array] -and $mf.trigger.days[0] -eq 5 -and $mc.cats.claude -eq 'code' -and $md.pins[0].slots -is [array] -and $md.pins[0].slots[0] -eq 0 -and $mg.text -notmatch '"Count":|"value":')
Check 'migration: a second read changes nothing' ($mg.text -ceq $mg.again -and $mg.same)
$m2 = Migrate ('{"version":2,' + $cat + ',"scenes":[' + $def + ',' + $mine + ']}')
$mc2 = ConvertFrom-Json $m2.text
Check 'migration: a version 2 config gets the trigger fields but no starter scene it does not already have' ($mc2.version -eq 3 -and (@($mc2.scenes.id) -join ',') -eq 'default,mine' -and $mc2.scenes[0].claudeGrid.at -eq 4 -and $mc2.optDefaults.noext.sec -eq 30)
Remove-Item -Recurse -Force $mig -ErrorAction SilentlyContinue

if ($standalone) { if ($script:fail) { "$($script:fail) check(s) failed."; exit 1 } else { 'All trigger checks passed.' } }
