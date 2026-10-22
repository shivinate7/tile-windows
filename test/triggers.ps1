# Checks for the automatic triggers in tray.ps1: for each, that it fires once, that its debounce holds, that its per-scene switch
# turns it off, and the global guards. Pure functions only: no window moves, no real profile.
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
$cfg = Cfg (StdScenes)
$cfgG = Cfg (StdScenes @{ focus = @{ desk = $true; window = $true; gaps = $true } })  # Focus in gaps on: it would answer any agenda, so only its own checks use it
$t0 = [datetime]'2026-10-21 10:00:00'  # a Wednesday; no scene is scheduled

# ---- Return to the desk ----
$s = New-TrayState; $day = [datetime]'2026-10-21 08:00:00'
$r = @((Run $s $day $cfg (Sig @{ unlockedAfter = 20 }) 'focus'), (Run $s $day.AddMinutes(30) $cfg (Sig @{ unlockedAfter = 200 }) 'focus'), (Run $s $day.AddMinutes(60) $cfg (Sig @{ unlockedAfter = 400 }) 'focus'), (Run $s $day.AddMinutes(90) $cfg (Sig @{ unlockedAfter = 400 }) 'plain'))
Check 'desk: the first unlock of the day applies Default; a lock under 5 min does nothing; 5+ min re-applies the active scene; a scene with the switch off does nothing' (($r -join '/') -eq 'default//focus/') ($r -join '/')
$s = New-TrayState; $c2 = Cfg (StdScenes @{ default = @{} })
$r = @((Run $s $day $c2 (Sig @{ unlockedAfter = 20 }) 'plain'), (Run $s $day.AddMinutes(30) $c2 (Sig @{ unlockedAfter = 20 }) 'plain'))
Check 'desk: with Default off the first unlock applies nothing, and uses up the day' (($r -join '/') -eq '/') ($r -join '/')
$s = New-TrayState
$r = @((Run $s $t0 $cfg (Sig @{ idleSec = 700 }) 'focus'), (Run $s $t0.AddSeconds(5) $cfg (Sig @{ idleSec = 3 }) 'focus'), (Run $s $t0.AddSeconds(60) $cfg (Sig @{ idleSec = 3 }) 'focus'))
Check 'desk: input after 10+ min idle re-applies the active scene, once' (($r -join '/') -eq '/focus/') ($r -join '/')
$s = New-TrayState
$r = @((Run $s $t0 $cfg (Sig @{ idleSec = 400 }) 'focus'), (Run $s $t0.AddSeconds(5) $cfg (Sig @{ idleSec = 3 }) 'focus'))
Check 'desk: under 10 min idle does nothing' (($r -join '/') -eq '/') ($r -join '/')
$s = New-TrayState; $s.deskDay = '2026-10-21'
$r = @((Run $s $t0 $cfg (Sig @{ idleSec = 700 }) 'focus'), (Run $s $t0.AddSeconds(5) $cfg (Sig @{ idleSec = 705; locked = $true }) 'focus'), (Run $s $t0.AddSeconds(710) $cfg (Sig @{ unlockedAfter = 705 }) 'focus'), (Run $s $t0.AddSeconds(715) $cfg (Sig @{ idleSec = 2 }) 'focus'), (Run $s $t0.AddSeconds(750) $cfg (Sig @{ idleSec = 2 }) 'focus'))
Check 'desk: a lock inside an idle span applies once, not twice' (($r -join '/') -eq '//focus//') ($r -join '/')
$s = New-TrayState; $c2 = Cfg (StdScenes @{ focus = @{} })
$r = @((Run $s $t0 $c2 (Sig @{ idleSec = 700 }) 'focus'), (Run $s $t0.AddSeconds(5) $c2 (Sig @{ idleSec = 3 }) 'focus'))
Check 'desk: the off switch on the active scene stops the idle trigger' (($r -join '/') -eq '/') ($r -join '/')

