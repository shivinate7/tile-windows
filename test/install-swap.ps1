# Checks for install.ps1's swap when the installed app folder is busy, for its tray.pid wait, for uninstall.ps1's tray.pid
# removal, and for the environment install.ps1 gives the tray it starts. The swap renames the old app aside (the Rename-Item retry loop in install.ps1), and a process whose working directory is
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
#   Tray environment (case 7, debt tray-inherits-claudecode): install.ps1 starts the tray with -Open. Run from a shell that carries an
#     agent marker (a name the live-move guard in tile.ps1 reads, other than the suite flag TILE_TEST_SUITE and the opt-in
#     TILE_TEST_ALLOW_LIVE; today only CLAUDECODE), the tray must not inherit the marker, or the guard refuses its live applies. The
#     marker names come from the guard's own syntax tree in tile.ps1, so a marker added there is picked up. The tray runs from a copy
#     of the app whose tray.ps1 writes the variables it inherited to a file and returns, so no tray, server or browser starts.
#     Red on 17a4bed: the tray inherits CLAUDECODE (7b). Green controls: 7c the suite flag still reaches the tray (a tray a test starts
#     stays guarded); 7d the install's other variables and its profile reach the tray; 7e the calling shell keeps its marker; 7f with no
#     marker the tray sees none (a Start-menu start). 7a scope checks come first and are never the red.
#   Agenda across a reinstall (case 8, debt reinstall-loses-agenda-json): the morning task writes agenda.json where the tray reads it, and
#     a reinstall must leave that file, byte for byte, where the installed tray reads it. Where that is comes from the one Join-Path of
#     'agenda.json' in tray.ps1 and config.ps1 (the files the tray takes its paths from), evaluated in a child with the profile's
#     USERPROFILE (8a). So a fix may keep the file in the app folder or hold it elsewhere, but the tray's read must follow it. When the
#     fix changes how the path is written (a second mention, another call than Join-Path), 8a fails by name: extend Get-AgendaPathExpr.
#     Red on ad8a0b8: the reinstall removes the old app folder with the file in it (8d). Green controls: 8b a swap that fails keeps the
#     file; 8c the reinstall itself works (exit 0, a new app, no leftover folder); 8e what is kept has the bytes that were written. 8e
#     runs only when the file is there, so a lost file is the one failed check 8d. Reinstalls with no agenda.json (the empty state) are
#     cases 1, 3 and 4.
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

