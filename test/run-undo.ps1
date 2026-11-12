# Checks for the run Undo (run undo decision; design notes docs/design/mockups/run-undo-notes.md). A run that moves windows shows a
# toast with one Undo action. Undo puts the windows back, restores the scene the run changed, and counts as the owner's own move.
# Fakes only: $tile, $icon and Send-RunToast are fakes and $NoApply is set, so no window moves, no toast shows, no registry is
# written, and no profile folder is made (TILE_HOME names a folder this file never creates; the last check proves it).
# Run alone: powershell -NoProfile -ExecutionPolicy Bypass -File test\run-undo.ps1 [-Tray <path to a tray.ps1 copy>]
# test\run.ps1 runs this file in a child powershell and counts its FAIL lines.
#
# Seams the builder must meet in tray.ps1 (names and fields are the contract; the test reads nothing else):
#   Apply-Scene($s, $why, [string]$prev = ''): $prev is the scene on screen before the run ('' when unknown). A run whose
#     placed[] has note 'moved' calls Send-RunToast once with a notice: kind 'toast'; title "<name> applied"; body
#     "<why, first letter in capitals>. Moved N window(s)." (one window is singular); actions = one
#     @{ label = 'Undo'; launch = 'tilewindows://undo?run=<id>' }; tag and group = one constant for every run toast.
#     It clears $script:offer and sets $script:runUndo = {id, at, scene, prev, changed, moved}, with or without $NoApply.
#     A run that moves no window, a failed run and the meeting offer keep Note (the balloon), with the text they have now.
#   Send-RunToast($notice): the one display call for a run toast. Under $NoIcon it is not called, and nothing is cleared.
#   Invoke-RunUndo($rec, $runId, $wins, $now): $rec = $script:runUndo, or $null after a restart; $wins = current windows
#     {id, app, title, x, y, w, h, min}. Returns {status 'undone' | 'later' | 'gone', text, scene (the scene to put back, or
#     '' when the run did not change it), manualAt (= $now when a window moved), placed, stayed, closed}. It places with
#     `& $tile -Place <json> -Json` (plus -DryRun under $NoApply), as the board's /apply does. A window goes back only when its
#     rect is within 4 px of the run's rect on each edge. A window minimised before the run (x <= -20000) is skipped.
#     Text: "Put back N windows." or "Put back N of M windows.", then " You moved <app> since, so it stays." or " <app> closed".
#   Get-UndoProtocolKeys(): rows {path, name, value} for HKCU:\Software\Classes\tilewindows (name 'URL Protocol') and for its
#     shell\open\command (value runs tray.ps1 with %1). Pure: it writes nothing. install.ps1 and uninstall.ps1 call it.
#   Env gate TILE_NO_REGISTRY=1: install.ps1 and uninstall.ps1 skip the protocol keys. test\run.ps1 sets it on every installer run.
#   The -NoIcon tray start in test\run.ps1 shows and clears no toast.
#   A seam tray.ps1 does not define fails its own check first, as move.ps1 does; the other checks of that case do not run.
param([string]$Tray = (Join-Path (Split-Path $PSScriptRoot) 'tray.ps1'))
$ErrorActionPreference = 'Stop'
$root = Split-Path $Tray
$utf8 = New-Object Text.UTF8Encoding $false
$script:fail = 0
function Check([string]$name, $ok, [string]$detail = '') { if ($ok) { "PASS  $name" } else { $script:fail++; "FAIL  $name  $detail" } }

# The home folder is named here and never made. Every write path in this file goes to a fake.
$homeNever = Join-Path ([IO.Path]::GetTempPath()) ('tile-undo-never-' + [guid]::NewGuid().ToString('n'))
$env:TILE_HOME = $homeNever
. $Tray -Lib

# Functions the -Lib surface lacks (the head's Note, Offer-Scene, Apply-Scene, or a seam) are read from tray.ps1 itself, so the
# run uses the file's own code with the fakes below in place. $fileFns says which functions tray.ps1 defines at all.
$tree = [Management.Automation.Language.Parser]::ParseFile($Tray, [ref]$null, [ref]$null)
$trayFns = @($tree.FindAll({ param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] }, $false))
$fileFns = @($trayFns | ForEach-Object { $_.Name })
foreach ($fn in $trayFns) { if (-not (Get-Command $fn.Name -CommandType Function -ErrorAction SilentlyContinue)) { . ([scriptblock]::Create($fn.Extent.Text)) } }

