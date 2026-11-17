# Checks for the live-move guard in tile.ps1. Under the suite (TILE_TEST_SUITE=1, which test\run.ps1 sets for its children), a run that
# moves windows is refused unless the caller names TILE_TEST_ALLOW_LIVE=1. The refusal exits non-zero, names TILE_TEST_ALLOW_LIVE, and
# comes before any pass (no 'Grid' line). What the builder meets:
#   TILE_TEST_SUITE=1: the suite. Exempt from the refusal: -DryRun, -From, -Monitors, -List (it returns before any Move-Win), a dot-source with -Lib, and -Json only as the
#     bare snapshot (no -Scene, -Default, -Place or -PlaceFile: with those, -Json still moves windows unless -DryRun is set).
#   TILE_TEST_ALLOW_LIVE=1: the caller accepts a live run. Unset, or any other value, is refused.
# Cases. Red means it fails on 656a8cf for the named cause. Green means a control that holds on 656a8cf and must keep holding.
#   Scope (green): a probe child shows which seam vars reached it; the bare snapshot lists no window named tile-test-no-such-app.
#   1 refusal (red): under the suite, a flagless -Scene, -PlaceFile, bare -Monitor, -Scene -Json or -PlaceFile -Json run is refused.
#   2 controls (green): -DryRun, bare -Json, -Monitors, -List, -From and a -Lib dot-source still run under the suite.
#   3 opt-in (green): TILE_TEST_ALLOW_LIVE=1 lets a flagless -Scene run.
#   4 outside the suite (green): with no suite var, a flagless -Scene is not refused.
#   5 seam (red): test\run.ps1 sets TILE_TEST_SUITE=1 for its children.
#   6 run folders (green): the sweep removes a run folder older than a day and keeps a newer one (test-temp-standard).
# Every flagless run names a scene or spec that matches no open window (tile-test-no-such-app), and the scope check proves no
# open window has that app name. So no flagless run can move a window on any code.
# Each child's env is set or stripped in full. A probe child first shows which seam vars reached it (scope before subject).
# Run: powershell -NoProfile -ExecutionPolicy Bypass -File test\safe-moves.ps1
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
$tile = Join-Path $root 'tile.ps1'; $runPs = Join-Path $PSScriptRoot 'run.ps1'; $fixture = Join-Path $PSScriptRoot 'fixture.json'
$utf8 = New-Object Text.UTF8Encoding $false
$script:fail = 0
function Check($name, $ok, $detail = '') { if ($ok) { "PASS  $name" } else { $script:fail++; "FAIL  $name  $detail" } }
# One child powershell: its exit code, stdout and stderr. $envSet maps a variable to a value; $null strips it from the child.
# A copy of fresh-screens.ps1's Invoke-PsChild: that file runs its checks at top level, so it cannot be dot-sourced.
function Invoke-PsChild([string]$argLine, $envSet = @{}) {
  $psi = New-Object Diagnostics.ProcessStartInfo 'powershell', "-NoProfile -ExecutionPolicy Bypass $argLine"
  $psi.UseShellExecute = $false; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true; $psi.CreateNoWindow = $true
  foreach ($k in $envSet.Keys) { if ($null -eq $envSet[$k]) { [void]$psi.EnvironmentVariables.Remove($k) } else { $psi.EnvironmentVariables[$k] = [string]$envSet[$k] } }
  $p = [Diagnostics.Process]::Start($psi)
  $errTask = $p.StandardError.ReadToEndAsync()
  $out = $p.StandardOutput.ReadToEnd(); $p.WaitForExit()
  [pscustomobject]@{ Code = $p.ExitCode; Out = $out; Err = $errTask.Result }
}
function Short($s) { $t = "$s".Trim(); $t.Substring(0, [Math]::Min(120, $t.Length)) }

# Run folders (test-temp-standard): one folder per run, <pid>-<UUID>, under one temp root per repo. The first request of a run
# removes sibling run folders older than a day and keeps newer ones. stack-lock.ps1 has the sweep, but it runs its own checks at
# its top level, so this file keeps a copy of it (bay.ps1 does the same).
$tempRoot = Join-Path $env:TEMP 'tile-windows-test-runs'
$runName = '^\d+-[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
function Remove-OldRuns([string]$dir, [TimeSpan]$olderThan) {
  if (-not (Test-Path -LiteralPath $dir)) { return }
  @(Get-ChildItem -LiteralPath $dir -Directory | Where-Object { $_.Name -match $runName -and $_.LastWriteTime -lt (Get-Date).Subtract($olderThan) }) | ForEach-Object { Remove-Item -LiteralPath $_.FullName -Recurse -Force }
}
New-Item -ItemType Directory -Force $tempRoot | Out-Null
Remove-OldRuns $tempRoot ([TimeSpan]::FromDays(1))
$run = Join-Path $tempRoot ("$PID-" + [guid]::NewGuid().ToString()); New-Item -ItemType Directory -Force $run | Out-Null

