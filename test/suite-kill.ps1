# Checks how test\run.ps1 collects its child files. Three scenarios, each run by a host powershell that takes run.ps1's functions and
# its loop from its file, over fake children made in this run's folder:
#   hang:   a child still running at its cap is stopped with its whole process tree, its FAIL line prints, and the child after it is
#           read and counted; no process of the stopped child survives.
#   held:   a child exits while a grandchild still holds its output; the child after it is still read and counted, and the grandchild
#           is stopped.
#   parent: the run stops before its collection loop; the children it started are stopped and read in the finally.
# The guard (60 s) sits well above a run (about 20 s). test\run.ps1 runs this file in a child powershell and counts its FAIL lines.
# Run alone: powershell -NoProfile -ExecutionPolicy Bypass -File test\suite-kill.ps1
param([string]$Scenario = '', [string]$Folder = '')
$ErrorActionPreference = 'Stop'
$utf8 = New-Object Text.UTF8Encoding $false
$script:fail = 0
# A failure's detail goes on one line, so a host's output shows whole in it.
function Check($name, $ok, $detail = '') { if ($ok) { "PASS  $name" } else { $script:fail++; "FAIL  $name  $(($detail -replace "`r?`n", ' | ').Trim())" } }
# A text file's contents, read while another process may still hold it open (a child that was not stopped can).
function Read-Text([string]$path) {
  if (-not (Test-Path -LiteralPath $path)) { return '' }
  $fs = [IO.File]::Open($path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
  try { $ms = New-Object IO.MemoryStream; $fs.CopyTo($ms); [Text.Encoding]::Default.GetString($ms.ToArray()) } finally { $fs.Dispose() }
}
if ($Scenario) {
  # Host mode: run.ps1's own functions and its one collection loop (the foreach over $suites that waits on each child), then the
  # loop runs over this scenario's fake children. The functions are written to a file in the scenario folder and dot-sourced from
  # there, so $PSScriptRoot in Start-Suite is that folder, where the fake children are. A run.ps1 with no such loop prints LOOPS 0.
  $tmp = $Folder
  $suiteCapMs = 15000
  $tokens = $null; $errs = $null
  $ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot 'run.ps1'), [ref]$tokens, [ref]$errs)
  $fnText = @($ast.FindAll({ param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] }, $true) | % { $_.Extent.Text })
  $lib = Join-Path $Folder 'run-functions.ps1'
  [IO.File]::WriteAllText($lib, ($fnText -join "`r`n"), $utf8)
  . $lib
  # The collection loop waits on each child. The parent scenario runs the other loop over $suites: the one in the finally, which
  # stops each child and prints what it left.
  $waits = $Scenario -ne 'parent'
  $loops = @($ast.FindAll({ param($n) $n -is [Management.Automation.Language.ForEachStatementAst] -and $n.Condition.Extent.Text -eq '$suites' -and (($n.Extent.Text -match 'WaitForExit') -eq $waits) }, $true))
  "LOOPS $($loops.Count)"
  if ($loops.Count -ne 1) { exit 1 }
  switch ($Scenario) {
    'hang' { $suites = @((Start-Suite 'hang' 'hang-child.ps1'), (Start-Suite 'normal' 'normal-child.ps1')) }
    'held' { $suites = @((Start-Suite 'holder' 'holder-child.ps1'), (Start-Suite 'normal' 'normal-child.ps1')) }
    'parent' { $suites = @(Start-Suite 'normal' 'normal-child.ps1'); [void]$suites[0].Proc.WaitForExit(30000) }
  }
  $script:fail = 0
  . ([scriptblock]::Create($loops[0].Extent.Text))
  "COUNT $script:fail"
  exit 0
}

# Parent mode: one run folder for this case (test-temp-standard); stack-lock.ps1 sweeps the old ones. Teardown stops what the
# children left and removes the folder.
. (Join-Path $PSScriptRoot 'run-folders.ps1')
$runsRoot = Join-Path $env:TEMP 'tile-windows-test-runs'
[void](New-Item -ItemType Directory -Force $runsRoot)
$run = Join-Path $runsRoot ("$PID-" + [guid]::NewGuid().ToString()); New-Item -ItemType Directory $run | Out-Null

