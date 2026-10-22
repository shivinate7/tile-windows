# Red proofs for the trigger checks: break one guard at a time on a scratch copy of the agent (tray.ps1, config.ps1, scenes.json),
# run test\triggers.ps1 against it, and say which check went red. A guard whose break turns nothing red is not trusted.
# Run: powershell -NoProfile -ExecutionPolicy Bypass -File test\redproof.ps1 [-Only <regex on the guard's name>]
param([string]$Only = '')
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
$utf8 = New-Object Text.UTF8Encoding $false
# name ## file ## text to find (exactly once) ## text to put there ## the check that must go red (a part of its name)
$table = @'
in-call guard ## tray.ps1 ## if ($s.inCall) { $s.pend ## if ($false) { $s.pend ## skipped during a call
manual-move hold, 10 s ## tray.ps1 ## ($now - $ma).TotalSeconds -lt 10 ## ($now - $ma).TotalSeconds -lt 0 ## waits until the move is 10 s old
mouse-down guard ## tray.ps1 ## $held = $sig.mouseDown -or ## $held = $false -or ## never while a mouse button is down
30 s cap ## tray.ps1 ## $capped = ($now - $s.lastAuto).TotalSeconds -lt 30 ## $capped = ($now - $s.lastAuto).TotalSeconds -lt 0 ## at most one automatic apply per 30 s
call trigger exempt from the cap ## tray.ps1 ## -not $capped -or $_.kind -eq 'call' ## -not $capped ## not held by the 30 s cap
call end goes back inside the cap ## tray.ps1 ## -not $capped -or $_.kind -eq 'call' ## -not $capped ## goes back at the end
60 s expiry of a held trigger ## tray.ps1 ## @($s.pend | ? { $_.exp -gt $now }) ## @($s.pend | ? { $true }) ## dropped after 60 s
manual move cancels a held one-shot ## tray.ps1 ## $s.pend = @($s.pend | ? { $_.kind -eq 'call' -or $_.gen -ge $ma }) ## $s.pend = @($s.pend) ## cancels a held one-shot
manual move cancels a waiting window ## tray.ps1 ## $s.newSeen = @{}; $s.act = $null } ## $s.act = $null } ## cancels a window that was waiting
manual move restarts the dwell ## tray.ps1 ## $s.newSeen = @{}; $s.act = $null } ## $s.newSeen = @{} } ## restarts the dwell
desk: lock length ## tray.ps1 ## [double]$sig.unlockedAfter -ge 60 * ## [double]$sig.unlockedAfter -ge 0 * ## a lock under 5 min does nothing
desk: idle length ## tray.ps1 ## 60 * (Get-Opt $cfg $asc 'desk' 'idleMin') ## 60 ## under 10 min idle does nothing
desk: an unlock ends the idle span ## tray.ps1 ## $s.idled = $false; $first = ## $first = ## a lock inside an idle span
desk: off switch on the idle trigger ## tray.ps1 ## if (Test-Auto $asc 'desk') { $ev += ## if ($true) { $ev += ## the off switch on the active scene
desk: off switch on the unlock trigger ## tray.ps1 ## -and (Test-Auto $asc 'desk')) { $active } ## ) { $active } ## not re-applied on unlock
desk: Default's own switch ## tray.ps1 ## if ($first -and (Test-Auto (Get-Scene $cfg 'default') 'desk')) ## if ($first) ## with Default off
window: hold ## tray.ps1 ## $hold = Get-Opt $cfg $sc 'window' 'holdSec' ## $hold = 0 ## that holds 3 s re-flows
window: size floor ## tray.ps1 ## [int]$w.w -lt 400 -or [int]$w.h -lt 300 ## [int]$w.w -lt 0 -or [int]$w.h -lt 0 ## a window under 400x300
window: scene apps only ## tray.ps1 ## $on -and (Test-SceneApp $sc $w.app) ## $on -and $true ## an app the scene does not place
window: off switch ## tray.ps1 ## $on = Test-Auto $sc 'window' ## $on = $true ## a scene with the switch off does nothing
thresholds come from the scene ## tray.ps1 ## $v = $sc.opt.$flag.$name; if ## $v = $null; if ## threshold:
activity: dwell ## tray.ps1 ## (Get-Opt $cfg $sc 'activity' 'dwellSec') ## 0 ## a minute in Procore
activity: already on that scene ## tray.ps1 ## if ($active -eq $to) { $s.act.done = $true; return } ## if ($false) { return } ## when the layout already is that scene
activity: off switch ## tray.ps1 ## if (-not (Test-Auto $sc 'activity')) { return } ## ## a mapped scene with the switch off
activity: grace after a hand-applied scene ## tray.ps1 ## if (($now - $s.manualApplyAt).TotalMinutes -lt (Get-Opt $cfg $sc 'activity' 'graceMin')) { return } ## ## left alone for 15 minutes
activity: own applies are not hand applies ## tray.ps1 ## if ($active -ne $s.autoApplied) { $s.manualApplyAt = $now } ## $s.manualApplyAt = $now ## not taken for one applied by hand
agenda: stale or missing does nothing ## tray.ps1 ## if ($d -ne $now.ToString('yyyy-MM-dd')) { return $null } ## ## an agenda for another day
agenda: teams reads true or false ## tray.ps1 ## teams = ConvertTo-Bool $_.teams ## teams = [bool]$_.teams ## reads as false
agenda: attendee count must read ## tray.ps1 ## attendees = [int]$_.attendees; teams ## attendees = 0; teams ## not a number is dropped
size: off switch ## tray.ps1 ## if (Test-Auto (Get-Scene $cfg $id) 'size') { $id } else { '' } ## $id ## with the switch off on both scenes
gaps: gap length ## tray.ps1 ## -lt (Get-Opt $cfg $f 'gaps' 'minutes') ## -lt 0 ## under 60 min off
gaps: touched in the last 2 min ## tray.ps1 ## $idle -ge 120 -or ## $idle -ge 99999 -or ## last input was 2+ min ago
gaps: a next meeting is required ## tray.ps1 ## $next = @($busy | ? { $_.start -gt $now } | Sort-Object start)[0] ## $next = @($busy | ? { $_.start -gt $now } | Sort-Object start)[0]; if (-not $next) { $next = [pscustomobject]@{ start = $now.AddHours(5) } } ## no meeting left today
gaps: not after a call ends ## tray.ps1 ## ($now - $s.callEndAt).TotalMinutes -lt 10 ## ($now - $s.callEndAt).TotalMinutes -lt 0 ## within 10 minutes of a call ending
gaps: once per gap ## tray.ps1 ## if ($s.gapKey -eq $k) { return } ## ## once per gap
gaps: off switch ## tray.ps1 ## $f = @(Get-AutoScenes $cfg 'gaps')[0] ## $f = @($cfg.scenes | ? { $_.id -eq 'focus' })[0] ## gaps: with the switch off
offer: once per meeting ## tray.ps1 ## if ($s.offered[$k]) { continue } ## ## once, and moves nothing
offer: lead time ## tray.ps1 ## $now -lt $e.start.AddMinutes(-(Get-Opt $cfg $osc 'offer' 'leadMin')) ## $now -lt $e.start.AddMinutes(-20) ## offer: 2 min before
offer: off switch ## tray.ps1 ## if (-not (Test-Auto $osc 'offer') -or ## if ($false -or ## offer: with the switch off
offer: its own switch is enough ## tray.ps1 ## $id = Get-SizeId $cfg $e.attendees ## $id = Get-SizeScene $cfg $e.attendees ## its own switch is enough
monitors: the set must match ## tray.ps1 ## ? { [int]$_.screens -eq $n })[0]; if ## ? { $true })[0]; if ## a set no scene is made for
monitors: off switch ## tray.ps1 ## @(Get-AutoScenes $cfg 'monitors' | ? ## @($cfg.scenes | ? ## monitors: with the switch off
no external: how long ## tray.ps1 ## (Get-Opt $cfg $sc 'noext' 'sec') ## 0 ## no external: 30 s
no external: the first reading only seeds ## tray.ps1 ## $s.screensSeen = $true; $s.soloDone = $true } ## $s.screensSeen = $true } ## starting the agent on one screen
no external: once per absence ## tray.ps1 ## ({ $st.soloDone = $true }.GetNewClosure()) ## ({ }.GetNewClosure()) ## once per absence
no external: a locked or idle PC does not count ## tray.ps1 ## if ($locked -or $idle -ge 120) { $s.soloSince = $null; return } ## if ($false) { return } ## a locked PC does not count
no external: the same event as a monitor-set scene ## tray.ps1 ## -or ($now - $s.displayAt).TotalSeconds -lt 60 ## -or ($now - $s.displayAt).TotalSeconds -lt 0 ## the same event
grid: threshold ## tray.ps1 ## if ($n -ge $at) { 'dense' } ## if ($n -gt $at) { 'dense' } ## grid: 4 or more
grid: hysteresis ## tray.ps1 ## elseif ($n -le $at - 2) { 'roomy' } elseif ($prev) { $prev } else { 'roomy' } ## else { 'roomy' } ## does not flap
page and tray list the same switches ## tray.ps1 ## 'noext', 'grid') ## 'noext') ## the page edits the same trigger switches
migration: only when older ## config.ps1 ## if ([int]$c.version -ge [int]$st.version) { return $text } ## ## a second read changes nothing
migration: never re-adds a deleted scene ## config.ps1 ## [int]$_.since -gt [int]$c.version -and ## $true -and ## an older config gains
migration: threshold defaults ## config.ps1 ## 'activity', 'meetingSize', 'optDefaults' ## 'activity', 'meetingSize' ## threshold defaults, and its own scenes stay
migration: trigger fields on a scene already there ## config.ps1 ## foreach ($k in 'screens', 'claudeGrid') ## foreach ($k in 'screens') ## gains screens, claudeGrid
migration: an auto block on every scene ## config.ps1 ## if (-not $x.PSObject.Properties['auto']) ## if ($false) ## gains an auto block
migration: a one-item array collapses ## config.ps1 ## $out = ConvertTo-Json -Depth 10 $c ## $out = (ConvertTo-Json -Depth 10 $c) -replace '"days":\s*\[\s*(\d)\s*\]', '"days": $1' ## nested and one-item arrays
grid json: depth ## tray.ps1 ## ConvertTo-Json -Depth 8 -Compress $full ## ConvertTo-Json -Depth 1 -Compress $full ## the scene JSON the tray hands
'@
$scratch = Join-Path $env:TEMP "tile-red-$PID"; New-Item -ItemType Directory $scratch | Out-Null
function Run-Triggers { $ErrorActionPreference = 'Continue'; (& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'triggers.ps1') -Tray (Join-Path $scratch 'tray.ps1') 2>&1 | % { "$_" }) }
function Reset-Scratch { foreach ($f in 'tray.ps1', 'config.ps1', 'scenes.json') { Copy-Item -LiteralPath (Join-Path $root $f) -Destination (Join-Path $scratch $f) -Force } }
$bad = 0
try {
  Reset-Scratch; $base = @(Run-Triggers | ? { $_ -like 'FAIL*' })
  if ($base.Count) { "BASE  not green on an unbroken copy: $($base -join ' | ')"; exit 1 }
  foreach ($line in ($table -split "`r?`n" | ? { $_.Trim() -and ($_ -split ' ## ')[0] -match $Only })) {
    $name, $file, $find, $repl, $red = $line -split ' ## ', 5
    Reset-Scratch; $path = Join-Path $scratch $file; $text = [IO.File]::ReadAllText($path)
    $n = ([regex]::Matches($text, [regex]::Escape($find))).Count
    if ($n -ne 1) { "STALE $name : the text to break occurs $n times in $file"; $bad++; continue }
    [IO.File]::WriteAllText($path, $text.Replace($find, $repl), $utf8)
    $out = @(Run-Triggers); $fails = @($out | ? { $_ -like 'FAIL*' })
    if (-not ($out -like 'All trigger checks passed.' -or $out -like '*check(s) failed.')) { "NOT RED $name : the run crashed, which proves nothing"; $bad++; continue }
    $hit = @($fails | ? { $_ -like "*$red*" })
    if ($hit.Count) { $nm = $hit[0] -replace '^FAIL\s+', ''; "RED   $name -> $($nm.Substring(0, [Math]::Min(90, $nm.Length)))" }
    else { "NOT RED $name : failed checks: $(if ($fails.Count) { $fails.Count } else { 'none' })"; $bad++ }
  }
} finally { Remove-Item -Recurse -Force $scratch -ErrorAction SilentlyContinue }
if ($bad) { "$bad guard(s) did not go red."; exit 1 } else { 'Every guard goes red when broken.' }
