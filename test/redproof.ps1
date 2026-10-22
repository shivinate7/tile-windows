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
manual-move guard, 10 s ## tray.ps1 ## $sig.manualAt).TotalSeconds -lt 10 ## $sig.manualAt).TotalSeconds -lt 0 ## never within 10 s of a manual move
mouse-down guard ## tray.ps1 ## $held = $sig.mouseDown -or ## $held = $false -or ## never while a mouse button is down
30 s cap ## tray.ps1 ## $capped = ($now - $s.lastAuto).TotalSeconds -lt 30 ## $capped = ($now - $s.lastAuto).TotalSeconds -lt 0 ## at most one automatic apply per 30 s
call trigger exempt from the cap ## tray.ps1 ## -not $capped -or $_.kind -eq 'call' ## -not $capped ## not held by the 30 s cap
60 s expiry of a held trigger ## tray.ps1 ## @($s.pend | ? { $_.exp -gt $now }) ## @($s.pend | ? { $true }) ## dropped after 60 s
desk: lock of 5 min ## tray.ps1 ## [double]$sig.unlockedAfter -ge 300 ## [double]$sig.unlockedAfter -ge 0 ## desk: the first unlock of the day
desk: idle of 10 min ## tray.ps1 ## elseif ([double]$sig.idleSec -ge 600) ## elseif ([double]$sig.idleSec -ge 60) ## under 10 min idle does nothing
desk: an unlock ends the idle span ## tray.ps1 ## $s.idled = $false; $first = $s.deskDay -ne $day ## $first = $s.deskDay -ne $day ## a lock inside an idle span
desk: off switch on the idle trigger ## tray.ps1 ## if (Test-Auto (Get-Scene $cfg $active) 'desk') { $ev += ## if ($true) { $ev += ## the off switch on the active scene
window: 3 s hold ## tray.ps1 ## ($now - $s.newSeen[$_]).TotalSeconds -ge 3 ## ($now - $s.newSeen[$_]).TotalSeconds -ge 0 ## holds 3 s
window: size floor ## tray.ps1 ## [int]$w.w -lt 400 -or [int]$w.h -lt 300 ## [int]$w.w -lt 0 -or [int]$w.h -lt 0 ## under 400x300
window: scene apps only ## tray.ps1 ## $on -and (Test-SceneApp $sc $w.app) ## $on -and $true ## under 400x300 or an app
window: off switch ## tray.ps1 ## $on = Test-Auto $sc 'window' ## $on = $true ## a scene with the switch off does nothing
activity: 60 s dwell ## tray.ps1 ## ($now - $s.act.since).TotalSeconds -ge 60 ## ($now - $s.act.since).TotalSeconds -ge 0 ## a minute in Procore
activity: already on that scene ## tray.ps1 ## if ($active -eq $to) { $s.act.done = $true; return } ## if ($false) { return } ## when the layout already is that scene
activity: off switch ## tray.ps1 ## if (-not (Test-Auto (Get-Scene $cfg $to) 'activity')) { return } ## ## mapped scene with the switch off
agenda: stale or missing does nothing ## tray.ps1 ## if ($d -ne $now.ToString('yyyy-MM-dd')) { return $null } ## ## no agenda, or one for another day
size: off switch ## tray.ps1 ## if (Test-Auto (Get-Scene $cfg $id) 'size') { $id } else { '' } ## $id ## with the switch off on both scenes
gaps: 60 min ## tray.ps1 ## ($next.start - $now).TotalMinutes -lt 60 ## ($next.start - $now).TotalMinutes -lt 0 ## not when the next busy meeting is under 60 min
gaps: touched in the last 2 min ## tray.ps1 ## $idle -ge 120 ## $idle -ge 99999 ## last input was 2+ min ago
gaps: once per gap ## tray.ps1 ## if ($s.gapKey -eq $k) { return } ## ## once per gap
gaps: off switch ## tray.ps1 ## $f = @(Get-AutoScenes $cfg 'gaps')[0] ## $f = @($cfg.scenes | ? { $_.id -eq 'focus' })[0] ## gaps: with the switch off
offer: once per meeting ## tray.ps1 ## if ($s.offered[$k]) { continue } ## ## once, and moves nothing
offer: 2 min ahead ## tray.ps1 ## $now -ge $_.start.AddMinutes(-2) ## $now -ge $_.start.AddMinutes(-20) ## offer: 2 min before
offer: off switch ## tray.ps1 ## if ($id -and (Test-Auto (Get-Scene $cfg $id) 'offer')) ## if ($id) ## offer: with the switch off
monitors: the set must match ## tray.ps1 ## ? { [int]$_.screens -eq $n })[0]; if ## ? { $true })[0]; if ## a set no scene is made for
monitors: off switch ## tray.ps1 ## @(Get-AutoScenes $cfg 'monitors' | ? ## @($cfg.scenes | ? ## monitors: with the switch off
no external: 30 s ## tray.ps1 ## ($now - $s.soloSince).TotalSeconds -lt 30) { return } ## ($now - $s.soloSince).TotalSeconds -lt 0) { return } ## no external: 30 s
no external: the first reading only seeds ## tray.ps1 ## $s.screensSeen = $true; $s.soloDone = $true } ## $s.screensSeen = $true } ## starting the agent on one screen
no external: once per absence ## tray.ps1 ## ({ $st.soloDone = $true }.GetNewClosure()) ## ({ }.GetNewClosure()) ## once per absence
grid: threshold ## tray.ps1 ## if ($n -ge [int]$sc.claudeGrid.at) ## if ($n -gt [int]$sc.claudeGrid.at) ## grid: 4 or more
page and tray list the same switches ## tray.ps1 ## 'noext', 'grid') ## 'noext') ## the page edits the same trigger switches
migration: only when older ## config.ps1 ## if ([int]$c.version -ge [int]$st.version) { return $text } ## ## a second read changes nothing
migration: never re-adds a deleted scene ## config.ps1 ## [int]$_.since -gt [int]$c.version -and ## $true -and ## an older config gains
'@
$scratch = Join-Path $env:TEMP "tile-red-$PID"; New-Item -ItemType Directory $scratch | Out-Null
function Run-Triggers { (& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'triggers.ps1') -Tray (Join-Path $scratch 'tray.ps1') 2>&1 | % { "$_" }) }
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
    $hit = @($fails | ? { $_ -like "*$red*" })
    if ($hit.Count) { $nm = $hit[0] -replace '^FAIL\s+', ''; "RED   $name -> $($nm.Substring(0, [Math]::Min(90, $nm.Length)))" }
    else { "NOT RED $name : failed checks: $(if ($fails.Count) { $fails.Count } else { 'none' })"; $bad++ }
  }
} finally { Remove-Item -Recurse -Force $scratch -ErrorAction SilentlyContinue }
if ($bad) { "$bad guard(s) did not go red."; exit 1 } else { 'Every guard goes red when broken.' }
