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
#   Monitor ids (case 6 on): each monitor carries id, builtin, maker, product, serial and idKind (the seam contract below). Case 6
#     checks the EDID parse and the id rule through the seam; case 7 checks -Monitors and the kept -Json fields; case 8 checks the
#     live ids (SKIP with no desktop); case 9 extends case 4 with main's tile.ps1 (5de673d), whose TileMon1 is the clash risk.
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
# Seam for monitor ids (cases 6 to 9). TILE_SCREENS_FILE entries may carry these fields as well:
#   id given (passthrough): id, builtin, maker, product, serial and idKind are copied to the monitor as given. Nothing is derived.
#   no id (derived): path (the device interface path \\?\DISPLAY#<maker+product>#<instance>#{guid}), edid (the EDID as hex) and
#     builtin (true = the machine's own panel) go through the same identity function the live read uses. A null or absent path
#     means no device: idKind size. maker and product come from the path; serial comes from the EDID.
#   outputTech (case 11): 8 hex digits, as the live read's Targets() prints them (the DISPLAYCONFIG output technology). An entry with
#     no builtin field is builtin for 80000000, 0000000B and 0000000D, and for no other value. A builtin field, when present, wins.
#     The live read classifies its own Targets() values with that same function.
#   Identity rule: id = <maker+product>-<serial>. serial is the text serial (the 0xFF descriptor, trimmed of its 0x0A and padding),
#     else bytes 12-15 as a decimal number when non-zero (idKind edid). Else, for a builtin screen, <maker+product>-builtin (idKind
#     builtin). Else <maker+product>-<UIDnnnn> (idKind port), UIDnnnn being the instance's last '&' segment. Else size-<bw>x<bh>
#     (idKind size), from the bounds, not the work area.
#   Descriptors: an EDID has four 18-byte blocks at 54, 72, 90 and 108. A monitor descriptor starts 00 00 00 <tag> 00 and holds 13
#     text bytes at block+5; the tag is at block+3. A timing block has a non-zero pixel clock in bytes 0-1 and is no descriptor,
#     whatever its byte 3.
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
  try { 'RESULT ' + ((& $Tile -Json -DryRun 3>$null | ? { "$_" -notmatch '^WARNING:' }) -join '') } catch { 'ERROR ' + $_.Exception.Message }
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
    $liveN = try { @((ConvertFrom-Json (((& powershell -NoProfile -ExecutionPolicy Bypass -File $Tile -Json -DryRun 3>$null)| ? { "$_" -notmatch '^WARNING:' }) -join '')).monitors).Count } catch { -1 }
    Check 'live: a -Json call counts the same monitors as a fresh EnumDisplayMonitors' ($liveN -eq $fresh[0]) "tile -Json counts $liveN monitor(s), EnumDisplayMonitors counts $($fresh[0])"
  }

  # ---- 4. Type clash: a base tile.ps1, then this one, in ONE process. Two bases: ed97406 (its class W has no Monitors) and 5de673d
  #      (this lane's base, which also defines TileMon1: serve.ps1 and tray.ps1 keep that class across calls). ----
  # This tile.ps1's W has Monitors, so in the ed97406 process its Add-Type meets the base's W. A changed TileMon1 meets 5de673d's.
  # A fresh process lists the live monitors. The base's own files come from git, into the run folder.
  Remove-Item env:TILE_SCREENS_FILE -ErrorAction SilentlyContinue
  # The helper: both calls in one process. Its answers: OLDTYPE (the base's W, with or without Monitors), OLDMON1 (the base's TileMon1),
  # NEW (this tile's -Json), NEWERR (its first errors).
  $clashText = @'
