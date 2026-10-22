# Checks for tile.ps1, serve.ps1, app.html, tray.ps1 and install.ps1. Plain asserts; moves no window
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
  if ($prof) { $psi.EnvironmentVariables['USERPROFILE'] = $prof; $psi.EnvironmentVariables['APPDATA'] = Join-Path $prof 'AppData\Roaming' }
  foreach ($k in $extra.Keys) { $psi.EnvironmentVariables[$k] = $extra[$k] }
  [Diagnostics.Process]::Start($psi)
}
function Post($url, $body) { (Invoke-WebRequest -UseBasicParsing $url -Method Post -ContentType 'application/json; charset=utf-8' -Body ($utf8.GetBytes($body))).Content }
$edge = @("${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe", "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe") | ? { Test-Path -LiteralPath $_ } | Select-Object -First 1
# Run one of the page's #selftest-* hooks in headless Edge; returns its JSON, or $null.
function SelfTest($url, $hook) {
  $dom = Join-Path $tmp "dom-$hook.html"
  Start-Process $edge -Wait -WindowStyle Hidden -RedirectStandardOutput $dom -RedirectStandardError (Join-Path $tmp "edge-$hook.log") -ArgumentList '--headless', '--disable-gpu', '--no-first-run', "--user-data-dir=$tmp\edge-$hook", '--virtual-time-budget=90000', '--dump-dom', "${url}#selftest-$hook"
  if ((Get-Content -Raw -Encoding UTF8 $dom) -match '<pre id="selftest">(.*?)</pre>') { [Net.WebUtility]::HtmlDecode($matches[1]) | ConvertFrom-Json }
}
# A starter scene as the page sends it: the scene plus the category map.
$starters = [IO.File]::ReadAllText((Join-Path $root 'scenes.json'), $utf8) | ConvertFrom-Json
function StarterJson($id) { $s = @($starters.scenes | ? { $_.id -eq $id })[0]; $s | Add-Member -Force cats $starters.cats; $s | Add-Member -Force categories $starters.categories; ConvertTo-Json -Depth 10 -Compress $s }

$form = $null; $srv = $null; $fsrv = $null; $tray = $null
$realHome = Join-Path $env:USERPROFILE '.tile-windows'; $realLink = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Tile Windows.lnk'
$realBefore = "$(Test-Path -LiteralPath $realHome)|$(if (Test-Path -LiteralPath $realHome) { (Get-ChildItem -Recurse -Force -LiteralPath $realHome | % { "$($_.FullName)@$($_.LastWriteTimeUtc.Ticks)" }) -join ',' })|$(Test-Path -LiteralPath $realLink)"
try {
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
  $fsrv = Start-Child $fprof "-File `"$serve`" -NoBrowser -From `"$fixture`""
  $furl = $fsrv.StandardOutput.ReadLine()
  $noFile = -not (Test-Path -LiteralPath $fcfg)
  $c1 = (Invoke-WebRequest -UseBasicParsing "${furl}config").Content
  Check 'config file created on first run, from the starters' ($noFile -and (Test-Path -LiteralPath $fcfg) -and ((ConvertFrom-Json $c1).scenes.id -join ',') -eq 'default,focus,meetings,review')
  # Save a scene with awkward text, read it back byte for byte, then run it through the engine by name.
  $cfg = ConvertFrom-Json $c1
  $new = ConvertFrom-Json '{"id":"x-1","name":"Late \"night\" — it''s ünïcode","trigger":{"type":"time","days":[1,3],"time":"21:30"},"grids":{"wide":{"c":2,"r":1}},"pins":[{"app":"chrome","match":"It''s a \"quoted\"","mon":"wide","slots":[1]}],"fill":{"mon":"wide","apps":["claude"],"skip":[],"sort":"title"}}'
  $cfg.scenes = @($cfg.scenes) + $new
  $body = ConvertTo-Json -Depth 10 -Compress $cfg
  $ok = (Status "${furl}config" $null) -eq 200 -and (Post "${furl}config" $body) -eq 'Saved'
  $back = (Invoke-WebRequest -UseBasicParsing "${furl}config").Content
  Check 'scene save/load round trip (server)' ($ok -and $back -ceq $body -and [IO.File]::ReadAllText($fcfg, $utf8) -ceq $body)
  $env:USERPROFILE, $real = $fprof, $env:USERPROFILE
  try { $r = (& $tile -Scene 'x-1' -From $fixture -Json 3>$null) -join '' | ConvertFrom-Json } finally { $env:USERPROFILE = $real }
  $p0 = @($r.placed | ? { $_.pin -eq 0 })[0]
  Check 'a saved scene runs by name through the engine' ($p0.id -eq 1007 -and $p0.x -eq 2048 -and $p0.w -eq 2048 -and @($r.placed | ? { $_.app -eq 'claude' })[0].title -eq 'Claude') ($r | ConvertTo-Json -Compress -Depth 5)
  Check 'server refuses a config without scenes, and keeps the file' ((Status "${furl}config" '{"scenes":"no"}') -eq 400 -and [IO.File]::ReadAllText($fcfg, $utf8) -ceq $body)
  [void](Post "${furl}config" $c1)

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
  $tprof = Profile 'tray'
  $tray = Start-Child $tprof "-File `"$(Join-Path $root 'tray.ps1')`" -NoIcon -NoApply"
  $env:USERPROFILE, $real = $tprof, $env:USERPROFILE
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
  $realAfter = "$(Test-Path -LiteralPath $realHome)|$(if (Test-Path -LiteralPath $realHome) { (Get-ChildItem -Recurse -Force -LiteralPath $realHome | % { "$($_.FullName)@$($_.LastWriteTimeUtc.Ticks)" }) -join ',' })|$(Test-Path -LiteralPath $realLink)"
  Check 'installer into a temp profile leaves the real one alone' ($realAfter -ceq $realBefore) "before: $realBefore after: $realAfter"
  New-Item -ItemType File (Join-Path $iprof '.tile-windows\config.json') -Force | Out-Null
  $un = Start-Child $iprof "-File `"$(Join-Path $iapp 'uninstall.ps1')`""; $uout = $un.StandardOutput.ReadToEnd() + $un.StandardError.ReadToEnd(); $un.WaitForExit()
  Check 'uninstall removes the app and shortcuts, keeps scenes' ($un.ExitCode -eq 0 -and -not (Test-Path -LiteralPath $iapp) -and -not (Test-Path -LiteralPath (Join-Path $iprog 'Tile Windows.lnk')) -and -not (Test-Path -LiteralPath (Join-Path $iprog 'Startup\Tile Windows tray.lnk')) -and (Test-Path -LiteralPath (Join-Path $iprof '.tile-windows\config.json'))) $uout

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
  foreach ($p in $srv, $fsrv, $tray) { if ($p -and -not $p.HasExited) { $p.Kill() } }
  Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
}
if ($script:fail) { "$($script:fail) check(s) failed."; exit 1 } else { 'All checks passed.' }
