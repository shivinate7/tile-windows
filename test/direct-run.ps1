# Checks that a test file run directly leaves no headless Edge behind when it is killed hard. test\run.ps1 puts each test child in a job
# object, so stopping the suite ends the child's processes. A file run by hand has no job: killed hard (Stop-Process -Force, a harness's
# timeout), its finally never runs, and the Edge it started stays and holds files and ports for the next run.
# Cases (the green controls beside the red subject are its scope checks, which find Edge up and the file running just before the kill,
# and the scan's synthetic sources, which hold on the old tree):
#   Edge, killed (subject): bay.ps1 is run directly with its own TEMP folder (so its Edge is told apart from every other Edge) and the
#     suite flag unset. As soon as its Edge has opened its DevTools port the file is killed hard, with no teardown. Scope first: its Edge
#     was up, the file was still running at the kill, and its own run folder is still there (the kill was hard). Then the subject: no
#     msedge of that run is still running 90 s after the kill.
#     The wait is long because a killed Edge tree can take a while to go on a loaded machine: 1 to 11 s with twelve busy loops running,
#     and one process stayed past 30 s in a whole-suite run. A run that is going to leave Edge behind never clears, so the cap costs only
#     a red run its time.
#   Wiring: every test file that starts headless Edge (a '--headless' string in its code) calls Enter-DirectRunJob as a top-level
#     statement, before that string. The scan reads each file with PowerShell's own parser, so a comment, a string or a here-string that
#     names either is no call and no Edge. Four synthetic sources check the scan: a comment, a string and a here-string naming both; a
#     lone quote in text before a good file; a call inside a function; and a call after the Edge.
# The guard (240 s) sits well above a run (about 30 s) plus the wait after the kill, which is a wait for the count to reach 0.
# test\run.ps1 runs this file in a child powershell and counts its FAIL lines.
# Run alone: powershell -NoProfile -ExecutionPolicy Bypass -File test\direct-run.ps1
param()
$ErrorActionPreference = 'Stop'
$script:fail = 0
# A failure's detail goes on one line, so a host's output shows whole in it.
function Check($name, $ok, $detail = '') { if ($ok) { "PASS  $name" } else { $script:fail++; "FAIL  $name  $(($detail -replace "`r?`n", ' | ').Trim())" } }

# Run folder (test-temp-standard): <TEMP>\tile-windows-test-runs\<pid>-<UUID>, removed at the end. The sweep of old run folders is stack-lock.ps1's.
. (Join-Path $PSScriptRoot 'run-folders.ps1')
$runsRoot = Join-Path $env:TEMP 'tile-windows-test-runs'
[void](New-Item -ItemType Directory -Force $runsRoot)
$run = Join-Path $runsRoot ("$PID-" + [guid]::NewGuid().ToString()); New-Item -ItemType Directory $run | Out-Null

# The processes of one folder: those whose command line names it. Edge's helper processes carry its --user-data-dir, so they count with it.
function Get-FolderProcs([string]$dir, [string]$exe = '') {
  $all = if ($exe) { Get-CimInstance Win32_Process -Filter "Name='$exe'" -ErrorAction SilentlyContinue } else { Get-CimInstance Win32_Process -ErrorAction SilentlyContinue }
  @($all | ? { $_.ProcessId -ne $PID -and $_.CommandLine -and $_.CommandLine.IndexOf($dir, [StringComparison]::OrdinalIgnoreCase) -ge 0 })
}
# Waits until no msedge names the folder, up to $capMs; returns the ones still running.
function Wait-EdgeGone([string]$dir, [int]$capMs) {
  $sw = [Diagnostics.Stopwatch]::StartNew()
  do { $left = @(Get-FolderProcs $dir 'msedge.exe'); if (-not $left.Count) { break }; Start-Sleep -Milliseconds 250 } while ($sw.ElapsedMilliseconds -lt $capMs)
  $left
}
# Up to twelve processes for a failure line: pid, the Edge process type (the browser process has none), its parent's pid and whether
# that parent is still running, and when it started.
function Format-Procs($procs) {
  (@($procs | Select-Object -First 12 | % {
    $t = if ($_.CommandLine -match '--type=([\w-]+)') { $matches[1] } else { 'browser' }
    $up = if (Get-Process -Id $_.ParentProcessId -ErrorAction SilentlyContinue) { 'running' } else { 'gone' }
    "$($_.ProcessId) ($t, parent $($_.ParentProcessId) $up, started $($_.CreationDate.ToString('HH:mm:ss.fff')))"
  })) -join '; '
}