# ---- Fakes: the balloon (Note calls $icon.ShowBalloonTip), the tile (-Scene returns $script:rec.placed; -Place records its JSON),
# and the toast sink. $NoApply is set, so no state.json or log write runs.
$script:rec = @{ balloons = New-Object Collections.ArrayList; toasts = New-Object Collections.ArrayList; places = New-Object Collections.ArrayList; placed = @(); tileFail = $false }
$script:offer = $null; $script:runUndo = $null
$NoApply = $true; $NoIcon = $false
$icon = [pscustomobject]@{}
Add-Member -InputObject $icon -MemberType ScriptMethod -Name ShowBalloonTip -Value { param($ms, $title, $text, $tip) [void]$script:rec.balloons.Add([pscustomobject]@{ title = $title; text = $text }) }
$tile = {
  param([string]$Scene = '', [string]$Place = '', [string]$PlaceFile = '', [switch]$Json, [switch]$DryRun)
  if ($Place -or $PlaceFile) {
    $placeSpec = if ($PlaceFile) { [IO.File]::ReadAllText($PlaceFile) } else { $Place }
    [void]$script:rec.places.Add([pscustomobject]@{ json = $placeSpec; dryRun = [bool]$DryRun })
    return (ConvertTo-Json -InputObject @(@(ConvertFrom-Json $placeSpec) | ForEach-Object { [pscustomobject]@{ app = $_.app; title = $_.title; ok = $true; note = 'moved' } }) -Compress)
  }
  if ($script:rec.tileFail) { throw 'tile failed' }
  ConvertTo-Json -Compress -Depth 6 ([pscustomobject]@{ placed = @($script:rec.placed) })
}
# RUN-TOAST-FAKE: the sink records the notice; nothing reaches the screen.
function Send-RunToast($notice) { $script:rec.sinkFake = $true; [void]$script:rec.toasts.Add($notice) }

function Reset-Run { $script:rec.balloons.Clear(); $script:rec.toasts.Clear(); $script:rec.places.Clear(); $script:rec.tileFail = $false; $script:offer = $null; $script:runUndo = $null }
function Rect($x, $y, $w, $h) { [pscustomobject]@{ x = $x; y = $y; w = $w; h = $h } }
function Moved($id, $app, $title, $from, $to, [string]$note = 'moved') { [pscustomobject]@{ id = $id; app = $app; title = $title; x = $to.x; y = $to.y; w = $to.w; h = $to.h; from = $from; note = $note; ok = $true } }
function Win($id, $app, $title, $r) { [pscustomobject]@{ id = $id; app = $app; title = $title; x = $r.x; y = $r.y; w = $r.w; h = $r.h } }
function Shown { "toasts=$(@($script:rec.toasts).Count) balloons=$(@($script:rec.balloons).Count) last balloon='$(@($script:rec.balloons)[-1].text)'" }
function RunMoved($sc, [string]$prev, $placed, [string]$why = 'because a new window opened') {
  $script:rec.placed = @($placed); $n0 = @($script:rec.toasts).Count
  $null = Apply-Scene $sc $why $prev
  if (@($script:rec.toasts).Count -gt $n0) { @($script:rec.toasts)[-1] }
}
function RunIdOf($notice) { if ($notice -and @($notice.actions).Count) { $l = [string]@($notice.actions)[0].launch; if ($l -match '^tilewindows://undo\?run=(.+)$') { $matches[1] } } }
function Sent { foreach ($p in @($script:rec.places)) { foreach ($e in @(ConvertFrom-Json $p.json)) { $e } } }
function Brief($list) { (@($list) | ForEach-Object { "$($_.id) $($_.x),$($_.y) $($_.w)x$($_.h)" }) -join '; ' }
function UndoNow($rid, $wins, $now) { $script:rec.places.Clear(); $o = @(Invoke-RunUndo $script:runUndo $rid $wins $now); if ($o.Count) { $o[-1] } }
function Scope([string]$case, [string]$seam) { $script:scopeOk = [bool]($fileFns -contains $seam); Check "$case (tray.ps1 defines $seam)" $script:scopeOk "tray.ps1 defines no $seam" }
function TSig($o = @{}) { $d = @{ idleSec = 0; locked = $false; unlockedAfter = $null; mouseDown = $false; manualAt = [datetime]::MinValue; wins = $null; fg = $null; screens = $null; agenda = $null }; foreach ($k in $o.Keys) { $d[$k] = $o[$k] }; [pscustomobject]$d }
function Ids($x) { (@($x) | ForEach-Object { $_.id }) -join ',' }
# Does a call to $name sit in $text as code? The parser decides: comments, strings and here-strings hold no call.
function Test-CallIn([string]$text, [string]$name) {
  $ast = [Management.Automation.Language.Parser]::ParseInput($text, [ref]$null, [ref]$null)
  [bool]@($ast.FindAll({ param($n) $n -is [Management.Automation.Language.CommandAst] -and $n.GetCommandName() -eq $name }, $true)).Count
}

