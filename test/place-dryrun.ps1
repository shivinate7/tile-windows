# Checks for the -Place -DryRun check in test\run.ps1 (section 2). That check read the live desktop twice, the snapshot and then the dry run
# of it, so a window that left the desktop between the two reads failed it on a correct tree ("Placed 24 of 25 (1 unmatched)"). The two
# reads and the verdict are test\place-step.ps1's (Read-Desktop, Test-PlaceDryRun), which run.ps1 calls, so this file runs what the check runs.
# Run alone: powershell -NoProfile -ExecutionPolicy Bypass -File test\place-dryrun.ps1
#
# The file starts two throwaway windows of its own (a minimized Windows Forms window with a GUID title, as run.ps1 starts for its title
# check), reads the snapshot while the first is open, changes the desktop, and then runs the dry run on that snapshot. It moves no window and
# closes only its own.
# Cases (red = fails on 17a4bed for the named cause, green = a control that holds there and must keep holding):
#   Scope (green): the snapshot lists window A; window B, opened after the snapshot, is on the desktop when the dry run starts; and once A is
#     closed a fresh read no longer lists A. Without these the cases below could not say what they probe.
#   Controls (green): the dry run matches all windows when the desktop is unchanged, and when a window opens between the two reads (the
#     engine ignores a window the snapshot did not list).
#   Closed window (red): the dry run matches all windows when a window closes between the two reads. The engine finds a window by its id
#     first and then by its title, so a closed window is the one change that leaves a snapshot window unmatched. Old code: the dry run reads
#     the desktop again and says "Placed N-1 of N (1 unmatched)".
# A title change between the reads is not probed: tile.ps1 matches by id before the title, so a retitled window should still match, but that
# is read from the code and unmeasured here.
# Copied on purpose: the throwaway window below repeats the one run.ps1 starts for its title check. run.ps1 runs its checks at the top level,
# so it cannot be dot-sourced. The sweep of old run folders is stack-lock.ps1's.
param()
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
$tile = Join-Path $root 'tile.ps1'
$script:fail = 0
function Check($name, $ok, $detail = '') { if ($ok) { "PASS  $name" } else { $script:fail++; "FAIL  $name  $detail" } }

. (Join-Path $PSScriptRoot 'run-folders.ps1')
. (Join-Path $PSScriptRoot 'place-step.ps1')
# Run folder (test-temp-standard): <TEMP>\tile-windows-test-runs\<pid>-<UUID>, removed at the end.
$runRoot = Join-Path $env:TEMP 'tile-windows-test-runs'
New-Item -ItemType Directory -Force $runRoot | Out-Null
$runDir = Join-Path $runRoot ("$PID-" + [guid]::NewGuid().ToString())
New-Item -ItemType Directory $runDir | Out-Null

# Set or strip each variable the engine reads, and point the profile into the run folder. TILE_TEST_SUITE is on, as in the suite, so a live
# move would be refused; none of the calls here moves a window.
$saved = @{ USERPROFILE = $env:USERPROFILE; APPDATA = $env:APPDATA; TILE_HOME = $env:TILE_HOME; TILE_SCREENS_FILE = $env:TILE_SCREENS_FILE; TILE_TEST_ALLOW_LIVE = $env:TILE_TEST_ALLOW_LIVE; CLAUDECODE = $env:CLAUDECODE; TILE_TEST_SUITE = $env:TILE_TEST_SUITE; TILE_TEST_TITLE = $env:TILE_TEST_TITLE }
$prof = Join-Path $runDir 'profile'; New-Item -ItemType Directory -Force (Join-Path $prof 'AppData\Roaming') | Out-Null
$env:USERPROFILE = $prof; $env:APPDATA = Join-Path $prof 'AppData\Roaming'
$env:TILE_HOME = $null; $env:TILE_SCREENS_FILE = $null; $env:TILE_TEST_ALLOW_LIVE = $null; $env:CLAUDECODE = $null; $env:TILE_TEST_SUITE = '1'
$forms = @()   # every window process this file starts; the finally block stops what is still running