# The variables the file under test reads from its caller. Each is unset for the child, so it runs as a person's direct run: no suite
# flag (TILE_TEST_SUITE), no live-move opt-in, no agent marker, no seam.
$stripped = 'TILE_TEST_SUITE', 'TILE_HOME', 'TILE_SCREENS_FILE', 'TILE_DRY_START', 'TILE_TEST_ALLOW_LIVE', 'CLAUDECODE'
# Starts a test file directly, in its own powershell, with TEMP and TMP at $temp. The file's run folder, and so its Edge's profile, is
# under $temp. Output goes to files, not pipes, so an Edge that inherits a handle holds nothing back. The returned process is the powershell.
function Start-Direct([string]$file, [string]$temp, [string]$name) {
  [void](New-Item -ItemType Directory -Force $temp)
  $names = @('TEMP', 'TMP') + $stripped
  $keep = @{}; foreach ($n in $names) { $keep[$n] = [Environment]::GetEnvironmentVariable($n) }
  [Environment]::SetEnvironmentVariable('TEMP', $temp); [Environment]::SetEnvironmentVariable('TMP', $temp)
  foreach ($n in $stripped) { [Environment]::SetEnvironmentVariable($n, $null) }
  try {
    Start-Process powershell -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$file`"" -PassThru -WindowStyle Hidden `
      -RedirectStandardOutput (Join-Path $run "$name.out") -RedirectStandardError (Join-Path $run "$name.err")
  } finally { foreach ($n in $names) { [Environment]::SetEnvironmentVariable($n, $keep[$n]) } }
}

# ---------- Wiring: the scan ----------
# One file's facts from its parse tree: whether a '--headless' string is in its code (an Edge launch argument), and whether a top-level
# statement calls Enter-DirectRunJob before the first one. A comment is no node; a string or here-string that holds the text is one
# string whose value is more than the bare argument, so neither counts. A call inside a function or a block is not top-level.
function Get-Wiring($ast, [int]$errors) {
  $edges = @($ast.FindAll({ param($n) $n -is [Management.Automation.Language.StringConstantExpressionAst] -and $n.Value -ceq '--headless' }, $true) | Sort-Object { $_.Extent.StartOffset })
  $calls = @($ast.EndBlock.Statements | ? { $_ -is [Management.Automation.Language.PipelineAst] -and $_.PipelineElements[0] -is [Management.Automation.Language.CommandAst] -and $_.PipelineElements[0].GetCommandName() -ceq 'Enter-DirectRunJob' } | Sort-Object { $_.Extent.StartOffset })
  $edgeAt = if ($edges.Count) { $edges[0].Extent.StartOffset } else { -1 }
  $callAt = if ($calls.Count) { $calls[0].Extent.StartOffset } else { -1 }
  [pscustomobject]@{ Errors = $errors; Edge = ($edges.Count -gt 0); EdgeAt = $edgeAt; CallAt = $callAt; Wired = ($callAt -ge 0 -and $edgeAt -ge 0 -and $callAt -lt $edgeAt) }
}
function Read-WiringSource([string]$source) {
  $tokens = $null; $errs = $null
  Get-Wiring ([Management.Automation.Language.Parser]::ParseInput($source, [ref]$tokens, [ref]$errs)) @($errs).Count
}
function Read-WiringFile([string]$path) {
  $tokens = $null; $errs = $null
  Get-Wiring ([Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$errs)) @($errs).Count
}
# Synthetic sources. The call and the Edge argument are named in a comment, in a string that opens with '#', and in a here-string.
$srcNamed = @'
# Start-Process $edge '--headless'; Enter-DirectRunJob
Write-Output '# --headless'
Write-Output "// Enter-DirectRunJob /* not a call */"
$t = @"
Enter-DirectRunJob
--headless
"@
Write-Output "Don't"
'@
$srcQuote = @'
Write-Output "Don't"
Enter-DirectRunJob
$a = @('--headless', '--disable-gpu')
'@
$srcInFunction = @'
function Start-Direct { Enter-DirectRunJob }
$a = @('--headless', '--disable-gpu')
'@
$srcAfter = @'
$a = @('--headless', '--disable-gpu')
Enter-DirectRunJob
'@