# ---- Controls: green on the head. They show the harness runs, and that the scanner reads code and not text.
$tc = ConvertFrom-Json '{"scenes":[{"id":"a","trigger":{"type":"time","days":[1],"time":"09:00"}}]}'
Check 'control: a due schedule scene fires on its minute (harness)' ((Ids (Get-DueScenes $tc ([datetime]'2026-11-09 09:00') @{})) -eq 'a') (Ids (Get-DueScenes $tc ([datetime]'2026-11-09 09:00') @{}))
$cn = 'Get-UndoProtocolKeys'
Check 'scan control: a call in a comment is not a call' (-not (Test-CallIn "# $cn" $cn)) 'a comment counted as a call'
Check 'scan control: a call name inside a string is not a call' (-not (Test-CallIn ("`$x = '" + $cn + "'") $cn)) 'a string counted as a call'
Check 'scan control: a call name inside a here-string is not a call' (-not (Test-CallIn ("`$x = @'`r`n" + $cn + "`r`n'@") $cn)) 'a here-string counted as a call'
Check 'scan control: a comment opener inside a string does not hide a call' (Test-CallIn ("`$x = '# not a comment'; " + $cn) $cn) 'the call after the string was missed'
Check 'scan control: a lone apostrophe in a comment does not hide the next call' (Test-CallIn ("# don't`r`n" + $cn) $cn) 'the call after the apostrophe was missed'

# ---- The toast: one run that moves windows shows one toast; a run that moves nothing, a failure and the offer keep the balloon.
$focus = [pscustomobject]@{ id = 'focus'; name = 'Focus' }
$work = [pscustomobject]@{ id = 'work'; name = 'Work' }
$from1 = Rect 100 100 400 300; $t1 = Rect 0 0 960 1040
$from2 = Rect 1000 100 500 400; $t2 = Rect 960 0 960 1040
$two = @((Moved 1001 'claude' 'Draft' $from1 $t1), (Moved 1002 'claude' 'Notes' $from2 $t2))
Check 'the toast sink in scope is this file''s fake, so no real toast can show' ([bool]((Get-Command Send-RunToast -CommandType Function).ScriptBlock.ToString() -match 'sinkFake'))

Reset-Run
[void](RunMoved $focus 'work' $two 'because a new window opened')
$t = @($script:rec.toasts)[0]
Check 'a run that moved windows shows one toast, not a balloon' ((@($script:rec.toasts).Count -eq 1) -and (@($script:rec.balloons).Count -eq 0)) (Shown)
Check 'the toast title is the scene name and applied' ([bool]($t -and $t.title -ceq 'Focus applied')) "$(Shown) | title '$($t.title)'"
Check 'the toast body gives the run reason and the count' ([bool]($t -and $t.body -ceq 'Because a new window opened. Moved 2 windows.')) "$(Shown) | body '$($t.body)'"
Check 'the toast has one Undo action that launches the run' ([bool]($t -and @($t.actions).Count -eq 1 -and @($t.actions)[0].label -ceq 'Undo' -and @($t.actions)[0].launch -match '^tilewindows://undo\?run=.+$')) "$(Shown) | actions $(@($t.actions).Count)"

