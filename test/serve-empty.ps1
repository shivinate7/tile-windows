# Checks for serve.ps1 when the engine gives no output. POST scene and POST apply must answer 500 with a body, as POST preview
# does (serve.ps1, since PR 63), never a 200 with an empty body. The board reads each reply as JSON, so an empty 200 shows as a JSON parse error
# in the results line under Undo and Apply; a 500 shows the server's text.
# Run alone: powershell -NoProfile -ExecutionPolicy Bypass -File test\serve-empty.ps1
#
# No real input makes tile.ps1 give no output, so these cases run serve.ps1 from a scratch copy of the root files whose tile.ps1 is a stand-in
# engine that is silent: it fails without throwing, which is the one way the debt says the engine gives no output. Nothing here moves a window:
# the stand-in moves none, and the real-engine controls are dry runs (a -From server, and no app the apply names is open).
# Cases (red = fails on c921613 for the named cause, green = a control that holds there and must keep holding):
#   Scope (green): the scratch serve.ps1 is the repo's; the stand-in prints nothing for a scene run; the dry stub server answers the snapshot.
#   Controls (green): POST preview on the silent engine answers 500 with a body (the route PR 63 fixed). On the real engine, POST scene answers
#     200 with placed windows and POST apply answers 200 with a JSON array: the fix must not turn every answer into a 500.
#   Live server (the board's normal mode), silent engine: POST scene and POST apply answer 500 (red), each answer has a body (red), and the failed
#     scene run is not logged as having moved windows (red: it logs "Moved 0 window(s)").
#   Dry server (-From, the board's Preview mode), silent engine: POST scene and POST apply answer 500 (red).
#   Page (headless Edge, red): the page, on the dry stub server, shows a failure line that names no JSON parse error after Undo (apply route) and
#     after Apply (scene route). The line is plain: "<Undo|Apply> failed: " then the server's text. Skipped, and counted, when Edge is absent.
# The 500 body's format is not pinned: the debt (text, as POST preview) and the brief (a JSON error body) differ, so a case asks only for a body,
# and the page cases ask only that the line shows no JSON parse error and no raw braces.
# Copied on purpose: Start-Child, Stop-Server, the error-body reader and the Edge launch repeat helpers of setup-plumbing.ps1 and run.ps1. Both run
# their checks at the top level, so neither can be dot-sourced (as safe-moves.ps1 says of fresh-screens.ps1's Invoke-PsChild).
param()
$ErrorActionPreference = 'Stop'
# A direct run gets a job of its own, so a hard kill of the file also ends its Edge and servers (test\direct-run-job.ps1).
. (Join-Path $PSScriptRoot 'direct-run-job.ps1')
Enter-DirectRunJob
$root = Split-Path $PSScriptRoot
$fixture = Join-Path $PSScriptRoot 'fixture.json'
$utf8 = New-Object Text.UTF8Encoding $false
$script:fail = 0
function Check($name, $ok, $detail = '') { if ($ok) { "PASS  $name" } else { $script:fail++; "FAIL  $name  $detail" } }
# One case. An error inside it is one FAIL line, and the run goes on.
function Case([string]$name, [scriptblock]$body) { try { & $body } catch { $script:fail++; "FAIL  $name  threw: $($_.Exception.Message)" } }

# Run folder (test-temp-standard): <TEMP>\tile-windows-test-runs\<pid>-<UUID>, removed at the end. The sweep of old run folders is stack-lock.ps1's.
. (Join-Path $PSScriptRoot 'run-folders.ps1')
$runRoot = Join-Path $env:TEMP 'tile-windows-test-runs'
New-Item -ItemType Directory -Force $runRoot | Out-Null
$runDir = Join-Path $runRoot ("$PID-" + [guid]::NewGuid().ToString())
New-Item -ItemType Directory $runDir | Out-Null

# Strip what the code under test reads from the caller, and point the profile into the run folder.
$saved = @{ USERPROFILE = $env:USERPROFILE; APPDATA = $env:APPDATA; TILE_HOME = $env:TILE_HOME; TILE_SCREENS_FILE = $env:TILE_SCREENS_FILE; TILE_TEST_ALLOW_LIVE = $env:TILE_TEST_ALLOW_LIVE; CLAUDECODE = $env:CLAUDECODE }
$prof = Join-Path $runDir 'profile'; New-Item -ItemType Directory -Force (Join-Path $prof 'AppData\Roaming') | Out-Null
$env:USERPROFILE = $prof; $env:APPDATA = Join-Path $prof 'AppData\Roaming'
$env:TILE_HOME = $null; $env:TILE_SCREENS_FILE = $null; $env:TILE_TEST_ALLOW_LIVE = $null; $env:CLAUDECODE = $null
$procs = @()   # every process this file starts; the finally block stops what is still running