# A minimized window with the title $title. Returns its process once the window carries the title. A window that has not opened in 60 s
# stops the file: that cap is a hang guard, well above the seconds a window takes, and no verdict depends on it.
$formFile = Join-Path $runDir 'form.ps1'
Set-Content -LiteralPath $formFile -Encoding ASCII -Value 'Add-Type -AssemblyName System.Windows.Forms; $f = New-Object Windows.Forms.Form; $f.Text = $env:TILE_TEST_TITLE; $f.WindowState = "Minimized"; [Windows.Forms.Application]::Run($f)'
function Start-Throwaway([string]$title) {
  $env:TILE_TEST_TITLE = $title
  $p = Start-Process powershell -PassThru -WindowStyle Hidden -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$formFile`""
  $script:forms += $p
  $t0 = Get-Date
  while ((Get-Process -Id $p.Id).MainWindowTitle -ne $title) {
    if (((Get-Date) - $t0).TotalSeconds -gt 60) { throw "the throwaway window '$title' did not open in 60 s" }
    Start-Sleep -Milliseconds 200
  }
  $p
}
# True when the snapshot text lists a window with this title.
function Test-Listed([string]$snapText, [string]$title) { @(($snapText | ConvertFrom-Json).windows | ? { $_.title -ceq $title }).Count -eq 1 }

try {
  $guid = [guid]::NewGuid().ToString()
  $titleA = "tile-test-place-A-$guid"; $titleB = "tile-test-place-B-$guid"
  $snapFile = Join-Path $runDir 'snap.json'
  $a = Start-Throwaway $titleA
  # The first read, with A open.
  $s1 = Read-Desktop $tile
  $scopeA = Test-Listed $s1 $titleA
  Check 'scope: the snapshot lists the throwaway window A' $scopeA "the snapshot has no window titled '$titleA'"

  # Control: nothing changes between the two reads.
  if ($scopeA) {
    $r = Test-PlaceDryRun $tile $s1 $snapFile
    Check 'control: -Place -DryRun matches all windows when the desktop is unchanged' $r.Ok "the dry run said: '$($r.Last)'"
  }

  # Control: a window opens between the two reads.
  $b = Start-Throwaway $titleB
  $scopeB = Test-Listed (Read-Desktop $tile) $titleB
  Check 'scope: window B, opened after the snapshot, is on the desktop at the dry run' $scopeB "a fresh read has no window titled '$titleB'"
  if ($scopeA -and $scopeB) {
    $r = Test-PlaceDryRun $tile $s1 $snapFile
    Check 'control: -Place -DryRun matches all windows when a window opens between the reads' $r.Ok "window '$titleB' opened between the reads; the dry run said: '$($r.Last)'"
  }

  # The subject: A closes between the two reads. A capped wait on its exit, so the window is gone before the dry run starts.
  $a.Kill()
  $exited = $a.WaitForExit(15000)
  $gone = $exited -and -not (Test-Listed (Read-Desktop $tile) $titleA)
  Check 'scope: once window A is closed a fresh read no longer lists it' $gone "window '$titleA' is still on the desktop (process exited: $exited)"
  if ($scopeA -and $gone) {
    $r = Test-PlaceDryRun $tile $s1 $snapFile
    Check 'a window that closes between the two reads does not fail -Place -DryRun' $r.Ok "window '$titleA' closed between the reads; the dry run said: '$($r.Last)'"
  }
} catch {
  $script:fail++; "FAIL  run stopped: $_"
} finally {
  foreach ($p in $forms) { if (-not $p.HasExited) { $p.Kill(); [void]$p.WaitForExit(15000) } }
  foreach ($k in $saved.Keys) { if ($null -eq $saved[$k]) { Remove-Item "env:$k" -ErrorAction SilentlyContinue } else { Set-Item "env:$k" $saved[$k] } }
  try { Remove-RunFolder $runDir } catch { Remove-Item -LiteralPath $runDir -Recurse -Force -ErrorAction SilentlyContinue }
}
if ($script:fail) { "$($script:fail) check(s) failed."; exit 1 } else { 'All place-dryrun checks passed.'; exit 0 }