Reset-Run
[void](RunMoved $work 'focus' @((Moved 1003 'claude' 'Draft' $from1 $t1)) 'because you are back at your desk')
$t = @($script:rec.toasts)[0]
Check 'a one-window run says Moved 1 window, singular' ([bool]($t -and $t.body -ceq 'Because you are back at your desk. Moved 1 window.')) "$(Shown) | body '$($t.body)'"

Reset-Run
[void](RunMoved $focus 'work' $two 'because a new window opened')
[void](RunMoved $work 'focus' @((Moved 1003 'claude' 'Draft' $from1 $t1)) 'because you are back at your desk')
$ta = @($script:rec.toasts)[0]; $tb = @($script:rec.toasts)[1]
Check 'every run toast shares one tag and one group' ([bool]($ta -and $tb -and $ta.tag -and $ta.tag -ceq $tb.tag -and $ta.group -and $ta.group -ceq $tb.group)) "tags '$($ta.tag)' and '$($tb.tag)'"

Reset-Run
[void](RunMoved $focus 'work' $two 'from the tray')
$t = @($script:rec.toasts)[0]
Check 'a run from the tray menu shows the same toast' ([bool]($t -and $t.body -ceq 'From the tray. Moved 2 windows.')) "$(Shown) | body '$($t.body)'"

Reset-Run
$script:offer = [pscustomobject]@{ scene = $work; exp = [datetime]'2026-11-12 15:30:00' }
[void](RunMoved $focus 'work' $two 'because you chose to arrange for the meeting')
$ranToast = (@($script:rec.toasts).Count -eq 1)
Check 'the toast path runs for an arranged meeting (scope)' $ranToast (Shown)
if ($ranToast) { Check 'the toast path clears the meeting offer, so a late click arranges nothing' ($null -eq $script:offer) "offer still armed for $($script:offer.scene.name)" }

Reset-Run
[void](RunMoved $focus 'work' @() 'because a new window opened')
Check 'a run that moved nothing keeps the balloon, with its count of 0' ((@($script:rec.toasts).Count -eq 0) -and (@($script:rec.balloons).Count -eq 1) -and ([bool](@($script:rec.balloons)[0].text -ceq 'Focus applied because a new window opened. Moved 0 window(s).'))) (Shown)

Reset-Run
$script:rec.tileFail = $true
[void](RunMoved $focus 'work' @() 'because a new window opened')
Check 'a failed run keeps the balloon, with the error' ((@($script:rec.toasts).Count -eq 0) -and (@($script:rec.balloons).Count -eq 1) -and ([bool](@($script:rec.balloons)[0].text -ceq 'Focus failed: tile failed'))) (Shown)

Reset-Run
Offer-Scene $focus 'a meeting starts soon'
Check 'the meeting offer keeps the balloon and stays armed' ((@($script:rec.toasts).Count -eq 0) -and (@($script:rec.balloons).Count -eq 1) -and ([bool](@($script:rec.balloons)[0].title -ceq 'Meeting in 2 minutes')) -and ($null -ne $script:offer)) (Shown)

Reset-Run
$saveIcon = $icon; $icon = $null; $NoIcon = $true
[void](RunMoved $focus 'work' $two 'because a new window opened')
$NoIcon = $false; $icon = $saveIcon
Check 'under -NoIcon a run that moved windows shows no toast and no balloon' ((@($script:rec.toasts).Count -eq 0) -and (@($script:rec.balloons).Count -eq 0)) (Shown)

# ---- Undo: the windows go back through tile.ps1 -Place, the scene and the manual-move time are set, the newest run only.
$b0 = [datetime]'2026-11-12 15:20:00'; $tU = [datetime]'2026-11-12 15:25:00'

