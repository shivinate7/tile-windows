# Checks for install.ps1's swap when the installed app folder is busy, for its tray.pid wait, and for uninstall.ps1's tray.pid
# removal. The swap renames the old app aside (the Rename-Item retry loop in install.ps1), and a process whose working directory is
# that folder makes the rename fail: "being used by another process". Each case has its own scope:
#   Frees up (case 1): a holder keeps the app folder busy and lets go 8 s after the install starts. The install waits the holder
#     out, swaps the new app in, and leaves no staging or old folder.
#   Never frees up (case 2, a green control): the holder never lets go. The install gives up in bounded time, exits non-zero,
#     leaves the old app in place, and leaves no staging folder.
#   Stale tray.pid (case 3): tray.pid names a powershell this user cannot wait on (its DACL refuses WaitForExit, which is how
#     install.ps1 waits for tray.pid). The install must still succeed: exit 0, the new app in place, no staging folder left.
#   Live tray.pid (case 4, a green control): tray.pid names a holder that lets go 24 s after the install starts. The install waits
#     for it. A version without that wait fails this case (the scratch mutant shows it). The arithmetic is at the case.
#   Uninstall (case 5): uninstall.ps1 without -Purge removes tray.pid.
#   Name collision (case 6): app.old-<install pid> already exists, so the rename fails for a reason that is not a lock. The install
#     must fail with its own error, not the "in use" message that follows its 15 s retry. Fast failure has no clock check here;
#     the missing "in use" text stands in for it.
# Scope before subject (P7): each case checks that the holder is up and that a rename of the folder is refused before it reads
# the install's result. Each check names one cause.
# Why 8 s: on the dev machine install.ps1 reaches its rename about 4 s after it starts (most of that is dot-sourcing tray.ps1 -Lib),
# so the folder must still be held then. A retry that keeps trying past that point gets through when the holder lets go.
# Run alone: powershell -NoProfile -ExecutionPolicy Bypass -File test\install-swap.ps1
# test\run.ps1 dot-sources this file in a child scope, so the variables it makes stay there.

$standalone = -not (Get-Command Check -ErrorAction SilentlyContinue)
if ($standalone) {
  $ErrorActionPreference = 'Stop'
  $root = Split-Path $PSScriptRoot
  $script:fail = 0
  function Check($name, $ok, $detail = '') { if ($ok) { "PASS  $name" } else { $script:fail++; "FAIL  $name  $detail" } }
  # A child powershell with its own profile: USERPROFILE and APPDATA both point at $prof. Its stdout and stderr are redirected.
  function Start-Child($prof, $argLine, $extra = @{}) {
    $psi = New-Object Diagnostics.ProcessStartInfo 'powershell', "-NoProfile -ExecutionPolicy Bypass $argLine"
    $psi.UseShellExecute = $false; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true; $psi.CreateNoWindow = $true
    $psi.EnvironmentVariables['USERPROFILE'] = $prof; $psi.EnvironmentVariables['APPDATA'] = Join-Path $prof 'AppData\Roaming'
    foreach ($k in $extra.Keys) { $psi.EnvironmentVariables[$k] = $extra[$k] }
    [Diagnostics.Process]::Start($psi)
  }
}

# One run folder for this file, under the temp root the suite uses (test-temp-standard); stack-lock.ps1 sweeps old ones.
$run = Join-Path (Join-Path $env:TEMP 'tile-windows-test-runs') ("$PID-" + [guid]::NewGuid().ToString())
New-Item -ItemType Directory -Force $run | Out-Null
$marker = [DateTime]::new(2001, 1, 1, 0, 0, 0, [DateTimeKind]::Utc)  # a fixed old time for the old tile.ps1: a swapped-in copy has another
$holdMs = 8000
$holdTrayMs = 24000  # case 4: the holder named by tray.pid lets go this long after the install starts (see that case)
$started = New-Object Collections.ArrayList  # every process this file starts; the finally kills what still runs
$holders = New-Object Collections.ArrayList
$savedEnv = @{ USERPROFILE = $env:USERPROFILE; APPDATA = $env:APPDATA }
$env:USERPROFILE = Join-Path $run 'suite-home'; $env:APPDATA = Join-Path $env:USERPROFILE 'AppData\Roaming'

# A fresh temp profile for one case.
function Make-Profile([string]$name) { $p = Join-Path $run $name; New-Item -ItemType Directory -Force (Join-Path $p 'AppData\Roaming') | Out-Null; $p }