# ---- New window finds its place ----
$w1 = Win 1 claude
function WinRun($s, $secs, $wins, $cfg = $cfg, $active = 'focus', $o = @{}) { $o.wins = @($wins); Run $s $t0.AddSeconds($secs) $cfg (Sig $o) $active }
$s = New-TrayState; $x = @((WinRun $s 0 @($w1)), (WinRun $s 3 @($w1, (Win 2 claude))), (WinRun $s 5 @($w1, (Win 2 claude))), (WinRun $s 6 @($w1, (Win 2 claude))), (WinRun $s 9 @($w1, (Win 2 claude))))
Check 'new window: a window of a scene app that holds 3 s re-flows the active scene, once' (($x -join '/') -eq '///focus/') ($x -join '/')
$s = New-TrayState; $x = @((WinRun $s 0 @($w1)), (WinRun $s 3 @($w1, (Win 2 claude))), (WinRun $s 5 @($w1)), (WinRun $s 8 @($w1)))
Check 'new window: a window gone before 3 s does nothing' (($x -join '/') -eq '///') ($x -join '/')
$s = New-TrayState; $x = @((WinRun $s 0 @($w1)), (WinRun $s 3 @($w1, (Win 2 claude 300 200), (Win 3 notepad))), (WinRun $s 9 @($w1, (Win 2 claude 300 200), (Win 3 notepad))))
Check 'new window: a window under 400x300 or an app the scene does not place does nothing' (($x -join '/') -eq '//') ($x -join '/')
$s = New-TrayState; $x = @((WinRun $s 0 @($w1) $cfg 'plain'), (WinRun $s 3 @($w1, (Win 2 claude)) $cfg 'plain'), (WinRun $s 9 @($w1, (Win 2 claude)) $cfg 'plain'))
Check 'new window: a scene with the switch off does nothing' (($x -join '/') -eq '//') ($x -join '/')
$s = New-TrayState; $x = @((WinRun $s 0 @($w1)), (WinRun $s 3 @($w1, (Win 2 claude))), (WinRun $s 10 @($w1, (Win 2 claude)) $cfg 'focus' @{ manualAt = $t0.AddSeconds(5) }), (WinRun $s 16 @($w1, (Win 2 claude)) $cfg 'focus' @{ manualAt = $t0.AddSeconds(5) }))
Check 'new window: never within 10 s of a manual move; it re-flows once the move is 10 s old' (($x -join '/') -eq '//' + '/focus') ($x -join '/')
$s = New-TrayState; $x = @((WinRun $s 0 @($w1)), (WinRun $s 3 @($w1, (Win 2 claude))), (WinRun $s 9 @($w1, (Win 2 claude)) $cfg 'focus' @{ mouseDown = $true }), (WinRun $s 10 @($w1, (Win 2 claude))))
Check 'new window: never while a mouse button is down; it re-flows when the button is up' (($x -join '/') -eq '//' + '/focus') ($x -join '/')

# ---- Activity snap ----
function FgRun($s, $secs, $app, $title, $cfg = $cfg, $active = 'plain') { Run $s $t0.AddSeconds($secs) $cfg (Sig @{ fg = [pscustomobject]@{ app = $app; title = $title } }) $active }
$s = New-TrayState; $x = @((FgRun $s 0 chrome 'Budget - Procore - Google Chrome'), (FgRun $s 59 chrome 'Budget - Procore - Google Chrome'), (FgRun $s 60 chrome 'Budget - Procore - Google Chrome'), (FgRun $s 120 chrome 'Budget - Procore - Google Chrome'))
Check 'activity: a minute in Procore (Chrome) snaps to Review, once; 59 s does not' (($x -join '/') -eq '//review/') ($x -join '/')
$s = New-TrayState; $x = @((FgRun $s 0 chrome 'Procore'), (FgRun $s 50 notepad 'x'), (FgRun $s 60 chrome 'Procore'), (FgRun $s 119 chrome 'Procore'), (FgRun $s 120 chrome 'Procore'))
Check 'activity: leaving the app starts the minute over' (($x -join '/') -eq '////review') ($x -join '/')
$s = New-TrayState; $x = @((FgRun $s 0 chrome 'Procore'), (FgRun $s 90 chrome 'Procore' $cfg 'review'))
Check 'activity: nothing when the layout already is that scene' (($x -join '/') -eq '/') ($x -join '/')
$s = New-TrayState; $x = @((FgRun $s 0 chrome 'Gmail'), (FgRun $s 90 chrome 'Gmail'), (FgRun $s 0 claude 'Claude'), (FgRun $s 90 claude 'Claude'))
Check 'activity: an app or title not in the map does nothing; a mapped scene with the switch off does nothing' (($x -join '/') -eq '///') ($x -join '/')