$p1 = @((Moved 1001 'claude' 'Draft' $from1 $t1), (Moved 1002 'chrome' 'Docs' $from2 $t2))
$w1 = @((Win 1001 'claude' 'Draft' $t1), (Win 1002 'chrome' 'Docs' $t2))
Reset-Run
$rid1 = RunIdOf (RunMoved $focus 'work' $p1)
Scope 'undo sends each moved window back to its from rect' 'Invoke-RunUndo'
if ($script:scopeOk) {
  $r = UndoNow $rid1 $w1 $tU
  $sent = @(Sent)
  Check 'undo sends each moved window back to its from rect (through tile.ps1 -Place)' ((@($sent).Count -eq 2) -and (@($sent | ? { $_.id -eq 1001 -and $_.x -eq 100 -and $_.y -eq 100 -and $_.w -eq 400 -and $_.h -eq 300 }).Count -eq 1) -and (@($sent | ? { $_.id -eq 1002 -and $_.x -eq 1000 -and $_.y -eq 100 -and $_.w -eq 500 -and $_.h -eq 400 }).Count -eq 1)) "sent: $(Brief $sent)"
  Check 'undo under -NoApply places as dry runs only' ((@($script:rec.places).Count -ge 1) -and (@($script:rec.places | ? { -not $_.dryRun }).Count -eq 0)) "place calls: $(@($script:rec.places).Count)"
  Check 'undo says how many windows it put back' ([bool]($r -and $r.text -ceq 'Put back 2 windows.')) "text '$($r.text)'"
}

$p2 = @((Moved 1001 'claude' 'Draft' $from1 $t1), (Moved 1002 'outlook' 'Inbox' $from2 $t2))
$w2 = @((Win 1001 'claude' 'Draft' (Rect 3 0 960 1040)), (Win 1002 'outlook' 'Inbox' (Rect 965 0 960 1040)))
Reset-Run
$rid2 = RunIdOf (RunMoved $focus 'work' $p2)
Scope 'a window 3 px off its run rect goes back, a window 5 px off stays' 'Invoke-RunUndo'
if ($script:scopeOk) {
  $r = UndoNow $rid2 $w2 $tU
  $sent = @(Sent)
  Check 'a window 3 px off its run rect goes back' (@($sent | ? { $_.id -eq 1001 -and $_.x -eq 100 }).Count -eq 1) "sent: $(Brief $sent)"
  Check 'a window 5 px off its run rect stays where the owner put it' (@($sent | ? { $_.id -eq 1002 }).Count -eq 0) "sent: $(Brief $sent)"
  Check 'the follow-up says which window stayed' ([bool]($r -and $r.text -ceq 'Put back 1 of 2 windows. You moved Outlook since, so it stays.')) "text '$($r.text)'"
}

$p3 = @((Moved 1003 'teams' 'Call' (Rect -32000 -32000 160 28) $t1), (Moved 1001 'claude' 'Draft' $from1 $t2))
$w3 = @((Win 1003 'teams' 'Call' $t1), (Win 1001 'claude' 'Draft' $t2))
Reset-Run
$rid3 = RunIdOf (RunMoved $focus 'work' $p3)
Scope 'a window minimised before the run is skipped' 'Invoke-RunUndo'
if ($script:scopeOk) {
  $r = UndoNow $rid3 $w3 $tU
  $sent = @(Sent)
  Check 'a window minimised before the run is not sent back' (@($sent | ? { $_.id -eq 1003 }).Count -eq 0) "sent: $(Brief $sent)"
  Check 'the window that was not minimised still goes back' (@($sent | ? { $_.id -eq 1001 -and $_.x -eq 100 }).Count -eq 1) "sent: $(Brief $sent)"
}

$p4 = @((Moved 1001 'claude' 'Draft' $from1 $t1), (Moved 1002 'outlook' 'Inbox' $from2 $t2))
$w4 = @((Win 1001 'claude' 'Draft' $t1))
Reset-Run
$rid4 = RunIdOf (RunMoved $focus 'work' $p4)
Scope 'a window closed since the run is skipped' 'Invoke-RunUndo'
if ($script:scopeOk) {
  $r = UndoNow $rid4 $w4 $tU
  $sent = @(Sent)
  Check 'a window closed since the run is skipped, the rest go back' ((@($sent).Count -eq 1) -and ([bool]($sent[0].id -eq 1001))) "sent: $(Brief $sent)"
  Check 'the follow-up says the closed window is gone' ([bool]($r -and $r.text -match 'Outlook closed')) "text '$($r.text)'"
}

