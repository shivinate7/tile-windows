# Checks for the live-move guard in tile.ps1. Under the suite (TILE_TEST_SUITE=1, which test\run.ps1 sets for its children), a run that
# moves windows is refused unless the caller names TILE_TEST_ALLOW_LIVE=1. The refusal exits non-zero, names TILE_TEST_ALLOW_LIVE, and
# comes before any pass (no 'Grid' line). What the builder meets:
#   TILE_TEST_SUITE=1: the suite. Exempt from the refusal: -DryRun, -From, -Monitors, -List (it returns before any Move-Win), a dot-source with -Lib, and -Json only as the
#     bare snapshot (no -Scene, -Default, -Place or -PlaceFile: with those, -Json still moves windows unless -DryRun is set).
#   TILE_TEST_ALLOW_LIVE=1: the caller accepts a live run. Unset, or any other value, is refused.
#   CLAUDECODE=1 (set in every agent shell): the same guard applies to a run with no suite, with the same exemptions.
# Cases. Red means it fails on the commit named for it (656a8cf; 62acbd4 for the CLAUDECODE cases) for the named cause. Green means a control
# that holds there and must keep holding.
#   Scope (green): a probe child shows which seam vars reached it; the bare snapshot lists no window named tile-test-no-such-app.
#   1 refusal (red): under the suite, a flagless -Scene, -PlaceFile, bare -Monitor, -Scene -Json or -PlaceFile -Json run is refused,
#     and so is a flagless -Default (with or without -Json) and an inline -Place.
#   2 controls (green): -DryRun, bare -Json, -Monitors, -List, -From and a -Lib dot-source still run under the suite.
#   3 opt-in (green): TILE_TEST_ALLOW_LIVE=1 lets a flagless -Scene run.
#   4 outside the suite (green): with no suite var, a flagless -Scene is not refused.
#   5 seam (red): test\run.ps1 sets TILE_TEST_SUITE=1 for its children, and clears CLAUDECODE for them (5c, red on 62acbd4).
#   6 run folders (green): the sweep removes a run folder older than a day and keeps a newer one (test-temp-standard).
#   7 CLAUDECODE (red 7a, 7b on 62acbd4): with no suite, a flagless -Scene is refused naming TILE_TEST_ALLOW_LIVE. Green controls: the
#     exempt runs, the opt-in, a neither-var run, and the tray and server apply paths (their dry seams) still run.
# Every flagless run names a scene or spec that matches no open window (tile-test-no-such-app), and the scope check proves no
# open window has that app name. So no flagless run can move a window on any code.
# Each child's env is set or stripped in full. A probe child first shows which seam vars reached it (scope before subject).
# Run: powershell -NoProfile -ExecutionPolicy Bypass -File test\safe-moves.ps1
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
$tile = Join-Path $root 'tile.ps1'; $serve = Join-Path $root 'serve.ps1'; $runPs = Join-Path $PSScriptRoot 'run.ps1'; $fixture = Join-Path $PSScriptRoot 'fixture.json'
$utf8 = New-Object Text.UTF8Encoding $false
$script:fail = 0
function Check($name, $ok, $detail = '') { if ($ok) { "PASS  $name" } else { $script:fail++; "FAIL  $name  $detail" } }
# One child powershell: its exit code, stdout and stderr. $envSet maps a variable to a value; $null strips it from the child.
# -NoWait returns the started process instead (a server runs until it is told to quit; its caller reads and stops it).
# A copy of fresh-screens.ps1's Invoke-PsChild: that file runs its checks at top level, so it cannot be dot-sourced.
function Invoke-PsChild([string]$argLine, $envSet = @{}, [switch]$NoWait) {
  $psi = New-Object Diagnostics.ProcessStartInfo 'powershell', "-NoProfile -ExecutionPolicy Bypass $argLine"
  $psi.UseShellExecute = $false; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true; $psi.CreateNoWindow = $true
  foreach ($k in $envSet.Keys) { if ($null -eq $envSet[$k]) { [void]$psi.EnvironmentVariables.Remove($k) } else { $psi.EnvironmentVariables[$k] = [string]$envSet[$k] } }
  $p = [Diagnostics.Process]::Start($psi)
  if ($NoWait) { return $p }
  $errTask = $p.StandardError.ReadToEndAsync()
  $out = $p.StandardOutput.ReadToEnd(); $p.WaitForExit()
  [pscustomobject]@{ Code = $p.ExitCode; Out = $out; Err = $errTask.Result }
}
function Short($s) { $t = "$s".Trim(); $t.Substring(0, [Math]::Min(120, $t.Length)) }
# A child's stdout without its WARNING lines (Write-Warning reaches stdout here), so the JSON after them parses.
function NoWarn($s) { (("$s" -split '\r?\n') | ? { $_ -notmatch '^WARNING:' }) -join "`n" }

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
  # CLAUDECODE (set in an agent's shell) is stripped too: a child has it only when its case sets it, never by inheritance.
  $m = @{ USERPROFILE = $userDir; APPDATA = (Join-Path $userDir 'AppData\Roaming'); TILE_HOME = $tileHome; TILE_SCREENS_FILE = $null; TILE_TEST_SUITE = $null; TILE_TEST_ALLOW_LIVE = $null; CLAUDECODE = $null }
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

  # ---- 1 (cont.) -Default and an inline -Place (red on 656a8cf, which has no guard, so both runs would go ahead there). ----
  # -Default's scene fills claude, chrome and '*' (scenes.json), so it must never reach a window. TILE_SCREENS_FILE holding [] gives the
  # run no monitor, and a pass with no screen places nothing. Scope first: a dry run places nothing. The refusal cases run only after it passes.
  $noScreens = Join-Path $run 'screens-none.json'; [IO.File]::WriteAllText($noScreens, '[]', $utf8)
  $noMon = @{ TILE_TEST_SUITE = '1'; TILE_SCREENS_FILE = $noScreens }
  $dd = Invoke-PsChild "-File `"$tile`" -Default -DryRun -Json" (New-ChildEnv $noMon)
  $ddObj = $null; try { $ddObj = ConvertFrom-Json (NoWarn $dd.Out) } catch { }
  $defScope = $dd.Code -eq 0 -and $null -ne $ddObj -and @($ddObj.placed).Count -eq 0
  Check 'scope: with no monitor, a dry -Default places nothing (exit 0, placed empty)' $defScope "exit $($dd.Code); out [$(Short $dd.Out)]"
  if ($defScope) {
    $dr = Invoke-PsChild "-File `"$tile`" -Default" (New-ChildEnv $noMon)
    Check '1h suite: a flagless -Default exits non-zero' ($dr.Code -ne 0) "exit $($dr.Code): the run went ahead"
    Check '1i suite: the -Default refusal names TILE_TEST_ALLOW_LIVE' (($dr.Out + $dr.Err) -match 'TILE_TEST_ALLOW_LIVE') "no refusal text; out [$(Short $dr.Out)] err [$(Short $dr.Err)]"
    $drj = Invoke-PsChild "-File `"$tile`" -Default -Json" (New-ChildEnv $noMon)
    Check '1j suite: a flagless -Default with -Json exits non-zero (JSON output does not make it a read)' ($drj.Code -ne 0) "exit $($drj.Code): the run went ahead"
  } else { Check '1h-1j suite: not run, the -Default scope check above failed' $false }
  # An inline -Place names one window that is not open. Its argument is one quoted string: each JSON quote arrives as \".
  $placeJson = '[{"app":"tile-test-no-such-app","title":"none","x":0,"y":0,"w":100,"h":100}]'
  $placeArg = '"' + ($placeJson -replace '"', '\"') + '"'
  $pc = Invoke-PsChild "-File `"$tile`" -Place $placeArg -DryRun -Json" (New-ChildEnv $suite)
  $pcObj = $null; try { $pcObj = @(ConvertFrom-Json (NoWarn $pc.Out)) } catch { }
  $placeScope = $pc.Code -eq 0 -and $pcObj.Count -eq 1 -and $pcObj[0].ok -eq $false -and $pcObj[0].note -eq 'no open window'
  Check 'scope: an inline -Place names no open window (dry run: one entry, note no open window)' $placeScope "exit $($pc.Code); out [$(Short $pc.Out)]"
  if ($placeScope) {
    $pl = Invoke-PsChild "-File `"$tile`" -Place $placeArg" (New-ChildEnv $suite)
    Check '1k suite: an inline -Place exits non-zero' ($pl.Code -ne 0) "exit $($pl.Code): the place run went ahead"
    Check '1l suite: the inline -Place refusal names TILE_TEST_ALLOW_LIVE' (($pl.Out + $pl.Err) -match 'TILE_TEST_ALLOW_LIVE') "no refusal text; out [$(Short $pl.Out)] err [$(Short $pl.Err)]"
  } else { Check '1k-1l suite: not run, the inline -Place scope check above failed' $false }

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
  # 5c (red on 62acbd4): an agent's shell carries CLAUDECODE=1. run.ps1 clears it, so no child of the run inherits it.
  $clears = @($tree.FindAll({ param($n) $n -is [Management.Automation.Language.AssignmentStatementAst] -and $n.Left -is [Management.Automation.Language.VariableExpressionAst] -and $n.Left.VariablePath.UserPath -eq 'env:CLAUDECODE' -and $n.Right.Extent.Text -eq '$null' }, $true))
  Check '5c seam: test\run.ps1 clears $env:CLAUDECODE for its children' ($clears.Count -ge 1) 'no assignment of $null to $env:CLAUDECODE in test\run.ps1'

  # ---- 6. Run folders: the sweep removes an old run folder and keeps a new one (green on 656a8cf). ----
  $proof = Join-Path $run 'sweep-proof'; New-Item -ItemType Directory -Force $proof | Out-Null
  $oldRun = Join-Path $proof ('1-' + [guid]::NewGuid().ToString()); $newRun = Join-Path $proof ('2-' + [guid]::NewGuid().ToString())
  New-Item -ItemType Directory -Force $oldRun | Out-Null; New-Item -ItemType Directory -Force $newRun | Out-Null
  (Get-Item -LiteralPath $oldRun).LastWriteTime = (Get-Date).AddDays(-2)
  Remove-OldRuns $proof ([TimeSpan]::FromDays(1))
  Check '6a run folders: the sweep removes a run folder older than a day' (-not (Test-Path -LiteralPath $oldRun))
  Check '6b run folders: the sweep keeps a run folder newer than a day' (Test-Path -LiteralPath $newRun)

  # ---- 7. CLAUDECODE=1 guards a run with no suite: an agent that runs tile.ps1 by hand has no TILE_TEST_SUITE. Red on 62acbd4: 7a, 7b.
  # Scope first: a child sees CLAUDECODE only when its case sets it, and no suite or opt-in var comes with it.
  $cprobe = Join-Path $run 'claude-probe.ps1'
  [IO.File]::WriteAllText($cprobe, '[Console]::Out.Write("[" + $env:CLAUDECODE + "|" + $env:TILE_TEST_SUITE + "|" + $env:TILE_TEST_ALLOW_LIVE + "]")', $utf8)
  $agent = @{ CLAUDECODE = '1' }; $agentLive = @{ CLAUDECODE = '1'; TILE_TEST_ALLOW_LIVE = '1' }
  $cp1 = Invoke-PsChild "-File `"$cprobe`"" (New-ChildEnv $agent)
  Check 'scope: a child with CLAUDECODE=1 and no suite sees only CLAUDECODE' ($cp1.Out -eq '[1||]') "probe said [$(Short $cp1.Out)]"
  $cp2 = Invoke-PsChild "-File `"$cprobe`"" (New-ChildEnv $outside)
  Check 'scope: a child with no seam sees no CLAUDECODE, even when this shell has it' ($cp2.Out -eq '[||]') "probe said [$(Short $cp2.Out)]"

  # 7a, 7b (red on 62acbd4: its guard reads only TILE_TEST_SUITE, so the flagless -Scene runs; the no-match scene moves nothing).
  $c7 = Invoke-PsChild "-File `"$tile`" -Scene `"$sceneNone`"" (New-ChildEnv $agent)
  Check '7a CLAUDECODE: a flagless -Scene with no suite exits non-zero' ($c7.Code -ne 0) "exit $($c7.Code): the run went ahead"
  Check '7b CLAUDECODE: that refusal names TILE_TEST_ALLOW_LIVE' (($c7.Out + $c7.Err) -match 'TILE_TEST_ALLOW_LIVE') "no refusal text; out [$(Short $c7.Out)] err [$(Short $c7.Err)]"

  # 7c-7h: the runs the guard exempts still run under CLAUDECODE=1 (green on 62acbd4, and must stay green).
  $c8 = Invoke-PsChild "-File `"$tile`" -Scene `"$sceneNone`" -DryRun" (New-ChildEnv $agent)
  Check '7c CLAUDECODE: -DryRun still runs (exit 0, its Grid line)' ($c8.Code -eq 0 -and $c8.Out -match '(?m)^Grid ') "exit $($c8.Code); out [$(Short $c8.Out)]"
  $c9 = Invoke-PsChild "-File `"$tile`" -Monitors" (New-ChildEnv $agent)
  $c9Obj = $null; try { $c9Obj = ConvertFrom-Json (NoWarn $c9.Out) } catch { }
  Check '7d CLAUDECODE: -Monitors still runs (exit 0, a JSON list of monitors)' ($c9.Code -eq 0 -and $null -ne $c9Obj -and @($c9Obj).Count -ge 1) "exit $($c9.Code); out [$(Short $c9.Out)]"
  $c10 = Invoke-PsChild "-File `"$tile`" -Scene `"$sceneClaude`" -From `"$fixture`" -Json" (New-ChildEnv $agent)
  $c10Obj = $null; try { $c10Obj = ConvertFrom-Json (NoWarn $c10.Out) } catch { }
  Check '7e CLAUDECODE: -From still runs on the fixture (exit 0, windows placed)' ($c10.Code -eq 0 -and $null -ne $c10Obj -and @($c10Obj.placed).Count -ge 1) "exit $($c10.Code); out [$(Short $c10.Out)]"
  $c11 = Invoke-PsChild "-File `"$tile`" -Json" (New-ChildEnv $agent)
  $c11Obj = $null; try { $c11Obj = ConvertFrom-Json (NoWarn $c11.Out) } catch { }
  Check '7f CLAUDECODE: the bare snapshot (-Json) still runs (exit 0, monitors and windows)' ($c11.Code -eq 0 -and $null -ne $c11Obj -and $c11Obj.PSObject.Properties.Name -contains 'monitors' -and $c11Obj.PSObject.Properties.Name -contains 'windows') "exit $($c11.Code); out [$(Short $c11.Out)]"
  $c12 = Invoke-PsChild "-File `"$tile`" -List -Proc tile-test-no-such-app" (New-ChildEnv @{ CLAUDECODE = '1'; TILE_SCREENS_FILE = $listSeam })
  Check '7g CLAUDECODE: -List still runs (exit 0, its screen line)' ($c12.Code -eq 0 -and $c12.Out -match 'SEAM-LIST \{X=0,Y=0,Width=1920,Height=1040\}') "exit $($c12.Code); out [$(Short $c12.Out)] err [$(Short $c12.Err)]"
  $c13 = Invoke-PsChild "-File `"$libProbe`"" (New-ChildEnv $agent)
  Check '7h CLAUDECODE: a dot-source with -Lib is not refused (exit 0, Move-Win defined)' ($c13.Code -eq 0 -and $c13.Out -eq 'ok') "exit $($c13.Code); out [$(Short $c13.Out)] err [$(Short $c13.Err)]"

  # 7i: TILE_TEST_ALLOW_LIVE=1 lets the flagless -Scene run under CLAUDECODE=1. 7j: with neither var, an inline -Place is not refused.
  $c14 = Invoke-PsChild "-File `"$tile`" -Scene `"$sceneNone`"" (New-ChildEnv $agentLive)
  Check '7i CLAUDECODE + TILE_TEST_ALLOW_LIVE=1: a flagless -Scene runs (exit 0, its Grid line)' ($c14.Code -eq 0 -and $c14.Out -match '(?m)^Grid ') "exit $($c14.Code); out [$(Short $c14.Out)] err [$(Short $c14.Err)]"
  $c15 = Invoke-PsChild "-File `"$tile`" -Place $placeArg" (New-ChildEnv $outside)
  Check '7j neither var: an inline -Place is not refused (exit 0, placed 0 of 1)' ($c15.Code -eq 0 -and $c15.Out -match 'Placed 0 of 1') "exit $($c15.Code); out [$(Short $c15.Out)]"

  # 7k: the tray's apply path, through its -NoApply seam (every apply a dry run), is not refused under CLAUDECODE=1. tray.ps1's -Lib
  # returns before Apply-Scene is defined, so the child takes Apply-Scene's text from the script's AST and runs it. Its tile.ps1 call reads
  # the empty screen list, so it places nothing.
  $tprobe = Join-Path $run 'tray-apply.ps1'
  $tsrc = @'
$root = '@@ROOT@@'
$tokens = $null; $errs = $null
$ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'tray.ps1'), [ref]$tokens, [ref]$errs)
$fn = @($ast.FindAll({ param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Apply-Scene' }, $true))[0]
. (Join-Path $root 'tray.ps1') -Lib
Invoke-Expression $fn.Extent.Text
$tile = Join-Path $root 'tile.ps1'; $NoApply = $true; $NoIcon = $true; $gridMode = @{}
function Note([string]$text) { [Console]::Out.Write('NOTE[' + $text + ']') }
Apply-Scene ([pscustomobject]@{ id = 'default'; name = 'Default' }) 'from the test'
'@
  [IO.File]::WriteAllText($tprobe, $tsrc.Replace('@@ROOT@@', $root), $utf8)
  $c16 = Invoke-PsChild "-File `"$tprobe`"" (New-ChildEnv @{ CLAUDECODE = '1'; TILE_SCREENS_FILE = $noScreens })
  Check '7k CLAUDECODE: the tray apply path (-NoApply) reports it applied, not failed or refused' ($c16.Out -match 'Default applied from the test\. Moved 0 window\(s\)\.' -and $c16.Out -notmatch 'failed') "probe said [$(Short $c16.Out)] err [$(Short $c16.Err)]"

  # 7l: the server's apply path, with -From (every apply a dry run), places the fixture window under CLAUDECODE=1. The server runs until /quit.
  $sv = Invoke-PsChild "-File `"$serve`" -NoBrowser -From `"$fixture`"" (New-ChildEnv $agent) -NoWait
  $svUrl = $sv.StandardOutput.ReadLine()
  $fxw = @((Get-Content -Raw -Encoding UTF8 -LiteralPath $fixture | ConvertFrom-Json).windows)[0]
  $apBody = ConvertTo-Json -InputObject @(@{ id = $fxw.id; app = $fxw.app; title = $fxw.title; x = 0; y = 0; w = 100; h = 100 }) -Compress
  $ap = $null; $apErr = ''
  try { $ap = @((Invoke-WebRequest -UseBasicParsing "$($svUrl)apply" -Method Post -ContentType 'application/json; charset=utf-8' -Body $apBody).Content | ConvertFrom-Json) } catch { $apErr = $_.Exception.Message }
  Check '7l CLAUDECODE: the server apply path (-From) places the fixture window as a dry run, not refused' ($null -ne $ap -and $ap.Count -eq 1 -and $ap[0].ok -eq $true -and "$($ap[0].note)" -like 'dry run*') "no dry-run entry back (refused or failed): $(Short $apErr) url [$(Short $svUrl)]"
  try { [void](Invoke-WebRequest -UseBasicParsing "$($svUrl)quit" -Method Post -Body 'quit') } catch { }
  Check 'the server exits on /quit (CLAUDECODE case)' ($sv.WaitForExit(5000))
} catch {
  $script:fail++; "FAIL  run stopped: $_"
} finally {
  if ($sv -and -not $sv.HasExited) { $sv.Kill() }
  Remove-Item -LiteralPath $run -Recurse -Force -ErrorAction SilentlyContinue
}
if ($script:fail) { "$($script:fail) check(s) failed."; exit 1 } else { 'All checks passed.' }