# A child powershell with the profile and home in the run folder. The caller's seams are blank in it, whatever the caller's shell holds.
function Start-Child([string]$tileHome, [string]$argLine) {
  $psi = New-Object Diagnostics.ProcessStartInfo 'powershell', "-NoProfile -ExecutionPolicy Bypass $argLine"
  $psi.UseShellExecute = $false; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true; $psi.CreateNoWindow = $true
  $psi.EnvironmentVariables['USERPROFILE'] = $prof; $psi.EnvironmentVariables['APPDATA'] = Join-Path $prof 'AppData\Roaming'
  $psi.EnvironmentVariables['TILE_HOME'] = $tileHome
  foreach ($k in 'TILE_SCREENS_FILE', 'TILE_TEST_ALLOW_LIVE', 'CLAUDECODE') { $psi.EnvironmentVariables[$k] = '' }
  $psi.EnvironmentVariables['TILE_TEST_SUITE'] = '1'   # the live-move guard is on, as in the suite: a live run of the real engine would be refused
  $p = [Diagnostics.Process]::Start($psi)
  $script:procs += $p
  $p
}
# A server on $serveFile: its process and tokened URL (its first line). -From makes it a dry run on that snapshot; with none it is live.
function Start-Server([string]$serveFile, [string]$tileHome, [string]$from = '') {
  $p = Start-Child $tileHome ("-File `"$serveFile`" -NoBrowser" + $(if ($from) { " -From `"$from`"" } else { '' }))
  $line = $p.StandardOutput.ReadLineAsync()
  if (-not $line.Wait(60000)) { $p.Kill(); throw "the server on $serveFile printed no URL in 60 s" }
  [pscustomobject]@{ proc = $p; url = $line.Result }
}
function Stop-Server($s) {
  if ($s.proc.HasExited) { return }
  try { [void](Invoke-WebRequest -UseBasicParsing "$($s.url)quit" -Method Post -Body 'quit') } catch {}
  if (-not $s.proc.WaitForExit(5000)) { $s.proc.Kill() }
}
# A reply: its status and its text. An error status gives its text too, so a case reads a 500's body.
function Read-Reply($call) {
  try { $r = & $call; [pscustomobject]@{ code = [int]$r.StatusCode; text = [string]$r.Content } }
  catch {
    $er = $_.Exception.Response
    if ($null -eq $er) { return [pscustomobject]@{ code = 0; text = "$($_.Exception.Message)" } }
    # Windows PowerShell has read the error answer's stream already; its text is in ErrorDetails.
    $text = if ($_.ErrorDetails -and $_.ErrorDetails.Message) { [string]$_.ErrorDetails.Message } else { $sr = New-Object IO.StreamReader($er.GetResponseStream(), $utf8); $sr.ReadToEnd() }
    $er.Close()
    [pscustomobject]@{ code = [int]$er.StatusCode; text = $text }
  }
}
function Send-Post([string]$url, [string]$body) {
  Read-Reply { Invoke-WebRequest -UseBasicParsing $url -Method Post -ContentType 'application/json; charset=utf-8' -Body ($utf8.GetBytes($body)) }
}
function Get-Reply([string]$url) { Read-Reply { Invoke-WebRequest -UseBasicParsing $url } }
function Short($s) { $t = "$s".Trim(); $t.Substring(0, [Math]::Min(120, $t.Length)) }

# The bodies the board sends: a scene, and the windows Undo puts back. The apply names no app that is open, so on the real engine it moves nothing.
$sceneBody = '{"id":"x","name":"X","grids":{"wide":{"c":2,"r":1}},"pins":[],"fill":{"mon":"wide","apps":["claude"],"skip":[],"sort":"app"}}'
$applyBody = '[{"app":"tile-test-no-such-app","title":"t","x":0,"y":0,"w":10,"h":10}]'
$edge = @("${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe", "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe") | ? { Test-Path -LiteralPath $_ } | Select-Object -First 1

try {
  # The scratch tree: the root files, with tile.ps1 swapped for an engine that is silent. serve.ps1 finds its engine, config and page beside itself.
  $tree = Join-Path $runDir 'tree'; New-Item -ItemType Directory $tree | Out-Null
  Get-ChildItem -LiteralPath $root -File | Copy-Item -Destination $tree
  [IO.File]::WriteAllText((Join-Path $tree 'tile.ps1'), "# Stand-in engine: it fails without throwing, so it gives no output for any call.`r`n", $utf8)
  $stubServe = Join-Path $tree 'serve.ps1'

  Case 'scope: the scratch serve.ps1 is the repo serve.ps1' {
    Check 'scope: the scratch serve.ps1 is the repo serve.ps1' ((Get-FileHash -LiteralPath $stubServe).Hash -eq (Get-FileHash -LiteralPath (Join-Path $root 'serve.ps1')).Hash) 'the copy differs from the repo file'
  }
  Case 'scope: the stand-in engine gives no output' {
    # The call serve.ps1 makes for a scene run, made the same way.
    $got = @(& (Join-Path $tree 'tile.ps1') -Scene $sceneBody -Json -DryRun:$true -From $fixture 3>$null)
    Check 'scope: the stand-in engine gives no output for a scene run' ($got.Count -eq 0) "it gave $($got.Count) value(s)"
  }

  $dry = Start-Server $stubServe (Join-Path $runDir 'home-dry') $fixture
  $live = Start-Server $stubServe (Join-Path $runDir 'home-live')
  $real = Start-Server (Join-Path $root 'serve.ps1') (Join-Path $runDir 'home-real') $fixture

  Case 'scope: the dry stub server answers the snapshot' {
    $r = Get-Reply "$($dry.url)snapshot"
    Check 'scope: the dry stub server answers the snapshot' ($r.code -eq 200 -and $r.text -match '"monitors"') "status $($r.code): $(Short $r.text)"
  }

  # Controls: the preview route (fixed in PR 63) and the real engine.
  Case 'control: preview' {
    $r = Send-Post "$($dry.url)preview" $sceneBody
    Check 'control: POST preview on a silent engine answers 500 with a body' ($r.code -eq 500 -and $r.text.Trim()) "status $($r.code), body '$(Short $r.text)'"
  }
  Case 'control: real engine' {
    $r = Send-Post "$($real.url)scene" $sceneBody
    $j = try { ConvertFrom-Json $r.text } catch { $null }
    Check 'control: POST scene on the real engine answers 200 with placed windows' ($r.code -eq 200 -and @($j.placed).Count -ge 1) "status $($r.code): $(Short $r.text)"
    $r = Send-Post "$($real.url)apply" $applyBody
    $j = try { ConvertFrom-Json $r.text } catch { $null }
    Check 'control: POST apply on the real engine answers 200 with a JSON array' ($r.code -eq 200 -and @($j).Count -eq 1) "status $($r.code): $(Short $r.text)"
  }

  # Subject, live server (the board's normal mode).
  Case 'live server: scene' {
    $r = Send-Post "$($live.url)scene" $sceneBody
    Check 'live server, silent engine: POST scene answers 500' ($r.code -eq 500) "status $($r.code), body '$(Short $r.text)'"
    Check 'live server, silent engine: the POST scene answer has a body' ([bool]$r.text.Trim()) "status $($r.code), body '$(Short $r.text)'"
  }
  Case 'live server: apply' {
    $r = Send-Post "$($live.url)apply" $applyBody
    Check 'live server, silent engine: POST apply answers 500' ($r.code -eq 500) "status $($r.code), body '$(Short $r.text)'"
    Check 'live server, silent engine: the POST apply answer has a body' ([bool]$r.text.Trim()) "status $($r.code), body '$(Short $r.text)'"
  }
  Case 'live server: log' {
    # The scene run above wrote the log if the route logs a run. Scope first: the state answers, with a log list.
    $r = Get-Reply "$($live.url)state"
    $st = try { ConvertFrom-Json $r.text } catch { $null }
    Check 'scope: the live stub server answers its state with a log list' ($r.code -eq 200 -and $null -ne $st -and $null -ne $st.PSObject.Properties['log']) "status $($r.code): $(Short $r.text)"
    $moved = @(@($st.log) | ? { $_.x -match 'applied from the app\. Moved \d+ window' })
    Check 'live server, silent engine: a failed scene run is not logged as having moved windows' ($moved.Count -eq 0) "logged: $(@($moved | % { $_.x }) -join ' | ')"
  }

  # Subject, dry server (-From, the board's Preview mode).
  Case 'dry server' {
    $r = Send-Post "$($dry.url)scene" $sceneBody
    Check 'dry server, silent engine: POST scene answers 500' ($r.code -eq 500) "status $($r.code), body '$(Short $r.text)'"
    $r = Send-Post "$($dry.url)apply" $applyBody
    Check 'dry server, silent engine: POST apply answers 500' ($r.code -eq 500) "status $($r.code), body '$(Short $r.text)'"
  }

  # Page: headless Edge on the dry stub server, behind preview-proxy.ps1, which puts test\serve-empty-driver.js in the page.
  if (-not $edge) {
    "SKIP  serve-empty: 3 page checks skipped (no Microsoft Edge)"
  } else {
    Case 'page' {
      $proxy = Start-Child '' ("-File `"$(Join-Path $PSScriptRoot 'preview-proxy.ps1')`" -Target `"$($dry.url)`" -Driver `"$(Join-Path $PSScriptRoot 'serve-empty-driver.js')`"")
      $purl = $proxy.StandardOutput.ReadLine()
      $dom = Join-Path $runDir 'dom-emptyreply.html'; $ep = Join-Path $runDir 'edge-emptyreply'
      # Font hosts fail fast (a pending font fetch can stall virtual time); a hung Edge is killed, not waited on.
      $e = Start-Process $edge -PassThru -WindowStyle Hidden -RedirectStandardOutput $dom -RedirectStandardError (Join-Path $runDir 'edge-emptyreply.log') -ArgumentList '--headless', '--disable-gpu', '--no-first-run', "--user-data-dir=$ep", '--host-resolver-rules="MAP fonts.googleapis.com 0.0.0.0, MAP fonts.gstatic.com 0.0.0.0"', '--virtual-time-budget=90000', '--dump-dom', "${purl}#selftest-emptyreply"
      # The kill matches this run's own profile folder only, so a hung page never takes down another file's Edge.
      if (-not $e.WaitForExit(120000)) { Get-CimInstance Win32_Process -Filter "Name='msedge.exe'" | ? { $_.CommandLine -like "*$ep*" } | % { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue } }
      $res = $null
      if ((Get-Content -Raw -Encoding UTF8 $dom) -match '<pre id="selftest">(.*?)</pre>') { $res = [Net.WebUtility]::HtmlDecode($matches[1]) | ConvertFrom-Json }
      # Scope first: the page loaded, and each route answered the page (a status came back).
      Check 'scope: the page loaded and each route answered it' ($null -ne $res -and $res.loaded -and $res.undo.status -gt 0 -and $res.apply.status -gt 0) "page: $(if ($null -eq $res) { 'no answer' } else { ConvertTo-Json -Compress -Depth 4 $res })"
      if ($null -ne $res) {
        # A plain line: the prefix, then text with no JSON parse error and no raw braces.
        function Test-PlainLine([string]$line, [string]$prefix) { $line.StartsWith($prefix) -and $line.Substring($prefix.Length).Trim() -and $line -notmatch 'JSON|Unexpected|parse|[{}]' }
        Check 'page: Undo with no engine answer shows a plain failure line' (Test-PlainLine $res.undo.line 'Undo failed: ') "reply $($res.undo.status) '$(Short $res.undo.body)'; line: '$($res.undo.line)'"
        Check 'page: Apply with no engine answer shows a plain failure line' (Test-PlainLine $res.apply.line 'Apply failed: ') "reply $($res.apply.status) '$(Short $res.apply.body)'; line: '$($res.apply.line)'"
      }
    }
  }
} catch {
  $script:fail++; "FAIL  run stopped: $_"
} finally {
  foreach ($s in @($dry, $live, $real)) { if ($s) { Stop-Server $s } }
  foreach ($p in $procs) { if (-not $p.HasExited) { $p.Kill() } }
  foreach ($k in $saved.Keys) { if ($null -eq $saved[$k]) { Remove-Item "env:$k" -ErrorAction SilentlyContinue } else { Set-Item "env:$k" $saved[$k] } }
  try { Remove-RunFolder $runDir } catch { Remove-Item -LiteralPath $runDir -Recurse -Force -ErrorAction SilentlyContinue }
}
if ($script:fail) { "$($script:fail) check(s) failed."; exit 1 } else { 'All serve-empty checks passed.'; exit 0 }