$p5 = @((Moved 1001 'claude' 'Draft' $from1 $t1)); $w5 = @((Win 1001 'claude' 'Draft' $t1))
Reset-Run
$ridA = RunIdOf (RunMoved $focus 'work' $p5)
Scope 'undo puts back the scene the run changed, and leaves an unchanged one' 'Invoke-RunUndo'
if ($script:scopeOk) {
  $rA = UndoNow $ridA $w5 $tU
  Check 'a run that changed the scene: undo puts the earlier scene back' ([bool]($rA -and $rA.scene -ceq 'work')) "scene '$($rA.scene)'"
  Reset-Run
  $ridB = RunIdOf (RunMoved $focus 'focus' $p5)
  $rB = UndoNow $ridB $w5 $tU
  Check 'a run that left the scene as it was (desk or window): undo leaves it' ([bool]($rB -and -not $rB.scene)) "scene '$($rB.scene)'"
}

$p6 = @((Moved 1001 'claude' 'Draft' $from1 $t1)); $w6 = @((Win 1001 'claude' 'Draft' $t1))
Reset-Run
$rid6 = RunIdOf (RunMoved $focus 'work' $p6)
$tM = $b0.AddSeconds(31)
Scope 'undo counts as your own move: it sets the manual-move time' 'Invoke-RunUndo'
if ($script:scopeOk) {
  $r6 = UndoNow $rid6 $w6 $tM
  Check 'undo sets the manual-move time to its own time' ([bool]($r6 -and $r6.manualAt -eq $tM)) "manualAt '$($r6.manualAt)'"
  $cfgU = ConvertFrom-Json '{"scenes":[{"id":"focus","name":"Focus","trigger":{"type":"manual"},"auto":{"desk":true}}]}'
  $sU = New-TrayState
  $null = Step-Tray $sU $b0 $cfgU $null $null 'focus' (TSig @{ idleSec = 3600 })
  $null = Step-Tray $sU $b0.AddSeconds(30) $cfgU $null $null 'focus' (TSig @{ idleSec = 5; mouseDown = $true })
  $mt = if ($r6) { $r6.manualAt } else { [datetime]::MinValue }
  $late = Ids (Step-Tray $sU $b0.AddSeconds(41) $cfgU $null $null 'focus' (TSig @{ idleSec = 5; manualAt = $mt }))
  Check 'a desk return that was waiting does not come back after the undo' ($late -eq '') "applied: '$late'"
}

$pA = @((Moved 1001 'claude' 'Draft' $from1 $t1)); $wA = @((Win 1001 'claude' 'Draft' $t1))
$pB = @((Moved 1002 'chrome' 'Docs' $from2 $t2)); $wB = @((Win 1002 'chrome' 'Docs' $t2))
Reset-Run
$ridOld = RunIdOf (RunMoved $focus 'work' $pA)
$ridNew = RunIdOf (RunMoved $work 'focus' $pB)
Scope 'only the newest run can be undone' 'Invoke-RunUndo'
if ($script:scopeOk) {
  $rOld = UndoNow $ridOld $wA $tU
  Check 'an older run''s Undo puts nothing back, because a later run replaced it' ([bool]($rOld -and $rOld.status -ceq 'later' -and @(Sent).Count -eq 0)) "status '$($rOld.status)', sent $(@(Sent).Count)"
  $rNew = UndoNow $ridNew $wB $tU
  Check 'the newest run''s Undo still puts its windows back' ([bool]($rNew -and $rNew.status -ceq 'undone' -and @(Sent).Count -eq 1)) "status '$($rNew.status)', sent $(@(Sent).Count)"
}

Scope 'after a tray restart, Undo does nothing' 'Invoke-RunUndo'
if ($script:scopeOk) {
  $script:rec.places.Clear()
  $o = @(Invoke-RunUndo $null $ridNew $wB $tU); $rR = if ($o.Count) { $o[-1] } else { $null }
  Check 'after a tray restart, Undo puts nothing back' ([bool]($rR -and $rR.status -ceq 'gone' -and @(Sent).Count -eq 0)) "status '$($rR.status)', sent $(@(Sent).Count)"
}