# One install.ps1 run in a child powershell, into the profile given, with no registry writes.
function Start-Install([string]$prof, [string]$flags) {
  $p = Start-Child $prof "-File `"$(Join-Path $root 'install.ps1')`" $flags" @{ TILE_SOURCE = $root; TILE_NO_REGISTRY = '1' }
  [void]$started.Add($p)
  [pscustomobject]@{ Proc = $p; Out = $p.StandardOutput.ReadToEndAsync(); Err = $p.StandardError.ReadToEndAsync() }
}

# Waits up to $ms for a child. A child still running then is killed, so nothing outlives the case. True when it exited.
function Wait-Exit($proc, [int]$ms) {
  if ($proc.WaitForExit($ms)) { return $true }
  try { $proc.Kill() } catch { }
  return $false
}

# A holder: a child powershell whose working directory is $app, so it holds the folder until its Release event is set.
# Up is true once the holder has started and set its Ready event.
function New-Holder([string]$app, [string]$tag) {
  $name = "tile-swap-$PID-$tag-" + [guid]::NewGuid().ToString('N')
  $ready = New-Object Threading.EventWaitHandle($false, [Threading.EventResetMode]::ManualReset, "$name-ready")
  $release = New-Object Threading.EventWaitHandle($false, [Threading.EventResetMode]::ManualReset, "$name-release")
  $file = Join-Path $run "hold-$tag.ps1"
  [IO.File]::WriteAllText($file, "`$r = [Threading.EventWaitHandle]::OpenExisting('$name-ready'); `$l = [Threading.EventWaitHandle]::OpenExisting('$name-release'); [void]`$r.Set(); [void]`$l.WaitOne(120000)", [Text.Encoding]::ASCII)
  $psi = New-Object Diagnostics.ProcessStartInfo 'powershell', "-NoProfile -ExecutionPolicy Bypass -File `"$file`""
  $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true; $psi.WorkingDirectory = $app
  $p = [Diagnostics.Process]::Start($psi)
  [void]$started.Add($p)
  $h = [pscustomobject]@{ Proc = $p; Ready = $ready; Release = $release; Up = $ready.WaitOne(20000) }
  [void]$holders.Add($h)
  $h
}

# True when a rename of the folder is refused, as it is while a process has the folder as its working directory.
# A rename that goes through is undone, so the folder keeps its name.
function Test-Held([string]$dir) {
  $aside = "$dir.probe"
  try { Rename-Item -LiteralPath $dir -NewName (Split-Path $aside -Leaf) -ErrorAction Stop } catch { return $true }
  Rename-Item -LiteralPath $aside -NewName (Split-Path $dir -Leaf)
  $false
}

# The app folder's file count, tile.ps1's write time (null when there is none), and the app.* folders left beside it.
function Get-AppState([string]$prof) {
  $app = Join-Path $prof '.tile-windows\app'; $tile = Join-Path $app 'tile.ps1'
  $count = @(Get-ChildItem -LiteralPath $app -ErrorAction SilentlyContinue).Count
  $stamp = $null
  if (Test-Path -LiteralPath $tile) { $stamp = (Get-Item -LiteralPath $tile).LastWriteTimeUtc }
  $staging = @(Get-ChildItem -LiteralPath (Join-Path $prof '.tile-windows') -Force -ErrorAction SilentlyContinue | Where-Object { $_.Name -like 'app.*' }).Count
  [pscustomobject]@{ Count = $count; Stamp = $stamp; Staging = $staging }
}

# A first install into a fresh profile: the old app the swap replaces. Its tile.ps1 gets the fixed old time.
function New-OldApp([string]$prof) {
  $i = Start-Install $prof '-NoStartup -NoLaunch'
  $exited = Wait-Exit $i.Proc 120000
  $st = Get-AppState $prof
  $ok = $exited -and $i.Proc.ExitCode -eq 0 -and $st.Count -eq 9
  if ($ok) { (Get-Item -LiteralPath (Join-Path $prof '.tile-windows\app\tile.ps1')).LastWriteTimeUtc = $marker }
  [pscustomobject]@{ Ok = $ok; Code = $i.Proc.ExitCode; Err = $i.Err }
}

