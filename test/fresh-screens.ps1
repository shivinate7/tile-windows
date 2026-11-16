# Checks for fresh screens: tile.ps1 reads the monitor list on every call. serve.ps1 runs tile.ps1 -Json inside one
# long-lived process, so a list read once per process goes stale when a monitor is unplugged. Three kinds, each with its own scope:
#   Static (case 1): the PowerShell parser's tree of tile.ps1 has no read of [..Screen]::AllScreens. A comment or a string that
#     names it is no read. Controls first: the scanner finds the real reads in one fixture, and none in a fixture of comments,
#     strings and here-strings.
#   Seam (case 2): in ONE powershell process, three -Json calls answer from the seam file as it is at each call: 3 screens,
#     then 2, then none. A list read once per process fails the second call.
#   Live (case 3): a -Json call with no seam counts the same monitors as a fresh process's EnumDisplayMonitors. SKIP with no desktop.
# Run alone: powershell -NoProfile -ExecutionPolicy Bypass -File test\fresh-screens.ps1 [-Tile <path to a tile.ps1 copy>]
# test\run.ps1 runs this file in a child powershell and counts its FAIL lines. The sweep of old run folders is stack-lock.ps1's.
#
# Seam the builder must meet (the only interface these cases use):
#   TILE_SCREENS_FILE=<path>, set and non-empty: tile.ps1 reads that file on every call, in place of the live monitors.
#     The file is a JSON array of {name, x, y, w, h, bw, bh}, the fields of -From's snapshot monitors: x, y, w, h are the
#     work area and bw, bh the bounds. -Json's monitors[].name is the file's name. Each call reads the file again.
#   Unset or empty: the live monitors, as today.
#   Live read (case 1 holds it to this): a direct Win32 call (EnumDisplayMonitors and GetMonitorInfo), not AllScreens.
param([string]$Tile = (Join-Path (Split-Path $PSScriptRoot) 'tile.ps1'))
$ErrorActionPreference = 'Stop'
$script:fail = 0
function Check($name, $ok, $detail = '') { if ($ok) { "PASS  $name" } else { $script:fail++; "FAIL  $name  $detail" } }
$utf8 = New-Object Text.UTF8Encoding $false

# One run folder per run, under the temp root the suite uses (test-temp-standard). Every helper file goes in it; teardown removes it.
$run = Join-Path (Join-Path $env:TEMP 'tile-windows-test-runs') ("$PID-" + [guid]::NewGuid().ToString())
New-Item -ItemType Directory -Force $run | Out-Null
$saved = @{ TILE_SCREENS_FILE = $env:TILE_SCREENS_FILE; TILE_HOME = $env:TILE_HOME }
try {
  $env:TILE_HOME = Join-Path $run 'home'  # tile.ps1 reads its config from here; the real profile is never named

  # ---- 1. Static: the parser's tree, not the text. ----
  function Get-AllScreensReads([string]$path) {
    $tokens = $null; $errs = $null
    $tree = [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$errs)
    $reads = @($tree.FindAll({ param($n) $n -is [System.Management.Automation.Language.MemberExpressionAst] -and $n.Static -and "$($n.Member.Value)" -eq 'AllScreens' }, $true))
    [pscustomobject]@{ Errors = @($errs).Count; Lines = @($reads | % { $_.Extent.StartLineNumber }) }
  }
  # Control fixture: three real reads, on lines 1, 3 and 5 (a plain read, one inside a block, one through a variable type).
  $posFile = Join-Path $run 'scan-control.ps1'; $negFile = Join-Path $run 'scan-text.ps1'
  $posText = (@(
    '$plain = [System.Windows.Forms.Screen]::AllScreens',
    '$inside = @(',
    '  [System.Windows.Forms.Screen]::AllScreens',
    ')',
    '$t = [System.Windows.Forms.Screen]; $alias = $t::AllScreens'
  ) -join "`r`n")
  # Text fixture: no read. A comment (with a lone quote), a double-quoted and a single-quoted string, a here-string,
  # a multi-line string and a block comment all name AllScreens.
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
    '$ok = 1'
  ) -join "`r`n")
  [IO.File]::WriteAllText($posFile, $posText, $utf8); [IO.File]::WriteAllText($negFile, $negText, $utf8)
  $ctl = Get-AllScreensReads $posFile
  Check 'static control: the scanner finds the three real reads (lines 1, 3, 5)' (($ctl.Errors -eq 0) -and (($ctl.Lines -join ',') -eq '1,3,5')) "parse errors=$($ctl.Errors), read lines=$($ctl.Lines -join ',')"
  $txt = Get-AllScreensReads $negFile
  Check 'static control: a comment, strings, a here-string and a block comment naming AllScreens are no read' (($txt.Errors -eq 0) -and ($txt.Lines.Count -eq 0)) "parse errors=$($txt.Errors), read lines=$($txt.Lines -join ',')"
  $tileScan = Get-AllScreensReads $Tile
  Check 'static: tile.ps1 parses with no error' ($tileScan.Errors -eq 0) "$($tileScan.Errors) parse error(s) in tile.ps1"
  Check 'static: tile.ps1 reads no [Screen]::AllScreens (its live monitor list is a direct Win32 read)' ($tileScan.Lines.Count -eq 0) "AllScreens is read at line(s) $($tileScan.Lines -join ', ') of tile.ps1"

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
} catch {
  $script:fail++; "FAIL  run stopped: $_"
} finally {
  foreach ($k in $saved.Keys) { if ($null -eq $saved[$k]) { Remove-Item "env:$k" -ErrorAction SilentlyContinue } else { Set-Item "env:$k" $saved[$k] } }
  Remove-Item -LiteralPath $run -Recurse -Force -ErrorAction SilentlyContinue
}
if ($script:fail) { "$($script:fail) check(s) failed."; exit 1 } else { 'All checks passed.' }