param([string]$Old, [string]$New)
$null = & $Old -Json -DryRun 3>$null 2>$null
$w = 'W' -as [type]
'OLDTYPE ' + $(if ($w -and -not $w.GetMethod('Monitors')) { 'no-Monitors' } else { 'other' })
'OLDMON1 ' + $(if ('TileMon1' -as [type]) { 'yes' } else { 'no' })
$Error.Clear()
'NEW ' + ((& $New -Json -DryRun 3>$null) -join '')
'NEWERR ' + (@($Error | Select-Object -First 2 | % { "$_" }) -join ' | ')
'@
  $clashFile = Join-Path $run 'clash-calls.ps1'; [IO.File]::WriteAllText($clashFile, $clashText, $utf8)
  $clashFresh = Invoke-PsChild "-File `"$Tile`" -Json -DryRun"
  $freshNames = Get-MonitorNames (@($clashFresh.Out -split "`r?`n" | ? { $_ -notmatch '^WARNING:' }) -join '')
  foreach ($base in 'ed97406', '5de673d') {
    $baseDir = Join-Path $run "base-$base"; New-Item -ItemType Directory -Force $baseDir | Out-Null
    Save-GitBlob "${base}:tile.ps1" (Join-Path $baseDir 'tile.ps1'); Save-GitBlob "${base}:config.ps1" (Join-Path $baseDir 'config.ps1')
    $clash = Invoke-PsChild "-File `"$clashFile`" -Old `"$(Join-Path $baseDir 'tile.ps1')`" -New `"$Tile`""
    $clashOut = @($clash.Out -split "`r?`n")
    $oldType = @($clashOut | ? { $_ -like 'OLDTYPE *' } | % { $_.Substring(8) })
    $oldMon1 = @($clashOut | ? { $_ -like 'OLDMON1 *' } | % { $_.Substring(8) })
    $newJson = @($clashOut | ? { $_ -like 'NEW *' } | % { $_.Substring(4) })
    $newErr = @($clashOut | ? { $_ -like 'NEWERR *' } | % { $_.Substring(7) })
    $scopeClash = ($oldType.Count -eq 1 -and $oldType[0] -eq 'no-Monitors') -and (($base -ne '5de673d') -or ($oldMon1.Count -eq 1 -and $oldMon1[0] -eq 'yes'))
    if (-not $scopeClash) {
      Check "type clash ($base): scope: the base run left its own classes in the process" $false "OLDTYPE answer: $($oldType -join ' '); OLDMON1 answer: $($oldMon1 -join ' '); base run stderr: $($clash.Err.Trim())"
    } elseif ($freshNames -eq '') {
      "SKIP  type clash ($base): no desktop session (a fresh process lists no monitor), so the same-process list is not compared"
    } else {
      $newNames = if ($newJson.Count -eq 0) { '(no result)' } else { Get-MonitorNames $newJson[0] }
      Check "type clash ($base): -Json after the base tile.ps1 in the same process lists the live monitors, as a fresh process does" ($newNames -eq $freshNames) "same process lists [$newNames], a fresh process lists [$freshNames]; first error: $(@($newErr)[0])"
      $newMons = @(); try { $newMons = @((ConvertFrom-Json $newJson[0]).monitors | % { $_ }) } catch { }
      $newNoId = @($newMons | ? { -not $_.id } | % { [string]$_.name })
      Check "type clash ($base): the same-process -Json gives every monitor an id" (($newMons.Count -gt 0) -and ($newNoId.Count -eq 0)) "monitors: $($newMons.Count); no id on: [$($newNoId -join ', ')]"
    }
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
      $r = Invoke-PsChild "-File `"$Tile`" -Json -DryRun" @{ TILE_SCREENS_FILE = $bad[1] }
      $shown = $r.Out.Trim(); $shown = $shown.Substring(0, [Math]::Min(80, $shown.Length))
      Check "bad seam ($($bad[0])): tile.ps1 -Json exits non-zero" ($r.Code -ne 0) "exit $($r.Code) on a bad seam file; stdout starts: $shown"
    }
  }
  # ---- 6. Monitor ids through the seam. The hardware is invented (maker TST, products 1001 to 7007): no owner panel is in the repo. ----
  Remove-Item env:TILE_SCREENS_FILE -ErrorAction SilentlyContinue
  function Get-DisplayPath([string]$hw, [string]$uid) { '\\?\DISPLAY#' + $hw + '#5&1a2b3c4d&0&' + $uid + '#{e6f07b5f-ee97-4a90-b076-33f57bf4eaa7}' }
  function New-SeamEntry([string]$name, [int]$x, [int]$bw, [int]$bh, $path = $null, $edid = $null, [bool]$builtin = $false, $tech = $null) {
    # The work area is 40 px shorter than the bounds, so a reader that uses the wrong size fails the size case.
    # $tech sets outputTech instead of builtin, so the entry has no builtin field and the classifier decides.
    $e = [pscustomobject]@{ name = $name; x = $x; y = 0; w = $bw; h = $bh - 40; bw = $bw; bh = $bh; path = $path; edid = $edid }
    if ($null -ne $tech) { $e | Add-Member -NotePropertyName outputTech -NotePropertyValue $tech } else { $e | Add-Member -NotePropertyName builtin -NotePropertyValue $builtin }
    $e
  }
  function Set-EdidBlock([byte[]]$bytes, [int]$off, [byte]$tag, [string]$text = $null) {
    $blk = New-Object byte[] 18
    $blk[3] = $tag
    if ($null -ne $text) {
      $t = [Text.Encoding]::ASCII.GetBytes($text)
      [Array]::Copy($t, 0, $blk, 5, $t.Length)
      if ($t.Length -lt 13) { $blk[5 + $t.Length] = 0x0A; for ($k = 6 + $t.Length; $k -lt 18; $k++) { $blk[$k] = 0x20 } }
    }
    [Array]::Copy($blk, 0, $bytes, $off, 18)
  }
  # A 128-byte EDID 1.4 as hex. $product: 4 hex digits (bytes 10-11, little-endian). $number: bytes 12-15, little-endian.
  # $text: the 0xFF serial, in the block at $textAt (90 or 108); null = no text serial.
  function New-EdidHex([string]$maker, [string]$product, [uint32]$number = 0, [string]$text = $null, [int]$textAt = 108) {
    $b = New-Object byte[] 128
    [Array]::Copy([byte[]](0, 255, 255, 255, 255, 255, 255, 0), 0, $b, 0, 8)
    $m = (([int][char]$maker[0] - 64) -shl 10) -bor (([int][char]$maker[1] - 64) -shl 5) -bor ([int][char]$maker[2] - 64)
    $b[8] = [byte](($m -shr 8) -band 0xFF); $b[9] = [byte]($m -band 0xFF)
    $p = [Convert]::ToInt32($product, 16)
    $b[10] = [byte]($p -band 0xFF); $b[11] = [byte](($p -shr 8) -band 0xFF)
    for ($k = 0; $k -lt 4; $k++) { $b[12 + $k] = [byte](([uint32]$number -shr (8 * $k)) -band 0xFF) }
    $b[16] = 1; $b[17] = 30; $b[18] = 1; $b[19] = 4; $b[20] = 0x80
    # 54: a timing block (non-zero pixel clock) whose byte 3 is 0xFF. 72: a 0xFC name. 90 and 108: the serial, or a dummy (tag 0x10).
    [Array]::Copy([byte[]](0x02, 0x3A, 0x80, 0xFF, 0x70, 0x38, 0x2D, 0x40, 0x58, 0x2C, 0x45, 0x00, 0xF4, 0x19, 0x11, 0x00, 0x00, 0x1E), 0, $b, 54, 18)
    Set-EdidBlock $b 72 0xFC 'TEST PANEL'
    foreach ($off in 90, 108) { if ($null -ne $text -and $off -eq $textAt) { Set-EdidBlock $b $off 0xFF $text } else { Set-EdidBlock $b $off 0x10 } }
    $sum = 0; for ($k = 0; $k -lt 127; $k++) { $sum += $b[$k] }
    $b[127] = [byte]((256 - ($sum % 256)) % 256)
    [BitConverter]::ToString($b).Replace('-', '')
  }
  # One -Json or -Monitors child with a seam: its exit code, stdout (warnings dropped, trimmed), parsed JSON or $null, and stderr.
  function Get-SeamRun([string]$argLine, [hashtable]$envSet) {
    $r = Invoke-PsChild $argLine $envSet
    $text = (@($r.Out -split "`r?`n" | ? { $_ -notmatch '^WARNING:' }) -join '').Trim()
    $doc = $null; $ok = $false
    try { $doc = $text | ConvertFrom-Json -ErrorAction Stop; $ok = $true } catch { }
    [pscustomobject]@{ Code = $r.Code; Text = $text; Doc = $doc; Json = $ok; Err = $r.Err.Trim() }
  }
  $edidS1 = New-EdidHex 'TST' '1001' 555000111 'TESTSNA1' 90   # a text serial beside a non-zero number: the text wins
  $edidS2 = New-EdidHex 'TST' '2002' 0 'TESTSNB2' 108          # a text serial alone, with its 0x0A and padding
  $edidS3 = New-EdidHex 'TST' '3003'                            # builtin: no text serial, number 0
  $edidN1 = New-EdidHex 'TST' '5005' 123456789                  # a number alone
  $edidF1 = New-EdidHex 'TST' '7007' 0 'ABCDEFGHIJKLM' 108     # a 13-character text serial, no 0x0A
  $edidP1 = New-EdidHex 'TST' '6006'                            # neither a text serial nor a number
  $seamS1 = New-SeamEntry 'SEAM-S1' 0 3440 1440 (Get-DisplayPath 'TST1001' 'UID4352') $edidS1 $false
  $seamS2 = New-SeamEntry 'SEAM-S2' 3440 1080 1920 (Get-DisplayPath 'TST2002' 'UID4353') $edidS2 $false
  $seamS3 = New-SeamEntry 'SEAM-S3' 4520 1920 1200 (Get-DisplayPath 'TST3003' 'UID4354') $edidS3 $true
  $seamN1 = New-SeamEntry 'SEAM-N1' 6440 1920 1080 (Get-DisplayPath 'TST5005' 'UID4355') $edidN1 $false
  $seamF1 = New-SeamEntry 'SEAM-F1' 8360 1920 1080 (Get-DisplayPath 'TST7007' 'UID4356') $edidF1 $false
  $seamP1 = New-SeamEntry 'SEAM-P1' 10280 1920 1080 (Get-DisplayPath 'TST6006' 'UID4358') $edidP1 $false
  $seamP2 = New-SeamEntry 'SEAM-P2' 12200 1920 1080 (Get-DisplayPath 'TST6006' 'UID4359') $edidP1 $false
  $seamZ1 = New-SeamEntry 'SEAM-Z1' 14120 1920 1080
  $seamPT = [pscustomobject]@{ name = 'SEAM-PT1'; x = 16040; y = 0; w = 1920; h = 1040; bw = 1920; bh = 1080; id = 'GIVEN-ID-1'; builtin = $false; maker = 'GIV'; product = 'EN01'; serial = 'GIVENSER'; idKind = 'edid' }
  # The same hardware in another order, with other names and positions (for the order case): SEAM-A is S3, SEAM-C is S1, SEAM-B is S2.
  $movedS3 = New-SeamEntry 'SEAM-A' 0 1920 1200 (Get-DisplayPath 'TST3003' 'UID4354') $edidS3 $true
  $movedS1 = New-SeamEntry 'SEAM-C' 2000 3440 1440 (Get-DisplayPath 'TST1001' 'UID4352') $edidS1 $false
  $movedS2 = New-SeamEntry 'SEAM-B' 5440 1080 1920 (Get-DisplayPath 'TST2002' 'UID4353') $edidS2 $false
  $nineFile = Join-Path $run 'ids-nine.json'; $threeFile = Join-Path $run 'ids-three.json'; $movedFile = Join-Path $run 'ids-moved.json'
  [IO.File]::WriteAllText($nineFile, (ConvertTo-Json -InputObject @($seamS1, $seamS2, $seamS3, $seamN1, $seamF1, $seamP1, $seamP2, $seamZ1, $seamPT) -Depth 4 -Compress), $utf8)
  [IO.File]::WriteAllText($threeFile, (ConvertTo-Json -InputObject @($seamS1, $seamS2, $seamS3) -Depth 4 -Compress), $utf8)
  [IO.File]::WriteAllText($movedFile, (ConvertTo-Json -InputObject @($movedS3, $movedS1, $movedS2) -Depth 4 -Compress), $utf8)

  # The nine seam monitors, one -Json call. Scope first: the right names are listed; then the subject, the ids.
  $ra = Get-SeamRun "-File `"$Tile`" -Json -DryRun" @{ TILE_SCREENS_FILE = $nineFile }
  $rmon = @($ra.Doc.monitors | % { $_ })
  $nineNames = (@($rmon | % { [string]$_.name }) | Sort-Object) -join ','
  $wantNine = (@('SEAM-S1', 'SEAM-S2', 'SEAM-S3', 'SEAM-N1', 'SEAM-F1', 'SEAM-P1', 'SEAM-P2', 'SEAM-Z1', 'SEAM-PT1') | Sort-Object) -join ','
  $scopeNine = $nineNames -eq $wantNine
  Check 'ids: scope: the seam run lists the nine seam monitors, by name' $scopeNine "lists [$nineNames], wanted [$wantNine]; exit $($ra.Code); stderr: $($ra.Err)"
  if ($scopeNine) {
    $by = @{}; foreach ($x in $rmon) { $by[[string]$x.name] = $x }
    $s1 = $by['SEAM-S1']; $s2 = $by['SEAM-S2']; $s3 = $by['SEAM-S3']; $n1 = $by['SEAM-N1']; $f1 = $by['SEAM-F1']
    $p1 = $by['SEAM-P1']; $p2 = $by['SEAM-P2']; $z1 = $by['SEAM-Z1']; $pt = $by['SEAM-PT1']
    Check 'passthrough: an entry with an id is listed as given (id, maker, product, serial, idKind): SEAM-PT1' ($pt.id -eq 'GIVEN-ID-1' -and $pt.maker -eq 'GIV' -and $pt.product -eq 'EN01' -and $pt.serial -eq 'GIVENSER' -and $pt.idKind -eq 'edid') "id '$($pt.id)', maker '$($pt.maker)', product '$($pt.product)', serial '$($pt.serial)', idKind '$($pt.idKind)'"
    Check 'parser: a text serial beats a non-zero number: SEAM-S1 serial is TESTSNA1' ($s1.serial -eq 'TESTSNA1') "serial is '$($s1.serial)'"
    Check 'parser: a text serial in the last block is read, trimmed of its 0x0A and padding: SEAM-S2 serial is TESTSNB2' ($s2.serial -eq 'TESTSNB2') "serial is '$($s2.serial)'"
    Check 'parser: a number alone is the serial, in decimal, idKind edid: SEAM-N1 serial is 123456789' ($n1.serial -eq '123456789' -and $n1.idKind -eq 'edid') "serial '$($n1.serial)', idKind '$($n1.idKind)'"
    Check 'parser: a 13-character text serial with no 0x0A is read whole: SEAM-F1 serial is ABCDEFGHIJKLM' ($f1.serial -eq 'ABCDEFGHIJKLM') "serial is '$($f1.serial)'"
    # Empty alone is no claim (a monitor with no serial field reads as empty too), so the case also needs the port fallback to have run.
    Check 'parser: neither a text serial nor a number: SEAM-P1 serial is empty and idKind is port' ((-not $p1.serial) -and $p1.idKind -eq 'port') "serial '$($p1.serial)', idKind '$($p1.idKind)'"
    Check 'id rule: a text serial gives <maker+product>-<serial>: SEAM-S1 TST1001-TESTSNA1, SEAM-S2 TST2002-TESTSNB2' ($s1.id -eq 'TST1001-TESTSNA1' -and $s2.id -eq 'TST2002-TESTSNB2') "ids are '$($s1.id)' and '$($s2.id)'"
    Check 'id rule: a builtin screen with no serial gives <maker+product>-builtin, builtin true, idKind builtin: SEAM-S3' ($s3.id -eq 'TST3003-builtin' -and $s3.builtin -eq $true -and $s3.idKind -eq 'builtin') "id '$($s3.id)', builtin '$($s3.builtin)', idKind '$($s3.idKind)'"
    $builtinNames = @($rmon | ? { $_.builtin -eq $true } | % { [string]$_.name })
    Check 'id rule: SEAM-S3 is the only builtin monitor' (($builtinNames -join ',') -eq 'SEAM-S3') "builtin monitors: [$($builtinNames -join ', ')]"
    Check 'id rule: a number gives <maker+product>-<decimal>: SEAM-N1 TST5005-123456789' ($n1.id -eq 'TST5005-123456789') "id is '$($n1.id)'"
    Check 'id rule: a 13-character text serial gives the whole serial: SEAM-F1 TST7007-ABCDEFGHIJKLM' ($f1.id -eq 'TST7007-ABCDEFGHIJKLM') "id is '$($f1.id)'"
    Check 'id rule: two identical monitors with no serial get ids by port: SEAM-P1 TST6006-UID4358, SEAM-P2 TST6006-UID4359' ($p1.id -eq 'TST6006-UID4358' -and $p2.id -eq 'TST6006-UID4359' -and $p1.idKind -eq 'port' -and $p2.idKind -eq 'port') "ids '$($p1.id)' and '$($p2.id)', idKinds '$($p1.idKind)' and '$($p2.idKind)'"
    Check 'id rule: a monitor with no device path gives size-<bw>x<bh> from its bounds, idKind size: SEAM-Z1' ($z1.id -eq 'size-1920x1080' -and $z1.idKind -eq 'size') "id '$($z1.id)', idKind '$($z1.idKind)'"
    Check 'id fields: maker and product come from the device path: SEAM-S1 TST and 1001' ($s1.maker -eq 'TST' -and $s1.product -eq '1001') "maker '$($s1.maker)', product '$($s1.product)'"
  }

  # Same process, three -Json calls, the seam file rewritten between them (the case 2 helper): call 2 repeats call 1's list, and
  # call 3 has the same hardware in another order, with other names and positions. The ids follow the hardware, not the list.
  $idRun = @(& powershell -NoProfile -ExecutionPolicy Bypass -File $seamFile -Tile $Tile -Screens $screensFile -First $threeFile -Second $threeFile -Third $movedFile)
  $calls = @($idRun | ? { "$_" -like 'RESULT *' } | % { "$_".Substring(7) })
  function Get-IdMap([string]$json) { $h = @{}; try { foreach ($x in @((ConvertFrom-Json $json).monitors | % { $_ })) { $h[[string]$x.name] = [string]$x.id } } catch { }; $h }
  $ids1 = if ($calls.Count -ge 1) { Get-IdMap $calls[0] } else { @{} }
  $ids2 = if ($calls.Count -ge 2) { Get-IdMap $calls[1] } else { @{} }
  $ids3 = if ($calls.Count -ge 3) { Get-IdMap $calls[2] } else { @{} }
  $scopeRun = ($calls.Count -eq 3) -and ($ids1.Count -eq 3) -and ($ids2.Count -eq 3) -and ($ids3.Count -eq 3)
  Check 'ids: scope: three calls in one process each list three monitors' $scopeRun "results: $($calls.Count); names in call 1: [$(@($ids1.Keys) -join ', ')]; call 3: [$(@($ids3.Keys) -join ', ')]; errors: $(@($idRun | ? { "$_" -like 'ERROR *' }) -join ' / ')"
  if ($scopeRun) {
    $noId1 = @($ids1.Keys | ? { -not $ids1[$_] })
    Check 'ids: call 1 gives every monitor a non-empty id' ($noId1.Count -eq 0) "no id on: $($noId1 -join ', ')"
    if ($noId1.Count -eq 0) {
      $map1 = (@($ids1.Keys | Sort-Object | % { "$_=$($ids1[$_])" })) -join ';'
      $map2 = (@($ids2.Keys | Sort-Object | % { "$_=$($ids2[$_])" })) -join ';'
      Check 'ids: call 2, same process and same list, gives the same ids as call 1' ($map1 -eq $map2) "call 1: $map1; call 2: $map2"
      $moved = @{ 'SEAM-A' = 'SEAM-S3'; 'SEAM-C' = 'SEAM-S1'; 'SEAM-B' = 'SEAM-S2' }
      $diff = @($moved.Keys | ? { $ids3[$_] -ne $ids1[$moved[$_]] } | % { "$_ is '$($ids3[$_])', wanted '$($ids1[$moved[$_]])'" })
      Check 'ids: call 3, with names, order and positions changed for the same hardware, keeps each id' ($diff.Count -eq 0) ($diff -join '; ')
    }
  }
  # ---- 7. -Monitors prints only the monitors (the same objects -Json lists); -Json keeps role and its fields and gains the six id fields. ----
  function Get-MonKey($o) { (@($o.PSObject.Properties | Sort-Object Name | % { "$($_.Name)=$($_.Value)" }) -join ';') }
  $threeRun = Get-SeamRun "-File `"$Tile`" -Json -DryRun" @{ TILE_SCREENS_FILE = $threeFile }
  $tmon = @($threeRun.Doc.monitors | % { $_ })
  $threeNames = (@($tmon | % { [string]$_.name }) | Sort-Object) -join ','
  $scopeThree = $threeNames -eq 'SEAM-S1,SEAM-S2,SEAM-S3'
  Check 'json: scope: the three seam monitors are listed by name' $scopeThree "lists [$threeNames]; exit $($threeRun.Code); stderr: $($threeRun.Err)"
  if ($scopeThree) {
    $tb = @{}; foreach ($x in $tmon) { $tb[[string]$x.name] = $x }
    Check 'json keeps role: SEAM-S1 wide, SEAM-S2 tall, SEAM-S3 laptop' ($tb['SEAM-S1'].role -eq 'wide' -and $tb['SEAM-S2'].role -eq 'tall' -and $tb['SEAM-S3'].role -eq 'laptop') "roles: S1 '$($tb['SEAM-S1'].role)', S2 '$($tb['SEAM-S2'].role)', S3 '$($tb['SEAM-S3'].role)'"
    $oldFields = @('name', 'role', 'x', 'y', 'w', 'h', 'bw', 'bh')
    $noOld = @($tmon | % { $o = $_; $oldFields | ? { $o.PSObject.Properties.Name -notcontains $_ } })
    Check 'json keeps the existing monitor fields and the windows list' (($noOld.Count -eq 0) -and ($threeRun.Text -match '"windows":')) "missing fields: [$($noOld -join ', ')]; windows list present: $($threeRun.Text -match '"windows":')"
    $idFields = @('id', 'builtin', 'maker', 'product', 'serial', 'idKind')
    $noId = @($tmon | % { $o = $_; $idFields | ? { $o.PSObject.Properties.Name -notcontains $_ } })
    Check 'json: every monitor carries id, builtin, maker, product, serial and idKind' ($noId.Count -eq 0) "missing fields: [$($noId -join ', ')]"
  }

  # -DryRun and a -Proc no app matches on every -Monitors call: a tile.ps1 without the switch must not place or move a real window.
  $mrun = Get-SeamRun "-File `"$Tile`" -Monitors -DryRun -Proc no-app-matches-this-test" @{ TILE_SCREENS_FILE = $threeFile }
  $monArray = $mrun.Text.StartsWith('[') -and $mrun.Json
  Check 'monitors: scope: -Monitors prints one JSON array of monitors' $monArray "exit $($mrun.Code); stdout starts '$($mrun.Text.Substring(0, [Math]::Min(40, $mrun.Text.Length)))'; stderr: $($mrun.Err)"
  if ($monArray -and $scopeThree) {
    $mm = @($mrun.Doc | % { $_ })
    Check 'monitors: prints only the monitors: no windows list in its output' ($mrun.Text -notmatch '"windows"') "output has a windows list"
    $jk = @{}; foreach ($x in $tmon) { $jk[[string]$x.name] = Get-MonKey $x }
    $mk = @{}; foreach ($x in $mm) { $mk[[string]$x.name] = Get-MonKey $x }
    $sameObjects = ($mk.Count -eq 3) -and ((@($jk.Keys | Sort-Object) -join ',') -eq (@($mk.Keys | Sort-Object) -join ',')) -and (@($jk.Keys | ? { $jk[$_] -ne $mk[$_] }).Count -eq 0)
    Check 'monitors: the same monitor objects as -Json (same fields and values, by name)' $sameObjects "-Json: $(@($jk.Values) -join ' | '); -Monitors: $(@($mk.Values) -join ' | ')"
  }

  $emptyFile = Join-Path $run 'ids-empty.json'; [IO.File]::WriteAllText($emptyFile, '[]', $utf8)
  $erun = Get-SeamRun "-File `"$Tile`" -Monitors -DryRun -Proc no-app-matches-this-test" @{ TILE_SCREENS_FILE = $emptyFile }
  Check 'monitors: no monitor prints an empty JSON array' ($erun.Text -eq '[]') "stdout '$($erun.Text)'; exit $($erun.Code); stderr: $($erun.Err)"

  # Green control, passes on the old code: -Monitor keeps binding once -Monitors exists (an exact name wins over a prefix).
  $ctl = Invoke-PsChild "-File `"$Tile`" -From `"$(Join-Path $PSScriptRoot 'fixture.json')`" -Monitor laptop -DryRun"
  Check 'control: -Monitor laptop still binds: the fixture dry run exits 0' ($ctl.Code -eq 0) "exit $($ctl.Code): $($ctl.Err.Trim())"
  # ---- 8. Live ids: with no seam, every live monitor has an id, and at most one is builtin (a desktop PC has none). SKIP with no desktop. ----
  Remove-Item env:TILE_SCREENS_FILE -ErrorAction SilentlyContinue
  if (-not $interactive -or $fresh.Count -eq 0 -or $fresh[0] -lt 1) {
    'SKIP  live ids: no desktop session (EnumDisplayMonitors found no monitor), so the live ids are not read'
  } else {
    $lv = Get-SeamRun "-File `"$Tile`" -Json -DryRun" @{}
    $lvMon = @($lv.Doc.monitors | % { $_ })
    $scopeLive = $lvMon.Count -eq $fresh[0]
    Check 'live ids: scope: -Json lists every live monitor that EnumDisplayMonitors finds' $scopeLive "-Json lists $($lvMon.Count), EnumDisplayMonitors finds $($fresh[0]); exit $($lv.Code); stderr: $($lv.Err)"
    if ($scopeLive) {
      $lvNoId = @($lvMon | ? { -not $_.id } | % { [string]$_.name })
      Check 'live ids: every live monitor has a non-empty id' ($lvNoId.Count -eq 0) "no id on: [$($lvNoId -join ', ')]"
      $lvBuiltin = @($lvMon | ? { $_.builtin -eq $true })
      Check 'live ids: at most one live monitor is builtin' ($lvBuiltin.Count -le 1) "builtin monitors: $($lvBuiltin.Count) of $($lvMon.Count)"
    }
  }

  # ---- 10. One monitor: -Json lists monitors in a JSON array, as -Monitors and main's tile.ps1 (5de673d) do. ----
  $oneFile = Join-Path $run 'ids-one.json'
  [IO.File]::WriteAllText($oneFile, (ConvertTo-Json -InputObject @(New-SeamEntry 'SEAM-ONE' 0 1920 1080) -Depth 4 -Compress), $utf8)
  $r10 = Get-SeamRun "-File `"$Tile`" -Json -DryRun" @{ TILE_SCREENS_FILE = $oneFile }
  $names10 = (@($r10.Doc.monitors | % { [string]$_.name }) | Sort-Object) -join ','
  Check 'one monitor: scope: -Json lists SEAM-ONE' ($names10 -eq 'SEAM-ONE') "lists [$names10]; exit $($r10.Code); stderr: $($r10.Err)"
  Check 'one monitor: -Json gives monitors as a JSON array of one, not a bare object' (($r10.Json) -and ($r10.Doc.monitors -is [System.Array]) -and (@($r10.Doc.monitors).Count -eq 1)) "monitors is a $(if ($r10.Doc.monitors) { $r10.Doc.monitors.GetType().Name } else { 'null' }); exit $($r10.Code)"
  # Green controls: three monitors already give an array, -Monitors gives one as an array, and main's tile.ps1 gives one as an array.
  Check 'one monitor: control: -Json with three monitors gives monitors as a JSON array of three' (($threeRun.Doc.monitors -is [System.Array]) -and (@($threeRun.Doc.monitors).Count -eq 3)) "monitors is a $(if ($threeRun.Doc.monitors) { $threeRun.Doc.monitors.GetType().Name } else { 'null' }); exit $($threeRun.Code)"
  $oneMon = Get-SeamRun "-File `"$Tile`" -Monitors -DryRun -Proc no-app-matches-this-test" @{ TILE_SCREENS_FILE = $oneFile }
  Check 'one monitor: control: -Monitors prints one monitor inside a JSON array' ($oneMon.Json -and $oneMon.Text.StartsWith('[') -and (@($oneMon.Doc).Count -eq 1)) "stdout starts '$($oneMon.Text.Substring(0, [Math]::Min(40, $oneMon.Text.Length)))'; exit $($oneMon.Code)"
  $mainOne = Invoke-PsChild "-File `"$(Join-Path $run 'base-5de673d\tile.ps1')`" -Json -DryRun" @{ TILE_SCREENS_FILE = $oneFile }
  $mainOneText = (@($mainOne.Out -split "`r?`n" | ? { $_ -notmatch '^WARNING:' }) -join '').Trim()
  $mainOneDoc = $null; try { $mainOneDoc = $mainOneText | ConvertFrom-Json -ErrorAction Stop } catch { }
  Check 'one monitor: control: main (5de673d) with the same one-monitor seam gives monitors as a JSON array of one' (($mainOneDoc.monitors -is [System.Array]) -and (@($mainOneDoc.monitors).Count -eq 1)) "main's monitors is a $(if ($mainOneDoc -and $mainOneDoc.monitors) { $mainOneDoc.monitors.GetType().Name } else { 'missing' }); exit $($mainOne.Code)"
  # ---- 11. The machine's own panel by output technology, through the seam's outputTech (contract in the header). ----
  # 0000000B (embedded DisplayPort), 0000000D (UDI embedded) and 80000000 (internal) make the built-in panel. The controls are
  # 0000000A (DisplayPort) and 00000005 (HDMI), which stay external. 80000000 is a guard: the live read already counts it.
  $techFile = Join-Path $run 'ids-tech.json'
  $techList = @(
    (New-SeamEntry 'SEAM-T11' 0 1920 1080 (Get-DisplayPath 'TST9011' 'UID4370') $null -tech '0000000B'),
    (New-SeamEntry 'SEAM-T13' 1920 1920 1080 (Get-DisplayPath 'TST9013' 'UID4371') $null -tech '0000000D'),
    (New-SeamEntry 'SEAM-TI' 3840 1920 1080 (Get-DisplayPath 'TST9080' 'UID4372') $null -tech '80000000'),
    (New-SeamEntry 'SEAM-TD' 5760 1920 1080 (Get-DisplayPath 'TST9010' 'UID4373') $null -tech '0000000A'),
    (New-SeamEntry 'SEAM-TH' 7680 1920 1080 (Get-DisplayPath 'TST9005' 'UID4374') $null -tech '00000005')
  )
  [IO.File]::WriteAllText($techFile, (ConvertTo-Json -InputObject $techList -Depth 4 -Compress), $utf8)
  $rt = Get-SeamRun "-File `"$Tile`" -Json -DryRun" @{ TILE_SCREENS_FILE = $techFile }
  $byT = @{}; foreach ($x in @($rt.Doc.monitors | % { $_ })) { $byT[[string]$x.name] = $x }
  $namesT = (@($byT.Keys | Sort-Object)) -join ','
  $wantT = (@('SEAM-T11', 'SEAM-T13', 'SEAM-TI', 'SEAM-TD', 'SEAM-TH') | Sort-Object) -join ','
  $scopeT = ($rt.Json) -and ($namesT -eq $wantT)
  Check 'output technology: scope: -Json lists the five SEAM-T monitors, by name' $scopeT "lists [$namesT], wanted [$wantT]; exit $($rt.Code); stderr: $($rt.Err)"
  if ($scopeT) {
    Check 'output technology: 0000000B (embedded DisplayPort) makes SEAM-T11 the built-in panel: builtin true, id TST9011-builtin' ($byT['SEAM-T11'].builtin -eq $true -and $byT['SEAM-T11'].id -eq 'TST9011-builtin' -and $byT['SEAM-T11'].idKind -eq 'builtin') "builtin '$($byT['SEAM-T11'].builtin)', id '$($byT['SEAM-T11'].id)', idKind '$($byT['SEAM-T11'].idKind)'"
    Check 'output technology: 0000000D (UDI embedded) makes SEAM-T13 the built-in panel: builtin true, id TST9013-builtin' ($byT['SEAM-T13'].builtin -eq $true -and $byT['SEAM-T13'].id -eq 'TST9013-builtin' -and $byT['SEAM-T13'].idKind -eq 'builtin') "builtin '$($byT['SEAM-T13'].builtin)', id '$($byT['SEAM-T13'].id)', idKind '$($byT['SEAM-T13'].idKind)'"
    Check 'output technology: 80000000 (internal) makes SEAM-TI the built-in panel: builtin true, id TST9080-builtin' ($byT['SEAM-TI'].builtin -eq $true -and $byT['SEAM-TI'].id -eq 'TST9080-builtin' -and $byT['SEAM-TI'].idKind -eq 'builtin') "builtin '$($byT['SEAM-TI'].builtin)', id '$($byT['SEAM-TI'].id)', idKind '$($byT['SEAM-TI'].idKind)'"
    Check 'output technology: control: 0000000A (DisplayPort) is not the built-in panel: SEAM-TD is builtin false, id TST9010-UID4373' ($byT['SEAM-TD'].builtin -eq $false -and $byT['SEAM-TD'].id -eq 'TST9010-UID4373' -and $byT['SEAM-TD'].idKind -eq 'port') "builtin '$($byT['SEAM-TD'].builtin)', id '$($byT['SEAM-TD'].id)', idKind '$($byT['SEAM-TD'].idKind)'"
    Check 'output technology: control: 00000005 (HDMI) is not the built-in panel: SEAM-TH is builtin false, id TST9005-UID4374' ($byT['SEAM-TH'].builtin -eq $false -and $byT['SEAM-TH'].id -eq 'TST9005-UID4374' -and $byT['SEAM-TH'].idKind -eq 'port') "builtin '$($byT['SEAM-TH'].builtin)', id '$($byT['SEAM-TH'].id)', idKind '$($byT['SEAM-TH'].idKind)'"
  }
  # ---- 12. Two monitors that derive the same id (the same maker, product and EDID serial): each id gets its instance UID appended.
  #      SEAM-K3 has the same maker and product but its own serial, so its id is the control and must not change.
  $edidK = New-EdidHex 'TST' '8008' 0 'SAMESER3' 90
  $edidO = New-EdidHex 'TST' '8008' 0 'OTHERSER4' 90
  $collFile = Join-Path $run 'ids-collide.json'
  $collList = @(
    (New-SeamEntry 'SEAM-K1' 0 1920 1080 (Get-DisplayPath 'TST8008' 'UID4360') $edidK),
    (New-SeamEntry 'SEAM-K2' 1920 1920 1080 (Get-DisplayPath 'TST8008' 'UID4361') $edidK),
    (New-SeamEntry 'SEAM-K3' 3840 1920 1080 (Get-DisplayPath 'TST8008' 'UID4362') $edidO)
  )
  [IO.File]::WriteAllText($collFile, (ConvertTo-Json -InputObject $collList -Depth 4 -Compress), $utf8)
  $rc = Get-SeamRun "-File `"$Tile`" -Json -DryRun" @{ TILE_SCREENS_FILE = $collFile }
  $byK = @{}; foreach ($x in @($rc.Doc.monitors | % { $_ })) { $byK[[string]$x.name] = $x }
  $namesK = (@($byK.Keys | Sort-Object)) -join ','
  $scopeK = ($rc.Json) -and ($namesK -eq 'SEAM-K1,SEAM-K2,SEAM-K3')
  Check 'collide: scope: -Json lists the three SEAM-K monitors, by name' $scopeK "lists [$namesK]; exit $($rc.Code); stderr: $($rc.Err)"
  if ($scopeK) {
    Check 'collide: colliding ids get the instance UID appended: SEAM-K1 TST8008-SAMESER3-UID4360, SEAM-K2 TST8008-SAMESER3-UID4361' ($byK['SEAM-K1'].id -eq 'TST8008-SAMESER3-UID4360' -and $byK['SEAM-K2'].id -eq 'TST8008-SAMESER3-UID4361') "ids are '$($byK['SEAM-K1'].id)' and '$($byK['SEAM-K2'].id)'"
    Check 'collide: control: the colliding monitors keep idKind edid' ($byK['SEAM-K1'].idKind -eq 'edid' -and $byK['SEAM-K2'].idKind -eq 'edid') "idKinds are '$($byK['SEAM-K1'].idKind)' and '$($byK['SEAM-K2'].idKind)'"
    Check 'collide: control: a monitor whose id does not collide keeps it: SEAM-K3 TST8008-OTHERSER4' ($byK['SEAM-K3'].id -eq 'TST8008-OTHERSER4') "id is '$($byK['SEAM-K3'].id)'"
  }
} catch {
  $script:fail++; "FAIL  run stopped: $_"
} finally {
  foreach ($k in $saved.Keys) { if ($null -eq $saved[$k]) { Remove-Item "env:$k" -ErrorAction SilentlyContinue } else { Set-Item "env:$k" $saved[$k] } }
  Remove-Item -LiteralPath $run -Recurse -Force -ErrorAction SilentlyContinue
}
if ($script:fail) { "$($script:fail) check(s) failed."; exit 1 } else { 'All checks passed.' }