# Every child gets a temp profile and home from this run folder, and the screens seam unset, so the real profile is never named.
$userDir = Join-Path $run 'profile'; New-Item -ItemType Directory -Force (Join-Path $userDir 'AppData\Roaming') | Out-Null
$tileHome = Join-Path $run 'home'
# The env one child gets: the base, then $seam, where $null strips a variable from the child.
function New-ChildEnv([hashtable]$seam = @{}) {
  $m = @{ USERPROFILE = $userDir; APPDATA = (Join-Path $userDir 'AppData\Roaming'); TILE_HOME = $tileHome; TILE_SCREENS_FILE = $null; TILE_TEST_SUITE = $null; TILE_TEST_ALLOW_LIVE = $null }
  foreach ($k in $seam.Keys) { $m[$k] = $seam[$k] }
  $m
}
$suite = @{ TILE_TEST_SUITE = '1' }; $live = @{ TILE_TEST_SUITE = '1'; TILE_TEST_ALLOW_LIVE = '1' }; $outside = @{}

try {
  # ---- Scope first: a probe child shows which seam vars reach a child, so each case below runs under the env it names. ----
  $probe = Join-Path $run 'probe.ps1'
  [IO.File]::WriteAllText($probe, '[Console]::Out.Write("[" + $env:TILE_TEST_SUITE + "|" + $env:TILE_TEST_ALLOW_LIVE + "]")', $utf8)
  $p = Invoke-PsChild "-File `"$probe`"" (New-ChildEnv $suite)
  Check 'scope: a child under the suite sees TILE_TEST_SUITE=1 and no opt-in' ($p.Out -eq '[1|]') "probe said [$(Short $p.Out)]"
  $p = Invoke-PsChild "-File `"$probe`"" (New-ChildEnv $live)
  Check 'scope: a child with the opt-in sees TILE_TEST_ALLOW_LIVE=1' ($p.Out -eq '[1|1]') "probe said [$(Short $p.Out)]"
  $p = Invoke-PsChild "-File `"$probe`"" (New-ChildEnv $outside)
  Check 'scope: a child outside the suite sees neither var' ($p.Out -eq '[|]') "probe said [$(Short $p.Out)]"
  # The bare snapshot moves nothing on any code. It shows the desktop's windows, so it proves no open window has the no-match name.
  $snap = Invoke-PsChild "-File `"$tile`" -Json" (New-ChildEnv $suite)
  $snapObj = $null; try { $snapObj = ConvertFrom-Json $snap.Out } catch { }
  Check 'scope: the bare snapshot (-Json) runs under the suite and parses' ($snap.Code -eq 0 -and $null -ne $snapObj -and $snapObj.PSObject.Properties.Name -contains 'windows') "exit $($snap.Code); out [$(Short $snap.Out)]"
  Check 'scope: no open window is named tile-test-no-such-app' ($null -ne $snapObj -and @($snapObj.windows | Where-Object { $_.app -eq 'tile-test-no-such-app' }).Count -eq 0) 'an open window has the no-match app name, or the snapshot did not parse'

  # ---- The inputs. Each flagless run names a scene or spec that matches no open window, so no window can move on any code. ----
  $sceneNone = Join-Path $run 'scene-none.json'
  [IO.File]::WriteAllText($sceneNone, '{"id":"none","name":"None","grids":{"wide":{"c":2,"r":1}},"pins":[],"zones":[],"bay":[],"fill":{"mon":"wide","apps":["tile-test-no-such-app"],"skip":[],"sort":"app"}}', $utf8)
  $placeNone = Join-Path $run 'place-none.json'
  [IO.File]::WriteAllText($placeNone, '[{"app":"tile-test-no-such-app","title":"none","x":0,"y":0,"w":100,"h":100}]', $utf8)
  # The full-size state for case 2: the fixture's Claude windows fill a grid.
  $sceneClaude = Join-Path $run 'scene-claude.json'
  [IO.File]::WriteAllText($sceneClaude, '{"id":"claude","name":"Claude","grids":{"wide":{"c":5,"r":2}},"pins":[],"zones":[],"bay":[],"fill":{"mon":"wide","apps":["claude"],"skip":[],"sort":"app"}}', $utf8)

  # ---- 1. Refusal (red on 656a8cf): under the suite, a flagless run that moves windows is refused before any pass. ----
  $r = Invoke-PsChild "-File `"$tile`" -Scene `"$sceneNone`"" (New-ChildEnv $suite)
  Check '1a suite: a flagless -Scene exits non-zero' ($r.Code -ne 0) "exit $($r.Code): the run went ahead"
  Check '1b suite: the refusal names TILE_TEST_ALLOW_LIVE' (($r.Out + $r.Err) -match 'TILE_TEST_ALLOW_LIVE') "no refusal text; out [$(Short $r.Out)] err [$(Short $r.Err)]"
  Check '1c suite: the refusal comes before any pass (no Grid line)' ($r.Out -notmatch '(?m)^Grid ') "a pass ran; out [$(Short $r.Out)]"
  $pf = Invoke-PsChild "-File `"$tile`" -PlaceFile `"$placeNone`"" (New-ChildEnv $suite)
  Check '1d suite: a flagless -PlaceFile exits non-zero' ($pf.Code -ne 0) "exit $($pf.Code): the place run went ahead"
  $bare = Invoke-PsChild "-File `"$tile`" -Monitor wide -Proc tile-test-no-such-app" (New-ChildEnv $suite)
  Check '1e suite: a flagless bare run (-Monitor, no scene) exits non-zero' ($bare.Code -ne 0) "exit $($bare.Code): the bare run went ahead"
  $sj = Invoke-PsChild "-File `"$tile`" -Scene `"$sceneNone`" -Json" (New-ChildEnv $suite)
  Check '1f suite: a flagless -Scene with -Json exits non-zero (JSON output does not make it a read)' ($sj.Code -ne 0) "exit $($sj.Code): the run went ahead"
  $pj = Invoke-PsChild "-File `"$tile`" -PlaceFile `"$placeNone`" -Json" (New-ChildEnv $suite)
  Check '1g suite: a flagless -PlaceFile with -Json exits non-zero (JSON output does not make it a read)' ($pj.Code -ne 0) "exit $($pj.Code): the place run went ahead"

  # ---- 2. Controls: the reads and dry runs that stay exempt still run under the suite (green on 656a8cf). ----
  $dry = Invoke-PsChild "-File `"$tile`" -Scene `"$sceneNone`" -DryRun" (New-ChildEnv $suite)
  Check '2a suite: -DryRun still runs (exit 0, its Grid line)' ($dry.Code -eq 0 -and $dry.Out -match '(?m)^Grid ') "exit $($dry.Code); out [$(Short $dry.Out)]"
  Check '2b suite: the bare snapshot (-Json) still lists the monitors (exit 0)' ($snap.Code -eq 0 -and $null -ne $snapObj -and $snapObj.PSObject.Properties.Name -contains 'monitors') "exit $($snap.Code); out [$(Short $snap.Out)]"
  $mon = Invoke-PsChild "-File `"$tile`" -Monitors" (New-ChildEnv $suite)
  $monObj = $null; try { $monObj = ConvertFrom-Json $mon.Out } catch { }
  Check '2c suite: -Monitors still runs (exit 0, a JSON list of monitors)' ($mon.Code -eq 0 -and $null -ne $monObj -and @($monObj).Count -ge 1) "exit $($mon.Code); out [$(Short $mon.Out)]"
  $fr = Invoke-PsChild "-File `"$tile`" -Scene `"$sceneClaude`" -From `"$fixture`" -Json" (New-ChildEnv $suite)
  $frObj = $null; try { $frObj = ConvertFrom-Json $fr.Out } catch { }
  Check '2d suite: -From still runs on the fixture (exit 0, windows placed)' ($fr.Code -eq 0 -and $null -ne $frObj -and @($frObj.placed).Count -ge 1) "exit $($fr.Code); out [$(Short $fr.Out)]"
  $libProbe = Join-Path $run 'lib-probe.ps1'
  [IO.File]::WriteAllText($libProbe, ". '$tile' -Lib; if (Get-Command Move-Win -ErrorAction SilentlyContinue) { [Console]::Out.Write('ok') }", $utf8)
  $lib = Invoke-PsChild "-File `"$libProbe`"" (New-ChildEnv $suite)
  Check '2e suite: a dot-source with -Lib is not refused (exit 0, Move-Win defined, no refusal text)' ($lib.Code -eq 0 -and $lib.Out -eq 'ok' -and (($lib.Out + $lib.Err) -notmatch 'TILE_TEST_ALLOW_LIVE')) "exit $($lib.Code); out [$(Short $lib.Out)] err [$(Short $lib.Err)]"
  # -List prints the screens and the windows of the named app, then returns before any Move-Win (tile.ps1 returns at its -List line,
  # ahead of every Move-Win call). The seam gives one screen, so the screen line is fixed; -Proc names no open window, so no title prints.
  $listSeam = Join-Path $run 'screens-list.json'
  [IO.File]::WriteAllText($listSeam, '[{"name":"SEAM-LIST","x":0,"y":0,"w":1920,"h":1040,"bw":1920,"bh":1080}]', $utf8)
  $ls = Invoke-PsChild "-File `"$tile`" -List -Proc tile-test-no-such-app" (New-ChildEnv @{ TILE_TEST_SUITE = '1'; TILE_SCREENS_FILE = $listSeam })
  Check '2f suite: -List still runs (exit 0, its screen line, not refused)' ($ls.Code -eq 0 -and $ls.Out -match 'SEAM-LIST \{X=0,Y=0,Width=1920,Height=1040\}' -and (($ls.Out + $ls.Err) -notmatch 'TILE_TEST_ALLOW_LIVE')) "exit $($ls.Code); out [$(Short $ls.Out)] err [$(Short $ls.Err)]"

  # ---- 3. The opt-in lets a flagless run proceed (green on 656a8cf). ----
  $al = Invoke-PsChild "-File `"$tile`" -Scene `"$sceneNone`"" (New-ChildEnv $live)
  Check '3a opt-in: TILE_TEST_ALLOW_LIVE=1 lets a flagless -Scene run (exit 0, its Grid line)' ($al.Code -eq 0 -and $al.Out -match '(?m)^Grid ') "exit $($al.Code); out [$(Short $al.Out)] err [$(Short $al.Err)]"

  # ---- 4. Outside the suite, a flagless run is not refused (green on 656a8cf). ----
  $ou = Invoke-PsChild "-File `"$tile`" -Scene `"$sceneNone`"" (New-ChildEnv $outside)
  Check '4a outside the suite: a flagless -Scene is not refused (exit 0, its Grid line)' ($ou.Code -eq 0 -and $ou.Out -match '(?m)^Grid ') "exit $($ou.Code); out [$(Short $ou.Out)]"

  # ---- 5. Seam: test\run.ps1 marks its children (red on 656a8cf). The parser reads the file, not its text. ----
  $tokens = $null; $errs = $null
  $tree = [Management.Automation.Language.Parser]::ParseFile($runPs, [ref]$tokens, [ref]$errs)
  Check '5a scope: test\run.ps1 parses with no errors' (@($errs).Count -eq 0) "$(@($errs).Count) parse error(s)"
  $marks = @($tree.FindAll({ param($n) $n -is [Management.Automation.Language.AssignmentStatementAst] -and $n.Left -is [Management.Automation.Language.VariableExpressionAst] -and $n.Left.VariablePath.UserPath -eq 'env:TILE_TEST_SUITE' -and $n.Right.Extent.Text -in "'1'", '"1"' }, $true))
  Check '5b seam: test\run.ps1 sets $env:TILE_TEST_SUITE to 1 for its children' ($marks.Count -ge 1) 'no assignment of 1 to $env:TILE_TEST_SUITE in test\run.ps1'

  # ---- 6. Run folders: the sweep removes an old run folder and keeps a new one (green on 656a8cf). ----
  $proof = Join-Path $run 'sweep-proof'; New-Item -ItemType Directory -Force $proof | Out-Null
  $oldRun = Join-Path $proof ('1-' + [guid]::NewGuid().ToString()); $newRun = Join-Path $proof ('2-' + [guid]::NewGuid().ToString())
  New-Item -ItemType Directory -Force $oldRun | Out-Null; New-Item -ItemType Directory -Force $newRun | Out-Null
  (Get-Item -LiteralPath $oldRun).LastWriteTime = (Get-Date).AddDays(-2)
  Remove-OldRuns $proof ([TimeSpan]::FromDays(1))
  Check '6a run folders: the sweep removes a run folder older than a day' (-not (Test-Path -LiteralPath $oldRun))
  Check '6b run folders: the sweep keeps a run folder newer than a day' (Test-Path -LiteralPath $newRun)
} catch {
  $script:fail++; "FAIL  run stopped: $_"
} finally {
  Remove-Item -LiteralPath $run -Recurse -Force -ErrorAction SilentlyContinue
}
if ($script:fail) { "$($script:fail) check(s) failed."; exit 1 } else { 'All checks passed.' }