# ---- Meeting size picks the call scene; agenda missing or stale does nothing ----
function CallRun($agenda, $cfg = $cfg, $active = 'plain') {
  $s = New-TrayState; $sg = Sig @{ agenda = $agenda }
  @((Run $s $t0 $cfg $sg $active $null $false), (Run $s $t0.AddSeconds(3) $cfg $sg $active $null $true), (Run $s $t0.AddSeconds(6) $cfg $sg $active $null $true), (Run $s $t0.AddSeconds(9) $cfg $sg $active $null $true)) -join '/'
}
Check 'size: a call with 25+ attendees applies Listen, once' ((CallRun (Agenda @(Ev '09:55' '11:00' 30))) -eq '//listen/') (CallRun (Agenda @(Ev '09:55' '11:00' 30)))
Check 'size: a smaller call applies Meetings' ((CallRun (Agenda @(Ev '09:55' '11:00' 5))) -eq '//meetings/') (CallRun (Agenda @(Ev '09:55' '11:00' 5)))
Check 'size: a call outside any Teams meeting, or in a free slot, does nothing' ((CallRun (Agenda @(Ev '13:00' '14:00' 30))) -eq '///' -and (CallRun (Agenda @(Ev '09:55' '11:00' 30 $true 'free'))) -eq '///' -and (CallRun (Agenda @(Ev '09:55' '11:00' 30 $false))) -eq '///')
Check 'size: no agenda, or one for another day, does nothing' ((CallRun $null) -eq '///' -and (CallRun (Agenda @(Ev '09:55' '11:00' 30) '2026-10-20')) -eq '///')
$c2 = Cfg (StdScenes @{ meetings = @{}; listen = @{} })
Check 'size: with the switch off on both scenes it does nothing' ((CallRun (Agenda @(Ev '09:55' '11:00' 30)) $c2) -eq '///')
$c2 = Cfg (StdScenes @{ listen = @{} })
Check 'size: the switch is per scene: Listen off, a big call applies nothing' ((CallRun (Agenda @(Ev '09:55' '11:00' 30)) $c2) -eq '///')

# ---- Focus in gaps ----
function GapRun($agenda, $idle = 30, $cfg = $cfgG, $active = 'plain', $secs = 0) { $s = New-TrayState; Run $s $t0.AddSeconds($secs) $cfg (Sig @{ agenda = $agenda; idleSec = $idle }) $active }
$ag = Agenda @(Ev '11:30' '12:00')
Check 'gaps: the next busy meeting 60+ min off and the PC touched lately applies Focus' ((GapRun $ag) -eq 'focus')
$s = New-TrayState; $x = @((Run $s $t0 $cfgG (Sig @{ agenda = $ag; idleSec = 30 })), (Run $s $t0.AddSeconds(60) $cfgG (Sig @{ agenda = $ag; idleSec = 30 })), (Run $s $t0.AddMinutes(10) $cfgG (Sig @{ agenda = $ag; idleSec = 30 })))
Check 'gaps: once per gap' (($x -join '/') -eq 'focus//') ($x -join '/')
Check 'gaps: not when the next busy meeting is under 60 min off, one is on now, or the last input was 2+ min ago' ((GapRun (Agenda @(Ev '10:30' '11:00'))) -eq '' -and (GapRun (Agenda @(Ev '09:30' '10:30' 4 $true 'busy') + @(Ev '13:00' '14:00'))) -eq '' -and (GapRun $ag 200) -eq '')
Check 'gaps: a free slot is not a meeting' ((GapRun (Agenda @(Ev '10:20' '10:50' 4 $true 'free'))) -eq 'focus')
Check 'gaps: after the last meeting of the day it applies once' ((GapRun (Agenda @(Ev '08:00' '09:00'))) -eq 'focus')
Check 'gaps: no agenda, or one for another day, does nothing' ((GapRun $null) -eq '' -and (GapRun (Agenda @(Ev '11:30' '12:00') '2026-10-20')) -eq '')
Check 'gaps: with the switch off it does nothing' ((GapRun $ag 30 $cfg) -eq '')
Check 'gaps: nothing when Focus is already on screen' ((GapRun $ag 30 $cfgG 'focus') -eq '')