# One install.ps1 run in a child powershell, into the profile given, with no registry writes. $extra adds or overrides child
# environment variables (TILE_SOURCE too). A non-empty $after, a PowerShell snippet, makes the install run by call in a session that
# then runs the snippet, so it can read what the install left in the calling session; the default runs it as -File.
function Start-Install([string]$prof, [string]$flags, [hashtable]$extra = @{}, [string]$after = '') {
  $childEnv = @{ TILE_SOURCE = $root; TILE_NO_REGISTRY = '1' }
  foreach ($k in $extra.Keys) { $childEnv[$k] = $extra[$k] }
  $inst = Join-Path $root 'install.ps1'
  $argLine = if ($after) { "-Command `"& '$inst' $flags | Out-Null; $after`"" } else { "-File `"$inst`" $flags" }
  $p = Start-Child $prof $argLine $childEnv
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

# ---- Case 7 helpers: the environment install.ps1 gives the tray it starts. ----
function Get-ScriptTree([string]$text) { [Management.Automation.Language.Parser]::ParseInput($text, [ref]$null, [ref]$null) }

# The environment variable names the live-move guard in tile.ps1 reads, from its syntax tree: the one `if` whose body throws the
# refusal. Empty when that statement is not found exactly once.
function Get-GuardEnvNames {
  $tree = Get-ScriptTree ([IO.File]::ReadAllText((Join-Path $root 'tile.ps1')))
  $guards = @($tree.FindAll({ param($n) $n -is [Management.Automation.Language.IfStatementAst] -and $n.Clauses[0].Item2.Extent.Text -match 'would move windows' }, $true))
  if ($guards.Count -ne 1) { return @() }
  $vars = $guards[0].Clauses[0].Item1.FindAll({ param($n) $n -is [Management.Automation.Language.VariableExpressionAst] -and $n.VariablePath.UserPath -like 'env:*' }, $true)
  @($vars | ForEach-Object { $_.VariablePath.UserPath.Substring(4) } | Sort-Object -Unique)
}

# A copy of the product's top-level files in $dir, to install from. Its tray.ps1 gets a probe right after the file's own
# `if ($Lib) { return }` (found in the syntax tree, so a string or comment that looks like it does not count): a -Lib run returns as
# before, and any other run writes the variables named in $names, as inherited, to $probe and returns, so no tray, server or browser
# starts however the install launches it. Returns how many such statements were found; the probe is added only when it is exactly one.
function New-ProbeSource([string]$dir, [string]$probe, [string[]]$names) {
  New-Item -ItemType Directory -Force $dir | Out-Null
  foreach ($f in Get-ChildItem -LiteralPath $root -File) { Copy-Item -LiteralPath $f.FullName -Destination $dir -Force }
  $tray = Join-Path $dir 'tray.ps1'; $text = [IO.File]::ReadAllText($tray)
  $hooks = @((Get-ScriptTree $text).FindAll({ param($n) $n -is [Management.Automation.Language.IfStatementAst] -and $n.Clauses.Count -eq 1 -and $n.Clauses[0].Item1.Extent.Text -eq '$Lib' -and $n.Clauses[0].Item2.Extent.Text -match '^\{\s*return\s*\}$' }, $false))
  if ($hooks.Count -eq 1) {
    $code = @'

# env probe (test): a run that is not -Lib writes the variables it inherited, then returns.
$probeLines = @(foreach ($probeName in @(@@NAMES@@)) { $probeName + '=[' + [Environment]::GetEnvironmentVariable($probeName) + ']' }) + ('open=[' + $Open.IsPresent + ']')
[IO.File]::WriteAllText('@@PROBE@@', ($probeLines -join "`n"), [Text.Encoding]::ASCII); return
'@
    $code = $code.Replace('@@NAMES@@', (($names | ForEach-Object { "'$_'" }) -join ',')).Replace('@@PROBE@@', $probe)
    [IO.File]::WriteAllText($tray, $text.Insert($hooks[0].Extent.EndOffset, $code), (New-Object Text.UTF8Encoding $false))
  }
  $hooks.Count
}

# One install into a fresh profile, from a probe source, with every name in $markers set to $marker in the install's environment
# ('1' is a shell that carries the agent markers, '' one that carries none). The caller's other variables the install reads or passes on
# are pinned. Returns: Hooks (see New-ProbeSource), Exited and Code (the install), Err, Probe (name -> value the tray wrote; $null when
# it wrote nothing within 60 s, a bound well above the install's own few seconds) and Caller (name -> value the calling session held
# once the install returned).
function Invoke-TrayEnvRun([string]$tag, [string]$marker, [string[]]$markers) {
  $prof = Make-Profile "trayenv-$tag"; $src = Join-Path $run "probe-src-$tag"; $probe = Join-Path $run "probe-$tag.txt"
  $res = [pscustomobject]@{ Hooks = 0; Exited = $false; Code = $null; Err = ''; Probe = $null; Caller = @{}; Profile = $prof }
  $res.Hooks = New-ProbeSource $src $probe (@($markers) + 'TILE_TEST_SUITE', 'TILE_ENVPROBE_KEEP', 'USERPROFILE')
  if ($res.Hooks -ne 1) { return $res }
  $e = @{ TILE_SOURCE = $src; TILE_NO_LAUNCH = ''; TILE_DRY_START = ''; TILE_HOME = ''; TILE_TEST_SWAP_FAIL = ''; TILE_TEST_ALLOW_LIVE = ''; TILE_TEST_SUITE = '1'; TILE_ENVPROBE_KEEP = "keep-$tag" }
  foreach ($m in $markers) { $e[$m] = $marker }
  $quoted = ($markers | ForEach-Object { "'$_'" }) -join ','
  $after = "foreach (`$n in @($quoted)) { [Console]::Out.WriteLine('caller-' + `$n + '=[' + [Environment]::GetEnvironmentVariable(`$n) + ']') }"
  $i = Start-Install $prof '-NoStartup' $e $after
  $res.Exited = Wait-Exit $i.Proc 120000; $res.Code = $i.Proc.ExitCode
  # A process the install started could hold its pipes after it exits, so the reads are bounded.
  [void]$i.Out.Wait(30000); [void]$i.Err.Wait(30000)
  $res.Err = if ($i.Err.IsCompleted) { "$($i.Err.Result)".Trim() } else { '' }
  $outText = if ($i.Out.IsCompleted) { "$($i.Out.Result)" } else { '' }
  foreach ($c in [regex]::Matches($outText, '(?m)^caller-(\w+)=\[([^\]\r\n]*)\]')) { $res.Caller[$c.Groups[1].Value] = $c.Groups[2].Value }
  # The tray starts on its own clock, so poll for its probe file with a cap, not a fixed wait.
  $sw = [Diagnostics.Stopwatch]::StartNew()
  while ($sw.ElapsedMilliseconds -lt 60000 -and -not $res.Probe) {
    try { $t = [IO.File]::ReadAllText($probe) } catch { $t = '' }
    if ($t -match '(?m)^open=\[') {
      $seen = @{}; foreach ($l in ($t -split "`n")) { if ($l -match '^(\w+)=\[(.*)\]\s*$') { $seen[$Matches[1]] = $Matches[2] } }
      $res.Probe = $seen
    } else { Start-Sleep -Milliseconds 100 }
  }
  # The probe returns at once, so no tray should still run. One that does carries this run folder in its command line: stop it.
  try {
    foreach ($w in @(Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe'" | Where-Object { $_.CommandLine -and $_.CommandLine.Contains($run) -and $_.CommandLine -match 'tray\.ps1' })) { Stop-Process -Id $w.ProcessId -Force -ErrorAction SilentlyContinue }
  } catch { }
  $res
}

# ---- Case 8 helpers: where the installed tray reads agenda.json (debt reinstall-loses-agenda-json). ----
# The one Join-Path command, as text, that names 'agenda.json' in the files of $appDir the tray takes its paths from (tray.ps1 and
# config.ps1). $null when there is not exactly one such mention, or it is not a three-part Join-Path. Found in the syntax tree, so a
# comment or a longer string that mentions the file does not count.
function Get-AgendaPathExpr([string]$appDir) {
  $found = @()
  foreach ($f in 'tray.ps1', 'config.ps1') {
    $found += @((Get-ScriptTree ([IO.File]::ReadAllText((Join-Path $appDir $f)))).FindAll({ param($n) $n -is [Management.Automation.Language.StringConstantExpressionAst] -and $n.Value -eq 'agenda.json' }, $true))
  }
  if ($found.Count -ne 1) { return $null }
  $cmd = $found[0].Parent
  if ($cmd -isnot [Management.Automation.Language.CommandAst] -or $cmd.GetCommandName() -ne 'Join-Path' -or $cmd.CommandElements.Count -ne 3) { return $null }
  $cmd.Extent.Text
}

# The path that command gives for the profile $prof: a child powershell dot-sources the installed config.ps1 (so $TileHome is the
# profile's, with TILE_HOME cleared) and evaluates the text with $PSScriptRoot standing for the app folder, which is what it is in the
# tray. $null when the child fails, does not end within 60 s (a cap well above its second or two), or prints nothing.
function Resolve-AgendaPath([string]$prof, [string]$expr) {
  $appDir = Join-Path $prof '.tile-windows\app'
  $exprFile = Join-Path $run 'agenda-expr.txt'; $script = Join-Path $run 'agenda-resolve.ps1'
  $utf8 = New-Object Text.UTF8Encoding $false
  [IO.File]::WriteAllText($exprFile, $expr.Replace('$PSScriptRoot', '$App'), $utf8)
  $resolver = @'
param([string]$App, [string]$ExprFile)
$ErrorActionPreference = 'Stop'
. (Join-Path $App 'config.ps1')
[Console]::Out.Write([string](Invoke-Expression ([IO.File]::ReadAllText($ExprFile))))
'@
  [IO.File]::WriteAllText($script, $resolver, $utf8)
  $c = Start-Child $prof "-File `"$script`" `"$appDir`" `"$exprFile`"" @{ TILE_HOME = '' }
  [void]$started.Add($c)
  $out = $c.StandardOutput.ReadToEndAsync(); [void]$c.StandardError.ReadToEndAsync()
  if (-not (Wait-Exit $c 60000) -or $c.ExitCode -ne 0) { return $null }
  $t = "$($out.Result)".Trim()
  if ($t) { $t } else { $null }
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

  # ---- Case 7: the environment install.ps1 gives the tray it starts (debt tray-inherits-claudecode). ----
  # The marker names are what tile.ps1's guard reads, less the suite flag and the opt-in. A shell with every marker set is an agent's;
  # one with none set is the Start menu's. Each run installs once and reads what the tray (the probe) inherited.
  $guardNames = @(Get-GuardEnvNames)
  $markers = @($guardNames | Where-Object { $_ -notin 'TILE_TEST_SUITE', 'TILE_TEST_ALLOW_LIVE' })
  $guardOk = ($guardNames -contains 'TILE_TEST_SUITE') -and ($markers -contains 'CLAUDECODE')
  Check 'setup (tray env): the guard in tile.ps1 reads TILE_TEST_SUITE and the agent marker CLAUDECODE' $guardOk "the guard reads: $($guardNames -join ', ')"
  if ($guardOk) {
    foreach ($spec in @(@('agent', '1'), @('plain', ''))) {
      $tag = $spec[0]; $tr = Invoke-TrayEnvRun $tag $spec[1] $markers
      $seen = if ($tr.Probe) { ($tr.Probe.Keys | Sort-Object | ForEach-Object { "$_=[$($tr.Probe[$_])]" }) -join ' ' } else { 'no probe file' }
      Check "7a scope ($tag): the probe is added to tray.ps1 at its one -Lib return" ($tr.Hooks -eq 1) "found $($tr.Hooks) such statements, so no probe was added"
      if ($tr.Hooks -ne 1) { continue }
      Check "7a scope ($tag): the install exits 0" ($tr.Exited -and $tr.Code -eq 0) "exit $($tr.Code): $(@($tr.Err -split "`r?`n")[0])"
      Check "7a scope ($tag): the install starts the tray with -Open (the probe wrote its line)" ($tr.Probe -and $tr.Probe['open'] -eq 'True') "probe: $seen"
      if (-not $tr.Probe) { continue }
      Check "7a scope ($tag): the tray inherits the install's other variables (the probe reads a real environment)" ($tr.Probe['TILE_ENVPROBE_KEEP'] -eq "keep-$tag") "probe: $seen"
      if ($tag -eq 'agent') {
        foreach ($m in $markers) {
          Check "7b the tray install.ps1 starts does not inherit $m (set to 1 in the install's shell)" ($tr.Probe[$m] -eq '') "the tray saw $m=[$($tr.Probe[$m])], so the live-move guard refuses its live applies"
        }
        Check '7c the suite flag TILE_TEST_SUITE still reaches the tray (a tray a test starts stays guarded)' ($tr.Probe['TILE_TEST_SUITE'] -eq '1') "the tray saw TILE_TEST_SUITE=[$($tr.Probe['TILE_TEST_SUITE'])]"
        Check "7d the tray runs in the install's profile (USERPROFILE reaches it)" ($tr.Probe['USERPROFILE'] -eq $tr.Profile) "the tray saw USERPROFILE=[$($tr.Probe['USERPROFILE'])]"
        foreach ($m in $markers) {
          Check "7e the shell that ran the install keeps $m after it returns" ($tr.Caller[$m] -eq '1') "the shell held $m=[$($tr.Caller[$m])] after the install"
        }
      } else {
        foreach ($m in $markers) {
          Check "7f with no $m in the shell, the tray sees none (a start like the Start menu's)" ($tr.Probe[$m] -eq '') "the tray saw $m=[$($tr.Probe[$m])]"
        }
      }
    }
  }

  # ---- Case 8: a reinstall keeps agenda.json where the tray reads it (debt reinstall-loses-agenda-json). ----
  # One profile: a first install; the morning task's agenda.json at the path the tray reads (8a); an install whose swap fails (8b, a
  # green control); then a reinstall that works (8c, 8d, 8e). The agenda is a made-up day with an event title that is not ASCII, so a
  # copy that round-trips the text through the system code page changes its bytes (8e). The tray ignores the title.
  $p8 = Make-Profile 'agenda'
  $old8 = New-OldApp $p8
  Check 'setup (agenda): a first install puts the old app in place (nine files)' $old8.Ok "first install exit $($old8.Code): $(@($old8.Err.Result.Trim() -split "`r?`n")[0])"
  if ($old8.Ok) {
    $expr8 = Get-AgendaPathExpr (Join-Path $p8 '.tile-windows\app')
    Check '8a scope: tray.ps1 and config.ps1 name agenda.json in exactly one three-part Join-Path, so the path the tray reads can be worked out' ($null -ne $expr8) 'not exactly one Join-Path of agenda.json: extend Get-AgendaPathExpr for the fix'
    $path8 = $null
    if ($expr8) { $path8 = Resolve-AgendaPath $p8 $expr8 }
    # GetFullPath expands an 8.3 short name (TEMP can be one), so both sides go through it before they are compared.
    $home8 = [IO.Path]::GetFullPath((Join-Path $p8 '.tile-windows'))
    $inHome8 = $false
    if ($path8) { try { $inHome8 = [IO.Path]::GetFullPath($path8).StartsWith($home8 + '\', [StringComparison]::OrdinalIgnoreCase) } catch { } }
    if ($expr8) { Check '8a scope: that path resolves, in a child of the profile, to a file inside the profile''s .tile-windows folder' $inHome8 "the expression '$expr8' gave: [$path8]" }
    if ($inHome8) {
      $path8 = [IO.Path]::GetFullPath($path8)
      $title8 = 'Revue trimestrielle ' + [char]0xE9 + 'quipe ' + [char]0x4F1A  # e-acute and a CJK character: not ASCII, and the CJK one is in no Western code page
      $agenda8 = @(
        '{', '  "date": "2026-01-15",', '  "events": [',
        '    { "start": "2026-01-15T09:00", "end": "2026-01-15T09:30", "attendees": 3, "teams": true, "showAs": "busy", "title": "Stand-up" },',
        ('    { "start": "2026-01-15T10:00", "end": "2026-01-15T11:00", "attendees": 40, "teams": true, "showAs": "busy", "title": "' + $title8 + '" },'),
        '    { "start": "2026-01-15T13:00", "end": "2026-01-15T13:45", "attendees": 1, "teams": false, "showAs": "free", "title": "Focus" }',
        '  ]', '}') -join "`r`n"
      New-Item -ItemType Directory -Force (Split-Path $path8) | Out-Null
      [IO.File]::WriteAllText($path8, $agenda8, (New-Object Text.UTF8Encoding $false))
      $hash8 = if (Test-Path -LiteralPath $path8) { (Get-FileHash -LiteralPath $path8 -Algorithm SHA256).Hash } else { '' }
      Check '8a scope: the agenda.json the morning task wrote is at the path the tray reads, before the reinstall' ($hash8 -ne '') "no file at $path8"
      if ($hash8) {
        # 8b (green control): the swap fails between its two renames. The old app goes back, and so does what it holds.
        $i8b = Start-Install $p8 '-NoStartup -NoLaunch' @{ TILE_TEST_SWAP_FAIL = '1'; TILE_HOME = '' }
        $exited8b = Wait-Exit $i8b.Proc 120000
        Check '8b scope: an install whose swap fails exits non-zero' ($exited8b -and $i8b.Proc.ExitCode -ne 0) "exit $($i8b.Proc.ExitCode)"
        $now8b = if (Test-Path -LiteralPath $path8) { (Get-FileHash -LiteralPath $path8 -Algorithm SHA256).Hash } else { '' }
        Check '8b control: an install whose swap fails keeps agenda.json with the bytes written' ($now8b -eq $hash8) "hash after the failed install: [$now8b], before: [$hash8]"

        # 8c-8e: the reinstall that works.
        $i8 = Start-Install $p8 '-NoStartup -NoLaunch' @{ TILE_TEST_SWAP_FAIL = ''; TILE_HOME = '' }
        $exited8 = Wait-Exit $i8.Proc 120000
        Check '8c scope: the reinstall exits 0' ($exited8 -and $i8.Proc.ExitCode -eq 0) "exit $($i8.Proc.ExitCode): $(@($i8.Err.Result.Trim() -split "`r?`n")[0])"
        $st8 = Get-AppState $p8
        Check '8c scope: the reinstall puts a new copy of the app in place (tile.ps1 is not the old one)' ($null -ne $st8.Stamp -and $st8.Stamp -ne $marker) "tile.ps1 time $($st8.Stamp)"
        Check '8c control: no staging or old folder is left after the reinstall' ($st8.Staging -eq 0) "$($st8.Staging) app.* folder(s) left beside the app"
        $kept8 = Test-Path -LiteralPath $path8
        Check '8d a reinstall keeps agenda.json at the path the tray reads' $kept8 "no file at $path8 after the reinstall"
        if ($kept8) {
          $after8 = (Get-FileHash -LiteralPath $path8 -Algorithm SHA256).Hash
          Check '8e the agenda.json a reinstall keeps has the bytes the morning task wrote' ($after8 -eq $hash8) "hash after: [$after8], before: [$hash8]"
        }
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
