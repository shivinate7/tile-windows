# Checks for tile.ps1 and serve.ps1. Plain asserts; moves no window (every place call is a dry run).
# Run: powershell -NoProfile -ExecutionPolicy Bypass -File test\run.ps1
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
$tile = Join-Path $root 'tile.ps1'; $serve = Join-Path $root 'serve.ps1'
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

$form = $null; $srv = $null
try {
  # 1. Snapshot JSON parses (in-process, as serve.ps1 calls it).
  $snapText = (& $tile -Json 2>$null) -join ''
  $snap = $snapText | ConvertFrom-Json
  Check 'snapshot JSON parses' ($snap.monitors.Count -ge 1 -and $null -ne $snap.windows)

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
  $psi = New-Object Diagnostics.ProcessStartInfo 'powershell', "-NoProfile -ExecutionPolicy Bypass -File `"$serve`" -NoBrowser -DryRun"
  $psi.UseShellExecute = $false; $psi.RedirectStandardOutput = $true; $psi.CreateNoWindow = $true
  $srv = [Diagnostics.Process]::Start($psi)
  $url = $srv.StandardOutput.ReadLine()
  $base = $url -replace '[0-9a-f]{32}/$', ''
  Check 'server prints a tokened URL' ($url -match '^http://127\.0\.0\.1:\d+/[0-9a-f]{32}/$') $url
  Check 'server rejects a missing token' ((Status "${base}snapshot") -eq 403)
  Check 'server rejects a wrong token' ((Status "${base}00000000000000000000000000000000/snapshot") -eq 403)
  $s2 = (Invoke-WebRequest -UseBasicParsing "${url}snapshot").Content | ConvertFrom-Json
  Check 'server snapshot parses' ($s2.monitors.Count -ge 1)
  $r = Invoke-WebRequest -UseBasicParsing "${url}apply" -Method Post -ContentType 'application/json; charset=utf-8' -Body ($utf8.GetBytes($js))
  $res = @($r.Content | ConvertFrom-Json)
  Check 'title survives page -> /apply (dry run)' ($res.Count -eq 1 -and $res[0].ok -and $res[0].title -ceq $title -and $res[0].note -like 'dry run*') $r.Content
  Check 'server refuses a non-array apply' ((Status "${url}apply" ' ') -eq 400)
  Check 'server refuses bad JSON' ((Status "${url}apply" '[{"app":') -eq 400)

  # 5. Undo (decision: undo-moves-windows). Headless Edge runs the page's #selftest-undo hook,
  #    which runs only when the server says it is in -DryRun.
  $edge = @("${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe", "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe") | ? { Test-Path -LiteralPath $_ } | Select-Object -First 1
  if (-not $edge) { 'SKIP  browser cases (Undo): Microsoft Edge not found in either Program Files folder.' } else {
    $dom = Join-Path $tmp 'dom.html'
    Start-Process $edge -Wait -WindowStyle Hidden -RedirectStandardOutput $dom -RedirectStandardError (Join-Path $tmp 'edge.log') -ArgumentList '--headless', '--disable-gpu', '--no-first-run', "--user-data-dir=$tmp\edge", '--virtual-time-budget=60000', '--dump-dom', "${url}#selftest-undo"
    $st = if ((Get-Content -Raw -Encoding UTF8 $dom) -match '<pre id="selftest">(.*?)</pre>') { [Net.WebUtility]::HtmlDecode($matches[1]) | ConvertFrom-Json }
    Check 'page self-test ran' ($null -ne $st)
    $o = $st.applyUndo.r; $b = @($st.applyUndo.bodies)
    $u = @(if ($b.Count -eq 2) { $b[1] })
    Check 'Apply then Undo sends the original rects, one window' ($b.Count -eq 2 -and $b[0][0].x -eq $o.x + 100 -and $u.Count -eq 1 -and $u[0].id -eq $o.id -and $u[0].x -eq $o.x -and $u[0].y -eq $o.y -and $u[0].w -eq $o.w -and $u[0].h -eq $o.h) ('n=' + $b.Count + ' u=' + $u.Count + ' ' + ($o | ConvertTo-Json -Compress) + ' ' + (($b | % { @($_)[0] } | Select-Object id, x, y, w, h) | ConvertTo-Json -Compress))
    Check 'Undo with no Apply sends nothing' ((N $st.undoNoApply.bodies) -eq 0)
    Check 'Undo of a drag made after Apply sends nothing more' ((N $st.undoDragAfterApply.bodies) -eq 1)
    Check 'Undo after Refresh sends nothing more' ((N $st.undoAfterRefresh.bodies) -eq 1)
    $bz = $st.busy.r
    Check 'Undo, Refresh and moves are off while Apply runs' ($bz.undoOff -and $bz.refreshOff -and $bz.kept) ($bz | ConvertTo-Json -Compress)
  }

  [void](Invoke-WebRequest -UseBasicParsing "${url}quit" -Method Post -Body 'quit')
  Check 'server exits on /quit' ($srv.WaitForExit(5000))

  # 6. -Default -DryRun prints the same as main's tile.ps1 (run back to back; windows can change between runs).
  $main = Join-Path $tmp 'tile-main.ps1'
  $src = & git -C $root show main:tile.ps1; if ($LASTEXITCODE) { $src = & git -C $root show origin/main:tile.ps1 }
  Set-Content -LiteralPath $main -Encoding ASCII -Value $src
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
  if ($srv -and -not $srv.HasExited) { $srv.Kill() }
  Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
}
if ($script:fail) { "$($script:fail) check(s) failed."; exit 1 } else { 'All checks passed.' }