# ---- Offer before a meeting ----
function OfferTick($agenda, $secs, $s = (New-TrayState), $cfg = $cfg, $o = @{}) { $o.agenda = $agenda; Step-Tray $s ([datetime]'2026-10-21 10:58:00').AddSeconds($secs) $cfg $null $null 'plain' (Sig $o) }
$ag = Agenda @(Ev '11:00' '12:00' 30)
$s = New-TrayState; $x = @((OfferTick $ag -1 $s), (OfferTick $ag 0 $s), (OfferTick $ag 10 $s), (OfferTick $ag 119 $s))
Check 'offer: 2 min before a busy Teams meeting it offers the scene for its size, once, and moves nothing itself' (@($x[0]).Count -eq 0 -and @($x[1]).Count -eq 1 -and $x[1].id -eq 'listen' -and $x[1].offer -eq $true -and @($x[2]).Count -eq 0 -and @($x[3]).Count -eq 0) (($x | % { Ids $_ }) -join '/')
Check 'offer: a small meeting offers Meetings' ((OfferTick (Agenda @(Ev '11:00' '12:00' 4)) 0).id -eq 'meetings')
Check 'offer: a meeting that is not on Teams or not busy is not offered' (@(OfferTick (Agenda @(Ev '11:00' '12:00' 4 $false)) 0).Count -eq 0 -and @(OfferTick (Agenda @(Ev '11:00' '12:00' 4 $true 'free')) 0).Count -eq 0)
Check 'offer: no agenda, or one for another day, offers nothing' (@(OfferTick $null 0).Count -eq 0 -and @(OfferTick (Agenda @(Ev '11:00' '12:00') '2026-10-20') 0).Count -eq 0)
Check 'offer: with the switch off it offers nothing' (@(OfferTick $ag 0 (New-TrayState) (Cfg (StdScenes @{ meetings = @{ size = $true }; listen = @{ size = $true } }))).Count -eq 0)
Check 'offer: its own switch is enough: size off, offer on, still offers' ((OfferTick $ag 0 (New-TrayState) (Cfg (StdScenes @{ meetings = @{ offer = $true }; listen = @{ offer = $true } }))).id -eq 'listen')
Check 'offer: a held mouse or a recent manual move does not hold an offer back' ((OfferTick $ag 0 (New-TrayState) $cfg @{ mouseDown = $true }).offer -eq $true)

# ---- A scene per monitor set; no external monitor for 30 s ----
function KeyRun($s, $key, $cfg = $cfg, $secs = 0) { Run $s $t0.AddSeconds($secs) $cfg (Sig) 'plain' $key }
$k1 = 'A=1x1@0,0'; $k2 = 'A=1x1@0,0;B=2x2@1,0'
$s = New-TrayState; $x = @((KeyRun $s $k2), (KeyRun $s $k1 $cfg 5), (KeyRun $s $k1 $cfg 10))
Check 'monitors: going to one screen applies the scene made for one screen, once' (($x -join '/') -eq '/solo/') ($x -join '/')
$s = New-TrayState; $x = @((KeyRun $s $k1), (KeyRun $s $k2 $cfg 5))
Check 'monitors: a set no scene is made for applies nothing' (($x -join '/') -eq '/') ($x -join '/')
$s = New-TrayState; $c2 = Cfg (StdScenes @{ solo = @{ noext = $true } }); $x = @((KeyRun $s $k2 $c2), (KeyRun $s $k1 $c2 5))
Check 'monitors: with the switch off it applies nothing' (($x -join '/') -eq '/') ($x -join '/')
function ScrRun($s, $secs, $n, $cfg = $cfg, $active = 'plain') { Run $s $t0.AddSeconds($secs) $cfg (Sig @{ screens = $n }) $active }
$s = New-TrayState; $x = @((ScrRun $s 0 2), (ScrRun $s 10 1), (ScrRun $s 39 1), (ScrRun $s 40 1), (ScrRun $s 100 1), (ScrRun $s 110 2), (ScrRun $s 120 1), (ScrRun $s 150 1))
Check 'no external: 30 s with one screen applies the laptop scene, once per absence' (($x -join '/') -eq '///solo////solo') ($x -join '/')
$s = New-TrayState; $x = @((ScrRun $s 0 1), (ScrRun $s 60 1))
Check 'no external: starting the agent on one screen applies nothing' (($x -join '/') -eq '/') ($x -join '/')
$s = New-TrayState; $c2 = Cfg (StdScenes @{ solo = @{ monitors = $true } }); $x = @((ScrRun $s 0 2 $c2), (ScrRun $s 10 1 $c2), (ScrRun $s 50 1 $c2))
Check 'no external: with the switch off it applies nothing' (($x -join '/') -eq '//') ($x -join '/')