# The pid a fake child wrote, or 0 when it wrote none.
function Read-Pid([string]$file) { $id = 0; if ([int]::TryParse((Read-Text $file).Trim(), [ref]$id)) { $id } else { 0 } }
# Whether a process this case started is still running, once it has had 5 s to end. A process that is gone is not alive.
function Test-Alive([int]$id) {
  $p = Get-Process -Id $id -ErrorAction SilentlyContinue
  if (-not $p) { return $false }
  return -not $p.WaitForExit(5000)
}
# Runs one scenario's host, in this run's folder, and waits up to the guard. A host still running at the guard is stopped alone, so
# what its children left running shows as it is.
function Start-Host([string]$scenario, [string]$dir, [int]$guardMs) {
  $env:SUITE_KILL_DIR = $dir
  try {
    $h = Start-Process powershell -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"", '-Scenario', $scenario, '-Folder', "`"$dir`"" -PassThru -WindowStyle Hidden -RedirectStandardOutput (Join-Path $dir 'host.out') -RedirectStandardError (Join-Path $dir 'host.err')
  } finally { Remove-Item Env:SUITE_KILL_DIR -ErrorAction SilentlyContinue }
  $done = $h.WaitForExit($guardMs)
  if (-not $done) { Stop-Process -Id $h.Id -Force -ErrorAction SilentlyContinue; [void]$h.WaitForExit(5000) }
  [pscustomobject]@{ Done = $done; Out = (Read-Text (Join-Path $dir 'host.out')) }
}
$normalChild = @'
Write-Output 'PASS  normal child is read'
Write-Output 'FAIL  normal child has one failing check'
'@
$hangChild = @'
Set-Content -LiteralPath (Join-Path $env:SUITE_KILL_DIR 'hang.pid') -Value $PID -Encoding ASCII
Start-Sleep -Seconds 600
'@
# The holder exits at once, but the grandchild it starts inherits its output file and keeps running.
$holderChild = @'
$psi = New-Object Diagnostics.ProcessStartInfo 'powershell', '-NoProfile -Command "Start-Sleep -Seconds 600"'
$psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
$g = [Diagnostics.Process]::Start($psi)
Set-Content -LiteralPath (Join-Path $env:SUITE_KILL_DIR 'grand.pid') -Value $g.Id -Encoding ASCII
Write-Output 'PASS  holder child is read'
'@

try {
  # Hang: the child at its cap is stopped, the child after it is read and counted, and no process of the stopped child survives.
  $hd = Join-Path $run 'hang'; New-Item -ItemType Directory $hd | Out-Null
  [IO.File]::WriteAllText((Join-Path $hd 'hang-child.ps1'), $hangChild, $utf8)
  [IO.File]::WriteAllText((Join-Path $hd 'normal-child.ps1'), $normalChild, $utf8)
  $hang = Start-Host 'hang' $hd 60000
  Check 'run.ps1 has one collection loop over its children (hang)' ($hang.Out -match '(?m)^LOOPS 1')
  $hangPid = Read-Pid (Join-Path $hd 'hang.pid')
  Check 'the hung child started and wrote its pid' ($hangPid -gt 0) "pid file: $(Read-Text (Join-Path $hd 'hang.pid'))"
  Check 'a child still running at its cap is stopped, so the collection finishes inside the guard' $hang.Done 'the host ran past 60 s: the loop waited on a child past its cap'
  Check 'the stopped child gets a FAIL line' ($hang.Out -match '(?m)^FAIL  hang ') "host output: $($hang.Out)"
  Check 'the child after the stopped one is read and printed' ($hang.Out -match 'PASS  normal child is read') "host output: $($hang.Out)"
  Check 'the stopped child and the child after it are counted' ($hang.Out -match '(?m)^COUNT 2') "host output: $($hang.Out)"
  Check 'no process of the stopped child survives its stop' (-not (Test-Alive $hangPid)) "pid $hangPid is still running"

  # Held: a child exits, but a grandchild still holds its output. The child is read, the child after it is read and counted, and the
  # grandchild is stopped with the child.
  $hd2 = Join-Path $run 'held'; New-Item -ItemType Directory $hd2 | Out-Null
  [IO.File]::WriteAllText((Join-Path $hd2 'holder-child.ps1'), $holderChild, $utf8)
  [IO.File]::WriteAllText((Join-Path $hd2 'normal-child.ps1'), $normalChild, $utf8)
  $held = Start-Host 'held' $hd2 60000
  Check 'run.ps1 has one collection loop over its children (held)' ($held.Out -match '(?m)^LOOPS 1')
  $grandPid = Read-Pid (Join-Path $hd2 'grand.pid')
  Check 'the holder child started a grandchild and wrote its pid' ($grandPid -gt 0) "pid file: $(Read-Text (Join-Path $hd2 'grand.pid'))"
  Check 'a child whose output a grandchild holds is read' ($held.Out -match 'PASS  holder child is read') "host output: $($held.Out)"
  Check 'the child after it is read when a grandchild held the earlier output' ($held.Out -match 'PASS  normal child is read') "host output: $($held.Out)"
  Check 'the child after it is counted' ($held.Out -match '(?m)^COUNT 1') "host output: $($held.Out)"
  Check 'the grandchild that held the output is stopped with its child' (-not (Test-Alive $grandPid)) "pid $grandPid is still running"

  # Parent throw: the run stops before its collection loop. The children it started are stopped and read in the finally, so their
  # output is not dropped.
  $pd = Join-Path $run 'parent'; New-Item -ItemType Directory $pd | Out-Null
  [IO.File]::WriteAllText((Join-Path $pd 'normal-child.ps1'), $normalChild, $utf8)
  $par = Start-Host 'parent' $pd 60000
  Check 'run.ps1 has one finally loop over its children (parent)' ($par.Out -match '(?m)^LOOPS 1') "host output: $($par.Out)"
  Check 'a child started before a throw is read and printed' ($par.Out -match 'PASS  normal child is read') "host output: $($par.Out)"
  Check 'a child started before a throw is counted' ($par.Out -match '(?m)^COUNT 1') "host output: $($par.Out)"
} finally {
  # Teardown: stop the fake children this case started, if they are still running (a red run leaves them), then remove the run folder.
  # Each is stopped only when its command line is one of the fake children's, so a pid reused by another process is left alone.
  foreach ($f in (Join-Path $run 'hang\hang.pid'), (Join-Path $run 'held\grand.pid')) {
    $id = Read-Pid $f
    if ($id -le 0) { continue }
    $cim = Get-CimInstance Win32_Process -Filter "ProcessId=$id" -ErrorAction SilentlyContinue
    $proc = if ($cim -and $cim.CommandLine -match 'hang-child\.ps1|Start-Sleep -Seconds 600') { Get-Process -Id $id -ErrorAction SilentlyContinue }
    if ($proc) { Stop-Process -Id $id -Force -ErrorAction SilentlyContinue; [void]$proc.WaitForExit(5000) }
  }
  # A process that has just ended can still hold a file in the run folder for a moment, so the folder is removed after it has gone.
  try { Remove-RunFolder $run } catch { $script:fail++; "FAIL  teardown could not remove the run folder  $($_.Exception.Message)" }
}
if ($script:fail) { "$($script:fail) check(s) failed."; exit 1 }
