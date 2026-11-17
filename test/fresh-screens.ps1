# Checks for fresh screens: tile.ps1 reads the monitor list on every call. serve.ps1 runs tile.ps1 -Json inside one
# long-lived process, so a list read once per process goes stale when a monitor is unplugged. Five kinds, each with its own scope:
#   Static (case 1): the PowerShell parser's tree of tile.ps1 has no static read of Screen.AllScreens or Screen.PrimaryScreen.
#     A comment or a string that names one is no read. Controls first: the scanner finds the real reads in one fixture, and none
#     in a fixture of comments, strings and here-strings.
#   Seam (case 2): in ONE powershell process, three -Json calls answer from the seam file as it is at each call: 3 screens,
#     then 2, then none. A list read once per process fails the second call.
#   Live (case 3): a -Json call with no seam counts the same monitors as a fresh process's EnumDisplayMonitors. SKIP with no desktop.
#   Type clash (case 4): ONE powershell process runs the base tile.ps1 (git ed97406), then this one. This one's -Json lists the live
#     monitors, as a fresh process does. The base's Add-Type class W has no Monitors, so this one's W clashes with it in that process.
#   Bad seam (case 5): with TILE_SCREENS_FILE set to an empty file, to invalid JSON, or to a missing path, -Json exits non-zero.
# Run alone: powershell -NoProfile -ExecutionPolicy Bypass -File test\fresh-screens.ps1 [-Tile <path to a tile.ps1 copy>]
# test\run.ps1 runs this file in a child powershell and counts its FAIL lines. The sweep of old run folders is stack-lock.ps1's.
#
# Seam the builder must meet (the only interface these cases use):
#   TILE_SCREENS_FILE=<path>, set and non-empty: tile.ps1 reads that file on every call, in place of the live monitors.
#     The file is a JSON array of {name, x, y, w, h, bw, bh}, the fields of -From's snapshot monitors: x, y, w, h are the
#     work area and bw, bh the bounds. -Json's monitors[].name is the file's name. Each call reads the file again.
#   Unset or empty: the live monitors, as today.
#   A file that is empty, not JSON, or missing: -Json exits non-zero (case 5).
#   Live read (cases 1 and 4 hold it to this): a direct Win32 call (EnumDisplayMonitors and GetMonitorInfo), not AllScreens,
#     and no PrimaryScreen read either. The class it defines must not clash with an older tile.ps1 in the same process (case 4).
param([string]$Tile = (Join-Path (Split-Path $PSScriptRoot) 'tile.ps1'))
$ErrorActionPreference = 'Stop'
$script:fail = 0
$repo = Split-Path $PSScriptRoot  # the checkout under test; its history holds the base files that case 4 runs
function Check($name, $ok, $detail = '') { if ($ok) { "PASS  $name" } else { $script:fail++; "FAIL  $name  $detail" } }
$utf8 = New-Object Text.UTF8Encoding $false
# One child powershell with its own environment (a copy of this one's, plus $envSet): its exit code, stdout and stderr.
function Invoke-PsChild([string]$argLine, $envSet = @{}) {
  $psi = New-Object Diagnostics.ProcessStartInfo 'powershell', "-NoProfile -ExecutionPolicy Bypass $argLine"
  $psi.UseShellExecute = $false; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true; $psi.CreateNoWindow = $true
  foreach ($k in $envSet.Keys) { $psi.EnvironmentVariables[$k] = $envSet[$k] }
  $p = [Diagnostics.Process]::Start($psi)
  $errTask = $p.StandardError.ReadToEndAsync()
  $out = $p.StandardOutput.ReadToEnd(); $p.WaitForExit()
  [pscustomobject]@{ Code = $p.ExitCode; Out = $out; Err = $errTask.Result }
}
# A file as git holds it at a revision: the exact bytes, so no encoding or line-ending change. Throws when git cannot.
function Save-GitBlob([string]$spec, [string]$dest) {
  $psi = New-Object Diagnostics.ProcessStartInfo 'git', "-C `"$repo`" show $spec"
  $psi.UseShellExecute = $false; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true; $psi.CreateNoWindow = $true
  $p = [Diagnostics.Process]::Start($psi)
  $errTask = $p.StandardError.ReadToEndAsync()
  $bytes = New-Object IO.MemoryStream; $p.StandardOutput.BaseStream.CopyTo($bytes); $p.WaitForExit()
  if ($p.ExitCode -ne 0) { throw "git show $spec failed: $($errTask.Result.Trim())" }
  [IO.File]::WriteAllBytes($dest, $bytes.ToArray())
}

# One run folder per run, under the temp root the suite uses (test-temp-standard). Every helper file goes in it; teardown removes it.
$run = Join-Path (Join-Path $env:TEMP 'tile-windows-test-runs') ("$PID-" + [guid]::NewGuid().ToString())
New-Item -ItemType Directory -Force $run | Out-Null
$saved = @{ TILE_SCREENS_FILE = $env:TILE_SCREENS_FILE; TILE_HOME = $env:TILE_HOME }
try {
  $env:TILE_HOME = Join-Path $run 'home'  # tile.ps1 reads its config from here; the real profile is never named

  # ---- 1. Static: the parser's tree, not the text. ----
  # Each of these static Screen members is a per-process cache, so tile.ps1 may read neither.
  function Get-ScreenReads([string]$path) {
    $tokens = $null; $errs = $null
    $tree = [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$errs)
    $reads = @($tree.FindAll({ param($n) $n -is [System.Management.Automation.Language.MemberExpressionAst] -and $n.Static -and "$($n.Member.Value)" -in 'AllScreens', 'PrimaryScreen' }, $true))
    [pscustomobject]@{ Errors = @($errs).Count; Lines = @($reads | % { $_.Extent.StartLineNumber }); Names = @($reads | % { "$($_.Member.Value)@$($_.Extent.StartLineNumber)" }) }
  }
  # Control fixture: real reads on lines 1, 3, 5, 6 and 7 (a plain read, one inside a block, one through a variable type,
  # one before a comment, and one after a '#' inside a string).
  $posFile = Join-Path $run 'scan-control.ps1'; $negFile = Join-Path $run 'scan-text.ps1'
  $posText = (@(
    '$plain = [System.Windows.Forms.Screen]::AllScreens',
    '$inside = @(',
    '  [System.Windows.Forms.Screen]::AllScreens',
    ')',
    '$t = [System.Windows.Forms.Screen]; $alias = $t::AllScreens',
    '$primary = [System.Windows.Forms.Screen]::PrimaryScreen  # a read, then a comment',
    '$hashed = "# not a comment"; $after = [System.Windows.Forms.Screen]::PrimaryScreen'
  ) -join "`r`n")
  # Text fixture: no read. A comment (with a lone quote), a double-quoted and a single-quoted string, a here-string,
  # a multi-line string and a block comment all name AllScreens or PrimaryScreen.
  $negText = (@(
    '# a comment naming [System.Windows.Forms.Screen]::AllScreens, with a lone quote: don''t',
    '$quoted = "# not a comment: [System.Windows.Forms.Screen]::AllScreens"',
    '$single = ''[System.Windows.Forms.Screen]::AllScreens''',
    '$block = @''',
    '[System.Windows.Forms.Screen]::AllScreens',
    '''@',
    '$multi = "first line',
    '[System.Windows.Forms.Screen]::AllScreens"',
    '<# block comment',
    '[System.Windows.Forms.Screen]::AllScreens #>',
    '# and [System.Windows.Forms.Screen]::PrimaryScreen, a comment too',
    '$quotedPrimary = "# not a comment: [System.Windows.Forms.Screen]::PrimaryScreen"',
    '$singlePrimary = ''[System.Windows.Forms.Screen]::PrimaryScreen''',
    '$multiPrimary = "first line',
    '[System.Windows.Forms.Screen]::PrimaryScreen"',
    '$ok = 1'
  ) -join "`r`n")
  [IO.File]::WriteAllText($posFile, $posText, $utf8); [IO.File]::WriteAllText($negFile, $negText, $utf8)
  $ctl = Get-ScreenReads $posFile
  Check 'static control: the scanner finds the real reads (AllScreens and PrimaryScreen, lines 1, 3, 5, 6, 7)' (($ctl.Errors -eq 0) -and (($ctl.Lines -join ',') -eq '1,3,5,6,7')) "parse errors=$($ctl.Errors), read lines=$($ctl.Lines -join ',')"
  $txt = Get-ScreenReads $negFile
  Check 'static control: comments, strings, here-strings and block comments naming AllScreens or PrimaryScreen are no read' (($txt.Errors -eq 0) -and ($txt.Lines.Count -eq 0)) "parse errors=$($txt.Errors), read lines=$($txt.Lines -join ',')"
  $tileScan = Get-ScreenReads $Tile
  Check 'static: tile.ps1 parses with no error' ($tileScan.Errors -eq 0) "$($tileScan.Errors) parse error(s) in tile.ps1"
  Check 'static: tile.ps1 reads no Screen.AllScreens or Screen.PrimaryScreen (both are per-process caches)' ($tileScan.Lines.Count -eq 0) "per-process Screen read(s) in tile.ps1, name@line: $($tileScan.Names -join ', ')"

  # ---- 2. Seam: one process, three -Json calls, the seam file rewritten between them. ----
  $screensFile = Join-Path $run 'screens.json'; $listA = Join-Path $run 'screens-a.json'; $listB = Join-Path $run 'screens-b.json'; $listC = Join-Path $run 'screens-empty.json'
  $setA = @(
    [pscustomobject]@{ name = 'SEAM-A-1'; x = 0;    y = 0; w = 3440; h = 1400; bw = 3440; bh = 1440 },
    [pscustomobject]@{ name = 'SEAM-A-2'; x = 3440; y = 0; w = 1920; h = 1040; bw = 1920; bh = 1080 },
    [pscustomobject]@{ name = 'SEAM-A-3'; x = 5360; y = 0; w = 1920; h = 1040; bw = 1920; bh = 1080 }
  )
  $setB = @(
    [pscustomobject]@{ name = 'SEAM-B-1'; x = 0;    y = 0; w = 1920; h = 1040; bw = 1920; bh = 1080 },
    [pscustomobject]@{ name = 'SEAM-B-2'; x = 1920; y = 0; w = 1920; h = 1040; bw = 1920; bh = 1080 }
  )
  [IO.File]::WriteAllText($listA, (ConvertTo-Json -InputObject $setA -Depth 3 -Compress), $utf8)
  [IO.File]::WriteAllText($listB, (ConvertTo-Json -InputObject $setB -Depth 3 -Compress), $utf8)
  [IO.File]::WriteAllText($listC, '[]', $utf8)
  # The helper: one powershell process. It copies each list over the seam file, then makes one -Json call. Each answer is one RESULT line.
  $seamText = @'
param([string]$Tile, [string]$Screens, [string]$First, [string]$Second, [string]$Third)
$env:TILE_SCREENS_FILE = $Screens
foreach ($list in $First, $Second, $Third) {
  Copy-Item -LiteralPath $list -Destination $Screens -Force
  try { 'RESULT ' + ((& $Tile -Json 3>$null | ? { "$_" -notmatch '^WARNING:' }) -join '') } catch { 'ERROR ' + $_.Exception.Message }
}
'@
  $seamFile = Join-Path $run 'seam-calls.ps1'; [IO.File]::WriteAllText($seamFile, $seamText, $utf8)
  $seamOut = @(& powershell -NoProfile -ExecutionPolicy Bypass -File $seamFile -Tile $Tile -Screens $screensFile -First $listA -Second $listB -Third $listC)
  $results = @($seamOut | ? { "$_" -like 'RESULT *' } | % { "$_".Substring(7) })
  $seamErrors = @($seamOut | ? { "$_" -like 'ERROR *' })
  Check 'seam: three -Json calls ran in one process and each gave a result' ($results.Count -eq 3) "results=$($results.Count); errors: $($seamErrors -join ' / ')"
  function Get-MonitorNames([string]$json) {
    try { (@((ConvertFrom-Json $json).monitors | % { [string]$_.name }) | Sort-Object) -join ',' } catch { '(not JSON)' }
  }
  $first = if ($results.Count -ge 1) { Get-MonitorNames $results[0] } else { '(no result)' }
  $second = if ($results.Count -ge 2) { Get-MonitorNames $results[1] } else { '(no result)' }
  Check 'seam: call 1 reads the 3 screens in the seam file, not the live monitors' ($first -eq 'SEAM-A-1,SEAM-A-2,SEAM-A-3') "call 1 showed: $first"
  Check 'seam: call 2, after the file was rewritten to 2 screens, shows those 2 and not call 1 again' ($second -eq 'SEAM-B-1,SEAM-B-2') "call 2 showed: $second"
  if (($first -eq 'SEAM-A-1,SEAM-A-2,SEAM-A-3') -and ($second -eq 'SEAM-B-1,SEAM-B-2')) {
    $third = if ($results.Count -ge 3) { Get-MonitorNames $results[2] } else { '(no result)' }
    Check 'seam: call 3, after the file was rewritten to an empty list, shows no screen' ($third -eq '') "call 3 showed: $third"
  } else {
    Check 'seam: call 3 (empty list) is judged only once calls 1 and 2 have each read the seam file' $false 'not judged: calls 1 and 2 must both read the seam file first'
  }

  # ---- 3. Live smoke: with no seam, a -Json call counts the monitors a fresh EnumDisplayMonitors finds. ----
  $probeCs = @'
using System; using System.Runtime.InteropServices;
public static class FreshScreensProbe {
  public delegate bool MonitorEnum(IntPtr monitor, IntPtr hdc, IntPtr rect, IntPtr data);
  [DllImport("user32.dll")] public static extern bool EnumDisplayMonitors(IntPtr hdc, IntPtr clip, MonitorEnum cb, IntPtr data);
  public static int Count() { int n = 0; EnumDisplayMonitors(IntPtr.Zero, IntPtr.Zero, (m, h, r, d) => { n++; return true; }, IntPtr.Zero); return n; }
}
'@
  $probeText = (@(
    'Add-Type -TypeDefinition @''',
    $probeCs,
    '''@',
    'Write-Output ("COUNT " + [FreshScreensProbe]::Count())',
    'Write-Output ("INTERACTIVE " + [Environment]::UserInteractive)'
  ) -join "`r`n")
  $probeFile = Join-Path $run 'probe.ps1'; [IO.File]::WriteAllText($probeFile, $probeText, $utf8)
  $probe = @(& powershell -NoProfile -ExecutionPolicy Bypass -File $probeFile)
  $fresh = @($probe | ? { "$_" -like 'COUNT *' } | % { [int]("$_".Substring(6)) })
  $interactive = @($probe | ? { "$_" -eq 'INTERACTIVE True' }).Count -gt 0
  if (-not $interactive -or $fresh.Count -eq 0 -or $fresh[0] -lt 1) {
    'SKIP  live: no desktop session (EnumDisplayMonitors found no monitor), so the -Json count is not compared'
  } else {
    Remove-Item env:TILE_SCREENS_FILE -ErrorAction SilentlyContinue
    $liveN = try { @((ConvertFrom-Json (((& powershell -NoProfile -ExecutionPolicy Bypass -File $Tile -Json 3>$null) | ? { "$_" -notmatch '^WARNING:' }) -join '')).monitors).Count } catch { -1 }
    Check 'live: a -Json call counts the same monitors as a fresh EnumDisplayMonitors' ($liveN -eq $fresh[0]) "tile -Json counts $liveN monitor(s), EnumDisplayMonitors counts $($fresh[0])"
  }

  # ---- 4. Type clash: the base tile.ps1 (ed97406), then this one, in ONE process. ----
  # The base's Add-Type class W has no Monitors; this tile.ps1's W has one, so in that process its Add-Type meets the base's W.
  # A fresh process lists the live monitors. The base's own files come from git, into the run folder.
  Remove-Item env:TILE_SCREENS_FILE -ErrorAction SilentlyContinue
  $baseDir = Join-Path $run 'base'; New-Item -ItemType Directory -Force $baseDir | Out-Null
  Save-GitBlob 'ed97406:tile.ps1' (Join-Path $baseDir 'tile.ps1'); Save-GitBlob 'ed97406:config.ps1' (Join-Path $baseDir 'config.ps1')
  # The helper: both calls in one process. Its answers: OLDTYPE (the base's W, with or without Monitors), NEW (this tile's -Json), NEWERR (its first errors).
  $clashText = @'
param([string]$Old, [string]$New)
$null = & $Old -Json 3>$null 2>$null
$w = 'W' -as [type]
'OLDTYPE ' + $(if ($w -and -not $w.GetMethod('Monitors')) { 'no-Monitors' } else { 'other' })
$Error.Clear()
'NEW ' + ((& $New -Json 3>$null) -join '')
'NEWERR ' + (@($Error | Select-Object -First 2 | % { "$_" }) -join ' | ')
'@
  $clashFile = Join-Path $run 'clash-calls.ps1'; [IO.File]::WriteAllText($clashFile, $clashText, $utf8)
  $clash = Invoke-PsChild "-File `"$clashFile`" -Old `"$(Join-Path $baseDir 'tile.ps1')`" -New `"$Tile`""
  $clashOut = @($clash.Out -split "`r?`n")
  $oldType = @($clashOut | ? { $_ -like 'OLDTYPE *' } | % { $_.Substring(8) })
  $newJson = @($clashOut | ? { $_ -like 'NEW *' } | % { $_.Substring(4) })
  $newErr = @($clashOut | ? { $_ -like 'NEWERR *' } | % { $_.Substring(7) })
  $clashFresh = Invoke-PsChild "-File `"$Tile`" -Json"
  $freshNames = Get-MonitorNames (@($clashFresh.Out -split "`r?`n" | ? { $_ -notmatch '^WARNING:' }) -join '')
  if ($oldType.Count -ne 1 -or $oldType[0] -ne 'no-Monitors') {
    Check 'type clash: scope: the base run left its own class W (no Monitors) in the process' $false "OLDTYPE answer: $($oldType -join ' '); base run stderr: $($clash.Err.Trim())"
  } elseif ($freshNames -eq '') {
    'SKIP  type clash: no desktop session (a fresh process lists no monitor), so the same-process list is not compared'
  } else {
    $newNames = if ($newJson.Count -eq 0) { '(no result)' } else { Get-MonitorNames $newJson[0] }
    Check 'type clash: -Json after the base tile.ps1 in the same process lists the live monitors, as a fresh process does' ($newNames -eq $freshNames) "same process lists [$newNames], a fresh process lists [$freshNames]; first error: $(@($newErr)[0])"
  }

  # ---- 5. Bad seam file: -Json must exit non-zero, never print an empty monitor list as success. ----
  $badDir = Join-Path $run 'bad'; New-Item -ItemType Directory -Force $badDir | Out-Null
  $emptySeam = Join-Path $badDir 'empty.json'; [IO.File]::WriteAllBytes($emptySeam, [byte[]]@())
  $brokenSeam = Join-Path $badDir 'broken.json'; [IO.File]::WriteAllText($brokenSeam, '[{"name":"X",', $utf8)
  $missingSeam = Join-Path $badDir 'missing.json'  # never created
  $brokenFails = $false; try { ConvertFrom-Json ([IO.File]::ReadAllText($brokenSeam, $utf8)) | Out-Null } catch { $brokenFails = $true }
  $fixturesOk = ((Get-Item -LiteralPath $emptySeam).Length -eq 0) -and $brokenFails -and (-not (Test-Path -LiteralPath $missingSeam))
  if (-not $fixturesOk) {
    Check 'bad seam: scope: the three bad files are empty, not JSON and absent' $false 'a fixture is not what its name says'
  } else {
    foreach ($bad in @(@('empty file', $emptySeam), @('invalid JSON', $brokenSeam), @('missing path', $missingSeam))) {
      $r = Invoke-PsChild "-File `"$Tile`" -Json" @{ TILE_SCREENS_FILE = $bad[1] }
      $shown = $r.Out.Trim(); $shown = $shown.Substring(0, [Math]::Min(80, $shown.Length))
      Check "bad seam ($($bad[0])): tile.ps1 -Json exits non-zero" ($r.Code -ne 0) "exit $($r.Code) on a bad seam file; stdout starts: $shown"
    }
  }
} catch {
  $script:fail++; "FAIL  run stopped: $_"
} finally {
  foreach ($k in $saved.Keys) { if ($null -eq $saved[$k]) { Remove-Item "env:$k" -ErrorAction SilentlyContinue } else { Set-Item "env:$k" $saved[$k] } }
  Remove-Item -LiteralPath $run -Recurse -Force -ErrorAction SilentlyContinue
}
if ($script:fail) { "$($script:fail) check(s) failed."; exit 1 } else { 'All checks passed.' }