# ---- Thursday prep and the starters ----
$st = ConvertFrom-Json ([IO.File]::ReadAllText((Join-Path $root 'scenes.json')))
$new = @($st.scenes | ? { $_.id -in 'listen', 'solo', 'thursday-prep' })
Check 'starters: Listen, Solo and Thursday Prep exist' ($new.Count -eq 3)
$flagsOk = @($st.scenes | ? { (@($_.auto.PSObject.Properties.Name) -join ',') -ne ($TileAutoFlags -join ',') }).Count -eq 0
Check 'starters: every scene lists every trigger switch' $flagsOk
Check 'starters: every automatic-trigger switch ships off' (@($st.scenes | ? { @($_.auto.PSObject.Properties | ? { $_.Value -ne $false }).Count }).Count -eq 0)
$th = @($st.scenes | ? { $_.id -eq 'thursday-prep' })[0]
Check 'starters: Thursday Prep is set for Thursday 14:30 and pins Procore in Chrome' ($th -and @($th.trigger.days) -join ',' -eq '4' -and $th.trigger.time -eq '14:30' -and @($th.pins | ? { $_.app -eq 'chrome' -and $_.match -eq 'Procore' }).Count -eq 1)
$tc = ConvertFrom-Json '{"scenes":[{"id":"t","trigger":{"type":"time","days":[4],"time":"14:30"}}]}'
Check 'starters: a Thursday 14:30 schedule is due that minute only' ((Ids (Get-DueScenes $tc ([datetime]'2026-10-22 14:30:10') @{})) -eq 't' -and @(Get-DueScenes $tc ([datetime]'2026-10-21 14:30:10') @{}).Count -eq 0)
$off = [IO.File]::ReadAllText((Join-Path $root 'app.html')) -match 'const AUTO=\[(.*?)\];'
$names = if ($off) { @([regex]::Matches($matches[1], '\["(\w+)"') | % { $_.Groups[1].Value }) }
Check 'starters: the page edits the same trigger switches as the tray' ($off -and ($names -join ',') -eq ($TileAutoFlags -join ',')) ($names -join ',')
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
Check 'grid: 4 or more Claude windows picks the denser grid, 3 or fewer the roomier one' ((Get-ClaudeGrid $gs 4).c -eq 6 -and (Get-ClaudeGrid $gs 9).c -eq 6 -and (Get-ClaudeGrid $gs 3).c -eq 4 -and (Get-ClaudeGrid $gs 0).c -eq 4)
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
function InCallRun($s, $extra = @()) { @((Run $s $tP $gc (Sig) 'plain' $null $false), (Run $s $tP.AddSeconds(3) $gc (Sig) 'plain' $null $true), (Run $s $tP.AddSeconds(6) $gc (Sig) 'plain' $null $true), (Run $s $tS $gc (Sig) 'plain' $null $true)) }
$s = New-TrayState; $x = InCallRun $s
Check 'guard: a scheduled apply is skipped during a call' (($x -join '/') -eq '//' + '/' -and $s.inCall) ($x -join '/')
$s = New-TrayState; $x = @(InCallRun $s) + @((Run $s $tS.AddSeconds(30) $gc (Sig) 'plain' $null $false), (Run $s $tS.AddSeconds(33) $gc (Sig) 'plain' $null $false))
Check 'guard: a skipped scheduled apply is not kept for after the call' (($x -join '/') -eq '/////') ($x -join '/')
$s = New-TrayState; $cg = Cfg (StdScenes); $sg = Sig @{ agenda = (Agenda @(Ev '09:55' '11:00' 30)) }
$x = @((Run $s $t0 $cg $sg 'plain' $null $false), (Run $s $t0.AddSeconds(3) $cg $sg 'plain' $null $true), (Run $s $t0.AddSeconds(6) $cg $sg 'plain' $null $true), (Run $s $t0.AddSeconds(7) $cg (Sig @{ agenda = $sg.agenda; screens = 1 }) 'plain' $k1), (Run $s $t0.AddSeconds(8) $cg (Sig @{ agenda = $sg.agenda; screens = 1 }) 'plain' $k2))
Check 'guard: the call trigger itself applies during a call, and a monitor change in the call does not' (($x -join '/') -eq '//listen//') ($x -join '/')
$s = New-TrayState; $x = @((Run $s $tS.AddSeconds(-9) $gc (Sig @{ manualAt = $tS.AddSeconds(-3) })), (Run $s $tS $gc (Sig @{ manualAt = $tS.AddSeconds(-5) })), (Run $s $tS.AddSeconds(6) $gc (Sig @{ manualAt = $tS.AddSeconds(-5) })))
Check 'guard: never within 10 s of a manual move; a scheduled apply goes through once the move is 10 s old, in its minute' (($x -join '/') -eq '//sched') ($x -join '/')
$s = New-TrayState; $x = @((KeyRun $s $k2 $gc), (Run $s $t0.AddSeconds(5) $gc (Sig @{ mouseDown = $true }) 'plain' $k1), (Run $s $t0.AddSeconds(6) $gc (Sig @{ mouseDown = $true })), (Run $s $t0.AddSeconds(7) $gc (Sig)))
Check 'guard: never while a mouse button is down; a monitor change waits for the button and then applies, once' (($x -join '/') -eq '///solo') ($x -join '/')
$s = New-TrayState; $x = @((KeyRun $s $k2 $gc), (Run $s $t0.AddSeconds(5) $gc (Sig @{ mouseDown = $true }) 'plain' $k1), (Run $s $t0.AddSeconds(70) $gc (Sig)))
Check 'guard: a held trigger is dropped after 60 s, not applied late' (($x -join '/') -eq '//') ($x -join '/')
$s = New-TrayState
$x = @((Run $s $t0 $gc (Sig @{ unlockedAfter = 20 }) 'focus'), (Run $s $t0.AddSeconds(10) $gc (Sig @{ wins = @($w1) }) 'focus'), (Run $s $t0.AddSeconds(13) $gc (Sig @{ wins = @($w1, (Win 2 claude)) }) 'focus'), (Run $s $t0.AddSeconds(20) $gc (Sig @{ wins = @($w1, (Win 2 claude)) }) 'focus'), (Run $s $t0.AddSeconds(29) $gc (Sig @{ wins = @($w1, (Win 2 claude)) }) 'focus'), (Run $s $t0.AddSeconds(31) $gc (Sig @{ wins = @($w1, (Win 2 claude)) }) 'focus'))
Check 'guard: at most one automatic apply per 30 s; the next waits for the cap' (($x -join '/') -eq 'default/////focus') ($x -join '/')
$s = New-TrayState; $x = @((Run $s $t0 $gc (Sig @{ unlockedAfter = 20 }) 'focus'), (Run $s $t0.AddSeconds(3) $gc (Sig @{ agenda = $sg.agenda }) 'plain' $null $false), (Run $s $t0.AddSeconds(6) $gc (Sig @{ agenda = $sg.agenda }) 'plain' $null $true), (Run $s $t0.AddSeconds(9) $gc (Sig @{ agenda = $sg.agenda }) 'plain' $null $true))
Check 'guard: the call trigger is not held by the 30 s cap' (($x -join '/') -eq 'default//' + '/listen') ($x -join '/')
$bc = Cfg (@(Scene 'work') + @(Scene 'meet' @{} @{ trigger = @{ type = 'call'; back = $true } }))
$s = New-TrayState; $x = @((Run $s $t0 $bc (Sig) 'work' $null $false), (Run $s $t0.AddSeconds(3) $bc (Sig) 'work' $null $true), (Run $s $t0.AddSeconds(6) $bc (Sig) 'work' $null $true), (Run $s $t0.AddSeconds(9) $bc (Sig) 'meet' $null $false), (Run $s $t0.AddSeconds(12) $bc (Sig) 'meet' $null $false))
Check 'guard: with live signals a call scene applies at the start and goes back at the end, even inside the 30 s cap' (($x -join '/') -eq '//meet//work') ($x -join '/')
$s = New-TrayState; $x = @((Run $s $tS $gc (Sig) 'plain'), (Run $s $tS.AddSeconds(2) $gc (Sig) 'plain'))
Check 'guard: without live signals only the schedule, display and call triggers run, and a schedule fires once' (($x -join '/') -eq 'sched/') ($x -join '/')