Reset-Run
$ridT = RunIdOf (RunMoved $focus 'work' $p1)
$recT = $script:runUndo
$tT = @($script:rec.toasts)[-1]
$names = if ($tT) { @($tT.PSObject.Properties.Name) } else { @() }
Check 'the run toast carries no expiry: Undo lasts until the next run' ([bool]($tT -and (@($names | ? { $_ -match 'xpir' }).Count -eq 0))) "toasts shown: $(@($script:rec.toasts).Count); fields: $($names -join ',')"
Scope 'undo is still offered two hours after the run' 'Invoke-RunUndo'
if ($script:scopeOk) {
  if ($recT -and $recT.at) {
    $r9 = UndoNow $ridT $w1 ($recT.at.AddHours(2))
    Check 'undo is still offered two hours after the run' ([bool]($r9 -and $r9.status -ceq 'undone' -and @(Sent).Count -eq 2)) "status '$($r9.status)', sent $(@(Sent).Count)"
  } else { Check 'undo is still offered two hours after the run (the run record has its time, at)' $false 'the run record has no time (at)' }
}

$p10 = @(foreach ($i in 1..10) { Moved (1000 + $i) 'claude' "Doc $i" (Rect (20 * $i) (20 * $i) 400 300) (Rect (96 * ($i - 1)) 0 96 1040) })
$w10 = @(foreach ($i in 1..10) { Win (1000 + $i) 'claude' "Doc $i" (Rect (96 * ($i - 1)) 0 96 1040) })
Reset-Run
$rid10 = RunIdOf (RunMoved $focus 'work' $p10)
$tt10 = @($script:rec.toasts)[0]
Check 'a full run of ten windows says Moved 10 windows' ([bool]($tt10 -and $tt10.body -like '* Moved 10 windows.')) "body '$($tt10.body)'"
Scope 'a full run: undo puts all ten windows back' 'Invoke-RunUndo'
if ($script:scopeOk) {
  $r10 = UndoNow $rid10 $w10 $tU
  $s10 = @(Sent)
  Check 'a full run: undo sends all ten windows back to their from rects' ((@($s10).Count -eq 10) -and (@($s10 | ? { $_.id -eq 1001 -and $_.x -eq 20 -and $_.y -eq 20 }).Count -eq 1)) "sent $(@($s10).Count)"
  Check 'a full run: the follow-up says Put back 10 windows.' ([bool]($r10 -and $r10.text -ceq 'Put back 10 windows.')) "text '$($r10.text)'"
}

# ---- Registration: the protocol keys come from one -Lib function, and install.ps1 and uninstall.ps1 call it. Text is read, not HKCU.
Scope 'the protocol keys name the tilewindows scheme and its open command' 'Get-UndoProtocolKeys'
if ($script:scopeOk) {
  $keys = @(Get-UndoProtocolKeys)
  Check 'the protocol keys include the tilewindows scheme (URL Protocol)' (@($keys | ? { $_.path -ceq 'HKCU:\Software\Classes\tilewindows' -and $_.name -ceq 'URL Protocol' }).Count -eq 1) "paths: $(@($keys | ForEach-Object { $_.path }) -join ' ; ')"
  Check 'the open command runs tray.ps1 with the link as %1' (@($keys | ? { $_.path -ceq 'HKCU:\Software\Classes\tilewindows\shell\open\command' -and $_.value -match 'tray\.ps1' -and $_.value -match '%1' }).Count -eq 1) "paths: $(@($keys | ForEach-Object { $_.path }) -join ' ; ')"
}
$installText = [IO.File]::ReadAllText((Join-Path $root 'install.ps1'), $utf8)
$uninstallText = [IO.File]::ReadAllText((Join-Path $root 'uninstall.ps1'), $utf8)
Check 'install.ps1 registers the tilewindows protocol (a call to Get-UndoProtocolKeys in code)' (Test-CallIn $installText 'Get-UndoProtocolKeys') 'install.ps1 has no call to Get-UndoProtocolKeys in code'
Check 'uninstall.ps1 removes the tilewindows protocol (a call to Get-UndoProtocolKeys in code)' (Test-CallIn $uninstallText 'Get-UndoProtocolKeys') 'uninstall.ps1 has no call to Get-UndoProtocolKeys in code'

Check 'the run wrote no profile folder (TILE_HOME was named, never made)' (-not (Test-Path -LiteralPath $homeNever)) $homeNever
if ($script:fail) { "$($script:fail) check(s) failed."; exit 1 } else { 'All run-undo checks passed.' }