$victim = $null; $victimTemp = $null
try {
  # ---------- Edge: a file run directly, killed hard ----------
  $edgeExe = @("${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe", "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe") | ? { Test-Path -LiteralPath $_ } | Select-Object -First 1
  if (-not $edgeExe) {
    'SKIP  direct-run: the Edge cases skipped (no Microsoft Edge)'
  } else {
    $victimTemp = Join-Path $run 'v'
    $victim = Start-Direct (Join-Path $PSScriptRoot 'bay.ps1') $victimTemp 'victim'
    # The file's Edge opens its DevTools port a few seconds in, and runs to the end of the file (about 25 s).
    $victimPort = Join-Path $victimTemp 'tile-windows-test-runs\*\edge\DevToolsActivePort'
    $guard = [Diagnostics.Stopwatch]::StartNew(); $guardMs = 240000; $settleMs = 90000
    $victimSeen = $false; $victimLive = $false; $killedAt = $null; $killClock = ''; $left = @(); $waited = $false
    while ($guard.ElapsedMilliseconds -lt $guardMs) {
      if ($null -eq $killedAt) {
        if (Test-Path -Path $victimPort) {
          # The kill: the powershell alone, with no tree and no teardown, as a harness's timeout or a Stop-Process -Force does it.
          $victimSeen = $true; $victimLive = -not $victim.HasExited
          if ($victimLive) { Stop-Process -Id $victim.Id -Force -ErrorAction SilentlyContinue }
          [void]$victim.WaitForExit(10000); $killedAt = $guard.ElapsedMilliseconds; $killClock = (Get-Date).ToString('HH:mm:ss.fff')
        } elseif ($victim.HasExited) { $killedAt = $guard.ElapsedMilliseconds }
      } else {
        $left = @(Get-FolderProcs $victimTemp 'msedge.exe')
        if (-not $left.Count -or ($guard.ElapsedMilliseconds - $killedAt) -ge $settleMs) { $waited = $true; break }
      }
      Start-Sleep -Milliseconds 100
    }
    Check 'scope: the killed file started its Edge (its DevTools port opened) before it ended' $victimSeen "the file ended or ran past the guard with no Edge of its own; output: $((Get-Content -LiteralPath (Join-Path $run 'victim.out') -ErrorAction SilentlyContinue | Select-Object -Last 3) -join ' | ')"
    Check 'scope: the killed file was still running when it was killed' $victimLive 'the file had already ended'
    Check 'scope: the kill was hard, so the file never tore down (its run folder is still there)' (Test-Path -Path (Join-Path $victimTemp 'tile-windows-test-runs\*')) "the file's run folder is gone, so its teardown ran"
    Check 'a test file run directly and killed hard leaves no Edge of its run' ($victimSeen -and $waited -and -not $left.Count) "$($left.Count) msedge process(es) of the killed run were still running $([int]($settleMs / 1000)) s after the kill at $killClock (file pid $($victim.Id)): $(Format-Procs $left); the file's own WARN and FAIL lines: $((@(Get-Content -LiteralPath (Join-Path $run 'victim.out') -ErrorAction SilentlyContinue | ? { $_ -match '^(WARN|FAIL)' } | Select-Object -First 3)) -join ' | ')"
  }

  # ---------- Wiring ----------
  $r = Read-WiringSource $srcNamed
  Check 'scan: a comment, a string and a here-string that name the call and the Edge argument are no call and no Edge' ($r.Errors -eq 0 -and -not $r.Edge -and $r.CallAt -lt 0) "errors $($r.Errors), edge $($r.Edge), call at $($r.CallAt)"
  $r = Read-WiringSource $srcQuote
  Check 'scan: a lone quote in text does not hide the call before the Edge argument' ($r.Errors -eq 0 -and $r.Edge -and $r.Wired) "errors $($r.Errors), edge at $($r.EdgeAt), call at $($r.CallAt)"
  $r = Read-WiringSource $srcInFunction
  Check 'scan: a call inside a function is not a top-level call' ($r.Errors -eq 0 -and $r.Edge -and $r.CallAt -lt 0 -and -not $r.Wired) "errors $($r.Errors), edge at $($r.EdgeAt), call at $($r.CallAt)"
  $r = Read-WiringSource $srcAfter
  Check 'scan: a call after the Edge argument is not wired' ($r.Errors -eq 0 -and $r.Edge -and $r.CallAt -ge 0 -and -not $r.Wired) "errors $($r.Errors), edge at $($r.EdgeAt), call at $($r.CallAt)"

  $files = @(Get-ChildItem -LiteralPath $PSScriptRoot -Filter '*.ps1' | ? { $_.FullName -ne $PSCommandPath })
  $facts = @($files | % { [pscustomobject]@{ Name = $_.Name; W = (Read-WiringFile $_.FullName) } })
  $starts = @($facts | ? { $_.W.Edge })
  Check 'scope: the scan finds the test files that start headless Edge, and reads each without a parse error' ($starts.Count -ge 6 -and @($facts | ? { $_.W.Errors }).Count -eq 0) "found $($starts.Count) Edge files; parse errors in: $((@($facts | ? { $_.W.Errors } | % { $_.Name })) -join ' ')"
  foreach ($f in $starts) {
    Check "$($f.Name) enters its own job object (Enter-DirectRunJob, top level) before it starts headless Edge" $f.W.Wired "$(if ($f.W.CallAt -lt 0) { 'no top-level Enter-DirectRunJob' } else { "the call is at offset $($f.W.CallAt), after the Edge argument at $($f.W.EdgeAt)" })"
  }
} finally {
  # Teardown: stop what a red run leaves, by folder only (another lane's Edge is never named here), then remove the run folder.
  if ($victimTemp) {
    foreach ($p in @(Get-FolderProcs $victimTemp)) { Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue }
    [void](Wait-EdgeGone $victimTemp 10000)
  }
  # A process that has just ended can still hold a file in the run folder for a moment, so the folder is removed after it has gone.
  try { Remove-RunFolder $run } catch { $script:fail++; "FAIL  teardown could not remove the run folder  $($_.Exception.Message)" }
}
if ($script:fail) { "$($script:fail) check(s) failed."; exit 1 } else { 'All direct-run checks passed.'; exit 0 }