# ---- An older config gains the new starters, and nothing else changes ----
$mig = Join-Path $env:TEMP "tile-mig-$PID"; New-Item -ItemType Directory $mig | Out-Null
$oldCfg = '{"version":1,"categories":[["code","Code"],["browse","Browse"],["comms","Comms"],["other","Other"]],"cats":{"claude":"code"},"scenes":[{"id":"fri","name":"Fri","trigger":{"type":"time","days":[5],"time":"14:00"},"grids":{"wide":{"c":2,"r":1}},"pins":[],"fill":{"mon":"wide","apps":["*"],"skip":[],"sort":"app"}},{"id":"default","name":"Default","trigger":{"type":"manual"},"grids":{"wide":{"c":1,"r":1}},"pins":[{"app":"outlook","match":"","mon":"tall","slots":[0]}],"fill":{"mon":"wide","apps":["claude"],"skip":[],"sort":"app"}},{"id":"mine","name":"Mine","trigger":{"type":"manual"},"grids":{"wide":{"c":2,"r":1}},"pins":[],"fill":{"mon":"wide","apps":["*"],"skip":[],"sort":"app"}}]}'
[IO.File]::WriteAllText((Join-Path $mig 'config.json'), $oldCfg)
$real = $env:TILE_HOME; $env:TILE_HOME = $mig
try {
  $cmd = ". '$(Join-Path (Split-Path $Tray) 'config.ps1')'; [void](Get-TileConfigText)"
  & powershell -NoProfile -ExecutionPolicy Bypass -Command $cmd 2>&1 | Out-Null
  $m1 = [IO.File]::ReadAllText((Join-Path $mig 'config.json')); $w1 = (Get-Item (Join-Path $mig 'config.json')).LastWriteTimeUtc
  & powershell -NoProfile -ExecutionPolicy Bypass -Command $cmd 2>&1 | Out-Null
  $m2 = [IO.File]::ReadAllText((Join-Path $mig 'config.json')); $w2 = (Get-Item (Join-Path $mig 'config.json')).LastWriteTimeUtc
} finally { if ($null -eq $real) { Remove-Item env:TILE_HOME } else { $env:TILE_HOME = $real } }
$mc = ConvertFrom-Json $m1; $md = @($mc.scenes | ? { $_.id -eq 'default' })[0]
Check 'migration: an older config gains Listen, Solo, Thursday Prep, the activity map and the meeting-size rule, and its own scenes stay' ($mc.version -eq 2 -and (@($mc.scenes.id) -join ',') -eq 'fri,default,mine,listen,solo,thursday-prep' -and $mc.activity.Count -ge 5 -and $mc.meetingSize.at -eq 25 -and -not $md.auto -and $md.pins[0].slots -is [array] -and $md.pins[0].slots[0] -eq 0) $m1
$mf = @($mc.scenes | ? { $_.id -eq 'fri' })[0]
Check 'migration: nested and one-item arrays survive the rewrite (categories, days)' ($mc.categories.Count -eq 4 -and $mc.categories[0] -is [array] -and $mc.categories[0][1] -eq 'Code' -and $mf.trigger.days -is [array] -and $mf.trigger.days[0] -eq 5 -and $mc.cats.claude -eq 'code' -and $m1 -notmatch '"Count":|"value":') $m1
Check 'migration: a second read changes nothing' ($m1 -ceq $m2 -and $w1 -eq $w2)
Remove-Item -Recurse -Force $mig -ErrorAction SilentlyContinue

if ($standalone) { if ($script:fail) { "$($script:fail) check(s) failed."; exit 1 } else { 'All trigger checks passed.' } }
