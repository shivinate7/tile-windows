# Checks for tile.ps1, serve.ps1, app.html, tray.ps1 (its automatic triggers: triggers.ps1) and install.ps1. Plain asserts; moves no window
# (every place call is a dry run) and touches no real profile (servers, tray and installer get a temp one).
# Run: powershell -NoProfile -ExecutionPolicy Bypass -File test\run.ps1
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
$tile = Join-Path $root 'tile.ps1'; $serve = Join-Path $root 'serve.ps1'; $fixture = Join-Path $PSScriptRoot 'fixture.json'
$tmp = Join-Path $env:TEMP "tile-test-$PID"; New-Item -ItemType Directory $tmp | Out-Null
$utf8 = New-Object Text.UTF8Encoding $false
$script:fail = 0
function Check($name, $ok, $detail = '') { if ($ok) { "PASS  $name" } else { $script:fail++; "FAIL  $name  $detail" } }
function Child { & powershell -NoProfile -ExecutionPolicy Bypass -File @args }
# A string as JSON.stringify writes it (the page's encoder): escape \ and " only.
# Count of a JSON array; -1 when it is missing (a crashed self-test must not pass).
function N($x) { if ($null -eq $x) { -1 } else { @($x).Count } }
function JsStr($s) { '"' + $s.Replace('\', '\\').Replace('"', '\"') + '"' }
function Status($url, $post) { try { if ($post) { (Invoke-WebRequest -UseBasicParsing $url -Method Post -Body $post).StatusCode } else { (Invoke-WebRequest -UseBasicParsing $url).StatusCode } } catch { [int]$_.Exception.Response.StatusCode } }
# A temp profile: USERPROFILE and APPDATA both point inside $tmp.
function Profile($name) { $p = Join-Path $tmp $name; New-Item -ItemType Directory -Force (Join-Path $p 'AppData\Roaming') | Out-Null; $p }
# Start a hidden powershell child with a temp profile; stdout is redirected so the caller can read the URL.
function Start-Child($prof, $argLine, $extra = @{}) {
  $psi = New-Object Diagnostics.ProcessStartInfo 'powershell', "-NoProfile -ExecutionPolicy Bypass $argLine"
  $psi.UseShellExecute = $false; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true; $psi.CreateNoWindow = $true
  if (-not $prof) { $prof = $env:USERPROFILE }
  $psi.EnvironmentVariables['USERPROFILE'] = $prof; $psi.EnvironmentVariables['APPDATA'] = Join-Path $prof 'AppData\Roaming'
  foreach ($k in $extra.Keys) { $psi.EnvironmentVariables[$k] = $extra[$k] }
  [Diagnostics.Process]::Start($psi)
}
function Post($url, $body) { (Invoke-WebRequest -UseBasicParsing $url -Method Post -ContentType 'application/json; charset=utf-8' -Body ($utf8.GetBytes($body))).Content }
$edge = @("${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe", "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe") | ? { Test-Path -LiteralPath $_ } | Select-Object -First 1
# Run one of the page's #selftest-* hooks in headless Edge; returns its JSON, or $null.
function SelfTest($url, $hook) {
  $dom = Join-Path $tmp "dom-$hook.html"
  # Font hosts fail fast (a pending font fetch can stall virtual time); a hung Edge is killed, not waited on.
  $e = Start-Process $edge -PassThru -WindowStyle Hidden -RedirectStandardOutput $dom -RedirectStandardError (Join-Path $tmp "edge-$hook.log") -ArgumentList '--headless', '--disable-gpu', '--no-first-run', "--user-data-dir=$tmp\edge-$hook", '--host-resolver-rules="MAP fonts.googleapis.com 0.0.0.0, MAP fonts.gstatic.com 0.0.0.0"', '--virtual-time-budget=90000', '--dump-dom', "${url}#selftest-$hook"
  if (-not $e.WaitForExit(120000)) { Get-CimInstance Win32_Process -Filter "Name='msedge.exe'" | ? { $_.CommandLine -like "*edge-$hook*" } | % { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }; return $null }
  if ((Get-Content -Raw -Encoding UTF8 $dom) -match '<pre id="selftest">(.*?)</pre>') { [Net.WebUtility]::HtmlDecode($matches[1]) | ConvertFrom-Json }
}
# A starter scene as the page sends it: the scene plus the category map.
$starters = [IO.File]::ReadAllText((Join-Path $root 'scenes.json'), $utf8) | ConvertFrom-Json
function StarterJson($id) { $s = @($starters.scenes | ? { $_.id -eq $id })[0]; $s | Add-Member -Force cats $starters.cats; $s | Add-Member -Force categories $starters.categories; ConvertTo-Json -Depth 10 -Compress $s }

$form = $null; $srv = $null; $fsrv = $null; $ssrv = $null; $tray = $null
# The whole run, and every child it starts, uses a temp profile: the real one is never named.
$saved = @{ USERPROFILE = $env:USERPROFILE; APPDATA = $env:APPDATA; TILE_HOME = $env:TILE_HOME }
$env:USERPROFILE = Profile 'run'; $env:APPDATA = Join-Path $env:USERPROFILE 'AppData\Roaming'; $env:TILE_HOME = $null
try {
  . (Join-Path $root 'config.ps1')
  Check 'the run and its children use a temp profile' ($env:USERPROFILE.StartsWith($tmp) -and $env:APPDATA.StartsWith($tmp) -and $TileHome.StartsWith($tmp)) "$env:USERPROFILE | $TileHome"
  # 1. Snapshot JSON parses (in-process, as serve.ps1 calls it).
  $snapText = (& $tile -Json 2>$null) -join ''
  $snap = $snapText | ConvertFrom-Json
  Check 'snapshot JSON parses' ($snap.monitors.Count -ge 1 -and $null -ne $snap.windows)
  Check 'snapshot gives the widest monitor the wide role' (@($snap.monitors | ? { $_.role -eq 'wide' })[0].w -eq ($snap.monitors.w | Measure-Object -Maximum).Maximum)

  # 2. Feeding the snapshot back to -PlaceFile -DryRun matches every window.
  $f = Join-Path $tmp 'snap.json'; [IO.File]::WriteAllText($f, $snapText, $utf8)
  $n = @($snap.windows).Count
  $last = @(& $tile -PlaceFile $f -DryRun 3>$null)[-1]
  Check '-Place -DryRun matches all windows' ($last -eq "Placed $n of $n (0 unmatched).") $last

  # 3. A title with quotes and apostrophes survives page -> file -> PowerShell, and page -> /apply.
  $title = "It's a ""quoted"" test `$x & <ok> $PID"
  $env:TILE_TEST_TITLE = $title
  $fs = Join-Path $tmp 'form.ps1'
  Set-Content -LiteralPath $fs -Encoding ASCII -Value 'Add-Type -AssemblyName System.Windows.Forms; $f = New-Object Windows.Forms.Form; $f.Text = $env:TILE_TEST_TITLE; $f.WindowState = "Minimized"; [Windows.Forms.Application]::Run($f)'
  $form = Start-Process powershell -PassThru -WindowStyle Hidden -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$fs`""
  $t0 = Get-Date
  while ((Get-Process -Id $form.Id).MainWindowTitle -ne $title) { if (((Get-Date) - $t0).TotalSeconds -gt 15) { throw 'Test window did not open.' }; Start-Sleep -Milliseconds 200; $form.Refresh() }
  $js = '[{"app":"powershell","title":' + (JsStr $title) + ',"x":100,"y":100,"w":400,"h":300}]'
  $pf = Join-Path $tmp 'last-place.json'; [IO.File]::WriteAllText($pf, $js, $utf8)
  $out = @(Child $tile -PlaceFile $pf -DryRun 2>&1 | % { "$_" })
  Check 'title survives page -> file -> -PlaceFile' ($out[-1] -eq 'Placed 1 of 1 (0 unmatched).') ($out -join ' | ')

  # 4. Server: token required; snapshot and dry-run apply work through it.
  $srv = Start-Child (Profile 'srv') "-File `"$serve`" -NoBrowser -DryRun"
  $url = $srv.StandardOutput.ReadLine()
  $base = $url -replace '[0-9a-f]{32}/$', ''
  Check 'server prints a tokened URL' ($url -match '^http://127\.0\.0\.1:\d+/[0-9a-f]{32}/$') $url
  Check 'server rejects a missing token' ((Status "${base}snapshot") -eq 403)
  Check 'server rejects a wrong token' ((Status "${base}00000000000000000000000000000000/snapshot") -eq 403)
  $s2 = (Invoke-WebRequest -UseBasicParsing "${url}snapshot").Content | ConvertFrom-Json
  Check 'server snapshot parses' ($s2.monitors.Count -ge 1)
  $res = @((Post "${url}apply" $js) | ConvertFrom-Json)
  Check 'title survives page -> /apply (dry run)' ($res.Count -eq 1 -and $res[0].ok -and $res[0].title -ceq $title -and $res[0].note -like 'dry run*') ($res | ConvertTo-Json -Compress)
  Check 'server refuses a non-array apply' ((Status "${url}apply" ' ') -eq 400)
  Check 'server refuses bad JSON' ((Status "${url}apply" '[{"app":') -eq 400)
  Check 'server refuses a non-object scene' ((Status "${url}scene" '[]') -eq 400)
  [void](Invoke-WebRequest -UseBasicParsing "${url}quit" -Method Post -Body 'quit')
  Check 'server exits on /quit' ($srv.WaitForExit(5000))

  # 5. Config (one home: %USERPROFILE%\.tile-windows\config.json), against a fixture server.
  $fprof = Profile 'fix'; $fcfg = Join-Path $fprof '.tile-windows\config.json'
  # A -From server without TILE_HOME keeps its scenes in a throwaway folder, never in the profile.
  $sprof = Profile 'sample'; $ssrv = Start-Child $sprof "-File `"$serve`" -NoBrowser -From `"$fixture`""; $surl = $ssrv.StandardOutput.ReadLine()
  $sc1 = (Invoke-WebRequest -UseBasicParsing "${surl}config").Content; $shome = Join-Path $env:TEMP "tile-windows-sample-$($ssrv.Id)"
  $sbefore = Test-Path -LiteralPath (Join-Path $shome 'config.json')
  [void](Invoke-WebRequest -UseBasicParsing "${surl}quit" -Method Post -Body 'quit'); [void]$ssrv.WaitForExit(5000)
  Check 'a -From (sample) server never writes the profile, and cleans up' ($sc1 -and $sbefore -and -not (Test-Path -LiteralPath (Join-Path $sprof '.tile-windows')) -and -not (Test-Path -LiteralPath $shome))
  $fsrv = Start-Child $fprof "-File `"$serve`" -NoBrowser -From `"$fixture`"" @{ TILE_HOME = (Join-Path $fprof '.tile-windows') }
  $furl = $fsrv.StandardOutput.ReadLine()
  $noFile = -not (Test-Path -LiteralPath $fcfg)
  $c1 = (Invoke-WebRequest -UseBasicParsing "${furl}config").Content
  Check 'config file created on first run, from the starters' ($noFile -and (Test-Path -LiteralPath $fcfg) -and ((ConvertFrom-Json $c1).scenes.id -join ',') -eq 'default,focus,meetings,review,listen,solo,thursday-prep')
  # Save a scene with awkward text, read it back byte for byte, then run it through the engine by name.
  $cfg = ConvertFrom-Json $c1
  $new = ConvertFrom-Json '{"id":"x-1","name":"Late \"night\" — it''s ünïcode","trigger":{"type":"time","days":[1,3],"time":"21:30"},"grids":{"wide":{"c":2,"r":1}},"pins":[{"app":"chrome","match":"It''s a \"quoted\"","mon":"wide","slots":[1]}],"fill":{"mon":"wide","apps":["claude"],"skip":[],"sort":"title"}}'
  $cfg.scenes = @($cfg.scenes) + $new
  $body = ConvertTo-Json -Depth 10 -Compress $cfg
  $ok = (Status "${furl}config" $null) -eq 200 -and (Post "${furl}config" $body) -eq 'Saved'
  $back = (Invoke-WebRequest -UseBasicParsing "${furl}config").Content
  Check 'scene save/load round trip (server)' ($ok -and $back -ceq $body -and [IO.File]::ReadAllText($fcfg, $utf8) -ceq $body)
  $env:TILE_HOME = Join-Path $fprof '.tile-windows'
  try { $r = (& $tile -Scene 'x-1' -From $fixture -Json 3>$null) -join '' | ConvertFrom-Json } finally { $env:TILE_HOME = $null }
  $p0 = @($r.placed | ? { $_.pin -eq 0 })[0]
  Check 'a saved scene runs by name through the engine' ($p0.id -eq 1007 -and $p0.x -eq 2048 -and $p0.w -eq 2048 -and @($r.placed | ? { $_.app -eq 'claude' })[0].title -eq 'Claude') ($r | ConvertTo-Json -Compress -Depth 5)
  Check 'server refuses a config without scenes, and keeps the file' ((Status "${furl}config" '{"scenes":"no"}') -eq 400 -and [IO.File]::ReadAllText($fcfg, $utf8) -ceq $body)
  [void](Post "${furl}config" $c1)
  # A config.json or state.json that does not parse: starters (or an empty log) come back, the bad text
  # is kept as .bad, and the page is told.
  [IO.File]::WriteAllText($fcfg, '{"scenes":[{bad', $utf8); $fst = Join-Path $fprof '.tile-windows\state.json'; [IO.File]::WriteAllText($fst, 'nope', $utf8)
  $rc = Invoke-WebRequest -UseBasicParsing "${furl}config"; $rs = Invoke-WebRequest -UseBasicParsing "${furl}state"
  Check 'a bad config.json falls back to the starters, keeps .bad, and says so' (((ConvertFrom-Json $rc.Content).scenes.id -join ',') -eq 'default,focus,meetings,review,listen,solo,thursday-prep' -and [IO.File]::ReadAllText("$fcfg.bad", $utf8) -ceq '{"scenes":[{bad' -and [Uri]::UnescapeDataString($rc.Headers['X-Tile-Note']) -like 'config.json could not be read*')
  Check 'a bad state.json gives an empty log, keeps .bad, and says so' (@((ConvertFrom-Json $rs.Content).log).Count -eq 0 -and [IO.File]::ReadAllText("$fst.bad", $utf8) -ceq 'nope' -and [Uri]::UnescapeDataString($rs.Headers['X-Tile-Note']) -like '*state.json could not be read*')
  # The note stays on every answer (the tray may have hit the bad file) until the page dismisses it.
  $rn = Invoke-WebRequest -UseBasicParsing "${furl}snapshot"; [void](Post "${furl}note" 'dismiss'); $rn2 = Invoke-WebRequest -UseBasicParsing "${furl}config"
  Check 'the recovery note stays until the page dismisses it' ([Uri]::UnescapeDataString($rn.Headers['X-Tile-Note']) -like 'config.json could not be read*state.json could not be read*' -and -not $rn2.Headers['X-Tile-Note']) $rn.Headers['X-Tile-Note']
  [IO.File]::WriteAllText($fcfg, '{"scenes":[{worse', $utf8); [void](Invoke-WebRequest -UseBasicParsing "${furl}config"); [void](Post "${furl}note" 'dismiss')
  $bads = @(Get-ChildItem -LiteralPath (Split-Path $fcfg) -Filter 'config.json.*.bad')
  Check 'a second bad config.json keeps the first .bad' ([IO.File]::ReadAllText("$fcfg.bad", $utf8) -ceq '{"scenes":[{bad' -and $bads.Count -eq 1 -and [IO.File]::ReadAllText($bads[0].FullName, $utf8) -ceq '{"scenes":[{worse') ($bads.Name -join ',')
  [IO.File]::WriteAllText($fst, '[1,2', $utf8); $env:TILE_HOME = Join-Path $fprof '.tile-windows'
  try { . (Join-Path $root 'config.ps1'); $threw = $false; try { Add-TileLog 'focus' 'after a move' 3>$null } catch { $threw = $true }; $st2 = ConvertFrom-Json (Get-TileStateText) } finally { $env:TILE_HOME = $null; . (Join-Path $root 'config.ps1') }
  Check 'Add-TileLog on a bad state.json does not throw and starts a fresh log' (-not $threw -and $st2.active -eq 'focus' -and @($st2.log).Count -eq 1)
  [void](Post "${furl}config" $c1)

  # Writers in three processes at once, released together: every log entry lands (each tagged by writer;
  # 3 x 6 fits the 20-entry log), every config write lands whole, no temp file is left behind.
  $whome = Join-Path $tmp 'writers'; $wjob = Join-Path $tmp 'writer.ps1'; $wgo = Join-Path $tmp 'writers-go'
  Set-Content -LiteralPath $wjob -Encoding ASCII -Value @"
. '$(Join-Path $root 'config.ps1')'; `$ErrorActionPreference = 'Stop'
`$starters = [IO.File]::ReadAllText('$(Join-Path $root 'scenes.json')')
while (-not (Test-Path -LiteralPath '$wgo')) { Start-Sleep -Milliseconds 10 }
1..6 | % { Add-TileLog "w`$PID" "w`$PID-`$_" 3>&1 | % { throw "`$_" }; Save-TileConfigText `$starters }
'ok'
"@
  $ws = @(1..3 | % { Start-Child $null "-File `"$wjob`"" @{ TILE_HOME = $whome } }); Start-Sleep -Milliseconds 1500; New-Item -ItemType File $wgo | Out-Null
  $wout = @($ws | % { $_.StandardOutput.ReadToEnd().Trim() + $_.StandardError.ReadToEnd().Trim() })
  $ws | % { $_.WaitForExit() }
  $wst = try { ConvertFrom-Json ([IO.File]::ReadAllText((Join-Path $whome 'state.json'))) } catch { $null }
  Check 'three processes writing config and log at once: all writes land, no temp files left' (($wout -join ',') -eq 'ok,ok,ok' -and @($ws | % { $p = $_.Id; 1..6 | % { "w$p-$_" } } | ? { @($wst.log.x) -notcontains $_ }).Count -eq 0 -and @($wst.log).Count -eq 18 -and @(Get-ChildItem -LiteralPath $whome -Filter '*.tmp').Count -eq 0) ("$($wout -join ' | ') log: $(@($wst.log).Count)")

  # 6. Browser cases: headless Edge runs the page's self-test hooks, which run only when the server is a dry run.
  if (-not $edge) { 'SKIP  browser cases: Microsoft Edge not found in either Program Files folder.' } else {
    # Undo (decision: undo-moves-windows). The hook applies a scene that moves one window (dry run), then undoes.
    $st = SelfTest $furl 'undo'
    Check 'page self-test ran' ($null -ne $st)
    $o = $st.applyUndo.r; $b = @($st.applyUndo.bodies)
    $u = @(if ($b.Count -eq 2) { $b[1] })
    $fx = (Get-Content -Raw $fixture | ConvertFrom-Json).windows
    Check 'Apply then Undo sends the original rects, one window' ($b.Count -eq 2 -and @($b[0].pins)[0].slots[0] -eq 9 -and $u.Count -eq 1 -and $u[0].id -eq $o.id -and $u[0].x -eq $o.x -and $u[0].y -eq $o.y -and $u[0].w -eq $o.w -and $u[0].h -eq $o.h -and $o.x -eq $fx[0].x -and $o.w -eq $fx[0].w) ('n=' + $b.Count + ' u=' + $u.Count + ' ' + ($o | ConvertTo-Json -Compress) + ' ' + ($u | ConvertTo-Json -Compress))
    Check 'Undo with no Apply sends nothing' ((N $st.undoNoApply.bodies) -eq 0)
    Check 'Undo of a drag made after Apply sends nothing more' ((N $st.undoDragAfterApply.bodies) -eq 1)
    Check 'Undo after Refresh sends nothing more' ((N $st.undoAfterRefresh.bodies) -eq 1)
    $bz = $st.busy.r
    Check 'Undo, Refresh and moves are off while Apply runs' ($bz.undoOff -and $bz.refreshOff -and $bz.kept) ($bz | ConvertTo-Json -Compress)

    # Page preview == engine, for each starter scene, on the fixture.
    $ss = SelfTest $furl 'scenes'
    foreach ($id in 'default', 'focus', 'meetings', 'review') {
      $eng = ((& $tile -Scene (StarterJson $id) -From $fixture -Json 3>$null) -join '' | ConvertFrom-Json).placed | Sort-Object id | % { "$($_.id):$($_.x),$($_.y),$($_.w)x$($_.h)" }
      $pg = @($ss.drawn.$id) | Sort-Object id | % { "$($_.id):$($_.x),$($_.y),$($_.w)x$($_.h)" }
      Check "page preview == engine: $id" ($eng.Count -gt 0 -and ($eng -join ' ') -ceq ($pg -join ' ')) ("engine: $($eng -join ' ') | page: $($pg -join ' ')")
    }
    Check 'page cell size rounds like tile.ps1 ([int], to even)' ($ss.cell.w -eq [int](1365 / 2) -and $ss.cell.h -eq [int](1001 / 2)) ($ss.cell | ConvertTo-Json -Compress)
    Check 'page Save as new writes the scene to config.json' (@($ss.names) -contains 'Selftest copy' -and ([IO.File]::ReadAllText($fcfg, $utf8)).Contains('"Selftest copy"')) (@($ss.names) -join ',')
  }
  [void](Invoke-WebRequest -UseBasicParsing "${furl}quit" -Method Post -Body 'quit')
  Check 'fixture server exits on /quit' ($fsrv.WaitForExit(5000))

  # 7. The offline page's category map is the starters' map (file:// pages cannot read scenes.json).
  $off = if ([IO.File]::ReadAllText((Join-Path $root 'app.html'), $utf8) -match 'const OFFLINE_CATS=(\{.*?\});') { ConvertFrom-Json $matches[1] }
  Check 'offline category map matches scenes.json' ($off -and (($off.PSObject.Properties | % { "$($_.Name)=$($_.Value)" }) -join ',') -ceq (($starters.cats.PSObject.Properties | % { "$($_.Name)=$($_.Value)" }) -join ','))

  $dead = @([regex]::Matches([IO.File]::ReadAllText((Join-Path $root 'README.md'), $utf8), '\]\(([^)#:]+)\)') | % { $_.Groups[1].Value } | ? { -not (Test-Path -LiteralPath (Join-Path $root $_)) })
  Check 'README links to files that exist' ($dead.Count -eq 0) ($dead -join ', ')

  # 8. Tray agent: the trigger rules, then a real start and quit (no icon, dry run, temp profile).
  . (Join-Path $root 'tray.ps1') -Lib
  $tc = ConvertFrom-Json '{"scenes":[{"id":"a","trigger":{"type":"time","days":[1,2,3,4,5],"time":"09:00"}},{"id":"b","trigger":{"type":"time","days":[6],"time":"09:00"}},{"id":"c","trigger":{"type":"display"}},{"id":"d","trigger":{"type":"manual"}}]}'
  $mon9 = [datetime]'2026-10-19 09:00:30'  # a Monday
  Check 'tray: a scheduled scene is due on its day and minute only' ((@(Get-DueScenes $tc $mon9 @{}).id -join ',') -eq 'a' -and @(Get-DueScenes $tc $mon9.AddMinutes(1) @{}).Count -eq 0 -and (@(Get-DueScenes $tc ([datetime]'2026-10-24 09:00') @{}).id -join ',') -eq 'b')
  Check 'tray: a scheduled scene fires once per minute' (@(Get-DueScenes $tc $mon9 @{ a = '2026-10-19 09:00' }).Count -eq 0)
  Check 'tray: display scenes and the monitor key' ((@(Get-DisplayScenes $tc).id -join ',') -eq 'c' -and (Get-MonitorKey @([pscustomobject]@{ DeviceName = 'B'; Bounds = [Drawing.Rectangle]::new(0, 0, 10, 20) }, [pscustomobject]@{ DeviceName = 'A'; Bounds = [Drawing.Rectangle]::new(-5, 1, 3, 4) })) -eq 'A=3x4@-5,1;B=10x20@0,0')
  $cases = @(ConvertFrom-Json (Get-Content -Raw (Join-Path $PSScriptRoot 'teams-call.json')) | % { $_ })
  $bad = @($cases | ? { (Test-TeamsCall $_.mic $_.wins) -ne $_.call } | % { $_.case })
  Check 'tray: Teams call detection, every fixture case' ($cases.Count -eq 11 -and $bad.Count -eq 0) ($bad -join '; ')
  $cc = ConvertFrom-Json '{"scenes":[{"id":"work","trigger":{"type":"manual"}},{"id":"meet","trigger":{"type":"call","back":true}}]}'
  $s1 = Step-CallTrigger $false $true $cc 'work' ''; $s2 = Step-CallTrigger $true $true $cc 'meet' $s1.back; $s3 = Step-CallTrigger $true $false $cc 'meet' $s2.back
  $cc.scenes[1].trigger.back = $false; $s4 = Step-CallTrigger $true $false $cc 'meet' 'work'
  Check 'tray: call start applies the call scene; call end goes back only when asked' ($s1.apply -eq 'meet' -and $s1.back -eq 'work' -and $s2.apply -eq '' -and $s3.apply -eq 'work' -and $s4.apply -eq '') (($s1, $s2, $s3, $s4 | ConvertTo-Json -Compress))
  $tt = ConvertFrom-Json '{"scenes":[{"id":"a","trigger":{"type":"time","days":[1],"time":"09:00"}},{"id":"c","trigger":{"type":"display"}},{"id":"c2","trigger":{"type":"display"}},{"id":"work","trigger":{"type":"manual"}},{"id":"meet","trigger":{"type":"call","back":true}}]}'
  function Ids($x) { (@($x) | % { $_.id }) -join ',' }
  $ts = New-TrayState
  $r1 = Ids (Step-Tray $ts $mon9 $tt $null $null ''); $r2 = Ids (Step-Tray $ts $mon9.AddSeconds(20) $tt $null $null '')
  Check 'tray tick: a scheduled scene fires once in its minute' ($r1 -eq 'a' -and $r2 -eq '') "$r1 / $r2"
  $ts = New-TrayState; $d = [datetime]'2026-10-20 10:00'
  $k1 = Ids (Step-Tray $ts $d $tt 'A' $null ''); $k2 = Ids (Step-Tray $ts $d $tt 'B' $null ''); $k3 = Ids (Step-Tray $ts $d $tt 'B' $null ''); $k4 = Ids (Step-Tray $ts $d $tt $null $null '')
  Check 'tray tick: a monitor change applies the first display scene, once' ($k1 -eq '' -and $k2 -eq 'c' -and $k3 -eq '' -and $k4 -eq '') "$k1 / $k2 / $k3 / $k4"
  $ts = New-TrayState
  $c = @(@($false, 'work'), @($true, 'work'), @($true, 'work'), @($false, 'meet'), @($true, 'meet'), @($false, 'meet'), @($false, 'meet')) | % { Ids (Step-Tray $ts $d $tt $null $_[0] $_[1]) }
  Check 'tray tick: a call starts and ends only after 2 readings agree, then goes back' (($c -join '/') -eq '//meet////work') ($c -join '/')
  $ts = New-TrayState; $m1 = Ids (Step-Tray $ts $d $tt $null $true 'meet'); $m2 = Ids (Step-Tray $ts $d $tt $null $true 'meet')
  Check 'tray tick: starting mid-call applies nothing' ($m1 -eq '' -and $m2 -eq '' -and $ts.inCall) "$m1 / $m2"
  # A half-counted start does not carry over when the call scenes change: the reading starts over.
  $tt2 = ConvertFrom-Json '{"scenes":[{"id":"work","trigger":{"type":"manual"}},{"id":"meet2","trigger":{"type":"call"}}]}'
  $ts = New-TrayState; $x = @((Ids (Step-Tray $ts $d $tt $null $false 'work')), (Ids (Step-Tray $ts $d $tt $null $true 'work')), (Ids (Step-Tray $ts $d $tt2 $null $true 'work')))
  Check 'tray tick: a change to the call scenes starts the call reading over' (($x -join '/') -eq '//' -and $ts.inCall -and $ts.streak -eq 0) ($x -join '/')
  # The automatic triggers (idle, new window, activity, meeting size, guards...) have their own file; a child scope keeps its variables out of this run.
  & { . (Join-Path $PSScriptRoot 'triggers.ps1') }
  $tprof = Profile 'tray'
  $tray = Start-Child $tprof "-File `"$(Join-Path $root 'tray.ps1')`" -NoIcon -NoApply"
  $real = $env:USERPROFILE; $env:USERPROFILE = $tprof
  try { . (Join-Path $root 'config.ps1'); $agent = TrayName 'Agent'; $quit = TrayName 'Quit' } finally { $env:USERPROFILE = $real; . (Join-Path $root 'config.ps1') }
  $t0 = Get-Date; $m = $null
  while (-not [Threading.Mutex]::TryOpenExisting($agent, [ref]$m) -and ((Get-Date) - $t0).TotalSeconds -lt 15 -and -not $tray.HasExited) { Start-Sleep -Milliseconds 200 }
  $up = [bool]$m; if ($m) { $m.Dispose() }
  if ($up) { Start-Sleep -Milliseconds 500; [void][Threading.EventWaitHandle]::OpenExisting($quit).Set() }
  Check 'tray agent starts and quits on its Quit event' ($up -and $tray.WaitForExit(8000) -and $tray.ExitCode -eq 0) ("up=$up exited=$($tray.HasExited) err=" + $(if ($tray.HasExited) { $tray.StandardError.ReadToEnd() }))

  # 9. Installer, piped as the one-liner runs it, into a temp profile; then uninstall.
  $iprof = Profile 'inst'
  $ins = Start-Child $iprof "-Command `"Get-Content -Raw -LiteralPath '$(Join-Path $root 'install.ps1')' | Invoke-Expression`"" @{ TILE_SOURCE = $root; TILE_NO_LAUNCH = '1' }
  $iout = $ins.StandardOutput.ReadToEnd(); $ierr = $ins.StandardError.ReadToEnd(); $ins.WaitForExit()
  $iapp = Join-Path $iprof '.tile-windows\app'; $iprog = Join-Path $iprof 'AppData\Roaming\Microsoft\Windows\Start Menu\Programs'
  $lnk = (New-Object -ComObject WScript.Shell).CreateShortcut((Join-Path $iprog 'Tile Windows.lnk'))
  Check 'installer (piped) copies the app and adds both shortcuts' ($ins.ExitCode -eq 0 -and @(Get-ChildItem -LiteralPath $iapp -ErrorAction SilentlyContinue).Count -eq 9 -and $lnk.Arguments -like "*$iapp\tray.ps1`" -Open" -and (Test-Path -LiteralPath (Join-Path $iprog 'Startup\Tile Windows tray.lnk'))) "$iout $ierr"
  Check 'installer writes only into the profile it is given' (-not (Test-Path -LiteralPath (Join-Path $env:USERPROFILE '.tile-windows\app')) -and -not (Test-Path -LiteralPath (Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Tile Windows.lnk')))
  # Run in a temp profile, a hard-coded path would still land in the real one, so read the scripts too:
  # every path must come from USERPROFILE or APPDATA (PowerShell's own tokenizer, so comments do not count).
  $hard = foreach ($f in 'install.ps1', 'uninstall.ps1', 'config.ps1', 'tray.ps1', 'serve.ps1') {
    $e = $null; foreach ($t in [Management.Automation.PSParser]::Tokenize([IO.File]::ReadAllText((Join-Path $root $f)), [ref]$e)) {
      if ($t.Type -eq 'Comment') { continue }
      if (($t.Type -eq 'Variable' -and $t.Content -match '^(HOME|env:(HOMEPATH|HOMEDRIVE|LOCALAPPDATA|HOME))$') -or $t.Content -match '(?i)GetFolderPath|SpecialFolder|\b[a-z]:\\users\\') { "${f}:$($t.StartLine) $($t.Content)" }
    } }
  Check 'installer and app take every profile path from USERPROFILE or APPDATA' (-not $hard) ($hard -join '; ')
  # Again, with -NoStartup and the installed tray agent running: same files, no staging folder left,
  # the login shortcut goes away, and the old agent was told to quit before the swap.
  $real = $env:USERPROFILE; $env:USERPROFILE = $iprof
  try { . (Join-Path $root 'config.ps1'); $iagent = TrayName 'Agent' } finally { $env:USERPROFILE = $real; . (Join-Path $root 'config.ps1') }
  $itray = Start-Child $iprof "-File `"$(Join-Path $iapp 'tray.ps1')`" -NoIcon -NoApply"; $t0 = Get-Date; $m = $null
  while (-not [Threading.Mutex]::TryOpenExisting($iagent, [ref]$m) -and ((Get-Date) - $t0).TotalSeconds -lt 15 -and -not $itray.HasExited) { Start-Sleep -Milliseconds 200 }
  $iup = [bool]$m; if ($m) { $m.Dispose() }
  $ins2 = Start-Child $iprof "-File `"$(Join-Path $root 'install.ps1')`" -NoStartup -NoLaunch" @{ TILE_SOURCE = $root }; $i2 = $ins2.StandardOutput.ReadToEnd() + $ins2.StandardError.ReadToEnd(); $ins2.WaitForExit()
  $iquit = $itray.HasExited; if (-not $iquit) { $itray.Kill() }
  Check 'installing again first stops the running tray agent' ($iup -and $iquit) "up=$iup quit=$iquit"
  Check 'installing again works in place; -NoStartup drops the login shortcut' ($ins2.ExitCode -eq 0 -and @(Get-ChildItem -LiteralPath $iapp).Count -eq 9 -and @(Get-ChildItem -LiteralPath (Join-Path $iprof '.tile-windows') -Filter 'app.new-*').Count -eq 0 -and (Test-Path -LiteralPath (Join-Path $iprog 'Tile Windows.lnk')) -and -not (Test-Path -LiteralPath (Join-Path $iprog 'Startup\Tile Windows tray.lnk'))) $i2
  # A failed copy (a missing source file) leaves the installed app as it was.
  $bsrc = Join-Path $tmp 'badsrc'; New-Item -ItemType Directory $bsrc | Out-Null; Get-ChildItem -LiteralPath $root -File | Copy-Item -Destination $bsrc; Remove-Item -LiteralPath (Join-Path $bsrc 'README.md')
  $stamp = (Get-Item -LiteralPath (Join-Path $iapp 'tile.ps1')).LastWriteTimeUtc
  $ins3 = Start-Child $iprof "-File `"$(Join-Path $bsrc 'install.ps1')`" -NoLaunch" @{ TILE_SOURCE = $bsrc }; [void]$ins3.StandardOutput.ReadToEnd(); [void]$ins3.StandardError.ReadToEnd(); $ins3.WaitForExit()
  Check 'a failed install leaves the old app in place' ($ins3.ExitCode -ne 0 -and @(Get-ChildItem -LiteralPath $iapp).Count -eq 9 -and (Get-Item -LiteralPath (Join-Path $iapp 'tile.ps1')).LastWriteTimeUtc -eq $stamp -and @(Get-ChildItem -LiteralPath (Join-Path $iprof '.tile-windows') -Filter 'app.new-*').Count -eq 0)
  # A failure between the two renames of the swap puts the old app back, and it still runs.
  $ins5 = Start-Child $iprof "-File `"$(Join-Path $root 'install.ps1')`" -NoLaunch" @{ TILE_SOURCE = $root; TILE_TEST_SWAP_FAIL = '1' }; [void]$ins5.StandardOutput.ReadToEnd(); [void]$ins5.StandardError.ReadToEnd(); $ins5.WaitForExit()
  $runs = ''; $runsOk = $false; if (Test-Path -LiteralPath (Join-Path $iapp 'tile.ps1')) { $runs = (Child (Join-Path $iapp 'tile.ps1') -From (Join-Path $root 'test\fixture.json') -Default 2>&1 | Out-String); $runsOk = $LASTEXITCODE -eq 0 }
  Check 'a failure mid-swap puts the old app back, and it runs' ($ins5.ExitCode -ne 0 -and (Test-Path -LiteralPath (Join-Path $iapp 'tile.ps1')) -and @(Get-ChildItem -LiteralPath $iapp).Count -eq 9 -and (Get-Item -LiteralPath (Join-Path $iapp 'tile.ps1')).LastWriteTimeUtc -eq $stamp -and @(Get-ChildItem -LiteralPath (Join-Path $iprof '.tile-windows') -Filter 'app.*-*').Count -eq 0 -and $runsOk) $runs
  New-Item -ItemType File (Join-Path $iprof '.tile-windows\config.json') -Force | Out-Null
  $un = Start-Child $iprof "-File `"$(Join-Path $iapp 'uninstall.ps1')`""; $uout = $un.StandardOutput.ReadToEnd() + $un.StandardError.ReadToEnd(); $un.WaitForExit()
  Check 'uninstall removes the app and shortcuts, keeps scenes' ($un.ExitCode -eq 0 -and -not (Test-Path -LiteralPath $iapp) -and -not (Test-Path -LiteralPath (Join-Path $iprog 'Tile Windows.lnk')) -and -not (Test-Path -LiteralPath (Join-Path $iprog 'Startup\Tile Windows tray.lnk')) -and (Test-Path -LiteralPath (Join-Path $iprof '.tile-windows\config.json'))) $uout
  $ins4 = Start-Child $iprof "-File `"$(Join-Path $root 'install.ps1')`" -NoLaunch" @{ TILE_SOURCE = $root }; [void]$ins4.StandardOutput.ReadToEnd(); [void]$ins4.StandardError.ReadToEnd(); $ins4.WaitForExit()
  $un2 = Start-Child $iprof "-File `"$(Join-Path $iapp 'uninstall.ps1')`" -Purge"; $u2 = $un2.StandardOutput.ReadToEnd() + $un2.StandardError.ReadToEnd(); $un2.WaitForExit()
  Check 'uninstall -Purge removes the scenes too' ($un2.ExitCode -eq 0 -and -not (Test-Path -LiteralPath (Join-Path $iprof '.tile-windows')) -and -not (Test-Path -LiteralPath (Join-Path $iprog 'Tile Windows.lnk'))) $u2

  # 10. -Default -DryRun prints the same as main's tile.ps1 (run back to back; windows can change between runs).
  #     -Default now runs the Default scene from scenes.json, so this also proves the scene engine mirrors it.
  #     It runs main's whole tree: tile.ps1 reads config.ps1 and scenes.json beside it.
  $ref = if ($env:TILE_TEST_MAIN) { $env:TILE_TEST_MAIN } else { 'main' }
  $zip = Join-Path $tmp 'main.zip'; $mainDir = Join-Path $tmp 'main'
  & git -C $root archive -o $zip $ref 2>$null; if ($LASTEXITCODE) { & git -C $root archive -o $zip "origin/$ref" }
  Expand-Archive -LiteralPath $zip -DestinationPath $mainDir
  $main = Join-Path $mainDir 'tile.ps1'
  $same = $false
  for ($k = 0; $k -lt 2 -and -not $same; $k++) {
    $a = (Child $main -Default -DryRun 2>&1 | % { "$_" }) -join "`n"
    $b = (Child $tile -Default -DryRun 2>&1 | % { "$_" }) -join "`n"
    $same = $a -ceq $b
  }
  Check '-Default -DryRun unchanged from main' $same
} catch {
  $script:fail++; "FAIL  run stopped: $_"
} finally {
  if ($form -and -not $form.HasExited) { Stop-Process -Id $form.Id -Force }
  foreach ($p in $srv, $fsrv, $ssrv, $tray) { if ($p -and -not $p.HasExited) { $p.Kill() } }
  foreach ($k in $saved.Keys) { if ($null -eq $saved[$k]) { Remove-Item "env:$k" -ErrorAction SilentlyContinue } else { Set-Item "env:$k" $saved[$k] } }
  Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
}
if ($script:fail) { "$($script:fail) check(s) failed."; exit 1 } else { 'All checks passed.' }