# Case 3 needs a process that Get-Process names but WaitForExit cannot open. This sets a DACL that gives SYSTEM only, so this
# user gets no SYNCHRONIZE on a new handle. The owner keeps READ_CONTROL and WRITE_DAC, so no admin rights are needed.
if (-not ('TileSwapDacl' -as [type])) {
  Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
public static class TileSwapDacl {
  [DllImport("advapi32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
  static extern bool ConvertStringSecurityDescriptorToSecurityDescriptorW(string sddl, uint rev, out IntPtr sd, out uint size);
  [DllImport("advapi32.dll", SetLastError = true)]
  static extern bool SetKernelObjectSecurity(IntPtr handle, uint info, IntPtr sd);
  public static void SetDacl(IntPtr handle, string sddl) {
    IntPtr sd; uint size;
    if (!ConvertStringSecurityDescriptorToSecurityDescriptorW(sddl, 1, out sd, out size)) throw new Win32Exception(Marshal.GetLastWin32Error());
    if (!SetKernelObjectSecurity(handle, 4, sd)) throw new Win32Exception(Marshal.GetLastWin32Error());
  }
}
'@
}

# A child powershell that sleeps, with the DACL above. It is in the run folder, so it holds nothing else. Returns the process.
function Start-Unwaitable {
  $psi = New-Object Diagnostics.ProcessStartInfo 'powershell', '-NoProfile -ExecutionPolicy Bypass -Command Start-Sleep -Seconds 120'
  $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true; $psi.WorkingDirectory = $run
  $p = [Diagnostics.Process]::Start($psi)
  [void]$started.Add($p)
  [TileSwapDacl]::SetDacl($p.Handle, 'D:(A;;GA;;;SY)')
  $p
}

# True when Get-Process names the pid powershell and WaitForExit is refused: the case 3 setup needs exactly that.
function Test-Unwaitable([int]$id) {
  $tp = Get-Process -Id $id -ErrorAction SilentlyContinue
  if (-not $tp -or $tp.ProcessName -notmatch '^(powershell|pwsh)$') { return $false }
  try { [void]$tp.WaitForExit(0); return $false } catch { return $true }
}

try {
  Check 'swap: the cases run in their own run folder, not the real profile' ($env:USERPROFILE.StartsWith($run))

  # ---- Case 1: the folder frees up 8 s after the install starts. ----
  $p1 = Make-Profile 'frees'
  $old1 = New-OldApp $p1
  Check 'setup (frees up): a first install puts the old app in place (nine files)' $old1.Ok "first install exit $($old1.Code): $(@($old1.Err.Result.Trim() -split "`r?`n")[0])"
  if ($old1.Ok) {
    $h1 = New-Holder (Join-Path $p1 '.tile-windows\app') 'frees'
    Check 'holder (frees up): its process is up and has set its ready event' $h1.Up 'the holder did not start'
    if ($h1.Up) {
      $held1 = Test-Held (Join-Path $p1 '.tile-windows\app')
      Check 'holder (frees up): a rename of the app folder is refused while the holder holds it' $held1 'the holder does not hold the folder: the rename went through'
      if ($held1) {
        $i1 = Start-Install $p1 '-NoStartup -NoLaunch'
        if (-not $i1.Proc.WaitForExit($holdMs)) { [void]$h1.Release.Set() }  # the folder frees up 8 s after the install starts
        $exited1 = Wait-Exit $i1.Proc 60000
        [void]$h1.Release.Set()
        Check 'install waits out the busy app folder and exits 0 once it frees up' ($exited1 -and $i1.Proc.ExitCode -eq 0) "exit $($i1.Proc.ExitCode): $(@($i1.Err.Result.Trim() -split "`r?`n")[0])"
        $st1 = Get-AppState $p1
        Check 'the new app replaces the old one: tile.ps1 is a new copy and the app has nine files' ($st1.Count -eq 9 -and $null -ne $st1.Stamp -and $st1.Stamp -ne $marker) "$($st1.Count) files, tile.ps1 time $($st1.Stamp)"
        Check 'no staging or old folder is left after the swap' ($st1.Staging -eq 0) "$($st1.Staging) app.* folder(s) left beside the app"
      }
    }
  }

  # ---- Case 2 (green control): the folder never frees up. ----
  $p2 = Make-Profile 'stuck'
  $old2 = New-OldApp $p2
  Check 'setup (never frees up): a first install puts the old app in place (nine files)' $old2.Ok "first install exit $($old2.Code): $(@($old2.Err.Result.Trim() -split "`r?`n")[0])"
  if ($old2.Ok) {
    $h2 = New-Holder (Join-Path $p2 '.tile-windows\app') 'stuck'
    Check 'holder (never frees up): its process is up and has set its ready event' $h2.Up 'the holder did not start'
    if ($h2.Up) {
      $held2 = Test-Held (Join-Path $p2 '.tile-windows\app')
      Check 'holder (never frees up): a rename of the app folder is refused while the holder holds it' $held2 'the holder does not hold the folder: the rename went through'
      if ($held2) {
        $i2 = Start-Install $p2 '-NoStartup -NoLaunch'
        $exited2 = Wait-Exit $i2.Proc 60000  # the holder keeps the folder for the whole run
        [void]$h2.Release.Set()
        Check 'install gives up in bounded time when the app folder never frees up' $exited2 'the install was still running after 60 s, so it was killed'
        Check 'install exits non-zero when the app folder never frees up' ($exited2 -and $i2.Proc.ExitCode -ne 0) "exit $($i2.Proc.ExitCode)"
        $st2 = Get-AppState $p2
        Check 'the old app stays in place when the app folder never frees up' ($st2.Count -eq 9 -and $st2.Stamp -eq $marker) "$($st2.Count) files, tile.ps1 time $($st2.Stamp)"
        Check 'no staging or old folder is left after the failed install' ($st2.Staging -eq 0) "$($st2.Staging) app.* folder(s) left beside the app"
      }
    }
  }
  # ---- Case 3: tray.pid names a powershell this user cannot wait on (a stale pid). The install must still succeed. ----
  $p3 = Make-Profile 'stale'
  $old3 = New-OldApp $p3
  Check 'setup (stale tray.pid): a first install puts the old app in place (nine files)' $old3.Ok "first install exit $($old3.Code): $(@($old3.Err.Result.Trim() -split "`r?`n")[0])"
  if ($old3.Ok) {
    $stale = Start-Unwaitable
    Check 'stale tray.pid (scope): the pid is a powershell whose WaitForExit is refused' (Test-Unwaitable $stale.Id) "pid $($stale.Id) can be waited on, so the case would not test a refused wait"
    [IO.File]::WriteAllText((Join-Path $p3 '.tile-windows\tray.pid'), "$($stale.Id)", [Text.Encoding]::ASCII)
    $i3 = Start-Install $p3 '-NoStartup -NoLaunch'
    $exited3 = Wait-Exit $i3.Proc 60000
    try { $stale.Kill() } catch { }
    Check 'install exits 0 when tray.pid names a process it cannot wait on' ($exited3 -and $i3.Proc.ExitCode -eq 0) "exit $($i3.Proc.ExitCode): $(@($i3.Err.Result.Trim() -split "`r?`n")[0])"
    $st3 = Get-AppState $p3
    Check 'the new app replaces the old one when tray.pid is stale' ($st3.Count -eq 9 -and $null -ne $st3.Stamp -and $st3.Stamp -ne $marker) "$($st3.Count) files, tile.ps1 time $($st3.Stamp)"
    Check 'no staging or old folder is left when tray.pid is stale' ($st3.Staging -eq 0) "$($st3.Staging) app.* folder(s) left beside the app"
  }

  # ---- Case 4 (green control): tray.pid names a holder that lets go 24 s after the install starts. ----
  # The install waits up to 10 s on tray.pid, then retries the rename for 15 s. Without that wait the retry starts near 4 s and gives
  # up near 19 s, so a 24 s holder fails. With the wait, the retry starts near 14 s and gets through by about 29 s.
  $p4 = Make-Profile 'pidwait'
  $old4 = New-OldApp $p4
  Check 'setup (live tray.pid): a first install puts the old app in place (nine files)' $old4.Ok "first install exit $($old4.Code): $(@($old4.Err.Result.Trim() -split "`r?`n")[0])"
  if ($old4.Ok) {
    $h4 = New-Holder (Join-Path $p4 '.tile-windows\app') 'pidwait'
    Check 'holder (live tray.pid): its process is up and has set its ready event' $h4.Up 'the holder did not start'
    if ($h4.Up) {
      [IO.File]::WriteAllText((Join-Path $p4 '.tile-windows\tray.pid'), "$($h4.Proc.Id)", [Text.Encoding]::ASCII)
      $held4 = Test-Held (Join-Path $p4 '.tile-windows\app')
      Check 'holder (live tray.pid): a rename of the app folder is refused while the holder holds it' $held4 'the holder does not hold the folder: the rename went through'
      if ($held4) {
        $i4 = Start-Install $p4 '-NoStartup -NoLaunch'
        if (-not $i4.Proc.WaitForExit($holdTrayMs)) { [void]$h4.Release.Set() }  # the folder frees up 24 s after the install starts
        $exited4 = Wait-Exit $i4.Proc 60000
        [void]$h4.Release.Set()
        Check 'install waits for the live tray.pid holder and exits 0 once the folder frees up' ($exited4 -and $i4.Proc.ExitCode -eq 0) "exit $($i4.Proc.ExitCode): $(@($i4.Err.Result.Trim() -split "`r?`n")[0])"
        $st4 = Get-AppState $p4
        Check 'the new app replaces the old one after the tray.pid holder lets go' ($st4.Count -eq 9 -and $null -ne $st4.Stamp -and $st4.Stamp -ne $marker) "$($st4.Count) files, tile.ps1 time $($st4.Stamp)"
        Check 'no staging or old folder is left after the tray.pid wait' ($st4.Staging -eq 0) "$($st4.Staging) app.* folder(s) left beside the app"
      }
    }
  }

  # ---- Case 5: uninstall without -Purge removes tray.pid. ----
  $p5 = Make-Profile 'untray'
  $old5 = New-OldApp $p5
  Check 'setup (uninstall): a first install puts the old app in place (nine files)' $old5.Ok "first install exit $($old5.Code): $(@($old5.Err.Result.Trim() -split "`r?`n")[0])"
  if ($old5.Ok) {
    $tpid5 = Join-Path $p5 '.tile-windows\tray.pid'
    [IO.File]::WriteAllText($tpid5, '4242', [Text.Encoding]::ASCII)  # uninstall never reads it, so only its removal clears it
    $un5 = Start-Child $p5 "-File `"$(Join-Path $p5 '.tile-windows\app\uninstall.ps1')`"" @{ TILE_NO_REGISTRY = '1' }
    $uout5 = $un5.StandardOutput.ReadToEnd() + $un5.StandardError.ReadToEnd(); $un5.WaitForExit()
    Check 'uninstall without -Purge exits 0 (scope)' ($un5.ExitCode -eq 0) "exit $($un5.ExitCode): $(@($uout5.Trim() -split "`r?`n")[0])"
    Check 'uninstall without -Purge removes tray.pid' (-not (Test-Path -LiteralPath $tpid5)) 'tray.pid is still in the profile after uninstall'
  }

  # ---- Case 6: app.old-<install pid> already exists, so the rename is a name collision, not a lock. ----
  $p6 = Make-Profile 'clash'
  $old6 = New-OldApp $p6
  Check 'setup (name collision): a first install puts the old app in place (nine files)' $old6.Ok "first install exit $($old6.Code): $(@($old6.Err.Result.Trim() -split "`r?`n")[0])"
  if ($old6.Ok) {
    $i6 = Start-Install $p6 '-NoStartup -NoLaunch'
    # The install's own name for its old app. It is taken at once, well before the install reaches its rename (about 4 s in).
    [void](New-Item -ItemType Directory -Force -Path (Join-Path $p6 ".tile-windows\app.old-$($i6.Proc.Id)"))
    $exited6 = Wait-Exit $i6.Proc 60000
    $err6 = $i6.Err.Result
    $st6 = Get-AppState $p6
    Check 'a name collision on app.old-<pid> fails the install' ($exited6 -and $i6.Proc.ExitCode -ne 0) "exit $($i6.Proc.ExitCode)"
    Check 'a name collision leaves the old app in place' ($st6.Count -eq 9 -and $st6.Stamp -eq $marker) "$($st6.Count) files, tile.ps1 time $($st6.Stamp)"
    Check 'a name collision is not reported as the app folder being in use' ($err6 -notmatch 'in use') "reported: $(@($err6.Trim() -split "`r?`n")[0])"
    Check 'a name collision leaves no app.new-* staging folder' (@(Get-ChildItem -LiteralPath (Join-Path $p6 '.tile-windows') -Filter 'app.new-*' -Force -ErrorAction SilentlyContinue).Count -eq 0) "app.new-* folder(s) left beside the app"
  }
} catch {
  $script:fail++; "FAIL  swap cases stopped: $_"
} finally {
  foreach ($h in $holders) { [void]$h.Release.Set() }
  foreach ($p in $started) { try { if (-not $p.HasExited) { $p.Kill(); [void]$p.WaitForExit(5000) } } catch { } }
  foreach ($h in $holders) { $h.Ready.Dispose(); $h.Release.Dispose() }
  foreach ($k in $savedEnv.Keys) { if ($null -eq $savedEnv[$k]) { Remove-Item "env:$k" -ErrorAction SilentlyContinue } else { Set-Item "env:$k" $savedEnv[$k] } }
  Remove-Item -LiteralPath $run -Recurse -Force -ErrorAction SilentlyContinue
}

if ($standalone) {
  if ($script:fail) { "$($script:fail) check(s) failed."; exit 1 } else { 'All checks passed.' }
}
