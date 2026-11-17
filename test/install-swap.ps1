# Checks for install.ps1's swap when the installed app folder is busy. The swap renames the old app aside (install.ps1 line 33),
# and a process whose working directory is that folder makes the rename fail: "being used by another process". Two cases,
# each with its own scope:
#   Frees up (case 1): a holder keeps the app folder busy and lets go 8 s after the install starts. The install waits the holder
#     out, swaps the new app in, and leaves no staging or old folder.
#   Never frees up (case 2, a green control): the holder never lets go. The install gives up in bounded time, exits non-zero,
#     leaves the old app in place, and leaves no staging folder.
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
